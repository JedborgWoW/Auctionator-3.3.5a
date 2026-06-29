AuctionatorBuyFrameMixin = {}

function AuctionatorBuyFrameMixin:Init()
  Auctionator.EventBus:RegisterSource(self, "AuctionatorBuyFrameMixin")
  self.CurrentPrices:Init()
  self.HistoryPrices:Init()
end

function AuctionatorBuyFrameMixin:Reset()
  if self.HistoryPrices:IsShown() then
    self:ToggleHistory()
  end

  self.HistoryPrices:Reset()
  self.CurrentPrices:Reset()
end

function AuctionatorBuyFrameMixin:ToggleHistory()
  self.HistoryPrices:SetShown(not self.HistoryPrices:IsShown())
  self.CurrentPrices:SetShown(not self.CurrentPrices:IsShown())

  if self.HistoryPrices:IsShown() then
    self.HistoryButton:SetText(AUCTIONATOR_L_CURRENT)
  else
    self.HistoryButton:SetText(AUCTIONATOR_L_HISTORY)
  end
end

AuctionatorBuyFrameMixinForShopping = CreateFromMixins(AuctionatorBuyFrameMixin)

function AuctionatorBuyFrameMixinForShopping:Init()
  AuctionatorBuyFrameMixin.Init(self)
  Auctionator.EventBus:Register(self, {
    Auctionator.Buying.Events.ShowForShopping,
    Auctionator.Shopping.Tab.Events.SearchStart,
  })
end

function AuctionatorBuyFrameMixinForShopping:OnShow()
  self:GetParent().ResultsListing:Hide()
  self:GetParent().ExportCSV:Hide()
  self:GetParent().ShoppingResultsInset:Hide()
  self.wasParentLoadAllPagesVisible = self:GetParent().LoadAllPagesButton:IsShown()
  self:GetParent().LoadAllPagesButton:Hide()
end

function AuctionatorBuyFrameMixinForShopping:OnHide()
  self:Hide()

  self:GetParent().ResultsListing:Show()
  self:GetParent().ExportCSV:Show()
  self:GetParent().ShoppingResultsInset:Show()
  self:GetParent().LoadAllPagesButton:SetShown(self.wasParentLoadAllPagesVisible)
end

function AuctionatorBuyFrameMixinForShopping:ReceiveEvent(eventName, eventData, ...)
  if eventName == Auctionator.Buying.Events.ShowForShopping then
    self:Show()

    self:Reset()

    if #eventData.entries > 0 then
      self.CurrentPrices.SearchDataProvider:SetQuery(eventData.entries[1].itemLink, function() 
        self.HistoryPrices.RealmHistoryDataProvider:SetItemLink(eventData.entries[1].itemLink)
        self.HistoryPrices.PostingHistoryDataProvider:SetItemLink(eventData.entries[1].itemLink)
      end)
    else
      self.CurrentPrices.SearchDataProvider:SetQuery(nil, function() end)
      self.HistoryPrices.RealmHistoryDataProvider:SetItemLink(nil)
      self.HistoryPrices.PostingHistoryDataProvider:SetItemLink(nil)
    end
    -- Always load EVERY page for the focused item before showing prices. On stock
    -- 3.3.5a the AH cannot be sorted server-side by unit price, so the shopping rows we
    -- were seeded with (page 1 only, unless the term was scanned in full) are NOT
    -- guaranteed to contain the cheapest auction. Rescanning all pages here makes the
    -- cheapest unit price show first and ensures "Load higher prices" can never reveal a
    -- cheaper auction than what is already displayed -- which is the whole point of the
    -- buy view (mis-ordering here is a buying hazard).
    self.CurrentPrices.SearchDataProvider:SetRequestAllResults(true)
    if not eventData.complete then
      -- These rows came from a search that stopped at page 1. Do a fresh all-pages scan
      -- of just this item and show the loading spinner meanwhile, rather than a partial
      -- (and possibly mis-ordered) list.
      self.CurrentPrices.SearchDataProvider:RefreshQuery()
    else
      -- The shopping search already collected every page for this term, so these entries
      -- are the complete set -- display them (sorted cheapest-unit-price-first) directly.
      self.CurrentPrices.SearchDataProvider:SetAuctions(eventData.entries)
      self.CurrentPrices.gotCompleteResults = true
      self.CurrentPrices:UpdateButtons()
    end
  elseif eventName == Auctionator.Shopping.Tab.Events.SearchStart then
    self:Hide()
  end
end

AuctionatorBuyFrameMixinForSelling = CreateFromMixins(AuctionatorBuyFrameMixin)
local AUCTION_EVENTS = {
  "AUCTION_OWNED_LIST_UPDATE",
}

function AuctionatorBuyFrameMixinForSelling:Init()
  AuctionatorBuyFrameMixin.Init(self)
  Auctionator.EventBus:Register(self, {
    Auctionator.Selling.Events.RefreshBuying,
    Auctionator.Selling.Events.RefreshHistoryOnly,
    Auctionator.Selling.Events.StartFakeBuyLoading,
    Auctionator.Selling.Events.StopFakeBuyLoading,
    Auctionator.Selling.Events.AuctionCreated,
  })
end

function AuctionatorBuyFrameMixinForSelling:Reset()
  AuctionatorBuyFrameMixin.Reset(self)

  self.CurrentPrices.SearchDataProvider:SetIgnoreItemSuffix(Auctionator.Config.Get(Auctionator.Config.Options.SELLING_IGNORE_ITEM_SUFFIX))
  self.waitingOnNewAuction = false
end

function AuctionatorBuyFrameMixinForSelling:OnShow()
  FrameUtil.RegisterFrameForEvents(self, AUCTION_EVENTS)
  self:Reset()
end

function AuctionatorBuyFrameMixinForSelling:OnHide()
  FrameUtil.UnregisterFrameForEvents(self, AUCTION_EVENTS)
end

function AuctionatorBuyFrameMixinForSelling:ReceiveEvent(eventName, eventData, ...)
  if eventName == Auctionator.Selling.Events.RefreshBuying then
    self:Reset()

    self.HistoryPrices.RealmHistoryDataProvider:SetItemLink(eventData.itemLink)
    self.HistoryPrices.PostingHistoryDataProvider:SetItemLink(eventData.itemLink)
    self.CurrentPrices.SearchDataProvider:SetQuery(eventData.itemLink, function()
      self.CurrentPrices.SearchDataProvider:SetRequestAllResults(Auctionator.Config.Get(Auctionator.Config.Options.SELLING_ALWAYS_LOAD_MORE))
      self.CurrentPrices.SearchDataProvider:RefreshQuery()
    end)

    self.CurrentPrices.RefreshButton:Enable()
    self.HistoryButton:Enable()
  elseif eventName == Auctionator.Selling.Events.RefreshHistoryOnly then
    self.HistoryPrices.RealmHistoryDataProvider:SetItemLink(eventData.itemLink)
    self.HistoryPrices.PostingHistoryDataProvider:SetItemLink(eventData.itemLink)
  elseif eventName == Auctionator.Selling.Events.StartFakeBuyLoading then
    -- Used so that it is clear something is loading, even if the search can't
    -- be sent yet.
    self.HistoryPrices.RealmHistoryDataProvider:SetItemLink(eventData.itemLink)
    self.HistoryPrices.PostingHistoryDataProvider:SetItemLink(eventData.itemLink)
    self.CurrentPrices.SearchDataProvider:SetQuery(eventData.itemLink, function() end)
    self.CurrentPrices.SearchDataProvider.onSearchStarted()
  elseif eventName == Auctionator.Selling.Events.StopFakeBuyLoading then
    self.CurrentPrices.SearchDataProvider.onSearchEnded()
    self:Reset()
    self.CurrentPrices.RefreshButton:Disable()
    self.HistoryButton:Disable()
  elseif eventName == Auctionator.Selling.Events.AuctionCreated then
    self.waitingOnNewAuction = true
  end
end

function AuctionatorBuyFrameMixinForSelling:OnEvent(eventName, ...)
  if eventName == "AUCTION_OWNED_LIST_UPDATE" and self.waitingOnNewAuction then
    self.waitingOnNewAuction = false
    self.CurrentPrices.SearchDataProvider:PurgeAndReplaceOwnedAuctions(Auctionator.AH.DumpAuctions("owner"))
  end
end
