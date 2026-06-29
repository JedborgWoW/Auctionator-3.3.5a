-- query = {
--   searchString -> string
--   minLevel -> int?
--   maxLevel -> int?
--   itemClassFilters -> itemClassFilter[]
--   isExact -> boolean?
-- }
function Auctionator.AH.QueryAuctionItems(query)
  Auctionator.AH.Internals.scan:StartQuery(query, 0, -1)
end

function Auctionator.AH.QueryAndFocusPage(query, page)
  Auctionator.AH.Internals.scan:StartQuery(query, page, page)
end

function Auctionator.AH.GetCurrentPage()
  return Auctionator.AH.Internals.scan:GetCurrentPage()
end

function Auctionator.AH.AbortQuery()
  Auctionator.AH.Internals.scan:AbortQuery()
end

-- Event ThrottleUpdate will fire whenever the state changes.
-- This gates the "grey post button" option. On stock 3.3.5a POSTING (StartAuction)
-- is NOT subject to the auction QUERY throttle (CanSendAuctionQuery), so it must
-- only consider whether a post/bid/cancel is already in progress -- otherwise the
-- Post button stays greyed after the buy view's price search leaves
-- CanSendAuctionQuery() false, and posting appears to do nothing.
function Auctionator.AH.IsNotThrottled()
  return not Auctionator.AH.Internals.throttling:AnyWaiting()
end

function Auctionator.AH.GetAuctionItemSubClasses(classID)
  return { GetAuctionItemSubClasses(classID) }
end

function Auctionator.AH.PlaceAuctionBid(...)
  Auctionator.AH.Internals.throttling:BidPlaced()
  PlaceAuctionBid("list", ...)
end

function Auctionator.AH.PostAuction(...)
  Auctionator.AH.Internals.throttling:AuctionsPosted()
  PostAuction(...)
end

-- view is a string and must be "list", "owner" or "bidder"
function Auctionator.AH.DumpAuctions(view)
  local auctions = {}
  for index = 1, GetNumAuctionItems(view) do
    local auctionInfo = { GetAuctionItemInfo(view, index) }
    local itemLink = GetAuctionItemLink(view, index)
    -- Stock 3.3.5a GetAuctionItemInfo does not return the itemID; derive it from
    -- the link so Constants.AuctionItemInfo.ItemID resolves for downstream filters.
    auctionInfo[Auctionator.Constants.AuctionItemInfo.ItemID] =
      itemLink and tonumber(string.match(itemLink, "item:(%d+)")) or nil
    local timeLeft = GetAuctionItemTimeLeft(view, index)
    local entry = {
      info = auctionInfo,
      itemLink = itemLink,
      timeLeft = timeLeft - 1, --Offset to match Retail time parameters
      index = index,
    }
    table.insert(auctions, entry)
  end
  return auctions
end

-- Cancel a single matching owned auction. NOTE: on the user's main server CancelAuction is a
-- PROTECTED function that only accepts calls from a button defined in frame XML -- the Cancelling
-- tab cancels via its hover "Cancel" button (AuctionatorCancellingFrameMixin), NOT through this
-- wrapper. This wrapper is still used by the bid-cost confirmation popup and the Cancel Undercut
-- flow, both of which originate from XML buttons.
function Auctionator.AH.CancelAuction(auction)
  local count = GetNumAuctionItems("owner")
  for index = 1, count do
    local info = { GetAuctionItemInfo("owner", index) }

    local stackPrice = info[Auctionator.Constants.AuctionItemInfo.Buyout]
    local stackSize = info[Auctionator.Constants.AuctionItemInfo.Quantity]
    local bidAmount = info[Auctionator.Constants.AuctionItemInfo.BidAmount]
    local saleStatus = info[Auctionator.Constants.AuctionItemInfo.SaleStatus]
    local itemLink = GetAuctionItemLink("owner", index)

    if saleStatus ~= 1 and auction.bidAmount == bidAmount and auction.stackPrice == stackPrice and auction.stackSize == stackSize and Auctionator.Search.GetCleanItemLink(itemLink) == Auctionator.Search.GetCleanItemLink(auction.itemLink) then
      Auctionator.AH.Internals.throttling:AuctionCancelled()
      CancelAuction(index)
      return
    end
  end
end
