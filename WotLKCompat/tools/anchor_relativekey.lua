-- Resolve dotted relativeKey anchors into runtime SetPoint calls.
--
-- On stock 3.3.5a the XML <Anchor relativeKey="..."> attribute is UNSUPPORTED:
-- the parser ignores it, so the anchor falls back to anchoring the owner to its
-- PARENT (point -> parent's relativePoint). For relativeKey="$parent" that happens
-- to be correct, but for relativeKey="$parent.Sibling" it is wrong -- every control
-- ends up stacked at the parent's BOTTOMLEFT (the config panels showed all widgets
-- piled on top of each other at the bottom).
--
-- Fix: for each anchor whose relativeKey contains a '.', emit an equivalent
-- self.<ownerKey>:SetPoint("POINT", <resolved ref>, "RELPOINT"[, x, y]) and inject
-- it into the OWNER's PARENT-frame OnLoad. parentKey works on 3.3.5a, so the key
-- path resolves at runtime. We inject into the PARENT frame (not the owner's own
-- OnLoad) because a frame's OnLoad runs AFTER all its children are created, so both
-- the owner child and any sibling/descendant it references already exist --
-- order-independent (handles the forward-reference anchor chains). We do NOT remove
-- the original <Anchor>: a later SetPoint for the same point simply replaces the
-- fallback anchor.
--
-- relativeKey is resolved from the OWNER, expressed in the PARENT frame (self):
--   owner.parent == self, so the leading "$parent" -> self; each further token:
--   "$parent" -> :GetParent(),  key -> .key
-- e.g. (parent frame OnLoad, owner parentKey="DefaultTab"):
--   relativeKey="$parent.TitleArea" -> self.DefaultTab:SetPoint(p, self.TitleArea, rp)
--
-- Usage: lua anchor_relativekey.lua <listfile>   (one xml path per line)

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

local REGION = { Texture=true, MaskTexture=true, FontString=true, Line=true }

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
  if not name then return false end
  return not CONTENT[name] and not REGION[name]
    and not (name:sub(1,2) == "On" and #name > 2 and name:sub(3,3):match("%u"))
end

local function trimStmt(s)
  return (s:gsub("^[%s;]+", ""):gsub("[%s;]+$", ""))
end

-- quote-aware split of an OnLoad body into statements at top-level ';'
local function splitStatements(body)
  local stmts, start, i, n = {}, 1, 1, #body
  local q = nil
  while i <= n do
    local c = body:sub(i, i)
    if q then
      if c == "\\" then i = i + 1 elseif c == q then q = nil end
    else
      if c == '"' or c == "'" then q = c
      elseif c == ";" then stmts[#stmts + 1] = body:sub(start, i - 1); start = i + 1 end
    end
    i = i + 1
  end
  if start <= n then stmts[#stmts + 1] = body:sub(start) end
  return stmts
end

local function joinBody(ownBody, pending)
  local parts = {}
  for _, s in ipairs(splitStatements(ownBody or "")) do
    local t = trimStmt(s); if t ~= "" then parts[#parts + 1] = t end
  end
  for _, s in ipairs(pending) do
    local t = trimStmt(s); if t ~= "" then parts[#parts + 1] = t end
  end
  return table.concat(parts, "; ")
end

-- Resolve a dotted relativeKey (from the owner) into a Lua expr in the PARENT
-- frame (self == owner.parent). Returns nil if it does not start with $parent.
local function resolveRef(rk)
  local tokens = {}
  for t in rk:gmatch("[^%.]+") do tokens[#tokens + 1] = t end
  if tokens[1] ~= "$parent" then return nil end
  local expr = "self"               -- owner.parent == self
  for i = 2, #tokens do
    if tokens[i] == "$parent" then expr = expr .. ":GetParent()"
    else expr = expr .. "." .. tokens[i] end
  end
  return expr
end

-- Same, but expressed in the OWNER's own OnLoad (self == owner), so the leading
-- "$parent" is the owner's parent == self:GetParent().
local function resolveRefOwn(rk)
  local tokens = {}
  for t in rk:gmatch("[^%.]+") do tokens[#tokens + 1] = t end
  if tokens[1] ~= "$parent" then return nil end
  local expr = "self:GetParent()"
  for i = 2, #tokens do
    if tokens[i] == "$parent" then expr = expr .. ":GetParent()"
    else expr = expr .. "." .. tokens[i] end
  end
  return expr
end

local stats = { setpoints = 0, files = 0, created = 0, skipped = 0 }

local function process(path)
  local f = io.open(path, "rb"); if not f then return false end
  local s = f:read("*a"); f:close()

  local out = {}
  local emit = function(x) out[#out + 1] = x end
  local stack = {}              -- element nesting: {kind, name, frame=node}
  local frames = {}             -- frame nodes (parallel to frame elements on stack)
  local repl = {}               -- placeholder -> final string
  local phid = 0
  local function newPH(kind) phid = phid + 1; return "\1" .. kind .. phid .. "\1" end

  local capturing = nil         -- frame node whose own OnLoad body we are buffering

  eachToken(s, function(kind, tok)
    if kind == "text" then
      if capturing then capturing.ownBody = (capturing.ownBody or "") .. tok else emit(tok) end
      return
    elseif kind == "raw" then
      if not capturing then emit(tok) end
      return
    end

    local name, attrs, isClose, isSelf = parseTag(tok)

    -- ANCHOR with dotted relativeKey -> queue a SetPoint on the parent frame
    if name == "Anchor" and not isClose then
      local rk = attrs:match('relativeKey="([^"]*)"')
      if rk and rk:find(".", 1, true) and rk ~= "$parent" then
        -- owner = nearest frame/region element; host = nearest frame above owner
        local owner, host
        for j = #stack, 1, -1 do
          local e = stack[j]
          if (e.kind == "frame" or e.kind == "region") and not owner then owner = e
          elseif e.kind == "frame" and owner and e ~= owner then host = e; break end
        end
        local point = attrs:match('point="([^"]*)"')
        local rel = attrs:match('relativePoint="([^"]*)"') or point
        local x = attrs:match('[^%w]x="([%-%.%w]+)"')
        local y = attrs:match('[^%w]y="([%-%.%w]+)"')
        local function mkstmt(ownerExpr, refExpr)
          if x or y then
            return string.format('%s:SetPoint("%s", %s, "%s", %s, %s)',
              ownerExpr, point, refExpr, rel, x or "0", y or "0")
          end
          return string.format('%s:SetPoint("%s", %s, "%s")', ownerExpr, point, refExpr, rel)
        end
        if owner and owner.parentKey and host and host.node and resolveRef(rk) then
          -- preferred: inject into the PARENT frame's OnLoad (order-independent;
          -- runs after all children exist). owner.parent == self there.
          host.node.pending[#host.node.pending + 1] =
            mkstmt("self." .. owner.parentKey, resolveRef(rk))
          stats.setpoints = stats.setpoints + 1
        elseif owner and owner.kind == "frame" and owner.node and resolveRefOwn(rk) then
          -- fallback (owner has no parentKey, or is a top-level template root):
          -- inject into the owner's OWN OnLoad. self == owner there, so the
          -- leading $parent resolves to self:GetParent().
          owner.node.pending[#owner.node.pending + 1] =
            mkstmt("self", resolveRefOwn(rk))
          stats.setpoints = stats.setpoints + 1
        else
          stats.skipped = stats.skipped + 1
          io.stderr:write(("SKIP %s rk=%s owner=%s host=%s key=%s\n"):format(
            path, rk, tostring(owner and owner.name), tostring(host and host.name),
            tostring(owner and owner.parentKey)))
        end
      end
      if not capturing then emit(tok) end
      if not isSelf then stack[#stack + 1] = { kind = "anchor" } end
      return
    end

    if isClose then
      local top = stack[#stack]
      if top and top.kind == "onload" and capturing then
        -- end of the frame's own OnLoad: emit a placeholder instead of the body
        local node = capturing
        node.hasOnLoad = true
        node.onloadPH = newPH("OL")
        emit(node.onloadPH)
        emit(tok) -- </OnLoad>
        capturing = nil
        stack[#stack] = nil
        return
      end
      if top and top.kind == "frame" then
        local node = top.node
        -- finalise this frame's placeholders now that pending is complete
        if #node.pending > 0 then
          if node.hasOnLoad then
            repl[node.onloadPH] = joinBody(node.ownBody, node.pending)
            repl[node.createPH] = ""
            if node.scriptsPH then repl[node.scriptsPH] = "" end
          elseif node.scriptsPH then
            repl[node.scriptsPH] = "<OnLoad>" .. joinBody("", node.pending) .. "</OnLoad>"
            repl[node.createPH] = ""
          else
            repl[node.createPH] = "<Scripts><OnLoad>" .. joinBody("", node.pending) .. "</OnLoad></Scripts>"
            stats.created = stats.created + 1
          end
        else
          if node.onloadPH then repl[node.onloadPH] = node.ownBody or "" end
          repl[node.createPH] = ""
          if node.scriptsPH then repl[node.scriptsPH] = "" end
        end
        emit(tok)
        stack[#stack] = nil
        return
      end
      if top then stack[#stack] = nil end
      emit(tok)
      return
    end

    -- OPEN tags
    if name == "OnLoad" and not isSelf then
      local parent = stack[#stack]
      local grand = stack[#stack - 1]
      if parent and parent.kind == "scripts" and grand and grand.kind == "frame" then
        -- the frame's OWN OnLoad: keep the <OnLoad> tags, swallow the body into
        -- ownBody and emit a placeholder for it (rebuilt with pending at close).
        capturing = grand.node
        grand.node.ownBody = ""
        emit(tok) -- <OnLoad>
        stack[#stack + 1] = { kind = "onload" }
        return
      end
      emit(tok)
      stack[#stack + 1] = { kind = "onload-other" }
      return
    end

    if isSelf then
      if not capturing then emit(tok) end
      return
    end

    if name == "Scripts" then
      emit(tok)
      local fr = stack[#stack]
      local node = (fr and fr.kind == "frame") and fr.node or nil
      stack[#stack + 1] = { kind = "scripts" }
      if node and not node.scriptsPH then
        node.scriptsPH = newPH("SC"); emit(node.scriptsPH)  -- insertion point for a new OnLoad
      end
    elseif isFrameTag(name) then
      emit(tok)
      local node = { pending = {}, parentKey = attrs:match('parentKey="([^"]*)"') }
      node.createPH = newPH("CR"); emit(node.createPH)       -- insertion point after open tag
      frames[#frames + 1] = node
      stack[#stack + 1] = { kind = "frame", name = name, node = node, parentKey = node.parentKey }
    elseif REGION[name] then
      emit(tok)
      stack[#stack + 1] = { kind = "region", name = name, parentKey = attrs:match('parentKey="([^"]*)"') }
    else
      emit(tok)
      stack[#stack + 1] = { kind = "content", name = name }
    end
  end)

  local result = table.concat(out)
  -- substitute placeholders
  result = result:gsub("\1[^\1]+\1", function(ph) return repl[ph] or "" end)

  if result ~= s then
    local w = io.open(path, "wb"); w:write(result); w:close()
    stats.files = stats.files + 1
    return true
  end
  return false
end

for path in io.lines(arg[1]) do
  path = path:gsub("%s+$", "")
  if #path > 0 then process(path) end
end
print(("files changed: %d  setpoints: %d  created-scripts: %d  skipped: %d")
  :format(stats.files, stats.setpoints, stats.created, stats.skipped))
