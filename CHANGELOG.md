# Changelog — Gold Advisor Midnight

## [1.8.8] — 2026-04-16

### Bug Fixes
- **Ink Songwater quantity corrected** — Sienna Ink and Munsell Ink strategies had `qtyPerCraft = 30` for Thalassian Songwater due to a 10x-inflated value in the spreadsheet; corrected the source data to 3 per craft and regenerated.

## [Unreleased]

### Data / Workbook
- **Cooking workbook import shipped** — The addon now includes `11` workbook-backed Cooking strategies, covering meals, feasts, and tea chains across the new `Cooking` sheet.
- **Cooking stat defaults and vendor pricing added** — Cooking now has its own workbook formula profile, saved stat defaults, settings-row controls, and static vendor pricing for core Cooking vendor mats.
- **Coverage/docs refreshed for shipped data** — The README and strategy coverage report now reflect the current `73` built-in strategies across `9` professions.

### Tooling
- **Seed-based workbook import path added** — New workbook-backed strategies can now be introduced from checked-in seed records instead of hand-editing generated Lua blocks.
- **Dazzling Thorium validation corrected** — The strategy comparer now accepts the intended full ranked output ID arrays for `Dazzling Thorium Prospecting`, matching runtime pricing behavior.
- **One-step GitHub release helper added** — `Release_GitHub.command` can bump the addon version, package the zip, commit, push, and create the GitHub release in one flow.

## [1.8.0] — 2026-04-12

### UI / Workflow
- **V2 polish pass shipped across both themes** — The main window now uses tighter card spacing, calmer separators, improved row striping, stronger selected-row treatment, clearer placeholder copy, and more consistent type rhythm across the header, list, detail, and footer surfaces.
- **VI breakdown now reads summary-first** — The popup keeps the same workflow and placement, but the summary block is more prominent, stage rows are easier to distinguish from child steps, and branch depth is clearer at a glance.
- **VI wording cleaned up** — Visible VI labels now use plain-language headers like `Amount`, `Plan Crafts`, `Actual Crafts`, and `Source`, with helper copy updated to explain the plan in user-facing terms instead of spreadsheet shorthand.

## [1.7.25] — 2026-04-09

### Bug Fixes
- **VI breakdown render path hardened again** — The VI popup now applies its row/header layout immediately instead of relying on later size callbacks, and it logs a clear debug warning plus visible fallback message if client-specific UI state still prevents the detailed panel from rendering.
- **Sunglass Vial reagent count corrected** — The Jewelcrafting strategy now requires 1 Duskshrouded Stone per craft again, so craft totals no longer show the halved stone requirement.
- **CraftSim node scaling restored on top of workbook baselines** — Formula strategies now keep spreadsheet parity at default nodes, then scale from those baked baselines to the player’s synced specialization bonuses when CraftSim cache data is available.
- **Blacksmithing baseline refreshed from live workbook formulas** — Refulgent Copper Ingot, Gloaming Alloy, and Sterling Alloy now use the sheet’s current Blacksmithing crafting baseline (`33%` Multi with effective `sheetMCm=1.4`), fixing undercounted output totals like Refulgent Copper Ingot showing `1496` instead of `1549` for 1000 crafts.

### UI / Workflow
- **Cooking profession scaffold added** — `Cooking` is now part of the canonical supported profession list and skill-line mapping, so it can appear in profession-aware filters and creator dropdowns even before any Cooking strategies are shipped.

## [1.7.24] — 2026-04-08

### Bug Fixes
- **VI breakdown blank-window fallback added** — The VI popup now anchors its scroll content more defensively, shows a clear empty-state instead of a silent black panel, and falls back to merged reagent rows when detailed branch steps are unavailable for a user/client state.

## [1.7.23] — 2026-04-08

### VI / Pricing
- **Generic vertical-integration graph shipped** — `Use own items/crafts` now recurses through loaded single-output producer strategies instead of only the old hardcoded pigment / bolt / ingot families, so chains like `Soul Cipher` and `Codified Azeroot` can resolve through their real craft trees when VI is enabled.
- **Economic vs execution VI math split finalized** — Summary economics now use fractional expected-value leaves for `Total Cost`, `Buy Now Cost`, `Profit`, `ROI`, and `Break-even`, while visible reagent rows, shopping lists, and scan helpers keep rounded execution counts for practical buying.
- **Manual missives moved to conservative estimated output math** — All six manual Thalassian missives now use a dedicated conservative inscription formula profile instead of fixed `1:1` output, so missive profitability no longer ignores resourcefulness / multicraft entirely.
- **Selected output pricing now respects fill-sensitive AH depth** — Unit sell pricing and debug scan dumps now stay aligned with the active fill quantity instead of drifting toward a different order-book slice.

### UI / Workflow
- **Resizable VI breakdown window added** — A dedicated popup now shows step-by-step VI chain expansion with branch-local costs, economic vs execution craft counts, direct AH comparisons, and clearer quantity formatting for large batch plans.
- **VI breakdown is now user-controlled** — The popup is toggled by a new `Show VI breakdown` checkbox under `Use own items/crafts`, so it follows selected strategies only when you want it on.
- **VI readability pass** — Breakdown headers, captions, and tooltips now explain the difference between merged header totals and branch-local row steps in shorter wording.

### Bug Fixes
- **Theme apply is safe before the main window exists** — Changing settings no longer throws a nil-frame Lua error if the V2 main window has not been built yet.

## [1.7.22] — 2026-04-07

### Bug Fixes
- **Vertical-integration economics corrected** — `Total Cost`, `Buy Now Cost`, `Profit`, `ROI`, and `Break-even` now stay anchored to the expected-value reagent model while `Use own items/crafts` display rows continue to round through real craft and milling batches for shopping accuracy.
- **Manual missive output inflation removed** — All six manual Thalassian missives now use a conservative fixed-output `1 craft = 1 missive` model instead of borrowing the `insc_ink` expected-value formula, so unexpected multicraft upside stays a bonus instead of being pre-baked into profit.

### Debugging / Workflow
- **Selected-strategy scan dump added** — `/gam scandump` opens the debug log and prints the selected strategy's output/input item IDs, cached prices, fill-sensitive averages, and raw scanned rows so incorrect AH expectations can be traced quickly.
- **Missive + VI smoke coverage added** — Pricing smoke tests now guard both the vertical-integration economics split and the new conservative missive output path.

## [1.7.21] — 2026-04-07

### Bug Fixes
- **Live quantity-aware pricing restored** — Strategy pricing now uses live AH depth again when scan data is available, so changing `Crafts` updates reagent pricing, total cost, profit, ROI, and break-even together instead of sticking to a single cheapest unit.
- **Non-commodity output pricing corrected** — Item-auction scans now weight listings by stack quantity instead of one listing = one vote, fixing inflated unit sell prices on outputs like `Thalassian Missive of the Quickblade`.
- **Vertical-integration totals reconciled** — `Total Cost`, `Buy Now Cost`, and the visible reagent rows now share the same resolved reagent model when `Use own items/crafts` is enabled, fixing mismatches like the `Soul Cipher` detail view.
- **Smoke-test load order fixed** — `/gam smoketest` no longer trips over nil local helpers during Pricing.lua initialization.
- **Editable-field confirmation fixed** — Transient commit buttons now apply reliably on click instead of losing the edit during focus changes, and the same `OK` confirmation flow now covers the tools-panel editors too.
- **Portuguese `My Professions` filter fixed** — Profession filtering now resolves player professions by stable skill-line IDs instead of localized profession names, so non-English clients no longer fall back to `All`.

### Data
- **Haranir Phial of Finesse reagent corrected** — The generated strategy now uses `Mana Lily` instead of `Argentleaf`.
- **Scoped workbook refresh applied** — Updated the approved Blacksmithing and Engineering-generated blocks from the latest workbook, including the revised ingot expectations and current Engineering recycling data.

### UI / Localization
- **Contextual `OK` buttons added** — Editable quantity/stat fields now show an `OK` button only while the value is actively being changed.
- **Short-label locale pass added** — Constrained UI labels now use shared short wording across all locales to reduce clipping and overflow in buttons, headers, and compact panels.
- **Footer readability improved** — The bottom support/version bar now uses larger text, and clicking it opens a copy-ready Discord invite popup again.

## [1.7.20] — 2026-04-02

### Bug Fixes
- **Crushing analyzer craft-qty sync fixed** — The analyzer now follows the current craft quantity from the detail pane instead of recalculating from the default baseline, so its prices, profit, ROI, and break-even stay aligned with the selected strategy view.
- **Crushing analyzer resizable layout fixed** — The analyzer window can now be resized safely, with columns expanding to show larger values without clipping.

## [1.7.19] — 2026-04-02

### UX / Workflow
- **Raw-chain VI display restored** — When `Use own items/crafts` is enabled, detail views, shopping lists, and selected-strategy scans now expand through raw herbs, ore + flux, and linen + thread again instead of stopping at intermediate pigments, ingots, and bolts.
- **Movable Crushing analyzer** — `Crushing` now opens a separate movable analyzer window that compares each eligible gem’s price, profit, ROI, and break-even while highlighting the current auto-picked gem.
- **`/gam edit` added** — User-created strategies can now be opened directly in edit mode through the slash command, with a dropdown picker that loads existing custom strats into the creator form.

### Bug Fixes
- **Spreadsheet parity preserved while restoring VI** — Pricing math still uses the workbook-aligned direct reagent model; only the user-facing display and shopping chain were changed.
- **Inscription VI batch-planning fixed** — Herb shopping for inks, Soul Cipher, and missives now rounds through real craft and milling batches, preventing underbuy regressions and correctly merging shared intermediate chains.

## [1.7.18] — 2026-04-01

### Bug Fixes / Parity
- **Workbook parity completed across shipped sheet-backed professions** — Alchemy, Blacksmithing, Enchanting, Engineering, Inscription, Jewelcrafting, Leatherworking, and Tailoring now match the live spreadsheet baseline aside from the intentional Dazzling ranked-ID runtime exception.
- **Rank-path and baseline repairs** — Fixed mis-scaled craft/start amounts in Blacksmithing and Alchemy, restored correct ranked output/reagent handling for Enchanting oils and shatters, and locked Engineering recycling to direct sheet prices even when vertical integration is enabled.
- **Vendor baseline alignment** — Added vendor-priced reagent handling for `Silverleaf Thread` and `Luminant Flux` using the spreadsheet’s lowest-cost baseline assumptions.

## [1.7.17] — 2026-04-01

### Data
- Regenerated from live Google Sheet (2026-04-01 export) — Songwater ingredient quantities, Crystalline Glass item ID, Enchanting shatter outputs, and Engineering baselines updated.

### Bug Fixes / Parity
- **Spreadsheet-parity rollback for formula math** — formula profiles now use sheet-authoritative fixed `sheetMCm`/`sheetRs` multipliers instead of mutable node-derived values, bringing runtime math to 1:1 parity with the live sheet at default stat inputs.
- **`insc_ink` baseline corrected** — Multi updated from 25.9 % → 29.7 % to match live sheet (Inscription!A18).
- **`leatherworking` baseline corrected** — Multi updated from 28.2 % → 32.0 % to match live sheet (Leatherworking!A18).
- **Engineering profiles split** — `engineering` replaced by `engineering_recycling` (no multi, 36 % Res, sheetRs=0.435) and `engineering_craft` (31.1 % Multi, 20.4 % Res, sheetMCm=2.5, sheetRs=0.435); strategies reassigned by source-block group.
- **CraftSim node sync temporarily disabled** — node influence is mathematically inert; node SavedVariables are preserved for future re-enablement.
- **Parity smoke checks added** — `/gam smoketest` now verifies formula profiles against live-sheet expected quantities for Engineering recycling (C11=3557.031), craft (C56=1950.596), and O37 (975.298), plus asserts insc_ink/LW baseline values.

## [1.7.16] — 2026-03-31

### Bug Fixes
- **Crushing rank-aware cheapest gem selection** — Flexible `cheapestOf` gem pools now resolve each option through the active rank policy before comparing prices, so R2 crushing picks the cheapest R2 gem instead of undercutting itself with an R1 listing.

## [1.7.15] — 2026-03-30

### Bug Fixes
- **Dynamic Crushing inputs restored** — Flexible `cheapestOf` reagent pools now survive importer normalization, so Jewelcrafting `Crushing` is priced against the cheapest eligible gem at runtime instead of falling back to a fixed baseline item.
- **Crushing scan coverage fixed** — Bulk AH scans now queue every gem in a flexible reagent pool, so `Crushing` can actually compare the full eligible set during normal `Scan Strat` and `Scan All` flows.
- **Crushing detail note** — Strategy detail now shows which flexible-pool reagent was selected as the current cheapest input, making the live pricing choice visible without changing profit math.

### Tooling
- Added a checked-in strategy coverage audit report and generator so workbook-backed versus manual shipped content can be reviewed directly from the repo.

## [1.7.14] — 2026-03-30

### Bug Fixes
- **Dazzling Thorium prospecting corrected** — The generator now reads the `3-30-26.xlsx` Dazzling layout correctly and pins every Dazzling output to its explicit Rank 1 item ID from the ranked materials table, so Crystalline Glass and the other Dazzling outputs stay Q1-only as intended.
- **Spreadsheet regen baseline fixed** — Regenerated `workbookExpectedQty` values now use the workbook's current craft baseline instead of the previously generated craft count, so data regen stays aligned when spreadsheet craft counts change and `compare_strats.py` verifies cleanly against the new sheet.
- **Engineering stat scaling restored** — All 12 Engineering strategies now use the shared Engineering formula profile, so `engMulti`, `engRes`, `engMcNode`, and `engRsNode` finally affect ROI consistently for recycling, reagent crafting, and finished Engineering crafts.
- **Engineering defaults normalized** — Engineering now uses one authoritative workbook baseline (`30.467%` Multicraft, `36%` Resourcefulness, `50/50` node bonuses). Generated raw yields are normalized so default output and profit stay aligned with the existing spreadsheet numbers.

### Documentation & Localization
- Updated the user docs to reflect that Engineering now uses shared Multicraft, Resourcefulness, and node-bonus fields.
- Synced missing Settings/AH/theme locale keys across all shipped translation files.
- Cleaned the public repo docs and release metadata for the first plain-source GitHub release.

## [1.7.13] — 2026-03-28

### Bug Fixes
- **JC prospecting ROI corrected** — The generator was storing `baseYieldPerCraft` as `workbook_expected / crafts` for all four JC prospecting strategies (Refulgent Copper Ore, Brilliant Silver Ore, Umbral Tin Ore, Dazzling Thorium is fixed-mode and unaffected). That value already had the formula factor baked in, so the addon was double-applying it and inflating output quantities by ~17%. All three `calcMode = "formula"` prospecting strategies now store the correct raw per-craft yield; ROI at default settings will match the spreadsheet.

## [1.7.12] — 2026-03-28

### Changes
- **Vertical integration simplified** — Replaced the three separate "Mill own herbs / Craft own bolts / Craft own ingots" checkboxes with a single "Use own items/crafts" toggle that enables all derivation paths atomically.
- **Theme switcher removed** — Main window theme is now locked to Classic while theme switching is reworked for a future release.

### Internal
- Locale cleanup: removed 14 obsolete keys, added new vertical integration and stat-label keys; all 10 translation files synced.
- Code comment cleanup across Core.lua, Pricing.lua, Settings.lua, and MainWindowV2.lua.
- Documentation updated to reflect current file structure and strategy count (62).

## [1.7.11] — 2026-03-24

### Bug Fixes
- **Missive R2 support** — Added `R2` output item IDs for all six manual inscription missives so they now follow the global rank-policy setting instead of being `R1`-only.
- **Missive naming cleanup** — Removed the `R1` suffix from manual missive strategy IDs and names now that those strategies support both `R1` and `R2`.
- **Manual data dedupe** — Fixed generated-data regeneration so existing `Manual` entries are skipped before the manual JSON section is appended, removing the duplicate missive blocks that had accumulated in `StratsGenerated.lua`.

## [1.7.10] — 2026-03-24

### Bug Fixes
- **Rank-aware shopping counts** — Reagent inventory counting now respects the active resolved rank, so owning `R1` inks or mats no longer suppresses `R2` shopping lists and vice versa.
- **Tailoring craft-own-bolts yield** — Added the tailoring formula profile to crafted bolt intermediates so vertical integration no longer overstates raw cloth/thread requirements.
- **Inscription workbook references** — Corrected the stored workbook expected-output values for `Sienna Ink`, `Munsell Ink`, and `Codified Azeroot` so generated data lines up with the current sheet again.

### Tooling
- **Workbook parser expected-row filter** — Updated the spreadsheet parser/compare tools to skip `Expected crafted value per` rows when scanning expected outputs, preventing false mismatches on inscription blocks.

## [1.7.9] — 2026-03-24

### Bug Fixes
- **Spreadsheet-aligned summary math** — `Total Cost`, `Profit`, `ROI`, and `Break-Even` now use the full required material cost basis so strategy economics match the workbook model even when you already own some mats.
- **Buy Now Cost display** — Added a separate inventory-aware `Buy Now Cost` line in the detail views so the addon still shows out-of-pocket spend without inflating profitability.
- **Detail panel cleanup** — Reorganized the inline detail summary so cost-related lines are grouped together and removed the redundant fill-quantity notice from the detail header.
- **Tooltip clarity** — Reagent and output item hover tooltips now explain unit price, required quantity, buy-now cost, and craft-level net revenue more clearly.

### Localization
- Added missing translations for the new `Buy Now Cost` label/tooltips and the row-level tooltip strings in the shipped locale files.
- Updated translated tooltip copy so `Profit` now describes the new full-cost calculation instead of the old buy-only behavior.

## [1.7.8] — 2026-03-23

### Bug Fixes
- **Blacksmithing Q2 reagent corrections** — Fixed the generated blacksmithing Q2 data to match the workbook for `Refulgent Copper Ingot`, `Gloaming Alloy`, and `Sterling Alloy`. The Q2 ore and flux splits now use the intended `3/2` ingot recipe and `3/3/4/3` alloy recipe structure.
- **Craft own ingots blacksmithing alignment** — `Craft own ingots` now expands blacksmithing alloy inputs using the corrected spreadsheet-aligned material quantities, so R2 blacksmithing paths no longer overcount ore, flux, or ingots.
- **Workbook parser off-by-one** — Fixed the blacksmithing spreadsheet parser so Q2 imports no longer skip the first reagent row when reading workbook blocks. This prevented stale higher-rank reagent quantities from leaking into generated addon data.

### Scope
- This patch intentionally does **not** refresh the newer inscription workbook changes. Remaining spreadsheet drift outside blacksmithing is out of scope for `1.7.8`.

## [1.7.7] — 2026-03-23

### Bug Fixes
- **Vertical integration consistency** — Unified rank-policy recipe resolution for pricing-adjacent helpers so `Scan Strat`, CraftSim push, floating detail scan-all, and ARP export now use the same active strategy view as the UI.
- **Craft own ingots backend path** — Fixed the blacksmithing-specific ingot derivation path so `Sterling Alloy` and `Gloaming Alloy` can correctly expand `Refulgent Copper Ingot` into ore and flux using the same expected-yield math as the spreadsheet.
- **Nested crafted reagent pricing** — `GetPreferredIngredientPrice()` now forwards quantity into nested craft-derived pricing so ingots, bolts, and herb-milling chains use the correct fill-sensitive material cost.
- **Expanded reagent UI rows** — Both strategy detail panels now render from metric rows instead of the base recipe rows, so vertical integration shows raw mats instead of leaving ingots, bolts, or pigments on screen.
- **Strategy switching and row editing** — Removed focus-loss refresh paths that could swallow row clicks and prevent switching strategies while an edit box was active.
- **Favorite toggle UX** — Favorites can now be toggled directly from the row star gutter, including removing an existing favorite after the list reorders.
- **Settings apply/cancel behavior** — Native Blizzard settings now refresh visible strategy views when cost-source toggles change, while cancel/close no longer silently saves edits.
- **Main list refresh performance** — The main strategy list now caches metrics per rebuild instead of recalculating every row repeatedly during sorting and redraw.
- **Best strategy scoring** — The hero card now uses the same strategy score selection as the pricing module, avoiding inconsistent “best” picks.
- **ARP export rank coverage** — Export now includes rank-variant-only item IDs so higher-rank columns are not incorrectly emitted as zero.

### Verification
- `luac -p` passes across addon Lua files.
- Spreadsheet comparisons against `3-21-26.xlsx` remained aligned after the fixes.

## [1.7.6] — 2026-03-23

### Bug Fixes
- **Frame layering** — Main window strata lowered from HIGH to MEDIUM so bag addons (e.g. Baganator) render above GAM by default; clicking GAM still raises it to the top of MEDIUM via SetToplevel.
- **AH toggle button** — Button now always shows when the AH is open regardless of auto-open setting; locale strings extracted to Locale.lua.

---

## [1.7.5] — 2026-03-23

### New Features
- **AH toggle button** — When "Auto-open with AH" is unchecked, a small Gold Advisor button appears in the top-right of the Auction House frame. Click to show/hide the GAM window without needing the minimap button.
- **Natural frame layering** — Main window now uses `HIGH` strata instead of `DIALOG`, so bags, inventory, and the AH frame can come to the front when clicked. Clicking the GAM frame brings it back to the top.

### Changes
- **Settings rank policy** — Replaced the UIDropDownMenu rank dropdown (which clipped outside the settings panel in Midnight 12.x) with a cycle button. Click to toggle between Lowest and Highest; setting is saved and restored correctly on re-open.
- **Disabled Create Custom Strategy / Import Strategy** — Buttons removed from the Settings Actions panel until the feature is fully ready.
- **Export button hidden in strategy detail** — The per-strategy export button is now always hidden.

---

## [1.7.0] — 2026-03-23

### New Features
- **Flask of the Magisters (Alchemy)** — Added missing Alchemy flask strategy: 1 Nocturnal Lotus, 6 Mana Lily, 2 Mote of Pure Void, 2 Sunglass Vial, 8 Sanguithorn per craft; same formula profile and expected output (~3036 flasks per 1000 crafts) as all other alchemy flask strats.

---

## [1.6.1] — 2026-03-23

### Bug Fixes
- **Vertical integration ore qty mismatch (ingots)** — `CRAFTED_REAGENT_MAP` stored the base yield for Refulgent Copper Ingot (0.2 ingots/ore) without applying crafting stats, so `ExpandReagentThroughChain` showed ~1503 ore for 300 ingots while the direct strategy view correctly showed ~1050. Added `GetEffectiveCraftYield()` which applies the same MC/RS formula as `CalculateStratMetrics`, and tagged both ingot entries with `formulaProfile = "blacksmithing"` so chain expansion and cost derivation now use the stat-adjusted yield.

---

## [1.6.0] — 2026-03-21

### New Features
- **Thalassian Missive inscription strats** — Added full set of Thalassian Missive strategies with Herb Milling VI support.

### Data
- Regenerated from 3-21-26 spreadsheet — Engineering reorganized (10 recycling strategies removed, 5 retained with updated sourceBlocks, 7 crafting strategies updated); Inscription Codified Azeroot strategy added; Inscription milling quantities updated.

### Bug Fixes
- **Vertical integration bolt quantity overcounted** — `CRAFTED_REAGENT_MAP` stored `yield = 0.942977` for Bright Linen Bolt Q1/Q2, but the base recipe yield is 1.0 bolt per linen craft. This caused ~12.5% too many linens to be shown in the shopping list and overstated derived bolt cost by the same factor. Fixed to `yield = 1.000000`.
- **Panel snap button jump** — Collapse toggle buttons jumped between vertically centered (after click) and 12px from top (after `OnShow`) due to mismatched anchors. Unified all code paths to `LEFT`/`RIGHT` at Y=0.
- **Dazzling Thorium always priced as rank 1** — `qualityPolicy = "force_q1_inputs"` is now enforced in `CalculateStratMetrics`. Dazzling Thorium Prospecting tagged with this policy so it always prices as Q1 regardless of the user's R1/R2 setting.

---

## [1.5.5] — 2026-03-21

### Bug Fixes
- **Vertical integration bolt quantity overcounted** — `CRAFTED_REAGENT_MAP` stored `yield = 0.942977` for Bright Linen Bolt Q1/Q2, but the base recipe yield is 1.0 bolt per linen craft (no stat combination can produce a yield below 1.0). This caused `ExpandReagentThroughChain` to show ~12.5% too many linens (2121 instead of 2000 for 1000 Imbued Bright Linen Bolt crafts) and `GetCraftDerivedReagentCost` to overstate derived bolt cost by the same factor. Fixed to `yield = 1.000000`.

---

## [1.5.4] — 2026-03-21

### Data
- Regenerated from 3-21-26.xlsx — Engineering reorganized (10 recycling strategies removed, 5 retained with updated sourceBlocks, 7 crafting strategies updated); Inscription Codified Azeroot strategy added; Inscription milling quantities updated.

### Bug Fixes
- **Panel snap button jump** — Collapse toggle buttons (`btnCollapseLeft` / `btnCollapseRight`) jumped between vertically centered (after click) and 12px from top (after `OnShow`) because the `OnShow` handler used `TOPLEFT`/`TOPRIGHT` anchors while creation and click used `LEFT`/`RIGHT` at Y=0. Unified all three code paths to `LEFT`/`RIGHT` at Y=0 so buttons stay centered.
- **Dazzling Thorium always priced as rank 1** — `qualityPolicy = "force_q1_inputs"` is now enforced in `CalculateStratMetrics`. Dazzling Thorium Prospecting has been tagged with this policy so it always prices as Q1 regardless of the user's R1/R2 setting. Existing `force_q2_inputs` Blacksmithing strategies also now receive enforcement.

---

## [1.5.3] — 2026-03-21

### Bug Fixes
- **Blank frame (root cause)** — `tickerClip:RegisterForClicks()` was called on a plain `Frame`. `RegisterForClicks` is a `Button`-only method; calling it on a `Frame` throws a runtime error that — because `Build()` runs inside `pcall` — was silently swallowed, aborting `Build()` before the left/center/right panels were ever created. Removed the invalid call; click detection is handled entirely by `OnMouseDown`.
- **Compact button nil call** — `ToggleCompactMode` was defined before `local function RelayoutPanels`, so Lua resolved `RelayoutPanels` as a global (nil), causing `attempt to call a nil value` on every click. Moved definition after `RelayoutPanels`.
- **Compact button not firing** — Added explicit `EnableMouse(true)` and `RegisterForClicks("LeftButtonUp")` on the compact `Button` frame to guarantee click events are delivered.

### New Features
- **Compact mode self-heal** — If `opts.compactMode` was persisted but no strategy is selected on load, compact mode now auto-resets to full layout instead of showing an empty detail shell.
- **Compact button state** — Button now shows `DETAIL` (normal mode) or `FULL` (compact mode). Disabled and dimmed until a strategy is selected; always enabled in compact mode so the user can always exit.
- **Collapse handle improvements** — Left/right panel seam handles are now larger (16×60), vertically centered, styled with a visible backdrop and border, glow on hover, and show a tooltip. They are hidden automatically while compact mode is active. A 10px seam gap was added so handles sit in visible buffer space rather than directly on panel borders.

---

## [1.5.2] — 2026-03-21

### Bug Fixes
- **Blank frame (persistent compact mode)** — `opts.compactMode = true` could be saved by v1.5.0 when the mis-positioned compact button intercepted close-button clicks, locking the layout in compact mode on all subsequent loads. A DATA_VERSION 9 migration now resets `compactMode` to `false` on first load after upgrade.
- **Compact button text garbled** — The button label used `\xNN` hex escape sequences (WoW Lua 5.1 does not guarantee correct behavior for these). Replaced with plain ASCII `<<` / `>>`.

---

## [1.5.1] — 2026-03-21

### Bug Fixes
- **Blank frame on open** — The new `RelayoutPanels` added in v1.5.0 unconditionally called `rightPanel:ClearAllPoints()` and re-anchored it on every call, including the initial `OnShow`. This differed from the original behavior (which never re-anchored rightPanel) and caused WoW's layout engine to blank out the right panel and its children. Fixed with a `wasCompact` flag so ClearAllPoints is only called when actually transitioning from compact mode back to normal. Frame resize logic is also gated the same way.
- **Compact mode button unclickable** — The compact button's `SetPoint` x-offset was `+4` (placing its right edge 4 px inside the close button), so most clicks were intercepted by the close button. Fixed to `-4` so the compact button sits cleanly to the left of the close button with a small gap.

---

## [1.5.0] — 2026-03-21

### New Features
- **AH auto-open toggle** — New setting: "Auto-open with Auction House". When disabled, Gold Advisor will no longer open automatically when you open the Auction House (toggle it manually with `/gam`).
- **Close with AH toggle** — New setting: "Close with Auction House". When enabled, Gold Advisor closes automatically when you close the Auction House.
- **Compact mode button** — A `⊟` button in the top-right of the main window (left of the close button) collapses the window to show only the strategy detail panel at ~450px wide. Click `⊞` to restore the full three-panel layout. State persists across sessions.

---

## [1.4.5] — 2026-03-20

### Bug Fixes
- **Vertical integration ingredient quantities** — When "Craft own ingots" or "Craft own bolts" was ticked, ingredient costs were calculated without considering the actual batch size. `GetCraftDerivedReagentCost` was missing the `qty` parameter, so AH fill prices were computed as if buying 1 craft's worth of ore/fiber at a time rather than the full batch. Now correctly passes batch size so fill-price lookups match actual purchase depth.
- **Dazzling Thorium Prospecting now outputs Q1-only** — Per updated spreadsheet, all 7 output gems are now priced at Q1 (unticked quality) rather than showing an average of Q1/Q2 prices.

### Data
- Regenerated from 3-20-26.xlsx spreadsheet — ingredient quantities updated for Blacksmithing, Alchemy, JC, and other professions.

---

## [1.4.3] — 2026-03-19

### Performance
- **Scan FPS regression fixed** — Second scan (after switching profession filter and re-scanning) was dropping FPS from 100+ to 14fps with ~84% CPU from the addon. Root cause: the sort comparator was calling `CalculateStratMetrics` once per comparison pair (O(n log n) calls), which became expensive after the first scan populated the AH price cache and triggered full order-book simulation per call. Fixed by pre-computing metrics for all strategies exactly once before sorting (O(n)). Additionally, `RebuildList` is no longer called during mid-scan progress updates — the list re-sorts once at scan completion instead.

### Bug Fixes
- **Blank addon title in main window header** — The title bar showed no text because `L["MAIN_TITLE"]` was removed in v1.4.0 during UI cleanup but `MainWindowV2.lua` still referenced it. Fixed to use `L["ADDON_TITLE"]`.

### New Features
- **Quick Buy macro support** — Quick Buy now requires one hardware event (keypress/click) per purchase, satisfying WoW's AH commodity purchase restriction. A hidden 1×1px named button `GAMQuickBuyBtn` is registered on login. Use `/gam quickbuy` to arm, then assign `/click GAMQuickBuyBtn` to a keybind or macro — each press buys the next item in the shopping list. Previously the addon looped purchases automatically without hardware events, which would fail silently in-game.

---

## [1.3.2] — 2026-03-17

### New Features
- **Crafts scaler** — Strategy detail panel now has a "Crafts" editbox on the right side of the Input Items header. Changing the value scales all reagent quantities, output quantities, costs, and revenue proportionally. Value persists per strategy per patch.

### Bug Fixes
- **Detail panel ROI mismatch** — Best Strategy card and detail panel could show different ROI values for the same strategy if bag contents changed between the scan and the click. Fixed by synchronising both calculations to the same moment.

### UI Polish
- Community ticker links updated with real Twitch, Patreon, YouTube, and Discord URLs. Click popup redesigned to show all four as individually copyable rows.

## [1.3.1] — 2026-03-17

### Bug Fixes
- **Quick buy double-purchase** — `/gam quickbuy` was buying double the required quantity and spamming chat. Root cause: `AUCTION_HOUSE_THROTTLED_SYSTEM_READY` fires multiple times per purchase session; each fire called `ConfirmCommoditiesPurchase` while `pendingItemID`/`pendingQty` were still set, triggering duplicate purchases. Fixed with a `confirmSent` guard: the first throttle event confirms and sets the flag; subsequent fires are no-ops until the next item in the list starts.

### New Features
- **Settings: Craft own bolts / Craft own ingots checkboxes** — The Pricing section in Settings now has dedicated checkboxes for bolt and ingot cost source (previously only accessible via the V2 left panel). Both sync bidirectionally: changes made in V2 are reflected when Settings opens; saving Settings updates the V2 checkboxes immediately.
- **V2: Version label** — The addon version is now shown centered below the "Gold Advisor Midnight" title in the V2 header.

### UI Polish
- **V2: Profession dropdown** — Removed the redundant "Profession" label above the dropdown; the dropdown sits directly below the Mine/All toggle without a label, saving vertical space.

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
