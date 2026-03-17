# Changelog — Gold Advisor Midnight

## [1.3.0] — 2026-03-17

### Bug Fixes
- **Qty-aware pricing** — Reagent costs now use the actual purchase quantity (`needToBuy`) for AH fill calculations instead of the global `shallowFillQty` (default 50). A strategy needing 870 Mote of Light now fills 870 units of AH depth and averages that, rather than the shallow 50-unit cached average. Covers all four price paths:
  - Direct AH purchases (all professions)
  - Mill-derived herb costs — Inscription `pigmentCostSource = "mill"` now passes the actual herb volume needed (`pigmentQty / yieldPerHerb`) to the herb price lookup
  - Craft-derived bolt/ingot ingredient costs — Tailoring bolts and Blacksmithing ingots use per-ingredient volume
  - Stale price flag — was incorrectly returning `false` when using qty-aware raw data from a previous session; now always inherits the cached timestamp staleness

### New Features
- **V2 Profession sub-filter** — A `Profession` dropdown has been added to the V2 left panel between the Mine/All toggle and Fill Qty. Players with multiple professions (e.g. Leatherworking + Enchanting) can narrow the strategy list to a single profession. The dropdown auto-populates based on the current filter mode: player professions in Mine mode, all available professions in All mode. Resets to "All" when the mode toggle is switched.
- **Community info ticker** — A scrolling strip at the very bottom of the V2 window displays Discord, Twitch, Patreon, and tip links. The ticker pauses when hovered and resumes on mouse-off. Clicking anywhere on it opens a small copy-link dialog with a pre-selected EditBox for the tip URL.

### Internal / Data
- **WorkbookGenerated.lua** added — auto-generated item catalog and formula profiles from the workbook spreadsheet, replacing the hand-maintained `StratsManual.lua`
- `StratsManual.lua` removed; all strategies consolidated into `StratsGenerated.lua`
- **Direct formula output calculation** — output quantities now computed as `crafts × baseYieldPerCraft × statMultiplier` for cleaner stat scaling
- **Per-profession spec node bonuses** — Resourcefulness/Multicraft node bonus fields per profession; sync-able from CraftSim via the Sync button in Settings
- `DATA_VERSION` → 7; price cache wiped on upgrade
- V2 window height increased to 680px to accommodate profession dropdown and ticker

---

## [1.2.8] — 2026-03-16

### New Features
- **New UI Layout (Beta)** — opt-in three-panel redesign available via Settings > "Use New UI Layout (Beta)". Classic UI remains the default and is fully preserved. Toggle takes effect next time you open the window; no `/reload` required.
  - **Three-panel layout**: Left panel (190px — char info, profession filter, scan button), Center panel (flexible — strategy list), Right panel (340px — inline strategy detail). All three panels are collapsible; collapse state persists across sessions.
  - **Best Strategy Card**: hero card above the strategy list scores all strategies using `profit × √ROI` (minimum 5g profit and 5% ROI gates) and surfaces the top opportunity automatically. Updates after every scan and filter change.
  - **Inline Strategy Detail**: clicking any strategy row or the Best Strategy Card populates the right panel with reagents, outputs, and metrics (Cost, Revenue, Profit, ROI, Break-even). Action buttons: Scan All, CraftSim push, Shopping List, Edit/Delete (user strats only).
  - **Dual column config**: "All Professions" mode shows a Profession column; "My Professions" mode widens the strategy name column and shows profession as a subtitle on each row.
  - **Scan button disable**: both the left-panel and status-bar scan buttons are disabled while a scan is in progress to prevent double-trigger; re-enabled automatically on scan complete.
  - **First-run onboarding**: a semi-transparent overlay guides new users on first open. "Got It" dismisses; "Scan Auction House" dismisses and starts a scan immediately.
  - **Scan progress bar**: moved to the status bar at the bottom of the window; shows `X / Y items` label during scans.

### Bug Fixes
- Fixed: `StratDetail` and `StratCreator` delete/save/import handlers called `GAM.UI.MainWindow.Refresh()` directly, bypassing V2 when the new UI is active. All four call sites updated to use `GAM:GetActiveMainWindow().Refresh()`.

### Internal
- `Pricing.GetBestStrategy(patchTag, profFilter)` — returns `(strat, profit, roi)` for the highest `profit × √ROI` strategy above minimum thresholds.
- `GAM:GetActiveMainWindow()` helper in Core.lua routes window calls to the correct UI based on `useNewUI` DB option.
- `UI\MainWindowV2.lua` added to TOC (1,326 lines).

---

## [1.2.7] — 2026-03-16

### New Features
- **Per-Profession Spec Node Bonuses** — Settings > Crafting Stats now includes MCm Node and Rs Node fields for each profession. These model the extra multiplier bonus from your spec tree's Multicraft/Resourcefulness node upgrades, separate from your base gear stats. The addon scales output quantities using: `eff_mcm = BASE_MCM × (1 + u_mc_node)`, `eff_rs = BASE_RS × (1 + u_rs_node)`. Defaults match the values baked into the new Dynamic Stats spreadsheet.
- **CraftSim Spec Node Auto-Sync** — If CraftSim is installed, node bonus percentages are read automatically from CraftSimDB on login and applied to your stat profile. A "Sync from CraftSim" button in Settings lets you pull them on demand at any time.
- **Dynamic Stats Spreadsheet** — All 60 strategies regenerated from the updated Dynamic Stats spreadsheet (March 2026). Per-profession baked MCm/Rs constants are now modeled explicitly in STAT_PROFILES rather than using a global baseline.

### Data Updates
- Alchemy, Enchanting, Inscription, Jewelcrafting, Leatherworking, Tailoring, Blacksmithing, Engineering: strat values updated from the new Dynamic Stats sheet.
- Blacksmithing: explicit Q1/Q2 strat IDs for Gloaming Alloy, Sterling Alloy, Refulgent Copper Ingot.
- Removed strats no longer in the spreadsheet (Sin'dorei Lens/Sunglass Vial crafting, Scale-Woven Hide, Void-Touched Drums, Imbued Bright Linen Bolt, old generic BS IDs).

### Internal
- `DATA_VERSION` bumped to 5 — wipes price cache on first login so stale multipliers from changed strats do not persist.
- All 60 strats verified against spreadsheet source values (60/60 pass).

---

## [1.2.6] — 2026-03-14

### Improvements
- After a scan completes, the strategy list now auto-sorts by highest ROI so the best opportunities surface immediately. Column headers remain clickable to re-sort manually.

### Data Fixes
- Fixed: Brilliant Silver Ore Prospecting — Crystalline Glass `qtyMultiplier` corrected from 0.180 → 0.095 (in-game testing: ~35 from 400 ore at 17% res; back-calculated baked rate ≈ 0.095).

---

## [1.2.5] — 2026-03-13

### New Features
- **Crafting Stat Scaling** — Settings > Crafting Stats section lets you enter your actual Multicraft% and Resourcefulness% per profession/tool-set. The addon scales output quantities from the baked spreadsheet baseline to your gear using the Master Equation: `scale = [(1 + u_multi × 1.875) / (1 + b_multi × 1.875)] × [(1 - b_res × 0.45) / (1 - u_res × 0.45)]`. Defaults match the baked-in values → fully-geared players see no change; players with lower stats see corrected (lower) outputs and profits.
- 12 stat groups cover all professions: Inscription (Milling, Ink), Jewelcrafting (Prospecting, Crushing, Crafting), Enchanting (Shattering, Crafting), Alchemy, Tailoring, Blacksmithing, Leatherworking, Engineering. Milling/Prospecting/Crushing/Shattering have no Multicraft field (profession window does not show Multicraft for those tool sets).
- Custom strats created in Strategy Creator are unaffected (scale = 1.0).

### New Strats
- **Enchanting — Radiant Shatter Q1**: shatters rank-1 Radiant Shards (3000) into Eversinging Dust Q1 (×3.36, i.e. 10,080 expected dust).

### Data Fixes
- Fixed: Blacksmithing Gloaming Alloy and Sterling Alloy Q1 — `defaultStartingAmount` corrected from 6,000 → 3,000 ore; `qtyMultiplier` corrected from 0.243667 → 0.240000 (720 expected alloy per 3,000 ore per updated March 2026 spreadsheet).

---

## [1.2.4] — 2026-03-13

### New Features
- **Mill Own Herbs** checkbox in Settings > Pricing — switches Inscription ink strategy cost from AH pigment prices to milling-derived cost (herb price ÷ expected pigment yield). Persists between sessions; defaults to AH pricing (no behavior change for existing users).

---

## [1.2.3] — 2026-03-12

### Bug Fixes
- Fixed: Strategy Creator window did not open — `MakeItemRow` referenced `L` (local to `Build()`) from module scope where it is nil; changed to `GAM.L`

---

## [1.2.2] — 2026-03-12

### New Strats
- **Jewelcrafting — Crushing**: converts cheapest low-tier gem (e.g. Amani Lapis) + Duskshrouded Stone into Glimmering Gemdust (start=673, output mult=0.835015, DS mult=0.35 for 35% resourcefulness)

### Data Fixes
- Fixed: Engineering crafting strats — Smuggler's Lynxeye, Laced Zoomshots, Farstrider Hawkeye, Weighted Boomshots output `qtyMultiplier` was 1.0; corrected to 1.875 (3750 expected / 2000 start)
- Fixed: Recycling Sunfire Silk Bolt output qty — 0.7068 → 0.7088 (7088 / 10000)
- Fixed: Leatherworking Void-Touched Drums output qty — 1.0 → 1.7 (1700 / 1000)
- Fixed: Enchanting Dawn Shatter Q2 — replaced stub with full multi-output: Q2 Radiant Shard ×2.3955 (4791/2000), Q1 Radiant Shard ×0.9465 (1893/2000)
- Fixed: Enchanting Radiant Shatter Q2 — replaced stub with full multi-output: Q2 Eversinging Dust ×2.3334 (7000/3000), Q1 Eversinging Dust ×1.0 (3000/3000)
- Fixed: Enchanting Oil of Dawn — added missing Q2 itemID 243736 (only Q1 243735 was in generated file)
- Fixed: Leatherworking Sin'dorei Armor Banding output name — was "Sin'Dorei"; corrected to "Sin'dorei" (WoW uses lowercase 'd')

### Code Quality
- All strategy data consolidated into `StratsGenerated.lua`; `StratsManual.lua` now reserved for new strats and hotfixes only

---

## [1.2.1] — 2026-03-12

### New Features
- **Spreadsheet Export** button moved to the Main Window bottom-left (below strategy count) for quicker access — no longer requires opening the Debug Log

### Bug Fixes
- Fixed: `ToggleFavorite` used wrong Lua expression — could store `true` instead of removing the key when un-favoriting, causing favorites to be sticky
- Fixed: `GAM.UI.MainWindow.Refresh()` was called by StratDetail and StratCreator on strat delete/save/import but the function did not exist — every delete/save operation produced a nil-call crash
- Fixed: Settings panel `ApplySettings` ran twice when closing via native Blizzard Settings (okay callback + OnHide both fired) — could double-wipe the price cache on fill qty change
- Fixed: `Pricing.GetOpts()` dereferenced `GAM.db.options` directly — now guards against `GAM.db` being nil before ADDON_LOADED
- Fixed: `PickItemID` called redundantly on every iteration of the quality-rank fallback loop — result is now cached before the loop

### Improvements
- Scan delay default corrected in docs (was documented as 3.0 s; actual default is 1.0 s)
- AH scan queue dequeue changed from O(n) `table.remove(scanQueue, 1)` to O(1) head-index advance — reduces per-tick CPU cost on large queues
- Removed dead `pendingLines` table from DebugLog
- Removed unused `DEBOUNCE_DELAY` constant; unified `DEFAULT_AH_CUT` into `AH_CUT` (Settings now reads `GAM.C.AH_CUT` instead of hardcoding `0.05`)

---

## [1.2.0] — 2026-03-11

### Breaking Changes
- **Fill Qty is now the only pricing mode** — the "Shallow Fill Mode (Experimental)" checkbox
  has been removed. All pricing uses a single configurable Fill Qty (default: 50 units,
  range: 10–10,000). Users who were on the old deep fill default (10,000 units) will be
  reset to 50 on first load; change Fill Qty in Settings to restore higher values.

### Improvements
- Removed "Experimental" label from the fill qty setting
- Strategy Detail window always shows active Fill Qty in the notice bar
- Fill Qty range expanded: minimum is now 10 (was 250)
- Settings UI simplified: checkbox removed, Fill Qty editbox is always active
- All locale files updated with new range and neutral terminology

### Bug Fixes
- Fixed: Rank selection in the Pricing engine used array position instead of actual crafting
  quality (Crystalline Glass, Sunglass Vial affected; Sin'dorei Lens showed wrong profit)

---

## [1.2.0-RC5a] — 2026-03-11

### New Features
- **ARP Export** — new button in the Debug Log window generates item pricing data in
  AverageReagentPrice (ARP) addon format (`ItemName, Rank 1, X.XX, Rank 2, X.XX, Rank 3, X.XX`)
  for direct paste into the comparison spreadsheet

### Bug Fixes
- Fixed: ARP Export rank ordering was wrong when itemID array order did not match crafting quality
  order — now uses `C_TradeSkillUI.GetItemReagentQualityByItemInfo` to assign each ID to its
  correct rank slot (Crystalline Glass, Sunglass Vial affected)
- Fixed: Non-tiered items (e.g. Dazzling Thorium, Petrified Root) were skipped by the ARP Export
  because `GetItemReagentQualityByItemInfo` returns `nil` for both uncached and non-tiered items;
  now uses `GetItemInfo` fallback — cached non-tiered items are placed at Rank 1
- Fixed: Q-suffix output items (e.g. "Eversinging Dust Q2") were placed at their quality rank
  (Rank 2) instead of Rank 1, producing a 0 in the spreadsheet VLOOKUP; now forced to Rank 1
- Item cache pre-warmed at `PLAYER_LOGIN` so ARP Export works reliably without a prior AH scan

### Data
- **Oil of Dawn** (Enchanting): added missing Q2 itemID 243736 — both ranks now export correctly
  (Q1=243735, Q2=243736, confirmed in-game)

## [1.2.0-RC4a] — 2026-03-10

### Data
- Refreshed all spreadsheet extract inputs from March 10, 2026 workbook
- Updated Jewelcrafting strategy math: Dazzling Thorium Prospecting (2000 start,
  corrected output multipliers), Sunglass Vial Crafting (2500 start, Stone ×0.2,
  Vial ×0.35), Sin'dorei Lens Crafting (3000 start, Gemdust ×0.333, Lens ×0.575)
- Updated Leatherworking strategy math: all 4 strats verified against workbook
- Added Sanguithorn Milling as a distinct Inscription strategy (63 strats total; was 62)
- Added `build/extract_spreadsheet.py` — openpyxl workbook extractor; fixes broken
  build pipeline (`generate_strats.py` now reads from `references/Spreadsheet/JSON_CSV/`)

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
