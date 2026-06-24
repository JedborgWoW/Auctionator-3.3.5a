-- WotLK 3.3.5a compatibility: modern ScrollBox framework (lean native shim)
--
-- Implements only the ScrollBox API Auctionator uses, backed by a native
-- ScrollFrame (clipping + scrolling) and a native Slider (scroll bar). Two
-- flavours, matching upstream:
--   * WowScrollBoxList  - virtualised list driven by a DataProvider + element
--     initializer (+ optional TableBuilder for column cells). Used by
--     ResultsListing and the Shopping lists/recents.
--   * WowScrollBox      - plain scroll of a single externally-managed content
--     frame (`ItemListingFrame`). Used by Groups/View.
--
-- Lists are bounded (RESULTS_DISPLAY_LIMIT = 100), so rows are rendered one frame
-- per entry into the scroll child rather than virtualised+recycled per-pixel;
-- frames still come from a pool so there is no per-update allocation.

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
ScrollBoxConstants = ScrollBoxConstants or {
  UpdateImmediately = true,
  UpdateQueued = false,
  RetainScrollPosition = true,
  DiscardScrollPosition = false,
  AlignBegin = 0,
  AlignCenter = 0.5,
  AlignEnd = 1,
  AlignNearest = -1,
  NoScrollInterpolation = true,
}

-- ---------------------------------------------------------------------------
-- Data providers
-- ---------------------------------------------------------------------------
local DataProviderMixin = {}
function DataProviderMixin:Init(collection)
  self.collection = collection or {}
end
function DataProviderMixin:GetSize()
  return #self.collection
end
DataProviderMixin.GetCount = DataProviderMixin.GetSize
function DataProviderMixin:Find(index)
  return self.collection[index]
end
function DataProviderMixin:Insert(elementData)
  self.collection[#self.collection + 1] = elementData
end
function DataProviderMixin:ForEach(func)
  for i, elementData in ipairs(self.collection) do
    func(elementData, i)
  end
end
function DataProviderMixin:FindElementDataIndexByPredicate(predicate)
  for i, elementData in ipairs(self.collection) do
    if predicate(elementData) then
      return i
    end
  end
  return nil
end
function DataProviderMixin:FindByPredicate(predicate)
  local i = self:FindElementDataIndexByPredicate(predicate)
  if i then return self.collection[i], i end
end

function CreateDataProvider(collection)
  local dp = CreateFromMixins(DataProviderMixin)
  dp:Init(collection)
  return dp
end

local IndexRangeDataProviderMixin = {}
function IndexRangeDataProviderMixin:Init(count)
  self.count = count or 0
end
function IndexRangeDataProviderMixin:GetSize()
  return self.count
end
IndexRangeDataProviderMixin.GetCount = IndexRangeDataProviderMixin.GetSize
function IndexRangeDataProviderMixin:Find(index)
  if index >= 1 and index <= self.count then
    return index
  end
end
function IndexRangeDataProviderMixin:FindElementDataIndexByPredicate(predicate)
  for i = 1, self.count do
    if predicate(i) then
      return i
    end
  end
end

function CreateIndexRangeDataProvider(count)
  local dp = CreateFromMixins(IndexRangeDataProviderMixin)
  dp:Init(count)
  return dp
end

-- ---------------------------------------------------------------------------
-- Linear views (mostly carriers of element extent + initializer)
-- ---------------------------------------------------------------------------
local LinearViewMixin = {}
function LinearViewMixin:Init(top, bottom, left, right, spacing)
  self.paddingTop = top or 0
  self.paddingBottom = bottom or 0
  self.paddingLeft = left or 0
  self.paddingRight = right or 0
  self.spacing = spacing or 0
  self.elementExtent = 20
end
function LinearViewMixin:SetElementExtent(extent)
  self.elementExtent = extent
end
function LinearViewMixin:GetElementExtent()
  return self.elementExtent
end
function LinearViewMixin:SetElementInitializer(template, initializer)
  self.elementType = template
  self.elementInitializer = initializer
end
-- Some callers pass an extent calculator; uniform extent is enough here.
function LinearViewMixin:SetElementExtentCalculator(_) end
function LinearViewMixin:SetPanExtent(panExtent)
  self.panExtent = panExtent
end
function LinearViewMixin:GetPanExtent()
  return self.panExtent
end
function LinearViewMixin:SetPadding(top, bottom, left, right, spacing)
  self.paddingTop, self.paddingBottom = top or 0, bottom or 0
  self.paddingLeft, self.paddingRight = left or 0, right or 0
  self.spacing = spacing or 0
end

function CreateScrollBoxListLinearView(top, bottom, left, right, spacing)
  local view = CreateFromMixins(LinearViewMixin)
  view:Init(top, bottom, left, right, spacing)
  return view
end
CreateScrollBoxLinearView = CreateScrollBoxListLinearView

-- ---------------------------------------------------------------------------
-- Frame-type detection for element pools
-- ---------------------------------------------------------------------------
local FRAME_TYPES = {
  Frame = true, Button = true, CheckButton = true, EditBox = true,
  Slider = true, StatusBar = true, ScrollFrame = true, Cooldown = true,
  ColorSelect = true, MessageFrame = true, SimpleHTML = true, Model = true,
  PlayerModel = true, GameTooltip = true,
}

local function MakeElementPool(parent, elementType)
  if FRAME_TYPES[elementType] then
    return CreateFramePool(elementType, parent, nil)
  end
  -- template name: detect its root frame type (Button is by far the common case)
  local frameType = "Button"
  local ok = pcall(function()
    local probe = CreateFrame("Button", nil, parent, elementType)
    probe:Hide()
  end)
  if not ok then
    frameType = "Frame"
  end
  return CreateFramePool(frameType, parent, elementType)
end

-- ---------------------------------------------------------------------------
-- Shared scroll mechanics (internal ScrollFrame + scroll child)
-- ---------------------------------------------------------------------------
local ScrollBoxBaseMixin = {}

function ScrollBoxBaseMixin:SetUpScroller(contentName, existingContent)
  self.panExtent = self.panExtent or 40
  self._scrollGuard = false

  local scroller = CreateFrame("ScrollFrame", nil, self)
  scroller:SetAllPoints(self)
  scroller:EnableMouseWheel(true)
  self.scroller = scroller

  -- Use a consumer-provided content child if one was given (non-list ScrollBox),
  -- otherwise create our own (list ScrollBox).
  local content = existingContent or CreateFrame("Frame", nil, scroller)
  content:SetParent(scroller)
  content:ClearAllPoints()
  content:SetPoint("TOPLEFT")
  local width = self:GetWidth()
  content:SetWidth((width and width > 0) and width or 1)
  scroller:SetScrollChild(content)
  if contentName then
    self[contentName] = content
  end
  self.scrollContent = content

  scroller:SetScript("OnSizeChanged", function(_, width)
    if width and width > 0 then content:SetWidth(width) end
    self:UpdateScrollRange()
    -- A FullUpdate that ran before this frame had a real size laid the rows out
    -- against a 0-size (clipping) scroller, so nothing was visible. Re-run it once
    -- the scroller actually has a size so the rows appear. Guarded against the
    -- re-entrancy that the content resize below would otherwise cause.
    if self.FullUpdate and self.dataProvider and not self._inFullUpdate then
      self:FullUpdate()
    end
  end)
  scroller:SetScript("OnMouseWheel", function(_, delta)
    self:ScrollByDelta(delta)
  end)
  scroller:SetScript("OnVerticalScroll", function(_, offset)
    if self.scrollBar and not self._scrollGuard then
      self._scrollGuard = true
      self.scrollBar:SetValue(offset)
      self._scrollGuard = false
    end
  end)
  scroller:SetScript("OnScrollRangeChanged", function()
    self:UpdateScrollBar()
  end)
end

function ScrollBoxBaseMixin:GetVisibleExtent()
  return self.scroller and self.scroller:GetHeight() or 0
end

function ScrollBoxBaseMixin:GetScrollRange()
  if not self.scroller or not self.scrollContent then
    return 0
  end
  return math.max(0, self.scrollContent:GetHeight() - self.scroller:GetHeight())
end

function ScrollBoxBaseMixin:GetDerivedScrollOffset()
  return self.scroller and self.scroller:GetVerticalScroll() or 0
end

function ScrollBoxBaseMixin:SetScrollOffset(offset)
  if not self.scroller then
    return
  end
  offset = Clamp(offset, 0, self:GetScrollRange())
  self.scroller:SetVerticalScroll(offset)
end

function ScrollBoxBaseMixin:ScrollToOffset(offset)
  self:SetScrollOffset(offset)
end

function ScrollBoxBaseMixin:ScrollByDelta(delta)
  self:SetScrollOffset(self:GetDerivedScrollOffset() - delta * self.panExtent)
end

function ScrollBoxBaseMixin:SetPanExtent(extent)
  self.panExtent = extent
end

function ScrollBoxBaseMixin:GetScrollPercentage()
  local range = self:GetScrollRange()
  if range <= 0 then
    return 0
  end
  return self:GetDerivedScrollOffset() / range
end

function ScrollBoxBaseMixin:SetScrollPercentage(percent)
  self:SetScrollOffset((percent or 0) * self:GetScrollRange())
end

function ScrollBoxBaseMixin:UpdateScrollBar()
  if not self.scrollBar then
    return
  end
  local range = self:GetScrollRange()
  self._scrollGuard = true
  self.scrollBar:SetMinMaxValues(0, range)
  self.scrollBar:SetValue(self:GetDerivedScrollOffset())
  self.scrollBar:SetShown(range > 0)
  self._scrollGuard = false
end

function ScrollBoxBaseMixin:UpdateScrollRange()
  -- Clamp current scroll into the new range and refresh the bar.
  self:SetScrollOffset(self:GetDerivedScrollOffset())
  self:UpdateScrollBar()
end

-- ---------------------------------------------------------------------------
-- WowScrollBox (non-list: external ItemListingFrame content)
-- ---------------------------------------------------------------------------
ScrollBoxMixin = CreateFromMixins(ScrollBoxBaseMixin)

function ScrollBoxMixin:OnLoad()
  self.panExtent = 40
end

-- Deferred: the consumer's content child (parentKey Content/ItemListingFrame/
-- ListListingFrame) only exists once the owning frame is fully built, so wire the
-- scroller up on the first SetView/use rather than in OnLoad.
function ScrollBoxMixin:EnsureScroller()
  if self.scroller then
    return
  end
  local content = self.Content or self.ItemListingFrame or self.ListListingFrame
  self:SetUpScroller(nil, content)
  -- Point every alias the consumers use at the actual scroll content.
  self.Content = self.scrollContent
  self.ItemListingFrame = self.ItemListingFrame or self.scrollContent
  self.ListListingFrame = self.ListListingFrame or self.scrollContent
end

function ScrollBoxMixin:SetView(view)
  self.view = view
  if view and view.GetPanExtent and view:GetPanExtent() then
    self.panExtent = view:GetPanExtent()
  end
  self:EnsureScroller()
end

function ScrollBoxMixin:FullUpdate()
  self:EnsureScroller()
  -- Content height is managed by the owner; just refresh the range/bar.
  self:UpdateScrollRange()
end

-- ---------------------------------------------------------------------------
-- WowScrollBoxList (DataProvider-driven list)
-- ---------------------------------------------------------------------------
ScrollBoxListMixin = CreateFromMixins(ScrollBoxBaseMixin)
ScrollBoxListMixin.Event = {
  OnDataRangeChanged = "OnDataRangeChanged",
  OnUpdate = "OnUpdate",
  OnScroll = "OnScroll",
  OnAllowSelectionChanged = "OnAllowSelectionChanged",
}

function ScrollBoxListMixin:OnLoad()
  Mixin(self, CallbackRegistryMixin)
  CallbackRegistryMixin.OnLoad(self)
  self:GenerateCallbackEvents({
    ScrollBoxListMixin.Event.OnDataRangeChanged,
    ScrollBoxListMixin.Event.OnUpdate,
    ScrollBoxListMixin.Event.OnScroll,
  })
  self:SetUpScroller("Content")
  self.tableBuilders = {}
  self.dataProvider = nil
end

function ScrollBoxListMixin:SetView(view)
  self.view = view
  if view and view.elementType and not self.framePool then
    self.framePool = MakeElementPool(self.Content, view.elementType)
  end
end

function ScrollBoxListMixin:GetElementExtent()
  return self.view and self.view:GetElementExtent() or 20
end

function ScrollBoxListMixin:RegisterTableBuilder(tableBuilder, translator)
  self.tableBuilders[#self.tableBuilders + 1] = {
    builder = tableBuilder,
    translator = translator or function(a) return a end,
  }
end

function ScrollBoxListMixin:SetDataProvider(dataProvider, retainScrollPosition)
  local savedPercent = retainScrollPosition and self:GetScrollPercentage() or nil
  self.dataProvider = dataProvider
  self:FullUpdate()
  if savedPercent then
    self:SetScrollPercentage(savedPercent)
  else
    self:SetScrollOffset(0)
  end
end

function ScrollBoxListMixin:GetDataProvider()
  return self.dataProvider
end

function ScrollBoxListMixin:FullUpdate()
  if not self.framePool then
    if self.view and self.view.elementType then
      self.framePool = MakeElementPool(self.Content, self.view.elementType)
    else
      return
    end
  end

  self._inFullUpdate = true

  -- Release current rows (and their table-builder cells).
  for frame in self.framePool:EnumerateActive() do
    for _, tb in ipairs(self.tableBuilders) do
      tb.builder:RemoveRow(frame)
    end
  end
  self.framePool:ReleaseAll()

  local dp = self.dataProvider
  local extent = self:GetElementExtent()
  local view = self.view
  local top = (view and view.paddingTop) or 0
  local spacing = (view and view.spacing) or 0
  local count = dp and dp:GetSize() or 0

  -- Make the scroll content match the visible width so rows are not laid out 1px
  -- wide (SetUpScroller's OnSizeChanged may not have run yet on first layout).
  local scrollerWidth = self.scroller and self.scroller:GetWidth() or 0
  if scrollerWidth > 0 and self.Content then
    self.Content:SetWidth(scrollerWidth)
  end
  if Auctionator and Auctionator.Debug then
    Auctionator.Debug.Message(
      "ScrollBox:FullUpdate count", count,
      "scrollerW", scrollerWidth,
      "scrollerH", self.scroller and self.scroller:GetHeight() or -1,
      "contentW", self.Content and self.Content:GetWidth() or -1,
      "extent", extent
    )
  end

  local y = top
  for i = 1, count do
    local elementData = dp:Find(i)
    local frame = self.framePool:Acquire()
    frame:SetParent(self.Content)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", self.Content, "TOPLEFT", 0, -y)
    frame:SetPoint("RIGHT", self.Content, "RIGHT", 0, 0)
    frame:SetHeight(extent)
    frame:Show()
    frame._elementData = elementData
    frame._dataIndex = i
    if view and view.elementInitializer then
      view.elementInitializer(frame, elementData)
    end
    for _, tb in ipairs(self.tableBuilders) do
      tb.builder:AddRow(frame, tb.translator(elementData))
    end
    y = y + extent + spacing
  end

  self.Content:SetHeight(math.max(y + ((view and view.paddingBottom) or 0), 1))
  self:UpdateScrollRange()

  self._inFullUpdate = false

  if self.TriggerEvent then
    self:TriggerEvent(ScrollBoxListMixin.Event.OnDataRangeChanged, true)
  end
end

function ScrollBoxListMixin:ForEachFrame(func)
  if not self.framePool then
    return
  end
  for frame in self.framePool:EnumerateActive() do
    func(frame, frame._elementData)
  end
end

function ScrollBoxListMixin:FindElementDataIndexByPredicate(predicate)
  if self.dataProvider then
    return self.dataProvider:FindElementDataIndexByPredicate(predicate)
  end
end

function ScrollBoxListMixin:GetExtentUntil(dataIndex)
  local extent = self:GetElementExtent()
  local top = (self.view and self.view.paddingTop) or 0
  return top + (dataIndex - 1) * extent
end

function ScrollBoxListMixin:ScrollToElementDataIndex(dataIndex, alignment)
  alignment = alignment or 0
  local offset = self:GetExtentUntil(dataIndex)
    - alignment * (self:GetVisibleExtent() - self:GetElementExtent())
  self:SetScrollOffset(offset)
end

function ScrollBoxListMixin:ScrollToNearest(dataIndex)
  local top = self:GetExtentUntil(dataIndex)
  local bottom = top + self:GetElementExtent()
  local viewTop = self:GetDerivedScrollOffset()
  local viewBottom = viewTop + self:GetVisibleExtent()
  if top < viewTop then
    self:SetScrollOffset(top)
  elseif bottom > viewBottom then
    self:SetScrollOffset(bottom - self:GetVisibleExtent())
  end
end

-- ---------------------------------------------------------------------------
-- Scroll bar (WowTrimScrollBar) - a Frame wrapping a native Slider
-- ---------------------------------------------------------------------------
ScrollBarMixin = {}

function ScrollBarMixin:OnLoad()
  local slider = CreateFrame("Slider", nil, self)
  slider:SetOrientation("VERTICAL")
  slider:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -16)
  slider:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 16)
  slider:SetMinMaxValues(0, 0)
  slider:SetValue(0)
  slider:SetValueStep(1)
  slider:EnableMouse(true)

  local thumb = slider:CreateTexture(nil, "OVERLAY")
  thumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  thumb:SetSize(18, 24)
  slider:SetThumbTexture(thumb)

  local bg = self:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(self)
  bg:SetTexture(0, 0, 0, 0.25)

  self.slider = slider
  slider:SetScript("OnValueChanged", function(_, value)
    self:OnValueChanged(value)
  end)
end

function ScrollBarMixin:OnValueChanged(value)
  if self.scrollBox and not self.scrollBox._scrollGuard then
    self.scrollBox:SetScrollOffset(value)
  end
end

function ScrollBarMixin:SetMinMaxValues(minValue, maxValue)
  self.slider:SetMinMaxValues(minValue, maxValue)
end

function ScrollBarMixin:SetValue(value)
  self.slider:SetValue(value)
end

function ScrollBarMixin:GetValue()
  return self.slider:GetValue()
end

-- ---------------------------------------------------------------------------
-- ScrollUtil
-- ---------------------------------------------------------------------------
ScrollUtil = ScrollUtil or {}

function ScrollUtil.RegisterScrollBoxWithScrollBar(scrollBox, scrollBar)
  scrollBox.scrollBar = scrollBar
  scrollBar.scrollBox = scrollBox
  scrollBox:UpdateScrollBar()
end

function ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
  scrollBox:SetView(view)
  ScrollUtil.RegisterScrollBoxWithScrollBar(scrollBox, scrollBar)
  scrollBox:FullUpdate()
  return view
end

function ScrollUtil.InitScrollBoxWithScrollBar(scrollBox, scrollBar, view)
  scrollBox:SetView(view)
  ScrollUtil.RegisterScrollBoxWithScrollBar(scrollBox, scrollBar)
  scrollBox:FullUpdate()
  return view
end

function ScrollUtil.RegisterTableBuilder(scrollBox, tableBuilder, translator)
  scrollBox:RegisterTableBuilder(tableBuilder, translator)
end
