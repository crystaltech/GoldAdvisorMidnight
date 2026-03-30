# GoldAdvisorMidnight

Gold Advisor Midnight is a WoW Retail Midnight addon for Auction House-based crafting analysis. It scans prices, evaluates strategy profitability, and shows the materials, revenue, and ROI behind each craft.

## Repository Contents

- `GoldAdvisorMidnight/` — the addon folder
- `CHANGELOG.md` — release notes
- `LICENSE` — usage terms

## Features

- Live Auction House scanning through `C_AuctionHouse`
- 62 built-in strategies across 8 professions
- Profit, ROI, break-even, and buy-now cost calculations
- Multicraft and Resourcefulness support with per-profession stat inputs
- Fill Qty simulation for large-buy pricing
- Vertical integration with "Use own items/crafts"
- Shopping aggregation and Quick Buy helper flow
- CraftSim stat sync
- 10 shipped locales

## Installation

1. Copy `GoldAdvisorMidnight/` into `World of Warcraft/_retail_/Interface/AddOns/`
2. Reload the UI with `/reload`
3. Open the Auction House and use `/gam` if the window is not already visible

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
- The folder to install is `GoldAdvisorMidnight/`.
- See `CHANGELOG.md` for recent addon changes.
13. Drag minimap button; `/reload` → position persists
14. Right-click minimap → Settings opens; stat fields present for all professions
15. Load with CraftSim → no Lua errors; load without CraftSim → no Lua errors
16. `bash Release_Patreon.command` → plain handoff zip built in `releases/`
