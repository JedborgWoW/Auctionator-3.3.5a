local unboundConstants = {
  LE_ITEM_BIND_NONE or Enum.ItemBind.None,
  LE_ITEM_BIND_ON_EQUIP or Enum.ItemBind.OnEquip,
  LE_ITEM_BIND_ON_USE or Enum.ItemBind.OnUse,
}
function Auctionator.Utilities.IsBound(itemInfo)
  local bindType = itemInfo[Auctionator.Constants.ITEM_INFO.BIND_TYPE]

  -- Stock 3.3.5a GetItemInfo stops at sellPrice (11 returns) and does NOT provide a
  -- bind type at index 14, so bindType is nil here. The old logic then evaluated
  -- tIndexOf(unbound, nil) == nil == true, marking EVERY item as bound -> AddAuctionTip
  -- bailed on `cannotAuction` and the scanned AH price line never appeared on tooltips
  -- (while the ungated Vendor line still did). Treat an unknown bind type as NOT bound
  -- so auctionable items show their AH price after a scan.
  if bindType == nil then
    return false
  end

  return tIndexOf(unboundConstants, bindType) == nil
end
