AuctionatorExportTextFrameMixin = {}

function AuctionatorExportTextFrameMixin:OnLoad()
  -- WotLK 3.3.5a: this dialog inherits AuctionatorSimplePanelTemplate whose rock-file
  -- background is absent (rendered GREEN) and whose metal border is invisible. Apply a
  -- real opaque DialogBox backdrop so the frame is solid and bordered.
  Auctionator.Theme.ApplyOpaqueDialogBackdrop(self)

  ScrollUtil.RegisterScrollBoxWithScrollBar(self.EditBoxContainer:GetScrollBox(), self.ScrollBar)
  self.EditBoxContainer:GetScrollBox():GetView():SetPanExtent(50)
end

function AuctionatorExportTextFrameMixin:SetOpeningEvents(open, close)
  self.openEvent = open
  self.closeEvent = close
end

function AuctionatorExportTextFrameMixin:OnShow()
  Auctionator.Debug.Message("AuctionatorExportTextFrameMixin:OnShow()")

  self.EditBoxContainer:GetEditBox():SetFocus()
  self.EditBoxContainer:GetEditBox():HighlightText()

  if self.openEvent then
    Auctionator.EventBus
      :RegisterSource(self, "lists export text dialog 2")
      :Fire(self, self.openEvent)
      :UnregisterSource(self)
  end
end

function AuctionatorExportTextFrameMixin:OnHide()
  self:Hide()

  if self.closeEvent then
    Auctionator.EventBus
      :RegisterSource(self, "lists export text dialog 2")
      :Fire(self, self.closeEvent)
      :UnregisterSource(self)
  end
end

function AuctionatorExportTextFrameMixin:SetExportString(exportString)
  self.EditBoxContainer:GetEditBox():SetText(exportString)
  self.EditBoxContainer:GetEditBox():HighlightText()
end

function AuctionatorExportTextFrameMixin:OnCloseClicked()
  self.EditBoxContainer:GetEditBox():SetText("")
  self:Hide()
end
