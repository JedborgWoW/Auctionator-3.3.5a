-- detect_self_anchor.lua
-- Scans transformed XML for injected OnLoad SetPoint calls that anchor a frame
-- to itself at RUNTIME (textually distinct expressions that resolve to the same
-- frame). Catches the "trying to anchor to itself" class of bug.
--
-- Detected patterns (owner == relativeTo after parentKey resolution):
--   1. OWNER:SetPoint("PT", OWNER, ...)                 -- textual self
--   2. self:SetPoint("PT", self:GetParent().<K>, ...)    where this frame's
--                                                         own parentKey == K
--   3. self.A:SetPoint("PT", self.A, ...)                -- textual (==1 form)
--
-- Usage: lua detect_self_anchor.lua <root-dir> [root-dir ...]

local function read(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

-- crude recursive file walk using `dir` (Windows) via io.popen
local function listFiles(root)
  local out = {}
  local p = io.popen('cmd /c dir /b /s /a-d "' .. root .. '\\*.xml" 2>nul')
  if p then
    for line in p:lines() do out[#out+1] = line end
    p:close()
  end
  return out
end

-- Extract the attribute value of `attr` from an opening-tag string.
local function attrOf(tag, attr)
  return tag:match(attr .. '%s*=%s*"([^"]*)"')
end

-- Walk a file, maintaining a stack of frames (open tag -> close tag), and for
-- each <OnLoad> body associate it with the nearest enclosing frame, recording
-- that frame's parentKey/name.
local FRAME_TAGS = {
  Frame=true, Button=true, EditBox=true, ScrollFrame=true, Slider=true,
  CheckButton=true, StatusBar=true, ModelFFX=true, Cooldown=true,
  Model=true, MessageFrame=true, SimpleHTML=true, ColorSelect=true,
  GameTooltip=true, Minimap=true, MovieFrame=true, ScrollingMessageFrame=true,
  PlayerModel=true, DressUpModel=true, TabardModel=true, Browser=true,
}

local findings = {}

local function scanFile(path)
  local src = read(path)
  if not src then return end

  -- Tokenize tags. We only care about frame open/close tags and OnLoad bodies.
  local stack = {}  -- each: {tag=, parentKey=, name=}
  local pos = 1
  local len = #src
  while pos <= len do
    local s, e, inner = src:find("<(/?%w[%w]*)", pos)
    if not s then break end
    local tagName = inner
    if tagName:sub(1,1) == "/" then
      -- closing tag
      local closeName = tagName:sub(2)
      if FRAME_TAGS[closeName] then
        -- pop nearest matching frame
        for i = #stack, 1, -1 do
          if stack[i].tag == closeName then
            table.remove(stack, i)
            break
          end
        end
      end
      pos = e + 1
    else
      -- opening tag: capture full tag text up to '>'
      local tagEnd = src:find(">", e)
      if not tagEnd then break end
      local tagText = src:sub(s, tagEnd)
      local selfClosing = tagText:sub(-2) == "/>"

      if tagName == "OnLoad" then
        -- read body up to </OnLoad>
        if not selfClosing then
          local bodyStart = tagEnd + 1
          local bodyEnd = src:find("</OnLoad>", bodyStart, true)
          local body = bodyEnd and src:sub(bodyStart, bodyEnd - 1) or ""
          local owner = stack[#stack]
          local pk = owner and owner.parentKey
          local nm = owner and owner.name
          -- pattern 1/3: textual owner == relativeTo
          for o, rel in body:gmatch("([%w_%.:%(%)]-):SetPoint%(%s*\"[^\"]*\"%s*,%s*([%w_%.:%(%)]+)") do
            local oTrim = o:gsub("^%s+",""):gsub("%s+$","")
            if oTrim ~= "" and oTrim == rel then
              findings[#findings+1] = string.format(
                "[TEXTUAL] %s\n    frame(parentKey=%s name=%s)\n    %s:SetPoint(..., %s)",
                path, tostring(pk), tostring(nm), oTrim, rel)
            end
          end
          -- pattern 2: self:SetPoint("PT", self:GetParent().<K>, ...) with parentKey==K
          if pk then
            for ptarget in body:gmatch("self:SetPoint%(%s*\"[^\"]*\"%s*,%s*self:GetParent%(%)%.([%w_]+)%s*[,%)]") do
              if ptarget == pk then
                findings[#findings+1] = string.format(
                  "[SELF-VIA-PARENT] %s\n    frame(parentKey=%s name=%s)\n    self:SetPoint(..., self:GetParent().%s)  -- parent.%s == self",
                  path, tostring(pk), tostring(nm), ptarget, ptarget)
              end
            end
          end
        end
        pos = tagEnd + 1
      elseif FRAME_TAGS[tagName] then
        local frame = {
          tag = tagName,
          parentKey = attrOf(tagText, "parentKey"),
          name = attrOf(tagText, "name"),
        }
        if not selfClosing then
          stack[#stack+1] = frame
        end
        pos = tagEnd + 1
      else
        pos = tagEnd + 1
      end
    end
  end
end

local roots = {...}
if #roots == 0 then
  io.stderr:write("usage: lua detect_self_anchor.lua <root-dir> ...\n")
  os.exit(1)
end

for _, root in ipairs(roots) do
  for _, f in ipairs(listFiles(root)) do
    scanFile(f)
  end
end

if #findings == 0 then
  print("No self-anchors detected.")
else
  print(string.format("Found %d potential self-anchor(s):\n", #findings))
  for _, msg in ipairs(findings) do
    print(msg)
    print("")
  end
end
