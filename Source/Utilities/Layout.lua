-- Explicit WotLK 3.3.5a layout helpers.
--
-- Auctionator's UI is built from Classic XML whose relative anchors (dotted relativeKey,
-- inherited OnLoad, mis-sized containers) are not reliably honored by the stock 3.3.5a
-- XML parser, so layout-critical frames drift. Rather than fight the parser, position
-- those frames EXPLICITLY in Lua from OnShow/OnLoad using these helpers. This is a
-- compatibility correction layer, not a redesign -- the values still match the Classic
-- look, they are just applied deterministically.

Auctionator.Layout = {}

-- Fill `parent` with per-side insets (positive insets move inward).
function Auctionator.Layout.SetInside(frame, parent, left, right, top, bottom)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", left or 0, -(top or 0))
  frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(right or 0), bottom or 0)
end

-- Lay buttons out as a left-to-right row. The first button is anchored to `parent` at
-- (point -> relativePoint, x, y); the rest chain off the previous one with `spacing`.
function Auctionator.Layout.SetButtonRow(buttons, parent, point, relativePoint, x, y, spacing)
  spacing = spacing or 8
  for index, button in ipairs(buttons) do
    button:ClearAllPoints()
    if index == 1 then
      button:SetPoint(point, parent, relativePoint, x or 0, y or 0)
    else
      button:SetPoint("LEFT", buttons[index - 1], "RIGHT", spacing, 0)
    end
  end
end

-- Raise an interactive frame above any number of passive background frames so clicks
-- land on it and it is never hidden behind a panel.
function Auctionator.Layout.RaiseAbove(frame, ...)
  local level = frame:GetFrameLevel() or 0
  for _, background in ipairs({ ... }) do
    if background and background.GetFrameLevel then
      level = math.max(level, background:GetFrameLevel() or 0)
    end
  end
  frame:SetFrameLevel(level + 10)
end

-- Apply a consistent dark, WotLK-safe backdrop (always-present tooltip textures) so all
-- result/list panels read the same and never show the world behind a missing texture.
function Auctionator.Layout.NormalizeBackground(frame, alpha)
  if not frame.SetBackdrop then
    return
  end
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  frame:SetBackdropColor(0, 0, 0, alpha or 0.85)
  frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
end
