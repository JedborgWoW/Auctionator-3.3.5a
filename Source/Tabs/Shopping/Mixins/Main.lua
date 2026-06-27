AuctionatorShoppingTabFrameMixin = {}

local EVENTBUS_EVENTS = {
  Auctionator.Shopping.Events.ListImportFinished,
  Auctionator.Shopping.Tab.Events.ListSearchRequested,
  Auctionator.Shopping.Tab.Events.ShowHistoricalPrices,
  Auctionator.Shopping.Tab.Events.UpdateSearchTerm,
  Auctionator.Shopping.Tab.Events.BuyScreenShown,
}

function AuctionatorShoppingTabFrameMixin:DoSearch(terms, options)
  if #terms == 0 then
    return
  end

  if options == nil and Auctionator.Constants.IsLegacyAH and IsShiftKeyDown() then
    options = { searchAllPages = true }
  end

  self:StopSearch()

  self.searchRunning = true
  Auctionator.EventBus:Fire(self, Auctionator.Shopping.Tab.Events.SearchStart, terms)
  self.SearchProvider:Search(terms, options or {})
  self:StartSpinner()
end

function AuctionatorShoppingTabFrameMixin:StopSearch()
  self.searchRunning = false
  self.SearchProvider:AbortSearch()
end

function AuctionatorShoppingTabFrameMixin:StartSpinner()
  self.ListsContainer.SpinnerAnim:Play()
  self.ListsContainer.LoadingSpinner:Show()
  self.ListsContainer.ResultsText:SetText(Auctionator.Locales.Apply("LIST_SEARCH_START", self:GetAppropriateListSearchName()))
  self.ListsContainer.ResultsText:Show()
end

function AuctionatorShoppingTabFrameMixin:CloseAnyDialogs()
  for _, d in ipairs(self.dialogs) do
    if d:IsShown() then
      d:Hide()
    end
  end
end

function AuctionatorShoppingTabFrameMixin:OnLoad()
  Auctionator.EventBus:RegisterSource(self, "AuctionatorShoppingTabFrameMixin")

  self.ResultsListing:Init(self.DataProvider)

  self.dialogs = {}

  self.itemDialog = CreateFrame("Frame", "AuctionatorShoppingTabItemFrame", self, "AuctionatorShoppingItemTemplate")
  self.itemDialog:ClearAllPoints()
  self.itemDialog:SetPoint("CENTER")
  table.insert(self.dialogs, self.itemDialog)

  self.exportDialog = CreateFrame("Frame", "AuctionatorExportListFrame", self, "AuctionatorExportListTemplate")
  self.exportDialog:SetPoint("CENTER")
  table.insert(self.dialogs, self.exportDialog)

  self.importDialog = CreateFrame("Frame", "AuctionatorImportListFrame", self, "AuctionatorImportListTemplate")
  self.importDialog:SetPoint("CENTER")
  table.insert(self.dialogs, self.importDialog)

  self.exportCSVDialog = CreateFrame("Frame", nil, self, "AuctionatorExportTextFrame")
  self.exportCSVDialog:SetPoint("CENTER")
  table.insert(self.dialogs, self.exportCSVDialog)

  self.ExportButton:SetScript("OnClick", function()
    self:CloseAnyDialogs()
    self.exportDialog:Show()
  end)
  self.ImportButton:SetScript("OnClick", function()
    self:CloseAnyDialogs()
    self.importDialog:Show()
  end)

  self.itemHistoryDialog = CreateFrame("Frame", "AuctionatorItemHistoryFrame", self, "AuctionatorItemHistoryTemplate")
  self.itemHistoryDialog:SetPoint("CENTER")
  self.itemHistoryDialog:Init()

  self:SetupSearchProvider()

  self:SetupListsContainer()
  self:SetupRecentsContainer()
  self:SetupTopSearch()

  self.NewListButton:SetScript("OnClick", function()
    Auctionator.Dialogs.ShowEditBox(AUCTIONATOR_L_CREATE_LIST_DIALOG, ACCEPT, CANCEL, function(text)
      local name = Auctionator.Shopping.ListManager:GetUnusedName(text)
      Auctionator.Shopping.ListManager:Create(name)
      self.ListsContainer:ExpandList(Auctionator.Shopping.ListManager:GetByName(name))
    end)
  end)

  self.ContainerTabs:SetView(Auctionator.Config.Get(Auctionator.Config.Options.SHOPPING_LAST_CONTAINER_VIEW))

  -- Explicit search-row layout (label / input / buttons on one centerline). The inherited
  -- Retail anchors leave the input tiny and misaligned, so re-lay it deterministically in
  -- Lua after the SearchOptions child has finished its own OnLoad.
  AuctionatorLegacy_LayoutShoppingSearchRow(self.SearchOptions)

  self.shouldDefaultOpenOnShow = true
  if Auctionator.Constants.IsVanilla then
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")
  else
    self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
  end
end

function AuctionatorShoppingTabFrameMixin:SetupSearchProvider()
  self.SearchProvider:InitSearch(
    function(results)
      self.searchRunning = false
      Auctionator.EventBus:Fire(self, Auctionator.Shopping.Tab.Events.SearchEnd, results)
      self.ListsContainer.SpinnerAnim:Stop()
      self.ListsContainer.LoadingSpinner:Hide()
      self.ListsContainer.ResultsText:Hide()
    end,
    function(current, total, partialResults)
      Auctionator.EventBus:Fire(self, Auctionator.Shopping.Tab.Events.SearchIncrementalUpdate, partialResults, total, current)
      self.ListsContainer.ResultsText:SetText(Auctionator.Locales.Apply("LIST_SEARCH_STATUS", current, total, self:GetAppropriateListSearchName()))
    end
  )
end

function AuctionatorShoppingTabFrameMixin:SetupListsContainer()
  self.ListsContainer:SetOnListExpanded(function()
    if Auctionator.Config.Get(Auctionator.Config.Options.AUTO_LIST_SEARCH) then
      self.singleSearch = false
      self:DoSearch(self.ListsContainer:GetExpandedList():GetAllItems())
    end
    self.SearchOptions:OnListExpanded()
  end)
  self.ListsContainer:SetOnListCollapsed(function()
    self:StopSearch()
    self.SearchOptions:OnListCollapsed()
  end)
  self.ListsContainer:SetOnSearchTermClicked(function(list, searchTerm, index)
    self.singleSearch = true
    self:DoSearch({searchTerm})
    self.SearchOptions:SetSearchTerm(searchTerm)
    self.ListsContainer:TemporarilySelectSearchTerm(index)
  end)
  self.ListsContainer:SetOnSearchTermDelete(function(list, searchTerm, index)
    list:DeleteItem(index)
  end)
  self.ListsContainer:SetOnSearchTermEdit(function(list, searchTerm, index)
    self:CloseAnyDialogs()
    self.itemDialog:Init(AUCTIONATOR_L_LIST_EDIT_ITEM_HEADER, AUCTIONATOR_L_EDIT_ITEM)
    self.itemDialog:SetOnFinishedClicked(function(newItemString)
      list:AlterItem(index, newItemString)
    end)
    self.itemDialog:Show()
    self.itemDialog:SetItemString(searchTerm)
  end)
  self.ListsContainer:SetOnListSearch(function(list)
    self.singleSearch = false
    self:DoSearch(list:GetAllItems())
  end)
  self.ListsContainer:SetOnListEdit(function(list)
    if list:IsTemporary() then
      Auctionator.Dialogs.ShowEditBox(AUCTIONATOR_L_MAKE_PERMANENT_CONFIRM:format(list:GetName()), ACCEPT, CANCEL, function(text)
        list:Rename(text)
        list:MakePermanent()
        Auctionator.Shopping.ListManager:Sort()
        self.ListsContainer:ScrollToList(list)
      end)
    else
      Auctionator.Dialogs.ShowEditBox(AUCTIONATOR_L_RENAME_LIST_CONFIRM:format(list:GetName()), ACCEPT, CANCEL, function(text)
        list:Rename(text)
        Auctionator.Shopping.ListManager:Sort()
        self.ListsContainer:ScrollToList(list)
      end)
    end
  end)
  self.ListsContainer:SetOnListDelete(function(list)
    Auctionator.Dialogs.ShowConfirm(AUCTIONATOR_L_DELETE_LIST_CONFIRM:format(list:GetName()):gsub("%%", "%%%%"), ACCEPT, CANCEL, function()
      if Auctionator.Shopping.ListManager:GetIndexForName(list:GetName()) ~= nil then
        Auctionator.Shopping.ListManager:Delete(list:GetName())
      end
    end)
  end)

  self.ListsContainer:SetOnListItemDrag(function(list, oldIndex, newIndex)
    if oldIndex ~= newIndex then
      local old = list:GetItemByIndex(oldIndex)
      list:DeleteItem(oldIndex)
      list:InsertItem(old, newIndex)
    end
  end)
end

function AuctionatorShoppingTabFrameMixin:SetupRecentsContainer()
  self.RecentsContainer:SetOnSearchRecent(function(searchTerm)
    self.singleSearch = true
    self:DoSearch({searchTerm})
    self.SearchOptions:SetSearchTerm(searchTerm)
    self.RecentsContainer:TemporarilySelectSearchTerm(searchTerm)
  end)
  self.RecentsContainer:SetOnDeleteRecent(function(searchTerm)
    Auctionator.Shopping.Recents.DeleteEntry(searchTerm)
  end)
  self.RecentsContainer:SetOnCopyRecent(function(searchTerm)
    local list = self.ListsContainer:GetExpandedList()
    if list == nil then
      Auctionator.Utilities.Message(AUCTIONATOR_L_COPY_NO_LIST_SELECTED)
    else
      list:InsertItem(searchTerm)
      Auctionator.Utilities.Message(AUCTIONATOR_L_COPY_ITEM_ADDED:format(
        GREEN_FONT_COLOR:WrapTextInColorCode(Auctionator.Search.PrettifySearchString(searchTerm)),
        GREEN_FONT_COLOR:WrapTextInColorCode(list:GetName())
      ))
    end
  end)
end

function AuctionatorShoppingTabFrameMixin:SetupTopSearch()
  self.SearchOptions:SetOnSearch(function(searchTerm)
    if self.searchRunning then
      self:StopSearch()
    elseif searchTerm == "" and self.ListsContainer:GetExpandedList() ~= nil then
      self:DoSearch(self.ListsContainer:GetExpandedList():GetAllItems())
    else
      self.singleSearch = true
      self:DoSearch({searchTerm})
      Auctionator.Shopping.Recents.Save(searchTerm)
    end
  end)
  self.SearchOptions:SetOnMore(function(searchTerm)
    self:CloseAnyDialogs()
    self.itemDialog:Init(AUCTIONATOR_L_LIST_EXTENDED_SEARCH_HEADER, AUCTIONATOR_L_SEARCH)
    self.itemDialog:SetOnFinishedClicked(function(searchTerm)
      self.SearchOptions:SetSearchTerm(searchTerm)
      self.singleSearch = true
      self:DoSearch({searchTerm})
      Auctionator.Shopping.Recents.Save(searchTerm)
    end)

    self.itemDialog:Show()
    self.itemDialog:SetItemString(searchTerm)
  end)
  self.SearchOptions:SetOnAddToList(function(searchTerm)
    self.ListsContainer:GetExpandedList():InsertItem(searchTerm)
    self.ListsContainer:ScrollToListEnd()
  end)
end

function AuctionatorShoppingTabFrameMixin:GetAppropriateListSearchName()
  if self.singleSearch or not self.ListsContainer:GetExpandedList() then
    return AUCTIONATOR_L_NO_LIST
  else
    return self.ListsContainer:GetExpandedList():GetName()
  end
end

function AuctionatorShoppingTabFrameMixin:ReceiveEvent(eventName, eventData)
  if eventName == Auctionator.Shopping.Events.ListImportFinished then
    self.ListsContainer:ExpandList(Auctionator.Shopping.ListManager:GetByName(eventData))

  elseif eventName == Auctionator.Shopping.Tab.Events.ListSearchRequested then
    self.ContainerTabs:SetView(Auctionator.Constants.ShoppingListViews.Lists)
    self.ListsContainer:ExpandList(eventData)
    if not Auctionator.Config.Get(Auctionator.Config.Options.AUTO_LIST_SEARCH) then
      self.singleSearch = false
      self:DoSearch(eventData:GetAllItems())
    end

  elseif eventName == Auctionator.Shopping.Tab.Events.ShowHistoricalPrices then
    self:CloseAnyDialogs()
    self.itemHistoryDialog:Show()

  elseif eventName == Auctionator.Shopping.Tab.Events.UpdateSearchTerm then
    self.SearchOptions:SetSearchTerm(eventData)

  elseif eventName == Auctionator.Shopping.Tab.Events.BuyScreenShown then
    self:StopSearch()
  end
end

function AuctionatorShoppingTabFrameMixin:OnEvent(eventName, ...)
  if eventName == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
    local showType = ...
    if showType == Enum.PlayerInteractionType.Auctioneer then
      self.shouldDefaultOpenOnShow = true
    end
  elseif eventName == "AUCTION_HOUSE_CLOSED" then
    self.shouldDefaultOpenOnShow = true
  end
end

function AuctionatorShoppingTabFrameMixin:OnShow()
  self.SearchOptions:FocusSearchBox()
  Auctionator.EventBus:Register(self, EVENTBUS_EVENTS)

  self:NormalizeVisuals()

  if self.shouldDefaultOpenOnShow then
    self:OpenDefaultList()
    self.shouldDefaultOpenOnShow = false
  end
end

-- Force the Shopping tab to match the Cancelling tab visually (the source of truth).
-- Cancelling reads well because ONE dark inset (AuctionatorInsetTemplate) sits behind its
-- results listing and the frame is symmetric. Shopping has a left sidebar too, so here we:
--   * wrap the results listing with its inset using Cancelling's exact margins;
--   * give the sidebar an IDENTICAL inset (same fill + InsetFrameTemplate4 border) sized to
--     the SAME top/bottom as the results inset, so left and right read as one panel system
--     (the old code used a different colour + soft tooltip border here -> the mismatch);
--   * lay New List / Import / Export on one bottom-left Y and Export Results bottom-right,
--     all clearly BELOW the panels (no floating, footer separated);
--   * keep all passive backgrounds strictly behind headers / rows / buttons.
-- Re-asserted on every show because the 3.3.5a XML parser does not reliably honour the
-- inherited/dotted anchors these frames were authored with.
function AuctionatorShoppingTabFrameMixin:NormalizeVisuals()
  -- Search row: re-asserted here (not just OnLoad) because only now is the frame width
  -- measured, so the input is sized to fit and Full Scan stays inside the frame.
  AuctionatorLegacy_LayoutShoppingSearchRow(self.SearchOptions)

  -- Full-width opaque dark background. Same StretchFullWidth as Selling/Cancelling, but with a
  -- LOWER bottom (default 2 -> -48, i.e. ~50px further down). WHY: the panel's two bottom
  -- corners showed stone "notches" -- AuctionFrame's stone frame draws over the inset there and
  -- the inset cannot be raised above it (AuctionatorInsetTemplate has useParentLevel="true", so
  -- SetFrameLevel on it is ignored on 3.3.5a). Extending the inset's bottom edge DOWN past the
  -- corner ornaments simply moves its corners clear of them -- no notch, no layering fight.
  -- Confirmed in-game. (Shopping only; Selling/Cancelling keep the default bottom and are fine,
  -- since their bottom corners are covered by their action buttons.)
  Auctionator.Visual.StretchFullWidth(self.ShoppingResultsInset, self, self.ResultsListing, nil, -48)
  Auctionator.Visual.SendToBack(
    self.ShoppingResultsInset,
    self.ResultsListing, self.ListsContainer, self.RecentsContainer, self.ContainerTabs
  )
  Auctionator.Visual.NormalizeHeaders(self.ResultsListing)

  -- LEFT-EDGE ROOT-CAUSE FIX (Shopping only; Selling/Cancelling untouched).
  -- Measured: the inset frame is at AuctionFrame+18, identical to Cancelling. The remaining
  -- left overhang is NOT the inset position but the two things that live LEFT of it on the
  -- Shopping tab (Selling/Cancelling have no left sidebar, so they never hit this):
  local inset = self.ShoppingResultsInset
  --   (a) The inset's dark Bg texture is authored with relativeKey="$parent" anchors. The
  --       3.3.5a XML parser does not reliably resolve those, so the fill can render wider
  --       than its frame and bleed past the left edge. Pin it explicitly to the frame.
  if inset.Bg then
    inset.Bg:ClearAllPoints()
    inset.Bg:SetAllPoints(inset)
    -- Re-assert the dark fill colour deterministically (matches AuctionatorInsetTemplate).
    inset.Bg:SetTexture(0.04, 0.04, 0.05, 1.0)
  end
  --   (a2) Hide the beveled border (InsetFrameTemplate4) for a flat, solid dark rectangle.
  --        The opaque Bg already fills the whole panel, so the bevel adds nothing on this big
  --        empty panel and its corner pieces only muddy the edges. (Shopping only --
  --        Selling/Cancelling keep their bevel and are NOT touched.)
  local insetBorder = select(1, inset:GetChildren())
  if insetBorder and insetBorder.Hide then
    insetBorder:Hide()
  end
  --   (b) Confine the lists/recents sidebar to the LEFT column of the dark panel. The authored
  --       XML anchors (point="TOP" + "BOTTOM" + "LEFT" together) pin the horizontal CENTRE to
  --       the tab frame, which over-constrains the frame so it STRETCHES to FULL WIDTH -- an
  --       expanded list's rows (sized to the container width, ListsContainer.lua) then ran
  --       across the whole panel, over the results columns. Re-anchor by the LEFT EDGE
  --       (TOPLEFT + BOTTOMLEFT, no centre-pin) with an explicit width that ends before the
  --       results listing (which starts at parent+285), so it stays a narrow left sidebar
  --       inside the dark panel.
  local SIDEBAR_W = 255
  self.ListsContainer:ClearAllPoints()
  self.ListsContainer:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -2)
  self.ListsContainer:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 4, 2)
  self.ListsContainer:SetWidth(SIDEBAR_W)
  self.RecentsContainer:ClearAllPoints()
  self.RecentsContainer:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -2)
  self.RecentsContainer:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 4, 2)
  self.RecentsContainer:SetWidth(SIDEBAR_W)
  -- List rows are sized to the container width when populated, so refresh now that it is narrow
  -- (otherwise rows built before this width change keep the old full-width size).
  if self.ListsContainer.Populate then
    self.ListsContainer:Populate()
  end

  -- The lists/recents search-status text used a broken 3.3.5a anchor and floated OUTSIDE
  -- the window (the "Searching for items in no list..." that appeared on Load more / scan);
  -- pin it (and its spinner) to the panel centre so it stays inside.
  local listsSpinner = self.ListsContainer and self.ListsContainer.LoadingSpinner
  if listsSpinner then
    listsSpinner:ClearAllPoints()
    listsSpinner:SetPoint("CENTER", self.ShoppingResultsInset, "CENTER", 0, 0)
  end
  local listsText = self.ListsContainer and self.ListsContainer.ResultsText
  if listsText then
    listsText:ClearAllPoints()
    listsText:SetPoint("CENTER", self.ShoppingResultsInset, "CENTER", 0, 0)
  end

  -- The separate sidebar inset and any stale theme background are no longer needed.
  local sidebarInset = Auctionator.Visual.EnsureInsetPanel(self, "SidebarInset")
  sidebarInset:Hide()
  if self.SidebarBg then
    self.SidebarBg:Hide()
  end

  -- Footer: drop the whole row onto the very bottom edge, level with the AH money display
  -- (gold/silver/copper), to the RIGHT of it. New List anchors to AuctionFrameMoneyFrame's
  -- right (same pattern the Selling tab uses for its History button); Import / Export /
  -- Export Results chain off New List, so they all land on that one bottom line.
  self.NewListButton:ClearAllPoints()
  if AuctionFrameMoneyFrame then
    self.NewListButton:SetPoint("LEFT", AuctionFrameMoneyFrame, "RIGHT", 20, 0)
  else
    self.NewListButton:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 150, 8)
  end
  Auctionator.Visual.NormalizeFooter(
    { self.ImportButton, self.ExportButton },
    { frame = self.NewListButton, point = "BOTTOMLEFT", relPoint = "BOTTOMRIGHT", x = 12, y = 0 },
    8
  )
  -- Export Results chains after Export so all four footer buttons form one bottom-left row
  -- (New List | Import | Export | Export Results). The full-width panel made anchoring to
  -- the panel's left edge collide with New List.
  self.ExportCSV:ClearAllPoints()
  self.ExportCSV:SetPoint("LEFT", self.ExportButton, "RIGHT", 12, 0)
  self.ExportCSV:SetPoint("BOTTOM", self.NewListButton, "BOTTOM")

  -- Interactive controls draw above the passive insets.
  Auctionator.Visual.RaiseAbove(self.NewListButton, self.ShoppingResultsInset, sidebarInset)
  Auctionator.Visual.RaiseAbove(self.ImportButton, self.ShoppingResultsInset, sidebarInset)
  Auctionator.Visual.RaiseAbove(self.ExportButton, self.ShoppingResultsInset, sidebarInset)
  Auctionator.Visual.RaiseAbove(self.ExportCSV, self.ShoppingResultsInset, sidebarInset)

  -- HEADER BLEED FIX 2 (reset/clear "X" button). It inherits UIPanelButtonTemplate, so it
  -- carries the dark stone button background (UI-Panel-Button-Up) behind the small red "no"
  -- icon -- that is the dark patch beside the red button. Blank the button-chrome textures so
  -- only the red icon shows, and pin the icon (its template texture has no anchors) to fill it.
  local resetBtn = self.SearchOptions and self.SearchOptions.ResetSearchStringButton
  if resetBtn then
    if resetBtn.SetNormalTexture then resetBtn:SetNormalTexture("") end
    if resetBtn.SetPushedTexture then resetBtn:SetPushedTexture("") end
    if resetBtn.SetDisabledTexture then resetBtn:SetDisabledTexture("") end
    if resetBtn.SetHighlightTexture then resetBtn:SetHighlightTexture("") end
    if resetBtn.texture then
      resetBtn.texture:ClearAllPoints()
      resetBtn.texture:SetAllPoints(resetBtn)
    end
  end

end

function AuctionatorShoppingTabFrameMixin:OnHide()
  if self.searchRunning then
    self:StopSearch()
  end
  Auctionator.EventBus:Unregister(self, EVENTBUS_EVENTS)
end

function AuctionatorShoppingTabFrameMixin:ExportCSVClicked()
  self:CloseAnyDialogs()
  self.DataProvider:GetCSV(function(result)
    self.exportCSVDialog:SetExportString(result)
    self.exportCSVDialog:Show()
  end)
end

function AuctionatorShoppingTabFrameMixin:OpenDefaultList()
  local listName = Auctionator.Config.Get(Auctionator.Config.Options.DEFAULT_LIST)

  if listName == Auctionator.Constants.NO_LIST then
    return
  end

  local listIndex = Auctionator.Shopping.ListManager:GetIndexForName(listName)

  if listIndex ~= nil then
    self.ListsContainer:CollapseList()
    self.ContainerTabs:SetView(Auctionator.Constants.ShoppingListViews.Lists)
    self.ListsContainer:ExpandList(Auctionator.Shopping.ListManager:GetByIndex(listIndex))
  end
end
