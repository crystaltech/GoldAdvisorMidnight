# Pricing Contract Audit

Status: Slices 3A through 3D complete

Date: 2026-08-08
Production behavior changed: every production consumer uses canonical facade results

## Boundary

`PricingContract.lua` defines the request/result boundary for the commodity
expected-value engine. `PricingFacade.lua` is the authoritative V2-only entry
point. The main strategy list consumes it through a signature-aware cache, and
both detail surfaces consume it through `UI/StrategyDetailModel.lua`. Shopping,
selected scans, scan dumps, VI/crushing analyzers, and CraftSim price pushes use
canonical result fields. The retired spreadsheet-era and V2-shadow calculators
are no longer present.

`UI/StrategyListModel.lua` owns the list's cache, visibility, favorite pinning,
and sort behavior so those decisions can be verified without constructing WoW
frames. The fixture proves the list never reaches the legacy-capable active
engine.

`UI/StrategyDetailModel.lua` owns the canonical-to-visible base-detail
projection. Its fixture covers profitable, unprofitable, missing-price, stale,
single-output, multi-output, and formula/stat-caption behavior without
constructing WoW frames.

## Pricing entry-point inventory

| Entry point | Current role | Classification | Slice disposition |
| --- | --- | --- | --- |
| `PricingFacade.Calculate` | Validates a versioned request, calls V2 only, and returns the canonical result | Authoritative production facade | Complete |
| `PricingFacade.CalculateCurrent` | Builds a current-state request and calculates it in one call | Authoritative convenience facade used by the strategy list and inline base detail | Use where a consumer does not need to retain the request snapshot |
| `CalculateStratMetricsActive` | Removed; no production engine selector remains | Retired compatibility facade | Complete |
| `CalculateStratMetricsV2` | Computes the sole canonical internal metrics shape | Production implementation behind the facade | Complete |
| `CalculateStratMetricsV2Shadow` | Removed with comparison deltas | Retired | Complete |
| `CalculateStratMetrics` | Removed spreadsheet-era public calculation | Retired | Complete |
| `GetActivePricingEngine` | Removed with the retired `pricingEngine` option | Retired compatibility control | Complete |
| `GetVIBreakdownData` | Builds the visible vertical-integration graph behind a canonical facade adapter | Production specialized projection, migrated | Complete |
| `GetCrushingAnalyzerData` | Builds visible crushing alternatives with facade-calculated candidates | Production specialized projection, migrated | Complete |
| `GetDisplayedItemSet` | Resolves selected ranked/display items from canonical shopping rows | Production helper, migrated | Keep until scanner consolidation |
| `GetExtraScanItems` | Adds special strategy scan dependencies | Production helper | Keep until scanner consolidation |
| `GetVerticalIntegrationScanItems` | Adds producer and producer-leaf scan dependencies | Production helper | Keep until scanner consolidation |
| `GetActiveRecipeView` | Public wrapper over canonical rank resolution | Production compatibility helper | Stop monkey-patching it in tests before considering removal |
| `GetStrategyScore` | Removed after reachability check | Retired | Complete |
| `GetBestStrategy` | Removed after reachability check | Retired | Complete |

Price-store and presentation helpers such as `GetEffectivePrice`,
`GetUnitPrice`, `FormatPrice`, and price overrides are not profit-engine entry
points. They remain owned by Pricing/PriceStore work and are outside this
contract migration.

## Consumer inventory

| Consumer | Fields or projections used | Classification | Migration order |
| --- | --- | --- | ---: |
| `UI/MainWindowV2.lua` strategy cache/list | Canonical `profit`, `roi`, `missingPrices`, and `hasStale` | Production, migrated | Complete |
| `UI/MainWindowV2Center.lua` list rendering | Canonical `profit`, `roi`, and `missingPrices` from cached results | Production, migrated | Complete |
| `UI/MainWindowV2Detail.lua` base detail | Canonical projection of costs, revenue, profit, ROI, break-even, crafts, reagent/output rows, and formula/stat diagnostics | Production, migrated | Complete |
| `UI/VIBreakdownWindow.lua` and `UI/CrushingAnalyzerWindow.lua` | Facade adapters over canonical results | Production, migrated | Complete |
| `UI/StratDetail.lua` | Canonical detail projection, shopping rows, scans, and CraftSim result | Reachable production fallback, migrated | Complete |
| `CraftSimPriceOverrides.lua` | Canonical `recipeReagents` and active output identity | Production integration, migrated | Complete |
| `UI/DebugLog.lua` scan dump | Canonical outputs, shopping rows, and displayed item set | Production diagnostic, migrated | Complete |
| `Pricing.RunSmokeChecks` and offline fixtures | canonical formula and recipe-graph behavior | Regression | Complete |
| `CraftSimBridge.RunSmokeChecks` | canonical CraftSim integration fixtures | Regression | Complete |

The old `StratDetail` remains a reachable fallback, but it uses the same
canonical facade as the primary detail surface.

## Canonical request version 1

The request is built and validated by `PricingContract.BuildRequest`.

| Field | Meaning |
| --- | --- |
| `contractVersion` | Exact schema version; currently `1` |
| `strategy` | Canonical `StrategyModel` strategy, including stable `id` and `recipeID` |
| `patchTag` | Price/state namespace used for this calculation |
| `craftScale` | Compatibility multiplier applied to the strategy's stored baseline amount and crafts |
| `inputQuantityOverride` | Snapshotted persisted input-quantity override, or nil |
| `craftsOverride` | Snapshotted persisted exact-crafts override, or nil; it takes precedence over the input override in the current engine |
| `materialRank` | `lowest` or `highest` input-rank policy |
| `pricingMode` | `exhaust_materials` or `fixed_crafts` |
| `inventoryPolicy` | `opportunity_cost`: owned inventory changes buy-now cash, not profit |
| `pricePolicy` | `runtime_market`, or `craftsim_then_market` when the saved CraftSim price source is active |
| `useVerticalIntegration` | Whether eligible intermediates may be valued through their producer graph |
| `fillQuantity` | Positive integer order-book depth used for input acquisition pricing |
| `auctionHouseCut` | Fraction removed from gross output revenue, at least zero and less than one |

`craftScale` preserves the current public call meaning. The canonical result
uses the resolved `crafts` count, so consumers do not need to know the baseline
scaling rule. Saved batch overrides are included in the request snapshot so a
change between request creation and calculation is detected rather than hidden.

Crafting-stat provider details are intentionally absent. The future facade owns
recipe-scoped native, CraftSim, cache, and manual fallback resolution, including
different stats for nodes in a vertical-integration graph.

## Canonical result version 1

The stable consumer result is produced by
`PricingContract.FromV2Metrics(request, metrics)`.

| Field | Exact meaning |
| --- | --- |
| `startingAmount` | Resolved baseline input-budget amount for the selected strategy |
| `crafts` | Planned craft attempts before Resourcefulness reinvestment |
| `effectiveCrafts` | Expected attempts after Resourcefulness behavior for the selected pricing mode |
| `expectedOutput` | Unrounded expected quantity of the primary output |
| `requiredCostFull` | Full market cost of the starting material budget, ignoring owned inventory |
| `expectedConsumedCostFull` | Economic cost used for profit and ROI; fixed crafts subtracts expected savings, exhaust materials reinvests them and normally retains the full budget cost |
| `averageSavedCost` | Expected material value not consumed in fixed-crafts mode; zero when savings are reinvested by exhaust-materials mode |
| `buyNowCost` | Current cash needed after owned inventory is applied to the shopping plan; never the profit denominator |
| `netRevenue` | Expected output sale value after the Auction House cut |
| `profit` | `netRevenue - expectedConsumedCostFull` |
| `profitPerCraft` | `profit / crafts`, using planned rather than effective crafts |
| `roi` | `profit / expectedConsumedCostFull * 100`; nil for a zero consumed cost |
| `breakEvenSell` | Required unit sale price before the Auction House cut for a single-output strategy |
| `shoppingReagents` | Rows presented/purchased after VI and owned-inventory resolution |
| `recipeReagents` | Direct recipe inputs needed by integrations such as CraftSim |
| `outputs` | One or more priced expected-output rows; the primary output is first |
| `missingPrices` | Names whose absent prices make the complete economic result unavailable |
| `hasStale` | At least one contributing runtime price is stale |
| `selectionNotes` | User-facing explanation of dynamic input selection |
| `diagnostics` | Nested formula, stat-source, and economic-choice evidence; not a general UI data source |

The canonical result deliberately excludes the ambiguous `totalCostFull`
alias, the old `costReagents` name, comparison `deltas`, and provider-specific stat
fields at the top level.

## Facade state rule

The current V2 implementation reads addon options and persisted batch overrides
through existing helpers. `PricingFacade.Calculate` therefore rebuilds the
current request snapshot immediately before calculation and compares every
policy field. A mismatch returns `request-current-state-mismatch:<field>` and
does not calculate.

This is a transitional safety boundary, not a global-state mutation mechanism.
It guarantees that the result's rank, pricing mode, price source, VI state,
fill quantity, AH cut, and batch overrides describe the state V2 actually used.
The facade calls only `CalculateStratMetricsV2`; no fallback engine entry point
exists.

## Compatibility surface that must survive migration

- SavedVariables inputs: `v2PricingMode`, `rankPolicy`,
  `shallowFillQty`, `ahCut`, three VI source options, per-strategy starting
  amounts, price overrides, and manual stat fallbacks.
- Support diagnostics: `/gam log` remains the only player-facing diagnostic.
  Pricing modes, formula fixtures, request-state mismatches, and scan lifecycle
  behavior are verified by the offline test suite; the old developer slash
  commands were retired before 2.0.
- Strategy list ordering and missing-price behavior.
- Detail labels and their current units: copper values, ROI percent, and
  break-even unit sale price.
- Shopping quantities, owned-item counts, VI producer selection, and the direct
  recipe rows exported to CraftSim.

## Slice 3D completion

Every production consumer is canonical. Embedded pricing smoke checks call the
canonical V2 implementation, the contract rejects `v2-shadow`, and repository
reachability checks find no legacy, active-selector, shadow, or comparison
pricing entry point.
