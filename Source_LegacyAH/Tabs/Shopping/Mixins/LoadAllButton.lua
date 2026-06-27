AuctionatorShoppingTabClassicLoadAllButtonMixin = {}

function AuctionatorShoppingTabClassicLoadAllButtonMixin:OnLoad()
  Auctionator.EventBus:Register(self, {
    Auctionator.Shopping.Tab.Events.SearchStart,
    Auctionator.Shopping.Tab.Events.SearchEnd,
  })
end

function AuctionatorShoppingTabClassicLoadAllButtonMixin:ReceiveEvent(eventName, eventData)
  if eventName == Auctionator.Shopping.Tab.Events.SearchStart then
    self.lastTerms = eventData
    self:Hide()
  elseif eventName == Auctionator.Shopping.Tab.Events.SearchEnd then
    if eventData and #eventData > 0 then
      local anyIncomplete = false
      for _, entry in ipairs(eventData) do
        if not entry.complete then
          anyIncomplete = true
          break
        end
      end
      self:SetShown(anyIncomplete)
    end
   end
end

function AuctionatorShoppingTabClassicLoadAllButtonMixin:OnClick()
  if self.lastTerms ~= nil then
    -- Hide immediately for feedback; SearchEnd will re-show it only if results are
    -- still incomplete after loading all pages.
    self:Hide()
    -- LoadAllPages appends the remaining pages to the current results instead of
    -- doing a fresh search (which would blank the panel). It does not fire
    -- SearchStart, so unlike DoSearch it does not Reset/clear the visible results.
    self:GetParent():LoadAllPages(self.lastTerms)
  end
end
