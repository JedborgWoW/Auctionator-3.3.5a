AuctionatorCancellingListResultsRowMixin = CreateFromMixins(AuctionatorResultsRowTemplateMixin)

-- CancelAuction is rejected from this ScrollBox-pooled row's own click on the user's server
-- (ADDON_ACTION_BLOCKED), but works from a button defined in the frame's XML (proven by the
-- Cancel Undercut button). So cancelling is driven by a single XML "Cancel" button
-- (AuctionatorCancellingFrameMixin.RowCancelButton) that the row shows on hover -- clicking that
-- button, not the row, issues the cancel. The row itself only handles modified clicks.

function AuctionatorCancellingListResultsRowMixin:OnClick(button, ...)
  if IsModifiedClick("DRESSUP") then
    DressUpLink(self.rowData.itemLink)
  elseif IsModifiedClick("CHATLINK") then
    Auctionator.Utilities.InsertLink(self.rowData.itemLink)
  end
end

function AuctionatorCancellingListResultsRowMixin:OnEnter()
  AuctionatorResultsRowTemplateMixin.OnEnter(self)
  if Auctionator.Cancelling.frame then
    Auctionator.Cancelling.frame:ShowRowCancelButton(self)
  end
end

function AuctionatorCancellingListResultsRowMixin:OnLeave()
  AuctionatorResultsRowTemplateMixin.OnLeave(self)
  if Auctionator.Cancelling.frame then
    Auctionator.Cancelling.frame:ScheduleHideRowCancelButton()
  end
end

function AuctionatorCancellingListResultsRowMixin:Populate(rowData, dataIndex)
  AuctionatorResultsRowTemplateMixin.Populate(self, rowData, dataIndex)

  -- This pooled row may be getting reused for a different auction while the hover Cancel button
  -- is still attached to it -- detach so the button can't act on the wrong auction.
  if Auctionator.Cancelling.frame then
    Auctionator.Cancelling.frame:DetachRowCancelButton(self)
  end

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
