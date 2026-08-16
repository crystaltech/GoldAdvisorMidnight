# Gold Advisor Midnight Commodity Refocus

Status: implemented; retained as the 2.0 design record

Target: `2.0.1`
Source of truth: this repository only; installed addon copies are out of scope.

## Implementation snapshot

Updated 2026-08-15:

- Milestones 1 and 2 are implemented: the 12.1 manifest contains 282 retained
  strategies and 477 commodity output item IDs from 606 definitions, with
  offline tests, a zero-issue retained recipe audit, and CI.
- Milestone 3 is complete. `StrategyModel` schema version 1 is now the only
  runtime normalization boundary, and both Importer and Pricing use it for
  rank-variant recipe views.
- SavedVariables data version 18 runs migrations before full defaults and
  preserves user strategy tables without rewriting active or archived entries.
- A shared nine-profession registry now owns skill lines, stat profiles, and
  CraftSim keys. Cooking is included.
- All retained recipes run through the formula model at runtime, including
  Dazzling Thorium Prospecting.
- Addon metadata identifies the release as `2.0.1`; the Retail interface target
  is `120100`. Remaining live-client checks are documented acceptance work,
  not alternate runtime implementations.
- Nine reviewed 12.1 mass-crafting strategies live in a patch-local strategy
  module with matching compact maintenance facts and recipe-scoped node maps.
- Strategy detail now offers a selected-only recipe refresh. Exact recipe
  snapshots cannot inherit another same-profile recipe's live stats. The live
  selected-recipe workflow is accepted for Lucky Keychain: it opened the exact
  Engineering craft and captured `12.7%` Multicraft / `28.8%`
  Resourcefulness against Blizzard's rounded `13%` / `29%`, with the expected
  recipe-local `+100%` / `+45%` node modifiers.
- The main workflow no longer exposes profile-wide Craft Stats fields. They
  remain in Settings as advanced manual fallbacks, while exact recipe captures
  are the normal source of visible stats and learned-node bonuses.
- A strategy row click now opens its exact recipe when the current crafter's
  snapshot is missing or older than 24 hours; clicking the selected row again
  forces a refresh. Favorite changes remain isolated to the star control.
- Exact recipe snapshots and learned nodes are reused across the account when
  the current character lacks that profession. Only the most recently
  verified exact cached crafter is eligible—profile-only snapshots never cross
  character boundaries—and the selected cached crafter is named in detail.
- The broad live schematic audit is closed with zero retained catalog
  mismatches or unavailable recipe IDs. Exact recipe-scoped CraftSim/node
  calculations have been validated on the account's available Alchemy,
  Blacksmithing, Enchanting, Engineering, Inscription, Jewelcrafting, and
  Tailoring characters. Leatherworking and Cooking learned-stat passes are
  deferred until suitable characters exist.
- Exhaust Materials now has live Resourcefulness-only, both-stat, invested-node,
  and same-profession vertical-integration coverage. VI strategy scans include
  producer leaf commodities and expose direct-versus-producer economic choices.
- Slice 3C's main strategy-list consumer is complete. Its cache, visible rows,
  and profit/ROI sorting now consume only canonical facade results, with an
  integration fixture covering profitable, unprofitable, missing-price,
  stale-price, and multi-output cases.
- Slice 3C is complete. `StrategyDetailModel` projects canonical results into
  both detail surfaces, and shopping, selected scans, scan dumps, VI/crushing
  analyzers, and CraftSim price pushes all consume canonical facade fields.
- Slice 3D is complete. The production engine selector, legacy calculator,
  V2-shadow entry point, comparison command, deltas, and saved option are
  removed. The V2 calculator now emits the sole canonical internal metrics
  shape directly.
- Milestone 4 scanner hardening is in progress. Attempt generations reject
  delayed callbacks after reset, pause, resume, or replacement; first-pass
  retry candidates no longer inflate permanent failure/progress counts.
  Deterministic coverage now includes stale and duplicate events, throttling,
  both timeout passes, Auction House close/resume, and full browse fallback.
- Milestone 5 has begun without a second-system rewrite: custom strategy
  authoring entry points are removed from the release workflow while existing
  eligible SavedVariables remain readable, the English post-locale override is
  gone, and CI verifies that every runtime locale key has a base definition.

Offline verification:

```sh
lua tests/run.lua
lua tests/core_migrations.lua
lua tests/pricing_derivation.lua
lua tests/pricing_v2_formula.lua
lua tests/pricing_contract.lua
lua tests/pricing_facade.lua
lua tests/strategy_list.lua
lua tests/strategy_detail.lua
lua tests/crafting_stats.lua
lua tests/craftsim_bridge.lua
lua tests/ah_scan.lua
lua tests/recipe_audit.lua
python3 tests/check_toc.py
```

## Engineering decision framework

Adopted 2026-07-31 from the
[Laws of Software Engineering](https://lawsofsoftwareengineering.com/). These
are review heuristics, not dogma. When a heuristic conflicts with the product
contract or live Retail evidence, the product contract and observed behavior
win.

### Project rules

1. **Start from the user outcome (First Principles, Pareto).** The core job is
   to answer: “Given this material budget and character, which commodity craft
   is worth mass-producing?” Work that does not improve the accuracy,
   reliability, or clarity of that decision is lower priority.
2. **Evolve the working core (Gall's Law, KISS, Second-System Effect, YAGNI).**
   Do not replace the addon with a speculative framework. Migrate one proven
   vertical slice at a time. Do not add plug-in systems, generic strategy
   editors, or abstractions for hypothetical future products.
3. **Keep one owner for each fact (DRY).** Recipe identity belongs to the
   canonical strategy model; commodity eligibility to `CommodityCatalog`;
   prices to the price store; character stats to the stat provider; expected
   outcomes to the profit engine. Consolidate duplicated knowledge, but do not
   merge code that merely looks similar while representing different rules.
4. **Put unavoidable complexity behind the workflow (Tesler's Law).** The
   addon—not the player—must resolve recipe-scoped stats, node modifiers,
   material exhaustion, rank IDs, and direct-versus-produced costs. Manual
   Multicraft and Resourcefulness values remain an explicit fallback, not the
   primary workflow.
5. **Treat observed behavior as compatibility surface (Hyrum's Law, Principle
   of Least Astonishment).** Before changing SavedVariables, slash commands,
   scan behavior, filters, or displayed economic terms, inventory the current
   behavior and preserve it through a migration or document the deliberate
   break. Names such as “crafts,” “cost,” and “profit” must keep one predictable
   meaning throughout the UI and API.
6. **Prefer readable and diagnosable code (Kernighan's Law).** No clever
   metaprogramming or compressed multi-purpose functions in pricing, scanning,
   or stat resolution. Important decisions must expose their source and inputs,
   as the V2 stat graph and economic-choice dump do today.
7. **Expect side effects (Law of Unintended Consequences).** Changes are small,
   reversible, and independently testable. A behavior change and a structural
   refactor should not share a patch unless a test makes their interaction
   explicit. The backup-first live installer remains part of the workflow.
8. **Use the test pyramid and refresh it (Testing Pyramid, Pesticide Paradox).**
   Put formula and state-machine cases in fast Lua tests, module boundaries in
   fewer integration tests, and reserve live WoW checks for APIs, protected UI,
   CraftSim, and Auction House behavior. Every escaped defect adds a new lower-
   level regression case when practical.
9. **Metrics inform; they do not define success (Goodhart's Law).** Strategy
   counts, module counts, lines deleted, and test counts are diagnostic. Exit
   criteria are observable outcomes: correct economic choices, deterministic
   migrations, complete scans, no taint, and a comprehensible mass-crafting
   workflow.
10. **Live behavior outranks the model (The Map Is Not the Territory).** Pinned
    TSM/Wago data and architecture documents guide development; live Retail
    schematics, CraftSim snapshots, and observed Auction House behavior decide
    whether the model is correct.

### Change review gate

Before merging a material change, answer:

- What user decision or reliability problem does this solve?
- Which module is the single owner of the changed rule afterward?
- Which observable behavior or saved data might already be depended on?
- What is the smallest reversible migration slice?
- What is the cheapest test that can catch a regression?
- What old path becomes provably unused and can be deleted?

If the last answer is “none,” the change must justify why it increases rather
than merely relocates complexity.

## Product contract

Gold Advisor Midnight is a mass-crafting advisor for Auction House commodities.
A shipped strategy is eligible when every output group contains at least one
confirmed commodity item ID. Inputs may include commodities or vendor-supplied
materials.

The product keeps transformations such as milling, prospecting, crushing,
shattering, inks, alloys, bolts, gems, enchants, consumables, and food. It
excludes equipment, profession tools, bags, toys, mounts, crafting-order items,
bind-on-pickup or warbound outputs, and other one-off products.

The pinned baseline established on 2026-07-23 retains 273 of 597 generated
strategy definitions:

| Profession | Retained |
| --- | ---: |
| Alchemy | 27 |
| Blacksmithing | 8 |
| Cooking | 41 |
| Enchanting | 76 |
| Engineering | 25 |
| Inscription | 29 |
| Jewelcrafting | 46 |
| Leatherworking | 11 |
| Tailoring | 10 |
| **Total** | **273** |

## Data policy

Commodity eligibility is generated at development time. The addon never
contacts external services at runtime.

- Primary signal: union of the public TSM Retail commodity files for US, EU,
  KR, and TW.
- Validation signal: Wago `ItemSparse` metadata pinned to a specific Retail
  build, including stack size, binding, inventory type, and item existence.
- Runtime pricing: live Auction House scans, manual prices, and known vendor
  prices. TSM prices are not shipped as live valuations.
- Exceptions: small, reviewed, documented, and represented in generated
  metadata rather than scattered through runtime code.

Source endpoints:

- `https://public-data.tradeskillmaster.com/retail/{region}/commodities.csv`
- `https://wago.tools/db2/ItemSparse/csv?product=wow&build={build}`

The committed manifest records source timestamps, hashes, and the Wago build.
CI validates the committed snapshot offline; refreshing public data is an
explicit development operation.

## Milestone 1: baseline and safety net

- Save this roadmap and source contract.
- Convert embedded smoke checks into a repeatable out-of-game command.
- Add migration fixtures for empty, legacy, and current SavedVariables.
- Add generated-data and TOC integrity checks.
- Add lightweight CI for Lua syntax and offline tests.
- Verify the current Retail interface before changing the TOC from `120100`.

Exit criteria:

- Existing state, pricing, crafting-stat, AH-scan, and CraftSim checks pass.
- All 597 definitions are characterized as retained or excluded.
- No development or test path reads an installed addon copy.

## Milestone 2: commodity catalog and safe filtering

- Add a standard-library manifest generator for the TSM and Wago CSV inputs.
- Generate `Data/CommodityManifest.lua`.
- Add a single `CommodityCatalog` runtime module.
- Enforce eligibility centrally in `Importer.lua`.
- Filter stale or noncommodity IDs from otherwise valid output groups.
- Preserve excluded favorites and custom strategies in SavedVariables without
  indexing them in the active catalog.
- Keep the raw 597-strategy dataset until the filtered runtime is verified.

Exit criteria:

- The pinned built-in runtime catalog contains exactly 273 strategies.
- All nine professions remain represented.
- No retained output is missing from the commodity manifest.
- Source refreshes produce an audit diff instead of silently changing scope.

## Milestone 3: unified craft, pricing, and stat model

Adopt one canonical strategy model:

```text
id
profession
recipeID
statProfileKey
defaultCrafts
outputs[].itemIDs
outputs[].baseYieldPerCraft
reagents[].itemIDs
reagents[].quantityPerCraft
```

Adopt one calculation input and result:

```text
input:  crafts, materialRank, inventoryPolicy, pricePolicy, craftingStats
result: inputCost, expectedOutput, netRevenue, profit, profitPerCraft, roi
```

Implement this as an evolutionary migration, not a pricing rewrite:

### Slice 3A: freeze the production contract

- **Completed 2026-07-31.** Inventory every consumer of legacy, active, and
  V2-shadow metrics in `docs/PRICING_CONTRACT_AUDIT.md`.
- Define the versioned canonical calculation request and result in
  `PricingContract.lua` and executable tests,
  including precise meanings for required cost, consumed cost, expected output,
  net revenue, profit, ROI, and break-even.
- Record compatibility surfaces: SavedVariables keys, slash diagnostics,
  exported fields, list sorting, detail rows, and shopping quantities.

### Slice 3B: one authoritative calculation facade

- **Completed 2026-08-01.** Keep the validated V2 formula and recipe graph
  behind the V2-only `PricingFacade` calculation entry point.
- Keep manual, native, workbook, and CraftSim stats behind `CraftingStatsV2`.
- Keep fallback reasons and economic choices observable under canonical
  diagnostics; do not leak provider-
  specific tables into UI consumers.
- Run SavedVariables migrations before defaults and preserve excluded user data.

### Slice 3C: migrate consumers individually

- **Completed 2026-08-08.**
- Move the main strategy list first, then detail views, shopping/export paths,
  analyzers, and diagnostics.
- Add an integration test for each consumer before switching it.
- Keep the legacy comparison callable only as a temporary diagnostic. Do not
  expose two production meanings of profit.

### Slice 3D: delete only after reachability is zero

- **Completed 2026-08-08.**
- Prove no production consumer calls legacy pricing or retired schema aliases.
- Remove shadow controls, duplicate amount/yield/profile fields, and legacy
  calculations in the same milestone that removes their final consumer.
- Preserve only narrow migration readers for supported historical data.

Exit criteria:

- One formula engine handles all retained strategies.
- One production facade returns the canonical result to every consumer.
- Golden calculations cover every retained stat profile.
- Migration fixtures prove legacy preferences and user strategies survive.
- Production consumers no longer read retired aliases.
- Legacy/shadow pricing and its comparison command are deleted; the contract
  rejects the retired `v2-shadow` shape.

## Milestone 4: commodity-only Auction House scanner

Evolve the working scanner toward one explicit state machine:

```text
queued -> waiting -> retrying -> succeeded | failed
```

- First characterize current queue, retry, close/resume, ranked-item fallback,
  and duplicate-event behavior with state-transition tests.
- Then add generation tokens and stale-callback rejection without changing
  price computation in the same slice.
- In a separate slice, make failure accounting and unique-ID progress totals
  deterministic.
- Remove noncommodity item results, name discovery, and obsolete item-key
  persistence only after the commodity and ranked-quality paths pass live.
- Retain browse fallback only when a captured Retail case proves it necessary.
- Preserve Auction House close/resume and hardware-event quick-buy behavior as
  compatibility surfaces until deliberately redesigned.

Exit criteria:

- Duplicate events cannot double-count.
- Stop/restart cannot allow an old callback to clear a new query.
- Successful retries are not reported as failures.
- Scan Everything queues only manifest commodity IDs.
- Every state transition is logged with a session/query identity at debug
  verbosity, without mutating Blizzard-owned result tables or shared frames.

## Milestone 5: mass-crafting UI

The primary workflow is:

1. Select a profession or commodity.
2. Enter planned crafts.
3. Select material rank and crafting-stat profile.
4. Scan prices.
5. Review batch cost, expected output, profit, profit per craft, and ROI.
6. Optionally inspect the commodity production chain.

Keep profession/search filters, favorites, material rank, inventory costing,
vertical integration, CraftSim, and useful shopping exports. Recipe stats should
be automatic by default; manual values move behind a clearly labeled fallback.

Remove from the initial 2.0 surface:

- General Strategy Creator.
- Encoded and Lua strategy exports.
- The dead `Data/StratsManual.lua` workflow.
- Legacy pricing and shadow-comparison controls.
- Noncommodity scan settings.

Make these changes incrementally in the existing window. Do not perform a
second-system UI rewrite:

- Remove or replace one workflow surface at a time, beginning with controls
  outside the six-step primary workflow.
- Preserve familiar filters, selection, scan, and detail behavior unless a
  recorded usability problem justifies the change.
- Replace the broken onboarding overlay with a simple first-run empty state.
- Remove the English `Locale/ShortUI.lua` overrides, add missing keys, and add a
  locale coverage check. Archive custom strategies rather than deleting them.
- Keep all menus addon-owned and add a protected-UI/taint live check after UI
  changes.

Exit criteria:

- The normal decision workflow fits in one main window.
- No hidden or overlapping controls remain.
- Every visible label is localizable.
- The UI cannot create or import noncommodity strategies.
- The default workflow requires no manual profession percentages when an exact
  recipe snapshot is available.

## Milestone 6: deletion, verification, and release

After reachability checks prove every consumer uses the replacement paths,
remove legacy pricing,
noncommodity scan handlers, name scans, obsolete browse logic, the general
creator/export workflow, redundant stat registries, obsolete settings and
locales, excluded generated definitions, and unused V1 UI modules.

Provisional responsibility map—not a target module count:

```text
CommodityCatalog
PriceStore
CommodityScanner
CraftStats
ProfitEngine
RecipeGraph
MainWindow
```

Keep a responsibility in an existing module when splitting it would add
indirection without removing duplicated knowledge or coupling. The names above
describe ownership boundaries, not a mandate to manufacture seven abstractions.

Final verification includes manifest generation, migration fixtures, formula
goldens across all retained profiles, scan race/retry coverage, CraftSim and
Cooking checks, vertical-integration cycle tests, clean install and upgrade
tests, TOC completeness, Lua syntax checks, and live Retail testing.

Release readiness is judged by the product contract and acceptance cases, not
by lines deleted, module count, or completing every hypothetical profession
configuration. Unavailable learned-profession coverage remains a documented
deferred boundary rather than blocking unrelated verified work.

## Immediate next slice

Continue Milestone 4's scanner characterization and live acceptance:

1. Run the short live list/detail/scan/CraftSim/VI/crushing acceptance pass on
   the 12.1 client, including closing and reopening the Auction House mid-scan.
2. In the release client, run `/dump select(4, GetBuildInfo())` and verify the
   TOC `Interface` value remains `120100` for the 12.1 client.
3. Complete the neither-stat, Multicraft-only, and real-batch formula sanity
   cases when suitable recipes and materials are available.
4. After the remaining live pass, remove the now-unreachable creator/detail
   compatibility modules and finish the onboarding/export reachability audit.

## Review issue disposition

| Finding | Disposition |
| --- | --- |
| Defaults applied before migrations | Fix in Milestone 3 |
| Stale AH callbacks | Attempt generations implemented; extend live/browse coverage in Milestone 4 |
| Incorrect retry accounting | Single-outcome retry accounting implemented; extend timeout/throttle coverage in Milestone 4 |
| Creator overlap and lossy export | Remove creator/export in Milestone 5 |
| Dead `StratsManual.lua` target | Remove in Milestone 5 |
| Broken onboarding | Replace in Milestone 5 |
| English locale overrides | Remove in Milestone 5 |
| Missing Cooking sync | Consolidate in Milestone 3 |
| Missing tests and CI | Begin in Milestone 1 |
| Installed `1.9.2-testing` divergence | Explicitly ignored |
