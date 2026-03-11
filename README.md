# GoldAdvisorMidnight

WoW Retail Midnight (12.0.1 / TOC 120001) crafting profit advisor.

Scans the Auction House for live prices, computes profit and ROI for spreadsheet-sourced crafting strategies, and presents a sortable in-game list with a shopping aggregator.

---

## Features

- **Live AH scanning** — throttled commodity + item queries via `C_AuctionHouse`
- **63 strategies** across 8 professions parsed from the Midnight spreadsheet
- **Profit / ROI engine** — cost-to-buy, net revenue after AH cut, break-even sell price
- **Editable starting amounts** — tell the addon what you already have in your bags
- **Shopping list** — aggregated NeedToBuy across all strategies
- **Item rank / variant support** — discovers itemIDs by name scan; picks highest/lowest/manual quality
- **Patch-tagged SavedVariables** — data scoped to `midnight-1` so future patch transitions are clean
- **CraftSim price bridge** (optional) — falls back gracefully if CraftSim is absent
- **Pure Blizzard UI** — no Ace3, no LibDBIcon, no external dependencies
- **ARP Export** — one-click export of all item prices in ARP addon format for spreadsheet paste
- **Debug log** — scrollable, copyable ring-buffer frame; `/gam log`

---

## Installation

1. Copy `GoldAdvisorMidnight/` into `World of Warcraft/_retail_/Interface/AddOns/`
2. Reload (`/reload`) — the addon registers under **Gold Advisor Midnight**
3. Open the Auction House to enable scanning

The `Sync_Addon.command` script at the repo root automates step 1 via `rsync`.

---

## Usage

### Minimap button
- **Left-click** — toggle the main strategy window
- **Right-click** — open the Settings panel
- **Drag** — repositions the button around the minimap edge (saved per character)

### Main window
1. Filter by patch tag, profession, or search text
2. Click a column header to sort
3. Click a row to open the detail panel
4. Click ★ to toggle a favourite
5. **Scan All** — queues every unpriced item for AH scanning (AH must be open)
6. **Shopping List** — aggregated buy list across all shown strategies

### Strategy detail
- Edit **Starting Amount** (top field) to set how many batches to calculate
- Edit individual reagent **Have** quantities inline
- **Scan** buttons queue individual items or all items for the strategy
- Metrics update live as prices arrive

### Slash commands
```
/gam           — toggle main window
/gam log       — open debug log
/gam scan      — queue all items for AH scan (AH must be open)
/gam clearcache — wipe the price cache for the current realm
/gam reload    — reload strategy data from SavedVars
```

---

## Build System

Strategy data is **generated** by a Python script — the addon cannot read CSV files at runtime.

### Re-running the build

```bash
python3 build/generate_strats.py
```

**Input**: `references/Spreadsheet/midnight_spreadsheet_extract_updated/{Profession}__grid.csv` + `{Profession}__formulas.json`
**Output**: `source/GoldAdvisorMidnight/Data/StratsGenerated.lua`

The script prints each strategy as it is parsed:
```
Processing Alchemy...
  ✓ [Alchemy] Composite Flora (4 reagents, 1 output(s), ×0.8107)
  ...
Done. 63 total strats
```

### Assigning item IDs

`StratsGenerated.lua` ships with empty `itemIDs = {}` tables. Populate them in `Data/StratsManual.lua` — entries there are merged over generated data at startup without touching the generated file:

```lua
-- Data/StratsManual.lua
GAM_STRATS_MANUAL[#GAM_STRATS_MANUAL+1] = {
    patchTag   = "midnight-1",
    profession = "Alchemy",
    stratName  = "Composite Flora",
    output = { itemIDs = { 12345 } },
    reagents = {
        { name = "Tranquility Bloom", itemIDs = { 67890 } },
    },
}
```

Alternatively, the AH name-scan feature discovers itemIDs at runtime for items that appear on the AH.

---

## Architecture

```
source/GoldAdvisorMidnight/
├── GoldAdvisorMidnight.toc     TOC Interface 120001
├── Constants.lua               GAM.C — all tunable constants
├── Locale.lua                  GAM.L — all user-visible strings
├── Log.lua                     Ring-buffer debug log (500 entries)
├── Core.lua                    Event backbone, SavedVars init, DB migration
├── Minimap.lua                 Pure Blizzard minimap button
├── Settings.lua                Blizzard Settings panel
├── Pricing.lua                 GetUnitPrice / CalculateStratMetrics
├── AHScan.lua                  C_AuctionHouse scan queue + throttle
├── Importer.lua                Loads + indexes StratsGenerated + StratsManual
├── CraftSimBridge.lua          Optional CraftSim price integration
├── Data/
│   ├── StratsGenerated.lua     AUTO-GENERATED — do not edit
│   └── StratsManual.lua        Manual itemID assignments + overrides
└── UI/
    ├── MainWindow.lua          Virtual-scroll strategy list
    ├── StratDetail.lua         Per-strategy detail + editable amounts
    ├── ShoppingList.lua        Aggregated NeedToBuy list
    └── DebugLog.lua            Scrollable copyable log frame + ARP Export

build/
└── generate_strats.py          CSV/JSON → StratsGenerated.lua
```

### SavedVariables layout

```lua
GoldAdvisorMidnightDB = {
    addonVersion = "1.0.2",
    dataVersion  = 2,
    options = {
        ahCut          = 0.05,   -- 5 %
        scanDelay      = 3.0,    -- seconds between AH queries
        resultWait     = 10.0,   -- timeout waiting for AH results
        debugVerbosity = 1,      -- 0=off 1=info 2=debug 3=verbose
        minimapHidden  = false,
        minimapAngle   = 45,
        rankPolicy     = "lowest",    -- "highest"|"lowest"|"manual"
        priceSource    = "ah",        -- "ah"|"craftsim"|"override"
    },
    patch = {
        ["midnight-1"] = {
            startingAmounts = {},   -- [stratID][reagentName] = qty
            favorites       = {},   -- [stratID] = true
            rankGroups      = {},   -- [itemName] = {itemID1, ...}
            priceOverrides  = {},   -- [itemID] = priceInCopper
        },
    },
    priceCache = {},   -- [realmKey][itemID] = {price,min,max,count,ts}
    scanState  = {},   -- [realmKey] = {lastScanTime}
}
```

### Strategy schema

Standard professions (single output):
```lua
{
    id         = "alchemy__composite_flora__midnight_1",
    patchTag   = "midnight-1",
    profession = "Alchemy",
    stratName  = "Composite Flora",
    notes      = "",
    sourceTab  = "Alchemy",
    defaultStartingAmount = 4000,
    output  = { name = "Composite Flora", itemIDs = {}, qtyMultiplier = 0.810750 },
    reagents = {
        { name = "Tranquility Bloom", itemIDs = {}, qtyMultiplier = 1.500000 },
        ...
    },
}
```

JC prospecting strats add an `outputs` list (all gem/stone yields):
```lua
{
    ...
    output  = { name = "Duskshrouded Stone", itemIDs = {}, qtyMultiplier = 0.270000 },
    outputs = {
        { name = "Harandar Peridot",   itemIDs = {}, qtyMultiplier = 0.020000 },
        { name = "Eversong Diamond",   itemIDs = {}, qtyMultiplier = 0.006400 },
        { name = "Duskshrouded Stone", itemIDs = {}, qtyMultiplier = 0.270000 },
        ...
    },
    reagents = {
        { name = "Refulgent Copper Ore", itemIDs = {}, qtyMultiplier = 1.000000 },
    },
}
```

---

## Strategy counts by profession

| Profession     | Strategies |
|----------------|:----------:|
| Alchemy        | 14         |
| Engineering    | 22         |
| Enchanting     | 5          |
| Inscription    | 6          |
| Leatherworking | 4          |
| Blacksmithing  | 3          |
| Tailoring      | 2          |
| Jewelcrafting  | 6          |
| **Total**      | **62**     |

---

## Verification checklist

1. `python3 build/generate_strats.py` → 63 total strats, no Python errors
2. Copy to AddOns dir; `/run print(GoldAdvisorMidnight and "OK")` → `OK`
3. Open AH → minimap button appears; left-click opens strategy list
4. Strategies visible in list filtered by profession
5. Click **Scan All** → prices populate; profit column turns green/red
6. Click a strategy → Detail panel opens to the right; edit **Qty/Craft** on any reagent → all quantities and output qty rescale
7. Click **Shopping List** in detail panel → single-strategy buy list appears to the left of the main window
8. `/gam log` → debug frame opens; `/run GAM.Log.Info("test")` → entry visible
9. Drag minimap button; `/reload` → position persists
10. Open Settings (right-click minimap button) → change Scan Delay → applies live
11. Load with CraftSim → no Lua errors; load without CraftSim → no Lua errors
12. JC Prospecting strat → Scan All Items scans ore + all gem outputs

---

## Known limitations / next steps

- `itemIDs` are all empty (`{}`) until populated via AH name scan or `StratsManual.lua`
- Spreadsheet-driven strategy defaults depend on which workbook snapshot was last imported; `StratsManual.lua` carries any newer workbook corrections until the extraction/build inputs are refreshed
- StratDetail rank picker UI for multi-itemID items is functional but does not persist the selected rank index between sessions (falls back to `rankPolicy`)
- CraftSim price bridge reads the first available price API; exact API may change with CraftSim updates
