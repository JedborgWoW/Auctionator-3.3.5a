local tabPadding = 0
local tabAbsoluteSize = nil
local minTabWidth = 36

AuctionatorTabContainerMixin = {}

local function InitializeFromDetails(details)
  local frame = CreateFrame(
    "BUTTON",
    "AuctionFrameTab" .. (AuctionFrame.numTabs + 1),
    AuctionFrame,
    "AuctionatorTabButtonTemplate"
  )
  local frameName = "AuctionatorTabs_" .. details.name
  _G[frameName] = frame

  frame:SetText(details.textLabel)

  frame:Initialize(details.name, details.tabTemplate, details.tabHeader, {details.tabFrameName})

  -- AuctionTabTemplate's label keeps a narrow width and truncates longer names to
  -- "Shop.."/"Canc..". On 3.3.5a PanelTemplates_TabResize(absoluteSize) sets the
  -- text width to (absoluteSize - sideTextureWidths), so it still came up short.
  -- Fix: size the tab background to text+padding via TabResize, THEN force the font
  -- string back to its full natural width so the label is never clipped.
  local label = frame:GetFontString()
  if label then
    label:SetWidth(0)
    local textW = math.ceil(label:GetStringWidth() or 0)
    if textW <= 0 then
      textW = 70
    end
    PanelTemplates_TabResize(frame, tabPadding, textW + 30, minTabWidth)
    label:SetWidth(textW)
  else
    PanelTemplates_TabResize(frame, tabPadding, tabAbsoluteSize, minTabWidth)
  end

  return frame
end

function AuctionatorTabContainerMixin:OnLoad()
  Auctionator.Debug.Message("AuctionatorTabContainerMixin:OnLoad()")

  -- Tabs are sorted to avoid inconsistent ordering based on the addon loading
  -- order
  table.sort(
    Auctionator.Tabs.State.knownTabs,
    function(left, right)
      return left.tabOrder < right.tabOrder
    end
  )

  self.Tabs = {}

  for _, details in ipairs(Auctionator.Tabs.State.knownTabs) do
    table.insert(self.Tabs, InitializeFromDetails(details))
  end

  self:HookTabs()
end

function AuctionatorTabContainerMixin:OnShow()
end

function AuctionatorTabContainerMixin:OnHide()
  for _, auctionatorTab in pairs(self.Tabs) do
    auctionatorTab:DeselectTab()
  end
end

function AuctionatorTabContainerMixin:IsAuctionatorFrame(tab)
  for _, frame in pairs(self.Tabs) do
    if frame == tab then
      return true
    end
  end

  return false
end

function AuctionatorTabContainerMixin:HookTabs()
  hooksecurefunc(_G, "AuctionFrameTab_OnClick", function(tabButton, ...)
    for _, tab in ipairs(self.Tabs) do
      tab:DeselectTab()
    end

    local isAuctionatorFrame = self:IsAuctionatorFrame(tabButton)
    if isAuctionatorFrame then
      tabButton:Selected()
    end
  end)
end
