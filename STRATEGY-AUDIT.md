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

# Astra4 — live audit correction

Bright Linen Spellthread (recipe 1228976): added Eversinging Dust item 243600 alongside 243599 in runtime data and profession source facts. Required amount remains 2. Evidence: user-provided live Tailoring schematic audit. Importer regression confirms both IDs survive loading.

Tailoring report: 7 PASS, 1 MISMATCH (fixed), 2 UNLEARNED; Engineering: 23 PASS, 0 MISMATCH, 3 UNLEARNED. UNLEARNED recipes, including R0CKY-To-Go, had no reported schematic mismatches; the character does not know them. These checks do not certify random salvage output distributions or complete output-rank mappings. Stats-source labels are separate from recipe-data checks and do not establish formula correctness.

29/29 offline checks pass; all 283 retained strategies pass the cross-file audit. Rerun Tailoring's /gamdev auditrecipes after installation to confirm the live discrepancy is gone. Other professions still need their live reports. This build includes all astra2/3 changes.

---

# Astra3 strategy audit

Install: replace GoldAdvisorMidnightDev, then reload WoW. This includes the astra2 layout fixes (your new screenshots still show astra1).

## R0CKY-To-Go

Stored recipe ID 1305148; output item 275676; base yield 3.
Inputs: Pile of Junk 253303 x10; Neutralized Venom Clot 274777 x10; Evercore 243581/243582 x20.
The screenshot corroborates the names, required amounts and base yield, but does not expose numeric IDs or every quality rank.

Using the visible rounded stats (12.7% Multicraft, 28.8% Resourcefulness, +100% MC extra, +45% resource saving), the existing Exhaust Materials model gives approximately 4.59 expected output. It assumes saved reagents are reinvested across repeated crafting. Previously the quantity column rounded up to 5, while revenue already used the fractional average. Main and standalone detail now display the fractional average. Base yield remains 3 and pricing math is unchanged. This expectation is not a guaranteed result from one craft; the screenshot alone does not validate the model's bonus constants.

## Completed checks

All 283 retained strategies passed the existing cross-file catalog audit: recipe/profile mappings, reagent/output IDs and amounts, and specialization mappings. The raw findings are in strategy-catalog-audit.txt; the exported catalog is strategy-catalog.tsv. 29/29 offline checks passed, including a new R0CKY base-vs-average regression and a stale rank-ID regression.

No speculative ID, rank or quantity replacements were made. Internal agreement is not independent proof of current in-game correctness. Wago DB2 retrieval returned HTTP 403 and the referenced item/spell pages could not be retrieved. Thus a fresh external verification of all IDs, rank mappings, and random processing yields remains outstanding.

## Live verification

Open a profession and run `/gamdev auditrecipes`. Copy the resulting export (Ctrl+A, Ctrl+C) and save/send it as text. Repeat for the professions on your crafters. `/gamdev auditrecipes all` attempts the entire retained catalog; unopened professions may be unavailable, so per-profession reports are preferable.

The read-only command checks required reagent ID sets and quantities, schematic output membership, base yield and recipe identity. It catches partially matching rank ID sets, where one correct ID previously hid another incorrect ID. It never changes data or crafts/buys items. UNAVAILABLE means the client did not supply enough information. UNLEARNED is distinct from a mismatch. Recipe-name differences may be localization; inspect findings before applying changes. Rank ordering, full output rank-set completeness and probabilistic milling/prospecting distributions are not certified by this schematic comparison.

## Scope

This is an offline audit plus an executable live-verification path, not a claim that every current game recipe is verified. Install the addon folder only; tests, tools, data and reports outside it are developer materials.
