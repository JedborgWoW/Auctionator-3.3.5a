-- WotLK 3.3.5a compatibility: core globals
--
-- Stock 3.3.5a (client 12340, Lua 5.1) lacks many globals that modern WoW (and
-- therefore modern Auctionator) assumes exist. Everything here is GUARDED with
-- `if not X` so that, should a future client/patch already provide it, the
-- native version wins. This file loads first (see WotLKCompat\Manifest.xml).

-- ---------------------------------------------------------------------------
-- Project/version constants.
--
-- On stock 3.3.5a all WOW_PROJECT_* are nil, so any `WOW_PROJECT_ID ==
-- WOW_PROJECT_MAINLINE` style check is `nil == nil` == true. Auctionator's
-- Constants/Main.lua would then set BOTH IsRetail and IsVanilla true. Defining
-- the constants and pointing WOW_PROJECT_ID at WRATH_CLASSIC makes the legacy-AH
-- (wrath) branch resolve correctly: IsLegacyAH=true, IsRetail=false,
-- IsVanilla=false.
-- ---------------------------------------------------------------------------
if WOW_PROJECT_MAINLINE == nil then WOW_PROJECT_MAINLINE = 1 end
if WOW_PROJECT_CLASSIC == nil then WOW_PROJECT_CLASSIC = 2 end
if WOW_PROJECT_BURNING_CRUSADE_CLASSIC == nil then WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5 end
if WOW_PROJECT_WRATH_CLASSIC == nil then WOW_PROJECT_WRATH_CLASSIC = 11 end
if WOW_PROJECT_CATACLYSM_CLASSIC == nil then WOW_PROJECT_CATACLYSM_CLASSIC = 14 end
if WOW_PROJECT_ID == nil then WOW_PROJECT_ID = WOW_PROJECT_WRATH_CLASSIC end

-- The Legacy Auction House (old QueryAuctionItems API) is what 3.3.5a uses.
if IsUsingLegacyAuctionClient == nil then
  IsUsingLegacyAuctionClient = function() return true end
end

-- ---------------------------------------------------------------------------
-- Mixin family
-- ---------------------------------------------------------------------------
if not Mixin then
  function Mixin(object, ...)
    for i = 1, select("#", ...) do
      local mixin = select(i, ...)
      -- Tolerate a nil mixin (e.g. a Blizzard mixin table that does not exist on
      -- 3.3.5a) instead of erroring in pairs().
      if mixin then
        for k, v in pairs(mixin) do
          object[k] = v
        end
      end
    end
    return object
  end
end

if not CreateFromMixins then
  function CreateFromMixins(...)
    return Mixin({}, ...)
  end
end

if not CreateAndInitFromMixin then
  function CreateAndInitFromMixin(mixin, ...)
    local object = CreateFromMixins(mixin)
    object:Init(...)
    return object
  end
end

-- ---------------------------------------------------------------------------
-- Misc helpers
-- ---------------------------------------------------------------------------
if not nop then
  function nop() end
end

if not CreateCounter then
  function CreateCounter(initial)
    local count = initial or 0
    return function()
      count = count + 1
      return count
    end
  end
end

-- securecall/securecallfunction: on a private 3.3.5a core there is nothing to
-- secure for an addon, so just call through.
if not securecallfunction then
  function securecallfunction(func, ...)
    return func(...)
  end
end
if not securecall then
  function securecall(func, ...)
    if type(func) == "string" then
      func = _G[func]
    end
    if func then
      return func(...)
    end
  end
end

-- GenerateClosure(func, a, b, ...) -> function(...) return func(a, b, ..., ...) end
if not GenerateClosure then
  function GenerateClosure(func, ...)
    local n = select("#", ...)
    if n == 0 then
      return func
    elseif n == 1 then
      local a = ...
      return function(...) return func(a, ...) end
    elseif n == 2 then
      local a, b = ...
      return function(...) return func(a, b, ...) end
    elseif n == 3 then
      local a, b, c = ...
      return function(...) return func(a, b, c, ...) end
    else
      local bound = { ... }
      return function(...)
        local m = select("#", ...)
        local args = {}
        for i = 1, n do args[i] = bound[i] end
        for i = 1, m do args[n + i] = select(i, ...) end
        return func(unpack(args, 1, n + m))
      end
    end
  end
end
if not GenerateFlatClosure then
  GenerateFlatClosure = GenerateClosure
end

-- ---------------------------------------------------------------------------
-- Math helpers
-- ---------------------------------------------------------------------------
if not Round then
  function Round(value)
    if value < 0 then
      return math.ceil(value - 0.5)
    end
    return math.floor(value + 0.5)
  end
end

if not Clamp then
  function Clamp(value, min, max)
    if value > max then
      return max
    elseif value < min then
      return min
    end
    return value
  end
end

if not Saturate then
  function Saturate(value)
    return Clamp(value, 0.0, 1.0)
  end
end

if not Lerp then
  function Lerp(startValue, endValue, amount)
    return (1 - amount) * startValue + amount * endValue
  end
end

if not PercentageBetween then
  function PercentageBetween(value, startValue, endValue)
    if startValue == endValue then
      return 0.0
    end
    return (value - startValue) / (endValue - startValue)
  end
end

if not ClampedPercentageBetween then
  function ClampedPercentageBetween(value, startValue, endValue)
    return Saturate(PercentageBetween(value, startValue, endValue))
  end
end

if not ApproximatelyEqual then
  function ApproximatelyEqual(value, otherValue, epsilon)
    return math.abs(value - otherValue) <= (epsilon or 0.0000001)
  end
end

if not Wrap then
  function Wrap(current, max)
    return (current % max) + 1
  end
end

-- BreakUpLargeNumbers (Cataclysm+): group an integer's digits in threes. Used by
-- the bundled MoneyFrame's display formatter.
if not BreakUpLargeNumbers then
  function BreakUpLargeNumbers(value)
    value = math.floor(tonumber(value) or 0)
    local negative = value < 0
    local digits = tostring(math.abs(value))
    local separator = LARGE_NUMBER_SEPERATOR or ","
    local out, n = "", #digits
    for i = 1, n do
      out = out .. digits:sub(i, i)
      local remaining = n - i
      if remaining > 0 and remaining % 3 == 0 then
        out = out .. separator
      end
    end
    return (negative and "-" or "") .. out
  end
end

-- FormatLargeNumber is native on 3.3.5a; alias to the grouping helper if absent.
if not FormatLargeNumber then
  FormatLargeNumber = BreakUpLargeNumbers
end

-- ---------------------------------------------------------------------------
-- Table helpers
-- ---------------------------------------------------------------------------
if not CopyTable then
  function CopyTable(tbl, shallow)
    local copy = {}
    for k, v in pairs(tbl) do
      if type(v) == "table" and not shallow then
        copy[k] = CopyTable(v)
      else
        copy[k] = v
      end
    end
    return copy
  end
end

if not tInvert then
  function tInvert(tbl)
    local inverted = {}
    for k, v in pairs(tbl) do
      inverted[v] = k
    end
    return inverted
  end
end

if not tIndexOf then
  function tIndexOf(tbl, item)
    for i, v in ipairs(tbl) do
      if item == v then
        return i
      end
    end
  end
end

if not tFilter then
  function tFilter(tbl, pred, isIndexTable)
    local result = {}
    if isIndexTable then
      for i, v in ipairs(tbl) do
        if pred(v) then
          table.insert(result, v)
        end
      end
    else
      for k, v in pairs(tbl) do
        if pred(v) then
          result[k] = v
        end
      end
    end
    return result
  end
end

if not tAppendAll then
  function tAppendAll(tbl, addArray)
    for _, v in ipairs(addArray) do
      table.insert(tbl, v)
    end
  end
end

if not tDeleteItem then
  -- Returns the number of removed elements (Blizzard's contract); TableBuilder
  -- does `tDeleteItem(self.rows, row) > 0`, so returning nil crashed it.
  function tDeleteItem(tbl, item)
    local count = 0
    local index = 1
    while index <= #tbl do
      if tbl[index] == item then
        table.remove(tbl, index)
        count = count + 1
      else
        index = index + 1
      end
    end
    return count
  end
end

if not tContains then
  function tContains(tbl, item)
    return tIndexOf(tbl, item) ~= nil
  end
end

-- safepack/safeunpack used by some Blizzard utility code paths.
if not SafePack then
  function SafePack(...)
    return { n = select("#", ...), ... }
  end
end
if not SafeUnpack then
  function SafeUnpack(tbl)
    return unpack(tbl, 1, tbl.n)
  end
end

-- Expansion constants. LE_EXPANSION_LEVEL_CURRENT (and the LE_EXPANSION_* family)
-- were added in Cataclysm; absent on 3.3.5a. Auctionator's Shopping item filter
-- loops `for i = 0, LE_EXPANSION_LEVEL_CURRENT` -> nil limit error without this.
-- 3.3.5a is WotLK = expansion level 2.
if LE_EXPANSION_CLASSIC == nil then LE_EXPANSION_CLASSIC = 0 end
if LE_EXPANSION_BURNING_CRUSADE == nil then LE_EXPANSION_BURNING_CRUSADE = 1 end
if LE_EXPANSION_WRATH_OF_THE_LICH_KING == nil then LE_EXPANSION_WRATH_OF_THE_LICH_KING = 2 end
if LE_EXPANSION_LEVEL_CURRENT == nil then LE_EXPANSION_LEVEL_CURRENT = 2 end
if EXPANSION_NAME0 == nil then EXPANSION_NAME0 = "Classic" end
if EXPANSION_NAME1 == nil then EXPANSION_NAME1 = "The Burning Crusade" end
if EXPANSION_NAME2 == nil then EXPANSION_NAME2 = "Wrath of the Lich King" end

-- AUCTION_CANCEL_COST: the cancellation-fee percentage charged when cancelling an
-- auction that already has a bid. Defined as a Blizzard FrameXML global on later
-- clients but NOT on stock 3.3.5a, so the Cancelling tab's
-- `bidAmount * AUCTION_CANCEL_COST / 100` errored on a nil global. WotLK charges 5%.
if AUCTION_CANCEL_COST == nil then AUCTION_CANCEL_COST = 5 end

-- SOUNDKIT: retail keys -> 3.3.5a PlaySound string names (PlaySound on 3.3.5a
-- takes the old string identifiers, not numeric IDs).
if not SOUNDKIT then
  SOUNDKIT = {
    IG_CHARACTER_INFO_TAB = "igCharacterInfoTab",
    IG_MAINMENU_OPEN = "igMainMenuOpen",
    IG_MAINMENU_OPTION_CHECKBOX_ON = "igMainMenuOptionCheckBoxOn",
  }
end
