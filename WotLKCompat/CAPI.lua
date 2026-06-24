-- WotLK 3.3.5a compatibility: C_* namespaces
--
-- Maps the modern C_* item/container/chat/etc. namespaces onto the native
-- 3.3.5a globals. NOT shimmed on purpose (callers guard or fall back):
--   * C_EncodingUtil  -> guarded everywhere, falls back to bundled LibCBOR.
--   * C_TooltipInfo   -> guarded modern paths fall back to legacy tooltip code;
--                        the one unguarded caller is fixed at its site.
--   * TooltipDataProcessor -> guarded; legacy tooltip hooks run instead.

-- ---------------------------------------------------------------------------
-- Hidden tooltip used for soulbound detection (no C_Item.IsBound on 3.3.5a).
-- ---------------------------------------------------------------------------
local scanTip = CreateFrame("GameTooltip", "AuctionatorCompatScanTooltip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function LocationIsBound(location)
  if not location or not location.HasAnyLocation or not location:HasAnyLocation() then
    return false
  end
  scanTip:ClearLines()
  if location:IsBagAndSlot() then
    local bag, slot = location:GetBagAndSlot()
    if not pcall(scanTip.SetBagItem, scanTip, bag, slot) then
      return false
    end
  elseif location:IsEquipmentSlot() then
    pcall(scanTip.SetInventoryItem, scanTip, "player", location:GetEquipmentSlot())
  end
  for i = 2, scanTip:NumLines() do
    local fontString = _G["AuctionatorCompatScanTooltipTextLeft" .. i]
    local text = fontString and fontString:GetText()
    if text == ITEM_SOULBOUND then
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- C_Container
-- ---------------------------------------------------------------------------
if not C_Container then
  C_Container = {}

  function C_Container.GetContainerNumSlots(bagID)
    return GetContainerNumSlots(bagID)
  end

  function C_Container.GetContainerItemInfo(bagID, slotIndex)
    local texture, itemCount, locked, quality, readable, lootable, link, isFiltered, noValue, itemID =
      GetContainerItemInfo(bagID, slotIndex)
    if texture == nil and link == nil then
      return nil
    end
    if itemID == nil and link ~= nil then
      itemID = tonumber(string.match(link, "item:(%d+)"))
    end
    return {
      iconFileID = texture,
      stackCount = itemCount,
      isLocked = locked,
      quality = quality,
      isReadable = readable,
      hasLoot = lootable,
      hyperlink = link,
      isFiltered = isFiltered,
      hasNoValue = noValue,
      itemID = itemID,
    }
  end

  function C_Container.GetContainerItemDurability(bagID, slotIndex)
    if GetContainerItemDurability then
      return GetContainerItemDurability(bagID, slotIndex)
    end
    return nil
  end

  function C_Container.PickupContainerItem(bagID, slotIndex)
    return PickupContainerItem(bagID, slotIndex)
  end

  function C_Container.GetContainerItemLink(bagID, slotIndex)
    return GetContainerItemLink(bagID, slotIndex)
  end

  function C_Container.UseContainerItem(bagID, slotIndex)
    return UseContainerItem(bagID, slotIndex)
  end
end

-- ---------------------------------------------------------------------------
-- C_Item
-- ---------------------------------------------------------------------------
if not C_Item then
  C_Item = {}

  C_Item.GetItemInfo = GetItemInfo
  C_Item.GetItemInfoInstant = GetItemInfoInstant
  C_Item.GetItemSpell = GetItemSpell
  C_Item.GetItemCount = GetItemCount

  function C_Item.GetItemNameByID(item)
    return (GetItemInfo(item))
  end

  function C_Item.DoesItemExist(itemLocation)
    return itemLocation ~= nil
      and itemLocation.HasAnyLocation ~= nil
      and itemLocation:HasAnyLocation()
      and Auctionator_GetLinkFromLocation(itemLocation) ~= nil
  end

  function C_Item.GetItemLink(itemLocation)
    return Auctionator_GetLinkFromLocation(itemLocation)
  end

  function C_Item.GetItemLinkByGUID()
    return nil -- no item-GUID lookup on 3.3.5a
  end

  function C_Item.IsItemDataCached(item)
    if item == nil then
      return false
    end
    -- Retail's C_Item.IsItemDataCached takes an ItemLocation (a table); callers
    -- (e.g. Groups/BagCache) pass one. GetItemInfo only accepts an itemID/link/
    -- name, so resolve a location to its link first.
    if type(item) == "table" then
      local link = Auctionator_GetLinkFromLocation and Auctionator_GetLinkFromLocation(item)
      return link ~= nil and GetItemInfo(link) ~= nil
    end
    return GetItemInfo(item) ~= nil
  end

  function C_Item.IsItemDataCachedByID(itemID)
    return itemID ~= nil and GetItemInfo(itemID) ~= nil
  end

  function C_Item.IsBound(itemLocation)
    return LocationIsBound(itemLocation)
  end

  function C_Item.GetDetailedItemLevelInfo(item)
    local itemLevel = select(4, GetItemInfo(item))
    return itemLevel, false, itemLevel
  end

  function C_Item.GetCurrentItemLevel(itemLocation)
    local link = Auctionator_GetLinkFromLocation(itemLocation)
    if not link then
      return nil
    end
    return (select(4, GetItemInfo(link)))
  end

  -- 3.3.5a has no GetItemClassInfo; map the numeric class IDs to (English) names
  -- so callers that key tables by the name (e.g. Groups) do not get a nil key.
  local ITEM_CLASS_NAMES = {
    [0] = "Consumable", [1] = "Container", [2] = "Weapon", [3] = "Gem",
    [4] = "Armor", [5] = "Reagent", [6] = "Projectile", [7] = "Trade Goods",
    [8] = "Item Enhancement", [9] = "Recipe", [11] = "Quiver", [12] = "Quest",
    [13] = "Key", [15] = "Miscellaneous", [16] = "Glyph",
  }
  function C_Item.GetItemClassInfo(classID)
    if GetItemClassInfo then
      local name = GetItemClassInfo(classID)
      if name then
        return name
      end
    end
    return ITEM_CLASS_NAMES[classID] or ("Class " .. tostring(classID))
  end

  function C_Item.GetItemSubClassInfo(classID, subClassID)
    if GetItemSubClassInfo then
      return GetItemSubClassInfo(classID, subClassID)
    end
    return nil
  end

  function C_Item.GetStackCount(itemLocation)
    if itemLocation and itemLocation:IsBagAndSlot() then
      local info = C_Container.GetContainerItemInfo(itemLocation:GetBagAndSlot())
      return info and info.stackCount or 1
    end
    return 1
  end

  function C_Item.GetItemIcon(item)
    return (select(10, GetItemInfo(item)))
  end

  -- AH item locking is a retail concept; harmless no-ops on the legacy AH.
  function C_Item.LockItem() end
  function C_Item.UnlockItem() end
  function C_Item.LockItemByGUID() end
  function C_Item.UnlockItemByGUID() end

  function C_Item.GetItemGUID()
    return nil
  end
end

-- ---------------------------------------------------------------------------
-- C_ChatInfo (addon messaging)
-- ---------------------------------------------------------------------------
if not C_ChatInfo then
  C_ChatInfo = {}

  function C_ChatInfo.SendAddonMessage(prefix, message, chatType, target)
    return SendAddonMessage(prefix, message, chatType, target)
  end

  function C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    if RegisterAddonMessagePrefix then
      return RegisterAddonMessagePrefix(prefix)
    end
    return true -- 3.3.5a needs no prefix registration
  end

  function C_ChatInfo.IsAddonMessagePrefixRegistered()
    return true
  end

  function C_ChatInfo.InChatMessagingLockdown()
    return false
  end
end

-- ---------------------------------------------------------------------------
-- C_AddOns
-- ---------------------------------------------------------------------------
if not C_AddOns then
  C_AddOns = {}

  function C_AddOns.GetAddOnMetadata(addon, field)
    return GetAddOnMetadata(addon, field)
  end

  function C_AddOns.IsAddOnLoaded(addon)
    return IsAddOnLoaded(addon)
  end

  function C_AddOns.LoadAddOn(addon)
    return LoadAddOn(addon)
  end
end

-- ---------------------------------------------------------------------------
-- C_MerchantFrame
-- ---------------------------------------------------------------------------
if not C_MerchantFrame then
  C_MerchantFrame = {}

  function C_MerchantFrame.GetItemInfo(index)
    local name, texture, price, quantity, numAvailable, isPurchasable, isUsable, extendedCost =
      GetMerchantItemInfo(index)
    if name == nil then
      return nil
    end
    return {
      name = name,
      texture = texture,
      price = price,
      stackCount = quantity,
      numAvailable = numAvailable,
      isPurchasable = isPurchasable,
      isUsable = isUsable,
      hasExtendedCost = extendedCost,
    }
  end
end

-- GetMerchantItemID (global, added to retail later) -> derive the itemID from the
-- 3.3.5a GetMerchantItemLink. Used by CraftingInfo vendor-price caching.
if not GetMerchantItemID then
  function GetMerchantItemID(index)
    local link = GetMerchantItemLink(index)
    if not link then
      return nil
    end
    return tonumber(link:match("item:(%d+)"))
  end
end

-- ExtractHyperlinkString (global, added in Legion) -> split a hyperlink into its
-- prematch, the inner link string (e.g. "item:12345:0:..."), and postmatch.
-- Auctionator's GetCleanItemLink uses the inner string. Falls back to treating
-- the whole argument as the link body when it is not a full |H...|h hyperlink.
if not ExtractHyperlinkString then
  function ExtractHyperlinkString(text)
    if type(text) ~= "string" then
      return false, "", "", ""
    end
    local pre, link, post = text:match("^(.-)|H(.-)|h.-|h(.*)$")
    if link then
      return true, pre, link, post
    end
    return true, "", text, ""
  end
end

-- ---------------------------------------------------------------------------
-- C_Spell
-- ---------------------------------------------------------------------------
if not C_Spell then
  C_Spell = {}

  function C_Spell.IsSpellDataCached(spellID)
    return spellID ~= nil and GetSpellInfo(spellID) ~= nil
  end

  function C_Spell.RequestLoadSpellData() end
end

-- ---------------------------------------------------------------------------
-- C_Cursor
--
-- Best-effort: the modern API returns an ItemLocation for the held item, which
-- is not recoverable on 3.3.5a (the cursor exposes only the item, not its
-- bag/slot). Returns nil; the drag-from-cursor convenience path degrades to the
-- normal left-click behaviour, item clicks still work via the bag-slot hooks.
-- ---------------------------------------------------------------------------
if not C_Cursor then
  C_Cursor = {}

  function C_Cursor.GetCursorItem()
    return nil
  end

  function C_Cursor.DropCursorMoney() end
  function C_Cursor.GetCursorMoney() return 0 end
end

-- ---------------------------------------------------------------------------
-- C_PetJournal (battle pets do not exist on WotLK)
-- ---------------------------------------------------------------------------
if not C_PetJournal then
  C_PetJournal = {}

  function C_PetJournal.GetPetInfoBySpeciesID()
    return nil
  end
end

-- ---------------------------------------------------------------------------
-- C_TradeSkillUI (Dragonflight reagent-quality API; no equivalent on 3.3.5a)
-- ---------------------------------------------------------------------------
if not C_TradeSkillUI then
  C_TradeSkillUI = {}

  function C_TradeSkillUI.GetRecipeSchematic() return nil end
  function C_TradeSkillUI.GetRecipeOutputItemData() return nil end
  function C_TradeSkillUI.GetItemReagentQualityInfo() return nil end
  function C_TradeSkillUI.GetItemReagentQualityByItemInfo() return nil end
end

-- ---------------------------------------------------------------------------
-- C_AuctionHouse (legacy AH only needs this one query)
-- ---------------------------------------------------------------------------
if not C_AuctionHouse then
  C_AuctionHouse = {}
end
if not C_AuctionHouse.IsSellItemValid then
  function C_AuctionHouse.IsSellItemValid(itemLocation)
    local link = Auctionator_GetLinkFromLocation(itemLocation)
    return link ~= nil and not LocationIsBound(itemLocation)
  end
end

-- Several non-retail call sites use the GLOBAL GetDetailedItemLevelInfo (present on
-- the Classic clients, absent on stock 3.3.5a) rather than the C_Item method --
-- e.g. BuyAuctions/Filters/SaleItem/ItemStringLoading/UndercutScan. On 3.3.5a the
-- item level is just GetItemInfo()'s 4th return; mirror C_Item.GetDetailedItemLevelInfo
-- as a guarded global so those paths stop erroring ("attempt to call global ... a
-- nil value").
if not GetDetailedItemLevelInfo then
  function GetDetailedItemLevelInfo(item)
    local itemLevel = select(4, GetItemInfo(item))
    return itemLevel, false, itemLevel
  end
end

-- NOTE: deliberately NOT defining a global `Settings`/`SettingsPanel`. Other
-- addons (e.g. Ace3's AceConfigDialog) feature-detect `Settings` and then call
-- the full retail canvas API; a partial shim breaks them. Auctionator's own
-- Config code (Source/Config/...) is instead routed to the native 3.3.5a
-- InterfaceOptions system directly.
