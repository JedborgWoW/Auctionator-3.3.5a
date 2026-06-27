local MIN_TAB_WIDTH = 70;
local TAB_PADDING = 20;

AuctionatorShoppingListsMiniTabButtonMixinMixin = {}

function AuctionatorShoppingListsMiniTabButtonMixinMixin:OnLoad()
  -- LeftDisabled is part of retail's full TabButtonTemplate chrome; our minimal
  -- 3.3.5a TabButtonTemplate is a plain text button, so guard it.
  if self.LeftDisabled then
    self.LeftDisabled:SetPoint("TOPLEFT")
  end
  self.deselectedTextY = 6
  self.selectedTextY = 2
end

-- These mini-tabs actually inherit the stock 3.3.5a TabButtonTemplate (our compat one is
-- shadowed by the native definition), which carries HelpFrameTab Active/Inactive background
-- art. On narrow text-width tabs that art renders as dark "bleed" blocks behind the labels.
-- Blank every HelpFrameTab texture (both states) so the mini-tabs read as clean text tabs;
-- blanking the texture file means they stay invisible even when PanelTemplates toggles their
-- shown state on select/deselect. The mouse highlight + selected text colour still distinguish
-- the active tab.
function AuctionatorShoppingListsMiniTabButtonMixinMixin:HideTabArt()
  for i = 1, self:GetNumRegions() do
    local r = select(i, self:GetRegions())
    if r and r.GetObjectType and r:GetObjectType() == "Texture" and r.GetTexture then
      local tex = r:GetTexture()
      if type(tex) == "string" and tex:find("HelpFrameTab", 1, true) then
        r:SetTexture("")
      end
    end
  end
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
  self:HideTabArt()
end

function AuctionatorShoppingListsMiniTabButtonMixinMixin:OnClick()
  self:GetParent():SetView(self:GetID())

  PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
end
