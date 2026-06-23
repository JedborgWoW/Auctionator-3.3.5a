-- WotLK 3.3.5a compatibility: C_Timer
--
-- C_Timer was added in 6.0; 3.3.5a only has frame OnUpdate. A single driver
-- frame runs all pending timers/tickers, which is cheaper than one frame each.

if not C_Timer then
  C_Timer = {}

  local driver = CreateFrame("Frame")
  local timers = {}       -- list of { at = GetTime()+delay, callback, ticker }
  local total = 0

  -- Tickers/cancellable timers return a handle with :Cancel() and :IsCancelled().
  local TimerMixin = {}
  function TimerMixin:Cancel()
    self._cancelled = true
  end
  function TimerMixin:IsCancelled()
    return self._cancelled == true
  end

  local function Schedule(delay, callback, iterations)
    local handle = setmetatable({}, { __index = TimerMixin })
    handle._cancelled = false
    handle._callback = callback
    handle._delay = delay
    handle._iterations = iterations   -- nil = run forever (ticker), number = count, false = single shot
    handle._next = GetTime() + delay
    timers[#timers + 1] = handle
    driver:Show()
    return handle
  end

  driver:Hide()
  driver:SetScript("OnUpdate", function(self, elapsed)
    if #timers == 0 then
      self:Hide()
      return
    end

    local now = GetTime()
    local i = 1
    while i <= #timers do
      local handle = timers[i]
      if handle._cancelled then
        table.remove(timers, i)
      elseif now >= handle._next then
        local cb = handle._callback
        -- Single-shot timer: remove before firing so a re-entrant Cancel is safe.
        if handle._iterations == false then
          table.remove(timers, i)
          if cb then cb(handle) end
        else
          -- Ticker (count or infinite).
          if handle._iterations ~= nil then
            handle._iterations = handle._iterations - 1
          end
          handle._next = now + handle._delay
          if cb then cb(handle) end
          if handle._iterations ~= nil and handle._iterations <= 0 then
            -- Find and remove (index may have shifted if cb scheduled more).
            for j = #timers, 1, -1 do
              if timers[j] == handle then
                table.remove(timers, j)
                break
              end
            end
          else
            i = i + 1
          end
        end
      else
        i = i + 1
      end
    end

    if #timers == 0 then
      self:Hide()
    end
  end)

  function C_Timer.After(delay, callback)
    Schedule(delay or 0, callback, false)
  end

  function C_Timer.NewTimer(delay, callback)
    return Schedule(delay or 0, callback, false)
  end

  function C_Timer.NewTicker(delay, callback, iterations)
    return Schedule(delay or 0, callback, iterations or nil)
  end
end
