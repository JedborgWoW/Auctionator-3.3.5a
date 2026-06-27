-- Central dark-theme constants + helpers for the 3.3.5a backport, so Shopping / Selling /
-- Cancelling and the Full Scan panel share one coherent look (dark charcoal panels, subtle
-- grey borders, gold/orange text) using only WotLK-safe textures. This is a visual layer
-- only -- it never changes AH logic.

Auctionator.Theme = {
  Colors = {
    MainBg       = {0.08, 0.075, 0.065, 0.95},
    PanelBg      = {0.05, 0.05, 0.06, 0.94},
    PanelBgSoft  = {0.07, 0.07, 0.09, 0.92},
    SidebarBg    = {0.04, 0.04, 0.05, 0.95},
    HeaderBg     = {0.09, 0.085, 0.075, 0.90},
    Border       = {0.35, 0.35, 0.35, 1},
    GoldText     = {1.0, 0.82, 0.0, 1},
    OrangeText   = {1.0, 0.55, 0.18, 1},
    WhiteText    = {1, 1, 1, 1},
    DisabledText = {0.45, 0.45, 0.45, 1},
  },

  Textures = {
    DialogBg     = "Interface\\DialogFrame\\UI-DialogBox-Background",
    DialogBorder = "Interface\\DialogFrame\\UI-DialogBox-Border",
    TooltipBg    = "Interface\\Tooltips\\UI-Tooltip-Background",
    TooltipBorder= "Interface\\Tooltips\\UI-Tooltip-Border",
    Highlight    = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
    SortArrow    = "Interface\\Buttons\\UI-SortArrow",
  },
}

local function Backdrop(frame, color, tileSize, edgeSize, inset)
  if not frame.SetBackdrop then
    return
  end
  frame:SetBackdrop({
    bgFile = Auctionator.Theme.Textures.TooltipBg,
    edgeFile = Auctionator.Theme.Textures.TooltipBorder,
    tile = true, tileSize = tileSize or 16, edgeSize = edgeSize or 14,
    insets = { left = inset or 3, right = inset or 3, top = inset or 3, bottom = inset or 3 },
  })
  frame:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
  frame:SetBackdropBorderColor(
    Auctionator.Theme.Colors.Border[1], Auctionator.Theme.Colors.Border[2],
    Auctionator.Theme.Colors.Border[3], Auctionator.Theme.Colors.Border[4]
  )
end

function Auctionator.Theme.ApplyPanelBackdrop(frame)
  Backdrop(frame, Auctionator.Theme.Colors.PanelBg)
end

function Auctionator.Theme.ApplyResultsBackdrop(frame)
  Backdrop(frame, Auctionator.Theme.Colors.PanelBgSoft)
end

function Auctionator.Theme.ApplySidebarBackdrop(frame)
  Backdrop(frame, Auctionator.Theme.Colors.SidebarBg)
end

-- Dialogs use the heavier stone DialogBox backdrop.
function Auctionator.Theme.ApplyDialogBackdrop(frame)
  if not frame.SetBackdrop then
    return
  end
  frame:SetBackdrop({
    bgFile = Auctionator.Theme.Textures.DialogBg,
    edgeFile = Auctionator.Theme.Textures.DialogBorder,
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
end

-- Opaque backdrop for the Shopping pop-up dialogs (Import / Export / Export Results
-- / Price History). These inherit AuctionatorSimplePanelTemplate, whose original
-- rock-file background is absent on this client (rendered bright GREEN) and whose
-- metal border uses virtual-texture inheritance (invisible on 3.3.5a). We give the
-- frame a real, present DialogBox backdrop so it is fully opaque WITH a visible
-- border, regardless of the broken XML art. Safe on a frame that already has a
-- solid <Color> Bg behind it (the backdrop just draws on top, also opaque).
function Auctionator.Theme.ApplyOpaqueDialogBackdrop(frame)
  if not frame or not frame.SetBackdrop then
    return
  end
  frame:SetBackdrop({
    bgFile = Auctionator.Theme.Textures.DialogBg,
    edgeFile = Auctionator.Theme.Textures.DialogBorder,
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  frame:SetBackdropColor(1, 1, 1, 1)
  frame:SetBackdropBorderColor(1, 1, 1, 1)
end

function Auctionator.Theme.ApplyTextColor(fontString, color)
  if fontString and fontString.SetTextColor then
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  end
end

-- Raise interactive controls above a passive background frame.
function Auctionator.Theme.RaiseControlsAboveBackground(background, controls)
  local base = (background and background.GetFrameLevel and background:GetFrameLevel()) or 0
  for _, control in ipairs(controls) do
    if control and control.SetFrameLevel then
      control:SetFrameLevel(base + 10)
    end
  end
end
