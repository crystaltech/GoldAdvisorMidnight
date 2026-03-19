# Project Structure — GoldAdvisorAddon

This repository contains the Gold Advisor Midnight WoW addon and all supporting tooling.

---

## Top-Level Layout

```
GoldAdvisorAddon/
├── source/                    Addon source (the only thing that ships to players)
├── tools/                     Data generation and encode/decode scripts
├── references/                Spreadsheets and game notes (not shipped)
├── releases/                  Built zip artifacts (not committed)
├── build/                     Legacy build scripts (archived)
├── memory/                    Claude Code project memory files
│
├── Sync_Addon.command         rsync source/ → WoW AddOns directory
├── Package_Addon.command      Build release zip only (no git ops)
├── Release_Addon.command      Build + commit + tag + push + GitHub release (plain)
└── Release_Protected.command  Build + commit + tag + push + GitHub release (encoded data)
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
├── Minimap.lua                   Pure Blizzard minimap button
├── Settings.lua                  Blizzard Settings panel (crafting stat fields for all professions)
├── Pricing.lua                   Price engine: GetEffectivePriceForItem, CalculateStratMetrics, FormatPrice
├── AHScan.lua                    C_AuctionHouse scan queue, throttle, progress callbacks
├── Importer.lua                  Loads StratsGenerated; XOR decoder for protected builds
├── CraftSimBridge.lua            Optional CraftSim stat sync and price push
├── Data/
│   ├── WorkbookGenerated.lua     AUTO-GENERATED — item catalog + formula profiles per profession
│   └── StratsGenerated.lua       AUTO-GENERATED — all 64 strategy definitions
└── UI/
    ├── MainWindowV2.lua          Three-panel main window (left controls / center list / right detail)
    ├── StratDetail.lua           Inline strategy detail panel (reagents, metrics, crafts scaler)
    ├── StratCreator.lua          Custom strategy creation UI
    └── DebugLog.lua              Scrollable debug log frame + ARP price export
```

The `Data/*Generated.lua` files are written by `tools/generate_workbook_data.py` and must not be edited manually.

In a **protected release**, these two files are encoded to `Data/*Encoded.lua` before zipping, and the TOC is temporarily patched to load them. The git repo always stays in plain dev state.

---

## tools/

```
tools/
├── generate_workbook_data.py   Reads .xlsx spreadsheet → writes WorkbookGenerated.lua + StratsGenerated.lua
├── encode_data.py              XOR + custom-base64 encode for protected builds (called by Release_Protected.command)
├── decode_data.py              Decode for debugging encoded builds
└── ENCODING_HOWTO.md           Notes on the encoding scheme
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
├── GoldAdvisorMidnight-v1.4.3-protected.zip    (latest)
└── ...
```

Zips are attached to GitHub releases via the release scripts.

---

## Release Scripts

| Script | What it does |
|--------|-------------|
| `Sync_Addon.command` | rsync `source/GoldAdvisorMidnight/` into the local WoW AddOns directory for testing |
| `Package_Addon.command` | Build a plain release zip into `releases/` (no git ops) |
| `Release_Addon.command` | Package_Addon + `git add source/ CHANGELOG.md` + commit + tag + push + `gh release create` |
| `Release_Protected.command` | Same as Release_Addon but encodes data files before zipping, restores TOC after |

All release scripts read the version from `## Version:` in the TOC file — bump that (and `ADDON_VERSION` in Constants.lua) before running.
