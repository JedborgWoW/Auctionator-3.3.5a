AuctionatorSellingTabMixin = {}

function AuctionatorSellingTabMixin:OnLoad()
  self:ApplyHiding()

  Auctionator.Groups.OnAHOpen()
  local defaultIconSize = Auctionator.Config.Defaults[Auctionator.Config.Options.SELLING_ICON_SIZE]
  local currentIconSize = Auctionator.Config.Get(Auctionator.Config.Options.SELLING_ICON_SIZE)
  local defaultIconsPerRow = 6
  self.BagListing:SetWidth(math.ceil(defaultIconsPerRow * defaultIconSize / currentIconSize ) * currentIconSize + self.BagListing.View.ScrollBar:GetWidth() + 4 * 2)

  self.BuyFrame:Init()

  -- The Selling frame has no XML OnShow, so wire visual normalization here. It runs every
  -- time the tab is shown and re-asserts a layout that matches the Cancelling tab.
  self:SetScript("OnShow", self.NormalizeVisuals)
end

-- Match the Cancelling tab visually (the source of truth). Two concrete corrections:
--   1. The result panel was anchored to the bag top (~10px below it), so its dark inset
--      (which extends 25px up over its header) intruded into the price-input fields above
--      -- the "result panel jammed into the top input area". Re-anchor it LOWER so there is
--      a clear gap below the inputs.
--   2. Re-wrap the result listing with its inset using Cancelling's exact margins and keep
--      the inset strictly behind the header/rows/footer.
-- Applied from Lua because the 3.3.5a XML parser does not reliably honour the authored
-- (inherited / dotted) anchors. Does NOT touch posting logic or the price-input wiring.
function AuctionatorSellingTabMixin:NormalizeVisuals()
  -- 1. Clear gap between the price inputs and the result panel.
  local showBag = Auctionator.Config.Get(Auctionator.Config.Options.SHOW_SELLING_BAG)
  self.BuyFrame:ClearAllPoints()
  if showBag then
    self.BuyFrame:SetPoint("TOPLEFT", self.BagListing, "TOPRIGHT", 14, -25)
  else
    self.BuyFrame:SetPoint("TOPLEFT", self, "TOPLEFT", 24, -205)
  end
  self.BuyFrame:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)

  -- 2. Result panel inset + headers, matching Cancelling.
  local prices = self.BuyFrame and self.BuyFrame.CurrentPrices
  if prices then
    Auctionator.Visual.NormalizeResultsPanel(prices.Inset, prices.SearchResultsListing)
    Auctionator.Visual.NormalizeHeaders(prices.SearchResultsListing)
    Auctionator.Visual.RaiseAbove(prices.CancelButton, prices.Inset)
    Auctionator.Visual.RaiseAbove(prices.BuyButton, prices.Inset)
    Auctionator.Visual.RaiseAbove(prices.RefreshButton, prices.Inset)
  end

  -- The bag's own dark inset stays behind the bag listing.
  if self.BagInset then
    Auctionator.Visual.SendToBack(self.BagInset, self.BagListing)
  end
end

function AuctionatorSellingTabMixin:ApplyHiding()
  if not Auctionator.Config.Get(Auctionator.Config.Options.SHOW_SELLING_BAG) then
    self.BagListing:Hide()
    self.BagInset:Hide()
    self.BuyFrame:SetPoint("TOPLEFT", self.BagListing, "TOPLEFT", 10, 10)
    self.BuyFrame.HistoryButton:SetPoint("LEFT", AuctionFrameMoneyFrame, "RIGHT")
  end
end

function AuctionatorSellingTabMixin:OnHide()
  self:Hide()
end
