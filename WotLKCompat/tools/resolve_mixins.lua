-- Resolve inherited mixin/OnLoad chains into each frame's OWN OnLoad.
--
-- On the target 3.3.5a client a template's <OnLoad> is NOT reliably run for a
-- frame that inherits it, so inherited mixins were never applied. This post-pass
-- makes mixin application independent of OnLoad inheritance by writing the FULL
-- resolved chain into each frame's own (plain) OnLoad.
--
-- CRITICAL ordering (matches retail): apply ALL mixins of the inheritance chain
-- FIRST, THEN run the per-level OnLoad bodies. Auctionator relies on this — e.g.
-- AuctionatorConfigurationTooltip's OnLoad does `Mixin(TooltipMixin); self:OnLoad()`
-- but TooltipMixin has no OnLoad; the self:OnLoad() is meant to resolve to the
-- most-derived mixin's OnLoad (CheckboxMixin etc.) AFTER all mixins are applied.
-- So per-level (Mixin; method; Mixin; method) ordering breaks it -> we split each
-- template body into its Mixin part and its rest, emit all Mixins, then all rests.
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
    name = inner:match("^/%s*([%w_]+)"); attrs = ""
  else
    local core = isSelf and inner:sub(1, -2) or inner
    name, attrs = core:match("^%s*([%w_]+)(.*)$")
  end
  return name, attrs or "", isClose, isSelf
end

local function isFrameTag(name)
  return not CONTENT[name] and not (name:sub(1,2) == "On" and #name > 2 and name:sub(3,3):match("%u"))
end

-- Split an OnLoad body into its leading Mixin(self, ...) and the rest.
local function splitBody(body)
  body = body:gsub("^%s+", ""):gsub("%s+$", "")
  local mixin = body:match("^(Mixin%(self,.-%))")
  if mixin then
    local rest = body:sub(#mixin + 1):gsub("^%s*;?%s*", "")
    return mixin, rest
  end
  return "", body
end

local function trimStmt(s)
  return (s:gsub("^[%s;]+", ""):gsub("[%s;]+$", ""))
end

-- ---------------------------------------------------------------------------
-- PASS 1: registry[name] = { mixin, rest, parent }
-- ---------------------------------------------------------------------------
local registry = {}

local function buildRegistry(path)
  local f = io.open(path, "rb"); if not f then return end
  local s = f:read("*a"); f:close()
  local stack = {}
  local capturing = nil
  eachToken(s, function(kind, tok)
    if kind == "text" then
      if capturing then capturing.body = (capturing.body or "") .. tok end
      return
    elseif kind == "raw" then return end
    local name, attrs, isClose, isSelf = parseTag(tok)
    if isClose then
      local top = table.remove(stack)
      if top and top.kind == "onload" then capturing = nil end
      if top and top.kind == "frame" and top.name then
        local mixin, rest = splitBody(top.body or "")
        registry[top.name] = { mixin = mixin, rest = rest, parent = top.inherits }
      end
      return
    end
    if name == "OnLoad" and not isSelf then
      local frameEl = stack[#stack - 1]
      if frameEl and frameEl.kind == "frame" then capturing = frameEl; frameEl.body = "" end
      stack[#stack + 1] = { kind = "onload" }
      return
    end
    if isSelf then return end
    if name == "Scripts" then
      stack[#stack + 1] = { kind = "scripts" }
    elseif isFrameTag(name) then
      stack[#stack + 1] = { kind = "frame", name = attrs:match('name="([^"]*)"'), inherits = attrs:match('inherits="([^"]*)"') }
    else
      stack[#stack + 1] = { kind = "content" }
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Chain resolution: collect all Mixin parts then all rest parts (root -> self)
-- ---------------------------------------------------------------------------
local function collect(inherits, mixins, rests, seen)
  if not inherits then return end
  for token in inherits:gmatch("[^,%s]+") do
    if registry[token] and not seen[token] then
      seen[token] = true
      collect(registry[token].parent, mixins, rests, seen)
      if registry[token].mixin ~= "" then mixins[#mixins + 1] = registry[token].mixin end
      if registry[token].rest ~= "" then rests[#rests + 1] = registry[token].rest end
    end
  end
end

-- Build the resolved OnLoad body for a frame from its inherits chain + own body.
local function resolved(inherits, ownBody)
  local mixins, rests = {}, {}
  collect(inherits, mixins, rests, {})
  local ownMixin, ownRest = splitBody(ownBody or "")
  if ownMixin ~= "" then mixins[#mixins + 1] = ownMixin end
  if ownRest ~= "" then rests[#rests + 1] = ownRest end
  local parts = {}
  for _, m in ipairs(mixins) do local t = trimStmt(m); if t ~= "" then parts[#parts + 1] = t end end
  for _, r in ipairs(rests) do local t = trimStmt(r); if t ~= "" then parts[#parts + 1] = t end end
  return table.concat(parts, "; ")
end

-- ---------------------------------------------------------------------------
-- PASS 2: rewrite addon frames
-- ---------------------------------------------------------------------------
local stats = { rewritten = 0, created = 0 }

local function rewrite(path)
  local f = io.open(path, "rb"); local s = f:read("*a"); f:close()
  local out = {}
  local stack = {}
  local capture = nil  -- {frame=..., buf=""} while inside a frame's own OnLoad
  local emit = function(x) out[#out + 1] = x end

  eachToken(s, function(kind, tok)
    if kind ~= "tag" then
      if capture then capture.buf = capture.buf .. tok else emit(tok) end
      return
    end
    local name, attrs, isClose, isSelf = parseTag(tok)

    if isClose then
      if name == "OnLoad" and capture then
        local body = resolved(capture.frame.inherits, capture.buf)
        emit("<OnLoad>" .. body .. "</OnLoad>")
        capture.frame.hadOnLoad = true
        capture = nil
        table.remove(stack) -- onload
        stats.rewritten = stats.rewritten + 1
        return
      end
      if name == "Scripts" then table.remove(stack); emit(tok); return end
      local top = stack[#stack]
      if top and top.kind == "frame" then
        if not top.hadOnLoad then
          local body = resolved(top.inherits, "")
          if body ~= "" then
            emit("<Scripts><OnLoad>" .. body .. "</OnLoad></Scripts>")
            stats.created = stats.created + 1
          end
        end
      end
      if top then table.remove(stack) end
      emit(tok)
      return
    end

    if name == "OnLoad" and not isSelf then
      local frameEl = stack[#stack - 1]
      if frameEl and frameEl.kind == "frame" then
        capture = { frame = frameEl, buf = "" }   -- swallow body; rebuild at close
        stack[#stack + 1] = { kind = "onload" }
        return                                    -- do NOT emit the <OnLoad...> tag
      end
      emit(tok)
      stack[#stack + 1] = { kind = "onload" }
      return
    end

    if isSelf then if capture then capture.buf = capture.buf .. tok else emit(tok) end; return end

    if name == "Scripts" then
      stack[#stack + 1] = { kind = "scripts" }
    elseif isFrameTag(name) then
      stack[#stack + 1] = { kind = "frame", inherits = attrs:match('inherits="([^"]*)"'), hadOnLoad = false }
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

local regList, rwList = arg[1], arg[2]
for path in io.lines(regList) do path = path:gsub("%s+$", ""); if #path > 0 then buildRegistry(path) end end
local changed = 0
for path in io.lines(rwList) do path = path:gsub("%s+$", ""); if #path > 0 and rewrite(path) then changed = changed + 1 end end
local rc = 0; for _ in pairs(registry) do rc = rc + 1 end
print("registry:", rc, "files changed:", changed, "rewritten:", stats.rewritten, "created:", stats.created)
