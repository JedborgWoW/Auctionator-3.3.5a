-- WotLK 3.3.5a compatibility: Blizzard shared utilities
--
-- FrameUtil / EventUtil / SecondsFormatter were added to retail FrameXML well
-- after 3.3.5a. Auctionator uses them at load (event registration, addon-loaded
-- callbacks, duration formatting). All guarded.

-- ---------------------------------------------------------------------------
-- FrameUtil
-- ---------------------------------------------------------------------------
if not FrameUtil then
  FrameUtil = {}
end
if not FrameUtil.RegisterFrameForEvents then
  function FrameUtil.RegisterFrameForEvents(frame, events)
    for _, event in ipairs(events) do
      frame:RegisterEvent(event)
    end
  end
end
if not FrameUtil.UnregisterFrameForEvents then
  function FrameUtil.UnregisterFrameForEvents(frame, events)
    for _, event in ipairs(events) do
      frame:UnregisterEvent(event)
    end
  end
end

-- GetAutoCompleteRealms (connected-realm list) does not exist on 3.3.5a; there
-- are no connected realms, so return an empty list.
if not GetAutoCompleteRealms then
  function GetAutoCompleteRealms()
    return {}
  end
end

-- ---------------------------------------------------------------------------
-- EventUtil
-- ---------------------------------------------------------------------------
if not EventUtil then
  EventUtil = {}
end

-- Run callback once the named addon is loaded (or immediately if already loaded).
if not EventUtil.ContinueOnAddOnLoaded then
  function EventUtil.ContinueOnAddOnLoaded(addOnName, callback)
    if IsAddOnLoaded(addOnName) then
      callback()
      return
    end
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(self, _, loadedName)
      if loadedName == addOnName then
        self:UnregisterEvent("ADDON_LOADED")
        self:SetScript("OnEvent", nil)
        callback()
      end
    end)
  end
end

-- Run callback once after all of the given events have each fired at least once.
if not EventUtil.ContinueAfterAllEvents then
  function EventUtil.ContinueAfterAllEvents(callback, ...)
    local remaining = {}
    local count = 0
    for i = 1, select("#", ...) do
      remaining[select(i, ...)] = true
      count = count + 1
    end
    if count == 0 then
      callback()
      return
    end
    local watcher = CreateFrame("Frame")
    for event in pairs(remaining) do
      watcher:RegisterEvent(event)
    end
    watcher:SetScript("OnEvent", function(self, event)
      if remaining[event] then
        remaining[event] = nil
        self:UnregisterEvent(event)
        count = count - 1
        if count == 0 then
          self:SetScript("OnEvent", nil)
          callback()
        end
      end
    end)
  end
end

-- ---------------------------------------------------------------------------
-- SecondsFormatter (Blizzard_AuctionHouseUtil / SharedXML)
-- ---------------------------------------------------------------------------
if not SecondsFormatter then
  SecondsFormatter = {
    Abbreviation = { Truncate = 1, OneLetter = 2, TwoLetter = 3, None = 4 },
    Interval = { Seconds = 1, Minutes = 2, Hours = 3, Days = 4 },
  }
end

if not SecondsFormatterMixin then
  SecondsFormatterMixin = {}

  function SecondsFormatterMixin:Init(minInterval, abbreviation, stripIntervalWhitespace)
    self.minInterval = minInterval or SecondsFormatter.Interval.Seconds
    self.abbreviation = abbreviation or SecondsFormatter.Abbreviation.None
    self.stripIntervalWhitespace = stripIntervalWhitespace
  end

  function SecondsFormatterMixin:GetMinInterval()
    return self.minInterval or SecondsFormatter.Interval.Seconds
  end

  function SecondsFormatterMixin:GetDesiredUnitCount()
    return 4
  end

  function SecondsFormatterMixin:SetStripIntervalWhitespace(strip)
    self.stripIntervalWhitespace = strip
  end

  local UNITS = {
    { sec = 86400, interval = SecondsFormatter.Interval.Days,    fmt = DAY_ONELETTER_ABBR or "%dd" },
    { sec = 3600,  interval = SecondsFormatter.Interval.Hours,   fmt = HOUR_ONELETTER_ABBR or "%dh" },
    { sec = 60,    interval = SecondsFormatter.Interval.Minutes, fmt = MINUTE_ONELETTER_ABBR or "%dm" },
    { sec = 1,     interval = SecondsFormatter.Interval.Seconds, fmt = SECOND_ONELETTER_ABBR or "%ds" },
  }

  function SecondsFormatterMixin:Format(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    local minInterval = self:GetMinInterval()
    local maxInterval = self.GetMaxInterval and self:GetMaxInterval() or SecondsFormatter.Interval.Days
    local desired = self:GetDesiredUnitCount()
    local parts = {}
    local remaining = seconds
    for _, unit in ipairs(UNITS) do
      if unit.interval >= minInterval and unit.interval <= maxInterval then
        local count = math.floor(remaining / unit.sec)
        if count > 0 or (#parts == 0 and unit.interval == minInterval) then
          local part = unit.fmt:format(count)
          if self.stripIntervalWhitespace then
            part = part:gsub("%s", "")
          end
          parts[#parts + 1] = part
          remaining = remaining - count * unit.sec
          if #parts >= desired then
            break
          end
        end
      end
    end
    if #parts == 0 then
      return (MINUTE_ONELETTER_ABBR or "%dm"):format(0)
    end
    return table.concat(parts, " ")
  end
end
