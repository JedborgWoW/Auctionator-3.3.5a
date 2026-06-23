-- Resolve inherited mixin/OnLoad chains into each frame's OWN OnLoad.
--
-- On the target 3.3.5a client, a template's <OnLoad> is NOT reliably run for a
-- frame that inherits it (especially when the inheriting frame has its own
-- <Scripts>), and inherit="append" does not fix it. Since the backport applies
-- mixins inside <OnLoad>, inherited mixins were never applied
-- ("attempt to call method 'X' (a nil value)").
--
-- This post-pass makes mixin application independent of OnLoad inheritance:
--   PASS 1 builds registry[name] = { body = <that template's own OnLoad body>,
--          parent = <its inherits= tokens> } from ALL xml (incl. WotLKCompat).
--   PASS 2 rewrites every frame in the addon dirs so its OnLoad = the full
--          resolved chain (root template -> ... -> own body), as a PLAIN OnLoad
--          (no inherit=), creating one if the frame had none. Nothing then
--          depends on the client running inherited OnLoads.
--
-- Usage: lua resolve_mixins.lua <registry-list> <rewrite-list>

local CONTENT = {}
for _, n in ipairs({
  "Ui","Include","Script","Scripts","KeyValues","KeyValue","Size","AbsDimension",
  "Anchors","Anchor","Offset","Dimension","Layers","Layer","Texture","MaskTexture",
  "Line","FontString","Color","Shadow","TexCoords","Gradient","MinColor","MaxColor",
  "Animations","AnimationGroup","Alpha","Scale","Translation","Rotation","LineScale",
  "LineTranslation","Path","ControlPoints","ControlPoint","ButtonText","PushedTextOffset",
  "NormalTexture","PushedTexture","HighlightTexture","DisabledTexture","CheckedTexture",
  "DisabledCheckedTexture","ThumbTexture","BarTexture","SwipeTexture","BlingTexture",
  "EdgeTexture","NormalText","HighlightText","DisabledText","NormalFont","HighlightFont",
  "DisabledFont","NormalColor","HighlightColor","DisabledColor","FontHeight","FontFamily",
  "Member","Fonts","Font","Frames","HitRectInsets","ResizeBounds","TitleRegion","Backdrop",
  "BackgroundInsets","EdgeSize","TileSize","BarColor","Attributes","Attribute","NineSlice",
}) do CONTENT[n] = true end

local TOKEN_RE = "<!%-%-.-%-%->" -- handled manually below

-- Manual tokenizer: yields tokens in order via callback.
local function eachToken(text, cb)
  local i, n = 1, #text
  while i <= n do
    local lt = text:find("<", i, true)
    if not lt then cb("text", text:sub(i)); break end
    if lt > i then cb("text", text:sub(i, lt - 1)) end
    if text:sub(lt, lt + 3) == "<!--" then
      local e = text:find("-->", lt, true); e = e and e + 2 or n
      cb("raw", text:sub(lt, e)); i = e + 1
    elseif text:sub(lt, lt + 8) == "<![CDATA[" then
      local e = text:find("]]>", lt, true); e = e and e + 2 or n
      cb("raw", text:sub(lt, e)); i = e + 1
    else
      local gt = text:find(">", lt, true)
      if not gt then cb("raw", text:sub(lt)); break end
      cb("tag", text:sub(lt, gt)); i = gt + 1
    end
  end
end

local function parseTag(tok)
  local inner = tok:sub(2, -2)
  local isClose = inner:sub(1, 1) == "/"
  local isSelf = (not isClose) and inner:sub(-1) == "/"
  local name, attrs
  if isClose then
    name = inner:match("^/%s*([%w_]+)")
    attrs = ""
  else
    local core = isSelf and inner:sub(1, -2) or inner
    name, attrs = core:match("^%s*([%w_]+)(.*)$")
  end
  return name, attrs or "", isClose, isSelf
end

local function isFrameTag(name)
  return not CONTENT[name] and not (name:sub(1, 2) == "On" and name:len() > 2 and name:sub(3, 3):match("%u"))
end

-- ---------------------------------------------------------------------------
-- PASS 1: registry
-- ---------------------------------------------------------------------------
local registry = {}

local function buildRegistry(path)
  local f = io.open(path, "rb"); if not f then return end
  local s = f:read("*a"); f:close()
  -- stack of {name, inherits, kind}; capture own OnLoad body of named frames
  local stack = {}
  local capturing = nil      -- frame table currently capturing its OnLoad body
  eachToken(s, function(kind, tok)
    if kind == "text" then
      if capturing then capturing.body = (capturing.body or "") .. tok end
      return
    elseif kind == "raw" then
      return
    end
    local name, attrs, isClose, isSelf = parseTag(tok)
    if isClose then
      local top = table.remove(stack)
      if top and top.kind == "frame" and top.name then
        registry[top.name] = { body = top.body or "", parent = top.inherits }
      end
      if top and top.kind == "onload" then capturing = nil end
      return
    end
    if name == "OnLoad" and not isSelf then
      -- direct child OnLoad of the nearest frame?
      local parentEl = stack[#stack]            -- should be Scripts
      local frameEl = stack[#stack - 1]
      if frameEl and frameEl.kind == "frame" then
        capturing = frameEl
        frameEl.body = ""
      end
      stack[#stack + 1] = { kind = "onload" }
      return
    end
    if isSelf then return end
    if name == "Scripts" then
      stack[#stack + 1] = { kind = "scripts" }
    elseif isFrameTag(name) then
      local nm = attrs:match('name="([^"]*)"')
      local inh = attrs:match('inherits="([^"]*)"')
      stack[#stack + 1] = { kind = "frame", name = nm, inherits = inh }
    else
      stack[#stack + 1] = { kind = "content" }
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Chain resolution
-- ---------------------------------------------------------------------------
local function resolveChain(inherits, seen)
  if not inherits then return "" end
  seen = seen or {}
  local out = {}
  for token in inherits:gmatch("[^,%s]+") do
    if registry[token] and not seen[token] then
      seen[token] = true
      local entry = registry[token]
      local parentBody = resolveChain(entry.parent, seen)
      if parentBody ~= "" then out[#out + 1] = parentBody end
      if entry.body ~= "" then out[#out + 1] = entry.body end
    end
  end
  return table.concat(out, " ")
end

-- ---------------------------------------------------------------------------
-- PASS 2: rewrite addon frames
-- ---------------------------------------------------------------------------
local stats = { onload_rewritten = 0, onload_created = 0 }

local function rewrite(path)
  local f = io.open(path, "rb"); local s = f:read("*a"); f:close()
  local out = {}
  local stack = {}
  local emit = function(x) out[#out + 1] = x end

  eachToken(s, function(kind, tok)
    if kind ~= "tag" then emit(tok); return end
    local name, attrs, isClose, isSelf = parseTag(tok)

    if isClose then
      if name == "Scripts" then
        table.remove(stack) -- scripts
        emit(tok)
        return
      end
      local top = stack[#stack]
      if top and top.kind == "frame" then
        if not top.hadOnLoad then
          local chain = resolveChain(top.inherits)
          if chain ~= "" then
            emit("<Scripts><OnLoad>" .. chain .. "</OnLoad></Scripts>")
            stats.onload_created = stats.onload_created + 1
          end
        end
        table.remove(stack)
      elseif top then
        table.remove(stack)
      end
      emit(tok)
      return
    end

    if name == "OnLoad" and not isSelf then
      local frameEl = stack[#stack - 1]
      if frameEl and frameEl.kind == "frame" then
        frameEl.hadOnLoad = true
        local chain = resolveChain(frameEl.inherits)
        emit("<OnLoad>") -- strip any inherit="append"
        if chain ~= "" then
          emit(chain .. " ")
          stats.onload_rewritten = stats.onload_rewritten + 1
        end
      else
        emit("<OnLoad>")
      end
      stack[#stack + 1] = { kind = "onload" }
      return
    end

    if isSelf then emit(tok); return end

    if name == "Scripts" then
      stack[#stack + 1] = { kind = "scripts" }
    elseif isFrameTag(name) then
      local inh = attrs:match('inherits="([^"]*)"')
      stack[#stack + 1] = { kind = "frame", inherits = inh, hadOnLoad = false }
    else
      stack[#stack + 1] = { kind = "content" }
    end
    emit(tok)
  end)

  local dst = table.concat(out)
  if dst ~= s then
    local w = io.open(path, "wb"); w:write(dst); w:close()
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
local regList, rwList = arg[1], arg[2]
for path in io.lines(regList) do
  path = path:gsub("%s+$", "")
  if #path > 0 then buildRegistry(path) end
end
local changed = 0
for path in io.lines(rwList) do
  path = path:gsub("%s+$", "")
  if #path > 0 and rewrite(path) then changed = changed + 1 end
end
local regCount = 0
for _ in pairs(registry) do regCount = regCount + 1 end
print("registry templates:", regCount, "files changed:", changed)
print("onload_rewritten:", stats.onload_rewritten, "onload_created:", stats.onload_created)
