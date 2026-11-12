-- Run from the repository root: lua tests/buy_dialog.lua
local noop = function() end
local ready, money, warning = true, 1000, false
local bids, refreshes = 0, 0
local livePrice, liveCount, liveLink = 100, 5, 'item:1'
local page = {
  {itemLink = 'item:1', info = {[3] = 5, [10] = 100, [11] = 0}},
  {itemLink = 'item:1', info = {[3] = 5, [10] = 100, [11] = 0}},
}
Auctionator = {
  AH = {Events = {ScanResultsUpdate = 'scan', ScanAborted = 'abort', ThrottleUpdate = 'throttle'},
    IsNotThrottled = function() return ready end,
    GetCurrentPage = function() return page end,
    AbortQuery = noop, QueryAndFocusPage = noop,
    Internals = {scan = {GetCurrentPage = function() return page end, AbortQuery = noop, StartQuery = noop}, throttling = {AnyWaiting = function() return not ready end, BidPlaced = function() ready = false end}}},
  Constants = {AuctionItemInfo = {Quantity = 3, Buyout = 10, BidAmount = 11}},
  Config = {Options = {}, Get = function() return false end, Set = noop},
  EventBus = {Register = noop, Unregister = noop, Fire = noop},
  Debug = {Message = noop}, Search = {GetCleanItemLink = function(x) return x end},
  Utilities = {Message = noop, SetStacksText = noop}, Buying = {Events = {}},
}
GetMoney = function() return money end
GetAuctionItemInfo = function() return 'item', nil, liveCount, nil, nil, nil, nil, nil, nil, livePrice end
GetAuctionItemLink = function() return liveLink end
PlaceAuctionBid = function(kind, index, price)
  assert(kind == 'list' and index == 1 and price == 100)
  bids = bids + 1
end
ERR_AUCTION_BID_PLACED, ERR_ITEM_NOT_FOUND = 'purchased', 'missing'
AUCTIONATOR_L_BUY_STACK, AUCTIONATOR_L_NONE_LEFT = 'Buy Stack', 'None Left'
dofile('Source_LegacyAH/AH/Wrappers.lua')
dofile('Source_LegacyAH/Tabs/Buying/Mixins/BuyDialog.lua')
local function dialog()
  local d = setmetatable({}, {__index = AuctionatorBuyDialogMixin})
  d:Reset()
  d.auctionData = {itemLink = 'item:1', stackSize = 5, stackPrice = 100, numStacks = 2}
  d.BuyStack = {SetEnabled = function(self, v) self.enabled = v end,
    IsEnabled = function(self) return self.enabled end, SetText = noop}
  d.WarningDialog = {IsShown = function() return warning end, Hide = function() warning = false end}
  d.ChainBuy = {GetChecked = function() return false end}
  d.UpdatePurchasedCount = noop
  d.GetParent = function() return {DoMinimalRefresh = function() refreshes = refreshes + 1 end} end
  -- Keep rendering out of the event test while exercising the real load/update path.
  d.SetDetails = function(self, data, quantity, size, blacklist)
    self.auctionData, self.quantityPurchased = data, quantity
    self.lastBuyStackSize, self.blacklistedBefore = size, blacklist
    self:LoadForPurchasing()
  end
  d:FindAuctionOnCurrentPage()
  return d
end
local d = dialog()
-- Reproduce the former Buy All state: no event or UI update may buy a stack.
d.buyAll, d.buyAllPrice = true, 100
d:UpdateButtons()
d:OnEvent('PLAYER_MONEY')
d:OnEvent('CHAT_MSG_SYSTEM', ERR_AUCTION_BID_PLACED)
d:ReceiveEvent('throttle')
d:ReceiveEvent('scan', true)
d:ContinueAfterWarning()
assert(bids == 0, 'event-driven purchase')
d:BuyStackClicked()
assert(bids == 1 and d.auctionData.numStacks == 1 and d.blacklistedBefore == 1)
d:BuyStackClicked()
assert(bids == 1, 'second bid while throttled')
ready = true
d:OnEvent('CHAT_MSG_SYSTEM', ERR_AUCTION_BID_PLACED)
d:OnEvent('PLAYER_MONEY')
d:ReceiveEvent('throttle')
assert(bids == 1, 'confirmation automatically purchased another stack')
for _, state in ipairs({'price', 'quantity', 'link', 'missing', 'gold', 'warning', 'empty'}) do
  ready, money, warning = true, 1000, false
  livePrice, liveCount, liveLink = 100, 5, 'item:1'
  d = dialog()
  if state == 'price' then livePrice = 200
  elseif state == 'quantity' then liveCount = 10
  elseif state == 'link' then liveLink = 'item:2'
  elseif state == 'missing' then liveLink = nil
  elseif state == 'gold' then money = 99
  elseif state == 'warning' then warning = true
  elseif state == 'empty' then d.auctionData.numStacks = 0 end
  d:BuyStackClicked()
  assert(bids == 1, 'unsafe bid: ' .. state)
end
assert(refreshes == 4, 'changed live auctions must refresh')
print('PASS: events never buy; one click/one bid; throttle, warning, funds and live data guards')
