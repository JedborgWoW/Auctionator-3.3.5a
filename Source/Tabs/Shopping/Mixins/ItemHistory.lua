AuctionatorItemHistoryFrameMixin = CreateFromMixins(AuctionatorEscapeToCloseMixin)

function AuctionatorItemHistoryFrameMixin:OnLoad()
  -- WotLK 3.3.5a: this dialog inherits AuctionatorSimplePanelTemplate whose rock-file
  -- background is absent (rendered GREEN) and whose metal border is invisible. Apply a
  -- real opaque DialogBox backdrop so the frame is solid and bordered.
  Auctionator.Theme.ApplyOpaqueDialogBackdrop(self)

  -- The inner results panel (self.Inset, AuctionatorInsetDarkTemplate) has its dark Bg
  -- texture authored with relativeKey="$parent" anchors, which the 3.3.5a XML parser does
  -- not reliably resolve -- so the fill renders mis-sized and "bleeds". Pin it explicitly
  -- to the inset and flatten it (hide the bevel border) for a clean solid dark panel,
  -- matching the Shopping results panel fix.
  local inset = self.Inset
  if inset then
    if inset.Bg then
      inset.Bg:ClearAllPoints()
      inset.Bg:SetAllPoints(inset)
      inset.Bg:SetTexture(0.04, 0.04, 0.05, 1.0)
    end
    local border = select(1, inset:GetChildren())
    if border and border.Hide then
      border:Hide()
    end
  end
end

function AuctionatorItemHistoryFrameMixin:Init()
  self.ResultsListing:Init(self.DataProvider)

  Auctionator.EventBus:Register(self, { Auctionator.Shopping.Tab.Events.ShowHistoricalPrices })
  self.isDocked = false
end

function AuctionatorItemHistoryFrameMixin:OnShow()
  Auctionator.Debug.Message("AuctionatorItemHistoryFrameMixin:OnShow()")

  Auctionator.EventBus
    :RegisterSource(self, "lists item history dialog")
    :Fire(self, Auctionator.Shopping.Tab.Events.DialogOpened)
    :UnregisterSource(self)
end

function AuctionatorItemHistoryFrameMixin:OnHide()
  self:Hide()

  Auctionator.EventBus
    :RegisterSource(self, "lists item history 1")
    :Fire(self, Auctionator.Shopping.Tab.Events.DialogClosed)
    :UnregisterSource(self)
end

function AuctionatorItemHistoryFrameMixin:ReceiveEvent(event, itemInfo)
  if event == Auctionator.Shopping.Tab.Events.ShowHistoricalPrices then
    self.Title:SetText(AUCTIONATOR_L_X_PRICE_HISTORY:format(itemInfo.name))
  end
end

function AuctionatorItemHistoryFrameMixin:OnDockDialogClicked()
  self:ClearAllPoints()
  if self.isDocked then
    self:SetPoint("CENTER", self:GetParent(), "CENTER")
    --Reset flipping
    self.Dock.Arrow:SetTexCoord(0, 1, 0, 1)
  else
    self:SetPoint("LEFT", AuctionHouseFrame or AuctionFrame, "RIGHT")
    --Flip the texture to point back in
    self.Dock.Arrow:SetTexCoord(1, 0, 0, 1)
  end

  self.isDocked = not self.isDocked
end

function AuctionatorItemHistoryFrameMixin:OnCloseDialogClicked()
  self:Hide()
end
