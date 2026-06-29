# Auctionator — WotLK 3.3.5a backport

> **This is a backport of [Auctionator](https://github.com/TheMouseNest/Auctionator)
> to the stock WotLK 3.3.5a (client build 12340) interface.**
> Original addon by **plusmouse** and **Borjamacare**. 3.3.5a backport by
> **Jedborg** ([JedborgWoW](https://github.com/JedborgWoW)).
>
> The modern retail UI framework that Auctionator relies on (the ScrollBox
> system, `mixin=`/`<OnX method>` XML, `C_*` namespaces, `Enum`, the menu/
> dropdown system, etc.) does not exist on stock 3.3.5a, so it is reimplemented
> in a self-contained compatibility layer under `WotLKCompat/` (no ClassicAPI or
> other compat addon required). Only the WotLK / Legacy-Auction-House code path
> is kept; the retail / Cata / Classic-Era / Modern-AH versions were removed.


Auctionator is designed for casual everyday auction house users, to make interactions easier and faster, and to provide quick access to auction prices.
## Key Features
* Auction prices in item tooltips (with an AH full scan function to update the prices)
* Straightforward UI
* Protection against posting too low
* Recipe reagent costs and profits in crafting views
* Searches with lots of filters with a search history and organised into shopping lists
* Undercut scan and one-click cancelling for owned auctions

For a description of and usage guide for more features please see the
[Curseforge page](https://www.curseforge.com/wow/addons/auctionator).




