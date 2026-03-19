# Gold Advisor Midnight — User Guide

**Version 1.4.3 · WoW Midnight (12.0.x / TOC 120001)**

---

## Table of Contents

1. [What This Addon Does](#what-this-addon-does)
2. [Installation](#installation)
3. [First-Time Setup](#first-time-setup)
4. [Minimap Button](#minimap-button)
5. [Main Window](#main-window)
6. [Strategy Detail Panel](#strategy-detail-panel)
7. [Shopping List](#shopping-list)
8. [Quick Buy](#quick-buy)
9. [Settings](#settings)
10. [Debug Log](#debug-log)
11. [CraftSim Integration](#craftsim-integration)
12. [Slash Commands](#slash-commands)
13. [Recommended Workflow](#recommended-workflow)
14. [Tips & FAQ](#tips--faq)
15. [Known Limitations](#known-limitations)

---

## What This Addon Does

Gold Advisor Midnight helps you find profitable crafting opportunities by:

- Scanning the **Auction House** for live prices on materials and crafted items
- Calculating **profit, ROI, cost-to-buy, and break-even sell price** for 64 pre-built crafting strategies across 8 professions
- Showing you exactly **what to buy and how much** to maximize each strategy
- Generating a **shopping list** and optionally buying items directly from the AH via a macro

The strategies come from the Midnight community crafting spreadsheet, covering Alchemy, Blacksmithing, Enchanting, Engineering, Inscription, Jewelcrafting, Leatherworking, and Tailoring.

---

## Installation

1. Copy the `GoldAdvisorMidnight` folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
2. Launch WoW (or type `/reload` if already logged in)
3. Confirm the addon is enabled in the AddOns list at character select

> **Sync script**: The `Sync_Addon.command` file at the repository root automates the copy step via `rsync`. Double-click it in Finder to sync.

---

## First-Time Setup

The first time you use the addon you will need to **scan prices**. Until you do, profit and ROI columns show `—`.

1. Log in and travel to a city with an Auction House
2. Open the Auction House
3. Click **Scan All** in the left panel of the Gold Advisor window
4. Wait for the scan to complete (progress shown in the status bar)
5. Profit and ROI values populate — green = profitable, red = a loss

Cached prices are reused for 10 minutes. You only need a full rescan when you want fresh market data.

---

## Minimap Button

| Action | Result |
|--------|--------|
| **Left-click** | Toggle the main window |
| **Right-click** | Open Settings |
| **Drag** | Reposition around the minimap edge (position saved) |

---

## Main Window

The window opens automatically when you open the Auction House, or via `/gam` or the minimap button. It has three panels.

### Left Panel — Controls

| Control | Description |
|---------|-------------|
| **Mine / All** toggle | Show only strategies for your professions, or all 64 |
| **Profession** dropdown | Sub-filter to a single profession |
| **Fill Qty** | Units to simulate purchasing from the AH order book when pricing reagents. Lower = small-batch cost; higher = reflects true volume depth. Range 10–10,000 |
| **AH Cut %** | Auction House fee applied to output revenue (default 5%) |
| **Mill Own Herbs** | When checked, Inscription ink strategies derive pigment costs from herb prices instead of buying pigments from the AH |
| **Craft Own Ingots** | When checked, Blacksmithing ingot costs are derived from ore + flux instead of AH ingot prices |
| **Craft Own Bolts** | When checked, Tailoring bolt costs are derived from cloth + thread instead of AH bolt prices |
| **Scan All** | Queue every visible strategy item for AH scanning (AH must be open) |
| **Shopping List** | Open the aggregated buy list for all visible strategies |

### Center Panel — Strategy List

Displays all strategies matching the current filter.

| Column | Description |
|--------|-------------|
| ★ | Favourite flag. Favourited strategies sort to the top. Click to toggle |
| **Strategy** | Strategy name |
| **Profession** | Profession |
| **Profit** | Total profit for one full run (gold) |
| **ROI%** | Return on investment. Best ROI sorted first by default |

- **Click a column header** to sort by that column. Click again to reverse.
- **Click a row** to open Strategy Detail in the right panel.
- Rows with `! Missing prices` have one or more un-priced items — open detail and click Scan.

### Right Panel — Best Strategy Card

When no row is selected, the right panel shows the **Best Strategy** — the highest-ROI strategy that exceeds minimum profit and ROI thresholds. Click it to open its detail.

---

## Strategy Detail Panel

Opens in the right panel when you click a strategy row.

### Output

Shows the crafted output item, its AH price, and the expected quantity for the current batch size.

For multi-output strategies (JC prospecting, Enchanting shatters), each output is listed with its individual quantity and net revenue contribution.

### Crafts Editbox

Located in the header of the reagent section. Enter a number and press Enter to scale the entire batch — all quantities, costs, and metrics update immediately. Clear and press Enter to reset to the spreadsheet default.

### Reagent Table

| Column | Description |
|--------|-------------|
| **Item** | Reagent name |
| **Required** | Total quantity needed for this batch |
| **Have** | Current bag + bank count (live read) |
| **Need to Buy** | max(0, Required − Have) |
| **Unit Price** | AH price per item |
| **Total Cost** | Need to Buy × Unit Price |
| **Scan** | Scan this specific item's AH price |

### Metrics

| Metric | Meaning |
|--------|---------|
| **Total Cost** | Sum of all reagent purchase costs |
| **Net Revenue** | Output qty × AH price × (1 − AH cut) |
| **Profit** | Net Revenue − Total Cost |
| **ROI** | (Net Revenue − Total Cost) / Total Cost × 100% |
| **Break-Even Sell** | Minimum sell price to cover all input costs after AH cut. Not shown for multi-output strategies. |

### Buttons

| Button | Action |
|--------|--------|
| **Shopping List** | Open buy list scoped to this strategy |
| **Scan All Items** | Scan every reagent and output for this strategy |
| **→ CraftSim** | Push scanned prices into CraftSim's price database |

---

## Shopping List

Opens from **Shopping List** in the left panel (all visible strategies) or in Strategy Detail (single strategy).

Shows every item you need to buy, with current bag counts and quantities to purchase.

**ARP Export** — copies all item prices in AverageReagentPrice addon format:
```
Tranquility Bloom, Rank 1, 6.70, Rank 2, 16.85, Rank 3, 0.00
```
Select all and copy (Ctrl+A, Ctrl+C) to paste into your comparison spreadsheet.

---

## Quick Buy

Quick Buy lets you purchase each item in your shopping list from the AH using a macro — one hardware event (keypress) per item, satisfying WoW's commodity purchase requirement.

**One-time setup:**
1. Create a macro: `/click GAMQuickBuyBtn`
2. Bind it to a convenient key

**Usage:**
1. Build a shopping list for any strategy
2. Open the Auction House
3. Press your macro key → the addon auto-arms and starts the purchase for the first item
4. Press again when the purchase completes → moves to the next item
5. Repeat until the list empties, or `/gam quickbuy` to stop early

Each keypress = one hardware event = one purchase. The addon does not loop automatically.

---

## Settings

Open via **right-click** on the minimap button, or Escape → Options → AddOns → Gold Advisor Midnight.

### General

| Setting | Description | Default |
|---------|-------------|---------|
| **Scan Delay** | Seconds between AH queries | 1.0 |
| **Debug Verbosity** | 0=off, 1=info, 2=debug, 3=verbose | 1 |
| **Show Minimap Button** | Toggle the minimap button | On |
| **UI Scale** | Scale of addon windows (0.7–1.5) | 1.0 |
| **Rank Policy** | Quality tier preference: Lowest Rank (R1) or Highest Rank (R2+) | Lowest |
| **Fill Qty** | AH order-book simulation depth | 50 |
| **AH Cut %** | AH fee applied to sell revenue | 5% |

### Pricing Sources

| Setting | Options | Description |
|---------|---------|-------------|
| **Pigment Cost Source** | AH / Mill Own Herbs | Price Inscription pigments from AH, or derive from herb costs |
| **Bolt Cost Source** | AH / Craft Own | Price Tailoring bolts from AH, or derive from cloth + thread |
| **Ingot Cost Source** | AH / Craft Own | Price Blacksmithing ingots from AH, or derive from ore + flux |

### Crafting Stats

Per-profession Resourcefulness %, Multicraft %, and spec node bonus fields. These match the columns in the community spreadsheet. Click **Sync from CraftSim** to import your actual in-game stats automatically.

| Profession | Stat fields |
|------------|-------------|
| Inscription (Milling) | Resourcefulness %, Res Node Bonus |
| Inscription (Ink) | Multicraft %, Resourcefulness %, MC Node, Res Node |
| Jewelcrafting | Prospect Res %, Crush Res %, Craft Multi %, Craft Res %, MC Node, Res Node |
| Enchanting | Shatter Res %, Craft Multi %, Craft Res %, MC Node, Res Node |
| Alchemy | Multicraft %, Resourcefulness %, MC Node, Res Node |
| Tailoring | Multicraft %, Resourcefulness %, MC Node, Res Node |
| Blacksmithing | Multicraft %, Resourcefulness %, MC Node, Res Node |
| Leatherworking | Multicraft %, Resourcefulness %, MC Node, Res Node |
| Engineering | Resourcefulness %, Res Node |

### Buttons

| Button | Action |
|--------|--------|
| **Sync from CraftSim** | Import all profession stats from CraftSim |
| **Clear Price Cache** | Wipe all cached AH prices for your realm |
| **Reload Data** | Re-read strategy tables without a full /reload |
| **Open Debug Log** | Open the debug log window |

---

## Debug Log

Open via `/gam log`, the Debug Log button in the main window, or Settings.

- **Clear** — wipe all entries
- **Copy All** — select all log text for Ctrl+C
- **ARP Export** — export all current item prices in ARP format

---

## CraftSim Integration

If CraftSim is installed, the addon detects it automatically at login.

**Stat sync**: Click **Sync from CraftSim** in Settings to import your current Multicraft %, Resourcefulness %, and spec node bonuses into all profession stat fields at once.

**Price push**: The **→ CraftSim** button in Strategy Detail pushes scanned prices for that strategy's items into CraftSim's price override database, so CraftSim uses the same market data as Gold Advisor.

If CraftSim is not installed, both features are silently unavailable — no errors occur.

---

## Slash Commands

| Command | Action |
|---------|--------|
| `/gam` | Toggle main window |
| `/gam log` | Toggle debug log |
| `/gam scan` | Queue all items for AH scan (AH must be open) |
| `/gam clearcache` | Wipe price cache for current realm |
| `/gam reload` | Reload strategy data |
| `/gam quickbuy` | Stop / disarm Quick Buy queue |
| `/gam create` | Open Strategy Creator |
| `/gam ids` | Dump tracked item IDs to debug log |
| `/goldadvisor` | Same as `/gam` |

---

## Recommended Workflow

### Daily scan routine

1. Log in and open the Auction House
2. Click **Scan All** in the left panel
3. Wait for the scan to finish (status bar clears)
4. Sort by **ROI%** or **Profit** to find today's best opportunities
5. Use the **Mine** toggle and **Profession** dropdown to narrow the list

### Evaluating a strategy

1. Click a row to open Strategy Detail
2. Check the **Have** column — live bag + bank read
3. Review **Need to Buy** and **Total Cost**
4. If any prices show `—`, click **Scan All Items**
5. Adjust **Crafts** to scale up or down — all metrics update immediately

### Buying materials

1. Click **Shopping List** in Strategy Detail or the left panel
2. Use **ARP Export** to copy prices for your spreadsheet
3. Optionally use **Quick Buy** to purchase items directly from the AH via macro

### Using Mill Own Herbs (Inscription)

Enable **Mill Own Herbs** in the left panel when herbs are cheaper than pigments on the AH. Ink strategies will derive pigment cost from herb prices, which can swing Sienna Ink and Munsell Ink from losses to strong profits depending on the market.

### Setting your crafting stats

1. Open Settings (right-click minimap button)
2. Click **Sync from CraftSim** (if installed), or enter your Res%/Multi%/node values manually
3. Click **Apply & Close** — all strategy metrics recalculate immediately

---

## Tips & FAQ

**Q: Why is profit showing a loss when I know I can sell for more?**
A: Check that the output item has a price. If it shows `—`, open Strategy Detail and click **Scan All Items**.

**Q: "Have" shows 0 but I have the item in my bank.**
A: Visit your bank this session. The bank count updates when you open the bank window.

**Q: The scan seems stuck.**
A: The AH throttles queries — the addon waits between requests. If genuinely stuck, check `/gam log` for timeout messages and try Scan All again.

**Q: Profits look different from the community spreadsheet.**
A: Verify your crafting stats in Settings match the spreadsheet assumptions (the defaults match the spreadsheet baseline). Also check whether **Mill Own Herbs** is on — it significantly changes ink strategy ROI.

**Q: How do I reset everything and start fresh?**
A: `/gam clearcache` wipes prices. To also wipe qty overrides and favourites, delete the `GoldAdvisorMidnightDB` entry from your SavedVariables file (`WTF/Account/.../SavedVariables/`) and `/reload`.

**Q: Can I use this without CraftSim?**
A: Yes — CraftSim is fully optional. Every feature works without it.

**Q: What is Quick Buy and do I need it?**
A: Quick Buy is optional. It lets you purchase shopping list items from the AH via a macro key. Create a macro with `/click GAMQuickBuyBtn`, bind it to a key, build a shopping list, then press the key once per item — it auto-arms on first press.

---

## Known Limitations

- **Price freshness**: Cached prices expire after 10 minutes. Rescan at the start of each AH session for best accuracy.
- **Single realm**: Price cache is scoped to your realm+faction. Multiple realms each have independent caches.
- **Mill Own Herbs yield constant**: The herb → pigment conversion uses a baked yield constant (1.53 pigments/herb at the addon's baseline stat level). If your stats differ significantly, derived pigment costs may be slightly off.
- **JC multi-output**: Break-Even Sell is not shown for prospecting/shattering strategies since there is no single output unit to price.

---

*Gold Advisor Midnight v1.4.3 — WoW Midnight (Interface 120001)*
