# GoldAdvisorMidnight

WoW Retail Midnight (12.0.x / TOC 120001) crafting profit advisor.

Scans the Auction House for live prices, computes profit and ROI for spreadsheet-sourced crafting strategies, and presents a sortable in-game list with inline detail and a shopping aggregator.

---

## Features

- **Live AH scanning** — throttled commodity + item queries via `C_AuctionHouse`
- **64 strategies** across 8 professions, generated from the Midnight community spreadsheet
- **Profit / ROI engine** — cost-to-buy, net revenue after AH cut, break-even sell price, Multicraft / Resourcefulness stat scaling
- **Formula profiles** — per-profession crafting stat slots (Res%, Multi%, spec node bonuses) match the spreadsheet model exactly
- **Editable batch sizes** — override crafts or starting amount per strategy; scales all quantities live
- **Fill Qty simulation** — simulates buying N units from the AH order book so large runs reflect real market depth
- **Mill / craft own intermediates** — "Mill Own Herbs" and "Craft Own Ingots/Bolts" modes expand derived reagent chains to raw material costs
- **Shopping list** — aggregated NeedToBuy across all strategies
- **Inline strategy detail** — right-hand panel in the main window; no secondary window required
- **Best Strategy card** — highlights the current top opportunity
- **Item rank / variant support** — R1/R2 rank policy (lowest / highest) per strategy
- **CraftSim stat sync** — imports profession stats (Res%, Multi%, node bonuses) from CraftSim in one click
- **ARP Export** — one-click price export in AverageReagentPrice addon format for spreadsheet paste
- **Quick Buy** — macro-driven AH purchase flow via hidden named button `GAMQuickBuyBtn`; one hardware event per item
- **Protected build** — strategy data files are XOR-encoded in release zips
- **Pure Blizzard UI** — no Ace3, no LibDBIcon, no external dependencies
- **10 locales** — deDE, frFR, esES, esMX, ruRU, zhCN, zhTW, koKR, itIT, ptBR (community-maintained)

---

## Installation

1. Copy `GoldAdvisorMidnight/` into `World of Warcraft/_retail_/Interface/AddOns/`
2. Reload (`/reload`) — the addon registers under **Gold Advisor Midnight**
3. Open the Auction House to enable scanning

The `Sync_Addon.command` script at the repo root automates step 1 via `rsync`.

---

## Usage

### Minimap button
- **Left-click** — toggle the main window
- **Right-click** — open Settings
- **Drag** — repositions the button around the minimap edge (saved per character)

### Main window (V2)
The window has three panels:

**Left panel** — scan controls and options:
- Mine / All toggle — filter to your professions or show everything
- Profession sub-filter dropdown
- Fill Qty, AH Cut %, stat options (Mill Own Herbs, Craft Own Ingots/Bolts)
- Scan All / Shopping List buttons

**Center panel** — sortable strategy list; click a row to open detail

**Right panel** — inline strategy detail:
- Output item, expected quantity, unit price
- Reagent table with bag counts and NeedToBuy
- Profit / ROI / Break-Even metrics
- Crafts editbox for live batch scaling
- Scan buttons, CraftSim push

### Slash commands

```
/gam              — toggle main window
/gam log          — open debug log
/gam scan         — queue all items for AH scan (AH must be open)
/gam clearcache   — wipe the price cache for the current realm
/gam reload       — reload strategy data
/gam quickbuy     — stop / disarm the Quick Buy queue
/gam create       — open Strategy Creator
/gam ids          — dump tracked item IDs to the debug log
```

### Quick Buy

1. Create a macro: `/click GAMQuickBuyBtn` and bind it to a key (one-time setup)
2. Build a Shopping List from any strategy
3. Open AH → press your macro key — it auto-arms and buys the first item
4. Press again per item until the list empties (or `/gam quickbuy` to stop early)

Each keypress provides one hardware event — required by WoW for AH commodity purchases.

---

## Build System

Strategy and formula-profile data are **generated** from the community spreadsheet — the addon cannot read `.xlsx` files at runtime.

### Re-generating data

```bash
python3 tools/generate_workbook_data.py
```

**Input**: `references/Spreadsheet/<spreadsheet>.xlsx`
**Output**:
- `source/GoldAdvisorMidnight/Data/WorkbookGenerated.lua` — item catalog and formula profiles
- `source/GoldAdvisorMidnight/Data/StratsGenerated.lua` — all 64 strategy definitions

Do not edit the `*Generated.lua` files manually; they are overwritten on the next run.

### Protected build

The protected release script encodes both generated data files before zipping:

```
StratsGenerated.lua   → StratsEncoded.lua   (XOR + custom-base64, ~116 KB)
WorkbookGenerated.lua → WorkbookEncoded.lua  (XOR + custom-base64, ~10 KB)
```

The TOC is patched to load the encoded files, the zip is built, then the TOC and encoded files are removed — the git repo always stays in plain dev state.

```bash
bash Release_Protected.command   # encoded zip + commit + tag + push + GitHub release
bash Release_Addon.command       # plain zip + commit + tag + push + GitHub release
```

---

## Architecture

```
source/GoldAdvisorMidnight/
├── GoldAdvisorMidnight.toc       TOC Interface 120001
├── Constants.lua                 GAM.C — all tunable values and defaults
├── Locale.lua                    GAM.L — English strings (fallback for all locales)
├── Locale/                       10 community-maintained locale files
├── Log.lua                       Ring-buffer debug log (500 entries)
├── Core.lua                      Event backbone, SavedVars init, DB migration, slash commands
├── Minimap.lua                   Pure Blizzard minimap button
├── Settings.lua                  Blizzard Settings panel (all profession stat fields)
├── Pricing.lua                   GetEffectivePriceForItem / CalculateStratMetrics / FormatPrice
├── AHScan.lua                    C_AuctionHouse scan queue + throttle + progress callbacks
├── Importer.lua                  Loads + indexes StratsGenerated; XOR decoder for protected builds
├── CraftSimBridge.lua            Optional CraftSim stat sync and price push
├── Data/
│   ├── WorkbookGenerated.lua     AUTO-GENERATED — item catalog + formula profiles
│   └── StratsGenerated.lua       AUTO-GENERATED — all 64 strategy definitions
└── UI/
    ├── MainWindowV2.lua          Three-panel main window (list + inline detail + best card)
    ├── StratDetail.lua           Inline strategy detail panel
    ├── StratCreator.lua          Custom strategy creation UI
    └── DebugLog.lua              Scrollable log frame + ARP Export

tools/
├── generate_workbook_data.py     xlsx → WorkbookGenerated.lua + StratsGenerated.lua
├── encode_data.py                XOR encode for protected builds
└── decode_data.py                Decode for debugging

releases/                         Built zips (not committed)
```

### SavedVariables layout

```lua
GoldAdvisorMidnightDB = {
    addonVersion = "1.4.3",
    dataVersion  = 8,
    options = {
        ahCut              = 0.05,
        scanDelay          = 1.0,
        debugVerbosity     = 1,       -- 0=off 1=info 2=debug 3=verbose
        minimapHidden      = false,
        minimapAngle       = 45,
        rankPolicy         = "lowest",   -- "lowest"|"highest"
        priceSource        = "ah",
        pigmentCostSource  = "ah",       -- "ah"|"mill"
        boltCostSource     = "ah",       -- "ah"|"craft"
        ingotCostSource    = "ah",       -- "ah"|"craft"
        shallowFillQty     = 50,
        uiScale            = 1.0,
        -- Per-profession stat fields (see WorkbookGenerated.formulaProfiles for full key list)
        inscMillingRes = 30.1, inscRsNode = 55,
        inscInkMulti   = 25.9, inscInkRes = 16.1, inscMcNode = 100,
        -- ... alchemy, jc, enchanting, tailoring, bs, lw, engineering
    },
    patch = {
        ["midnight-1"] = {
            rankGroups        = {},   -- [itemName] = {itemID, ...}
            priceOverrides    = {},   -- [itemID] = priceInCopper
            inputQtyOverrides = {},   -- [stratID] = qty override
            craftsOverrides   = {},   -- [stratID] = crafts override
            favorites         = {},   -- [stratID] = true
            priceCache        = {},   -- [realmKey][itemID] = {price, ts}
        },
    },
}
```

### Strategy schema

```lua
{
    id            = "alchemy__composite_flora__midnight_1",
    patchTag      = "midnight-1",
    profession    = "Alchemy",
    stratName     = "Composite Flora",
    sourceTab     = "Alchemy",
    sourceBlock   = "C7",
    defaultStartingAmount = 4000,
    defaultCrafts         = 1000,
    formulaProfile    = "alchemy",   -- key into WorkbookGenerated.formulaProfiles
    calcMode          = "formula",   -- "formula" | "fixed"
    qualityPolicy     = "normal",
    outputQualityMode = "rank_policy",
    notes = "",
    outputs = {
        { itemRef = "Composite Flora", itemIDs = {241280, 241281},
          baseYieldPerCraft = 2.0, baseYield = 0.5,
          workbookExpectedQty = 3036.649 },
    },
    reagents = {
        { itemRef = "Mote of Wild Magic", itemIDs = {236951},
          qtyPerCraft = 4.0, qtyPerStart = 1.0,
          workbookTotalQty = 4000 },
        -- ...
    },
    -- rankVariants (optional): lowest/highest recipe variants for BS/LW/JC strats
}
```

---

## Strategy counts by profession

| Profession      | Strategies |
|-----------------|:----------:|
| Engineering     |     22     |
| Alchemy         |     14     |
| Jewelcrafting   |      7     |
| Inscription     |      7     |
| Enchanting      |      5     |
| Leatherworking  |      4     |
| Blacksmithing   |      3     |
| Tailoring       |      2     |
| **Total**       |   **64**   |

---

## Verification checklist

1. `python3 tools/generate_workbook_data.py` → no errors, both `*Generated.lua` files updated
2. Copy to AddOns dir (`bash Sync_Addon.command`); `/run print(GoldAdvisorMidnight and "OK")` → `OK`
3. Open AH → minimap button appears; left-click opens main window
4. Mine / All toggle and profession dropdown filter the list correctly
5. Click **Scan All** → progress updates; profit column populates green/red on completion
6. Second scan after switching profession filter maintains 60+ FPS throughout
7. Click a strategy → right panel shows reagents, metrics, crafts editbox
8. Edit Crafts field → all quantities and output scale live
9. Click **Shopping List** → aggregated buy list appears
10. Build shopping list → press `/click GAMQuickBuyBtn` macro → auto-arms and buys one item per press; `/gam quickbuy` stops early
11. `/gam log` → debug frame opens
12. Drag minimap button; `/reload` → position persists
13. Right-click minimap → Settings opens; stat fields present for all professions
14. Load with CraftSim → no Lua errors; load without CraftSim → no Lua errors
15. `bash Release_Protected.command` → encoded zip built, TOC restored to dev state after
