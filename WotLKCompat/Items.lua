-- WotLK 3.3.5a compatibility: ItemLocation + Item mixins
--
-- The modern item-location / async item-loading API (Legion+). Backed by the
-- native 3.3.5a globals (GetContainerItemLink, GetInventoryItemLink, GetItemInfo).

-- ---------------------------------------------------------------------------
-- ItemLocation
-- ---------------------------------------------------------------------------
if not ItemLocationMixin then
  ItemLocationMixin = {}

  function ItemLocationMixin:Clear()
    self.bagID = nil
    self.slotIndex = nil
    self.equipmentSlotIndex = nil
  end

  function ItemLocationMixin:IsBagAndSlot()
    return self.bagID ~= nil and self.slotIndex ~= nil
  end

  function ItemLocationMixin:IsEquipmentSlot()
    return self.equipmentSlotIndex ~= nil
  end

  function ItemLocationMixin:HasAnyLocation()
    return self:IsBagAndSlot() or self:IsEquipmentSlot()
  end

  function ItemLocationMixin:IsValid()
    return self:HasAnyLocation()
  end

  function ItemLocationMixin:SetBagAndSlot(bagID, slotIndex)
    self.bagID = bagID
    self.slotIndex = slotIndex
    self.equipmentSlotIndex = nil
  end

  function ItemLocationMixin:SetEquipmentSlot(equipmentSlotIndex)
    self.equipmentSlotIndex = equipmentSlotIndex
    self.bagID = nil
    self.slotIndex = nil
  end

  function ItemLocationMixin:GetBagAndSlot()
    if self:IsBagAndSlot() then
      return self.bagID, self.slotIndex
    end
  end

  function ItemLocationMixin:GetEquipmentSlot()
    if self:IsEquipmentSlot() then
      return self.equipmentSlotIndex
    end
  end
end

if not ItemLocation then
  ItemLocation = {}

  function ItemLocation:CreateEmpty()
    return CreateFromMixins(ItemLocationMixin)
  end

  function ItemLocation:CreateFromBagAndSlot(bagID, slotIndex)
    local location = CreateFromMixins(ItemLocationMixin)
    location:SetBagAndSlot(bagID, slotIndex)
    return location
  end

  function ItemLocation:CreateFromEquipmentSlot(equipmentSlotIndex)
    local location = CreateFromMixins(ItemLocationMixin)
    location:SetEquipmentSlot(equipmentSlotIndex)
    return location
  end
end

-- Resolve an item link from any location using native 3.3.5a globals.
local function GetLinkFromLocation(location)
  if not location then
    return nil
  end
  if location:IsBagAndSlot() then
    local bag, slot = location:GetBagAndSlot()
    return GetContainerItemLink(bag, slot)
  elseif location:IsEquipmentSlot() then
    return GetInventoryItemLink("player", location:GetEquipmentSlot())
  end
end
Auctionator_GetLinkFromLocation = GetLinkFromLocation

-- ---------------------------------------------------------------------------
-- Item (async loadable item)
-- ---------------------------------------------------------------------------
if not ItemMixin then
  ItemMixin = {}

  function ItemMixin:SetItemID(itemID)
    self.itemID = itemID
    self.itemLink = nil
    self.itemLocation = nil
  end

  function ItemMixin:SetItemLink(itemLink)
    self.itemLink = itemLink
    self.itemID = nil
    self.itemLocation = nil
  end

  function ItemMixin:SetItemLocation(itemLocation)
    self.itemLocation = itemLocation
    self.itemID = nil
    self.itemLink = nil
  end

  -- A stable key for GetItemInfo lookups.
  function ItemMixin:GetItemKey()
    if self.itemLink then
      return self.itemLink
    end
    if self.itemID then
      return self.itemID
    end
    if self.itemLocation then
      return GetLinkFromLocation(self.itemLocation)
    end
  end

  function ItemMixin:IsItemEmpty()
    return self:GetItemKey() == nil
  end

  function ItemMixin:GetItemID()
    if self.itemID then
      return self.itemID
    end
    local link = self:GetItemLink()
    if link then
      return tonumber(string.match(link, "item:(%d+)"))
    end
  end

  function ItemMixin:GetItemLink()
    if self.itemLink then
      return self.itemLink
    end
    if self.itemLocation then
      local link = GetLinkFromLocation(self.itemLocation)
      if link then
        return link
      end
    end
    if self.itemID then
      return (select(2, GetItemInfo(self.itemID)))
    end
  end

  function ItemMixin:GetItemName()
    local key = self:GetItemKey()
    return key and (GetItemInfo(key))
  end

  function ItemMixin:GetItemIcon()
    local key = self:GetItemKey()
    if not key then
      return nil
    end
    return (select(10, GetItemInfo(key)))
  end

  function ItemMixin:GetItemQuality()
    local key = self:GetItemKey()
    if not key then
      return nil
    end
    return (select(3, GetItemInfo(key)))
  end

  function ItemMixin:IsItemDataCached()
    local key = self:GetItemKey()
    return key ~= nil and GetItemInfo(key) ~= nil
  end

  -- Calls callback once item data is available. 3.3.5a has no
  -- ITEM_DATA_LOAD_RESULT event, so poll GetItemInfo briefly. Returns a cancel
  -- function (for ContinueWithCancelOnItemLoad).
  function ItemMixin:ContinueOnItemLoad(callback)
    if self:IsItemEmpty() then
      return nil
    end

    if self:IsItemDataCached() then
      callback()
      return nil
    end

    local cancelled = false
    local attempts = 0
    local function poll()
      if cancelled then
        return
      end
      if self:IsItemDataCached() then
        callback()
      elseif attempts < 50 then -- ~5s at 0.1s intervals
        attempts = attempts + 1
        C_Timer.After(0.1, poll)
      else
        -- Fire anyway so the UI does not hang waiting forever.
        callback()
      end
    end
    poll()

    return function()
      cancelled = true
    end
  end

  function ItemMixin:ContinueWithCancelOnItemLoad(callback)
    return self:ContinueOnItemLoad(callback)
  end
end

if not Item then
  Item = {}

  function Item:CreateFromItemID(itemID)
    local item = CreateFromMixins(ItemMixin)
    item:SetItemID(itemID)
    return item
  end

  function Item:CreateFromItemLink(itemLink)
    local item = CreateFromMixins(ItemMixin)
    item:SetItemLink(itemLink)
    return item
  end

  function Item:CreateFromItemLocation(itemLocation)
    local item = CreateFromMixins(ItemMixin)
    item:SetItemLocation(itemLocation)
    return item
  end

  function Item:CreateFromBagAndSlot(bagID, slotIndex)
    return Item:CreateFromItemLocation(ItemLocation:CreateFromBagAndSlot(bagID, slotIndex))
  end
end
