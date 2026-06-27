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
-- Event-driven adaptive throttle. The old code waited a fixed 0.5s between pages
-- (CanSendAuctionQuery() is briefly false right after a query), wasting ~0.5s/page.
-- Instead poll the gate every MIN_DELAY and send the next page the instant it opens;
-- only back off toward MAX_DELAY when the server hands back a stale/duplicate page.
local MIN_DELAY = 0.05    -- gate poll / fastest spacing
local MAX_DELAY = 0.75    -- backoff cap when the server is busy
local MAX_RETRIES = 12    -- give up on a single page after this many stale responses
local STUCK_TIMEOUT = 15  -- seconds with no accepted page -> abort as stuck

local AII = Auctionator.Constants.AuctionItemInfo

-- Link-only DB-key resolver for the full scan. The shared Auctionator.Utilities.DBKeyFromLink
-- calls IsGear() -> C_Item.GetItemInfoInstant() -> GetItemInfo() PER ROW; on 3.3.5a that shim
-- is GetItemInfo(), which for any uncached item returns nil AND queues a server item-info
-- request. Running it across all ~31000 scanned auctions floods the client item-query queue
-- and blocks a whole frame (the visible freeze "on complete"). It is also unnecessary: on the
-- LegacyAH path the only thing the gear branch adds is a "gr:<id>:<suffixString>" key, and that
-- key can ONLY exist when the item link carries a non-zero suffix in its 7th item-field. So we
-- parse the link directly (pure string work, zero API calls) and only emit the extra gear key
-- when there is an actual suffix to resolve -- identical output to DBKeyFromLink, no GetItemInfo.
local SuffixIDToSuffixStringID = Auctionator.Utilities.SuffixIDToSuffixStringID
local SuffixStringIDTOSuffixString = Auctionator.Utilities.SuffixStringIDTOSuffixString

local function ResolveDBKeysFast(itemLink)
  if itemLink == nil then
    return nil
  end
  local _, _, itemString = string.find(itemLink, "^|c%w+:?|H(.+)|h%[.*%]")
  if itemString == nil and string.find(itemLink, "^item") then
    itemString = itemLink
  end
  if itemString == nil then
    return nil
  end
  local linkType, itemId = strsplit(":", itemString)
  if linkType == "battlepet" then
    return { "p:" .. itemId }
  elseif linkType ~= "item" then
    return nil
  end

  -- Suffix is the 7th colon-delimited field of an item link (after the itemId, enchant and
  -- four gem slots). A 0 / absent suffix means no gear-suffix key is possible -> basic key only,
  -- which covers the overwhelming majority of auctions (trade goods, consumables, etc.).
  local suffix = tonumber((itemLink:match("item:.-:.-:.-:.-:.-:.-:(.-):")))
  if suffix and suffix ~= 0 then
    local suffixStringID = SuffixIDToSuffixStringID[suffix]
    local suffixString = suffixStringID and SuffixStringIDTOSuffixString[suffixStringID]
    if suffixString then
      return { "gr:" .. itemId .. ":" .. suffixString, itemId }
    end
  end
  return { itemId }
end

function AuctionatorFullScanFrameMixin:OnLoad()
  Auctionator.Debug.Message("AuctionatorFullScanFrameMixin:OnLoad")
  Auctionator.EventBus:RegisterSource(self, "AuctionatorFullScanFrameMixin")
  self.state = Auctionator.SavedState
end

function AuctionatorFullScanFrameMixin:ResetData()
  self.scanData = {}
end

-- On 3.3.5a a full scan is just a normal query repeated per page, so all we need
-- is the ability to send a query (no getAll, no server-side 15 min cooldown).
function AuctionatorFullScanFrameMixin:CanInitiate()
  return CanSendAuctionQuery() == true and not self.inProgress
end

function AuctionatorFullScanFrameMixin:InitiateScan()
  Auctionator.Debug.Message("FullScan: InitiateScan", "canQuery", tostring(CanSendAuctionQuery()), "inProgress", tostring(self.inProgress))
  -- Always give clear, user-visible feedback so a Full Scan click is never silent.
  if self.inProgress then
    Auctionator.Utilities.Message("|cffffd100Auctionator:|r Full scan already running.")
    return
  end
  if not CanSendAuctionQuery() then
    Auctionator.Utilities.Message("|cffffd100Auctionator:|r Auction house busy -- wait a few seconds, then click Full Scan again.")
    return
  end

  Auctionator.EventBus:Fire(self, Auctionator.FullScan.Events.ScanStart)
  self.state.TimeOfLastGetAllScan = time()

  self.inProgress = true
  self.currentPage = 0
  self.totalPages = 0
  self.totalAuctions = 0
  self.auctionsProcessed = 0
  self.scanStartTime = GetTime()
  self.lastAcceptTime = GetTime()
  self.speedSamples = {}
  self.scanDelay = MIN_DELAY
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

-- Live progress snapshot for the scan progress UI.
function AuctionatorFullScanFrameMixin:GetProgressInfo()
  local elapsed = self.scanStartTime and (GetTime() - self.scanStartTime) or 0
  local processed = self.auctionsProcessed or 0
  local total = self.totalAuctions or 0
  local auctionsPerSec = elapsed > 0 and (processed / elapsed) or 0

  -- Recent speed over the last ~15 pages -- distinguishes a real current slowdown from
  -- an early-average that was skewed high.
  local recentSpeed = auctionsPerSec
  local samples = self.speedSamples
  if samples and #samples >= 2 then
    local first, last = samples[1], samples[#samples]
    local dt = last.t - first.t
    if dt > 0 then
      recentSpeed = (last.a - first.a) / dt
    end
  end

  -- ETA uses recent speed (more representative of the current rate).
  local etaSpeed = recentSpeed > 0 and recentSpeed or auctionsPerSec
  local eta = 0
  if total > 0 and etaSpeed > 0 and processed < total then
    eta = (total - processed) / etaSpeed
  end
  return {
    inProgress = self.inProgress == true,
    currentPage = self.currentPage or 0,
    totalPages = self.totalPages or 0,
    totalAuctions = total,
    auctionsProcessed = processed,
    elapsed = elapsed,
    auctionsPerSec = auctionsPerSec,
    recentSpeed = recentSpeed,
    pagesPerSec = elapsed > 0 and ((self.currentPage or 0) / elapsed) or 0,
    eta = eta,
  }
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
  -- Watchdog: if no page has been accepted for STUCK_TIMEOUT, give up cleanly.
  if self.lastAcceptTime and (GetTime() - self.lastAcceptTime) > STUCK_TIMEOUT then
    Auctionator.Utilities.Message(string.format(
      "|cffff4040Auctionator:|r Full Scan aborted -- stuck on page %d (AH query throttle).",
      self.currentPage
    ))
    self:Abort()
    return
  end

  if CanSendAuctionQuery() then
    self.awaitingPage = true
    self.lastQueryTime = GetTime() -- for the per-page wait/process profile
    -- 3.3.5a signature: (name, minLevel, maxLevel, invType, class, subclass,
    --                    page, isUsable, qualityIndex) -- no getAll.
    Auctionator.Debug.Message("FullScan: QueryAuctionItems page", self.currentPage)
    QueryAuctionItems("", nil, nil, nil, nil, nil, self.currentPage, nil, nil)
  else
    -- Gate closed (just queried). Poll frequently and fire the moment it reopens.
    C_Timer.After(MIN_DELAY, function() self:QueryNextPage() end)
  end
end

-- Lightweight fingerprint of the current result list, to detect a duplicate page.
-- The full-list concat was wasteful (a second GetAuctionItemInfo pass over all 50 rows plus a
-- big string alloc EVERY page). A re-sent (stale) page on 3.3.5a is byte-identical, so sampling
-- a handful of anchor rows -- first, middle, last -- alongside the batch count is enough to spot
-- a duplicate while doing a fraction of the work on the hot path.
function AuctionatorFullScanFrameMixin:PageSignature(numBatch)
  local mid = math.floor((numBatch + 1) / 2)
  local parts = { numBatch }
  for _, x in ipairs({ 1, mid, numBatch }) do
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

  local procStart = GetTime()
  local waitTime = self.lastQueryTime and (procStart - self.lastQueryTime) or 0

  local numBatch, total = GetNumAuctionItems("list")
  Auctionator.Debug.Message("FullScan: ProcessPage page", self.currentPage, "numBatch", numBatch, "total", total)

  -- Empty response: on page 0 the server may just be slow -> retry; otherwise we
  -- have run off the end of the list.
  if numBatch == nil or numBatch == 0 or total == nil or total == 0 then
    if self.currentPage == 0 and self.retries < MAX_RETRIES then
      self.retries = self.retries + 1
      self.awaitingPage = false
      C_Timer.After(self.scanDelay, function() self:QueryNextPage() end)
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
    -- Stale/duplicate page = server is behind. Back off (up to MAX_DELAY) and re-query
    -- the SAME page, so we never hammer a busy server.
    self.retries = self.retries + 1
    self.scanDelay = math.min(MAX_DELAY, self.scanDelay * 1.5)
    self.awaitingPage = false
    C_Timer.After(self.scanDelay, function() self:QueryNextPage() end)
    return
  end

  -- Accept the page: store RAW page data only (auction info + link). DB-key resolution
  -- is deferred to EndProcessing -- DBKeyFromLink calls GetItemInfo per row, which for
  -- uncached items queues a client-side item query; doing that 31000x interleaved with
  -- the scan floods the client's item-query queue and progressively slows the scan.
  -- Deferring keeps per-page cost flat (cheap AH reads only).
  local scanData = self.scanData
  local n = #scanData -- hoist the length search out of the per-row loop (O(1) append)
  for x = 1, numBatch do
    local link = GetAuctionItemLink("list", x)
    if link then
      n = n + 1
      scanData[n] = { auctionInfo = { GetAuctionItemInfo("list", x) }, itemLink = link }
    end
  end

  self.prevPageSig = sig
  self.retries = 0
  -- Page accepted: recover the delay toward the minimum and reset the watchdog.
  self.scanDelay = math.max(MIN_DELAY, self.scanDelay * 0.7)
  self.lastAcceptTime = GetTime()
  self.auctionsProcessed = (self.auctionsProcessed or 0) + numBatch
  self.currentPage = self.currentPage + 1
  self.awaitingPage = false

  -- Recent-speed sample window (last ~15 accepted pages).
  local samples = self.speedSamples
  samples[#samples + 1] = { t = self.lastAcceptTime, a = self.auctionsProcessed }
  while #samples > 15 do
    table.remove(samples, 1)
  end

  -- Compact profile every 25 pages (debug only): proves whether per-page cost is flat
  -- (server-bound) or growing (addon-side). wait = AH response, process = addon work.
  if Auctionator.Debug.IsOn() and (self.currentPage % 25) == 0 then
    local p = self:GetProgressInfo()
    Auctionator.Debug.Message(string.format(
      "FullScan page=%d wait=%.2fs process=%.3fs delay=%.2fs mem=%dKB speed=%d/s recent=%d/s",
      self.currentPage, waitTime, GetTime() - procStart, self.scanDelay or 0,
      math.floor(collectgarbage("count")),
      math.floor(p.auctionsPerSec or 0), math.floor(p.recentSpeed or 0)
    ))
  end

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

-- Resolve DB keys and merge to lowest-buyout-per-key in a SINGLE pass over the raw scan data.
-- Uses the link-only resolver (no GetItemInfo), so even ~31000 rows stay cheap and never touch
-- the client item-query queue. Folding resolve + merge together also avoids materialising a
-- per-row dbKeys table for every auction (less GC churn on a big scan).
local function MergeInfo(scanData)
  local allInfo = {}
  for index = 1, #scanData do
    local entry = scanData[index]
    local auctionInfo = entry.auctionInfo
    local available = auctionInfo[AII.Quantity]
    local buyoutPrice = auctionInfo[AII.Buyout]
    if available and available > 0 and buyoutPrice and buyoutPrice ~= 0 then
      local dbKeys = ResolveDBKeysFast(entry.itemLink)
      if dbKeys then
        local effectivePrice = math.ceil(buyoutPrice / available)
        for k = 1, #dbKeys do
          local dbKey = dbKeys[k]
          local bucket = allInfo[dbKey]
          if bucket == nil then
            bucket = {}
            allInfo[dbKey] = bucket
          end
          bucket[#bucket + 1] = { price = effectivePrice, available = available }
        end
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

  -- ProcessScan returns the number of DISTINCT items priced (e.g. ~2453), which is
  -- confusing next to the ~31000 auctions the panel reported. Show both so the count is
  -- unambiguous and consistent with the progress panel.
  local count = Auctionator.Database:ProcessScan(MergeInfo(self.scanData))
  Auctionator.Utilities.Message(string.format(
    "|cffffd100Auctionator:|r Full Scan complete -- %d auctions scanned, %d items priced.",
    self.auctionsProcessed or 0, count
  ))

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
