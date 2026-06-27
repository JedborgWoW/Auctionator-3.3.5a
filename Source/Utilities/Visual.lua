-- Auctionator.Visual -- explicit, deterministic visual NORMALIZATION for the 3.3.5a
-- backport.
--
-- WHY THIS EXISTS
-- The three auction tabs (Shopping / Selling / Cancelling) are all built from the same
-- two shared templates:
--   * AuctionatorResultsListingTemplate -- the header row + scrollable result rows
--   * AuctionatorInsetTemplate          -- the dark panel placed BEHIND a results listing
--                                          (fill 0.07,0.07,0.09,0.92 + InsetFrameTemplate4)
-- Cancelling looks correct, so it is the visual source of truth. Shopping and Selling
-- looked wrong NOT because the dark-panel mechanism differs, but because:
--   1. earlier theme code gave the Shopping sidebar a DIFFERENT colour + DIFFERENT border
--      than the results inset, so two mismatched dark blocks sat side by side;
--   2. the Classic XML anchors (dotted relativeKey, inherited OnLoad that does not run on
--      the 3.3.5a parser) leave the inset / footer drifting.
-- So rather than invent a new theme, this module forces Shopping and Selling to reuse the
-- EXACT same inset look + the same margins as Cancelling, applied from Lua on OnShow after
-- every XML frame exists. It is a compatibility-correction layer, not a redesign.

Auctionator.Visual = {}

-- ONE palette. These mirror AuctionatorInsetTemplate (the Cancelling look) so every panel
-- reads as the same system. Text colours are WotLK-safe (gold status, white rows).
Auctionator.Visual.Palette = {
  ResultsBg = { 0.07, 0.07, 0.09, 0.92 },
  SidebarBg = { 0.07, 0.07, 0.09, 0.92 }, -- identical to results => guaranteed match
  Border    = { 0.35, 0.35, 0.35, 1.0 },
  GoldText  = { 1.0, 0.82, 0.0, 1.0 },
  WhiteText = { 1.0, 1.0, 1.0, 1.0 },
  GreyText  = { 0.5, 0.5, 0.5, 1.0 },
}

-- Margins (in px) by which a results inset extends past its results listing. Taken from
-- the Cancelling tab: the top extends up 25px to sit behind the header row.
local INSET_LEFT, INSET_TOP, INSET_RIGHT, INSET_BOTTOM = -5, -25, 0, 2

-- Create-once an AuctionatorInsetTemplate panel (identical fill + InsetFrameTemplate4
-- border to the results inset) stored under parent[key]; returns it. This is how a sidebar
-- gets the SAME look as the results area instead of a mismatched custom backdrop.
function Auctionator.Visual.EnsureInsetPanel(parent, key)
  if parent == nil then
    return nil
  end
  if parent[key] == nil then
    parent[key] = CreateFrame("Frame", nil, parent, "AuctionatorInsetTemplate")
  end
  return parent[key]
end

-- Push a passive background strictly below a set of content frames so it can never cover
-- headers / rows / text / buttons.
function Auctionator.Visual.SendToBack(background, ...)
  if not (background and background.SetFrameLevel) then
    return
  end
  local minLevel
  for _, f in ipairs({ ... }) do
    if f and f.GetFrameLevel then
      local level = f:GetFrameLevel()
      minLevel = minLevel and math.min(minLevel, level) or level
    end
  end
  background:SetFrameLevel(math.max(0, (minLevel or 1) - 1))
end

-- Raise interactive frames above any number of passive background frames.
function Auctionator.Visual.RaiseAbove(frame, ...)
  if not (frame and frame.SetFrameLevel) then
    return
  end
  local level = frame:GetFrameLevel() or 0
  for _, background in ipairs({ ... }) do
    if background and background.GetFrameLevel then
      level = math.max(level, background:GetFrameLevel() or 0)
    end
  end
  frame:SetFrameLevel(level + 10)
end

-- TASK 2 API ----------------------------------------------------------------------------

-- Anchor `inset` to wrap `listing` exactly like Cancelling wraps its ResultsListing, then
-- send the inset behind the listing's content. `options` may override margins
-- (left/top/right/bottom).
function Auctionator.Visual.NormalizeResultsPanel(inset, listing, options)
  if inset == nil or listing == nil then
    return
  end
  options = options or {}
  inset:ClearAllPoints()
  inset:SetPoint("TOPLEFT", listing, "TOPLEFT", options.left or INSET_LEFT, options.top or INSET_TOP)
  inset:SetPoint("BOTTOMRIGHT", listing, "BOTTOMRIGHT", options.right or INSET_RIGHT, options.bottom or INSET_BOTTOM)
  Auctionator.Visual.SendToBack(inset, listing, listing.HeaderContainer, listing.ScrollArea)
end

-- Give `frame` a dark backdrop IDENTICAL to the results inset by attaching a child
-- AuctionatorInsetTemplate covering it, kept behind the frame's own content. Returns the
-- backdrop panel. Use for a passive area (e.g. a sidebar) that must match the result panel.
function Auctionator.Visual.NormalizeDarkBackdrop(frame, key)
  if frame == nil then
    return nil
  end
  local panel = Auctionator.Visual.EnsureInsetPanel(frame, key or "VisualInset")
  panel:ClearAllPoints()
  panel:SetAllPoints(frame)
  Auctionator.Visual.SendToBack(panel)
  panel:Show()
  return panel
end

-- Lay a footer button row on ONE shared bottom Y. `anchor` = { frame, point, relPoint,
-- x, y }; the first button anchors there, the rest chain to the right by `spacing`.
function Auctionator.Visual.NormalizeFooter(buttons, anchor, spacing)
  spacing = spacing or 8
  for index, button in ipairs(buttons) do
    if button and button.ClearAllPoints then
      button:ClearAllPoints()
      if index == 1 then
        button:SetPoint(
          anchor.point or "BOTTOMLEFT", anchor.frame,
          anchor.relPoint or "BOTTOMRIGHT", anchor.x or 0, anchor.y or 0
        )
      else
        button:SetPoint("BOTTOMLEFT", buttons[index - 1], "BOTTOMRIGHT", spacing, 0)
      end
    end
  end
end

-- Stretch a dark panel edge-to-edge across the AuctionFrame interior. AuctionFrame is the
-- actual window (a guaranteed global). This client's AH frame is ASYMMETRIC -- the left
-- stone border is ~18px wide while the right is only ~5px -- so the insets are NOT mirrored.
--
-- ROOT CAUSE FIX (Shopping drifting left): the vertical used to be taken via TOP/BOTTOM
-- anchored to the results listing. Those points also pin the panel's HORIZONTAL CENTRE to
-- the listing's centre. On Selling/Cancelling the listing is centred, so harmless; but on
-- Shopping the listing is only the RIGHT column block (starts ~+285), badly off-centre, so
-- that centre constraint FOUGHT the LEFT/RIGHT edges and dragged the whole panel sideways
-- (amount depending on width -- which is why it shifted when right changed 18 -> 5).
-- Fix: anchor BOTH corners to AuctionFrame (centred -> no centre conflict) and DERIVE the
-- vertical from the listing's measured top/bottom. Identical result where it already worked.
local FW_LEFT, FW_RIGHT = 18, 5
-- `leftInset` overrides the left margin (defaults to FW_LEFT = the same as Selling/Cancelling).
--
-- Both corners are anchored to AuctionFrame (centred -> no horizontal-centre conflict) and the
-- vertical is DERIVED from the listing's measured top/bottom. The catch: at the first OnShow
-- the listing's position can be unmeasurable (GetTop == nil). The OLD fallback then anchored
-- TOP/BOTTOM directly to the listing -- which on Shopping (whose listing is only the off-centre
-- RIGHT column) pinned the panel's horizontal centre to that column and dragged the whole panel
-- LEFT, out over the stone border. That is exactly the "Shopping left not inside the frame" bug,
-- and it was intermittent because on loads where the listing WAS measurable the clean corner
-- path ran instead. Fix: never use the conflicting fallback -- if positions aren't ready, defer
-- one frame and retry until they are, so every tab deterministically lands on the corner path.
function Auctionator.Visual.StretchFullWidth(panel, tabFrame, listing, top, bottom, leftInset, _retry)
  if panel == nil or listing == nil then
    return
  end
  local frame = AuctionFrame or (tabFrame and tabFrame:GetParent()) or tabFrame
  local lt, lb = listing:GetTop(), listing:GetBottom()
  local ft, fb = frame:GetTop(), frame:GetBottom()
  if lt and lb and ft and fb then
    local L = leftInset or FW_LEFT
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", L, (lt - ft) + (top or -25))
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -FW_RIGHT, (lb - fb) + (bottom or 2))
    Auctionator.Visual.SendToBack(panel, listing)
  elseif (_retry or 0) < 12 then
    C_Timer.After(0, function()
      Auctionator.Visual.StretchFullWidth(panel, tabFrame, listing, top, bottom, leftInset, (_retry or 0) + 1)
    end)
  end
end

-- Make a results listing's header row + empty-state text read consistently: header drawn
-- above the inset, "No results" / status text gold. Safe to call repeatedly.
function Auctionator.Visual.NormalizeHeaders(listing)
  if listing == nil then
    return
  end
  if listing.HeaderContainer then
    Auctionator.Visual.RaiseAbove(listing.HeaderContainer, listing)
  end
  local gold = Auctionator.Visual.Palette.GoldText
  local scroll = listing.ScrollArea
  if scroll then
    if scroll.NoResultsText and scroll.NoResultsText.SetTextColor then
      scroll.NoResultsText:SetTextColor(gold[1], gold[2], gold[3], gold[4])
    end
    if scroll.ResultsText and scroll.ResultsText.SetTextColor then
      scroll.ResultsText:SetTextColor(gold[1], gold[2], gold[3], gold[4])
    end
  end
end
