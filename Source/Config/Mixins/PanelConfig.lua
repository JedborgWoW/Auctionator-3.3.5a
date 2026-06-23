AuctionatorPanelConfigMixin = {}

function AuctionatorPanelConfigMixin:SetupPanel()
  self.cancel = function()
    self:Cancel()
  end

  self.okay = function()
    if self.shownSettings then
      self:Save()
    end
  end

  self.shownSettings =  false

  self.OnCommit = self.okay
  self.OnDefault = function() end
  self.OnRefresh = function() end

  -- Stock 3.3.5a has no retail Settings canvas API; register with the native
  -- InterfaceOptions system instead (frame.name = title, frame.parent = parent
  -- category name for subpanels).
  if self.parent == nil then
    InterfaceOptions_AddCategory(self)
    Auctionator.State.OptionsCategory = self
  else
    self.parent = Auctionator.State.OptionsCategory and Auctionator.State.OptionsCategory.name
    InterfaceOptions_AddCategory(self)
  end
end

function AuctionatorPanelConfigMixin:OnShow()
  self:ShowSettings()
  self.shownSettings = true
end

-- Derive
function AuctionatorPanelConfigMixin:Cancel()
  Auctionator.Debug.Message("AuctionatorPanelConfigMixin:Cancel() Unimplemented")
end

-- Derive
function AuctionatorPanelConfigMixin:Save()
  Auctionator.Debug.Message("AuctionatorPanelConfigMixin:Save() Unimplemented")
end
