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
  --
  -- Unlike the retail Settings canvas, the 3.3.5a InterfaceOptions panel container
  -- is a fixed height and does NOT scroll, so tall option panels (e.g. "Selling:
  -- All Items") overflow off the bottom of the window. Register a ScrollFrame as
  -- the category and make this content panel its scroll child so the options
  -- scroll instead. Nothing inside the panel is re-parented, so every widget
  -- anchor stays valid.
  local container = InterfaceOptionsFramePanelContainer or UIParent
  local scroller = CreateFrame("ScrollFrame", self:GetName() .. "Scroller", container, "UIPanelScrollFrameTemplate")
  scroller:SetAllPoints(container)
  scroller.name = self.name
  scroller.parent = self.parent
  -- InterfaceOptions drives these on the *registered* frame (the scroller); point
  -- them at this content panel's handlers.
  scroller.okay = self.okay
  scroller.cancel = self.cancel
  scroller.default = self.OnDefault
  scroller.refresh = self.OnRefresh
  scroller.OnCommit = self.OnCommit
  scroller.OnDefault = self.OnDefault
  scroller.OnRefresh = self.OnRefresh
  self.Scroller = scroller

  self:SetParent(scroller)
  self:ClearAllPoints()
  scroller:SetScrollChild(self)

  -- The category is shown/hidden by InterfaceOptions on the scroller; forward that
  -- so this panel's OnShow (ShowSettings) / OnHide (Save) scripts still fire.
  scroller:SetScript("OnShow", function()
    self:Show()
  end)
  scroller:SetScript("OnHide", function()
    self:Hide()
  end)
  scroller:EnableMouseWheel(true)
  scroller:SetScript("OnMouseWheel", function(frame, delta)
    local bar = frame.ScrollBar or _G[frame:GetName() .. "ScrollBar"]
    if bar then
      bar:SetValue(bar:GetValue() - delta * 25)
    end
  end)

  if self.parent == nil then
    InterfaceOptions_AddCategory(scroller)
    Auctionator.State.OptionsCategory = scroller
  else
    scroller.parent = Auctionator.State.OptionsCategory and Auctionator.State.OptionsCategory.name
    self.parent = scroller.parent
    InterfaceOptions_AddCategory(scroller)
  end
end

function AuctionatorPanelConfigMixin:OnShow()
  self:ShowSettings()
  self.shownSettings = true
  self:UpdateScrollRange()
end

-- Size the scroll child to the container width and to the full height of its
-- content so the ScrollFrame's vertical scroll range is correct. Recomputed on
-- every show because ShowSettings can toggle which widgets are visible.
function AuctionatorPanelConfigMixin:UpdateScrollRange()
  local scroller = self.Scroller
  if not scroller then
    return
  end

  local width = scroller:GetWidth()
  if width and width > 0 then
    self:SetWidth(width - 20)
  end

  local top = self:GetTop()
  if not top then
    -- The frame rect is not resolved yet (can happen on the first show, before
    -- SetScrollChild positions us). Retry next frame; bounded by IsVisible so a
    -- panel that gets hidden again stops retrying.
    if self:IsVisible() then
      C_Timer.After(0, function() self:UpdateScrollRange() end)
    end
    return
  end

  local lowest = top
  local function consider(region)
    if region and region:IsShown() then
      local bottom = region:GetBottom()
      if bottom and bottom < lowest then
        lowest = bottom
      end
    end
  end
  for _, child in ipairs({ self:GetChildren() }) do
    consider(child)
  end
  for _, region in ipairs({ self:GetRegions() }) do
    consider(region)
  end

  self:SetHeight((top - lowest) + 24)
end

-- Derive
function AuctionatorPanelConfigMixin:Cancel()
  Auctionator.Debug.Message("AuctionatorPanelConfigMixin:Cancel() Unimplemented")
end

-- Derive
function AuctionatorPanelConfigMixin:Save()
  Auctionator.Debug.Message("AuctionatorPanelConfigMixin:Save() Unimplemented")
end
