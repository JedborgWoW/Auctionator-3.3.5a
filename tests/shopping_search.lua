-- Run from the repository root: lua tests/shopping_search.lua
local noop = function() end
local unpackValues = unpack or table.unpack
local activeQuery
Auctionator = {
  AH = {
    Events = {ScanResultsUpdate = "scan", ScanAborted = "abort"},
    AbortQuery = function() activeQuery = nil end,
  },
  Buying = {Events = {ShowForShopping = "show buy view"}},
  Shopping = {Tab = {}},
  Constants = {IsLegacyAH = true},
  Debug = {Message = noop},
  Locales = {Apply = function(key) return key end},
  Utilities = {Slice = function(list) return {unpackValues(list)} end},
}
geterrorhandler = function() return error end
IsShiftKeyDown = function() return false end
AuctionatorResultsRowTemplateMixin = {OnClick = noop}

dofile("WotLKCompat/Globals.lua")
dofile("Source/Utilities/EventBusMixin.lua")
dofile("Source/Shopping/Events.lua")
dofile("Source/Search/Mixins/MultiSearchMixin.lua")
dofile("Source/Search/Mixins/SearchProviderMixin.lua")
dofile("Source_LegacyAH/Search/Mixins/DirectSearchProviderMixin.lua")
dofile("Source/Tabs/Shopping/Mixins/Main.lua")
dofile("Source_LegacyAH/Tabs/Buying/Mixins/Main.lua")
dofile("Source_LegacyAH/Tabs/ResultsListing/Mixins/ShoppingResultsRow.lua")

local animation = {
  Play = function(self) self.playing = true end,
  Stop = function(self) self.playing = false end,
}
local spinner = {
  SpinnerAnim = animation,
  Show = function(self) self.shown = true end,
  Hide = function(self) self.shown = false end,
}
local shopping = CreateFromMixins(AuctionatorShoppingTabFrameMixin)
shopping.SearchProvider = CreateFromMixins(AuctionatorDirectSearchProviderMixin)
shopping.ListsContainer = {
  LoadingSpinner = spinner,
  SpinnerAnim = animation,
  ResultsText = {Show = noop, Hide = noop, SetText = noop},
}
shopping.singleSearch = true
shopping.SearchOptions = {FocusSearchBox = noop}
shopping.NormalizeVisuals = noop
shopping:SetupSearchProvider()
Auctionator.EventBus:RegisterSource(shopping, "shopping test")
shopping:OnShow()

local buys = CreateFromMixins(AuctionatorBuyFrameMixinForShopping)
buys.Show = noop
buys.Reset = noop
buys.HistoryPrices = {RealmHistoryDataProvider = {SetItemLink = noop}, PostingHistoryDataProvider = {SetItemLink = noop}}
buys.CurrentPrices = {SearchDataProvider = {
  SetQuery = function(_, link, callback) assert(link == "item:1"); callback() end,
  SetRequestAllResults = function(_, all) assert(all) end,
  RefreshQuery = function() activeQuery = "buy" end,
}}
Auctionator.EventBus:Register(buys, {Auctionator.Buying.Events.ShowForShopping})

activeQuery = "shopping"
shopping.searchRunning = true
shopping.SearchProvider.complete = false
shopping.SearchProvider.gotAllResults = false
shopping.SearchProvider.fullResults = {}
local row = CreateFromMixins(AuctionatorShoppingResultsRowMixin)
row.rowData = {itemLink = "item:1", entries = {{itemLink = "item:1"}}, complete = false}
row:OnClick("LeftButton")
assert(activeQuery == "buy" and not shopping.searchRunning, "shopping cleanup cancelled the buy query")

shopping.SearchProvider.Search = function(self) self.onSearchComplete({}) end
shopping:DoSearch({"item"})
assert(not animation.playing and not spinner.shown, "a synchronous search left the spinner active")
shopping:LoadAllPages({"item"})
assert(not animation.playing and not spinner.shown, "a synchronous load-more left the spinner active")
print("PASS: buy view keeps its query and synchronous searches clear the spinner")
