local SLASH_COMMAND_DESCRIPTIONS = {
  {commands = "p, post", message = "Posts the chosen item from the \"Selling\" tab." },
  {commands = "cu, cancelundercut", message = "Cancels the next undercut auction in the \"Cancelling\" tab." },
  {commands = "scan, fullscan", message = "Scan the whole auction house (page by page) to update prices. Open the AH first." },
  {commands = "ra, resetall", message = "Reset database and full scan timer." },
  {commands = "rdb, resetdatabase", message = "Reset Auctionator database."},
  {commands = "rt, resettimer", message = "Reset full scan timer."},
  {commands = "rc, resetconfig", message = "Reset configuration to defaults."},
  {commands = "npd, nopricedb", message = "Disable recording auction prices."},
  {commands = "d, debug", message = "Toggle debug mode."},
  {commands = "c, config", message = "Show current configuration values."},
  {commands = "c [toggle-name], config [toggle-name]", message = "Toggle the value of the configuration value [toggle-name]."},
  {commands = "v, version", message = "Show current version."},
  {commands = "h, help", message = "Show this help message."},
}

function Auctionator.SlashCmd.Post()
  Auctionator.EventBus
    :RegisterSource(Auctionator.SlashCmd.Post, "Auctionator.SlashCmd.Post")
    :Fire(Auctionator.SlashCmd.Post, Auctionator.Selling.Events.RequestPost)
    :UnregisterSource(Auctionator.SlashCmd.Post)
end

function Auctionator.SlashCmd.CancelUndercut()
  Auctionator.EventBus
    :RegisterSource(Auctionator.SlashCmd.CancelUndercut, "Auctionator.SlashCmd.CancelUndercut")
    :Fire(Auctionator.SlashCmd.CancelUndercut, Auctionator.Cancelling.Events.RequestCancelUndercut)
    :UnregisterSource(Auctionator.SlashCmd.CancelUndercut)
end

function Auctionator.SlashCmd.ToggleDebug()
  Auctionator.Debug.Toggle()
  if Auctionator.Debug.IsOn() then
    Auctionator.Utilities.Message("Debug mode on")
  else
    Auctionator.Utilities.Message("Debug mode off")
  end
end

function Auctionator.SlashCmd.ResetDatabase()
  if Auctionator.Debug.IsOn() then
    -- See Source/Variables/Main.lua for variable usage
    AUCTIONATOR_PRICE_DATABASE = nil
    Auctionator.Utilities.Message("Price database reset")
    Auctionator.Variables.InitializeDatabase()
  else
    Auctionator.Utilities.Message("Requires debug mode.")
  end
end

function Auctionator.SlashCmd.ResetTimer()
  if Auctionator.Debug.IsOn() then
    Auctionator.SavedState.TimeOfLastReplicateScan = nil
    Auctionator.SavedState.TimeOfLastGetAllScan = nil
    Auctionator.Utilities.Message("Scan timer reset.")
  else
    Auctionator.Utilities.Message("Requires debug mode.")
  end
end

function Auctionator.SlashCmd.CleanReset()
  Auctionator.SlashCmd.ResetTimer()
  Auctionator.SlashCmd.ResetDatabase()
end

-- Trigger a whole-AH page-by-page scan. The in-tab "Full Scan" button was removed
-- with the Info tab, so this is the UI-independent trigger. Needs the AH open
-- (you can only query auctions while it is).
function Auctionator.SlashCmd.FullScan()
  if not (AuctionFrame and AuctionFrame:IsShown()) then
    Auctionator.Utilities.Message("Open the auction house first to run a full scan.")
    return
  end
  local frame = Auctionator.State.FullScanFrameRef
  if not frame then
    Auctionator.Utilities.Message("Full scan not ready -- reopen the auction house and try again.")
    return
  end
  frame:InitiateScan()
end

-- /atrui: dump the key Auctionator layout frames by name/path so overflow/parent/size
-- bugs are diagnosed by measurement, not guessing. Always prints each target (even 0x0
-- or unanchored) and MISSING if absent; flags any frame whose right edge spills past
-- AuctionFrame, lists every SetPoint, and shows the texture for icon regions.
function Auctionator.SlashCmd.UIDump()
  local ref = _G.AuctionFrame
  if ref == nil then
    Auctionator.Utilities.Message("Open the auction house first, then /atrui.")
    return
  end

  local function num(v)
    return v and math.floor(v + 0.5) or 0
  end

  local function pointsOf(f)
    if not f.GetNumPoints then
      return ""
    end
    local parts = {}
    for i = 1, (f:GetNumPoints() or 0) do
      local p, rel, rp, x, y = f:GetPoint(i)
      local relName = "nil"
      if rel then
        relName = (rel.GetName and rel:GetName()) or "anon"
      end
      table.insert(parts, string.format("%s>%s.%s(%d,%d)", tostring(p), relName, tostring(rp), num(x), num(y)))
    end
    return table.concat(parts, " ")
  end

  local function dumpFrame(label, f)
    if f == nil then
      Auctionator.Utilities.Message(label .. ": |cffff4040MISSING|r")
      return
    end
    local l = f.GetLeft and f:GetLeft()
    local r = f.GetRight and f:GetRight()
    local overflow = ""
    if r and ref:GetRight() then
      local d = r - ref:GetRight()
      if d > 0.5 then
        overflow = "  |cffff4040>>OVERFLOW " .. num(d) .. "px|r"
      end
    end
    local par = f.GetParent and f:GetParent()
    local tex = ""
    if f.GetTexture then
      tex = " tex=" .. tostring(f:GetTexture())
    elseif f.Icon and f.Icon.GetTexture then
      tex = " iconTex=" .. tostring(f.Icon:GetTexture())
    end
    Auctionator.Utilities.Message(string.format(
      "%s: [%s] par=%s %s lvl%d %dx%d L%s R%s {%s}%s%s",
      label,
      (f.IsShown and f:IsShown()) and "shown" or "hidden",
      (par and ((par.GetName and par:GetName()) or "anon")) or "nil",
      (f.GetFrameStrata and f:GetFrameStrata()) or "?",
      (f.GetFrameLevel and f:GetFrameLevel()) or 0,
      num(f.GetWidth and f:GetWidth()), num(f.GetHeight and f:GetHeight()),
      l and num(l) or "nil", r and num(r) or "nil",
      pointsOf(f), tex, overflow
    ))
  end

  local function resolve(path)
    local parts = { strsplit(".", path) }
    local f = _G[parts[1]]
    for i = 2, #parts do
      if type(f) ~= "table" then
        return nil
      end
      f = f[parts[i]]
    end
    return f
  end

  Auctionator.Utilities.Message("|cffffd100=== /atrui (overflow vs AuctionFrame flagged) ===|r")
  dumpFrame("AuctionFrame(ref)", ref)
  local targets = {
    "AuctionatorAHFrame",
    "AuctionatorShoppingFrame",
    "AuctionatorShoppingFrame.ListsContainer",
    "AuctionatorShoppingFrame.SearchOptions",
    "AuctionatorShoppingFrame.ResultsListing",
    "AuctionatorShoppingFrame.ResultsListing.HeaderContainer",
    "AuctionatorShoppingFrame.ResultsListing.ScrollArea",
    "AuctionatorShoppingFrame.ImportButton",
    "AuctionatorShoppingFrame.ExportButton",
    "AuctionatorShoppingFrame.ExportCSV",
    "AuctionatorSellingFrame",
    "AuctionatorSellingFrame.SaleItem",
    "AuctionatorSellingFrame.SaleItem.Icon",
    "AuctionatorCancellingFrame",
    "AuctionatorCancellingFrame.ResultsListing",
    "AuctionatorCancellingFrame.ResultsListing.HeaderContainer",
  }
  for _, path in ipairs(targets) do
    dumpFrame(path, resolve(path))
  end
end

function Auctionator.SlashCmd.NoPriceDB()
  Auctionator.Config.Set(Auctionator.Config.Options.NO_PRICE_DATABASE, true)

  AUCTIONATOR_PRICE_DATABASE = nil
  Auctionator.Variables.InitializeDatabase()

  Auctionator.Utilities.Message("Disabled recording auction prices in the price database.")
end

function Auctionator.SlashCmd.ResetConfig()
  if Auctionator.Debug.IsOn() then
    Auctionator.Config.Reset()
    Auctionator.Utilities.Message("Config reset.")
  else
    Auctionator.Utilities.Message("Requires debug mode.")
  end
end

local INVALID_OPTION_VALUE = "Wrong config value type %s (required %s)"
function Auctionator.SlashCmd.Config(optionName, value1, ...)
  if optionName == nil then
    Auctionator.Utilities.Message("No config option name supplied")
    for _, name in pairs(Auctionator.Config.Options) do
      Auctionator.Utilities.Message(name .. ": " .. tostring(Auctionator.Config.Get(name)))
    end
    return
  end

  local currentValue = Auctionator.Config.Get(optionName)
  if currentValue == nil then
    Auctionator.Utilities.Message("Unknown config: " .. optionName)
    return
  end

  if value1 == nil then
    Auctionator.Utilities.Message("Config " .. optionName .. ": " .. tostring(currentValue))
    return
  end

  if type(currentValue) == "boolean" then
    if value1 ~= "true" and value1 ~= "false" then
      Auctionator.Utilities.Message(INVALID_OPTION_VALUE:format(type(value1), type(currentValue)))
      return
    end
    Auctionator.Config.Set(optionName, value1 == "true")
  elseif type(currentValue) == "number" then
    if tonumber(value1) == nil then
      Auctionator.Utilities.Message(INVALID_OPTION_VALUE:format(type(value1), type(currentValue)))
      return
    end
    Auctionator.Config.Set(optionName, tonumber(value1))
  elseif type(currentValue) == "string" then
    Auctionator.Config.Set(optionName, strjoin(" ", value1, ...))
  else
    Auctionator.Utilities.Message("Unable to edit option type " .. type(currentValue))
    return
  end
  Auctionator.Utilities.Message("Now set " .. optionName .. ": " .. tostring(Auctionator.Config.Get(optionName)))
end

function Auctionator.SlashCmd.Version()
  Auctionator.Utilities.Message(
    BLUE_FONT_COLOR:WrapTextInColorCode("Version: ") .. C_AddOns.GetAddOnMetadata("Auctionator", "Version") ..
    LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(", " .. date() .. ", ") ..
    BLUE_FONT_COLOR:WrapTextInColorCode("WoW: ") .. select(4, GetBuildInfo())
  )
end

function Auctionator.SlashCmd.Help()
  for index = 1, #SLASH_COMMAND_DESCRIPTIONS do
    local description = SLASH_COMMAND_DESCRIPTIONS[index]
    Auctionator.Utilities.Message(description.commands .. ": " .. description.message)
  end
end
