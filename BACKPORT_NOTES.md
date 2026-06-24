# Auctionator — WoW 3.3.5a (WotLK, client 12340) backport notes

This is the modern (Classic-flavour) Auctionator codebase made to run on **stock
WoW 3.3.5a, interface 30300, build 12340**. Only the **Legacy AH** path is kept
(`Source` + `Source_Classic` + `Source_Vanilla` + `Source_LegacyAH` +
`Source_TBC/Constants`); the Retail and Modern-AH (`C_AuctionHouse`) paths are
removed. There is **no ClassicAPI dependency** — every modern API the addon needs is
shimmed in `WotLKCompat/`.

Original Auctionator by plusmouse & Borjamacare. 3.3.5a backport by Jedborg.

---

## 1. How the compatibility layer is structured

`WotLKCompat/` loads **first** (before Libs/Imports/Source) so the shims exist
before any consumer runs:

| File | Provides |
|------|----------|
| `Globals.lua` | `WOW_PROJECT_*`, `Mixin`/`CreateFromMixins`, math/table utils (`Round`, `tInvert`, `tDeleteItem`→returns count, …), `GenerateClosure`, `SOUNDKIT`, `LE_EXPANSION_*`/`EXPANSION_NAMEn`, `BreakUpLargeNumbers` |
| `Enum.lua` | `Enum.ItemQuality/ItemClass/InventoryType/AuctionHouseTimeLeftBand/PlayerInteractionType/…` |
| `Color.lua` | `ColorMixin`/`CreateColor`, the `*_FONT_COLOR` tables, and `.color` added to each `ITEM_QUALITY_COLORS` entry |
| `Pools.lua` | `CreateFramePool`/`CreateFramePoolCollection`/`CreateObjectPool` |
| `Timer.lua` | `C_Timer.After/NewTicker` (single OnUpdate driver) |
| `CallbackRegistry.lua` | `CallbackRegistryMixin` |
| `Items.lua` | `ItemLocation`/`ItemLocationMixin`, `Item`/`ItemMixin` (async via poll), `Auctionator_GetLinkFromLocation` |
| `CAPI.lua` | `C_Item`, `C_Container`, `C_ChatInfo`, `C_AddOns`, `C_MerchantFrame`, `C_Spell`, `C_CurrencyInfo`, `C_Cursor`, `C_TradeSkillUI`, `GetMerchantItemID`, `ExtractHyperlinkString` |
| `AuctionHouse.lua` | `PostAuction`, `SortAuctionSetSort`/`ApplySort` (no-op), `GetAuctionDeposit`→`CalculateAuctionDeposit` |
| `BlizzardUtil.lua` | `FrameUtil` (pcall per `RegisterEvent` — tolerates retail-only events), `EventUtil`, `SecondsFormatter` |
| `Color/Widgets.lua` | widget metatable shims: `SetShown/SetSize/SetEnabled/SetPropagateKeyboardInput/SetMaxLines/SetColorTexture`, `GetItemInfoInstant`, `GameTooltip:SetItemByID` |
| `ScrollBox.lua`+`.xml` | native-`ScrollFrame`-backed `WowScrollBoxList`/`WowTrimScrollBar`/`ScrollUtil`/`Create*View`/`CreateDataProvider`/`CreateIndexRangeDataProvider` |
| `Menu.lua`, `Templates.lua/.xml` | `MenuUtil`→`UIDropDownMenu`; `UIPanelDynamicResizeButtonTemplate`, `ResizeLayoutFrame`, `NineSlicePanelTemplate`, `ButtonFrameTemplate`, `TabButtonTemplate`, `InsetFrameTemplate4`, … |

XML was transformed offline by dev tools (kept under `WotLKCompat/tools/`, **not**
loaded by the TOC): `xml_backport.lua` (mixin=/method=/KeyValue/EventFrame →
3.3.5a), `merge_frames.lua` (multiple `<Frames>` → one), `anchor_relativekey.lua`
(`<Anchor relativeKey>` → runtime `SetPoint`), `resolve_mixins.lua` (flatten mixin
chains into each frame's own OnLoad), `anchor_inherit.lua` (propagate anchor
SetPoints down inheritance). Correct pipeline order: xml_backport → merge_frames →
anchor_relativekey → resolve_mixins → anchor_inherit.

---

## 2. Auction House API map (Classic/Retail → 3.3.5a)

The AH backend is abstracted in `Source_LegacyAH/AH/` and uses **only legacy APIs**:

| Used by the addon | 3.3.5a call | Notes |
|---|---|---|
| search/scan | `QueryAuctionItems(name, minLevel, maxLevel, invType, classIndex, subclassIndex, page, isUsable, qualityIndex)` | **9 args, NO `getAll`.** `getAll` does not exist on 3.3.5a (Cataclysm+). |
| read a page | `GetNumAuctionItems("list")`, `GetAuctionItemInfo("list", i)`, `GetAuctionItemLink("list", i)`, `GetAuctionItemTimeLeft("list", i)` | see index table below |
| owned auctions | `GetNumAuctionItems("owner")`, `GetAuctionItemInfo("owner", i)` | Cancelling tab |
| sell slot | `GetAuctionSellItemInfo()`, `ClickAuctionSellItemButton()`, `PickupContainerItem(bag,slot)` | item must be placed in the sell slot before posting |
| post | `StartAuction(minBid, buyoutPrice, runTime, stackSize, numStacks)` | `runTime` is 1/2/3 (12/24/48h); 3.3.5a clears the slot after each call |
| bid / cancel | `PlaceAuctionBid("list", i, bid)`, `CancelAuction(index)` | native |
| throttle | `CanSendAuctionQuery()` | gates **queries** only — NOT posting |

**`GetAuctionItemInfo("list", i)` 12-field 3.3.5a order** (≠ Classic, which adds
`levelColHeader`/`bidderFullName`/`ownerFullName`/`itemId`). `Constants.AuctionItemInfo`
is set to this; `itemId` is **not returned on 3.3.5a** and is injected from the link:

```
1 name  2 texture  3 count  4 quality  5 canUse  6 level  7 minBid
8 minIncrement  9 buyoutPrice  10 bidAmount  11 highBidder  12 owner  13 saleStatus
```
→ `Quantity=3, Level=6, MinBid=7, Buyout=9, BidAmount=10, Bidder=11, Owner=12, SaleStatus=13, ItemID=14(injected)`

**Events (all native on 3.3.5a, registered via `FrameUtil` which pcalls each
`RegisterEvent`):** `AUCTION_HOUSE_SHOW/CLOSED`, `AUCTION_ITEM_LIST_UPDATE`,
`AUCTION_OWNED_LIST_UPDATE`, `NEW_AUCTION_UPDATE`, `AUCTION_MULTISELL_START/UPDATE/FAILURE`,
`CHAT_MSG_SYSTEM`. Retail-only `PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE` are
registered but harmlessly no-op (pcall) and never fire.

The AH UI is bootstrapped by `Source_Classic/Initialize/Main.lua` on
`AUCTION_HOUSE_SHOW`: it creates `AuctionatorAHFrame` (parented to `AuctionFrame`)
which builds the tab container.

---

## 3. Notable 3.3.5a traps fixed (root causes)

- **`getAll` absent** → the whole-AH scan is page-by-page with duplicate-page
  detection (`Source_LegacyAH/FullScan/Mixins/Frame.lua`); trigger `/atr scan`.
- **`tDeleteItem` is native and returns nothing** → a guarded shim never applied and
  `tDeleteItem(...) > 0` errored, blocking every results update. Fixed at the call
  site (`TableBuilder:RemoveRow`).
- **Post button gated on the QUERY throttle** → `IsNotThrottled()` now checks only
  `not throttling:AnyWaiting()` (posting is not query-throttled on 3.3.5a).
- **`<Texture inherits="virtualTexture">` does not apply `file=`** → inline the file;
  AH panel backgrounds use one solid `<Color>` (the `FrameGeneral` marble/rock
  textures are absent on the test client).
- **Atlas system absent** → coin icons use `Interface\MoneyFrame\UI-MoneyIcons` file
  texcoords instead of `auctionhouse-icon-coin-*` atlases.
- **`PanelTemplates_*` need named frames** → guarded for anonymous mini-tabs; AH tab
  labels sized by forcing the fontstring to its full natural width.
- **`ContinueOnItemLoad` does not fire for an unresolvable item** → search result
  finalisation counts every key down anyway so it never hangs.

---

## 4. Known limitations / open items

- **Results listing rendering** (Shopping/Cancelling): data reaches the provider
  (`AppendEntries N`) but rows can be laid out before the ScrollBox frame has its
  final size, so the `ScrollFrame` clips them. Mitigated by (a) forcing the scroll
  content width and (b) re-running `FullUpdate` from the scroller's `OnSizeChanged`.
  If still blank, capture the debug line `ScrollBox:FullUpdate count …` (see tests).
- **Selling multi-stack**: stock 3.3.5a empties the sell slot after each
  `StartAuction`; posting `numStacks > 1` relies on the SaleItem re-placement loop.
- Atlas-based art is cosmetic-only and may differ from Retail.
- Tooltip price injection uses `GameTooltip:SetHyperlink` (no `C_TooltipInfo`).

---

## 5. Manual test checklist

1. Open AH → no Lua errors.
2. Shopping → search "Thick Hide" → results populate (name / available / price).
3. Price column stays inside the frame.
4. Selling → place item in sell slot → price list loads; undercut fills Unit/Stack.
5. Post button enables only when valid (item, qty>0, price>0); posting succeeds.
6. Cancelling → owned auctions list populates; Undercut Scan does not error.
7. `/atr scan` runs a full page-by-page scan with progress.
8. Close/reopen AH → no taint, frames rebuild.

**Debugging the results table:** `/atr d` then search, and read the line
`ScrollBox:FullUpdate count <n> scrollerW <w> scrollerH <h> contentW <c> extent <e>`:
- `count 0` → data not reaching the listing (provider).
- `scrollerW/H 0` → the listing has no size (frame layout/anchor problem).
- `contentW 1` with `scrollerW>0` → content-width timing (should now self-correct).
- all non-zero → row/cell column layout (table width) issue.
