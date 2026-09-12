# Gold-making workflow: proposed next changes

## Status

Astra9 implements the default of 50 starting crafts. Existing saved global quantities and per-strategy overrides remain intact: the addon cannot distinguish a deliberately saved 1,000 from an old default. Set `/gamdev globalstartqty 50` to adopt 50 for an existing profile; individual overrides still win. The features below are a design/implementation brief, not implemented in astra9.

## Compact detail layout

Keep the current window and table layout. Beside the profit summary, add two short rows that wrap in narrow Details mode:

- Demand: `TSM sale rate 24% · Avg sold/day 18.5` (illustrative numbers).
- Estimate inputs: `Prices current · Recipe captured` or actionable `Prices stale · Stats estimated`.

Do not add a dashboard, mandatory tutorial, opaque confidence score, or automatic demand-based craft limit. Detail Info explains provenance and limitations. Main list may show a small warning indicator with a tooltip, without adding more permanent columns. Profit label becomes `Estimated profit if sold` where space permits; short list header stays `Est. profit`, with the same explanation in its tooltip.

## 1. Optional TSM demand integration

Use the installed TSM addon's documented API through a small adapter, not an in-game web request. Feature-detect the API and protect queries; confirm the callable API and decimal return behavior against the installed supported TSM version before implementation. Request DBRegionSaleRate and DBRegionSoldPerDay for the actual crafted output item ID selected by the existing rank/pricing logic. Do not scale these values as copper prices.

TSM defines regional sale rate as historical posting success averaged across auction houses, and sold/day as average units sold per auction house per day in the region. Neither predicts this user's sell-through or market share. Show those labels in the tooltip; do not call sold/day the region-wide total or convert batch/sold-per-day into a promised sale time.

Missing provider/data is `Unavailable`, not zero. Preserve a genuine reported zero. Never substitute another output rank without clearly stating it. For multiple distinct outputs, show demand per output under Info or its row tooltip; do not average their rates into a fictional strategy demand score. TSM data can be stale independently of GAM's AH scan; disclose that its refresh is managed by TSM.

Cache queries by exact item ID for a short session TTL (initially 60 seconds), and refresh on selection/expiry rather than per-row sorting or resize. Missing TSM must not prevent scanning, pricing, buying, or crafting. No compulsory dependency.

## 2. Explain output without making promises

Show `Base output for 50 crafts: 150` and `Expected average: ...` for a deterministic recipe, using the active recipe's base yield and requested craft count. This is the baseline before random crafting effects, not a guarantee about rank or sale proceeds. For Exhaust Materials, state that the average includes reinvesting saved materials; do not present expected extra crafts as executable whole crafts.

For milling/prospecting and other random-output recipes, use `Baseline average` instead of `Base output`. Never describe a random drop distribution as guaranteed. Preserve fractional expected quantities; inventory, purchase and executable craft counts continue using their appropriate whole-number rules. Both detail surfaces should consume one shared presentation model.

## 3. Expose estimate inputs

Reuse PricingContract/StrategyDetailModel diagnostics. Treat missing prices, stale prices, fallback stats and unreachable rank as separate facts, not one confidence percentage. Required missing prices suppress numeric profit as today. Stale prices and estimated stats retain the estimate but visibly qualify it. Never display `Verified` merely because the recipe audit passes: recipe identity, rank capability, stat capture and market freshness are different checks.

Offer the existing Scan and Refresh Recipe actions as remedies. Keep scan shortcut help intact. Tooltip/Info names the relevant source and affected items; avoid repeated modal warnings on selecting or scrolling strategies.

## 4. Quick Buy: preserve profit context

Add a compact batch-cost/estimated-profit row above the existing Buy Next/Skip footer. Do not add Stop or a second confirmation on ordinary unchanged purchases.

The shopping list must first gain a strategy-context snapshot: strategy ID, patch, rank/mix, requested and execution quantities, stat snapshot, starting inventory, output valuations, expected costs and their freshness. MainWindowShopping currently hands Quick Buy entries; entries alone are insufficient to honestly recalculate batch profit. Lists without strategy context show `Batch profit unavailable` and retain explicit higher-price review.

On each live quote, calculate a candidate projection before submitting. Reuse the canonical pricing model with quote inputs, not a second profit formula in QuickBuy. Keep confirmed spending as a separate ledger, replace only the current quote, and retain estimates for unquoted materials. Label the result `Projected profit — remaining prices estimated`; buying one item does not refresh output prices. Preserve the original batch/inventory baseline so purchases arriving in bags cannot be counted both as free owned material and as paid cost. Show economic profit separately from cash needed; owned materials still have value.

Keep the existing >5% unit-price review. Also require explicit review if a quote turns projected economic profit from positive to zero/negative, or necessary valuation becomes unavailable/stale. Show old → new cost/profit and the reason in the existing window. With no reliable batch context, never claim margin protection. First version has no arbitrary universal minimum ROI; a later user-configurable floor is optional.

An accepted warning authorizes that quote only. Recheck expiry and funds; don't confirm a changed quote under an old approval. Quote handlers must respect WoW's hardware-event requirements. Close still cancels unsubmitted work while allowing submitted purchase results to reconcile. Auto-close only after confirmed completion.

## 5. Low priority: VI plan → CraftSim queue

Entry point: one `Send to CraftSim queue` action in VI Breakdown/More Tools, not another main toolbar button. Reuse VIBreakdownPlan's dependency-ordered execution steps; do not traverse the tree again or queue economic average craft counts. Purchases/vendor materials never become crafts. Shared intermediates must be consumed/deduplicated according to the existing execution plan, including owned inventory.

Before mutating CraftSim, preview recipe, crafter, exact rank allocation and whole execution count. Validate the installed CraftSim queue interface and version; its current integration here captures stats and is not proof of a supported queue writer. Check learned recipe, profession, required gear/mix, cooldowns, concentration and character ownership. Do not silently substitute another recipe, rank or crafter. Unsupported cross-character or missing-recipe steps must be explained before any queue additions.

Keep existing queue entries; append only after an explicit click. Prevent duplicate additions on repeated clicks for the same plan. Report any partial insertion and identify remaining steps; do not retry already-added steps blindly. Sending a plan never starts crafting automatically. Isolate the adapter so CraftSim changes cannot break pricing or other addon windows.

## Order and acceptance checks

1. Default 50 (implemented); demand adapter plus shared estimate-status/output presentation.
2. Context-bearing shopping lists, quote projection and explicit loss review.
3. CraftSim queue adapter after its current interface is verified.

Tests should cover absent/partial/zero TSM data, exact output rank, multiple outputs; missing/stale prices and fallback stats; quote expiry, thin-margin loss under a 5% increase, confirmed-purchase ledger versus inventory, changed strategy after export; shared VI intermediates, missing recipe, duplicate queue submission and adapter failure. In-game checks remain necessary for secure purchase/recipe actions and layout at minimum width/UI scale.

## Design basis and sources

Apply proximity/common region and chunking by keeping demand and estimate conditions beside profit; use Info for detail. Hick's Law favors one purchase action with conditional review over more permanent buttons. Software principles KISS/DRY/Gall's Law favor small adapters, the existing canonical pricing model, and staged implementation. These are design choices informed by the sites, not proof that one layout is objectively best.

- https://lawsofux.com/
- https://lawsofsoftwareengineering.com/
- https://support.tradeskillmaster.com/en_US/custom-strings/which-value-sources-can-i-use-and-what-do-they-mean
- https://support.tradeskillmaster.com/en_US/api-documentation/what-is-the-tsm-addon-api-and-how-do-i-use-it
