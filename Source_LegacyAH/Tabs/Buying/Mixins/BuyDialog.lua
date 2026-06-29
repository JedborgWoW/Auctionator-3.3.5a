AuctionatorBuyDialogMixin = {}

local QUERY_EVENTS = {
  Auctionator.AH.Events.ScanResultsUpdate,
  Auctionator.AH.Events.ScanAborted,
}

local EVENTS = {
  Auctionator.AH.Events.ThrottleUpdate,
}

local MONEY_EVENTS = {
  "PLAYER_MONEY",
  "UI_ERROR_MESSAGE",
  "CHAT_MSG_SYSTEM",
}

function AuctionatorBuyDialogMixin:OnLoad()
  -- The XML frameStrata="Dialog" enum is not reliably honored on 3.3.5a, so the
  -- dialog stayed at the listing's strata and the higher-level result rows ate the
  -- clicks meant for its Buy Stack / Close buttons. Force it above the listing.
  self:SetFrameStrata("DIALOG")
  self:SetToplevel(true)
  self:RegisterForDrag("LeftButton")
  self.NumberPurchased:SetText(AUCTIONATOR_L_ALREADY_PURCHASED_X:format(15))
  self.PurchaseDetails:SetText(AUCTIONATOR_L_BUYING_X_FOR_X:format(BLUE_FONT_COLOR:WrapTextInColorCode("x20"), GetMoneyString(10998, true)))
  self.UnitPrice:SetText(AUCTIONATOR_L_BRACKETS_X_EACH:format(GetMoneyString(550, true)))
  Auctionator.EventBus:RegisterSource(self, "BuyDialogMixin")

  self:Reset()
end

function AuctionatorBuyDialogMixin:Reset()
  self.auctionData = nil
  self.buyInfo = nil
  self.blacklistedBefore = 0
  self.gotAllResults = true
  self.quantityPurchased = 0
  self.lastBuyStackSize = 0
end

function AuctionatorBuyDialogMixin:OnEvent(eventName, ...)
  if eventName == "PLAYER_MONEY" then
    self:UpdateButtons()
  elseif eventName == "UI_ERROR_MESSAGE" then
    local _, message = ...
    if message == ERR_ITEM_NOT_FOUND and self.buyInfo ~= nil then
      Auctionator.Debug.Message("AuctionatorBuyDialogMixin", "failed purchase", self.buyInfo.index, self.lastBuyStackSize)
      self.lastBuyStackSize = 0
      self.blacklistedBefore = self.buyInfo.index
      self:SetDetails(self.auctionData, self.quantityPurchased, self.lastBuyStackSize, self.blacklistedBefore)
      self:LoadForPurchasing()
    end
  elseif eventName == "CHAT_MSG_SYSTEM" then
    local message = ...
    if message == ERR_AUCTION_BID_PLACED then
      self.quantityPurchased = self.quantityPurchased + self.lastBuyStackSize
      self:SetDetails(self.auctionData, self.quantityPurchased, self.lastBuyStackSize, self.blacklistedBefore)
      self:LoadForPurchasing()
    end
  end
end

function AuctionatorBuyDialogMixin:OnShow()
  Auctionator.EventBus:Register(self, EVENTS)
  FrameUtil.RegisterFrameForEvents(self, MONEY_EVENTS)
  self.ChainBuy:SetChecked(Auctionator.Config.Get(Auctionator.Config.Options.CHAIN_BUY_STACKS))

  -- Mouse-input layering fix (re-asserted on every show, after the dialog reaches its
  -- shown/raised frame level). The modal Overlay (enableMouse, spans the whole tab to
  -- block click-through to the listing) is declared with useParentLevel="true", which
  -- stock 3.3.5a does NOT honor -- it landed ABOVE the Buy Stack / Close buttons and
  -- swallowed their clicks (only the ChainBuy checkbox, which sits higher, still
  -- toggled). Pin the Overlay just above the dialog (still over the listing via the
  -- DIALOG strata) and raise the interactive controls clearly above the Overlay.
  local base = self:GetFrameLevel()
  self.Overlay:SetFrameLevel(base + 1)
  self.BuyStack:SetFrameLevel(base + 5)
  self.BuyAll:SetFrameLevel(base + 5)
  self.Cancel:SetFrameLevel(base + 5)
  self.ChainBuy:SetFrameLevel(base + 5)
end

function AuctionatorBuyDialogMixin:OnHide()
  self:SetChainBuy()
  self.buyAll = false
  FrameUtil.UnregisterFrameForEvents(self, MONEY_EVENTS)
  if self.quantityPurchased > 0 and self.auctionData ~= nil then
    Auctionator.Utilities.Message(AUCTIONATOR_L_PURCHASED_X_XX:format(self.auctionData.itemLink, self.quantityPurchased))
  end
  Auctionator.EventBus:Unregister(self, EVENTS)
  Auctionator.EventBus:Unregister(self, QUERY_EVENTS)
  self.auctionData = nil

  self.WarningDialog:Hide()
end

function AuctionatorBuyDialogMixin:UpdatePurchasedCount(newCount)
  self.NumberPurchased:SetShown(newCount ~= 0 and not self.priceWarningTimeout)
  self.NumberPurchased:SetText(AUCTIONATOR_L_ALREADY_PURCHASED_X:format(newCount))
end

function AuctionatorBuyDialogMixin:SetDetails(auctionData, initialQuantityPurchased, lastBuyStackSize, blacklistedBefore)
  self:Reset()

  self.auctionData = auctionData
  self:Show()

  if self.auctionData == nil then
    self:Hide()
    return
  end

  self.quantityPurchased = initialQuantityPurchased or 0
  self.lastBuyStackSize = lastBuyStackSize or 0
  self.blacklistedBefore = blacklistedBefore or 0

  local stackText = BLUE_FONT_COLOR:WrapTextInColorCode("x" .. auctionData.stackSize)
  local priceText = GetMoneyString(auctionData.stackPrice, true)
  local unitPriceText = GetMoneyString(math.ceil(auctionData.stackPrice / auctionData.stackSize), true)
  self.PurchaseDetails:SetText(AUCTIONATOR_L_BUYING_X_FOR_X:format(stackText, priceText))
  self.UnitPrice:SetText(AUCTIONATOR_L_BRACKETS_X_EACH:format(unitPriceText))

  self:UpdatePurchasedCount(self.quantityPurchased)
  self:UpdateButtons()

  self:LoadForPurchasing()
end

function AuctionatorBuyDialogMixin:LoadForPurchasing()
  if self.auctionData.numStacks < 1 then
    self:UpdateButtons()
    if Auctionator.Config.Get(Auctionator.Config.Options.CHAIN_BUY_STACKS) and self.auctionData.nextEntry ~= nil and not self.auctionData.nextEntry.isOwned then
      local nextEntry = self.auctionData.nextEntry

      -- Show warning if the price increases a lot
      local oldUnitPrice = self.auctionData.stackPrice / self.auctionData.stackSize
      local newUnitPrice = nextEntry.stackPrice / nextEntry.stackSize
      local priceIncrease = math.floor((newUnitPrice - oldUnitPrice) / oldUnitPrice * 100)
      if priceIncrease > Auctionator.Constants.PriceIncreaseWarningThreshold then
        self.WarningDialog:Show()
        self.WarningDialog.Text:SetText(AUCTIONATOR_L_PRICE_INCREASE_WARNING_2:format(FormatLargeNumber(priceIncrease) .. "%"))
        self:UpdateButtons()
      end

      self:SetDetails(self.auctionData.nextEntry, self.quantityPurchased, self.lastBuyStackSize, self.blacklistedBefore)
    end
    return
  end

  Auctionator.AH.AbortQuery()
  self:FindAuctionOnCurrentPage()
  if self.buyInfo == nil then
    self.blacklistedBefore = 0
    Auctionator.EventBus:Register(self, QUERY_EVENTS)
    self.gotAllResults = false
    Auctionator.AH.QueryAndFocusPage(self.auctionData.query, self.auctionData.page)
  end

  self:UpdateButtons()
end

function AuctionatorBuyDialogMixin:ContinueAfterWarning()
  self.WarningDialog:Hide()
  self:UpdateButtons()
end

function AuctionatorBuyDialogMixin:ReceiveEvent(eventName, ...)
  if eventName == Auctionator.AH.Events.ThrottleUpdate then
    self:UpdateButtons()
  elseif eventName == Auctionator.AH.Events.ScanResultsUpdate then
    self.gotAllResults = ...
    if self.gotAllResults then
      Auctionator.EventBus:Unregister(self, QUERY_EVENTS)
    end
    if self.auctionData and self.auctionData.numStacks > 0 then
      self:FindAuctionOnCurrentPage()
      if self.buyInfo == nil then
        self:Hide()
        self:GetParent():DoMinimalRefresh()
      end
      self:UpdateButtons()
    end
  elseif eventName == Auctionator.AH.Events.ScanAborted then
    Auctionator.EventBus:Unregister(self, QUERY_EVENTS)
  end
end

function AuctionatorBuyDialogMixin:FindAuctionOnCurrentPage()
  self.buyInfo = nil

  local page = Auctionator.AH.GetCurrentPage()
  for index, auction in ipairs(page) do
    if index > self.blacklistedBefore then
      local stackPrice = auction.info[Auctionator.Constants.AuctionItemInfo.Buyout]
      local stackSize = auction.info[Auctionator.Constants.AuctionItemInfo.Quantity]
      local bidAmount = auction.info[Auctionator.Constants.AuctionItemInfo.BidAmount]
      if auction.itemLink == self.auctionData.itemLink and
         stackPrice == self.auctionData.stackPrice and
         stackSize == self.auctionData.stackSize and
         bidAmount ~= stackPrice then
        self.buyInfo = {index = index}
        break
      end
    end
  end
end

function AuctionatorBuyDialogMixin:UpdateButtons()
  self.BuyStack:SetEnabled(self.auctionData ~= nil and Auctionator.AH.IsNotThrottled() and self.buyInfo ~= nil and self.auctionData.numStacks > 0 and GetMoney() >= self.auctionData.stackPrice and not self.WarningDialog:IsShown())
  if self.auctionData and self.auctionData.numStacks > 0 then
    self.BuyStack:SetText(AUCTIONATOR_L_BUY_STACK)
  else
    self.BuyStack:SetText(AUCTIONATOR_L_NONE_LEFT)
  end
  if self.BuyAll then
    self.BuyAll:SetEnabled(self.BuyStack:IsEnabled())
  end

  -- Drive an active "Buy All": keep buying THIS price point as soon as Buy Stack becomes
  -- available again (throttle freed + the live auction was found), until it runs out, gold
  -- runs low, or the price changes. It never rolls on to a more expensive price
  -- automatically (that is Chain Buy's job, with its own warning). Re-entrancy guarded; each
  -- step still re-validates the live price inside BuyStackClicked, so a moved/changed auction
  -- can't be mis-bought.
  if self.buyAll and not self.inBuyAllStep then
    if self.auctionData ~= nil and self.auctionData.stackPrice == self.buyAllPrice
        and self.BuyStack:IsEnabled() then
      self.inBuyAllStep = true
      self:BuyStackClicked()
      self.inBuyAllStep = false
    elseif self.auctionData == nil or self.auctionData.numStacks <= 0
        or self.auctionData.stackPrice ~= self.buyAllPrice then
      self.buyAll = false
    end
  end
end

function AuctionatorBuyDialogMixin:BuyAllClicked()
  if self.auctionData == nil then
    return
  end
  -- Buy every remaining stack at the CURRENT price. UpdateButtons drives the loop (one buy
  -- each time the throttle frees), so here we just arm it and fire the first buy.
  self.buyAll = true
  self.buyAllPrice = self.auctionData.stackPrice
  self:BuyStackClicked()
end

function AuctionatorBuyDialogMixin:SetChainBuy()
  Auctionator.Config.Set(Auctionator.Config.Options.CHAIN_BUY_STACKS, self.ChainBuy:GetChecked())
end

function AuctionatorBuyDialogMixin:BuyStackClicked()
  -- Never buy past what's left (prevents the count going negative and a runaway Buy All).
  if self.auctionData == nil or self.auctionData.numStacks <= 0 then
    self.buyAll = false
    self:UpdateButtons()
    return
  end
  if self.auctionData.stackPrice > GetMoney() then
    self:UpdateButtons()
    return
  end

  self:SetChainBuy()
  self:FindAuctionOnCurrentPage()
  if self.buyInfo ~= nil then
    -- Re-validate against the LIVE auction list immediately before bidding. On
    -- 3.3.5a PlaceAuctionBid("list", index, price) addresses the current server
    -- "list"; read the buyout straight from GetAuctionItemInfo so we never bid on a
    -- stale price, and bail (forcing a refresh) if the row moved under us. This also
    -- emits the diagnostic trail for the buy pipeline.
    local index = self.buyInfo.index
    local info = { GetAuctionItemInfo("list", index) }
    local liveName = info[1]
    local liveCount = info[Auctionator.Constants.AuctionItemInfo.Quantity]
    local liveBuyout = info[Auctionator.Constants.AuctionItemInfo.Buyout]
    local liveLink = GetAuctionItemLink("list", index)
    Auctionator.Debug.Message(
      "BuyDialog:BuyStackClicked", "index", index, "name", liveName,
      "displayStackPrice", self.auctionData.stackPrice, "liveBuyout", liveBuyout,
      "liveCount", liveCount, "stackSize", self.auctionData.stackSize
    )

    local linksMatch = liveLink ~= nil and self.auctionData.itemLink ~= nil
      and Auctionator.Search.GetCleanItemLink(liveLink) == Auctionator.Search.GetCleanItemLink(self.auctionData.itemLink)
    if liveBuyout == nil or liveBuyout == 0 or liveCount ~= self.auctionData.stackSize or not linksMatch then
      Auctionator.Debug.Message("BuyDialog:BuyStackClicked aborted -- live list data changed")
      Auctionator.Utilities.Message(AUCTIONATOR_L_BUY_AUCTION_CHANGED)
      self.buyInfo = nil
      self:UpdateButtons()
      self:GetParent():DoMinimalRefresh()
      return
    end

    Auctionator.Debug.Message("BuyDialog -> PlaceAuctionBid", "list", index, liveBuyout)
    Auctionator.AH.PlaceAuctionBid(index, liveBuyout)
    self.auctionData.numStacks = self.auctionData.numStacks - 1
    -- On this server a buyout does NOT refresh the "list", so the auction we just bought
    -- stays in the page. Blacklist its index so the next find advances to the NEXT auction
    -- instead of re-bidding the one we already bought (which spent no gold, timed out with
    -- "server took too long", and drove the available count negative). When the stale page is
    -- exhausted, the existing buyInfo==nil path re-queries a fresh list (which resets this).
    self.blacklistedBefore = index
    Auctionator.Utilities.SetStacksText(self.auctionData)
    self.lastBuyStackSize = self.auctionData.stackSize
    self:UpdatePurchasedCount(self.quantityPurchased)
    Auctionator.EventBus:Fire(self, Auctionator.Buying.Events.StacksUpdated)
  end
  self:LoadForPurchasing()
end
