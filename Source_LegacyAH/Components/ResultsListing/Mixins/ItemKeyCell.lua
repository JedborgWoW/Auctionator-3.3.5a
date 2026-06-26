AuctionatorItemKeyCellTemplateMixin = CreateFromMixins(AuctionatorCellMixin, AuctionatorRetailImportTableBuilderCellMixin)

function AuctionatorItemKeyCellTemplateMixin:Init()
  self.Text:SetJustifyH("LEFT")
end

function AuctionatorItemKeyCellTemplateMixin:Populate(rowData, index)
  AuctionatorCellMixin.Populate(self, rowData, index)

  self.Text:SetText(rowData.itemName or "")

  -- Always set an icon. Cells are pooled, so a nil iconTexture used to leave the
  -- PREVIOUS row's icon (or blank) in place -- the "only some items have icons" bug
  -- for items the client had not cached yet. GetItemIconSafe gives a placeholder now
  -- and the real icon resolves on GET_ITEM_INFO_RECEIVED (see GetItemIconSafe.lua).
  self.Icon:SetTexture(rowData.iconTexture or Auctionator.Utilities.GetItemIconSafe(rowData.itemLink or rowData.itemString))
  self.Icon:SetVertexColor(1, 1, 1, 1)
  self.Icon:Show()

  self.Icon:SetAlpha(rowData.noneAvailable and 0.5 or 1.0)
end

function AuctionatorItemKeyCellTemplateMixin:OnEnter()
  if self.rowData.itemLink then
    GameTooltip:SetOwner(self:GetParent(), "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.rowData.itemLink)
    GameTooltip:Show()
  end
  AuctionatorCellMixin.OnEnter(self)
end

function AuctionatorItemKeyCellTemplateMixin:OnLeave()
  if self.rowData.itemLink then
    GameTooltip:Hide()
  end
  AuctionatorCellMixin.OnLeave(self)
end
