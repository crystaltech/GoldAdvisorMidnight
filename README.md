# Gold Advisor Midnight

Gold Advisor Midnight (GAM) is a World of Warcraft Retail addon for comparing Midnight crafting profits with live Auction House prices.

It includes 282 commodity strategies across nine professions. Equipment, profession tools, bags, toys, mounts, bind-on-pickup items, and other one-off crafts are intentionally excluded.

## Features

- Scans live commodity and item prices from the Auction House
- Calculates material value, buy-now cost, net revenue, profit, ROI, and break-even price
- Uses quantity-sensitive order-book pricing for larger purchases
- Models Multicraft and Resourcefulness for mass crafting
- Captures recipe stats, specialization bonuses, and saved gear setups per crafter
- Compares saved Multicraft and Resourcefulness gear with the `Auto` option
- Builds cooldown-aware vertical-integration (VI) shopping and crafting plans
- Creates Auctionator shopping lists and can send prices to CraftSim
- Tracks recipe cooldowns and charges across cached characters

## Installation

1. Download a release zip from GitHub Releases.
2. Copy `GoldAdvisorMidnight/` to:

   ```text
   World of Warcraft/_retail_/Interface/AddOns/
   ```

3. Keep the addon folder named `GoldAdvisorMidnight`.
4. Launch the game or run `/reload`.
5. Open the Auction House. Use `/gam` if GAM is not visible.

## Basic Workflow

1. Select a profession and strategy.
2. Open the matching Blizzard recipe so GAM can capture its current stats and specialization bonuses.
3. Choose the starting craft count, material rank, and stat gear.
4. Use `Scan Selected` to refresh the required Auction House prices.
5. Review profit, ROI, break-even price, materials, and expected output.
6. Enable `VI Crafting` to compare buying intermediates with crafting them yourself.
7. Enable `Show craft steps` to open the grouped shopping list and dependency-safe crafting order.

`Scan Current List` refreshes the currently relevant strategy list. Additional tools—including cooldowns, shopping, CraftSim, Quick Buy, and exports—are under `More Tools`.

## Important Controls

- `AH Price Qty` controls how deeply GAM samples the Auction House order book.
- `Material Rank` selects R1, R2, or the cheapest verified mix for the reachable output rank.
- `Stat Gear` selects `Auto`, `Multicraft`, or `Resourcefulness`.
- `Refresh Recipe` recaptures the selected recipe from the current crafter.
- `VI Crafting` recursively evaluates eligible intermediate recipes.
- `Show craft steps` groups vendor purchases, Auction House purchases, intermediate crafts, and the final craft in execution order.

To save a gear setup, equip it, open the exact Blizzard recipe, and use `Save MC` or `Save Res` from the Stat Gear menu. Saved setups belong to that recipe and crafter.

## Planning Notes

- The main strategy panel estimates the requested batch using expected-value crafting math.
- Visible shopping quantities use practical execution counts and subtract owned inventory.
- VI chooses between buying and crafting intermediates using current prices.
- Live recipe charges limit the immediate VI plan. GAM crafts only what is currently available and buys any required intermediate remainder.
- A charge-limited final recipe keeps its requested-batch profitability estimate, while the VI craft-now plan and shopping quantities are capped to the currently available crafts.
- Manual Thalassian missive estimates remain intentionally conservative.

## Commands

```text
/gam
/goldadvisor
/gam log
/gam help
```

- `/gam` or `/goldadvisor` toggles the main window.
- `/gam log` opens the copyable support log.
- `/gam help` lists the available commands.

## Development

The installable addon is in `GoldAdvisorMidnight/`. Generated source data, tests, tools, and documentation remain outside the shipped addon folder.

Run the complete verification gate from the repository root:

```text
python tools/verify.py
```

Build a release package from the addon directory:

```text
python ../tools/package_release.py
```

Additional documentation:

- [Architecture](docs/ARCHITECTURE.md)
- [Translation guide](docs/TRANSLATING.md)
- [Auction House scan test](docs/INGAME_AUCTION_SCAN_TEST.md)
- [Third-party notices](docs/THIRD_PARTY_NOTICES.md)
- [Release history](CHANGELOG.md)

## Support

- Discord: https://discord.gg/v7vsCKCsFh
- For unexpected results, include the output from `/gam log`.
