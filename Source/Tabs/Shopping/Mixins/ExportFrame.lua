AuctionatorListExportFrameMixin = {}

function AuctionatorListExportFrameMixin:OnLoad()
  Auctionator.Debug.Message("AuctionatorListExportFrameMixin:OnLoad()")

  -- WotLK 3.3.5a: this dialog inherits AuctionatorSimplePanelTemplate whose rock-file
  -- background is absent (rendered GREEN) and whose metal border is invisible. Apply a
  -- real opaque DialogBox backdrop so the frame is solid and bordered.
  Auctionator.Theme.ApplyOpaqueDialogBackdrop(self)

  -- Setup scrolling region
  local view = CreateScrollBoxLinearView()
  view:SetPadding(5, 5, 0, 0, 0)
  view:SetPanExtent(50)
  ScrollUtil.InitScrollBoxWithScrollBar(self.ScrollBox, self.ScrollBar, view);

  self.ScrollBox.ListListingFrame.OnCleaned = function()
    self.ScrollBox:FullUpdate(ScrollBoxConstants.UpdateImmediately);
  end

  self.copyTextDialog = CreateFrame("Frame", nil, self:GetParent(), "AuctionatorExportTextFrame")
  self.copyTextDialog:SetPoint("CENTER")

  if self:GetParent().dialogs then
    table.insert(self:GetParent().dialogs, self.copyTextDialog)
  end

  -- self.ExportOption:SetOnChange(function(selectedValue)
  --   if selectedValue == Auctionator.Constants.EXPORT_TYPES.WHISPER then
  --     self.Recipient:Show()
  --     self.Recipient:SetFocus()
  --   else
  --     self.Recipient:Hide()
  --   end
  -- end)
  -- self.ExportOption:SetSelectedValue(Auctionator.Constants.EXPORT_TYPES.STRING)

  self.checkBoxPool = CreateFramePool("Frame", self.ScrollBox.ListListingFrame, "AuctionatorConfigurationCheckbox")
end

function AuctionatorListExportFrameMixin:OnShow()
  Auctionator.Debug.Message("AuctionatorListExportFrameMixin:OnShow()")

  Auctionator.EventBus:Register(self, { Auctionator.Shopping.Events.ListMetaChange })

  self:RefreshLists()

  Auctionator.EventBus
    :RegisterSource(self, "lists export dialog 1")
    :Fire(self, Auctionator.Shopping.Tab.Events.DialogOpened)
    :UnregisterSource(self)
end

function AuctionatorListExportFrameMixin:OnHide()
  self:Hide()

  Auctionator.EventBus:Unregister(self, { Auctionator.Shopping.Events.ListMetaChange })

  Auctionator.EventBus
    :RegisterSource(self, "lists export dialog 1")
    :Fire(self, Auctionator.Shopping.Tab.Events.DialogClosed)
    :UnregisterSource(self)
end

function AuctionatorListExportFrameMixin:ReceiveEvent(eventName, listName)
  if eventName == Auctionator.Shopping.Events.ListMetaChange then
    if self:IsShown() then
      self:RefreshLists()
    end
  end
end

function AuctionatorListExportFrameMixin:RefreshLists()
  Auctionator.Debug.Message("AuctionatorListExportFrameMixin:RefreshLists()")
  self.checkBoxPool:ReleaseAll()

  local listing = self.ScrollBox.ListListingFrame
  -- Make sure the scroll content has a real width, so the checkboxes (anchored to its left/right
  -- edges) aren't laid out 1px wide before the ScrollBox has been sized.
  local boxWidth = self.ScrollBox:GetWidth()
  if listing and boxWidth and boxWidth > 0 then
    listing:SetWidth(boxWidth)
  end

  for index = 1, Auctionator.Shopping.ListManager:GetCount() do
    local list = Auctionator.Shopping.ListManager:GetByIndex(index)
    local checkBox = self.checkBoxPool:Acquire()
    checkBox:SetText(list:GetName())
    checkBox:SetHeight(25)
    -- Drop the template's inherited LEFT/RIGHT anchors FIRST. On 3.3.5a SetPoint without
    -- ClearAllPoints leaves those active, so the box is pinned by four conflicting points
    -- (centre via LEFT/RIGHT + top via TOPLEFT/TOPRIGHT) and collapses/overlaps -- which is
    -- why the export list looked empty.
    checkBox:ClearAllPoints()
    checkBox:SetPoint("TOPRIGHT", listing, "TOPRIGHT", 0, -(checkBox:GetHeight()) * (index - 1))
    checkBox:SetPoint("TOPLEFT", listing, "TOPLEFT", 0, -(checkBox:GetHeight()) * (index - 1))
    checkBox:Show()
  end

  self.ScrollBox.ListListingFrame:MarkDirty()
end

function AuctionatorListExportFrameMixin:OnCloseDialogClicked()
  self:Hide()
end

function AuctionatorListExportFrameMixin:OnSelectAllClicked()
  for checkbox in self.checkBoxPool:EnumerateActive() do
    checkbox:SetChecked(true)
  end
end

function AuctionatorListExportFrameMixin:OnUnselectAllClicked()
  for checkbox in self.checkBoxPool:EnumerateActive() do
    checkbox:SetChecked(false)
  end
end

function AuctionatorListExportFrameMixin:OnExportClicked()
  local exportString = ""

  for checkbox in self.checkBoxPool:EnumerateActive() do
    if checkbox:GetChecked() then
      exportString = exportString .. Auctionator.Shopping.Lists.GetBatchExportString(checkbox:GetText()) .. "\n"
    end
  end

  -- if self.ExportOption:GetValue() == 0 then
    self:Hide()
    self.copyTextDialog:SetExportString(exportString)
    self.copyTextDialog:Show()
  -- else
    -- Addon messages can not exceed 254 characters, so do lists one by one?
    -- for checkbox in self.checkBoxPool:EnumerateActive() do
    --   if checkbox:IsVisible() and checkbox:GetChecked() then
    --     C_ChatInfo.SendAddonMessage( "Auctionator", Auctionator.Shopping.Lists.GetBatchExportString(checkbox:GetText()), "WHISPER", self.Recipient:GetText())
    --   end
    -- end
    -- C_ChatInfo.SendAddonMessage( "Auctionator", exportString, "WHISPER", self.Recipient:GetText())
  -- end

end
