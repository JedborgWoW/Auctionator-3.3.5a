# Auctionator — WoW 3.3.5a (WotLK) backport

> The modern **[Auctionator](https://github.com/TheMouseNest/Auctionator)** auction-house
> addon, backported to run on **stock Wrath of the Lich King 3.3.5a** (interface `30300`,
> client build `12340`) — no ClassicAPI or other compatibility addon required.

![Game version](https://img.shields.io/badge/WoW-3.3.5a%20(12340)-informational)
![Interface](https://img.shields.io/badge/Interface-30300-informational)
![Branch](https://img.shields.io/badge/AH%20path-Legacy%20(QueryAuctionItems)-success)
[![Auctionator Discord](https://img.shields.io/badge/discord-auctionator-blue.svg)](https://discord.gg/JabzHmzjWF)

Auctionator makes buying, selling and managing auctions fast and painless: live prices in
your tooltips, a powerful search with shopping lists, one-click reposting, and undercut
detection — all wrapped in a clean UI that fits the WotLK auction house.

---

## Installation

1. Download / clone this repository.
2. Copy the **`Auctionator`** folder into your client's `Interface\AddOns\` directory
   (so you end up with `Interface\AddOns\Auctionator\Auctionator.toc`).
3. Restart the game client (a full restart — `/reload` is unreliable on 3.3.5a).
4. Open any auctioneer; the Auctionator tabs appear along the bottom of the AH window.

Saved data (shopping lists, price database, recent searches, etc.) lives in `WTF\` and
survives updates.

---

## Features

### Tooltips & pricing
- **Auction price in item tooltips** — current AH value and a disenchant estimate.
- **Full Scan** — a fast, page-by-page scan of the entire auction house to refresh the
  price database, with a live progress panel (page, count, speed, ETA) and a cancel button.

### Shopping
- **Search with rich filters** — name, exact match, item class, level/item-level ranges,
  price range, quality, and quantity via the **Search Options** dialog.
- **Shopping lists** — save groups of searches; import/export lists as text.
- **Recent searches** — every search is remembered and one click re-runs it.
- **Available count** shown per result (a `N+` lower bound while a multi-page search is still
  loading, exact once all pages are fetched).

### Buying
- Click a result to open the buy view with the live auctions, item icon and tooltip.
- **Buy Stack** — buy a single stack, or **Buy All** — buy *every* stack at the current
  price in one click (throttle-paced and gold-safe; it never rolls onto a higher price).
- **Chain buy** to continue onto the next-cheapest price (with a price-jump warning).

### Selling
- Place an item in the sell slot and post with unit/stack pricing and a duration choice;
  the slot icon shows the **stack count**, and **Deposit / Total Price** are shown clearly.
- Protection against accidentally posting far below value.

### Cancelling
- Lists your active auctions with time left and an **Undercut Scan** to flag undercut
  auctions, plus **Cancel Undercut** for quick cleanup.

---

## What's different in this backport

The retail UI framework Auctionator is built on does **not** exist on 3.3.5a, so it is
reimplemented in a self-contained compatibility layer under **`WotLKCompat/`** (loaded
first): the `ScrollBox` system, `mixin=`/`<OnX method>` XML, the `C_*` namespaces, `Enum`,
frame pools, `C_Timer`, the menu/dropdown system, `Mixin`/`CreateFromMixins`, and the
templates Auctionator expects. Only the **Legacy auction-house** path (the classic
`QueryAuctionItems` API) is kept — the retail / Cataclysm / Classic-Era / `C_AuctionHouse`
paths were removed.

On top of the port, this fork includes a number of 3.3.5a-specific fixes and quality-of-life
additions, among them:

- **Buy All** button for buying out a whole price point at once.
- Stack-count overlay on the Selling slot icon.
- Solid, readable dialogs (Search Options, Price History, Full Scan, Import/Export) — the
  retail backgrounds render transparent/green on this client.
- Full-width dark result panels and a tidied Shopping header (centered *Search Term*,
  active-tab marker, no texture bleeds).
- Buying/cancelling completion driven by reliable 3.3.5a signals (gold change, owned-list
  change) instead of events that don't fire on this client.
- A heavily optimized Full Scan (no end-of-scan freeze, adaptive query throttle).

A deep technical write-up of the compatibility layer, the API/index differences, and the
offline XML-transform tooling lives in **[BACKPORT_NOTES.md](BACKPORT_NOTES.md)**.

---

## Known limitations

- **Scan speed is server-bound.** 3.3.5a has no bulk `getAll` query and pages can't be
  pipelined, so a Full Scan is paced by how fast the server answers one ~50-item page at a
  time (roughly a ~100 auctions/sec ceiling). The engine already runs at that ceiling.
- **Custom servers vary.** Some private servers don't fire the standard auction-house
  confirmation events (post / buyout / cancel), so a few flows rely on fallback signals and
  behaviour can differ slightly between servers.

---

## Credits

- Original **Auctionator** by **plusmouse** and **Borjamacare** —
  [TheMouseNest/Auctionator](https://github.com/TheMouseNest/Auctionator).
- WoW 3.3.5a (WotLK) backport by **Jedborg**
  ([JedborgWoW](https://github.com/JedborgWoW)).

Licensed **All Rights Reserved** (© 2020–2025 plusmouse, borjamacare; backport
modifications © 2026 Jedborg) — see [LICENSE](LICENSE). Consider supporting the
original authors on [Patreon](https://patreon.com/auctionator).
