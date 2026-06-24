Auctionator.Constants.MaxResultsPerPage = 50
Auctionator.Constants.ITEM_LEVEL_THRESHOLD = 0

-- Stock 3.3.5a (client 12340) GetAuctionItemInfo returns, in order:
--   1 name        2 texture      3 count        4 quality   5 canUse
--   6 level       7 minBid       8 minIncrement 9 buyoutPrice
--   10 bidAmount  11 highBidder  12 owner       13 saleStatus
-- i.e. the OLD layout WITHOUT the Classic/retail extras (levelColHeader,
-- bidderFullName, ownerFullName, itemId). The upstream values targeted Classic
-- (Buyout=10/Owner=14/SaleStatus=16/ItemID=17) and so read the wrong fields here
-- -- Owner landed on a nil slot, which made the scan's GotAllOwners() check never
-- pass (no results). itemId is NOT returned on 3.3.5a; DumpAuctions injects it
-- from the item link at the ItemID index below.
Auctionator.Constants.AuctionItemInfo = {
  Quantity = 3,
  Level = 6,
  MinBid = 7,
  Buyout = 9,
  BidAmount = 10,
  Bidder = 11,
  Owner = 12,
  SaleStatus = 13,
  ItemID = 14,
}

Auctionator.Constants.PriceIncreaseWarningDuration = 5
Auctionator.Constants.PriceIncreaseWarningThreshold = 40
