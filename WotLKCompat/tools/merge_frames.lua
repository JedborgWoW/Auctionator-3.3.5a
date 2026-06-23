-- Merge multiple direct <Frames> blocks within a frame into the FIRST one.
--
-- Stock 3.3.5a's XML parser only honours the FIRST <Frames> child of a frame;
-- child frames declared in a second <Frames> block are silently never created
-- (e.g. AuctionatorStackOfInputTemplate: NumStacks in the first <Frames>, a
-- <Layers> with the Label in between, then StackSize in a SECOND <Frames> ->
-- self.StackSize was nil). Child creation order no longer matters for layout
-- (positions are SetPoint'd in OnLoad), so concatenate the inner content of all
-- of a frame's <Frames> blocks into its first block.
--
-- Usage: lua merge_frames.lua <listfile>

local CONTENT = {}
for _, n in ipairs({
  "Ui","Include","Script","Scripts","KeyValues","KeyValue","Size","AbsDimension",
  "Anchors","Anchor","Offset","Dimension","Layers","Layer","Texture","MaskTexture",
  "Line","FontString","Color","Shadow","TexCoords","Gradient","MinColor","MaxColor",
  "Animations","AnimationGroup","Alpha","Scale","Translation","Rotation","ButtonText",
  "PushedTextOffset","NormalTexture","PushedTexture","HighlightTexture","DisabledTexture",
  "CheckedTexture","DisabledCheckedTexture","ThumbTexture","BarTexture","SwipeTexture",
  "BlingTexture","EdgeTexture","NormalText","HighlightText","DisabledText","NormalFont",
  "HighlightFont","DisabledFont","NormalColor","HighlightColor","DisabledColor","FontHeight",
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
  local name
  if isClose then name = inner:match("^/%s*([%w_]+)")
  else local core = isSelf and inner:sub(1, -2) or inner; name = core:match("^%s*([%w_]+)") end
  return name, isClose, isSelf
end

local function isFrameTag(name)
  if not name then return false end
  return not CONTENT[name] and not REGION[name]
    and not (name:sub(1,2) == "On" and #name > 2 and name:sub(3,3):match("%u"))
end

local stats = { files = 0, merged = 0 }

local function process(path)
  local f = io.open(path, "rb"); if not f then return end
  local s = f:read("*a"); f:close()

  local out = {}
  local emit = function(x) out[#out + 1] = x end
  local stack = {}        -- entries: {kind="frame"/"frames"/"content", node=, first=}
  local repl = {}
  local phid = 0
  local divert = nil      -- frame node whose extra <Frames> inner we are buffering

  local function put(tok)
    if divert then divert.extra[#divert.extra + 1] = tok else emit(tok) end
  end

  eachToken(s, function(kind, tok)
    if kind ~= "tag" then put(tok); return end
    local name, isClose, isSelf = parseTag(tok)

    if isClose then
      local top = stack[#stack]
      if name == "Frames" and top and top.kind == "frames" then
        if top.first then
          emit(top.node.ph)   -- insertion point inside the first block
          emit(tok)           -- </Frames>
        else
          divert = nil        -- end of an extra block: drop its </Frames>
        end
        stack[#stack] = nil
        return
      end
      if top and top.kind == "frame" then
        if top.node.ph then repl[top.node.ph] = table.concat(top.node.extra) end
        stack[#stack] = nil
        put(tok)
        return
      end
      if top then stack[#stack] = nil end
      put(tok)
      return
    end

    if name == "Frames" and not isSelf then
      local fr
      for j = #stack, 1, -1 do if stack[j].kind == "frame" then fr = stack[j].node; break end end
      if fr then
        fr.seen = (fr.seen or 0) + 1
        if fr.seen == 1 then
          phid = phid + 1; fr.ph = "\1MF" .. phid .. "\1"; fr.extra = {}
          emit(tok)                                   -- first <Frames>
          stack[#stack + 1] = { kind = "frames", first = true, node = fr }
        else
          divert = fr                                 -- buffer inner into fr.extra
          stack[#stack + 1] = { kind = "frames", first = false, node = fr }
          stats.merged = stats.merged + 1
        end
        return
      end
      put(tok)
      stack[#stack + 1] = { kind = "content" }
      return
    end

    put(tok)
    if not isSelf then
      if isFrameTag(name) then
        stack[#stack + 1] = { kind = "frame", node = {} }
      else
        stack[#stack + 1] = { kind = "content" }
      end
    end
  end)

  local result = table.concat(out)
  result = result:gsub("\1MF%d+\1", function(ph) return repl[ph] or "" end)
  if result ~= s then
    local w = io.open(path, "wb"); w:write(result); w:close()
    stats.files = stats.files + 1
  end
end

for path in io.lines(arg[1]) do
  path = path:gsub("%s+$", "")
  if #path > 0 then process(path) end
end
print(("files changed: %d  extra <Frames> merged: %d"):format(stats.files, stats.merged))
