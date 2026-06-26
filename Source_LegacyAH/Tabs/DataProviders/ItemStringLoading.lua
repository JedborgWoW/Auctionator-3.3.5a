AuctionatorItemStringLoadingMixin = {}

function AuctionatorItemStringLoadingMixin:OnLoad()
  -- When the client finishes caching items shown with a placeholder icon, re-render
  -- so the real icons replace the placeholders (no re-search needed).
  Auctionator.Utilities.RegisterIconRefresh(function()
    self:SetDirty()
  end)

  self:SetOnEntryProcessedCallback(function(entry)
    -- Synchronous best-effort icon immediately, so an uncached item is never blank
    -- (ContinueOnItemLoad does not fire for an item the client has not cached yet).
    if entry.iconTexture == nil then
      entry.iconTexture = Auctionator.Utilities.GetItemIconSafe(entry.itemString)
    end
    local item = Item:CreateFromItemID((C_Item.GetItemInfoInstant(entry.itemString)))
    local complete = false
    item:ContinueOnItemLoad(function()
      -- Check to avoid overwriting name on empty results
      if entry.itemName == nil then
        self:ProcessItemString(entry, { C_Item.GetItemInfo(entry.itemString) })
      end
      complete = true
    end)
    if complete then
      self:NotifyCacheUsed()
    end
  end)
end

function AuctionatorItemStringLoadingMixin:ProcessItemString(rowEntry, itemInfo)
  local name = itemInfo[Auctionator.Constants.ITEM_INFO.NAME]
  local qualityColor = ITEM_QUALITY_COLORS[itemInfo[Auctionator.Constants.ITEM_INFO.RARITY]].color
  local class = itemInfo[Auctionator.Constants.ITEM_INFO.CLASS]

  rowEntry.itemLink = itemInfo[Auctionator.Constants.ITEM_INFO.LINK]

  rowEntry.name = name
  if class == Enum.ItemClass.Weapon or class == Enum.ItemClass.Armor then
    local itemLevel = GetDetailedItemLevelInfo(rowEntry.itemLink)
    rowEntry.name = rowEntry.name .. " (" .. itemLevel .. ")"
  end
  rowEntry.itemName = qualityColor:WrapTextInColorCode(rowEntry.name)

  rowEntry.iconTexture = itemInfo[Auctionator.Constants.ITEM_INFO.TEXTURE]
    or Auctionator.Utilities.GetItemIconSafe(rowEntry.itemLink or rowEntry.itemString)

  rowEntry.noneAvailable = rowEntry.totalQuantity == 0

  self:SetDirty()
end
