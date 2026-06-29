AuctionatorGroupsViewItemMixin = {}

function AuctionatorGroupsViewItemMixin:SetClickEvent(eventName)
  self.clickEventName = eventName
end

function AuctionatorGroupsViewItemMixin:SetItemInfo(info)
  self.itemInfo = info

  if info ~= nil then

    -- Selling slot / groups item icon. info.iconTexture from the bag cache can be a
    -- numeric fileID or otherwise invalid on 3.3.5a, which renders a solid GREEN
    -- square -- so resolve authoritatively through GetItemIconSafe (GetItemInfo first;
    -- the bag item is always cached) and only accept a string. Reset the texture region
    -- so a previous tint/coord can never leave it green/black.
    self.Icon:SetTexture(Auctionator.Utilities.GetItemIconSafe(info.itemLink, info.iconTexture))
    self.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    self.Icon:SetVertexColor(1, 1, 1, 1)
    self.Icon:SetDrawLayer("ARTWORK")
    self.Icon:Show()

    if info.selected then
      self.Icon:SetAlpha(0.8)
    else
      self.Icon:SetAlpha(1)
    end
    local selectedColor = {r=0.977, g=0.592, b=0.086}

    self.IconSelectedHighlight:SetVertexColor(selectedColor.r, selectedColor.g, selectedColor.b)
    self.IconSelectedHighlight:SetShown(info.selected)

    self.IconBorder:SetVertexColor(
      ITEM_QUALITY_COLORS[self.itemInfo.quality].r,
      ITEM_QUALITY_COLORS[self.itemInfo.quality].g,
      ITEM_QUALITY_COLORS[self.itemInfo.quality].b,
      1
    )
    self.IconBorder:SetShown(not info.selected)

    -- Stack/quantity overlay (bottom-right of the icon). The Groups view supplies
    -- info.itemCount; the Selling sale-item supplies info.count -- accept either so the
    -- Selling slot shows how many are in the stack (e.g. "8"). Hidden for a single item.
    local quantity = info.itemCount or info.count
    if type(quantity) == "number" and quantity > 1 then
      self.Text:SetText(quantity)
    else
      self.Text:SetText("")
    end

    self:ApplyQualityIcon(info.itemLink)

  else
    self.IconBorder:Hide()
    self.Icon:Hide()
    self.Text:SetText("")
    self:SetAlpha(1)

    self:HideQualityIcon()
  end

  self.initializationTime = GetTime()
end

function AuctionatorGroupsViewItemMixin:OnEnter()
  if GetTime() - self.initializationTime > 0 then
    self:UpdateTooltip()
  end
end

function AuctionatorGroupsViewItemMixin:UpdateTooltip()
  if self.itemInfo ~= nil then
    if IsModifiedClick("DRESSUP") then
      ShowInspectCursor();
    else
      ResetCursor()
    end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if Auctionator.Utilities.IsPetLink(self.itemInfo.itemLink) then
      BattlePetToolTip_ShowLink(self.itemInfo.itemLink)
    else
      GameTooltip:SetHyperlink(self.itemInfo.itemLink)
      GameTooltip:Show()
    end
  end
end

function AuctionatorGroupsViewItemMixin:OnLeave()
  ResetCursor()
  if BattlePetTooltip then
    BattlePetTooltip:Hide()
  end
  GameTooltip:Hide()
end

function AuctionatorGroupsViewItemMixin:OnClick(button)
  if self.itemInfo ~= nil then
    if IsModifiedClick("DRESSUP") then
      -- Retail vs Classic functions
      (DressUpLink or DressUpItemLink)(self.itemInfo.itemLink)

    elseif IsModifiedClick("CHATLINK") then
      Auctionator.Utilities.InsertLink(self.itemInfo.itemLink)

    else
      Auctionator.Groups.CallbackRegistry:TriggerEvent(self.clickEventName, self, button)
    end
  end
end

-- Adds Dragonflight (10.0) crafting quality icon for reagents on retail only
function AuctionatorGroupsViewItemMixin:ApplyQualityIcon(itemLink)
  if Auctionator.Constants.IsRetail then
    local info = C_TradeSkillUI.GetItemReagentQualityInfo(itemLink)
    if info ~= nil then
      if not self.ProfessionQualityOverlay then
        self.ProfessionQualityOverlay = self:CreateTexture(nil, "OVERLAY");
        self.ProfessionQualityOverlay:SetPoint("TOPLEFT", -2, 2);
        self.ProfessionQualityOverlay:SetDrawLayer("OVERLAY", 7);
      end
      self.ProfessionQualityOverlay:Show()

      self.ProfessionQualityOverlay:SetAtlas(info.iconInventory, TextureKitConstants.UseAtlasSize);
    else
      self:HideQualityIcon()
    end
  end
end

function AuctionatorGroupsViewItemMixin:HideQualityIcon()
  if self.ProfessionQualityOverlay then
    self.ProfessionQualityOverlay:Hide()
  end
end
