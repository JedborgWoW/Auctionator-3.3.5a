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

-- Returns ONLY a valid texture-path string, never a number or nil. On 3.3.5a a valid
-- icon is always a string path; a numeric fileID (the value Classic bag-cache code can
-- produce) is NOT a valid texture here and SetTexture(number) renders a solid GREEN
-- square. So every candidate is type-checked and a numeric/empty value is rejected in
-- favour of the question-mark placeholder.
function Auctionator.Utilities.GetItemIconSafe(itemLinkOrID, fallbackTexture)
  -- 1. Authoritative: GetItemInfo texture (string) for a cached item; also triggers
  --    caching when it is not (GET_ITEM_INFO_RECEIVED then refreshes).
  if itemLinkOrID ~= nil and itemLinkOrID ~= "" then
    local texture = select(10, GetItemInfo(itemLinkOrID))
    if type(texture) == "string" and texture ~= "" then
      return texture
    end

    -- 2. Some 3.3.5a cores expose a synchronous global GetItemIcon(itemID).
    if GetItemIcon then
      local itemID = ToItemID(itemLinkOrID)
      if itemID then
        local viaIcon = GetItemIcon(itemID)
        if type(viaIcon) == "string" and viaIcon ~= "" then
          return viaIcon
        end
      end
    end
  end

  -- 3. Only honour a STRING fallback (reject numeric fileIDs -> they render green).
  if type(fallbackTexture) == "string" and fallbackTexture ~= "" then
    return fallbackTexture
  end

  -- 4. Guaranteed-valid placeholder; never blank, never green.
  return QUESTION_MARK
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
