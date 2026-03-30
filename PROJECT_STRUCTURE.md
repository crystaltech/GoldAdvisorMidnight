# Project Structure — GoldAdvisorAddon

This repository contains the Gold Advisor Midnight WoW addon and all supporting tooling.

---

## Top-Level Layout

```
GoldAdvisorAddon/
├── source/                    Addon source (the only thing that ships to players)
├── tools/                     Data generation and verification scripts
├── references/                Spreadsheets and game notes (not shipped)
├── releases/                  Built zip artifacts (not committed)
├── build/                     Legacy build scripts (archived)
├── memory/                    Claude Code project memory files
│
├── Sync_Addon.command         rsync source/ → WoW AddOns directory
├── Package_Addon.command      Build release zip only (no git ops)
├── Release_Discord.command    Build plain pre-release zip + GitHub pre-release
├── Release_CurseForge.command Build plain release zip + GitHub release + CurseForge upload
├── Release_Patreon.command    Build plain handoff zip only
└── Release_Addon.command      Legacy: build + commit + tag + push + GitHub release (plain)
```

---

## source/GoldAdvisorMidnight/

The addon itself. Everything inside this folder ships in the release zip.

```
source/GoldAdvisorMidnight/
├── GoldAdvisorMidnight.toc       Interface 120001 (WoW Midnight 12.0.x)
├── Constants.lua                 GAM.C — all tunable values and defaults
├── Locale.lua                    GAM.L — English strings (fallback for all locales)
├── Locale/                       10 community locale files (deDE frFR esES esMX ruRU zhCN zhTW koKR itIT ptBR)
├── Log.lua                       Ring-buffer debug log (500 entries)
├── Core.lua                      Event backbone, SavedVars init, DB migration, slash commands, Quick Buy
├── State.lua                     Shared addon state (selected strat, patchTag, UI refs)
├── Minimap.lua                   Pure Blizzard minimap button
├── Settings.lua                  Blizzard Settings panel (crafting stat fields for all professions)
├── Pricing.lua                   Price engine: GetEffectivePriceForItem, CalculateStratMetrics, FormatPrice
├── PricingDerivation.lua         Vertical integration derivation chains (mill/craft cost paths)
├── AHScan.lua                    C_AuctionHouse scan queue, throttle, progress callbacks
├── Importer.lua                  Loads StratsGenerated and normalizes it for runtime
├── CraftSimBridge.lua            Optional CraftSim stat sync and price push
├── Data/
│   ├── WorkbookGenerated.lua     AUTO-GENERATED — item catalog + formula profiles per profession
│   └── StratsGenerated.lua       AUTO-GENERATED — 62 strategy definitions
└── UI/
    ├── MainWindowV2.lua          Three-panel main window coordinator (layout, theme, refresh)
    ├── MainWindowV2Common.lua    Shared theme definitions and helper utilities
    ├── MainWindowV2LeftPanel.lua Left panel: scan controls, filters, VI toggle, craft stats
    ├── MainWindowV2Center.lua    Center panel: sortable strategy list
    ├── MainWindowV2Detail.lua    Right panel: inline strategy detail (reagents, metrics, scaler)
    ├── StratDetail.lua           Standalone strategy detail panel
    ├── StratCreator.lua          Custom strategy creation UI
    └── DebugLog.lua              Scrollable debug log frame + ARP price export
```

The `Data/*Generated.lua` files are written by `tools/generate_workbook_data.py` and must not be edited manually.

---

## tools/

```
tools/
├── generate_workbook_data.py   Reads .xlsx spreadsheet → writes WorkbookGenerated.lua + StratsGenerated.lua
├── compare_strats.py           Verifies StratsGenerated.lua matches spreadsheet source (must show 0 mismatches before release)
├── verify_stat_scaling.py      Verify crafting stat scaling calculations against expected values
└── manual_strats.json          Supplemental strategy entries merged in by the generator
```

---

## references/

Long-term reference assets. Nothing here ships to players.

```
references/
├── Spreadsheet/                Community crafting spreadsheet versions (source for data generation)
└── WoW_Game_Notes/             Gameplay and profession notes
```

The active spreadsheet used by `tools/generate_workbook_data.py` is whichever `.xlsx` is pointed to in that script.

---

## releases/

Built zip artifacts. This directory is not committed to git.

```
releases/
├── GoldAdvisorMidnight-v1.7.14.zip    (example)
└── ...
```

Zips are attached to GitHub releases via the release scripts.

---

## Release Scripts

| Script | What it does |
|--------|-------------|
| `Sync_Addon.command` | rsync `source/GoldAdvisorMidnight/` into the local WoW AddOns directory for testing |
| `Package_Addon.command` | Plain unencoded zip only, no git ops, for local testing |
| `Release_Discord.command` | Plain zip + GitHub pre-release tag `vX.X.X-discord`, pushes current branch |
| `Release_CurseForge.command` | Plain zip + GitHub stable release + CurseForge upload, pushes `main` |
| `Release_Patreon.command` | Plain handoff zip only, no git ops, for direct distribution |
| `Release_Addon.command` | Legacy: plain zip + commit + tag + push + GitHub release |

All release scripts read the version from `## Version:` in the TOC file — bump that (and `ADDON_VERSION` in Constants.lua) before running.
