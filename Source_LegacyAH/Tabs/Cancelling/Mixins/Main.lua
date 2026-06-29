AuctionatorCancellingFrameMixin = {}

function AuctionatorCancellingFrameMixin:OnLoad()
  Auctionator.Debug.Message("AuctionatorCancellingFrameMixin:OnLoad()")

  self.ResultsListing:Init(self.DataProvider)

  Auctionator.EventBus:Register(self, {
    Auctionator.Cancelling.Events.RequestCancel,
    Auctionator.Cancelling.Events.TotalUpdated,
  })

  self.SearchFilter:HookScript("OnTextChanged", function()
    self.DataProvider:NoQueryRefresh()
  end)

  self:SetScript("OnUpdate", self.OnUpdate)

  -- The Cancelling frame has no XML OnShow, so wire visual normalization here.
  self:SetScript("OnShow", self.NormalizeVisuals)

  -- Expose this frame so the (pooled) result rows can drive the hover Cancel button, and put the
  -- button above the rows so it is clickable. The button itself is defined in the frame's XML so
  -- its click is allowed to call the protected CancelAuction (a pooled row's click is not).
  Auctionator.Cancelling.frame = self
  if self.RowCancelButton then
    self.RowCancelButton:SetFrameStrata("HIGH")
    self.RowCancelButton:Hide()
  end
end

-- Show the hover Cancel button over the row the mouse is on, remembering its auction.
function AuctionatorCancellingFrameMixin:ShowRowCancelButton(row)
  local button = self.RowCancelButton
  if not button or not row or not row.rowData then
    return
  end
  button.auction = row.rowData
  button.attachedRow = row
  button:ClearAllPoints()
  button:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  button:Show()
end

-- Hide the button shortly after the mouse leaves the row OR the button -- unless it has moved
-- onto the other of the two (so moving from row to button doesn't make it vanish).
function AuctionatorCancellingFrameMixin:ScheduleHideRowCancelButton()
  local button = self.RowCancelButton
  if not button then
    return
  end
  C_Timer.After(0.1, function()
    if button:IsShown() and not button:IsMouseOver()
        and not (button.attachedRow and button.attachedRow:IsMouseOver()) then
      button:Hide()
    end
  end)
end

-- A pooled row is being reused for a different auction -- drop the button if it was on that row
-- so it can never act on the wrong auction.
function AuctionatorCancellingFrameMixin:DetachRowCancelButton(row)
  local button = self.RowCancelButton
  if button and button.attachedRow == row then
    button:Hide()
    button.auction = nil
    button.attachedRow = nil
  end
end

-- Issue the cancel for the hovered auction. Runs from the XML button's OnClick, so the protected
-- CancelAuction is accepted (server confirms "Auction cancelled.").
function AuctionatorCancellingFrameMixin:CancelHoveredAuction()
  local button = self.RowCancelButton
  local auctionData = button and button.auction
  if not auctionData then
    return
  end

  -- Auctions someone has bid on cost gold to cancel -> confirm first.
  local cancelCost = math.floor(((auctionData.bidAmount or 0) * (AUCTION_CANCEL_COST or 0)) / 100)
  if cancelCost > 0 then
    local dialog = StaticPopup_Show("AuctionatorConfirmBidPricePopupDialog")
    if dialog then
      dialog.data = auctionData
      MoneyFrame_Update(dialog.moneyFrame, cancelCost)
    end
    return
  end

  -- Cancel EVERY stack of this auction (same item + quantity + buyout, no bid) in this one click,
  -- exactly like the native Zirco Auctionator. The owned list does not reshuffle synchronously on
  -- this server (ownerCount is unchanged right after CancelAuction), so iterating fixed indices in
  -- a single pass is safe, and 3.3.5a allows multiple CancelAuction calls per hardware event.
  local AII = Auctionator.Constants.AuctionItemInfo
  local wantId = auctionData.itemLink and tonumber(auctionData.itemLink:match("item:(%d+)"))
  for index = 1, GetNumAuctionItems("owner") do
    local info = { GetAuctionItemInfo("owner", index) }
    local link = GetAuctionItemLink("owner", index)
    local id = link and tonumber(link:match("item:(%d+)"))
    if info[AII.SaleStatus] ~= 1
        and info[AII.Quantity] == auctionData.stackSize
        and info[AII.Buyout] == auctionData.stackPrice
        and (info[AII.BidAmount] or 0) == 0
        and id == wantId then
      CancelAuction(index)
    end
  end

  auctionData.cancelled = true
  button:Hide()
  Auctionator.EventBus
    :RegisterSource(self, "CancellingFrameRowCancel")
    :Fire(self, Auctionator.Cancelling.Events.CancelConfirmed, auctionData)
    :UnregisterSource(self)
end

-- Stretch the dark results panel edge to edge (full width) and keep it behind the rows,
-- matching the Shopping/Selling tabs. The opaque fill comes from AuctionatorInsetTemplate.
function AuctionatorCancellingFrameMixin:NormalizeVisuals()
  local inset = self.HistoricalPriceInset
  local listing = self.ResultsListing
  if inset and listing then
    -- Anchor to the wrapper (reliable content boundary), not the mis-sized tab frame.
    Auctionator.Visual.StretchFullWidth(inset, self, listing)
    Auctionator.Visual.NormalizeHeaders(listing)
  end
end

function AuctionatorCancellingFrameMixin:OnUpdate()
  GetOwnerAuctionItems(0)
end

local ConfirmBidPricePopup = "AuctionatorConfirmBidPricePopupDialog"

StaticPopupDialogs[ConfirmBidPricePopup] = {
  text = AUCTIONATOR_L_BID_EXISTING_ON_OWNED_AUCTION,
  button1 = ACCEPT,
  button2 = CANCEL,
  OnAccept = function(self)
    Auctionator.AH.CancelAuction(self.data)
    Auctionator.EventBus:RegisterSource(self, "CancellingFramePopupDialog")
      :Fire(self, Auctionator.Cancelling.Events.CancelConfirmed, self.data)
      :UnregisterSource(self)
  end,
  hasMoneyFrame = 1,
  showAlert = 1,
  timeout = 0,
  exclusive = 1,
  hideOnEscape = 1
}

function AuctionatorCancellingFrameMixin:IsAuctionShown(auctionInfo)
  local searchString = self.SearchFilter:GetText()
  if searchString ~= "" then
    local exact = searchString:match("^\"(.*)\"$")
    local name = string.lower(Auctionator.Utilities.GetNameFromLink(auctionInfo.itemLink))
    if exact then
      return name == exact
    else
      return string.find(name, string.lower(searchString), 1, true)
    end
  else
    return true
  end
end

function AuctionatorCancellingFrameMixin:ReceiveEvent(eventName, ...)
  if eventName == Auctionator.Cancelling.Events.RequestCancel then
    local auctionData = ...
    Auctionator.Debug.Message("Executing cancel request", auctionData)

    -- Prevent cancelling auctions which someone has bid on
    local cancelCost = math.floor((auctionData.bidAmount * AUCTION_CANCEL_COST) / 100)
    if cancelCost > 0 then
      local dialog = StaticPopup_Show(ConfirmBidPricePopup)
      if dialog then
        dialog.data = auctionData
        MoneyFrame_Update(dialog.moneyFrame, cancelCost);
      end
    else
      Auctionator.AH.CancelAuction(auctionData)
      Auctionator.EventBus:RegisterSource(self, "CancellingFrame")
        :Fire(self, Auctionator.Cancelling.Events.CancelConfirmed, auctionData)
    end

    PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)

  elseif eventName == Auctionator.Cancelling.Events.TotalUpdated then
    local totalOnSale, totalPending = ...

    local text = AUCTIONATOR_L_TOTAL_ON_SALE:format(
        GetMoneyString(totalOnSale, true)
      )
    if totalPending > 0 then
      text = text .. " " ..
      AUCTIONATOR_L_TOTAL_PENDING:format(
        GetMoneyString(totalPending, true)
      )
    end

    self.Total:SetText(text)
  end
end
