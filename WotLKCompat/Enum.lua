-- WotLK 3.3.5a compatibility: Enum
--
-- 3.3.5a has no Enum table. Auctionator references Enum.* at file scope (in
-- Constants/Main.lua and elsewhere), so this must exist before Source loads.
-- Values are chosen to match the 3.3.5a numeric IDs where they feed real API
-- calls (item quality, item class, inventory type), and to match retail where
-- they are only used as opaque keys.

Enum = Enum or {}

-- Item quality. 3.3.5a: 0 Poor, 1 Common, 2 Uncommon, 3 Rare, 4 Epic,
-- 5 Legendary, 6 Artifact, 7 Heirloom. Auctionator's classic branch aliases
-- Common->Standard and Uncommon->Good.
Enum.ItemQuality = Enum.ItemQuality or {
  Poor = 0,
  Standard = 1,
  Common = 1,
  Good = 2,
  Uncommon = 2,
  Rare = 3,
  Epic = 4,
  Legendary = 5,
  Artifact = 6,
  Heirloom = 7,
  WoWToken = 8,
}

-- Item class IDs. These match the 3.3.5a item class numbering where it matters
-- (Consumable 0, Container 1, Weapon 2, Gem 3, Armor 4, Reagent 5, Projectile 6,
-- Tradegoods 7, Recipe 9, Quiver 11, Quest 12, Key 13, Misc 15, Glyph 16).
-- Classes that do not exist on 3.3.5a (Battlepet, Profession, Housing,
-- ItemEnhancement) get retail-ish IDs that simply never match a real item.
Enum.ItemClass = Enum.ItemClass or {
  Consumable = 0,
  Container = 1,
  Weapon = 2,
  Gem = 3,
  Armor = 4,
  Reagent = 5,
  Projectile = 6,
  Tradegoods = 7,
  ItemEnhancement = 8,
  Recipe = 9,
  CurrencyTokenObsolete = 10,
  Quiver = 11,
  Questitem = 12,
  Key = 13,
  PermanentObsolete = 14,
  Miscellaneous = 15,
  Glyph = 16,
  Battlepet = 17,
  WoWToken = 18,
  Profession = 19,
  Housing = 20,
}

-- Equip-slot enum (Enum.InventoryType.IndexXType). Numeric values match the
-- engine's INVSLOT/inventory-type numbering used by GetInventoryItemLink etc.
Enum.InventoryType = Enum.InventoryType or {
  IndexNonEquipType = 0,
  IndexHeadType = 1,
  IndexNeckType = 2,
  IndexShoulderType = 3,
  IndexBodyType = 4,
  IndexChestType = 5,
  IndexWaistType = 6,
  IndexLegsType = 7,
  IndexFeetType = 8,
  IndexWristType = 9,
  IndexHandType = 10,
  IndexFingerType = 11,
  IndexTrinketType = 12,
  IndexWeaponType = 13,
  IndexShieldType = 14,
  IndexRangedType = 15,
  IndexCloakType = 16,
  Index2HweaponType = 17,
  IndexBagType = 18,
  IndexTabardType = 19,
  IndexRobeType = 20,
  IndexWeaponmainhandType = 21,
  IndexWeaponoffhandType = 22,
  IndexHoldableType = 23,
  IndexAmmoType = 24,
  IndexThrownType = 25,
  IndexRangedrightType = 26,
  IndexQuiverType = 27,
  IndexRelicType = 28,
}

-- Auction duration bands (selling). Short 12h, Medium 24h(48?), Long. The
-- numeric values are opaque keys used by Auctionator's own duration tables.
Enum.AuctionHouseTimeLeftBand = Enum.AuctionHouseTimeLeftBand or {
  Short = 0,
  Medium = 1,
  Long = 2,
  VeryLong = 3,
}

Enum.ItemBind = Enum.ItemBind or {
  None = 0,
  OnAcquire = 1,
  OnEquip = 2,
  OnUse = 3,
  Quest = 4,
}

-- Only used as opaque keys by the tooltip-info / interaction shims.
Enum.TooltipDataType = Enum.TooltipDataType or {
  Item = 10,
  Spell = 11,
  Unit = 2,
}

Enum.PlayerInteractionType = Enum.PlayerInteractionType or {
  Auctioneer = 21,
  MailInfo = 17,
  Merchant = 5,
}
