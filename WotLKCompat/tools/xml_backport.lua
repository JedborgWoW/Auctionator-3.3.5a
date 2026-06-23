-- Transform modern WoW XML features (unsupported on stock 3.3.5a) in place.
--   mixin="A B C"             -> Mixin(self, A, B, C)  in the element's OnLoad
--   <KeyValues><KeyValue.../>  -> self.key = value     in the element's OnLoad
--   <OnX method="Y"/>          -> <OnX>self:Y(<args>)</OnX>
--   <EventFrame>/<DropdownButton> -> <Frame>/<Button>
--
-- Each frame element is buffered so the combined "prologue" (Mixin + KeyValues)
-- is injected into a single OnLoad regardless of whether KeyValues/Scripts come
-- before or after it (creating an OnLoad/Scripts when none exists). A nesting
-- stack matches tags; comments / CDATA / function= handlers are left untouched.
--
-- Usage: lua xml_backport.lua <listfile>   (one xml path per line; arg path is
-- translated by the shell, so do not hard-code paths inside this script)

local MARK = "\001"  -- single placeholder per frame buffer, substituted at close

local SCRIPT_ARGS = {
  OnLoad="", OnShow="", OnHide="", OnTextSet="", OnEnterPressed="",
  OnEscapePressed="", OnEditFocusGained="", OnEditFocusLost="", OnTabPressed="",
  OnSpacePressed="", OnDragStop="", OnReceiveDrag="",
  OnEnter="motion", OnLeave="motion",
  OnMouseDown="button", OnMouseUp="button", OnDoubleClick="button", OnDragStart="button",
  OnClick="button, down", PostClick="button, down",
  OnUpdate="elapsed", OnEvent="event, ...",
  OnKeyDown="key", OnKeyUp="key", OnChar="text",
  OnTextChanged="userInput, ...", OnValueChanged="value, ...",
  OnSizeChanged="width, height", OnMouseWheel="delta",
  OnVerticalScroll="offset", OnHorizontalScroll="offset",
  OnScrollRangeChanged="xrange, yrange",
  OnHyperlinkEnter="link, text", OnHyperlinkLeave="link, text",
  OnHyperlinkClick="link, text, button", OnAttributeChanged="name, value",
}

local RENAME = { EventFrame="Frame", DropdownButton="Button" }

-- Element names that are NOT frame containers (emitted as content). Anything not
-- listed (and not a handler) is treated as a frame and buffered; mis-treating a
-- childless content element as a frame is a harmless passthrough.
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

local stats = { mixin=0, keyvalue=0, method=0, rename=0, onload_created=0 }

local function isHandler(name)
  return name:sub(1,2) == "On" and name:len() > 2 and name:sub(3,3):match("%u") ~= nil
end

local function mixinCall(value)
  local parts = {}
  for w in value:gmatch("%S+") do parts[#parts+1] = w end
  return "Mixin(self, " .. table.concat(parts, ", ") .. ")"
end

local function kvAssign(key, value, vtype)
  local rhs
  if vtype == "number" or vtype == "boolean" or vtype == "global" then
    rhs = value
  elseif vtype == "nil" then
    rhs = "nil"
  else -- string (default)
    rhs = string.format("%q", value)
  end
  return "self." .. key .. " = " .. rhs
end

local function transform(text)
  local root = {}
  local frames = {}          -- buffer-frame stack
  local nstack = {}          -- nesting stack: {name, kind}  kind: "frame"/"content"/"scripts"/"keyvalues"/"handler"
  local function curbuf()
    if #frames > 0 then return frames[#frames].buf else return root end
  end
  local function emit(s) local b = curbuf(); b[#b+1] = s end
  local function curframe() return frames[#frames] end

  local i, n = 1, #text
  while i <= n do
    local lt = text:find("<", i, true)
    if not lt then emit(text:sub(i)); break end
    if lt > i then emit(text:sub(i, lt-1)) end

    if text:sub(lt, lt+3) == "<!--" then
      local e = text:find("-->", lt, true); e = e and e+2 or n
      emit(text:sub(lt, e)); i = e + 1
    elseif text:sub(lt, lt+8) == "<![CDATA[" then
      local e = text:find("]]>", lt, true); e = e and e+2 or n
      emit(text:sub(lt, e)); i = e + 1
    else
      local gt = text:find(">", lt, true)
      if not gt then emit(text:sub(lt)); break end
      local tok = text:sub(lt, gt); i = gt + 1
      local inner = tok:sub(2, -2)
      local isClose = inner:sub(1,1) == "/"
      local isSelf  = (not isClose) and inner:sub(-1) == "/"

      if isClose then
        local name = inner:match("^/%s*([%w_]+)")
        local outName = RENAME[name] or name
        if RENAME[name] then stats.rename = stats.rename + 1 end
        local top = table.remove(nstack)
        local kind = top and top.kind
        if kind == "keyvalues" then
          -- suppressed
        elseif kind == "scripts" then
          local f = curframe()
          if f and not f.injected then
            emit("<OnLoad>" .. MARK .. "</OnLoad>")
            f.injected = true
          end
          emit("</Scripts>")
        elseif kind == "frame" then
          local f = table.remove(frames)
          if not f.injected and f.prologue ~= "" then
            f.buf[#f.buf+1] = "<Scripts><OnLoad>" .. MARK .. "</OnLoad></Scripts>"
            f.injected = true
            stats.onload_created = stats.onload_created + 1
          end
          local body = table.concat(f.buf)
          local pro = f.prologue
          body = body:gsub(MARK, function() return pro end)
          emit(f.openTag .. body .. "</" .. f.name .. ">")
        else
          emit("</" .. outName .. ">")
        end

      elseif isSelf then
        local core = inner:sub(1, -2)
        local name, attrs = core:match("^%s*([%w_]+)(.*)$")
        attrs = attrs or ""
        if isHandler(name) then
          local method = attrs:match('method="([%w_]+)"')
          if method then
            stats.method = stats.method + 1
            local args = SCRIPT_ARGS[name] or "..."
            local b = "self:" .. method .. "(" .. args .. ")"
            if name == "OnLoad" then
              local f = curframe()
              if f and not f.injected then
                b = MARK .. b
                f.injected = true
              end
            end
            emit("<" .. name .. ">" .. b .. "</" .. name .. ">")
          else
            emit(tok) -- function= or other handler: leave untouched
          end
        elseif name == "KeyValue" then
          -- collect into the current frame's prologue
          local f = curframe()
          local key   = attrs:match('key="([^"]*)"')
          local value = attrs:match('value="([^"]*)"')
          local vtype = attrs:match('type="([%w]+)"')
          if f and key then
            f.prologue = f.prologue .. kvAssign(key, value or "", vtype) .. "; "
            stats.keyvalue = stats.keyvalue + 1
          end
          -- suppressed (not emitted)
        elseif CONTENT[name] then
          emit(tok)
        else
          -- self-closing frame, maybe with mixin
          local mixin = attrs:match('mixin="([^"]*)"')
          local outName = RENAME[name] or name
          if RENAME[name] then stats.rename = stats.rename + 1 end
          if mixin then
            local attrs2 = attrs:gsub('%s*mixin="[^"]*"', "", 1)
            stats.mixin = stats.mixin + 1
            stats.onload_created = stats.onload_created + 1
            emit("<" .. outName .. attrs2 .. "><Scripts><OnLoad>" .. mixinCall(mixin)
              .. "</OnLoad></Scripts></" .. outName .. ">")
          else
            emit("<" .. outName .. attrs .. "/>")
          end
        end

      else -- opening tag
        local name, attrs = inner:match("^%s*([%w_]+)(.*)$")
        attrs = attrs or ""
        if name == "KeyValues" then
          nstack[#nstack+1] = { name=name, kind="keyvalues" }
          -- suppressed
        elseif name == "Scripts" then
          emit("<Scripts>")
          nstack[#nstack+1] = { name=name, kind="scripts" }
        elseif isHandler(name) then
          if name == "OnLoad" then
            emit("<OnLoad>")
            local f = curframe()
            if f and not f.injected then emit(MARK); f.injected = true end
          else
            emit("<" .. name .. ">")
          end
          nstack[#nstack+1] = { name=name, kind="handler" }
        elseif CONTENT[name] then
          emit("<" .. name .. attrs .. ">")
          nstack[#nstack+1] = { name=name, kind="content" }
        else
          -- frame container
          local mixin = attrs:match('mixin="([^"]*)"')
          if mixin then attrs = attrs:gsub('%s*mixin="[^"]*"', "", 1); stats.mixin = stats.mixin + 1 end
          local outName = RENAME[name] or name
          if RENAME[name] then stats.rename = stats.rename + 1 end
          local F = { name=outName, openTag="<"..outName..attrs..">",
                      prologue = mixin and (mixinCall(mixin) .. "; ") or "",
                      buf = {}, injected = false }
          frames[#frames+1] = F
          nstack[#nstack+1] = { name=outName, kind="frame" }
        end
      end
    end
  end

  -- flush any unclosed frames (shouldn't happen in well-formed XML)
  while #frames > 0 do
    local f = table.remove(frames)
    local body = table.concat(f.buf):gsub(MARK, function() return f.prologue end)
    emit(f.openTag .. body .. "</" .. f.name .. ">")
  end
  return table.concat(root)
end

local lf = assert(io.open(arg[1], "r"))
local changed, scanned = 0, 0
for path in lf:lines() do
  path = path:gsub("%s+$", "")
  if #path > 0 then
    scanned = scanned + 1
    local f = assert(io.open(path, "rb"))
    local src = f:read("*a"); f:close()
    local dst = transform(src)
    if dst ~= src then
      local w = assert(io.open(path, "wb")); w:write(dst); w:close()
      changed = changed + 1
    end
  end
end
lf:close()
print("scanned:", scanned, "changed:", changed)
for k, v in pairs(stats) do print("  "..k, v) end
