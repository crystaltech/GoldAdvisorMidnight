# Current Dev implementation contract

This file supersedes the earlier theme-switching handoff. See REVIEW.md for implemented fixes, remaining live validation, and test results.

- Build only **Gold Advisor Midnight Dev** with the Comfortable appearance. No style dropdown, no restoration of deleted `v2Theme`, and no requirement to maintain selectable Classic/Soft layouts in this Dev addon. Preserve the production addon alongside it.
- Use space for readable rows and useful data. Main controls run horizontally, less-frequent Crafting options collapse to a summary, and selecting a strategy opens inline detail. Do not spawn a standalone window on selection.
- **Details / Full** toggles focus mode. Preserve the full-view position/dimensions and selection; never overwrite full geometry from focus mode. Main resize and UI scale are separate controls.
- Keep **Refresh Recipe**, which updates verified recipe stats/bonuses; keep adjacent **Info**, which only displays existing diagnostics. Apply this to main detail/focus and standalone detail. Preserve all existing calculations, item interactions and recipe actions except documented bug fixes.
- Quick Buy has no Stop button. Closing cancels unsubmitted work; a submitted purchase must still be reconciled. Auto-close only on confirmed final success. Preserve existing purchase/price guard behavior, and label its starting action **Buy Next** because it can submit a purchase.
- Standalone Settings uses explicit Apply & Close / Cancel. Hiding does not commit drafts. Preserve native Settings callbacks.
- Review correctness before speculative optimization. Test IDs against bundled sources and live captures when available. Do not guess current game IDs or change rating nodes into percentages. Preserve the Blacksmithing display fix.
- Follow Laws of UX grouping/proximity, progressive disclosure and familiar controls; use the software-engineering principles of focused changes, shared calculation contracts, and avoiding speculative features.
- Keep further work staged and report briefly. Test actual WoW rendering and current recipe data before release.


Astra2 implementation update: see REVIEW.md for the screenshot-driven layout corrections and remaining in-game checks. Dev remains Comfortable-only; no theme switcher.


# Astra8 — shared window styling and scan shortcuts

The main frame's Comfortable dark background/header and flat text-button styling now extend through WindowManager to secondary windows (standalone strategy detail, VI breakdown, Crushing, cooldowns, Debug Log and exports). Quick Buy applies the same shared treatment. Existing primary-button emphasis, item icons, row colors, quality colors, close buttons and resize grips are preserved. Existing table geometry is retained; this is a styling pass, not a rewrite of every secondary layout.

Unified main scan action: click scans the current filtered list; Ctrl-click scans everything in the current patch; Alt-click scans favorites in the current patch regardless of the profession filter; Shift-click scans the selected strategy. In the standalone detail window, Shift-click targets that window's strategy. Clicking during an active scan stops it without restarting. No selection/no matches produces a message instead of silently scanning a different scope. Combined modifier precedence: Ctrl, Alt, Shift. The tooltip documents all shortcuts; the main and inline-detail button labels reflect held modifiers.

Removed the redundant Scan Selected entry from More Tools. Main detail and standalone detail retain one scan action so scanning is available while the planner toolbar is hidden. Standalone per-item scan controls remain available for targeted price updates.

32/32 offline checks pass; new tests exercise actual scan dispatch, hidden favorites, standalone override, missing selection, combined keys and stopping; secondary-theme tests ensure icons and existing primary buttons are preserved. All runtime Lua syntax checked. Needs in-game visual verification and AH checks for all four shortcut scopes. Install the GoldAdvisorMidnightDev folder and reload. All earlier fixes are included.

