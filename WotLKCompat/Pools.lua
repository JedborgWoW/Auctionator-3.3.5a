-- WotLK 3.3.5a compatibility: object/frame pools
--
-- Backport of Blizzard's Pools.lua (added in Legion). Auctionator's bundled
-- TableBuilder and the ScrollBox shim rely on CreateFramePool /
-- CreateFramePoolCollection. Guarded so a native version wins.

if not CreatePool then

  -- Standard resetter helpers -------------------------------------------------
  function Pool_HideAndClearAnchors(pool, obj)
    obj:Hide()
    obj:ClearAllPoints()
  end
  FramePool_HideAndClearAnchors = Pool_HideAndClearAnchors
  FontStringPool_HideAndClearAnchors = Pool_HideAndClearAnchors
  TexturePool_HideAndClearAnchors = Pool_HideAndClearAnchors

  -- ObjectPoolMixin -----------------------------------------------------------
  ObjectPoolMixin = {}

  function ObjectPoolMixin:OnLoad(creationFunc, resetterFunc)
    self.creationFunc = creationFunc
    self.resetterFunc = resetterFunc
    self.activeObjects = {}
    self.inactiveObjects = {}
    self.numActiveObjects = 0
    self.disallowResetIfNew = false
  end

  function ObjectPoolMixin:Acquire()
    local numInactiveObjects = #self.inactiveObjects
    if numInactiveObjects > 0 then
      local obj = self.inactiveObjects[numInactiveObjects]
      self.activeObjects[obj] = true
      self.numActiveObjects = self.numActiveObjects + 1
      self.inactiveObjects[numInactiveObjects] = nil
      return obj, false
    end

    local newObj = self.creationFunc(self)
    if self.resetterFunc and not self.disallowResetIfNew then
      self.resetterFunc(self, newObj)
    end
    self.activeObjects[newObj] = true
    self.numActiveObjects = self.numActiveObjects + 1
    return newObj, true
  end

  function ObjectPoolMixin:Release(obj)
    if self:IsActive(obj) then
      self.inactiveObjects[#self.inactiveObjects + 1] = obj
      self.activeObjects[obj] = nil
      self.numActiveObjects = self.numActiveObjects - 1
      if self.resetterFunc then
        self.resetterFunc(self, obj)
      end
      return true
    end
    return false
  end

  function ObjectPoolMixin:ReleaseAll()
    for obj in pairs(self.activeObjects) do
      self:Release(obj)
    end
  end

  function ObjectPoolMixin:SetResetDisallowedIfNew(disallowed)
    self.disallowResetIfNew = disallowed
  end

  function ObjectPoolMixin:EnumerateActive()
    return pairs(self.activeObjects)
  end

  function ObjectPoolMixin:GetNextActive(current)
    return (next(self.activeObjects, current))
  end

  function ObjectPoolMixin:GetNextInactive(current)
    return (next(self.inactiveObjects, current))
  end

  function ObjectPoolMixin:IsActive(object)
    return (self.activeObjects[object] ~= nil)
  end

  function ObjectPoolMixin:GetNumActive()
    return self.numActiveObjects
  end

  function ObjectPoolMixin:EnumerateInactive()
    return ipairs(self.inactiveObjects)
  end

  function CreateObjectPool(creationFunc, resetterFunc)
    local pool = CreateFromMixins(ObjectPoolMixin)
    pool:OnLoad(creationFunc, resetterFunc)
    return pool
  end
  CreatePool = CreateObjectPool

  -- FramePoolMixin ------------------------------------------------------------
  FramePoolMixin = CreateFromMixins(ObjectPoolMixin)

  local function FramePoolFactory(framePool)
    return CreateFrame(framePool.frameType, nil, framePool.parent, framePool.frameTemplate)
  end

  function FramePoolMixin:OnLoad(frameType, parent, frameTemplate, resetterFunc, forbidden, frameInitializer)
    ObjectPoolMixin.OnLoad(self, FramePoolFactory, resetterFunc)
    self.frameType = frameType
    self.parent = parent
    self.frameTemplate = frameTemplate
    self.frameInitializer = frameInitializer
  end

  function FramePoolMixin:GetTemplate()
    return self.frameTemplate
  end

  function CreateFramePool(frameType, parent, frameTemplate, resetterFunc, forbidden, frameInitializer)
    local pool = CreateFromMixins(FramePoolMixin)
    pool:OnLoad(frameType, parent, frameTemplate, resetterFunc or FramePool_HideAndClearAnchors, forbidden, frameInitializer)
    return pool
  end

  -- TexturePoolMixin ----------------------------------------------------------
  TexturePoolMixin = CreateFromMixins(ObjectPoolMixin)

  local function TexturePoolFactory(texturePool)
    return texturePool.parent:CreateTexture(nil, texturePool.layer, texturePool.textureTemplate, texturePool.subLayer)
  end

  function TexturePoolMixin:OnLoad(parent, layer, subLayer, textureTemplate, resetterFunc)
    ObjectPoolMixin.OnLoad(self, TexturePoolFactory, resetterFunc)
    self.parent = parent
    self.layer = layer
    self.subLayer = subLayer
    self.textureTemplate = textureTemplate
  end

  function CreateTexturePool(parent, layer, subLayer, textureTemplate, resetterFunc)
    local pool = CreateFromMixins(TexturePoolMixin)
    pool:OnLoad(parent, layer, subLayer, textureTemplate, resetterFunc or TexturePool_HideAndClearAnchors)
    return pool
  end

  -- FontStringPoolMixin -------------------------------------------------------
  FontStringPoolMixin = CreateFromMixins(ObjectPoolMixin)

  local function FontStringPoolFactory(fontStringPool)
    return fontStringPool.parent:CreateFontString(nil, fontStringPool.layer, fontStringPool.fontStringTemplate, fontStringPool.subLayer)
  end

  function FontStringPoolMixin:OnLoad(parent, layer, subLayer, fontStringTemplate, resetterFunc)
    ObjectPoolMixin.OnLoad(self, FontStringPoolFactory, resetterFunc)
    self.parent = parent
    self.layer = layer
    self.subLayer = subLayer
    self.fontStringTemplate = fontStringTemplate
  end

  function CreateFontStringPool(parent, layer, subLayer, fontStringTemplate, resetterFunc)
    local pool = CreateFromMixins(FontStringPoolMixin)
    pool:OnLoad(parent, layer, subLayer, fontStringTemplate, resetterFunc or FontStringPool_HideAndClearAnchors)
    return pool
  end

  -- PoolCollection ------------------------------------------------------------
  FramePoolCollectionMixin = {}

  function FramePoolCollectionMixin:OnLoad()
    self.pools = {}
  end

  function FramePoolCollectionMixin:GetNumActive()
    local numActive = 0
    for _, pool in pairs(self.pools) do
      numActive = numActive + pool:GetNumActive()
    end
    return numActive
  end

  function FramePoolCollectionMixin:GetOrCreatePool(frameType, parent, template, resetterFunc, forbidden, frameInitializer)
    local pool = self:GetPool(template)
    if not pool then
      pool = self:CreatePool(frameType, parent, template, resetterFunc, forbidden, frameInitializer)
    end
    return pool
  end

  function FramePoolCollectionMixin:CreatePool(frameType, parent, template, resetterFunc, forbidden, frameInitializer)
    local pool = CreateFramePool(frameType, parent, template, resetterFunc, forbidden, frameInitializer)
    self.pools[template] = pool
    return pool
  end

  function FramePoolCollectionMixin:CreatePoolIfNeeded(frameType, parent, template, resetterFunc, forbidden, frameInitializer)
    if not self:GetPool(template) then
      self:CreatePool(frameType, parent, template, resetterFunc, forbidden, frameInitializer)
    end
  end

  function FramePoolCollectionMixin:GetPool(template)
    return self.pools[template]
  end

  function FramePoolCollectionMixin:Acquire(template)
    local pool = self:GetPool(template)
    assert(pool ~= nil, "FramePoolCollection: no pool for template " .. tostring(template))
    return pool:Acquire()
  end

  function FramePoolCollectionMixin:Release(object)
    for _, pool in pairs(self.pools) do
      if pool:IsActive(object) then
        pool:Release(object)
        return true
      end
    end
    return false
  end

  function FramePoolCollectionMixin:ReleaseAllByTemplate(template)
    local pool = self:GetPool(template)
    if pool then
      pool:ReleaseAll()
    end
  end

  function FramePoolCollectionMixin:ReleaseAll()
    for _, pool in pairs(self.pools) do
      pool:ReleaseAll()
    end
  end

  function FramePoolCollectionMixin:EnumerateActiveByTemplate(template)
    local pool = self:GetPool(template)
    if pool then
      return pool:EnumerateActive()
    end
    return nop
  end

  function FramePoolCollectionMixin:EnumerateActive()
    local currentPoolKey, currentPool = next(self.pools, nil)
    local currentObject = nil
    return function()
      if currentPool then
        currentObject = currentPool:GetNextActive(currentObject)
        while not currentObject do
          currentPoolKey, currentPool = next(self.pools, currentPoolKey)
          if currentPool then
            currentObject = currentPool:GetNextActive(currentObject)
          else
            return nil
          end
        end
      end
      return currentObject
    end
  end

  function CreateFramePoolCollection()
    local poolCollection = CreateFromMixins(FramePoolCollectionMixin)
    poolCollection:OnLoad()
    return poolCollection
  end

  CreateTexturePoolCollection = CreateFramePoolCollection
  CreatePoolCollection = CreateFramePoolCollection
end
