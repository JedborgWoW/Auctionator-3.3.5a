-- WotLK 3.3.5a compatibility: legacy Auction House API names
--
-- Auctionator's Legacy-AH code targets the Classic clients (1.15 / Wrath Classic
-- 3.4) whose AH API names differ from stock 3.3.5a (12340):
--   * PostAuction(...)        -> 3.3.5a uses the native StartAuction (see below)
--   * GetOwnerAuctionItems()  -> not present on 3.3.5a (owner list auto-loads)
--   * SortAuctionSetSort(...) -> may be absent; Auctionator re-sorts results itself
-- The browse/search path uses the native QueryAuctionItems (signature adapted in
-- Source_LegacyAH/AH/Mixins/Scan.lua).
--
-- ROOT CAUSE of "posting does not work" (fixed here): stock 3.3.5a's StartAuction
-- is the FIVE-argument native form
--     StartAuction(minBid, buyoutPrice, runTime, stackSize, numStacks)
-- The CLIENT itself posts <numStacks> stacks of <stackSize>, pulling items from
-- the bags and firing AUCTION_MULTISELL_START / _UPDATE / _FAILURE as it goes
-- (already handled by AuctionatorAHThrottlingFrameMixin). The previous shim called
-- the 3-argument form StartAuction(minBid, buyout, runTime) inside a Lua loop, so
-- it only ever posted the single stack sitting in the sell slot -- and because
-- StartAuction empties the slot, the loop broke after one iteration and multi-stack
-- posting silently failed. The native multisell events never fired (no multi-post
-- was ever initiated), which is why a stack of fragile chat-message / slot-watch
-- completion fallbacks accreted in Throttling.lua.
-- Verified against the working legacy 3.3.5a Auctionator
--   (Atr_CreateAuction_OnClick -> StartAuction(start, buyout, duration, stackSize, numStacks)
--    + AUCTION_MULTISELL_* event handlers).
-- runTime is 1/2/3 (12h/24h/48h), matching what GetDuration() yields.

-- PostAuction(minBid, buyoutPrice, runTime, stackSize, numStacks, ...)
if not PostAuction then
  function PostAuction(minBid, buyoutPrice, runTime, stackSize, numStacks)
    if not StartAuction then
      return
    end
    if Auctionator and Auctionator.Debug then
      Auctionator.Debug.Message(
        "PostAuction", "minBid", minBid, "buyout", buyoutPrice,
        "runTime", runTime, "stackSize", stackSize, "numStacks", numStacks
      )
    end
    -- Single native call: the client posts all <numStacks> stacks itself.
    StartAuction(minBid, buyoutPrice, runTime, stackSize or 1, numStacks or 1)
  end
end

-- The player's own auctions. On stock 3.3.5a the owner list is populated by the
-- engine (AUCTION_OWNED_LIST_UPDATE) when the Auctions tab is viewed; if the
-- query function is missing, no-op (the data is already available via
-- GetNumAuctionItems("owner") / GetAuctionItemInfo("owner", i)).
if not GetOwnerAuctionItems then
  function GetOwnerAuctionItems()
  end
end

-- Sort helpers. If absent on this client, no-op (Auctionator sorts results in its
-- own data providers, so the server-side sort order is not relied upon).
if not SortAuctionSetSort then
  function SortAuctionSetSort()
  end
end
if not SortAuctionApplySort then
  function SortAuctionApplySort()
  end
end

-- Deposit preview. Stock 3.3.5a has NO GetAuctionDeposit global (the Classic
-- clients do); the native function is CalculateAuctionDeposit(runTime), which
-- returns the deposit for the item currently in the sell slot for the given run
-- time (1/2/3 = 12h/24h/48h -- the same enum GetDuration() yields). Auctionator
-- calls GetAuctionDeposit(runTime, minBid, buyout, stackSize, numStacks) every
-- frame from SaleItem:OnUpdate, so a missing global spams infinitely; here we map
-- it through, scaling the per-stack figure by numStacks. Falls back to 0 when no
-- item is placed / the native is absent (the server charges the real deposit on
-- post anyway).
if not GetAuctionDeposit then
  function GetAuctionDeposit(runTime, minBid, buyout, stackSize, numStacks)
    if CalculateAuctionDeposit then
      return (CalculateAuctionDeposit(runTime) or 0) * (numStacks or 1)
    end
    return 0
  end
end
