# GoldAdvisorMidnight

Gold Advisor Midnight is a World of Warcraft Retail addon for Auction House crafting analysis in Midnight. It scans AH prices, prices strategies against the current market, and helps you compare profit before you commit materials.

This repository contains the full addon source, generated strategy data, development tooling, and release history for the public GitHub build.

## What It Does

- Scans live Auction House commodity and item data through `C_AuctionHouse`
- Calculates `Total Cost`, `Buy Now Cost`, `Net Revenue`, `Profit`, `ROI`, and `Break-even`
- Supports profession `Resourcefulness` and `Multicraft` inputs in the main UI
- Uses fill-sensitive order-book pricing so larger batches can price deeper into the AH
- Expands vertical-integration chains through real craft producers when `Use own items/crafts` is enabled
- Shows a step-by-step VI breakdown popup when `Show VI breakdown` is enabled
- Builds Auctionator shopping lists for selected strategies
- Pushes selected-strategy prices into CraftSim
- Includes debug tools for item ID dumps, scan dumps, and smoke tests

## Shipped Strategy Scope

The addon currently ships with `73` built-in strategies across `9` professions:

- `Alchemy`: 15
- `Blacksmithing`: 3
- `Cooking`: 11
- `Enchanting`: 5
- `Engineering`: 12
- `Inscription`: 14
- `Jewelcrafting`: 7
- `Leatherworking`: 4
- `Tailoring`: 2

Notable shipped behavior:

- `Crushing` uses dynamic cheapest-eligible gem selection at runtime
- `Dazzling Thorium Prospecting` keeps full ranked output item IDs so runtime quality resolution can pick the correct output tier
- Manual Thalassian missives use a conservative estimated inscription output profile
- Cooking ships `11` workbook-backed meals and teas, with static vendor pricing for Cooking vendor mats
- Vertical integration can recurse through intermediate crafts like inks, `Soul Cipher`, and Cooking tea chains

## Current UI Workflow

At the Auction House, the main window is split into three panels:

- `Tools` on the left: filters, fill quantity, VI toggle, VI breakdown toggle, stat inputs, scan buttons, CraftSim, Shopping, and ARP export
- `Strategy List` in the center: ranked strategies with profit and ROI
- `Strategy Detail` on the right: costs, outputs, inputs, and craft count for the selected strat

Key workflow pieces:

- `Use own items/crafts` switches between buying intermediates from the AH and recursively crafting eligible intermediates from their own raw-material chains
- `Show VI breakdown` opens a resizable popup that follows the selected strategy and shows branch-by-branch VI steps
- `Fill Qty` controls how many units are sampled from the order book for AH pricing
- `Scan Strat` and `Scan All` queue the currently relevant items for live AH repricing

## Slash Commands

The addon currently supports:

```text
/gam
/goldadvisor
/gam log
/gam scan
/gam clearcache
/gam reload
/gam ids
/gam scandump
/gam smoketest
/gam create
/gam edit
/gam quickbuy
```

Command notes:

- `/gam` or `/goldadvisor`: toggle the main window
- `/gam log`: open the debug log window
- `/gam scan`: queue all strategy items for AH scanning
- `/gam clearcache`: clear persisted price cache data
- `/gam reload`: reload importer data in-session
- `/gam ids`: dump known item IDs into the debug log
- `/gam scandump`: dump the selected strategy's scan and pricing inputs
- `/gam smoketest`: run pricing, AH scan, and state smoke checks
- `/gam create`: open the custom strategy creator
- `/gam edit`: open the custom strategy edit picker
- `/gam quickbuy`: reset or report the Quick Buy flow state

## Installation

1. Download a release zip from GitHub Releases, or clone this repository.
2. Copy `GoldAdvisorMidnight/` into:
   `World of Warcraft/_retail_/Interface/AddOns/`
3. Launch the game or run `/reload`.
4. Open the Auction House and use `/gam` if the window is not already visible.

The addon folder must remain named `GoldAdvisorMidnight/`.

## Repository Layout

- `GoldAdvisorMidnight/`: installable addon folder
- `GoldAdvisorMidnight/Data/`: checked-in generated strategy and workbook data
- `docs/reports/strategy_coverage_report.md`: generated shipped-strategy coverage snapshot
- `CHANGELOG.md`: release history
- `releases/`: packaged release zips
- `LICENSE`: usage terms

## Accuracy Notes

- Output and reagent pricing use the live scanned order book when session scan data is available.
- Summary economics use expected-value math.
- Visible reagent rows and shopping quantities use rounded execution counts so batch planning stays practical.
- VI breakdown rows are branch-local steps; the header totals use merged raw-material totals.
- Manual missives are intentionally conservative until enough verified craft data exists to promote them to a stronger modeled profile.

## Current Limitations

- Theme support is currently limited to the shipped V2 `classic` and `soft` layouts.
- Runtime formula math is spreadsheet-authoritative; the shipped workbook profiles drive fixed sheet multipliers for parity.
- Some advanced debugging and export flows are aimed at spreadsheet verification and addon development, not general gameplay use.

## Development and Verification

Useful local checks:

- `luac -p GoldAdvisorMidnight/...` for syntax validation
- `python3 tools/compare_strats.py <workbook.xlsx>` for workbook parity checks
- `python3 tools/audit_strategy_coverage.py` to refresh the shipped strategy coverage report
- `/gam smoketest` for in-game smoke checks
- `/gam scandump` for selected-strategy pricing traces

Release helpers:

- `./Release_GitHub.command [patch|minor|major|x.y.z]` bumps the addon version, builds the zip, commits, pushes, and creates a GitHub release

Release metadata is tracked in:

- [`CHANGELOG.md`](CHANGELOG.md)
- [`GoldAdvisorMidnight/GoldAdvisorMidnight.toc`](GoldAdvisorMidnight/GoldAdvisorMidnight.toc)
- [`GoldAdvisorMidnight/Constants.lua`](GoldAdvisorMidnight/Constants.lua)

## Support

- Discord: `https://discord.gg/v7vsCKCsFh`
- Recent release notes: see `CHANGELOG.md`
