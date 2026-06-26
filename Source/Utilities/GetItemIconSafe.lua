-- Safe, synchronous item-icon resolution for stock WotLK 3.3.5a.
--
-- ROOT CAUSE this addresses: the modern icon path resolves an item with
-- Item:CreateFromItemID():ContinueOnItemLoad(), whose callback NEVER fires on 3.3.5a
-- for an item the client has not cached yet (matches retail for empty items, but on
-- 3.3.5a a perfectly valid auction result is simply "not cached until seen"). So search
-- results for items the player had never encountered rendered with NO icon, while
-- already-cached items showed fine -- the "only some items have icons" symptom. Worse,
-- the results cells are pooled, so a nil icon left the PREVIOUS row's icon in place.
--
-- This helper returns the best icon available right now and a guaranteed fallback
-- otherwise, so an icon region is never left blank/stale. Calling GetItemInfo() also
-- asks the server to cache the item; when it arrives GET_ITEM_INFO_RECEIVED fires and
-- the registered listings re-render (real icon replaces the placeholder).

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local function ToItemID(itemLinkOrID)
  if type(itemLinkOrID) == "number" then
    return itemLinkOrID
  end
  return tonumber(itemLinkOrID) or tonumber(string.match(tostring(itemLinkOrID), "item:(%d+)"))
end

function Auctionator.Utilities.GetItemIconSafe(itemLinkOrID, fallbackTexture)
  fallbackTexture = fallbackTexture or QUESTION_MARK
  if itemLinkOrID == nil or itemLinkOrID == "" then
    return fallbackTexture
  end

  -- 1. GetItemInfo texture (10th return); works once the item is cached, and triggers
  --    caching for next time when it is not.
  local texture = select(10, GetItemInfo(itemLinkOrID))
  if texture then
    return texture
  end

  -- 2. Some 3.3.5a cores expose a synchronous global GetItemIcon(itemID).
  if GetItemIcon then
    local itemID = ToItemID(itemLinkOrID)
    if itemID then
      local viaIcon = GetItemIcon(itemID)
      if viaIcon then
        return viaIcon
      end
    end
  end

  -- 3. Never leave the region blank/stale.
  return fallbackTexture
end

-- Listings register a refresh function; we call them (throttled) when the client
-- finishes caching items, so placeholder icons get replaced without a re-search.
local refreshCallbacks = {}
function Auctionator.Utilities.RegisterIconRefresh(callback)
  table.insert(refreshCallbacks, callback)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local queued = false
watcher:SetScript("OnEvent", function()
  if queued then
    return
  end
  queued = true
  -- Coalesce a burst of cache loads into one refresh.
  C_Timer.After(0.3, function()
    queued = false
    for _, cb in ipairs(refreshCallbacks) do
      pcall(cb)
    end
  end)
end)
