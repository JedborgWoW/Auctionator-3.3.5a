AuctionatorBagItemSelectedMixin = CreateFromMixins(AuctionatorGroupsViewItemMixin)

function AuctionatorBagItemSelectedMixin:SetItemInfo(info, ...)
  AuctionatorGroupsViewItemMixin.SetItemInfo(self, info, ...)
  self.IconSelectedHighlight:Hide()
  self.IconBorder:SetShown(info ~= nil)
  self.Icon:SetAlpha(1)

  self.clickEventName = "BagUse.BagItemClicked"
end

local seenBag, seenSlot

function AuctionatorBagItemSelectedMixin:OnClick(button)
  local wasCursorItem = C_Cursor.GetCursorItem()
  self:ProcessCursor(function(check)
    if not check then
      if button == "LeftButton" and not wasCursorItem and self.itemInfo ~= nil and not IsModifiedClick("DRESSUP") and not IsModifiedClick("CHATLINK") then
        self:SearchInShoppingTab()
      else
        AuctionatorGroupsViewItemMixin.OnClick(self, button)
      end
    end
  end)
end

function AuctionatorBagItemSelectedMixin:SearchInShoppingTab()
  Auctionator.API.v1.MultiSearchExact(AUCTIONATOR_L_SELLING_TAB, { self.itemInfo.itemName })
end

function AuctionatorBagItemSelectedMixin:OnReceiveDrag()
  self:ProcessCursor(function() end)
end

function AuctionatorBagItemSelectedMixin:ProcessCursor(callback)
  local location = C_Cursor.GetCursorItem()
  ClearCursor()

  if not location then
    Auctionator.Debug.Message("nothing on cursor")
    callback(false)
    return
  end

  -- Case when picking up a key from your keyring in classic, WoW doesn't always
  -- give a valid item location for the cursor, causing an error unless we
  -- either:
  --  1. Ignore it
  --  2. Replace the location with one that is valid based on a hook on bag
  --  clicks.
  -- We use 2.
  if not location:HasAnyLocation() then
    Auctionator.Debug.Message("AuctionatorBagItemSelected", "recovering")
    location = ItemLocation:CreateFromBagAndSlot(seenBag, seenSlot)
  end

  if not C_Item.DoesItemExist(location) then
    Auctionator.Debug.Message("AuctionatorBagItemSelected", "not exists")
    callback(false)
    return
  end

  local itemLink = C_Item.GetItemLink(location)

  Auctionator.EventBus:RegisterSource(self, "BagItemSelected")
  Auctionator.Groups.CallbackRegistry:RegisterCallback("BagCacheUpdated", function(_, cache)
    Auctionator.Groups.CallbackRegistry:UnregisterCallback("BagCacheUpdated", self)
    Auctionator.Groups.CallbackRegistry:TriggerEvent("BagCacheOff")
    cache:CacheLinkInfo(itemLink, function()
      local info = Auctionator.Groups.Utilities.ToPostingItem(AuctionatorBagCacheFrame:GetByLinkInstant(itemLink, true))
      if info.location then
        callback(true)
        info.location = location
        Auctionator.EventBus:Fire(self, Auctionator.Selling.Events.BagItemClicked, info)
      else
        Auctionator.Selling.ShowCannotSellReason(location)
        callback(false)
      end
    end)
  end, self)
  Auctionator.Groups.CallbackRegistry:TriggerEvent("BagCacheOn")
end

local function HookForPickup(bag, slot)
  seenBag = bag
  seenSlot = slot
end

-- For classic record clicks on bag items so that we can make keyring items
-- being picked up and placed in the Selling tab work.
if C_Container and C_Container.PickupContainerItem then
  hooksecurefunc(C_Container, "PickupContainerItem", HookForPickup)
end
-- On stock 3.3.5a a manual bag drag/pickup goes through the GLOBAL PickupContainerItem
-- (the Blizzard bag UI), not the C_Container shim, so hook it too. This records the
-- bag/slot the dragged item came from so the drag-onto-Selling recovery can rebuild
-- the item location (C_Cursor.GetCursorItem only reports that *an* item is held).
if type(PickupContainerItem) == "function" then
  pcall(hooksecurefunc, "PickupContainerItem", HookForPickup)
end
