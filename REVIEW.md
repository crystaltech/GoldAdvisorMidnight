# Astra10 — validated VI-to-CraftSim queue action

The VI Breakdown window now exposes one explicit **Queue in CraftSim** action. It
uses the existing postorder execution plan, validates every recipe through the
CraftSim API before writing, preserves exact resolved reagent selections, rejects
ambiguous rank pools, and prevents repeated submission of the same plan during a
session. Missing CraftSim support leaves the action unavailable; queueing never
starts crafting. A failed write reports the number of steps already appended.

The shared Comfortable button helper now also tolerates lightweight texture
fixtures that do not implement `SetAllPoints`, while retaining the normal WoW
path. 33/33 offline checks pass, including duplicate-plan and ambiguous-rank
queue regressions. In-game verification remains required against the installed
CraftSim version, especially recipe ownership, profession, gear, concentration,
cooldowns, and the exact CraftSim queue schema.

---

# Astra9 — 50-craft default and workflow design

Default starting crafts is now 50 for profiles without a saved value. Saved global values and per-strategy overrides are preserved. Existing users can run `/gamdev globalstartqty 50`. 32/32 offline checks passed at that stage. GOLDMAKING-UX-PLAN.md still specifies proposed TSM demand, estimate clarity and Quick Buy margin review; the lower-priority VI-to-CraftSim queue action was implemented in Astra10.

# Astra8 — shared window styling and scan shortcuts

The main frame's Comfortable dark background/header and flat text-button styling now extend through WindowManager to secondary windows (standalone strategy detail, VI breakdown, Crushing, cooldowns, Debug Log and exports). Quick Buy applies the same shared treatment. Existing primary-button emphasis, item icons, row colors, quality colors, close buttons and resize grips are preserved. Existing table geometry is retained; this is a styling pass, not a rewrite of every secondary layout.

Unified main scan action: click scans the current filtered list; Ctrl-click scans everything in the current patch; Alt-click scans favorites in the current patch regardless of the profession filter; Shift-click scans the selected strategy. In the standalone detail window, Shift-click targets that window's strategy. Clicking during an active scan stops it without restarting. No selection/no matches produces a message instead of silently scanning a different scope. Combined modifier precedence: Ctrl, Alt, Shift. The tooltip documents all shortcuts; the main and inline-detail button labels reflect held modifiers.

Removed the redundant Scan Selected entry from More Tools. Main detail and standalone detail retain one scan action so scanning is available while the planner toolbar is hidden. Standalone per-item scan controls remain available for targeted price updates.

32/32 offline checks pass; new tests exercise actual scan dispatch, hidden favorites, standalone override, missing selection, combined keys and stopping; secondary-theme tests ensure icons and existing primary buttons are preserved. All runtime Lua syntax checked. Needs in-game visual verification and AH checks for all four shortcut scopes. Install the GoldAdvisorMidnightDev folder and reload. All earlier fixes are included.

---

# Astra7 — live audit confirmation and runtime fixes

The latest user report covers all 283 retained strategies across nine professions, with zero MISMATCH and zero UNAVAILABLE. This confirms the prior Tailoring dust rank, contract crafting ID, quality-icon normalization, and Blacksmithing variant corrections within the schematic auditor's scope. Unlearned entries have no reported schematic mismatches. Random processing distributions, complete output-rank mapping, and crafting-stat accuracy remain outside this result.

Fixed QuickBuy.lua initialization: the newly created window is hidden before installing its OnHide callback. Previously its first hide reset the controller and refreshed UI controls before refs.progress existed, aborting construction. Normal user close still resets the controller, with the existing pending-purchase reconciliation preserved.

Fixed CraftingStats.lua protected action: OpenRecipe runs only synchronously in the initiating Refresh Recipe click. Delayed retries only inspect/capture the selected recipe; they never call OpenRecipe. If Blizzard does not switch to the requested recipe, the existing bounded failure callback runs; open the recipe manually and click Refresh Recipe again. The regression verifies timer retries perform no recipe-selection calls.

The separate CraftSim ReagentData.lua ItemCountDB nil-call stack is not patched: CraftSim source is not part of this build, and the supplied stack does not identify GAM as the cause.

Validation: 30/30 offline checks passed, including a new actual Quick Buy builder initialization/close test and updated asynchronous capture tests. Runtime Lua syntax passes. In-game confirmation still needed: login without Quick Buy error; open/close Quick Buy; Refresh Recipe without ADDON_ACTION_BLOCKED.

---

# Astra6 — complete profession report pass

User reports cover 283 strategies across all nine professions: Tailoring 10, Engineering 26, Cooking 42, Jewelcrafting 48, Inscription 31, Enchanting 77, Alchemy 30, Blacksmithing 8, Leatherworking 11.

Correction to the initial reading of Blacksmithing: its five apparently missing reagent-rank entries already exist in rankVariants. No rank IDs or quantities were added to the three Blacksmithing strategies. The audit now recognizes alternate IDs across saved variants, sums split reagent quantities within each mix, and separately checks each variant's totals against the schematic. This prevents false missing-rank reports without weakening amount checks. Existing fixed material mixes are preserved.

Enchanting, Alchemy and Leatherworking reported zero schematic mismatches. UNLEARNED is not a missing schematic or data failure, but stats marked fallback are not independently validated by these recipe checks. In particular Multicraft support and bonus formulas remain a separate verification task.

Cumulative corrections: missing Tailoring dust rank (astra4); wrong Zul'jarra contract crafting spell ID (astra5); quality-icon name false positives (astra5); Blacksmithing variant false positives (astra6). Prior corrected recipes still need post-install live confirmation. Live schematic checking does not certify probabilistic milling/prospecting output distributions or complete output-rank mappings.

Validation: 29/29 offline suites/checks passed. Added regression coverage for a valid split-rank mix and an invalid variant quantity total. Runtime Lua syntax checked. Install GoldAdvisorMidnightDev and rerun Blacksmithing, Tailoring, Jewelcrafting and Inscription audits; report any remaining findings.

---

# Astra5 — Cooking, Jewelcrafting and Inscription reports

Cooking: 42 checked, no reported mismatches (2 unlearned). Jewelcrafting: two recipe-name false positives caused by quality atlas markup; the auditor now removes atlas/texture/color markup before comparing names, while still detecting real name differences. No Jewelcrafting recipe quantities or IDs changed. Random salvage yields remain outside the live schematic check.

Inscription: Contract: Zul'jarra's Forces now uses crafting spell 1303151 instead of 1303144. Source: https://www.wowhead.com/spell=1303151/contract-zuljarras-forces (retrieved this pass). This source lists the existing four ingredients and amounts. The user report on the old ID showed no matching ingredients and a yield of ten; do not apply that yield to the crafting recipe. Base yield one and item/reagent IDs are retained pending a fresh live audit on the corrected ID. The existing contract specialization mapping follows the corrected recipe ID; node values were not changed or independently reverified.

29/29 offline checks pass. Regression tests cover icon-decorated recipe names and the corrected contract identity. All 283 retained strategies pass cross-file checks. Rerun Jewelcrafting and Inscription audits in-game; the corrected contract schematic still needs live confirmation. Stats-source/fallback labels do not certify stat accuracy; the two unlearned Cooking recipes using workbook defaults remain unverified for crafting-stat support.

This includes astra4's Tailoring rank correction and all prior layout changes.

---

# Astra4

Fixed the live-reported missing Eversinging Dust rank in Bright Linen Spellthread; see STRATEGY-AUDIT.md.

# Astra3

See STRATEGY-AUDIT.md for the current strategy audit, output-display correction and live verification command.

# Astra2 — in-game layout follow-up

Version: 2.0.10-dev.astra2. Replace the GoldAdvisorMidnightDev folder, then reload WoW.

- Aligned crafting-option labels/fields, reduced toolbar height, and moved the stray Scan Selected button into its actual tools-menu parent.
- Left-aligned the Strategy column heading with its rows.
- Details-only mode now has a resize grip, 440 x 360 minimum, and separately remembered dimensions. Full-view geometry remains separate. Its default height is 620. Secondary header text hides in Details mode to avoid overlapping Full.
- Detail actions share one fixed footer row. Starting crafts sits alongside Materials; Info disclosure keeps its scrolling body. Refresh Recipe remains visible but disabled when no live recipe can be opened.
- Crushing layout no longer exits before anchoring headings when scaled dimensions are fractional. It also reflows on show; column widths/positions fit its viewport. Minimum width is 560.
- Quick Buy opens at 500 x 230; VI opens at 920 x 300. VI reports unavailable cost when displayed entries have missing prices.
- Debug Log and ARP Export have resize grips; debug buttons reflow with window width. ARP uses the dark background shared by the other windows.

Validation: 28/28 offline checks passed, including a new actual Crushing-layout regression for fractional dimensions and the full-view geometry reentry regression updated to exercise SetSize. All runtime Lua parses as Lua 5.1.

In-game checks still required: toolbar at minimum/full width and your UI scale; Details resize with Info open/closed and return to Full; Crushing column visibility; small Debug/ARP windows; Quick Buy status wrapping. No live WoW renderer is available here. This pass changes the main window's Details-only mode; the separate standalone strategy window retains its existing resize behavior.

The earlier review below describes the preceding astra1 changes, retained in this build.

---

# Gold Advisor Midnight Dev — Astra review build

Build: **2.0.10-dev.astra1**, 2026-09-06. Based on the uploaded GAM.zip working tree, not an older GitHub checkout. The uploaded branch was `feature/main-frame-redesign`; its uncommitted Dev conversion and Comfortable work have been retained.

## Install and identify this build

1. Exit WoW. Replace the existing `Interface/AddOns/GoldAdvisorMidnightDev` folder with the folder in this archive. Keep the folder name exactly `GoldAdvisorMidnightDev`.
2. Keep the released `GoldAdvisorMidnight` folder untouched. Enable **Gold Advisor Midnight Dev** and open it with `/gamdev`.
3. Confirm **2.0.10-dev.astra1** in the Dev window footer. If you still see the tall left sidebar and Crafting Estimates hero, check the installed folder/version: this build selects Comfortable directly from its Dev identity and has no user-facing theme switcher.
4. This is a source snapshot, not a replacement Git repository. Copy changed source/tests into your existing branch; preserve its Git history. `review-changes.patch` records changes relative to the uploaded ZIP.

## Confirmed issues fixed

| Area | Finding and correction |
|---|---|
| Quick Buy | Closing/resetting during `purchasing` discarded the submitted transaction, so its success event could no longer remove it from the list. Retain its identity until success/failure; block Skip and another purchase while it is pending. Closing an unsubmitted quote still cancels it. |
| Quick Buy label | Dev said **Get Quote**, although the existing controller automatically confirms quotes within its 5% guard. Restored **Buy Next** so the label accurately describes the action. Existing price approval behavior remains. |
| VI shopping | An explicitly empty execution shopping list fell back to economic recipe inputs. Empty now means nothing to buy; fallback is only for missing legacy fields. |
| Formula edge case | Fixed-craft Resourcefulness bounded savings after multiplying by proc chance. An oversized manual bonus could therefore save more than all reagents on a proc. Cap the per-proc saving before probability, consistent with the exhaust-materials model. Normal golden calculations are unchanged. |
| Detail focus | `SetWidth` could synchronously trigger relayout before compact mode was marked active, overwriting remembered full-view width. Set mode before resizing; retain full-view geometry. |
| Saved geometry | Invalid saved sizes/anchors could error during window creation. Validate finite dimensions/offsets and allowed anchor names, then use defaults and size bounds. |
| Detail space | Info previously hid text while reserving its original space. Metrics and tables now reflow; a single outer content viewport scrolls long content while actions stay visible. Table names use extra width. |
| Detail rows | Fixed inline pools of 12 reagent/10 output rows could omit longer plans. Grow and reuse row pools from the projection's actual row count. |
| Detail state | Same-strategy refresh no longer forcibly resets material/output scroll; a changed selection resets its content view. Scan remains directly available in inline detail as well as focus mode. |
| UI scale | An array containing unopened/nil frames stopped `ipairs`, skipping later windows. Iterate frame names and include Quick Buy, cooldowns, VI, crushing and export. Quick Buy/cooldowns also apply saved scale when first created. |
| Settings fallback | Explicit **Apply & Close** commits; Cancel/X/hide discards uncommitted drafts. Native commit callbacks remain. |
| Formatting | Four quantity formatters used an unsupported optional-capture Lua pattern; thousands separators never matched. Corrected integer/fractional formatting. |
| Side-by-side controls | Dev and release AH mini-buttons occupied the same location. Offset the Dev control. |
| Resize cost | Comfortable resize events reran selected-strategy pricing/VI calculations. Geometry-only resize now reflows the current projection instead. No new result-cache invalidation policy was introduced. |

## UI work retained and completed

The uploaded source already contained substantial new layout work beyond the earlier screenshot. This build retains its horizontal filters/actions, expandable Crafting options, 28-pixel strategy rows, full-width list when unselected, detail focus toggle, resizable main window, restrained surfaces, and secondary-window styling.

Refresh Recipe and click-to-open Info are available in the inline/focus detail and standalone detail. Standalone Info reads the current canonical stat, gear and node diagnostics and does not trigger recalculation. Quick Buy keeps Skip and X, without Stop; its existing confirmed-completion callback closes it after the final successful purchase. Cooldown tracking retains its own per-recipe Stop action.

The standalone detail retains its richer existing tables, per-item actions and footer; this pass does not replace it with a new two-column implementation. Its new Info surface is a scrollable disclosure. Exact pixel appearance must be reviewed in WoW.

## Review and verification scope

- All 76 runtime Lua files compile with Lua 5.1; the TOC includes each runtime source exactly once.
- **24 Lua test suites pass**, including new actual-builder layout, geometry/reentrancy, and scale tests. The 21 supplied suites passed before changes.
- Existing regression coverage was rerun for the commodity catalog/importer, recipe schematic audit classifier, price contract/facade and formula goldens, inventory economics, VI derivation and execution order, optimizer, node display/capture/resolution, migrations, state, AH event handling, CraftSim, cooldowns, vendor prices and Dev data isolation.
- **Three Python checks pass:** TOC/runtime inventory, localization references, and transient edit commit behavior. The locale checker checks keyed translations; it does not certify translation of every literal UI phrase.
- Bundled active catalog checks still report **283 strategies**. The existing Blacksmithing node fix remains; rating nodes are not converted into proc percentages. No item/recipe/node IDs were guessed or renumbered.
- `review-test-results.txt` records individual results. `tests/` includes the new regression checks and all supplied tests. `tests/run_offline.py` can run the suite with Python and `lupa`; each Lua suite can also run using a Lua 5.1 interpreter from the addon directory.

This is an offline source review and correction pass, not proof that every current game ID or formula coefficient matches the live client. Bundled data references build `12.1.0.69587`; it was not replaced with newly scraped catalogs. Existing tests establish internal consistency and known cases, not exhaustive live coverage. No in-game rendering, live purchases, recipe captures or performance profiling were available. No release, push or production SavedVariables migration was performed.

## In-game checks needed

- Verify the new version and horizontal layout. Resize large/small, change UI scale, enter Details, return Full, reload, and confirm full-view position/size. Minimum full-view size remains 1000 x 560 logical pixels; use UI scale to fit a smaller display.
- Select a recipe with several reagents and a long name. Toggle Info, scroll, edit starting crafts, refresh prices, and refresh recipe stats. Check that controls remain reachable and refreshed stats belong to the selected recipe/crafter.
- Open Blacksmithing and the other crafting professions; verify node names/ranks, captured/default/manual states, and compare representative estimates against current recipe data. Report any live discrepancy with recipe ID, ranks, captured stats and quantities.
- Exercise VI with owned intermediates, no purchases required, shared dependencies, missing prices and cooldown-limited producers. Compare actual ingredient requirements and craft order with the displayed plan.
- Quick Buy: normal success, above-guard approval, unavailable quantity, skip, close during quote, close during submitted purchase, then reopen. Confirm final success removes the item exactly once and closes the window. A submitted AH transaction cannot be undone by closing its UI.
- Both addons have isolated GAM data/frame names, but share Blizzard AH and CraftSim/Auctionator services. Compare their interfaces side by side; run scans/purchases from one addon at a time. Namespace isolation does not create independent AH transaction channels.
- Open secondary windows before and after changing scale. Check standalone Settings Apply/Cancel and verify the production addon still has its original settings.

## Next review input

Provide the Dev footer version, a screenshot, Lua error text/stack if present, and the affected strategy/recipe ID. For formula differences include rank policy, starting crafts, gear, captured stats, node overrides, VI state and displayed material prices. Continue from this snapshot rather than restarting from an older brief.
