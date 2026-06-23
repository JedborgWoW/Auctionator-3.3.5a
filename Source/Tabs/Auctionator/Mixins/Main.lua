AuctionatorConfigTabMixin = {}

function AuctionatorConfigTabMixin:OnLoad()
  Auctionator.Debug.Message("AuctionatorConfigTabMixin:OnLoad()")

  if Auctionator.Constants.IsLegacyAH then
    -- Reposition lower down translator entries so that they don't go past the
    -- bottom of the tab
    self.esES:SetPoint("TOPLEFT", self.deDE, "TOPLEFT", 300, 0)
    self.koKR:SetPoint("TOPLEFT", self.esES, "TOPLEFT", 300, 0)
  else
    self.ruRU:SetPoint("TOPLEFT", self.deDE, "TOPLEFT", 300, 0)
  end
end

function AuctionatorConfigTabMixin:OpenOptions()
  local category = Auctionator.State.OptionsCategory
  if InterfaceOptionsFrame_OpenToCategory and category then
    -- 3.3.5a needs this called twice to reliably scroll to the panel.
    InterfaceOptionsFrame_OpenToCategory(category)
    InterfaceOptionsFrame_OpenToCategory(category)
  end
end
