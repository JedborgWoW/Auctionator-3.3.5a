AuctionatorItemKeyCellTemplateMixin = CreateFromMixins(AuctionatorCellMixin, AuctionatorRetailImportTableBuilderCellMixin)

function AuctionatorItemKeyCellTemplateMixin:Init()
  self.Text:SetJustifyH("LEFT")
end

function AuctionatorItemKeyCellTemplateMixin:Populate(rowData, index)
  AuctionatorCellMixin.Populate(self, rowData, index)

  self.Text:SetText(rowData.itemName or "")

  -- Always set a VALID icon. Cells are pooled, so a missing icon used to leave the
  -- PREVIOUS row's icon (or blank) in place -- the "only some items have icons" bug
  -- for items the client had not cached yet. A non-string iconTexture (numeric fileID)
  -- would render green, so accept it only when it is a string; otherwise resolve
  -- through GetItemIconSafe (real icon once cached, else a question-mark placeholder
  -- that the GET_ITEM_INFO_RECEIVED refresh later replaces).
  local icon = rowData.iconTexture
  if type(icon) ~= "string" or icon == "" then
    icon = Auctionator.Utilities.GetItemIconSafe(rowData.itemLink or rowData.itemString)
  end
  self.Icon:SetTexture(icon)
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
