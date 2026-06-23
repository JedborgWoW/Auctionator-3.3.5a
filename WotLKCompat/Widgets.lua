-- WotLK 3.3.5a compatibility: widget method shims
--
-- Adds region/frame methods that modern WoW has but 3.3.5a lacks. On this client
-- each widget type has its own metatable __index table (Button does not inherit
-- Frame's table), so each missing method must be added to every type we use.
--
-- NOTE: we deliberately do NOT wrap the global CreateFrame (doing so taints every
-- frame the secure UI and other addons create). The modern "EventFrame" /
-- "DropdownButton" frame types are handled by editing Auctionator's few
-- CreateFrame call sites to "Frame" / "Button" directly.

-- ---------------------------------------------------------------------------
-- Method shims
-- ---------------------------------------------------------------------------
local function AddMethods(sample, methods)
  if not sample then
    return
  end
  local mt = getmetatable(sample)
  local index = mt and mt.__index
  if type(index) ~= "table" then
    return
  end
  for name, fn in pairs(methods) do
    if index[name] == nil then
      index[name] = fn
    end
  end
end

local function SetShown(self, shown)
  if shown then
    self:Show()
  else
    self:Hide()
  end
end

local function SetSize(self, width, height)
  self:SetWidth(width)
  self:SetHeight(height)
end

local function GetSize(self)
  return self:GetWidth(), self:GetHeight()
end

local function SetEnabled(self, enabled)
  if enabled then
    if self.Enable then self:Enable() end
  else
    if self.Disable then self:Disable() end
  end
end

local function SetPropagateKeyboardInput() end -- retail-only, safe no-op

-- GetPointByName (added in Shadowlands): return the anchor matching a point name.
local function GetPointByName(self, pointName)
  for i = 1, self:GetNumPoints() do
    local point, relativeTo, relativePoint, x, y = self:GetPoint(i)
    if point == pointName then
      return point, relativeTo, relativePoint, x, y
    end
  end
end

-- Region-level methods (apply to frames AND textures/fontstrings).
local regionMethods = {
  SetShown = SetShown,
  SetSize = SetSize,
  GetSize = GetSize,
  GetPointByName = GetPointByName,
}

-- Frame-level extras.
local frameMethods = {
  SetEnabled = SetEnabled,
  SetPropagateKeyboardInput = SetPropagateKeyboardInput,
}

-- Build one sample of each widget type and patch its metatable.
local probe = CreateFrame("Frame")

AddMethods(probe, regionMethods)
AddMethods(probe, frameMethods)

local frameTypes = {
  "Button", "CheckButton", "EditBox", "Slider", "StatusBar",
  "ScrollFrame", "GameTooltip", "MessageFrame", "ColorSelect",
  "Cooldown", "SimpleHTML", "Model", "PlayerModel", "Minimap",
}
for _, t in ipairs(frameTypes) do
  local ok, obj = pcall(CreateFrame, t)
  if ok and obj then
    AddMethods(obj, regionMethods)
    AddMethods(obj, frameMethods)
  end
end

-- Textures and font strings (regions, not frames).
local tex = probe:CreateTexture()
AddMethods(tex, regionMethods)
AddMethods(tex, {
  SetColorTexture = function(self, r, g, b, a)
    self:SetTexture(r, g, b, a)
  end,
  -- 3.3.5a has no atlas system; treat as a no-op (the texture simply stays
  -- whatever it was). Cosmetic only.
  SetAtlas = function() end,
  GetAtlas = function() return nil end,
})

local fontString = probe:CreateFontString()
AddMethods(fontString, regionMethods)

-- ---------------------------------------------------------------------------
-- GetItemInfoInstant: added in Legion. Best-effort on 3.3.5a — the itemID and
-- equip-location/icon are reliable; classID/subClassID are not numerically
-- available from GetItemInfo on this client, so they are returned as nil.
-- Returns: itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID
-- ---------------------------------------------------------------------------
if not GetItemInfoInstant then
  function GetItemInfoInstant(item)
    if item == nil then
      return nil
    end
    local itemID
    if type(item) == "number" then
      itemID = item
    else
      itemID = tonumber(item) or tonumber(string.match(item, "item:(%d+)"))
    end
    if itemID == nil then
      return nil
    end
    local _, _, _, _, _, itemType, itemSubType, _, itemEquipLoc, icon = GetItemInfo(item)
    return itemID, itemType, itemSubType, itemEquipLoc, icon, nil, nil
  end
end

-- CreateAtlasMarkup: returns an inline texture markup. No atlases on 3.3.5a, so
-- return an empty string (callers concatenate it into text).
if not CreateAtlasMarkup then
  function CreateAtlasMarkup()
    return ""
  end
end

-- C_Texture stub (GetAtlasInfo used indirectly by some helpers).
if not C_Texture then
  C_Texture = {
    GetAtlasInfo = function() return nil end,
  }
end

-- GameTooltip:SetItemByID (added in Cataclysm) -> SetHyperlink on the shared
-- GameTooltip metatable (covers GameTooltip, ItemRefTooltip and other
-- GameTooltipTemplate frames). Auctionator hooks this to inject price lines.
if GameTooltip and not GameTooltip.SetItemByID then
  local mt = getmetatable(GameTooltip)
  local index = mt and mt.__index
  if type(index) == "table" and index.SetItemByID == nil then
    index.SetItemByID = function(self, itemID)
      if itemID then
        self:SetHyperlink("item:" .. itemID)
      end
    end
  end
end

-- UnitName-less helpers occasionally referenced.
if not GetPhysicalScreenSize then
  function GetPhysicalScreenSize()
    return 1920, 1080
  end
end
