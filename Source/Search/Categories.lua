local CategoryLookup = {}

local function SaveCategory(categories, prefix)
  prefix = prefix or ""

  for _, c in ipairs(categories) do
    local currentName = prefix .. c.name
    CategoryLookup[currentName] = c.filters

    if c.subCategories ~= nil then
      SaveCategory(c.subCategories, currentName .. "/")
    end
  end
end

function Auctionator.Search.InitializeCategories()
  Auctionator.Search.InitializeOldCategories()

  -- AuctionCategories is a modern Blizzard AH global (the nested category tree);
  -- it does not exist on stock 3.3.5a. The old-category path above
  -- (InitializeOldCategories, built from the 3.3.5a item classes) is what this
  -- client uses, and GetItemClassCategories falls back to it, so skip when nil.
  if AuctionCategories then
    SaveCategory(AuctionCategories)
  end
end

function Auctionator.Search.GetItemClassCategories(categoryKey)
  local lookup = CategoryLookup[categoryKey]
  if lookup ~= nil then
    return lookup
  elseif categoryKey ~= "" then
    -- Compatibility with old category format
    return Auctionator.Search.GetItemClassOldCategories(categoryKey)
  end
end
