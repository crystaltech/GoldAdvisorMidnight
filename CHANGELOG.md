# Changelog — Gold Advisor Midnight

## [1.2.0-RC4] — 2026-03-09

### Bug Fixes
- Fixed: R2 item prices were 29–45% higher than ARP Tracker — `DEEP_FILL_QTY` reduced
  from 50,000 to 10,000 to match ARP Tracker's default fill quantity; `MAX_SHALLOW_FILL_QTY`
  ceiling updated to match
- Fixed: Output prices for milling and prospecting strategies now match the rank of the
  input reagent — R1 herb/ore produces R1 pigment/gem price; R2 herb/ore produces R2
  price. Previously always showed R1 (cheapest) regardless of selected rank.
  Applies to all professions: Inscription (milling), Jewelcrafting (prospecting/crushing),
  Engineering (recycling), Blacksmithing (smelting), Leatherworking, Tailoring, Enchanting.
- Fixed: R2 quality items (non-commodity AH path) now use the same fill+trim logic as R1
  commodities; raw listings cached in session and persisted for qty-aware pricing
- Fixed: Debug log window now raises to front when opened via `/gam log` or minimap

## [1.2.0-RC3] — 2026-03-06

### Repo / Release Tooling
- Moved addon source tree to `source/GoldAdvisorMidnight/`
- Updated packaging script to build from `source/` and write release zips to `releases/`
- Updated sync scripts (`Sync_Addon.command`, memory sync scripts) for the new repo layout
- Updated build and setup documentation to reflect current paths

## [1.2.0-RC2] — 2026-03-03

### Bug Fixes
- Fixed: Minimap right-click now properly opens Blizzard Interface > AddOns Settings; eliminated
  infinite recursion between `OpenPanel()` and `Toggle()` in the fallback path
- Fixed: MainWindow footer displayed literal "STATUS_STRAT_COUNT" instead of strategy count —
  `L` was undefined outside `Build()` scope; added file-scope `local L = GAM.L`
- Fixed: Rank toggle button label was inverted — now shows what clicking will switch TO, not current state
- Fixed: Wrong reagent row had the editable qty box; now correctly selects the highest-qty reagent
  (the primary bulk input such as herbs or blooms, not secondary reagents like vials)

### Improvements
- Strategy Detail frame height increased from 620→700px; input section 200→240px; output 136→176px
- Settings > Actions buttons centered under their section header
- New: UI Scale slider in Settings > Display (range 0.7–1.5, applied live to all addon frames)

## [1.2.0-RC1] — 2026-03-03

### New Features
- **Strategy Creator** — create, edit, delete, export, and import custom strategies in-game
  (`/gam create`; Base64 `GAM1:` format for sharing with other GAM users)
- **Shallow Fill Mode** (Experimental) — prices reagents from a configurable AH fill quantity
  (250–50,000 units) instead of the default deep fill; toggle and qty control in Settings
- **Localization** — 10 locale files added: deDE, frFR, esES, esMX, ruRU, zhCN, zhTW, koKR,
  itIT, ptBR; all UI strings routed through `GAM.L` with English fallback
- **Native Settings panel** — Settings now registers as a proper Blizzard Interface > AddOns
  canvas; no more "frame inside a frame" appearance; minimap right-click opens it directly
- **Credits & Thanks scrollbox** in Settings — acknowledges Eloncs (spreadsheet data powering
  all strategies), Brrerker (arp_tracker; AH scanning inspiration), CraftSim integration,
  and the broader WoW addon community
- **2-column metrics layout** in Strategy Detail — Cost and Net Revenue on the left,
  ROI% and Break-Even on the right, Profit centered below a gold rule as the visual bottom line
- **Gold accent theme** — WoW-standard gold (`FFD100`) applied across all panels: window titles,
  column headers, section headers, and separator rules

### Improvements
- `itemKeyDB` SavedVar persists full AH itemKeys between sessions — skips browse re-scan on login
- `userStrats` top-level SavedVar stores user-created strategies persistently
- SavedVar migration v3: removes legacy `experimentalFillQty` option from DB
- Rank toggle (R1 Mats / R2 Mats) in Strategy Detail to switch material quality tier
- Auctionator list export from Strategy Detail (single-strat shopping list)
- Push-to-CraftSim price override integration for selected strategy reagents
- `patchDB.inputQtyOverrides` replaces old `qtyOverrides` key (keyed by stratID)

### Bug Fixes
- Fixed: `L["CONFIRM_DELETE_BODY"]` referenced nil `L` in `ShowDeleteConfirm()` — now uses `GAM.L`
- Fixed: Pigment rank ordering for Mana Lily Pigment and Sanguithorn Pigment (lower itemID = Q1)
- Fixed: `GetNumItemSearchResults` and `GetItemSearchResultInfo` require `itemKey` arg in Midnight 12.x
- Fixed: Browse fallback `_gen` counter prevents stale timeout callbacks from firing on new scans
- Fixed: `GetOutputPriceForItem` now averages across all quality ranks with RANK_TRIM=3.0 outlier exclusion

### Data
- 62 strategies across 8 professions (Midnight patch)
- Sin'dorei Armor Banding Q1 itemID verified in-game: 244636
- Oil of Dawn Q2: 243735; Munsell Ink Q1/Q2: 245801/245802 (corrected from crafted_id_names.csv)
- Radiant Shard Q1/Q2: 243602/243603; Eversinging Dust Q1/Q2: 243599/243600

---

## [1.1.x] — Prior beta versions

Internal beta builds. No public changelog maintained.
