# Architecture and release boundaries

Gold Advisor Midnight 2.0 is a mass-crafting planner. Its release boundary is
the file order in `GoldAdvisorMidnight.toc`; tests, audit modules, generated
reports, and packaging tools are repository assets and are not loaded in game.

The maintenance rules below apply the practical guidance collected at
<https://lawsofsoftwareengineering.com/>: keep the shipped behavior small
(KISS/YAGNI), keep one owner for each fact (DRY), improve touched code (Boy
Scout Rule), protect behavior with layered tests (Testing Pyramid), and avoid
surprising compatibility breaks (Least Astonishment and Hyrum's Law).

## Runtime flow

1. `Core`, `State`, and `Settings` establish the event, persistence, and option
   boundaries.
2. `CommodityCatalog`, `StrategyModel`, and `Importer` turn generated data into
   canonical runtime strategies.
3. `CraftingStatsV2` captures exact recipe/crafter stats and owns formula
   profiles. `CraftingStatsDiagnostics` keeps compatibility audit/report APIs
   separate without owning capture state.
4. `AHScan` owns live market observations. `PricingContract` validates a
   request, `PricingV2Engine` calculates it, and `PricingFacade` is the only
   production entry point used by UI consumers.
5. Pure UI models project calculation results. Window modules render those
   projections and delegate purchase, cooldown, VI-plan, and CraftSim actions
   to their focused services.

## Ownership rules

- Generated catalog facts live under `Data/`; change their source or generator
  when possible, not the generated shape ad hoc.
- Recipe/crafter stats and learned nodes belong to `CraftingStatsV2`.
- Market observations belong to `AHScan`; price policy belongs to the pricing
  contract/engine, never a frame.
- UI modules may format and route actions but must not recalculate economics.
- Saved custom strategies remain readable for upgrade compatibility. The 2.0
  release does not expose create, import, edit, or delete controls.
- Public slash commands are limited to opening the addon, help, and the support
  log. Player workflows belong in visible UI; developer checks belong in
  `tests/` or `tools/`.

## File-size policy

Size alone is not a reason to split a stable module. Split when a cohesive
responsibility can be named, tested, and loaded in an unambiguous order. This
is why window projections, VI planning, cooldown tracking, Quick Buy, pricing
contracts, and crafting-stat diagnostics have their own modules. Large
generated data files and the pricing formula's embedded regression fixtures
stay intact until a behavior-preserving extraction has equivalent coverage.

## Verification layers

- Pure Lua tests cover formulas, pricing contracts, models, cooldowns, Quick
  Buy, VI ordering, scanner lifecycle, imports, and migrations.
- Python checks enforce TOC completeness, release packaging, and full active
  localization coverage.
- `luac -p` validates every shipped Lua file.
- Live-client acceptance covers Blizzard-only APIs: profession recipe opening,
  learned-node capture, Auction House quotes/purchases, gear snapshots, and
  cooldown reset behavior.

Run the complete local gate from the addon directory before packaging:

```text
lua tests/run.lua
python tests/check_locales.py
python tests/check_toc.py
python tools/package_release.py --check
```

The GitHub workflow runs the full focused Lua test matrix in addition to these
release checks. The release zip is created only from the TOC set, so
repository-only code cannot leak into the installed addon.
