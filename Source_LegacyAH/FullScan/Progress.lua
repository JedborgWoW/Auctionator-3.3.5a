-- Visible Full Scan progress panel for stock 3.3.5a.
--
-- The page-by-page scan engine (FullScan/Mixins/Frame.lua) fires ScanStart / ScanComplete
-- / ScanFailed over the EventBus and exposes a live snapshot via GetProgressInfo(). This
-- panel shows that progress (page X/Y, auctions scanned / total, elapsed seconds) with a
-- Cancel button, so the scan is not just chat spam. Built by hand with the native
-- SetBackdrop (no atlas / no modern template) so it renders reliably on 3.3.5a.

AuctionatorFullScanProgressMixin = {}

local PROGRESS_EVENTS = {
  Auctionator.FullScan.Events.ScanStart,
  Auctionator.FullScan.Events.ScanComplete,
  Auctionator.FullScan.Events.ScanFailed,
}

function AuctionatorFullScanProgressMixin:Init()
  Auctionator.EventBus:Register(self, PROGRESS_EVENTS)

  self:SetScript("OnUpdate", function(frame, elapsed)
    frame.sinceUpdate = (frame.sinceUpdate or 0) + elapsed
    if frame.sinceUpdate < 0.2 then
      return
    end
    frame.sinceUpdate = 0
    frame:UpdateProgressText()
  end)

  self:Hide()
end

-- Engine snapshot. Returns nil if the scan engine is not ready.
local function Snapshot()
  local engine = Auctionator.State.FullScanFrameRef
  if engine and engine.GetProgressInfo then
    return engine:GetProgressInfo()
  end
  return nil
end

function AuctionatorFullScanProgressMixin:UpdateProgressText()
  local p = Snapshot()
  -- Only refresh while the scan is live; otherwise leave the final result message up.
  if p == nil or not p.inProgress then
    return
  end
  local elapsed = math.floor(p.elapsed)
  local speed = math.floor((p.auctionsPerSec or 0) + 0.5)
  local recent = math.floor((p.recentSpeed or 0) + 0.5)
  if p.totalAuctions > 0 then
    self.StatusText:SetText(string.format(
      "|cffffd100Full Scan running|r\nPage %d / %d   ·   %d / %d auctions   ·   %ds\n|cffaaaaaaSpeed: %d/s avg · %d/s recent   ·   ETA: %ds|r",
      p.currentPage, p.totalPages, p.auctionsProcessed, p.totalAuctions, elapsed,
      speed, recent, math.floor(p.eta or 0)
    ))
  else
    self.StatusText:SetText(string.format(
      "|cffffd100Full Scan running|r\nPage %d   ·   %d auctions   ·   %ds\n|cffaaaaaaSpeed: %d/s avg · %d/s recent|r",
      p.currentPage, p.auctionsProcessed, elapsed, speed, recent
    ))
  end
end

function AuctionatorFullScanProgressMixin:HideAfter(seconds)
  local token = (self.hideToken or 0) + 1
  self.hideToken = token
  C_Timer.After(seconds, function()
    -- Only hide if a newer scan hasn't reused the panel in the meantime.
    if self.hideToken == token then
      self:Hide()
    end
  end)
end

function AuctionatorFullScanProgressMixin:ReceiveEvent(eventName, ...)
  if eventName == Auctionator.FullScan.Events.ScanStart then
    self.hideToken = (self.hideToken or 0) + 1 -- cancel any pending hide
    self.CancelButton:SetText(CANCEL)
    self.CancelButton:Enable()
    self:Show()
    self:UpdateProgressText()

  elseif eventName == Auctionator.FullScan.Events.ScanComplete then
    local p = Snapshot()
    self.StatusText:SetText(string.format(
      "|cff00ff00Full Scan complete|r\n%d auctions scanned in %ds",
      (p and p.auctionsProcessed) or 0,
      (p and math.floor(p.elapsed)) or 0
    ))
    -- Scan done: turn the button into an OK that dismisses the panel (kept enabled so the
    -- user can close it immediately instead of waiting for the auto-hide fallback).
    self.CancelButton:SetText(OKAY)
    self.CancelButton:Enable()
    self:HideAfter(10)

  elseif eventName == Auctionator.FullScan.Events.ScanFailed then
    self.StatusText:SetText("|cffff4040Full Scan aborted|r")
    self.CancelButton:SetText(OKAY)
    self.CancelButton:Enable()
    self:HideAfter(6)
  end
end

function Auctionator.FullScan.InitializeProgressUI()
  if Auctionator.State.FullScanProgressRef ~= nil then
    return
  end

  local frame = CreateFrame("Frame", "AuctionatorFullScanProgressFrame", AuctionFrame or UIParent)
  frame:SetSize(420, 96)
  frame:SetPoint("TOP", AuctionFrame or UIParent, "TOP", 0, -130)
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)

  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end

  frame.StatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.StatusText:SetPoint("TOP", frame, "TOP", 0, -14)
  frame.StatusText:SetWidth(370)
  frame.StatusText:SetJustifyH("CENTER")

  frame.CancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.CancelButton:SetSize(100, 22)
  frame.CancelButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
  frame.CancelButton:SetText(CANCEL)
  -- One button, two roles: while a scan runs it Cancels (aborts); once the scan has
  -- finished it acts as OK and just dismisses the panel.
  frame.CancelButton:SetScript("OnClick", function()
    local engine = Auctionator.State.FullScanFrameRef
    if engine and engine.inProgress then
      engine:Abort()
    else
      frame:Hide()
    end
  end)

  Mixin(frame, AuctionatorFullScanProgressMixin)
  frame:Init()

  Auctionator.State.FullScanProgressRef = frame
end
