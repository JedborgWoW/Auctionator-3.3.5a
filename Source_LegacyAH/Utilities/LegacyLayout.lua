-- Explicit Lua layout for the Selling SaleItem frame and the Shopping search row.
--
-- ROOT CAUSE this addresses: these frames inherit Retail templates that already carry
-- anchors. On stock 3.3.5a, calling SetPoint() WITHOUT ClearAllPoints() first leaves the
-- old inherited anchor active, so the control ends up pinned by two conflicting points and
-- the layout breaks (tiny/overlapping search box, money boxes on the wrong line, uneven
-- gaps). The original code worked around this with giant inline XML OnLoad SetPoint chains
-- that are unreadable and still left stale anchors in places.
--
-- So every manually positioned control here follows: Clear -> SetPoint -> size. All child
-- lookups are defensive (frames may exist under different keys/names on different template
-- paths), and missing optional frames are skipped rather than erroring.
--
-- Pure 3.3.5a / Lua 5.1: no atlas, no NineSlice, no LayoutFrame, no Retail money APIs.

local function Clear(frame)
  if frame and frame.ClearAllPoints then
    frame:ClearAllPoints()
  end
end

-- Resolve a child by trying several parentKeys, then several global-name suffixes. The
-- inherited templates expose the money boxes differently depending on the path, so callers
-- pass every plausible name (e.g. "GoldBox", "Gold", "GoldInput").
local function GetChild(frame, ...)
  if not frame then
    return nil
  end
  local name = frame.GetName and frame:GetName() or nil
  for i = 1, select("#", ...) do
    local key = select(i, ...)
    if frame[key] then
      return frame[key]
    end
    if name and _G[name .. key] then
      return _G[name .. key]
    end
  end
  return nil
end

-- ===========================================================================
-- Money input row (Unit Price / Stack Price / Bid Price)
-- ===========================================================================
-- A row is an AuctionatorConfigurationMoneyInputAlternate: it has a .Label and a
-- .MoneyInput, and .MoneyInput holds GoldBox / SilverBox / CopperBox edit boxes (the value
-- is read back via MoneyInput:GetAmount(), so the boxes must stay intact -- we only move
-- and size them).

-- Box width is capped by the room before the Duration column (the Unit Price row is only
-- ~320px wide and Duration anchors to its right edge): label space + 3 boxes + 2 gaps must
-- stay inside that, so 60px equal boxes are the largest that fit without overlapping
-- Duration. They are still equal-width (symmetrical) on one centerline with even spacing.
local BOX_W = 60     -- per-box width (gold/silver/copper identical -> symmetrical)
local BOX_H = 22     -- per-box height (shared centerline)
local BOX_GAP = 12   -- horizontal gap between boxes
local LABEL_SPACE = 104 -- room reserved on the row's left for the label
local LABEL_GAP = 12 -- gap between label and the first (gold) box

-- Replace the (dead atlas) coin icon with the always-present 3.3.5a money-icon sheet so
-- each box shows a real gold/silver/copper coin. l/r are the horizontal texcoords.
local function StyleCoin(box, l, r)
  if not box then
    return
  end
  local icon = box.Icon or GetChild(box, "Icon")
  if icon and icon.SetTexture then
    icon:SetTexture("Interface\\MoneyFrame\\UI-MoneyIcons")
    icon:SetTexCoord(l, r, 0, 1)
    if icon.SetSize then
      icon:SetSize(13, 13)
    end
    Clear(icon)
    icon:SetPoint("RIGHT", box, "RIGHT", -4, 0)
  end
end

function AuctionatorLegacy_LayoutMoneyInput(row)
  if not row then
    return
  end

  local money = GetChild(row, "MoneyInput", "Money")
  if not money then
    return
  end
  local gold   = GetChild(money, "GoldBox", "Gold", "GoldInput")
  local silver = GetChild(money, "SilverBox", "Silver", "SilverInput")
  local copper = GetChild(money, "CopperBox", "Copper", "CopperInput")
  local label  = GetChild(row, "Label")

  -- Pin the money-box container to a fixed offset from the row's left so Unit Price and
  -- Stack Price (both laid out by this function) get identical x positions.
  Clear(money)
  money:SetPoint("TOPLEFT", row, "TOPLEFT", LABEL_SPACE, 0)
  if money.SetSize then
    money:SetSize(BOX_W * 3 + BOX_GAP * 2, BOX_H)
  end

  -- Gold | Silver | Copper, left to right, top-aligned (one centerline), even spacing.
  local previous = nil
  for _, box in ipairs({ gold, silver, copper }) do
    if box then
      Clear(box)
      if previous then
        box:SetPoint("TOPLEFT", previous, "TOPRIGHT", BOX_GAP, 0)
      else
        box:SetPoint("TOPLEFT", money, "TOPLEFT", 0, 0)
      end
      if box.SetSize then
        box:SetSize(BOX_W, BOX_H)
      end
      if box.SetTextInsets then
        box:SetTextInsets(8, 18, 0, 0) -- right inset leaves room for the coin icon
      end
      previous = box
    end
  end

  StyleCoin(gold, 0, 0.25)
  StyleCoin(silver, 0.25, 0.5)
  StyleCoin(copper, 0.5, 0.75)

  -- Label cleanly to the LEFT of the boxes, vertically centred on the row.
  if label then
    Clear(label)
    label:SetPoint("RIGHT", gold or money, "LEFT", -LABEL_GAP, 0)
  end
end

-- ===========================================================================
-- SaleItem frame (Selling tab top input block)
-- ===========================================================================
function AuctionatorLegacy_LayoutSaleItemFrame(frame)
  if not frame then
    return
  end

  if frame.SetSize then
    frame:SetSize(600, 110)
  end

  local icon         = frame.Icon
  local title        = frame.TitleArea
  local unit         = frame.UnitPrice
  local stack        = frame.StackPrice
  local stacks       = frame.Stacks
  local duration     = frame.Duration
  local post         = frame.PostButton
  local skip         = frame.SkipButton
  local prev         = frame.PrevButton
  local bid          = frame.BidPrice
  local deposit      = frame.Deposit
  local depositPrice = frame.DepositPrice
  local total        = frame.Total
  local totalPrice   = frame.TotalPrice

  local ROW_STEP = 30 -- vertical step between price rows (box height + gap)

  -- Item icon under the title.
  if icon and title then
    Clear(icon)
    icon:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -20, -5)
  end

  -- Unit Price row to the right of the icon; Stack Price directly below with the SAME left
  -- edge; Stacks below that, indented to sit under the money boxes.
  if unit and icon then
    Clear(unit)
    unit:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 5)
    unit:SetPoint("RIGHT", icon, "RIGHT", 330, 0)
  end
  if stack and unit then
    Clear(stack)
    stack:SetPoint("TOPLEFT", unit, "TOPLEFT", 0, -ROW_STEP)
    stack:SetPoint("RIGHT", unit, "RIGHT")
  end
  if stacks and stack then
    Clear(stacks)
    stacks:SetPoint("TOPLEFT", stack, "TOPLEFT", LABEL_SPACE, -ROW_STEP)
    stacks:SetPoint("RIGHT", unit, "RIGHT")
  end

  -- Duration radio group to the right of the price rows.
  if duration and unit then
    Clear(duration)
    duration:SetPoint("TOPLEFT", unit, "TOPRIGHT", 20, 0)
    duration:SetPoint("RIGHT", unit, "RIGHT", 200, 0)
  end

  -- Post / Skip / Prev buttons. Honour the bid-price option (the mixin shows BidPrice
  -- under the Post button and tightens the gap when it is enabled).
  local showBid = Auctionator.Config ~= nil
    and Auctionator.Config.Get(Auctionator.Config.Options.SHOW_SELLING_BID_PRICE)
  if post and duration then
    Clear(post)
    post:SetPoint("TOPLEFT", duration, "BOTTOMLEFT", 20, showBid and 0 or -19)
  end
  if skip and post then
    Clear(skip)
    skip:SetPoint("TOPLEFT", post, "TOPRIGHT", 4, 0)
  end
  if prev and post then
    Clear(prev)
    prev:SetPoint("TOPRIGHT", post, "TOPLEFT", -4, 0)
  end
  if bid and post then
    Clear(bid)
    bid:SetPoint("TOPLEFT", post, "BOTTOMLEFT", 0, -6)
    if showBid then
      bid:Show()
    end
  end

  -- Deposit / Total read-outs (right column under Duration).
  if deposit and duration then
    Clear(deposit)
    deposit:SetPoint("TOPLEFT", duration, "TOPRIGHT", 20, 0)
  end
  if depositPrice and deposit then
    Clear(depositPrice)
    depositPrice:SetPoint("TOPLEFT", deposit, "BOTTOMLEFT", 0, -4)
  end
  if total and depositPrice then
    Clear(total)
    total:SetPoint("TOPLEFT", depositPrice, "BOTTOMLEFT", 0, -6)
  end
  if totalPrice and total then
    Clear(totalPrice)
    totalPrice:SetPoint("TOPLEFT", total, "BOTTOMLEFT", 0, -4)
  end

  -- Clean, identical Gold/Silver/Copper layout for both price rows (and bid if shown).
  AuctionatorLegacy_LayoutMoneyInput(unit)
  AuctionatorLegacy_LayoutMoneyInput(stack)
  if showBid then
    AuctionatorLegacy_LayoutMoneyInput(bid)
  end
end

-- ===========================================================================
-- Shopping search row
-- ===========================================================================
-- frame is the SearchOptions container. Lays label / input / buttons on one centerline.
function AuctionatorLegacy_LayoutShoppingSearchRow(frame)
  if not frame then
    return
  end

  local label    = GetChild(frame, "SearchLabel")
  local input    = GetChild(frame, "SearchString", "SearchBox", "SearchTerm")
  local reset    = GetChild(frame, "ResetSearchStringButton")
  local search   = GetChild(frame, "SearchButton")
  local more     = GetChild(frame, "MoreButton", "SearchOptionsButton")
  local addList  = GetChild(frame, "AddToListButton")
  local fullScan = GetChild(frame, "FullScanButton")

  -- Ensure every button is at its natural text width before we measure them.
  for _, button in ipairs({ reset, search, more, addList, fullScan }) do
    if button and button.dynamicResizeMinWidth and DynamicResizeButton_Resize then
      DynamicResizeButton_Resize(button)
    end
  end

  local LABEL_LEFT   = 16  -- label inset from the row's left
  local INPUT_GAP    = 12  -- label -> input
  local RESET_GAP    = 3   -- input -> reset (X)
  local GAP          = 8   -- between buttons
  local RIGHT_MARGIN = 14  -- keep the last button clear of the frame's right edge

  local function Width(f)
    return (f and f.GetWidth and f:GetWidth()) or 0
  end

  local labelW = 70
  if label and label.GetStringWidth then
    labelW = math.ceil(label:GetStringWidth() or 0)
    if labelW <= 0 then
      labelW = 70
    end
  end
  local inputStart = LABEL_LEFT + labelW + INPUT_GAP

  -- Size the input to the space LEFT OVER after the five buttons, so the whole row always
  -- fits inside the 768px AuctionFrame and the Full Scan button never spills past the right
  -- edge (the bug: a fixed 240px input + the wide buttons overflowed). Falls back to a
  -- fixed width until the frame has a measured width (very first OnLoad).
  local inputW = 200
  local frameW = Width(frame)
  if frameW > 200 then
    local buttonsW = Width(reset) + Width(search) + Width(more) + Width(addList) + Width(fullScan)
    local gapsW = RESET_GAP + GAP * 4
    inputW = frameW - RIGHT_MARGIN - buttonsW - gapsW - inputStart
  end
  if inputW < 140 then
    inputW = 140
  elseif inputW > 300 then
    inputW = 300
  end

  if input then
    Clear(input)
    input:SetPoint("TOPLEFT", frame, "TOPLEFT", inputStart, -6)
    if input.SetSize then
      input:SetSize(inputW, 22)
    end
  end
  -- Label to the LEFT of the input, vertically centred on it.
  if label and input then
    Clear(label)
    label:SetPoint("RIGHT", input, "LEFT", -INPUT_GAP, 0)
  end
  -- Reset ("X") hugs the input's right edge.
  if reset and input then
    Clear(reset)
    reset:SetPoint("LEFT", input, "RIGHT", RESET_GAP, 0)
  end
  -- Search / Search Options / Add To List / Full Scan chain to the right on one centerline.
  local previous = reset or input
  for _, button in ipairs({ search, more, addList, fullScan }) do
    if button and previous then
      Clear(button)
      button:SetPoint("LEFT", previous, "RIGHT", GAP, 0)
      previous = button
    end
  end
end
