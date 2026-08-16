# Recipe catalog audit

Updated: 2026-08-15

Pinned data build: `12.1.0.69299`
Runtime scope: 282 commodity strategies and 477 eligible output item IDs

## Current result

- 606 raw definitions were reviewed.
- 282 commodity strategies are retained across nine professions.
- 324 definitions are excluded, including 25 explicit disabled entries.
- Every retained strategy has a canonical recipe ID and name.
- The checked-in offline audit reports zero retained recipe-identity issues.
- Nine reviewed Retail 12.1 additions are isolated in
  `Data/Strategies/Patch12_1.lua`; their compact facts live in
  `Data/ProfessionCraftsPatch12_1.lua`.

The earlier live sweep corrected Haranir Phial of Finesse to Azeroot x3 and
Mana Lily x6, corrected Mote of Primal Energy to x1 for affected missives, and
classified salvage/processing schematics whose single Blizzard result item
does not describe their probabilistic output distribution. Generic Milling,
Prospecting, Crushing, Shattering, and Recycling views may intentionally share
a spell identity.

## Repeat the deterministic audit

Run from the addon directory:

```text
lua tools/audit_recipe_catalog.lua
python tools/audit_wago_recipe_data.py
lua tests/run.lua
```

Detailed output is written to
`output/spreadsheet/recipe_catalog_audit.csv`; the concise result is written to
`output/spreadsheet/recipe_catalog_audit_summary.md`.

`RecipeAudit.lua` is a repository-only live-audit module loaded explicitly by
`tests/recipe_audit.lua`. It is deliberately absent from the TOC and release
zip. The old recipe-audit and dump slash commands were removed from the public
addon once their catalog corrections and regression coverage were committed.

## Live-client boundary

DB2 data cannot fully describe modified reagent slots, salvage distributions,
learned state, or every client-visible base output. Release acceptance therefore
checks representative learned recipes through the normal planner workflow:

1. Select the strategy and use `Refresh Recipe`.
2. Confirm Blizzard opens the exact recipe and the fixed reagents agree.
3. Compare visible Multicraft/Resourcefulness with Strategy Detail.
4. Confirm the displayed recipe bonuses are recipe-scoped.
5. For VI recipes, confirm producers use their own exact snapshots and remain
   in the root profession.
6. Use `/gam log` to collect a support report if a mismatch appears.

Learned-state and exact-stat coverage are intentionally character dependent.
An unlearned recipe is not a catalog failure. Saved snapshots from another
character are acceptable only when the recipe ID is exact and that crafter is
identified in Strategy Detail.

## Known verified boundaries

- Jewelcrafting root crafts and Crushing producers resolve independent node
  sets even when they share a profession.
- Engineering mass crafts retain recipe-local Multicraft and Resourcefulness
  modifiers.
- Tailoring VI resolves root and bolt-producer stats separately.
- Producer selection is restricted to the root profession, preventing a craft
  chain from silently crossing professions.
- Dazzling Thorium Prospecting retains ranked output IDs for runtime quality
  resolution.

The source URLs and exact 12.1 additions are recorded in
`PATCH_12_1_DATA_AUDIT.md`.
