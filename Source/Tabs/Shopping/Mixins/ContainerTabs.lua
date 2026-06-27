AuctionatorShoppingTabContainerTabsMixin = {}

function AuctionatorShoppingTabContainerTabsMixin:OnLoad()
  self.Tabs = {self.ListsTab, self.RecentsTab}
  self.numTabs = #self.Tabs
end

function AuctionatorShoppingTabContainerTabsMixin:SetView(viewIndex)
  -- PanelTemplates_SetTab -> PanelTemplates_UpdateTabs indexes _G[frameName.."Tab"..i]
  -- on 3.3.5a, which errors for this anonymous (parentKey-only) container. The mini
  -- tabs aren't PanelTemplates-style tabs, so just record the selection; the
  -- show/hide below is the real behaviour.
  self.selectedTab = viewIndex
  Auctionator.Config.Set(Auctionator.Config.Options.SHOPPING_LAST_CONTAINER_VIEW, viewIndex)

  -- Mark the active tab (gold underline) so it is clear which of the two tabs is selected.
  if self.Tabs then
    for _, tab in ipairs(self.Tabs) do
      if tab.SetActive then
        tab:SetActive(tab:GetID() == viewIndex)
      end
    end
  end

  self:GetParent().NewListButton:Hide()
  self:GetParent().ImportButton:Hide()
  self:GetParent().ExportButton:Hide()

  if viewIndex == Auctionator.Constants.ShoppingListViews.Recents then
    self:GetParent().ListsContainer:Hide()
    self:GetParent().RecentsContainer:Show()

  elseif viewIndex == Auctionator.Constants.ShoppingListViews.Lists then
    self:GetParent().RecentsContainer:Hide()
    self:GetParent().ListsContainer:Show()
    self:GetParent().NewListButton:Show()
    self:GetParent().ImportButton:Show()
    self:GetParent().ExportButton:Show()
  end
end
