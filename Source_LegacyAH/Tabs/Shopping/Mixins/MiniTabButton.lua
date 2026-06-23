local MIN_TAB_WIDTH = 70;
local TAB_PADDING = 20;

AuctionatorShoppingListsMiniTabButtonMixinMixin = {}

function AuctionatorShoppingListsMiniTabButtonMixinMixin:OnLoad()
  self.LeftDisabled:SetPoint("TOPLEFT")
  self.deselectedTextY = 6
  self.selectedTextY = 2
end

function AuctionatorShoppingListsMiniTabButtonMixinMixin:OnShow()
  -- PanelTemplates_TabResize on 3.3.5a resolves the tab's side textures via
  -- _G[tabName.."Middle"] etc., so it errors for an anonymous tab (these mini-tabs
  -- have only a parentKey, no name). Size from the text width in that case.
  if self:GetName() then
    PanelTemplates_TabResize(self, TAB_PADDING, nil, MIN_TAB_WIDTH)
  else
    local textWidth = self.GetTextWidth and self:GetTextWidth() or 0
    self:SetWidth(math.max(MIN_TAB_WIDTH, textWidth + TAB_PADDING))
  end
end

function AuctionatorShoppingListsMiniTabButtonMixinMixin:OnClick()
  self:GetParent():SetView(self:GetID())

  PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
end
