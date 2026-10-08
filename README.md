# Gold Advisor Midnight

Gold Advisor Midnight (GAM) is a World of Warcraft Retail addon for comparing Midnight crafting profits with live Auction House prices, then shopping for, crafting, posting and tracking the profitable ones.

It includes 285 commodity strategies across nine professions. Equipment, profession tools, bags, toys, mounts, bind-on-pickup items, and other one-off crafts are intentionally excluded.

New to GAM? The [Getting Started guide (PDF)](docs/guide/GAM-Getting-Started-Guide.pdf) walks through installing, your first price scan, and your first week, step by step. It is also attached to each release.

## Features

- Scans live commodity and item prices from the Auction House
- Calculates material cost, buy-now cost, net revenue, profit, return, and break-even price
- Prices materials for the exact quantity you need, ignoring bait listings and never assuming unlisted items exist
- Models Multicraft and Resourcefulness for mass crafting
- Reads your recipe stats and specialization bonuses when you open a profession, and keeps exact stats for each saved profession gear set
- Compares saved Multicraft and Resourcefulness gear with the `Auto` option
- Plans intermediate crafting (for example, milling herbs for your own pigments) when it is cheaper than buying
- Optional manual material prices for materials you gathered or already bought
- Craft Queue with combined Shopping, a gold check, Quick Buy, and confirmed crafting progress
- Posting tab: post what you crafted at the lowest listing (never undercutting), and cancel and repost undercut auctions
- History tab: what you bought, crafted, posted and sold, realized profit per item and per batch, and suggestions on what to craft more or post less
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
2. Open that profession's window once on the crafter. GAM reads the stats of every strategy recipe the character knows, and reads them again after gear or specialization changes. Strategies this character can't craft are dimmed; hover one to see why and which of your characters has learned it.
3. Choose the starting craft count, material quality, and profession gear.
4. Scan prices at the Auction House.
5. Review profit, return, break-even price, materials, and expected output.
6. Turn on **Intermediates: Craft them myself** to compare buying intermediate materials with crafting them.
7. Click `Add to Queue` in Details, then use the `Shopping` and `Craft Queue` tabs. Add more strategies to combine their shopping.
8. Post your crafts from the `Posting` tab, and check `History` to see what really made gold.

`Scan prices` scans the strategies in the list. Ctrl-click scans all strategies, Alt-click scans favorites, and Shift-click scans the selected strategy; the arrow beside it offers the same choices. Click again during a scan to stop it. Cooldowns, Quick Buy, CraftSim, exports, and the Craft Queue are also under `Tools`.

Set the default batch for strategies without their own value in **Settings > Pricing > Default starting crafts**, or with `/gam globalstartqty 50`. Editing **Starting crafts** on a strategy overrides it for that strategy.

## How Prices Work

- **Materials** are priced from the Auction House listings for the exact quantity each strategy needs. Unusually cheap bait listings are ignored, expensive listings you would have to buy are included, and units the market does not list are priced at the highest listed price. When in doubt, estimates err toward a higher cost.
- **Crafted items** are valued at the lowest listing. The Auction House sells the newest listing first at equal prices, so matching the lowest price is enough.
- **Materials you own** reduce what you need to buy, but profit values them at the current market price. Crafting must beat simply selling those materials.
- Each scan saves a small price-by-quantity summary per item, so prices stay accurate after `/reload`.
- If the market lists fewer units than you need, Shopping marks the material with `!` and its tooltip shows how many are listed.
- **Manual material prices** (off by default): turn on **Settings > Pricing > Allow manual material prices**, then right-click a material in Details to use your own price, for example for materials you gathered or already bought. Prices last until you log out unless **Keep manual prices after logout** is on, and are set per rank. They only value materials: sale prices, Buy Now cost and Quick Buy always use the Auction House.

## Settings Row

- `Material quality` chooses Rank 1 materials, Rank 2 materials, or the cheapest verified mix for the highest reachable output rank.
  The output rank is checked on the character who knows the recipe. Open GAM once on each crafter; your other characters then use that crafter's rank and mix.
- `Profession gear` chooses `Auto`, `Multicraft`, or `Resourcefulness` for the selected strategy.
- `Intermediates` includes crafting intermediate materials yourself when that is cheaper than buying them.
- `Refresh Recipe` (in Details) recaptures the selected recipe from the current crafter. Opening the profession already does this for every recipe; use it for salvage recipes (milling, prospecting, crushing, recycling, shatter), which only show their stats with an item selected.

### Profession Gear Sets

Equip a gear set, open any recipe of that profession, and use `Save MC` or `Save Res` in the Profession gear menu. A set is saved once per profession and character, and every strategy in that profession uses it together with your specialization nodes.

Once saved, the button reads `Update MC` / `Update Res`. Green means you are wearing that set; orange means your equipped gear differs. Hover it to see the saved items and when they were saved. Click it with new gear equipped to replace the set.

A saved set fills in its own stats: whenever the profession window is open and you are wearing that set, GAM keeps that set's exact Multicraft and Resourcefulness for every strategy recipe. Wear each set once with the profession open after saving it, and again after spending knowledge points. Sets saved by older versions don't need saving again; wear them once with the profession open. With `Auto`, GAM compares your sets recipe by recipe, usually picking Multicraft for recipes that have Multicraft and Resourcefulness for the ones that don't (salvage, enchants, gear).

Stats read while Shattered Essence is active are not saved, and gear sets can't be saved during it, because its bonus lasts only minutes.

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

## Posting

- The `Posting` tab lists what your Craft Queue made. **Settings > Posting** can add other items GAM strategies make that are in your bags or bank.
- Each row starts at the lowest listing. Tick what to post, change the price or quantity if you like, then press **Post** once per auction (Blizzard requires a click for each).
- Rows start unticked when the price is below break-even, the item keeps expiring, you already have enough listed, or the only listings look far above the item's usual price. Hover the status dot to see why; you can still tick them.
- **Your auctions** shows where each auction stands: first in line, undercut, matched by a newer listing at your price (the newest sells first), or worth reposting higher. Ticked auctions are cancelled and reposted with the same button. A cancel is only ticked when reposting stays above break-even and the lost deposit is small.
- Press `Recheck` to re-read your auctions and current prices. To have GAM re-check prices on its own when the Auction House opens and after each post or cancel (only while a GAM window is open), turn on **Settings > Posting > Check prices automatically**. It is off by default.
- Auction duration, starting quantity and the cancel rules are in **Settings > Posting** and **Settings > Your auctions**.

## History

- GAM records purchases, crafts, posts, cancels, expiries and sales on each character, including ones made with Blizzard's interface or other addons.
- **Totals** show what you spent, sold after the cut, lost in deposits, your realized profit, and gold sitting in unsold stock.
- **By item** gives each item a verdict (Craft more, Post less, Losing money, Unsold stock). **By batch** follows each Craft Queue plan from purchase to sale, using the materials it really used at what you paid. **Log** lists every event.
- **Suggestions** rank what to do next by gold. `Queue N crafts` adds about a week of your own sales, minus what you already own, have listed or have queued, within 80% of your gold. Nothing changes unless you click.
- Keep history for 30, 90 or 180 days or a year in **Settings > Crafting history**, with an optional minimum profit per craft.

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
