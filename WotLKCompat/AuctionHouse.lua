-- WotLK 3.3.5a compatibility: legacy Auction House API names
--
-- Auctionator's Legacy-AH code targets the Classic clients (1.15 / Wrath Classic
-- 3.4) whose AH API names differ from stock 3.3.5a (12340):
--   * PostAuction(...)        -> 3.3.5a uses StartAuction(minBid, buyout, runTime)
--   * GetOwnerAuctionItems()  -> not present on 3.3.5a (owner list auto-loads)
--   * SortAuctionSetSort(...) -> may be absent; Auctionator re-sorts results itself
-- The browse/search path uses the native QueryAuctionItems (signature adapted in
-- Source_LegacyAH/AH/Mixins/Scan.lua). NOTE: multi-stack posting is the main
-- IN-GAME test point - stock 3.3.5a clears the sell slot after each StartAuction
-- and does not auto-refill it, so this posts the placed stack once; posting
-- several stacks needs the sell-slot to be re-populated between posts.

-- PostAuction(minBid, buyoutPrice, runTime, stackSize, numStacks, ...)
-- runTime is already 1/2/3 (12h/24h/48h), matching StartAuction.
if not PostAuction then
  function PostAuction(minBid, buyoutPrice, runTime, stackSize, numStacks)
    if not StartAuction then
      return
    end
    numStacks = numStacks or 1
    for _ = 1, numStacks do
      -- Only post while an item is actually in the sell slot (stops safely after
      -- the slot empties on stock 3.3.5a).
      if GetAuctionSellItemInfo and GetAuctionSellItemInfo() == nil then
        break
      end
      StartAuction(minBid, buyoutPrice, runTime)
    end
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
