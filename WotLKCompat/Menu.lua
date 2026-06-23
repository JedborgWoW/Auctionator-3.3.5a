-- WotLK 3.3.5a compatibility: MenuUtil + menu descriptions
--
-- Bridges the modern (10.x) menu system (MenuUtil, rootDescription:CreateButton/
-- CreateCheckbox/CreateRadio, DropdownButton:SetupMenu/GenerateMenu) onto the
-- native 3.3.5a UIDropDownMenu. TaintLess.xml already patches UIDropDownMenu.

if not MenuResponse then
  MenuResponse = {
    Open = 1,
    Close = 2,
    Refresh = 3,
    CloseAll = 4,
  }
end

-- ---------------------------------------------------------------------------
-- Menu description tree (what generators build).
-- ---------------------------------------------------------------------------
local MenuDescriptionMixin = {}

function MenuDescriptionMixin:Init()
  self.children = {}
end

local function AddEntry(self, entry)
  Mixin(entry, MenuDescriptionMixin)
  entry.children = {}
  self.children[#self.children + 1] = entry
  return entry
end

function MenuDescriptionMixin:CreateButton(text, onClick, data)
  return AddEntry(self, { kind = "button", text = text, onClick = onClick, data = data })
end

function MenuDescriptionMixin:CreateCheckbox(text, isSelected, setSelected, data)
  return AddEntry(self, { kind = "checkbox", text = text, isSelected = isSelected, setSelected = setSelected, data = data })
end

function MenuDescriptionMixin:CreateRadio(text, isSelected, setSelected, data)
  return AddEntry(self, { kind = "radio", text = text, isSelected = isSelected, setSelected = setSelected, data = data })
end

function MenuDescriptionMixin:CreateTitle(text)
  return AddEntry(self, { kind = "title", text = text })
end

function MenuDescriptionMixin:CreateDivider()
  return AddEntry(self, { kind = "divider" })
end

-- Tooltip helpers used by some menu builders; harmless no-ops here.
function MenuDescriptionMixin:SetTooltip() end
function MenuDescriptionMixin:SetEnabled() end
function MenuDescriptionMixin:SetSelected() end

local function CreateRootDescription()
  local root = CreateFromMixins(MenuDescriptionMixin)
  root:Init()
  return root
end
Auctionator_CreateMenuRootDescription = CreateRootDescription

-- ---------------------------------------------------------------------------
-- Render a description tree through UIDropDownMenu.
-- ---------------------------------------------------------------------------
local function PopulateLevel(owningMenu, level, entries)
  for _, entry in ipairs(entries) do
    local info = UIDropDownMenu_CreateInfo()
    info.text = entry.text

    if entry.kind == "title" then
      info.isTitle = true
      info.notCheckable = true
    elseif entry.kind == "divider" then
      info.notCheckable = true
      info.disabled = true
      info.text = ""
    elseif entry.kind == "checkbox" or entry.kind == "radio" then
      info.isNotRadio = (entry.kind == "checkbox")
      info.checked = entry.isSelected and entry.isSelected(entry.data) or false
      info.keepShownOnClick = true
      info.func = function()
        if entry.setSelected then
          entry.setSelected(entry.data)
        end
        if owningMenu and owningMenu._onSelectionChanged then
          owningMenu._onSelectionChanged()
        end
        CloseDropDownMenus()
      end
    else -- button
      info.notCheckable = true
      info.func = function()
        if entry.onClick then
          entry.onClick(entry.data)
        end
        CloseDropDownMenus()
      end
    end

    if entry.children and #entry.children > 0 then
      info.hasArrow = true
      info.notCheckable = true
      info.menuList = entry.children
    end

    UIDropDownMenu_AddButton(info, level)
  end
end

-- Shared hidden dropdown used to display context menus at the cursor.
local contextMenu = CreateFrame("Frame", "AuctionatorCompatContextDropDown", UIParent, "UIDropDownMenuTemplate")

local function ShowContextMenu(anchor, root)
  UIDropDownMenu_Initialize(contextMenu, function(self, level, menuList)
    PopulateLevel(self, level, menuList or root.children)
  end, "MENU")
  ToggleDropDownMenu(1, nil, contextMenu, anchor or "cursor", 0, 0)
end

-- ---------------------------------------------------------------------------
-- MenuUtil
-- ---------------------------------------------------------------------------
if not MenuUtil then
  MenuUtil = {}
end

-- MenuUtil.CreateContextMenu(ownerRegion, generator) - generator(owner, root).
function MenuUtil.CreateContextMenu(owner, generator)
  local root = CreateRootDescription()
  if generator then
    generator(owner, root)
  end
  ShowContextMenu("cursor", root)
  return {
    Close = function() CloseDropDownMenus() end,
  }
end

-- MenuUtil.CreateCheckboxContextMenu(owner, isSelected, setSelected, ...entries)
-- each entry is { text, data }.
function MenuUtil.CreateCheckboxContextMenu(owner, isSelected, setSelected, ...)
  local entries = { ... }
  return MenuUtil.CreateContextMenu(owner, function(_, root)
    for _, entry in ipairs(entries) do
      root:CreateCheckbox(entry[1], isSelected, setSelected, entry[2])
    end
  end)
end

-- MenuUtil.CreateRadioMenu(owner, isSelected, setSelected, ...entries)
-- If the owner is a dropdown button it configures the dropdown; otherwise it
-- pops a radio context menu.
function MenuUtil.CreateRadioMenu(owner, isSelected, setSelected, ...)
  local entries = { ... }
  local generator = function(_, root)
    for _, entry in ipairs(entries) do
      root:CreateRadio(entry[1], isSelected, setSelected, entry[2])
    end
  end

  if owner and owner.SetupMenu then
    owner:SetupMenu(generator)
    if owner.GenerateMenu then
      owner:GenerateMenu()
    end
    return
  end

  return MenuUtil.CreateContextMenu(owner, generator)
end

-- ---------------------------------------------------------------------------
-- DropdownButtonMixin - mixed into WowStyle1DropdownTemplate buttons (see
-- WotLKCompat\Templates.xml). Stores a generator and reflects the selected
-- entry's text on the button.
-- ---------------------------------------------------------------------------
DropdownButtonMixin = DropdownButtonMixin or {}

function DropdownButtonMixin:OnLoad_Compat()
  self._menuGenerator = nil
  self.selectedValue = nil
end

function DropdownButtonMixin:SetupMenu(generator)
  self._menuGenerator = generator
  self:GenerateMenu()
end

function DropdownButtonMixin:GetMenuDescription()
  if not self._menuGenerator then
    return nil
  end
  local root = CreateRootDescription()
  self._menuGenerator(self, root)
  return root
end

local function SetDropdownText(self, text)
  if self.Text then
    self.Text:SetText(text or "")
  elseif self.SetText then
    self:SetText(text or "")
  end
end

-- Refresh the displayed selection text from whichever entry is selected.
function DropdownButtonMixin:GenerateMenu()
  local root = self:GetMenuDescription()
  if not root then
    return
  end
  for _, entry in ipairs(root.children) do
    if entry.kind == "radio" or entry.kind == "checkbox" then
      local selected = (entry.isSelected and entry.isSelected(entry.data))
        or (self.selectedValue ~= nil and entry.data == self.selectedValue)
      if selected then
        SetDropdownText(self, entry.text)
        return
      end
    end
  end
end

function DropdownButtonMixin:SetValue(value)
  self.selectedValue = value
  self:GenerateMenu()
end

function DropdownButtonMixin:GetValue()
  return self.selectedValue
end

function DropdownButtonMixin:OpenMenu()
  local root = self:GetMenuDescription()
  if not root then
    return
  end
  ShowContextMenu(self, root)
end

function DropdownButtonMixin:CloseMenu()
  if self:IsMenuOpen() then
    CloseDropDownMenus()
  end
end

function DropdownButtonMixin:IsMenuOpen()
  return UIDROPDOWNMENU_OPEN_MENU == contextMenu
end

function DropdownButtonMixin:SetMenuOpen()
  self:OpenMenu()
end

-- Click toggles the menu (used by the WowStyle1DropdownTemplate button).
function DropdownButtonMixin:OnClick_Compat()
  if self:IsMenuOpen() then
    CloseDropDownMenus()
  else
    self:OpenMenu()
  end
end
