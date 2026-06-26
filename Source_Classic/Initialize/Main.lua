local AUCTIONATOR_EVENTS = {
  -- AH Window Initialization Events
  "AUCTION_HOUSE_SHOW",
  "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
  -- Trade Window Initialization Events
  "TRADE_SKILL_SHOW",
  -- Cache vendor prices event
  "MERCHANT_SHOW",
}

AuctionatorInitializeClassicMixin = {}

function AuctionatorInitializeClassicMixin:OnLoad()
  FrameUtil.RegisterFrameForEvents(self, AUCTIONATOR_EVENTS)
end

function AuctionatorInitializeClassicMixin:OnEvent(event, ...)
  if event == "AUCTION_HOUSE_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and (...) == Enum.PlayerInteractionType.Auctioneer) then
    self:AuctionHouseShown()
  elseif event == "TRADE_SKILL_SHOW" then
    Auctionator.CraftingInfo.Initialize()
  elseif event == "MERCHANT_SHOW" then
    Auctionator.CraftingInfo.CacheVendorPrices()
  end
end

function AuctionatorInitializeClassicMixin:AuctionHouseShown()
  Auctionator.Debug.Message("AuctionatorInitializeClassicMixin:AuctionHouseShown()")

  -- Prevents a lot of errors if loaded in retail
  if (Auctionator.Constants.IsLegacyAH and AuctionFrame == nil) or (not Auctionator.Constants.IsLegacyAH and AuctionHouseFrame == nil) then
    return
  end

  Auctionator.AH.Initialize()

  if Auctionator.State.AuctionatorFrame == nil then
    Auctionator.State.AuctionatorFrame = CreateFrame("FRAME", "AuctionatorAHFrame", AuctionFrame, "AuctionatorAHFrameTemplate")
    -- This frame is the addon's event/logic root (AUCTION_HOUSE_SHOW/CLOSED); the tab
    -- content is parented to AuctionFrame via the tab wrappers, NOT to this frame. It
    -- had no anchors/size, so it showed as a 0x0 "unanchored" phantom in /atrui. Pin it
    -- to AuctionFrame so it has a real, stable rect (no layout children depend on it,
    -- but this removes the confusing 0x0 and is harmless -- it has no mouse/textures).
    Auctionator.State.AuctionatorFrame:SetAllPoints(AuctionFrame)
  end

  FrameUtil.RegisterFrameForEvents(Auctionator.State.AuctionatorFrame, { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" })
end
