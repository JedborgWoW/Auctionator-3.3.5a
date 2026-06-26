AuctionatorFullScanFrameMixin = {}

-- Stock 3.3.5a (client 12340) has NO getAll auction query (that was added in
-- Cataclysm). The whole-AH scan must therefore walk the result list PAGE BY PAGE
-- and merge the lowest prices itself -- the technique the original native 3.3.5a
-- Auctionator (Zirco) used. The 3.3.5a server also occasionally returns a stale
-- (duplicate) page for a query, so each page is checked against the previous one
-- and re-queried if identical.

local FULL_SCAN_EVENTS = {
  "AUCTION_ITEM_LIST_UPDATE",
  "AUCTION_HOUSE_CLOSED",
}

local PAGE_SIZE = Auctionator.Constants.MaxResultsPerPage -- 50 on 3.3.5a
local RETRY_DELAY = 0.5   -- seconds before re-querying a not-ready / duplicate page
local MAX_RETRIES = 12    -- give up on a page after this many stale responses

local AII = Auctionator.Constants.AuctionItemInfo

function AuctionatorFullScanFrameMixin:OnLoad()
  Auctionator.Debug.Message("AuctionatorFullScanFrameMixin:OnLoad")
  Auctionator.EventBus:RegisterSource(self, "AuctionatorFullScanFrameMixin")
  self.state = Auctionator.SavedState
end

function AuctionatorFullScanFrameMixin:ResetData()
  self.scanData = {}
  self.dbKeysMapping = {}
end

-- On 3.3.5a a full scan is just a normal query repeated per page, so all we need
-- is the ability to send a query (no getAll, no server-side 15 min cooldown).
function AuctionatorFullScanFrameMixin:CanInitiate()
  return CanSendAuctionQuery() == true and not self.inProgress
end

function AuctionatorFullScanFrameMixin:InitiateScan()
  if not self:CanInitiate() then
    Auctionator.Utilities.Message(self:NextScanMessage())
    return
  end

  Auctionator.EventBus:Fire(self, Auctionator.FullScan.Events.ScanStart)
  self.state.TimeOfLastGetAllScan = time()

  self.inProgress = true
  self.currentPage = 0
  self.totalPages = 0
  self.totalAuctions = 0
  self.retries = 0
  self.prevPageSig = nil
  self.awaitingPage = false
  self:ResetData()

  self:RegisterForEvents()
  Auctionator.Utilities.Message(AUCTIONATOR_L_STARTING_FULL_SCAN)

  -- Patch to prevent an error from the classic AH code path for unknown qualities
  if not ITEM_QUALITY_COLORS[-1] then
    ITEM_QUALITY_COLORS[-1] = {r = 0, b = 0, g = 0}
  end

  -- Clear any server sort so pages come back in a stable order.
  SortAuctionClearSort("list")

  Auctionator.EventBus:Fire(self, Auctionator.FullScan.Events.ScanProgress, 0.01)
  self:QueryNextPage()
end

function AuctionatorFullScanFrameMixin:NextScanMessage()
  -- Only reached when CanSendAuctionQuery() is false (throttled); keep the
  -- original localized message shape.
  local timeSinceLastScan = time() - (self.state.TimeOfLastGetAllScan or 0)
  local minutesUntilNextScan = math.max(0, 1 - math.ceil(timeSinceLastScan / 60))
  local secondsUntilNextScan = math.max(0, (60 - timeSinceLastScan) % 60)
  return AUCTIONATOR_L_NEXT_SCAN_MESSAGE:format(minutesUntilNextScan, secondsUntilNextScan)
end

-- During the scan we must stop the regular search/throttle frames from reacting to our
-- per-page AUCTION_ITEM_LIST_UPDATE events (they would treat the results as a user
-- search). The retail code used GetFramesRegisteredForEvent -- a Cataclysm (4.0) API
-- that is NIL on stock 3.3.5a, so it errored here and the scan never started. On 3.3.5a
-- the only listeners that matter are Auctionator's own AH frames, so suppress those by
-- reference (IsEventRegistered/UnregisterEvent are native) and restore them afterwards.
function AuctionatorFullScanFrameMixin:RegisterForEvents()
  self.suppressedFrames = {}
  local internals = Auctionator.AH.Internals
  local candidates = {}
  if internals then
    if internals.scan then table.insert(candidates, internals.scan) end
    if internals.throttling then table.insert(candidates, internals.throttling) end
  end
  for _, f in ipairs(candidates) do
    if f.IsEventRegistered and f:IsEventRegistered("AUCTION_ITEM_LIST_UPDATE") then
      f:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
      table.insert(self.suppressedFrames, f)
    end
  end
  FrameUtil.RegisterFrameForEvents(self, FULL_SCAN_EVENTS)
  Auctionator.Debug.Message("FullScan: registered events; suppressed", #self.suppressedFrames, "frames")
end

function AuctionatorFullScanFrameMixin:UnregisterForEvents()
  FrameUtil.UnregisterFrameForEvents(self, FULL_SCAN_EVENTS)
  if self.suppressedFrames then
    for _, f in ipairs(self.suppressedFrames) do
      f:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
    end
    self.suppressedFrames = nil
  end
end

function AuctionatorFullScanFrameMixin:QueryNextPage()
  if not self.inProgress then
    return
  end
  if CanSendAuctionQuery() then
    self.awaitingPage = true
    -- 3.3.5a signature: (name, minLevel, maxLevel, invType, class, subclass,
    --                    page, isUsable, qualityIndex) -- no getAll.
    Auctionator.Debug.Message("FullScan: QueryAuctionItems page", self.currentPage)
    QueryAuctionItems("", nil, nil, nil, nil, nil, self.currentPage, nil, nil)
  else
    Auctionator.Debug.Message("FullScan: throttled, retrying page", self.currentPage)
    C_Timer.After(RETRY_DELAY, function() self:QueryNextPage() end)
  end
end

-- Lightweight fingerprint of the current result list, to detect a duplicate page.
function AuctionatorFullScanFrameMixin:PageSignature(numBatch)
  local parts = {}
  for x = 1, numBatch do
    local name, _, count, _, _, _, minBid, _, buyout, bid = GetAuctionItemInfo("list", x)
    parts[#parts + 1] = (name or "?") .. "/" .. (count or 0) .. "/" ..
      (minBid or 0) .. "/" .. (buyout or 0) .. "/" .. (bid or 0)
  end
  return table.concat(parts, "|")
end

function AuctionatorFullScanFrameMixin:OnEvent(event, ...)
  Auctionator.Debug.Message("FullScan: event", event, "inProgress", self.inProgress, "awaiting", self.awaitingPage)
  if event == "AUCTION_ITEM_LIST_UPDATE" then
    if self.inProgress and self.awaitingPage then
      self:ProcessPage()
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    self:Abort()
  end
end

function AuctionatorFullScanFrameMixin:ProcessPage()
  if not self.inProgress then
    return
  end

  local numBatch, total = GetNumAuctionItems("list")
  Auctionator.Debug.Message("FullScan: ProcessPage page", self.currentPage, "numBatch", numBatch, "total", total)

  -- Empty response: on page 0 the server may just be slow -> retry; otherwise we
  -- have run off the end of the list.
  if numBatch == nil or numBatch == 0 or total == nil or total == 0 then
    if self.currentPage == 0 and self.retries < MAX_RETRIES then
      self.retries = self.retries + 1
      self.awaitingPage = false
      C_Timer.After(RETRY_DELAY, function() self:QueryNextPage() end)
      return
    end
    self.awaitingPage = false
    self:EndProcessing()
    return
  end

  self.totalAuctions = total
  self.totalPages = math.max(1, math.ceil(total / PAGE_SIZE))

  -- Duplicate/stale page guard: if the server handed back the same page contents
  -- as last time, re-query (up to a limit) instead of accepting it.
  local sig = self:PageSignature(numBatch)
  if self.prevPageSig ~= nil and sig == self.prevPageSig and self.retries < MAX_RETRIES then
    self.retries = self.retries + 1
    self.awaitingPage = false
    C_Timer.After(RETRY_DELAY, function() self:QueryNextPage() end)
    return
  end

  -- Accept the page: accumulate each auction (DBKeyFromLink is synchronous on the
  -- LegacyAH path, so this completes in-line).
  for x = 1, numBatch do
    local info = { GetAuctionItemInfo("list", x) }
    local link = GetAuctionItemLink("list", x)
    if link then
      Auctionator.Utilities.DBKeyFromLink(link, function(dbKeys)
        if #dbKeys > 0 then
          table.insert(self.scanData, { auctionInfo = info, itemLink = link })
          table.insert(self.dbKeysMapping, dbKeys)
        end
      end)
    end
  end

  self.prevPageSig = sig
  self.retries = 0
  self.currentPage = self.currentPage + 1
  self.awaitingPage = false

  Auctionator.EventBus:Fire(
    self,
    Auctionator.FullScan.Events.ScanProgress,
    math.min(0.99, self.currentPage / self.totalPages)
  )

  if self.currentPage >= self.totalPages then
    self:EndProcessing()
  else
    self:QueryNextPage()
  end
end

local function GetInfo(auctionInfo)
  local available = auctionInfo[AII.Quantity]
  local buyoutPrice = auctionInfo[AII.Buyout]
  if not available or available == 0 or not buyoutPrice then
    return 0, 0
  end
  return math.ceil(buyoutPrice / available), available
end

local function MergeInfo(scanData, dbKeysMapping)
  local allInfo = {}
  for index = 1, #scanData do
    local effectivePrice, available = GetInfo(scanData[index].auctionInfo)
    if available > 0 and effectivePrice ~= 0 then
      for _, dbKey in ipairs(dbKeysMapping[index]) do
        if allInfo[dbKey] == nil then
          allInfo[dbKey] = {}
        end
        table.insert(allInfo[dbKey], { price = effectivePrice, available = available })
      end
    end
  end
  return allInfo
end

function AuctionatorFullScanFrameMixin:EndProcessing()
  if not self.inProgress then
    return
  end

  local rawFullScan = self.scanData

  local count = Auctionator.Database:ProcessScan(MergeInfo(self.scanData, self.dbKeysMapping))
  Auctionator.Utilities.Message(AUCTIONATOR_L_FINISHED_PROCESSING:format(count))

  self.inProgress = false
  self.awaitingPage = false
  self:UnregisterForEvents()

  Auctionator.EventBus:Fire(self, Auctionator.FullScan.Events.ScanProgress, 1)
  Auctionator.EventBus:Fire(self, Auctionator.FullScan.Events.ScanComplete, rawFullScan)

  self:ResetData()
end

function AuctionatorFullScanFrameMixin:Abort()
  self:UnregisterForEvents()
  if self.inProgress then
    self.inProgress = false
    self.awaitingPage = false
    self:ResetData()
    Auctionator.Utilities.Message(
      AUCTIONATOR_L_FULL_SCAN_FAILED .. " " .. self:NextScanMessage()
    )
    Auctionator.EventBus:Fire(self, Auctionator.FullScan.Events.ScanFailed)
  end
end
