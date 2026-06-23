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
    return item ~= nil and GetItemInfo(item) ~= nil
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

  function C_Item.GetItemClassInfo(classID)
    if GetItemClassInfo then
      return GetItemClassInfo(classID)
    end
    return nil
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

-- ---------------------------------------------------------------------------
-- Settings / SettingsPanel (retail options canvas API, added in Dragonflight).
-- Bridge to the 3.3.5a InterfaceOptions system. Auctionator's Config panels are
-- parented to SettingsPanel and registered via Settings.RegisterCanvasLayout*.
-- ---------------------------------------------------------------------------
if SettingsPanel == nil then
  SettingsPanel = InterfaceOptionsFramePanelContainer or UIParent
end

if Settings == nil then
  Settings = {}

  local function MakeCategory(frame, name, parentName)
    frame.name = name
    frame.parent = parentName
    if InterfaceOptions_AddCategory then
      InterfaceOptions_AddCategory(frame)
    end
    return {
      frame = frame,
      name = name,
      GetID = function() return name end,
      GetName = function() return name end,
    }
  end

  function Settings.RegisterCanvasLayoutCategory(frame, name)
    return MakeCategory(frame, name, nil)
  end

  function Settings.RegisterCanvasLayoutSubcategory(parentCategory, frame, name)
    local parentName = parentCategory and (parentCategory.name
      or (parentCategory.frame and parentCategory.frame.name))
    return MakeCategory(frame, name, parentName)
  end

  -- The frame is already registered with InterfaceOptions; nothing more to do.
  function Settings.RegisterAddOnCategory() end

  function Settings.OpenToCategory(id)
    if InterfaceOptionsFrame_OpenToCategory then
      -- 3.3.5a needs this called twice to reliably scroll to the panel.
      InterfaceOptionsFrame_OpenToCategory(id)
      InterfaceOptionsFrame_OpenToCategory(id)
    end
  end
end
