AuctionatorAHScanFrameMixin = {}

local SCAN_EVENTS = {
  "AUCTION_ITEM_LIST_UPDATE",
}

local function ParamsForBlizzardAPI(query, page)
  -- Stock 3.3.5a QueryAuctionItems signature differs from Wrath Classic 3.4:
  --   (name, minLevel, maxLevel, invTypeIndex, classIndex, subclassIndex,
  --    page, isUsable, qualityIndex, getAll)
  -- 3.3.5a has no exactMatch/filterData params; exact matching and category
  -- filtering are applied to the results instead (see the search providers).
  return query.searchString, query.minLevel, query.maxLevel, nil, nil, nil, page, nil, query.quality, false
end

function AuctionatorAHScanFrameMixin:OnLoad()
  self.scanRunning = false
  Auctionator.EventBus:RegisterSource(self, "AuctionatorAHScanFrameMixin")
end

function AuctionatorAHScanFrameMixin:IsOnLastPage()
  Auctionator.Debug.Message("AuctionatorAHScanFrameMixin:IsOnLastPage()")

  --Loaded all the terms from API
  return (
    (self.endPage ~= -1 and self.nextPage > self.endPage) or
    GetNumAuctionItems("list") < Auctionator.Constants.MaxResultsPerPage
  )
end

function AuctionatorAHScanFrameMixin:GotAllOwners()
  local result = true
  local allAuctions = Auctionator.AH.DumpAuctions("list")
  for _, auction in ipairs(allAuctions) do
    result = result and auction.info[Auctionator.Constants.AuctionItemInfo.Owner] ~= nil
  end

  return result
end

function AuctionatorAHScanFrameMixin:OnEvent(eventName, ...)
  if eventName == "AUCTION_ITEM_LIST_UPDATE" and self.waitingOnPage and self.sentQuery then
    -- Owner names can arrive in a later AUCTION_ITEM_LIST_UPDATE on 3.3.5a, so give
    -- them a couple of extra ticks to populate -- but NEVER hang the whole search
    -- waiting for an owner that never resolves. The proven old Auctionator engine
    -- processes the page regardless and simply accepts nil owners.
    if not self:GotAllOwners() and (self.ownerWaits or 0) < 2 then
      self.ownerWaits = (self.ownerWaits or 0) + 1
      return
    end
    self.ownerWaits = 0
    self.waitingOnPage = false
    self:ProcessSearchResults()
  end
end

function AuctionatorAHScanFrameMixin:ReceiveEvent(eventName, ...)
  if eventName == Auctionator.AH.Events.ThrottleAbort then
    self:AbortQuery()
  end
end

function AuctionatorAHScanFrameMixin:StartQuery(query, startPage, endPage)
  if self.scanRunning then
    error("Scan already running")
  end
  self:RegisterEvents()

  self.scanRunning = true

  self.nextPage = startPage
  self.endPage = endPage
  self.query = query
  self:DoNextSearchQuery()
end

function AuctionatorAHScanFrameMixin:AbortQuery()
  if self.scanRunning then
    Auctionator.AH.Queue:Remove(self.lastQueuedItem)
    self.scanRunning = false
    self:UnregisterEvents()
    Auctionator.EventBus:Fire(self, Auctionator.AH.Events.ScanAborted)
  end
end

function AuctionatorAHScanFrameMixin:DoNextSearchQuery()
  local page = self.nextPage
  self.sentQuery = false

  self.lastQueuedItem = function()
    self.sentQuery = true
    SortAuctionSetSort("list", "unitprice")
    QueryAuctionItems(ParamsForBlizzardAPI(self.query, page))
  end
  Auctionator.AH.Queue:Enqueue(self.lastQueuedItem)

  self.waitingOnPage = true
  self.nextPage = self.nextPage + 1

  Auctionator.EventBus:Fire(self, Auctionator.AH.Events.ScanPageStart, page)
end

function AuctionatorAHScanFrameMixin:ProcessSearchResults()
  Auctionator.Debug.Message("AuctionatorAHScanFrameMixin:ProcessSearchResults()")

  local results = self:GetCurrentPage()

  if self:IsOnLastPage() then
    self.scanRunning = false
    self:UnregisterEvents()
  else
    self:DoNextSearchQuery()
  end
  Auctionator.EventBus:Fire(self, Auctionator.AH.Events.ScanResultsUpdate, results, not self.scanRunning)
end

function AuctionatorAHScanFrameMixin:GetCurrentPage()
  local results = Auctionator.AH.DumpAuctions("list")
  for _, entry in ipairs(results) do
    entry.query = self.query
    entry.page = self.nextPage - 1
  end

  return results
end

function AuctionatorAHScanFrameMixin:RegisterEvents()
  FrameUtil.RegisterFrameForEvents(self, SCAN_EVENTS)

  Auctionator.EventBus:Register(self, {
    Auctionator.AH.Events.ThrottleAbort
  })
end

function AuctionatorAHScanFrameMixin:UnregisterEvents()
  FrameUtil.UnregisterFrameForEvents(self, SCAN_EVENTS)

  Auctionator.EventBus:Unregister(self, {
    Auctionator.AH.Events.ThrottleAbort
  })
end
