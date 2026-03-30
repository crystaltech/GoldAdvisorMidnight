# GoldAdvisorMidnight

Gold Advisor Midnight is a World of Warcraft Retail addon for Auction House crafting analysis in Midnight. It scans market prices, estimates crafting costs and revenue, and helps compare profit opportunities before you commit materials.

## Repository Contents

- `GoldAdvisorMidnight/` - installable addon folder
- `CHANGELOG.md` - version history
- `LICENSE` - usage terms

## Features

- Live Auction House scanning through `C_AuctionHouse`
- 62 built-in strategies across 8 professions
- Profit, ROI, break-even, and buy-now cost calculations
- Multicraft and Resourcefulness support with per-profession stat inputs
- Fill Qty simulation for large-batch pricing
- Dynamic reagent-pool selection for flexible recipes such as Jewelcrafting Crushing
- Vertical integration with `Use own items/crafts`
- Auctionator shopping-list support and Quick Buy helper flow
- Optional CraftSim stat sync
- 10 shipped locales

## Installation

1. Download a release zip or clone this repository.
2. Copy `GoldAdvisorMidnight/` into `World of Warcraft/_retail_/Interface/AddOns/`
3. Reload the UI with `/reload`
4. Open the Auction House and use `/gam` if the window is not already visible

## Commands

```text
/gam
/gam log
/gam scan
/gam clearcache
/gam reload
/gam quickbuy
/gam create
/gam ids
```

## Notes

- The addon ships with checked-in data files in `GoldAdvisorMidnight/Data/`.
- Crushing is priced against the cheapest eligible gem in its shipped reagent pool at runtime rather than a fixed gem baseline.
- The install folder name must remain `GoldAdvisorMidnight/`.
- See `CHANGELOG.md` for recent addon changes.
