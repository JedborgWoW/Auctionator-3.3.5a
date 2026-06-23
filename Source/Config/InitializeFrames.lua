function Auctionator.Config.InternalInitializeFrames(templateNames)
  for _, name in ipairs(templateNames) do
    CreateFrame(
      "FRAME",
      "AuctionatorConfig" .. name .. "Frame",
      InterfaceOptionsFramePanelContainer or UIParent,
      "AuctionatorConfig" .. name .. "FrameTemplate")
  end
end
