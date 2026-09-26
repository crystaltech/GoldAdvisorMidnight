# Gold Advisor Midnight

Gold Advisor Midnight (GAM) is a World of Warcraft Retail addon for comparing Midnight crafting profits with live Auction House prices.

It includes 283 commodity strategies across nine professions. Equipment, profession tools, bags, toys, mounts, bind-on-pickup items, and other one-off crafts are intentionally excluded.

## Features

- Scans live commodity and item prices from the Auction House
- Calculates material value, buy-now cost, net revenue, profit, ROI, and break-even price
- Uses quantity-sensitive order-book pricing for larger purchases
- Models Multicraft and Resourcefulness for mass crafting
- Captures recipe stats, specialization bonuses, and saved profession gear sets per crafter
- Compares saved Multicraft and Resourcefulness gear with the `Auto` option
- Builds cooldown-aware vertical-integration (VI) shopping and crafting plans
- Saves multiple strategies in a native Craft Plan with combined shopping, Buy/Craft controls, and confirmed progress
- Creates Auctionator shopping lists and can send prices to CraftSim
- Sends a validated VI execution plan to the CraftSim queue when CraftSim supports it
- Tracks recipe cooldowns and charges across cached characters

## Installation

1. Copy `GoldAdvisorMidnight/` to `World of Warcraft/_retail_/Interface/AddOns/`, replacing the previous production addon files.
2. Launch the game or run `/reload`, then enable **Gold Advisor Midnight**.
3. Use `/gam` to open the addon.

Version **2.2.0** adds the Craft Queue with combined Shopping, Mini mode, profession-wide
saved gear sets, an optional TSM sale-rate column, and a Debug Log with filters and
troubleshooting checks. Existing
`GoldAdvisorMidnightDB` settings are retained and upgraded in place. The separate
development addon's settings are not imported.

## Basic Workflow

1. Select a profession and strategy.
2. Open the matching Blizzard recipe so GAM can capture its current stats and specialization bonuses.
3. Choose the starting craft count, material quality, and profession gear.
4. Use Shift-click on `Scan` to refresh the required Auction House prices.
5. Review profit, ROI, break-even price, materials, and expected output.
6. Enable `VI Crafting` to compare buying intermediates with crafting them yourself.
7. Click `Add to Queue` in Details, then use the `Craft Queue` and `Shopping` tabs in the same right pane. Add other strategies to combine their shopping requirements.

Set the default batch for strategies without a saved override with
`/gam globalstartqty 50`, or change **Default starting crafts** in the addon
settings. Editing **Starting crafts** on an individual strategy continues to
override the global value for that strategy.

Click `Scan` to refresh the filtered list; Ctrl-click scans all strategies, Alt-click scans favorites, and Shift-click scans the selected strategy. Click during a scan to stop it. Additional tools—including cooldowns, shopping, CraftSim, Quick Buy, and exports—are under `More Tools`.

## Important Controls

- Material costs use the Auction House listings for the exact quantity each strategy needs. Unusually cheap bait listings are ignored, and units the market does not list are priced at the highest listed price, so estimates err toward higher costs. Crafted items are valued at the lowest listing, matching how the Auction House sells the newest listing first at equal prices.
- `Material quality` opens a menu to choose R1, R2, or the cheapest verified mix for the reachable output rank.
- `Profession gear` chooses `Auto`, `Multicraft`, or `Resourcefulness` for the selected strategy.
- `Refresh Recipe` recaptures the selected recipe from the current crafter.
- `VI Crafting` recursively evaluates eligible intermediate recipes.
- `Add to Queue` saves the selected strategy's craft count and material ranks without opening another window or changing tabs. `Tools > Craft Queue` opens the queue tab.
- The full-width top controls remain above the strategy list and the right pane. `Details`, `Craft Queue`, and `Shopping` share that pane, with compact centered tabs.
- Closing the pane keeps the strategy list visible. `Open pane` restores its last tab.
- `Mini` switches to a small window with `Strategies`, `Details`, `Craft Queue`, and `Shopping` tabs. Selecting a strategy opens its Details; returning to Strategies retains the list's filters, sorting, and scroll position. `Full` restores the list alongside the right pane.
- The mini Strategies header contains the profession dropdown, `Favorites only` filter, and the scan button with its options menu on the right, sharing the full window's selections and scan actions.
- Narrow mini lists prioritize recipe names and profit; wider lists restore return and sale rate. The window has one close button in Mini.
- Queued entries use their saved material/VI setup. Global settings and new scans affect new entries; changing a queued quantity recalculates its requirements using the saved setup. If recipe data becomes incompatible, `Use current setup` updates remaining work while preserving progress.
- Select a material in Shopping to buy it independently, including when another item is unavailable. Merchant Quick Buy respects a cheaper fresh AH offer.
- Auction deliveries are reconciled after an observed successful buyer-mail collection and bag arrival. If collection is ambiguous or occurred across a reload, use `Collected` in Shopping only after receiving that delivery. Ordinary bag gains never clear expected mail.
- Crushing/recycling salvage jobs preserve their exact input item and rank, resolve an unlocked bag stack at craft time, and limit each batch to that stack. Enchanting jobs target vellum, including it in shopping requirements. Existing-equipment recrafting remains manual. Crafting a queued final recipe outside GAM asks you to confirm total completed crafts; reported output counts cover GAM-managed batches only.
- Completed regular jobs can offer extra crafts from unreserved materials in your bags and banks. Optional batches have lower priority than every regular job (including jobs added later), never generate purchases, and wait if their surplus disappears.
- Shopping combines requirements across the whole queue. The primary queue action leads through shopping and collection before crafting. Changing a saved setup or output rank can change requirements and require additional materials.
- When Shopping is visible, buy and approve prices directly in that tab. When it is hidden, the contextual Quick Buy window provides the same controls. Switching views preserves the pending quote or purchase.

To save a gear set, equip it, open any recipe of that profession, and use `Save MC` or `Save Res` from the Profession gear menu. A set is saved once per profession and crafter; every strategy in that profession uses it together with your specialization nodes. Once saved, the button reads `Update MC` / `Update Res`: green means you are wearing that set, orange means your equipped gear differs. Hover it to see the saved items and when they were saved; click it with the new gear equipped to replace the set.

## Craft Plan

Plans are saved per character. With VI enabled, eligible intermediate recipes appear
before the final craft; with VI disabled, the shopping list uses direct recipe inputs.
The Shopping tab combines shortages across plans and reserves owned inventory (bags, bank, reagent bank and Warband bank) once.
A compact Quick Buy panel appears beside the Auction House or vendor when the queue
needs materials available there. It shows one item, quantity, total, and Buy action.
Opening the panel never buys anything; price increases still require confirmation.
Closing it suppresses automatic reopening until the next visit. Confirmed
Auction House purchases count toward shopping while awaiting mailbox collection,
but only materials you already own (bags and banks) enable crafting.

The minimum counts **final recipe casts**, not output items. Intermediate requirements
use base yields without assuming Multicraft or Resourcefulness. Actual inventory
updates reduce remaining requirements; a shortage never silently reduces the final
target. The plan keeps its saved reagent ranks and checks current recipe requirements,
output quality, and available cooldown charges before a batch.

Open the required recipe, equip the intended gear, then use the single next-action
button. Available batches take priority over shopping for later crafts. The material
column means there are inputs for that many crafts; live recipe checks still apply.
Each queued strategy has an inline `Total crafts` field and a `Remove` button.
Quantity edits apply on Enter or when clicking away; Escape cancels the edit.
Materials and the next available step update automatically as inventory and
confirmed crafts change. There are no save, refresh, or skip buttons. Queued
recipes retain the material ranks and VI choices selected when added.
Each new recipe requires a click. `Stop` appears while crafting; it and closing the main window stop repetitions after
the current cast. Confirmed casts leave the active queue and remain in completed
history. Finished outputs group actual produced quantities by item and separately
show stock free in bags and banks after active plan reservations (including previously
owned stock). Break-even uses the same expected-yield basis as Details and is
recalculated when you change the quantity; after accepting new output ranks it
falls back to a base-yield estimate from current material prices.

A verified rank mismatch offers `Review output rank`. GAM checks the resulting
item and every affected downstream recipe, then previews the rank changes.
`Accept ranks` updates only that plan, preserves completed progress, and recalculates
material requirements. It does not craft automatically. Unknown output data,
incompatible reagents, missing stations, and unavailable cooldown charges cannot
be bypassed. Concentration remains off throughout planning and crafting.

This initial native adapter handles standard item recipes without Concentration.
Salvage, enchanting targets, and recrafts still require Blizzard's profession controls.
Plans retain their final target across cooldowns; charged recipes may require later
batches. Reloading during a batch requires reviewing the recorded completed count
before continuing.

## Planning Notes

- The main strategy panel estimates the requested batch using expected-value crafting math.
- Visible shopping quantities use practical execution counts and subtract owned inventory. `Buy Now Cost` in Details is the gold needed up front for exactly what the Craft Queue would buy (base yields, no procs), so it can exceed the expected material cost.
- VI chooses between buying and crafting intermediates using current prices.
- Live recipe charges limit the immediate VI plan. GAM crafts only what is currently available and buys any required intermediate remainder.
- A charge-limited final recipe keeps its requested-batch profitability estimate, while the VI craft-now plan and shopping quantities are capped to the currently available crafts.
- Manual Thalassian missive estimates remain intentionally conservative.
- Crushing is priced as a sell-only strategy. Strategies that use Glimmering Gemdust buy it at the Auction House rather than planning to crush ore for it.

## Commands

```text
/gam
/goldadvisor
/gam log
/gam settings
/gam help
```

- `/gam` or `/goldadvisor` toggles the main window.
- `/gam log` opens the Debug Log. Its Log page filters messages by severity, area, and text; its Troubleshooting page runs checks (scan results, gear sets, stat sources, recipe audits, support summary) and writes the results to the log.
- `/gam settings` opens the settings window directly.
- `/gam help` lists the available commands.

## Versioning

Gold Advisor Midnight uses `MAJOR.MINOR.PATCH` version numbers:

- `MAJOR` for incompatible redesigns or a new product generation.
- `MINOR` for backward-compatible feature releases.
- `PATCH` for bug fixes, data corrections, and small improvements.

World of Warcraft and source-data build numbers are tracked separately from the addon version.

## Support

- [Release history](https://github.com/crystaltech/GoldAdvisorMidnight/releases)
- Discord: https://discord.gg/v7vsCKCsFh
- For unexpected results, open `/gam log`, run `Troubleshooting > Support summary`, reproduce the problem, then use `Copy All` and include the text.
- The interface is English-only for now; translations will return after review by native speakers.
