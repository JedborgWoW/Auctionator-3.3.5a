AuctionatorCancellingListResultsRowMixin = CreateFromMixins(AuctionatorResultsRowTemplateMixin)

function AuctionatorCancellingListResultsRowMixin:OnClick(button, ...)
  -- A click only cancels when the throttle is free (gate below). If a background undercut
  -- scan / pending action holds the throttle, the click is dropped here -- which is why a
  -- row-click "did nothing" while Cancel Undercut (scan-aware) worked.
  Auctionator.Debug.Message(
    "AuctionatorCancellingListResultsRowMixin:OnClick", button,
    "throttleReady", Auctionator.AH.IsNotThrottled(),
    self.rowData and self.rowData.itemLink
  )

  if IsModifiedClick("DRESSUP") then
    DressUpLink(self.rowData.itemLink);

  elseif IsModifiedClick("CHATLINK") then
    Auctionator.Utilities.InsertLink(self.rowData.itemLink)

  elseif (button == "LeftButton" or button == "RightButton") and Auctionator.AH.IsNotThrottled() then
    -- Either mouse button cancels the auction (right-click added as a quick alternative to
    -- left-click; a plain right-click no longer fires a Shopping search -- that only ever
    -- created an unwanted "Cancelling (temporary)" shopping list).
    --
    -- Cancel DIRECTLY here, in the row's own mouse-click handler, instead of firing an
    -- EventBus event for the Cancelling frame to handle. CancelAuction must run inside the
    -- synchronous execution of the hardware click; EventBus:Fire wraps each handler in pcall
    -- (and securecall behaves no better), which drops the hardware-event/secure status, so the
    -- client rejects the cancel with "Interface action failed because of an AddOn" and the
    -- auction is never cancelled. A direct call -- exactly what the native Zirco Auctionator
    -- does from its cancel button -- keeps that status intact.
    local auctionData = self.rowData

    -- Auctions someone has bid on cost gold to cancel; confirm first (same as the frame path).
    local cancelCost = math.floor(((auctionData.bidAmount or 0) * (AUCTION_CANCEL_COST or 0)) / 100)
    if cancelCost > 0 then
      local dialog = StaticPopup_Show("AuctionatorConfirmBidPricePopupDialog")
      if dialog then
        dialog.data = auctionData
        MoneyFrame_Update(dialog.moneyFrame, cancelCost)
      end
    else
      auctionData.cancelled = true
      self:ApplyFade()
      Auctionator.AH.CancelAuction(auctionData)
      -- Post-cancel UI refresh only (not a protected action) -- safe to route through the bus.
      Auctionator.EventBus
        :RegisterSource(self, "CancellingListResultRow")
        :Fire(self, Auctionator.Cancelling.Events.CancelConfirmed, auctionData)
        :UnregisterSource(self)
    end
  end
end

function AuctionatorCancellingListResultsRowMixin:OnEnter()
  if Auctionator.AH.IsNotThrottled() then
    AuctionatorResultsRowTemplateMixin.OnEnter(self)
  end
end

function AuctionatorCancellingListResultsRowMixin:OnLeave()
  AuctionatorResultsRowTemplateMixin.OnLeave(self)
end

function AuctionatorCancellingListResultsRowMixin:Populate(rowData, dataIndex)
  AuctionatorResultsRowTemplateMixin.Populate(self, rowData, dataIndex)

  self:ApplyFade()
  self:ApplyUndercutHighlight()
end

function AuctionatorCancellingListResultsRowMixin:ApplyFade()
  --Fade while waiting for the cancel to take effect
  if self.rowData.cancelled then
    self:SetAlpha(0.5)
  else
    self:SetAlpha(1)
  end
end

function AuctionatorCancellingListResultsRowMixin:ApplyUndercutHighlight()
  self.SelectedHighlight:SetShown(self.rowData.undercut == AUCTIONATOR_L_UNDERCUT_YES)
end

function AuctionatorCancellingListResultsRowMixin:ApplyBidderHighlight()
  self.BidderHighlight:SetShown(self.rowData.bidder ~= nil)
end
