# GoldAdvisorMidnight

Gold Advisor Midnight is a World of Warcraft Retail addon for Auction House crafting analysis in Midnight. It scans AH prices, prices strategies against the current market, and helps you compare profit before you commit materials.

This repository contains the full addon source, generated strategy data, development tooling, and release history for the public GitHub build.

## What It Does

- Scans live Auction House commodity and item data through `C_AuctionHouse`
- Calculates `Total Cost`, `Buy Now Cost`, `Net Revenue`, `Profit`, `ROI`, and `Break-even`
- Reinvests expected `Resourcefulness` procs into additional mass-crafting attempts while `Multicraft` increases expected output per attempt
- Captures learned specialization-node bonuses and localized in-game path names from Blizzard whenever a profession window opens; verified English names cover directly mapped traits before first capture, and CraftSim is not required
- Reuses exact cached recipe stats and learned nodes from another account character when the current character lacks that profession
- Saves exact Multicraft and Resourcefulness gear setups per recipe and crafter; Auto compares both with current prices and chooses the more profitable setup
- Tracks selected profession recipe cooldowns and charges per cached crafter, including last-known countdowns while that character is offline
- Uses fill-sensitive order-book pricing so larger batches can price deeper into the AH
- Expands vertical-integration chains through real craft producers when `Use own items/crafts` is enabled
- Shows a grouped VI shopping list and dependency-safe crafting order when `Show VI breakdown` is enabled
- Builds Auctionator shopping lists for selected strategies
- Pushes selected-strategy prices into CraftSim
- Includes a copyable support log plus deterministic offline verification tools

## Shipped Strategy Scope

The addon retains `282` commodity strategies across `9` professions from a
pinned set of `606` definitions, including reviewed Retail 12.1 additions:

- `Alchemy`: 30
- `Blacksmithing`: 8
- `Cooking`: 41
- `Enchanting`: 77
- `Engineering`: 26
- `Inscription`: 31
- `Jewelcrafting`: 48
- `Leatherworking`: 11
- `Tailoring`: 10

The generated commodity manifest currently contains `477` eligible output item
IDs. Equipment, profession tools, bags, toys, mounts, bind-on-pickup outputs,
and other one-off products are excluded from the active runtime catalog.

Notable shipped behavior:

- `Crushing` uses dynamic cheapest-eligible gem selection at runtime
- `Dazzling Thorium Prospecting` keeps full ranked output item IDs so runtime quality resolution can pick the correct output tier
- Manual Thalassian missives use a conservative estimated inscription output profile
- Cooking includes workbook-backed meals and teas plus broader Wowhead-seeded recipe coverage, with static vendor pricing for Cooking vendor mats
- Vertical integration can recurse through intermediate crafts like inks, `Soul Cipher`, and Cooking tea chains
- Retail 12.1 adds nine reviewed mass-crafting strategies across Alchemy, Enchanting, Engineering, Inscription, and Jewelcrafting

## Current UI Workflow

At the Auction House, the main window is split into three panels:

- `Crafting Planner` on the left: profession filters, Auction House price quantity, intermediate-craft planning, material rank, stat gear, and scan actions. Cooldowns, Shopping, CraftSim, and Export are grouped under `More Tools`.
- `Strategy List` in the center: a stable Strategy, Profit, and ROI comparison at every panel width; profession and missing-price context remain available on row hover
- `Strategy Detail` on the right: profit and break-even first, followed by material commitment, the selected craft setup, required materials, and expected output

Key workflow pieces:

- `Use own items/crafts` switches between buying intermediates from the AH and recursively crafting eligible intermediates from their own raw-material chains
- `Show VI breakdown` opens a resizable popup that groups vendor purchases, groups Auction House purchases, then lists every intermediate craft before the final output craft
- `Fill Qty` controls how many units are sampled from the order book for AH pricing
- `Stat Gear` opens a focused menu for `Auto`, `Multicraft`, and `Resourcefulness`. To save a setup, equip that gear, open the exact selected Blizzard recipe, then use `Save MC` or `Save Res`; saves belong to that recipe and crafter.
- `Auto` compares both captured gear setups at current prices. A forced setup is never silently replaced by the other preset; the detail panel warns when the requested preset has not been captured.
- `Scan Strat` and `Scan All` queue the currently relevant items for live AH repricing
- Selecting a strategy opens its exact recipe when the current crafter snapshot is missing or stale; selecting that row again forces a refresh
- `Refresh Recipe` remains available as an explicit refresh action when the current character knows the profession
- Characters without the selected profession use the most recently verified exact cached crafter and show that crafter in Strategy Detail
- Profile-wide manual stat values remain available only in Settings as advanced fallbacks
- Profession Node settings show compact in-game names and captured ranks; hover a name or rank for its Blizzard description and the exact pricing effect, then edit only when a manual override is needed
- `Craft Cooldowns` opens a panel with a scrollable crafter selector. Track the selected strategy for any cached character, or track the recipe currently open on the logged-in crafter; only that logged-in character's live state is refreshed. The help icon explains snapshots, countdowns, charges, and reset verification.

## Slash Commands

The addon currently supports:

```text
/gam
/goldadvisor
/gam log
/gam help
```

Command notes:

- `/gam` or `/goldadvisor`: toggle the main window
- `/gam log`: open the debug log window
- `/gam help`: print the supported command list

Scanning, cache maintenance, Quick Buy, exports, CraftSim, and cooldowns are
available from the addon UI. Developer diagnostics run from the repository test
suite instead of expanding the in-game command surface.

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
- `GoldAdvisorMidnight/Data/Professions/`: compact generated craft facts split by profession
- `GoldAdvisorMidnight/tests/`: deterministic offline regression suite
- `GoldAdvisorMidnight/tools/`: catalog auditing and release packaging tools
- `GoldAdvisorMidnight/docs/ARCHITECTURE.md`: runtime boundaries and maintenance rules
- `GoldAdvisorMidnight/docs/TRANSLATING.md`: locale contribution and validation guide
- `CHANGELOG.md`: release history
- `LICENSE`: usage terms

## Accuracy Notes

- Output and reagent pricing use the live scanned order book when session scan data is available.
- Summary economics use expected-value math.
- Fractional expected attempts remain available in the Stats tooltip, while the visible craft recommendation conservatively rounds down to a whole craft.
- Visible reagent rows and shopping quantities use rounded execution counts so batch planning stays practical.
- VI purchase rows merge repeated materials before subtracting owned inventory. Repeated intermediate recipes are combined, rounded to whole craft quantities, and ordered before every consuming craft; the selected strategy's final craft is always last.
- Manual missives are intentionally conservative until enough verified craft data exists to promote them to a stronger modeled profile.

## Current Limitations

- Theme support is currently limited to the shipped V2 `classic` and `soft` layouts.
- The release UI and runtime use the mass-crafting `exhaust_materials` model.
- Existing eligible custom strategies remain readable for compatibility, but the release UI no longer creates, imports, edits, or deletes custom strategies.
- The 12.1 selected-recipe open/refresh path still requires final live-client verification because Blizzard only permits profession opening from a user input event.
- Cooldown and charge discovery uses the current Retail `C_Spell` APIs and needs final live-client verification against recipes with daily, weekly, and charge-based cooldowns.
- Some advanced debugging and export flows are aimed at spreadsheet verification and addon development, not general gameplay use.

## Development and Verification

Useful local checks:

- `lua tests/run.lua` from the addon directory for the catalog/import regression suite
- `python tests/check_locales.py` to require every active string in every shipped locale
- `python tests/check_toc.py` to verify the runtime file boundary
- `luac -p` over shipped Lua files for syntax validation
- `python tools/package_release.py --check` from the addon directory to validate the exact release file set
- `python tools/package_release.py` from the addon directory to build a deterministic zip under `output/releases/`

In game, use the normal planner workflow for acceptance testing and `/gam log`
to collect a copyable support report when a result is unexpected.

Release metadata is tracked in:

- [`CHANGELOG.md`](CHANGELOG.md)
- [`GoldAdvisorMidnight/GoldAdvisorMidnight.toc`](GoldAdvisorMidnight/GoldAdvisorMidnight.toc)
- [`GoldAdvisorMidnight/Constants.lua`](GoldAdvisorMidnight/Constants.lua)

## Support

- Discord: `https://discord.gg/v7vsCKCsFh`
- Recent release notes: see `CHANGELOG.md`
