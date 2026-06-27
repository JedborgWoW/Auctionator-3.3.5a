function Auctionator.Shopping.Tab.CreateOptionButton(button, xOffset, width, height)
  local option = CreateFrame("Button", nil, button)
  option:SetPoint("TOPRIGHT", xOffset, 0)
  option:SetSize(width, height)
  option.Icon = option:CreateTexture()
  option.Icon:SetSize(height - 5, height - 5)
  option.Icon:SetPoint("CENTER")
  option:SetScript("OnEnter", function()
    option.Icon:SetAlpha(0.5)
    if option.TooltipText then
      GameTooltip:SetOwner(option, "ANCHOR_RIGHT")
      GameTooltip:SetText(option.TooltipText, 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  option:SetScript("OnLeave", function()
    option.Icon:SetAlpha(1)
    if option.TooltipText then
      GameTooltip:Hide()
    end
  end)
  option:SetScript("OnHide", function()
    option.Icon:SetAlpha(1)
  end)
  return option
end

function Auctionator.Shopping.Tab.SetupContainerRow(button, buttonHeight, buttonSpacing)
  local fontString = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fontString:SetJustifyH("LEFT")
  fontString:SetPoint("RIGHT", button, "RIGHT", -buttonSpacing, 0)
  fontString:SetWordWrap(false)
  button.Text = fontString
  -- The retail row atlases (auctionhouse-rowstripe-1 / -ui-row-highlight / -ui-row-select) do
  -- NOT exist on 3.3.5a and render as solid WHITE blocks behind every row -- that was the
  -- "white" look. Use WotLK-safe solid colours instead: no permanent stripe (flat dark rows),
  -- a subtle hover, and a gold-tinted selected state.
  button.Bg = button:CreateTexture(nil, "BACKGROUND")
  button.Bg:SetAllPoints()
  button.Bg:Hide()
  button.Highlight = button:CreateTexture(nil, "ARTWORK")
  button.Highlight:SetTexture(1, 1, 1, 0.10)
  button.Highlight:SetAllPoints()
  button.Highlight:Hide()
  button.Selected = button:CreateTexture(nil, "ARTWORK")
  button.Selected:SetTexture(1, 0.82, 0, 0.16)
  button.Selected:SetAllPoints()
  button.Selected:Hide()
end
