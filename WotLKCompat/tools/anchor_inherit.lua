-- Propagate a template's anchor SetPoints down its inheritance chain.
--
-- anchor_relativekey.lua injects SetPoint() calls into the OnLoad of the template
-- that DEFINES the anchored children. But on 3.3.5a a frame that has its own
-- <Scripts> does NOT run an inherited template's <OnLoad> (this is why
-- resolve_mixins flattens mixin chains into each frame's own OnLoad). Because the
-- anchor pass ran AFTER resolve_mixins, those SetPoints were never propagated into
-- inheriting templates -> e.g. AuctionatorConfigShoppingAltFrameTemplate inherits
-- AuctionatorConfigShoppingFrameTemplate but only runs its OWN OnLoad, so the
-- parent's option SetPoints never execute and the parent's controls pile up.
--
-- This pass appends each addon-template ancestor's OWN SetPoint statements to a
-- template's own OnLoad. The ancestor's children are inherited (self.X resolves),
-- and a frame's OnLoad runs after all children exist, so it stays correct.
--
-- Usage: lua anchor_inherit.lua <registry-list> <rewrite-list>

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
  if isClose then name = inner:match("^/%s*([%w_]+)"); attrs = ""
  else local core = isSelf and inner:sub(1, -2) or inner; name, attrs = core:match("^%s*([%w_]+)(.*)$") end
  return name, attrs or "", isClose, isSelf
end

local CONTENT = { Scripts=true, KeyValues=true, KeyValue=true, Anchors=true, Anchor=true,
  Layers=true, Layer=true, Frames=true, Size=true, AbsDimension=true }
local REGION = { Texture=true, MaskTexture=true, FontString=true, Line=true }
local function isFrameTag(name)
  return name and not CONTENT[name] and not REGION[name]
    and not (name:sub(1,2) == "On" and #name > 2 and name:sub(3,3):match("%u"))
    and name ~= "Ui" and name ~= "Include" and name ~= "Script"
end

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
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- ---------------------------------------------------------------------------
-- PASS 1: registry[name] = { setpoints = {stmt,...}, parents = {token,...} }
-- ---------------------------------------------------------------------------
local registry = {}

local function buildRegistry(path)
  local f = io.open(path, "rb"); if not f then return end
  local s = f:read("*a"); f:close()
  local stack = {}
  local capturing = nil  -- named-frame node whose own OnLoad body we collect
  eachToken(s, function(kind, tok)
    if kind == "text" then
      if capturing then capturing.body = (capturing.body or "") .. tok end
      return
    elseif kind == "raw" then return end
    local name, attrs, isClose, isSelf = parseTag(tok)
    if isClose then
      local top = table.remove(stack)
      if top and top.kind == "onload" then capturing = nil end
      return
    end
    if name == "OnLoad" and not isSelf then
      local parent = stack[#stack]
      local grand = stack[#stack - 1]
      if parent and parent.kind == "scripts" and grand and grand.kind == "frame" and grand.name then
        capturing = grand; grand.body = ""
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
      local node = { kind = "frame", name = nm }
      stack[#stack + 1] = node
      if nm then
        local parents = {}
        if inh then for t in inh:gmatch("[^,%s]+") do parents[#parents + 1] = t end end
        registry[nm] = { parents = parents, setpoints = {}, _node = node }
      end
    else
      stack[#stack + 1] = { kind = "content" }
    end
  end)
  -- extract setpoints from each captured body
  for nm, rec in pairs(registry) do
    if rec._node and rec._node.body and #rec.setpoints == 0 then
      for _, st in ipairs(splitStatements(rec._node.body)) do
        local t = trim(st)
        if t:find(":SetPoint%(") then rec.setpoints[#rec.setpoints + 1] = t end
      end
      rec._node = nil
    end
  end
end

-- collect ancestors' own setpoints (root -> nearest), de-duplicated
local function ancestorSetpoints(name, seen, acc, present)
  local rec = registry[name]
  if not rec then return end
  for _, p in ipairs(rec.parents) do
    if registry[p] and not seen[p] then
      seen[p] = true
      ancestorSetpoints(p, seen, acc, present)
      for _, st in ipairs(registry[p].setpoints) do
        if not present[st] then present[st] = true; acc[#acc + 1] = st end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- PASS 2: append ancestor setpoints to each template's own OnLoad
-- ---------------------------------------------------------------------------
local stats = { files = 0, appended = 0 }

-- Collect setpoints for a frame from its inherits= chain: each inherited template's
-- ancestors' setpoints, then the template's own. Covers anonymous inline instances
-- (e.g. DefaultStacks inheriting AuctionatorStackOfInputTemplate) whose own OnLoad
-- (from KeyValues/mixin) shadows the inherited template's SetPoint-bearing OnLoad.
local function ancestorSetpointsFromInherits(inheritsStr, acc, present)
  if not inheritsStr then return end
  local seen = {}
  for token in inheritsStr:gmatch("[^,%s]+") do
    if registry[token] and not seen[token] then
      seen[token] = true
      ancestorSetpoints(token, seen, acc, present)        -- token's ancestors
      for _, st in ipairs(registry[token].setpoints) do   -- token's own
        if not present[st] then present[st] = true; acc[#acc + 1] = st end
      end
    end
  end
end

local function inheritsHaveSetpoints(inheritsStr)
  local acc = {}
  ancestorSetpointsFromInherits(inheritsStr, acc, {})
  return #acc > 0
end

local function rewrite(path)
  local f = io.open(path, "rb"); local s = f:read("*a"); f:close()
  local out = {}
  local emit = function(x) out[#out + 1] = x end
  local stack = {}
  local capture = nil  -- { node=, buf="" } inside a named frame's own OnLoad
  eachToken(s, function(kind, tok)
    if kind ~= "tag" then
      if capture then capture.buf = capture.buf .. tok else emit(tok) end
      return
    end
    local name, attrs, isClose, isSelf = parseTag(tok)
    if isClose then
      if name == "OnLoad" and capture then
        local node = capture.node
        local present = {}
        for _, st in ipairs(splitStatements(capture.buf)) do present[trim(st)] = true end
        local acc = {}
        ancestorSetpointsFromInherits(node.inherits, acc, present)
        local body = capture.buf
        if #acc > 0 then
          body = trim(body)
          if body ~= "" and not body:find(";%s*$") then body = body .. "; " end
          body = body .. table.concat(acc, "; ")
          stats.appended = stats.appended + #acc
        end
        emit("<OnLoad>" .. body .. "</OnLoad>")
        capture = nil
        table.remove(stack)
        return
      end
      if name then table.remove(stack) end
      emit(tok)
      return
    end
    if name == "OnLoad" and not isSelf then
      local parent = stack[#stack]
      local grand = stack[#stack - 1]
      if parent and parent.kind == "scripts" and grand and grand.kind == "frame"
         and grand.inherits and inheritsHaveSetpoints(grand.inherits) then
        capture = { node = grand, buf = "" }
        stack[#stack + 1] = { kind = "onload" }
        return  -- swallow <OnLoad> tag; rebuilt at close
      end
      emit(tok)
      stack[#stack + 1] = { kind = "onload" }
      return
    end
    if isSelf then if capture then capture.buf = capture.buf .. tok else emit(tok) end; return end
    if name == "Scripts" then stack[#stack + 1] = { kind = "scripts" }
    elseif isFrameTag(name) then stack[#stack + 1] = { kind = "frame", name = attrs:match('name="([^"]*)"'), inherits = attrs:match('inherits="([^"]*)"') }
    else stack[#stack + 1] = { kind = "content" } end
    emit(tok)
  end)
  local result = table.concat(out)
  if result ~= s then
    local w = io.open(path, "wb"); w:write(result); w:close()
    stats.files = stats.files + 1
  end
end

local regList, rwList = arg[1], arg[2]
for path in io.lines(regList) do path = path:gsub("%s+$", ""); if #path > 0 then buildRegistry(path) end end
for path in io.lines(rwList) do path = path:gsub("%s+$", ""); if #path > 0 then rewrite(path) end end
print(("files changed: %d  setpoints appended: %d"):format(stats.files, stats.appended))
