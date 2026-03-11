# Gold Advisor Midnight — How-To Guide
**Version 1.2.0-RC5** | Author: Celaida | WoW Midnight (12.x)

---

## What It Does

Gold Advisor Midnight scans the Auction House for current prices, then calculates profit, ROI, and reagent costs for 63 crafting strategies across 8 professions. It tells you which crafts are profitable right now and exactly what to buy. You can also create, edit, and share your own custom strategies.

---

## Getting Started

### Opening the Addon
1. Open the Auction House (walk up to an AH NPC).
2. The Gold Advisor window opens automatically alongside the AH.
3. Alternatively, type `/gam` anywhere to toggle the window.

### First Scan
Click the **Scan All** button in the main window, or type `/gam scan` while the AH is open.

- The addon queries every item used by tracked strategies, one at a time.
- A progress bar shows scanned / total. Scanning ~200 items takes 10–15 minutes at the default throttle.
- Prices are cached for **10 minutes**. You don't need to re-scan every session.

> **Tip:** Run a scan once when you log in, then browse strategies while it runs in the background.

---

## Main Window

The main window lists all strategies sorted by **Profit** by default. Each row shows:

| Column | Description |
|--------|-------------|
| **Strategy** | Craft / process name |
| **Profit** | Net revenue minus total reagent cost (after AH cut) |
| **ROI** | Return on investment as a percentage |
| **Cost** | Total gold needed to buy all missing reagents |
| **Revenue** | Expected sell revenue (after AH cut) |
| ★ | Favorite — click to pin to the top of the list |

### Filtering by Profession
Use the tabs at the top of the window to filter by profession:
`All` · `Alchemy` · `Engineering` · `Enchanting` · `Inscription` · `Jewelcrafting` · `Leatherworking` · `Blacksmithing` · `Tailoring`

### Sorting
Click any column header to sort by that column. Click again to reverse the sort.

### Color Coding
- **Green** profit = currently profitable after AH cut
- **Red** profit = currently a loss
- **Gray / italics** = one or more prices are missing (no scan data yet)
- **Orange tint** = price data is stale (older than 10 minutes)

---

## Strategy Detail Window

Click any row in the main window to open the **Strategy Detail** panel. It shows:

### Input / Reagents Section
Each reagent row displays:
- **Item name** (click to view the item tooltip or shift-click to link it in chat)
- **Unit price** (from AH scan or your override)
- **Total Qty** — how many you need to buy (after subtracting what you already have in bags/bank)
- **Total Cost** — unit price × qty to buy

The **first reagent row** (primary input) has an editable **Total Qty** field. Type a number there and press Enter to set how many of the primary input you want to process. All other quantities scale proportionally.

> **Example (Tranquility Bloom Milling):** Default is 5000 herbs. Type `10000` → all reagent and output quantities double automatically.

### Output Section
Shows the expected output item(s), their quantity, unit price, and net revenue. Item names are clickable for tooltips and chat linking.

**Multi-output strategies** (Jewelcrafting prospecting, Enchanting shatters) show each output item separately with its expected quantity and individual revenue contribution. Total revenue is the sum across all outputs.

### Summary Bar
At the bottom of the detail panel:
- **Total Cost to Buy** — gold needed for missing reagents
- **Net Revenue** — expected income after AH cut
- **Profit** — revenue minus cost
- **ROI** — profit / cost × 100%
- **Break-even Price** — minimum sell price per output unit to cover costs

### Shallow Fill Notice
If **Shallow Fill Mode** is enabled in Settings, an orange notice bar appears above the buttons:
> `[Shallow Fill] 1,000-unit AH price (experimental)`

This is a reminder that prices are using a shallower fill quantity rather than the standard 50,000-unit simulation. See [Shallow Fill Mode](#shallow-fill-mode-experimental) below.

---

## Covered Strategies (63 total)

### Alchemy (14)
Composite Flora · Haranir Phial of Perception · Amani Extract · Silvermoon Health Potion · Draught of Rampant Abandon · Vicious Thalassian Flask of Honor · Haranir Phial of Finesse · Potion of Recklessness · Potion of Zealotry · Light's Potential · Flask of the Blood Knights · Flask of the Shattered Sun · Void-Shrouded Tincture · Lightfused Mana Potion

### Engineering (22)
**Crafting:** Soul Sprocket · Song Gear · Smugglers Lynxeye · Laced Zoomshots · Farstrider Hawkeye · Weighted Boomshots · Emergency Soul Link

**Recycling (sell materials for engineering parts):** Recycling Arcanoweave · Recycling Codified Azeroot · Recycling Sunfire Silk Bolt · Recycling Soul Sprocket · Recycling Arcanoweave Lining · Recycling Gloaming Alloy · Recycling Powder Pigment · Recycling Refulgent Copper Ingot · Recycling Argentleaf Pigment · Recycling Devouring Banding · Recycling Munsell Ink · Recycling Song Gear · Recycling Bright Linen Bolt · Recycling Imbued Bright Linen Bolt · Recycling Infused Scalewoven Hide

### Enchanting (5)
Dawn Shatter Q2 · Oil of Dawn · Smuggler's Enchanted Edge · Radiant Shatter Q2 · Thalassian Phoenix Oil

### Inscription (6)
Tranquility Bloom Milling · Argentleaf Milling · Mana Lily Milling · Sienna Ink · Munsell Ink · Soul Cipher

### Jewelcrafting (7)
Refulgent Copper Ore Prospecting · Dazzling Thorium Prospecting · Brilliant Silver Ore Prospecting · Umbral Tin Ore Prospecting · Crushing · Sunglass Vial Crafting · Sin'dorei Lens Crafting

### Leatherworking (4)
Scale Woven Hide · Void-Touched Drums · Sin'Dorei Armor Banding · Silvermoon Weapon Wrap

### Blacksmithing (3)
Refulgent Copper Ingot · Gloaming Alloy · Sterling Alloy

### Tailoring (2)
Bright Linen Bolt · Imbued Bright Linen Bolt

---

## Settings

Open settings via the **minimap button** (right-click) or the gear icon in the main window header.

| Setting | Default | Description |
|---------|---------|-------------|
| **Scan Delay** | 3.0s | Seconds between AH queries. Increase if you experience throttle errors |
| **Debug Verbosity** | 1 | Log detail level: 0=off, 1=info, 2=debug, 3=verbose |
| **Show Minimap Button** | On | Toggle the minimap icon |
| **Rank Policy** | Lowest | Which quality rank to use when buying reagents: `Lowest` (cheapest) or `Highest` |
| **Shallow Fill Mode** | Off | See [Shallow Fill Mode](#shallow-fill-mode-experimental) below |
| **Fill Qty** | 1,000 | Active when Shallow Fill is enabled. Range: 250–50,000 |

---

## Shallow Fill Mode (Experimental)

Found in **Settings**, below the Rank Policy dropdown.

By default, GAM prices reagents by simulating the purchase of **50,000 units** from the AH order book. This gives a stable "deep-fill" average that represents the real cost of buying at scale.

**Shallow Fill Mode** instead simulates buying only your configured **Fill Qty** (default 1,000). This can show cheaper prices for small crafting sessions where you only need a few hundred units, because it only samples the top of the order book rather than filling deep into it.

**Important caveats:**
- This is a different *pricing model*, not a more accurate one. On thin markets it can be unstable (one cheap listing skews the entire average).
- Use it for comparison or when you know you're doing a small one-time batch — not as a general replacement for the default.
- Changing the effective fill quantity (or toggling the mode) automatically **clears the price cache** so fresh scans use the new model.

### Configuring Fill Qty
1. Open Settings (right-click minimap button).
2. Check **Shallow Fill Mode (Experimental)**.
3. The **Fill Qty** editbox becomes active. Type a number between 250 and 50,000.
4. Click **Apply & Close**.

The Strategy Detail window will show an orange notice bar when the mode is active.

---

## Price Overrides

In the Strategy Detail window, right-click any reagent price to set a **manual price override**. Overrides persist across sessions and take priority over AH scan data and CraftSim. Useful for:
- Items you already own (set price to 0 or your cost basis)
- Items with thin AH markets where the listed price is unreliable

To clear an override, right-click the price and choose **Clear Override**.

---

## Understanding Output Quantities

All quantities shown assume you're processing the **default batch size** (shown at the top of the detail panel). Expected output quantities already include average proc rates for multicraft and resourcefulness — they represent real-world averages, not base recipe yields.

> **Example:** Soul Cipher shows 2.729 ciphers per craft. This accounts for the multicraft proc that occasionally yields 2 instead of 1. Over many crafts your actual average will be close to this number.

For **milling and prospecting**, the batch size is fixed (e.g., 5000 herbs or ore). Use the primary reagent qty field to scale up or down.

---

## Custom Strategies

You can create, edit, and share your own strategies via the **Strategy Creator**.

### Opening the Creator
- Type `/gam create`, or
- Click the **Create Strategy** button in the Settings panel.

### Creating a Strategy
1. Choose a **Profession** from the dropdown (or type a custom name).
2. Enter a **Strategy Name**.
3. Set the **Input Quantity** — the base batch size all ratios are calculated against (e.g. 1000 herbs to mill).
4. Add **Reagents** — click **+ Reagent**, enter the item name and item ID, and set the quantity per batch.
5. Add **Outputs** — click **+ Output**, enter the item name, item ID, and expected output quantity per batch.
6. Click **Save**.

> **Finding Item IDs:** Hover over any item in-game and use an addon like ItemID, or type `/gam ids` to dump all currently tracked item IDs to the debug log.

### Editing and Deleting
Open a user-created strategy in the Strategy Detail window. The **Edit** and **Export** buttons appear at the bottom right (these buttons are hidden for built-in strategies).

- **Edit** — opens the Strategy Creator pre-filled with the strategy's current values.
- **Delete** — available inside the Creator when editing an existing strategy.

### Exporting and Sharing
Click the **Export** button in the Strategy Detail window to open the Export popup. Two formats are provided:

| Format | Use |
|--------|-----|
| **Encoded** | Share the one-line string with other GAM users. They can paste it to import. |
| **File-edit (Lua)** | Paste the Lua table directly into `Data/StratsManual.lua` for a permanent addition. |

---

## Slash Commands

| Command | Description |
|---------|-------------|
| `/gam` | Toggle the main window |
| `/gam scan` | Start a full AH price scan (AH must be open) |
| `/gam clearcache` | Wipe all cached prices (forces fresh scan) |
| `/gam reload` | Reload strategy data from saved variables |
| `/gam log` | Toggle the debug log window |
| `/gam ids` | Dump all tracked item IDs to the debug log |
| `/gam create` | Open the Strategy Creator |

---

## CraftSim Integration (Optional)

If you have [CraftSim](https://www.curseforge.com/wow/addons/craftsim) installed, you can use the **Push to CraftSim** button in the Strategy Detail window to push current reagent prices as manual overrides into CraftSim. This is useful for feeding GAM's AH-scanned prices into CraftSim's crafting queue.

> **Warning:** Pushing prices will overwrite any existing manual price overrides in CraftSim for all reagents in that strategy.

---

## Tips

- **Recycling strats** are useful when raw materials (cloth, leather, pigments) are cheap relative to engineering components. Check these when the market for crafted gear is slow.
- **Milling** profitability depends heavily on herb prices. Tranquility Bloom and Mana Lily yield the same pigment rate (~1.53 pigment per herb on average).
- **Prospecting** strats show the combined revenue from all gem types. Individual gem prices vary wildly — a single expensive diamond can flip a strat from loss to profit.
- **Enchanting shatters** (Dawn Shatter Q2, Radiant Shatter Q2) produce two quality tiers of output. Both are factored into the revenue calculation.
- The **Favorites** star pins a strategy to the top of the list across all profession tabs.
- **Shift-click** any item name in the Strategy Detail window to link it in chat.

---

## Known Limitations (Beta)

- The addon does not place AH listings or buy orders automatically — it is read-only.
- Some items may show **"No Price"** if they haven't appeared in the AH during your scan window. Try `/gam clearcache` followed by a fresh scan during peak hours.
- The **Crushing** strategy uses Amani Lapis as the representative cheap gem. If a different gem (Harandar Peridot, Tenebrous Amethyst, Sanguine Garnet) is cheaper on your realm, swap the primary reagent manually via price override.
- **Shallow Fill Mode** can show volatile prices on thin markets (fewer than ~250 active listings). This is expected behavior — it reflects actual AH availability.

---

*Gold Advisor Midnight v1.2.0-RC5 — feedback and bug reports welcome.*
