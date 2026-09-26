# Gold Advisor Midnight

Gold Advisor Midnight (GAM) is a World of Warcraft Retail addon for comparing Midnight crafting profits with live Auction House prices, then shopping for and crafting the profitable ones.

It includes 283 commodity strategies across nine professions. Equipment, profession tools, bags, toys, mounts, bind-on-pickup items, and other one-off crafts are intentionally excluded.

## Features

- Scans live commodity and item prices from the Auction House
- Calculates material cost, buy-now cost, net revenue, profit, return, and break-even price
- Prices materials for the exact quantity you need, ignoring bait listings and never assuming unlisted items exist
- Models Multicraft and Resourcefulness for mass crafting
- Captures recipe stats, specialization bonuses, and saved profession gear sets per crafter
- Compares saved Multicraft and Resourcefulness gear with the `Auto` option
- Plans intermediate crafting (for example, milling herbs for your own pigments) when it is cheaper than buying
- Craft Queue with combined Shopping, a gold check, Quick Buy, and confirmed crafting progress
- Creates Auctionator shopping lists and can send prices and plans to CraftSim
- Shows TradeSkillMaster region sale rates when TSM is installed
- Tracks recipe cooldowns and charges across your characters

## Installation

1. Copy `GoldAdvisorMidnight/` to `World of Warcraft/_retail_/Interface/AddOns/`, replacing any previous version.
2. Launch the game or run `/reload`, then enable **Gold Advisor Midnight**.
3. Use `/gam` to open the addon, then scan once at the Auction House.

Existing `GoldAdvisorMidnightDB` settings are kept and upgraded in place. The separate development addon's settings are not imported.

## Basic Workflow

1. Select a profession, then a strategy.
2. Open the matching recipe in your profession window so GAM can capture its stats and specialization bonuses.
3. Choose the starting craft count, material quality, and profession gear.
4. Scan prices at the Auction House.
5. Review profit, return, break-even price, materials, and expected output.
6. Turn on **Intermediates: Craft them myself** to compare buying intermediate materials with crafting them.
7. Click `Add to Queue` in Details, then use the `Shopping` and `Craft Queue` tabs. Add more strategies to combine their shopping.

`Scan prices` scans the strategies in the list. Ctrl-click scans all strategies, Alt-click scans favorites, and Shift-click scans the selected strategy; the arrow beside it offers the same choices. Click again during a scan to stop it. Cooldowns, Quick Buy, CraftSim, exports, and the Craft Queue are also under `Tools`.

Set the default batch for strategies without their own value in **Settings > Pricing > Default starting crafts**, or with `/gam globalstartqty 50`. Editing **Starting crafts** on a strategy overrides it for that strategy.

## How Prices Work

- **Materials** are priced from the Auction House listings for the exact quantity each strategy needs. Unusually cheap bait listings are ignored, expensive listings you would have to buy are included, and units the market does not list are priced at the highest listed price. When in doubt, estimates err toward a higher cost.
- **Crafted items** are valued at the lowest listing. The Auction House sells the newest listing first at equal prices, so matching the lowest price is enough.
- **Materials you own** reduce what you need to buy, but profit values them at the current market price. Crafting must beat simply selling those materials.
- Each scan saves a small price-by-quantity summary per item, so prices stay accurate after `/reload`.
- If the market lists fewer units than you need, Shopping marks the material with `!` and its tooltip shows how many are listed.

## Settings Row

- `Material quality` chooses Rank 1 materials, Rank 2 materials, or the cheapest verified mix for the highest reachable output rank.
- `Profession gear` chooses `Auto`, `Multicraft`, or `Resourcefulness` for the selected strategy.
- `Intermediates` includes crafting intermediate materials yourself when that is cheaper than buying them.
- `Refresh Recipe` (in Details) recaptures the selected recipe from the current crafter.

### Profession Gear Sets

Equip a gear set, open any recipe of that profession, and use `Save MC` or `Save Res` in the Profession gear menu. A set is saved once per profession and character, and every strategy in that profession uses it together with your specialization nodes.

Once saved, the button reads `Update MC` / `Update Res`. Green means you are wearing that set; orange means your equipped gear differs. Hover it to see the saved items and when they were saved. Click it with new gear equipped to replace the set.

## Craft Queue and Shopping

- `Add to Queue` saves the strategy with its craft count, material ranks, and intermediate choices. Queued plans keep that setup; new scans and global settings affect new entries only.
- **Shopping** combines materials across all queued plans and counts what you already own in your bags, bank, reagent bank, and Warband bank once.
- **Gold check:** Shopping shows the estimated cost and how much you can spend. If buying everything would leave less than your gold reserve (default 20%, **Settings > Pricing > Gold reserve**), it warns you and offers a button to lower the craft count to what fits. With several plans queued, they are reduced together.
- Select a material in Shopping to buy it. Price increases over 5% need your confirmation, and nothing is bought without a click.
- A compact **Quick Buy** panel appears beside the Auction House or a vendor when the queue needs materials sold there. Closing it keeps it closed until your next visit. A vendor purchase is skipped when a fresh Auction House price is cheaper.
- Auction House purchases count toward Shopping while they wait in your mailbox, but only materials you have collected can be crafted. If a delivery was collected across a reload, use `Collected` in Shopping after you receive it.

### Crafting

- Craft counts are **final recipe casts**, not output items. Intermediate requirements use base yields, without assuming Multicraft or Resourcefulness.
- Open the required recipe, equip the intended gear, then use the single next-action button. Each new recipe needs a click; `Stop` (or closing the main window) stops after the current cast.
- Before each batch GAM checks the recipe, your equipped gear, the saved reagent ranks, output quality, and cooldown charges. A changed buff, spec, gear, or output rank asks you to review instead of crafting.
- `Review output rank` previews how a different output rank changes the plan; `Accept ranks` updates that plan and keeps completed progress.
- Each plan has a `Total crafts` field (Enter or clicking away applies, Escape cancels) and a `Remove` button. `Use current setup` updates a plan whose recipe data changed, keeping completed crafts.
- Salvage jobs (crushing, recycling) keep their exact input item and rank; enchanting jobs include the vellum. Recrafting existing equipment stays in Blizzard's profession window. Concentration is never used.
- Finished work moves to completed history. Outputs show produced quantities and free stock in your bags and banks, with a break-even estimate per item. After a batch finishes, GAM can offer extra crafts from unreserved materials; these never buy anything.
- Reloading in the middle of a batch asks you to confirm the completed count before continuing.

## Windows

- `Details`, `Shopping`, and `Craft Queue` share the right-hand pane. `Hide pane` keeps the strategy list; `Open pane` restores the last tab.
- `Mini` switches to one small window with `Strategies`, `Details`, `Shopping`, and `Craft Queue` tabs, sharing the full window's filters and scan actions. `Full` returns to the full layout.

## Planning Notes

- The strategy list estimates the requested batch using expected-value crafting math.
- `Buy Now Cost` in Details is the gold needed up front for exactly what the Craft Queue would buy (base yields, no procs), so it can exceed the expected material cost.
- Intermediate crafting is limited to the cooldown charges you have now; GAM buys any remaining intermediates.
- Thalassian missive estimates are intentionally conservative.
- Crushing is priced as a sell-only strategy. Strategies that use Glimmering Gemdust buy it instead of planning to crush ore.

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
- `/gam settings` opens the settings window.
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
