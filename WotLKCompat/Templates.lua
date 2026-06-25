-- WotLK 3.3.5a compatibility: backports of Blizzard templates Auctionator needs
-- that are absent on stock 3.3.5a. The templates themselves are in Templates.xml;
-- this file holds their mixins / helper globals.

-- ---------------------------------------------------------------------------
-- UIPanelDynamicResizeButtonTemplate
-- A normal UIPanelButton that sizes its width to fit its text.
-- ---------------------------------------------------------------------------
function DynamicResizeButton_Resize(button)
  if not button then return end
  local textWidth = 0
  if button.GetTextWidth then
    textWidth = button:GetTextWidth() or 0
  end
  local minWidth = button.dynamicResizeMinWidth or 40
  button:SetWidth(math.max(minWidth, textWidth + 40))
end

-- ---------------------------------------------------------------------------
-- ResizeLayoutFrame / ResizeLayoutMixin
-- Resizes the frame to the bounding box of its shown children + regions.
-- ---------------------------------------------------------------------------
ResizeLayoutMixin = {}

function ResizeLayoutMixin:OnLoad() end

function ResizeLayoutMixin:Layout()
  local left, top = self:GetLeft(), self:GetTop()
  if not left or not top then
    return
  end
  local maxRight, minBottom = left, top

  local function consider(region)
    if region == self or not region.IsShown or not region:IsShown() then
      return
    end
    local r = region.GetRight and region:GetRight()
    local b = region.GetBottom and region:GetBottom()
    if r and r > maxRight then maxRight = r end
    if b and b < minBottom then minBottom = b end
  end

  for _, child in ipairs({ self:GetChildren() }) do
    consider(child)
  end
  for _, region in ipairs({ self:GetRegions() }) do
    consider(region)
  end

  local width = maxRight - left + (self.widthPadding or 0)
  local height = top - minBottom + (self.heightPadding or 0)
  if width > 0 then self:SetWidth(width) end
  if height > 0 then self:SetHeight(height) end

  -- Owners (e.g. config ScrollBox content) hook OnCleaned to refresh scrolling.
  if self.OnCleaned then
    self:OnCleaned()
  end
end

function ResizeLayoutMixin:MarkDirty()
  self:Layout()
end

-- ---------------------------------------------------------------------------
-- NineSlicePanelTemplate
-- Cosmetic bordered panel. 3.3.5a has native SetBackdrop, so use a tooltip-like
-- border instead of the retail nine-slice atlas system.
-- ---------------------------------------------------------------------------
NineSlicePanelMixin = {}

function NineSlicePanelMixin:OnLoad()
  if self.SetBackdrop then
    self:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 16,
      insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
  end
end

-- Retail callers pass the panel's texture kit to NineSliceUtil; there is no atlas
-- texture kit on 3.3.5a, so report none.
function NineSlicePanelMixin:GetFrameLayoutTextureKit()
  return nil
end

-- NineSliceUtil: retail helper that applies atlas-based nine-slice borders. 3.3.5a
-- has no atlas system and NineSlicePanelMixin:OnLoad already draws a SetBackdrop
-- border, so these are no-ops. Without this shim every Auctionator dialog errored on
-- `NineSliceUtil.ApplyLayoutByName` (a nil global) -- e.g. the Shopping "New List"
-- dialog and the post/cancel confirmation popups.
if not NineSliceUtil then
  NineSliceUtil = {}
  function NineSliceUtil.ApplyLayout() end
  function NineSliceUtil.ApplyLayoutByName() end
  function NineSliceUtil.GetLayout() return nil end
  function NineSliceUtil.AddLayout() end
  function NineSliceUtil.DisableSharpening() end
  function NineSliceUtil.ApplyUniqueCornersLayout() end
end

-- ---------------------------------------------------------------------------
-- ButtonFrameTemplate (portrait frame; added in Cataclysm)
-- Provides self.Inset, self.TitleText, self:SetTitle(), a close button and a
-- portrait, plus the global ButtonFrameTemplate_HidePortrait().
-- ---------------------------------------------------------------------------
ButtonFrameTemplateMixin = {}

function ButtonFrameTemplateMixin:OnLoad()
  if self.SetBackdrop then
    self:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
end

function ButtonFrameTemplateMixin:SetTitle(title)
  if self.TitleText then
    self.TitleText:SetText(title)
  end
end

function ButtonFrameTemplate_HidePortrait(self)
  if self.portrait then self.portrait:Hide() end
  if self.PortraitContainer then self.PortraitContainer:Hide() end
end

function ButtonFrameTemplate_ShowPortrait(self)
  if self.portrait then self.portrait:Show() end
  if self.PortraitContainer then self.PortraitContainer:Show() end
end

-- ---------------------------------------------------------------------------
-- ScrollingEditBoxTemplate
-- A multi-line edit box inside a scroll frame. Exposes GetEditBox()/GetScrollBox()
-- the way Auctionator's import/export frames expect.
-- ---------------------------------------------------------------------------
AuctionatorScrollingEditBoxMixin = {}

function AuctionatorScrollingEditBoxMixin:OnLoad()
  local scrollFrame = CreateFrame("ScrollFrame", nil, self)
  scrollFrame:SetAllPoints(self)
  scrollFrame:EnableMouse(true)
  self.scrollFrame = scrollFrame

  local editBox = CreateFrame("EditBox", nil, scrollFrame)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:SetFontObject(ChatFontNormal)
  editBox:SetWidth(self:GetWidth())
  editBox:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
  editBox:SetScript("OnEditFocusGained", function(eb) eb:HighlightText() end)
  scrollFrame:SetScrollChild(editBox)
  self.editBox = editBox

  scrollFrame:SetScript("OnSizeChanged", function(_, width)
    editBox:SetWidth(width)
  end)
  -- Keep the cursor visible as the user types.
  editBox:SetScript("OnCursorChanged", function(eb, x, y, w, h)
    local offset = scrollFrame:GetVerticalScroll()
    local height = scrollFrame:GetHeight()
    if -y < offset then
      scrollFrame:SetVerticalScroll(-y)
    elseif -y + h > offset + height then
      scrollFrame:SetVerticalScroll(-y + h - height)
    end
    self:UpdateScrollBar()
  end)
  editBox:SetScript("OnTextChanged", function() self:UpdateScrollBar() end)

  -- Proxy presented as the "scroll box" to ScrollUtil/the scroll bar.
  local proxy = {}
  proxy._scrollGuard = false
  proxy.GetView = function() return { SetPanExtent = function() end } end
  proxy.GetScrollRange = function()
    return math.max(0, editBox:GetHeight() - scrollFrame:GetHeight())
  end
  proxy.GetDerivedScrollOffset = function() return scrollFrame:GetVerticalScroll() end
  proxy.SetScrollOffset = function(_, offset)
    scrollFrame:SetVerticalScroll(Clamp(offset, 0, proxy.GetScrollRange()))
  end
  proxy.UpdateScrollBar = function(p)
    if p.scrollBar then
      p._scrollGuard = true
      p.scrollBar:SetMinMaxValues(0, proxy.GetScrollRange())
      p.scrollBar:SetValue(scrollFrame:GetVerticalScroll())
      p.scrollBar:SetShown(proxy.GetScrollRange() > 0)
      p._scrollGuard = false
    end
  end
  self.scrollBoxProxy = proxy
end

function AuctionatorScrollingEditBoxMixin:UpdateScrollBar()
  if self.scrollBoxProxy and self.scrollBoxProxy.UpdateScrollBar then
    self.scrollBoxProxy.UpdateScrollBar(self.scrollBoxProxy)
  end
end

function AuctionatorScrollingEditBoxMixin:GetEditBox()
  return self.editBox
end

function AuctionatorScrollingEditBoxMixin:GetScrollBox()
  return self.scrollBoxProxy
end

function AuctionatorScrollingEditBoxMixin:SetText(text)
  self.editBox:SetText(text or "")
end

function AuctionatorScrollingEditBoxMixin:GetInputBox()
  return self.editBox
end
