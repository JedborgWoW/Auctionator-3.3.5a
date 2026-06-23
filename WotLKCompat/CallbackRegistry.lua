-- WotLK 3.3.5a compatibility: CallbackRegistryMixin
--
-- Backport of Blizzard's CallbackRegistry (added in BfA). Auctionator builds its
-- own registries with CreateFromMixins(CallbackRegistryMixin) *without* calling
-- OnLoad (e.g. Source/Groups/Main.lua), so every method lazily initialises the
-- callback store. The ScrollBox shim also mixes this into scroll boxes.

if not CallbackRegistryMixin then
  CallbackRegistryMixin = {}

  function CallbackRegistryMixin:OnLoad()
    self.callbacks = {}
  end

  function CallbackRegistryMixin:GenerateCallbackEvents(events)
    if not self.Event then
      self.Event = {}
    end
    for _, event in ipairs(events) do
      self.Event[event] = event
    end
  end

  function CallbackRegistryMixin:SetUndefinedEventsAllowed(allowed)
    self.undefinedEventsAllowed = allowed
  end

  -- RegisterCallback(event, func[, owner]). On trigger, func is called as
  -- func(owner, ...). If no owner is given the function itself is the owner key
  -- (so an anonymous callback can still be unregistered by reference).
  function CallbackRegistryMixin:RegisterCallback(event, func, owner)
    assert(event ~= nil, "CallbackRegistry: nil event")
    assert(type(func) == "function", "CallbackRegistry: callback must be a function")

    owner = owner or func

    if not self.callbacks then
      self.callbacks = {}
    end
    if not self.callbacks[event] then
      self.callbacks[event] = {}
    end
    self.callbacks[event][owner] = func

    return owner
  end

  -- Accepts (event, owner) and the looser (event, func, owner) form Auctionator
  -- sometimes uses; the owner is whichever of the trailing args is provided.
  function CallbackRegistryMixin:UnregisterCallback(event, arg1, arg2)
    local owner = arg2 or arg1
    if self.callbacks and self.callbacks[event] then
      self.callbacks[event][owner] = nil
      -- Also clear if the caller keyed by the function reference.
      if arg2 ~= nil and arg1 ~= nil then
        self.callbacks[event][arg1] = nil
      end
    end
  end

  function CallbackRegistryMixin:UnregisterAllCallbacks(owner)
    if not self.callbacks then
      return
    end
    for _, ownerTable in pairs(self.callbacks) do
      ownerTable[owner] = nil
    end
  end

  function CallbackRegistryMixin:TriggerEvent(event, ...)
    if not self.callbacks or not self.callbacks[event] then
      return
    end
    -- Snapshot so a callback can (un)register during dispatch without breaking
    -- the iteration.
    local snapshot = {}
    for owner, func in pairs(self.callbacks[event]) do
      snapshot[#snapshot + 1] = owner
      snapshot[#snapshot + 1] = func
    end
    for i = 1, #snapshot, 2 do
      local owner, func = snapshot[i], snapshot[i + 1]
      func(owner, ...)
    end
  end

  -- Handle-based variant used by some Blizzard widgets. Returns a handle with
  -- :Unregister().
  function CallbackRegistryMixin:RegisterCallbackWithHandle(event, func, owner)
    local registeredOwner = self:RegisterCallback(event, func, owner)
    local registry = self
    return {
      Unregister = function()
        registry:UnregisterCallback(event, registeredOwner)
      end,
    }
  end
end
