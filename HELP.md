# Gold Advisor Midnight — User Guide

**Version 1.0.2 · WoW Midnight (12.0.1)**

---

## Table of Contents

1. [What This Addon Does](#what-this-addon-does)
2. [Installation](#installation)
3. [First-Time Setup](#first-time-setup)
4. [Minimap Button](#minimap-button)
5. [Main Window](#main-window)
6. [Strategy Detail Panel](#strategy-detail-panel)
7. [Shopping List](#shopping-list)
8. [Settings](#settings)
9. [Debug Log](#debug-log)
10. [CraftSim Integration](#craftsim-integration)
11. [Slash Commands](#slash-commands)
12. [Recommended Workflow](#recommended-workflow)
13. [Tips & FAQ](#tips--faq)
14. [Known Limitations](#known-limitations)

---

## What This Addon Does

Gold Advisor Midnight helps you find profitable crafting opportunities by:

- Scanning the **Auction House** for live prices on materials and crafted items
- Calculating **profit, ROI, cost to buy, and break-even sell price** for 62 pre-built crafting strategies across 8 professions
- Showing you exactly **what to buy and how much** to maximize each strategy
- Generating a **shopping list** of everything you need to purchase

The strategies come from a curated spreadsheet covering Alchemy, Blacksmithing, Enchanting, Engineering, Inscription, Jewelcrafting, Leatherworking, and Tailoring.

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

The first time you use the addon you will need to **scan prices**. Until you do, profit and ROI columns show `—` because no market data exists.

**Steps:**

1. Log in and travel to a city with an Auction House
2. Open the Auction House
3. The Gold Advisor window opens automatically
4. Click **Scan All** — the addon will query the AH for every item across all strategies
5. Wait for the scan to complete (the progress bar will disappear when done)
6. Profit and ROI values will populate — green = profitable, red = a loss

Scanning 63 strategies takes a few minutes due to AH throttling. You only need to do a full scan when you want fresh prices; cached prices are reused for 10 minutes.

---

## Minimap Button

A small coin icon appears on the edge of your minimap.

| Action | Result |
|--------|--------|
| **Left-click** | Toggle the main strategy window |
| **Right-click** | Open the Settings panel |
| **Drag** | Reposition the button around the minimap edge |

The button position is saved and restored after each login.

If you accidentally hide the minimap button, you can restore it via **Settings → Show Minimap Button**.

---

## Main Window

Opens automatically when you open the Auction House, or via `/gam` or the minimap button.

### Layout

```
┌──────────────────────────────────────────────────┐
│  Gold Advisor Midnight              [X]           │
│  Profession: [All ▾]                              │
│──────────────────────────────────────────────────│
│  ★ Strategy         Profession   Profit    ROI%  │
│  ──────────────────────────────────────────────  │
│  ★ Composite Flora  Alchemy      45g 20s   12.3% │
│  ☆ Goblin Grenade   Engineering  -8g 00s   -2.1% │
│  ...                                             │
│──────────────────────────────────────────────────│
│  63 strategies   [Debug Log] [Scan All] [Close]  │
└──────────────────────────────────────────────────┘
```

### Controls

**Profession filter dropdown** — filters the list to one profession. Select "All" to see everything.

**Column headers** — click any header to sort by that column. Click again to reverse the sort order.
- ★ Strategy — alphabetical by strategy name
- Profession — alphabetical by profession
- Profit — highest profit first (default)
- ROI% — best return on investment first

**Rows**
- **Single-click** a row → opens the Strategy Detail panel for that strategy
- **Double-click** a row → toggles the ★ favourite flag. Favourited strategies always sort to the top of the list.

**Missing prices indicator** — `! Missing prices` appears on rows where one or more items have no cached price. Click that strategy and use its Scan buttons to fetch the missing data.

**Scan All button** — queues every item visible in the current filtered list for AH scanning. The AH must be open. A progress bar appears while scanning.

**Stop Scan button** — replaces Scan All while a scan is running. Clicking it halts the current scan immediately.

**Debug Log button** — opens the debug log window.

**Close button** — hides the window. The window also closes when you close the Auction House.

---

## Strategy Detail Panel

Opens to the right of the main window when you click a strategy row.

### Header

Shows the strategy name, profession, and any notes (e.g. "15% Res, 30% Multi" — these are the expected chance stats from the spreadsheet).

### Output Section

Shows the crafted item you will produce:
- **Item name**
- **Current AH price** (from price cache)
- **Expected quantity** — how many you'll get from one run at the current batch size
- **Scan button** — scans AH price for the output item only

For Jewelcrafting prospecting strategies, the output section shows the primary yield (ore → gems). All gem outputs contribute to the profit calculation even if only the primary is shown here.

### Reagent Table

| Column | Description |
|--------|-------------|
| **Item** | Reagent name |
| **Qty/Craft** | How many you need for this batch size. **Editable** — type a number and press Enter to override |
| **In Bags** | How many you currently have across bags + bank (live read, not saved) |
| **Need to Buy** | Max(0, Qty/Craft − In Bags). What you actually need to purchase |
| **Unit Price** | Current AH price per item |
| **Total Cost** | Need to Buy × Unit Price |
| **Scan** | Scan AH price for this specific item |

**Editing Qty/Craft:** Type a new quantity and press Enter (or click away). The batch size will be inferred from your override and all other columns update automatically — including the output quantity and all metrics. To reset to the spreadsheet default, clear the field and press Enter.

### Metrics Section

| Metric | Meaning |
|--------|---------|
| **Total Cost** | Sum of all reagent purchase costs |
| **Net Revenue** | Expected sell price × output quantity × 0.95 (AH cut applied) |
| **Profit** | Net Revenue − Total Cost. Green = profit, red = loss |
| **ROI** | (Profit / Total Cost) × 100%. Higher is better |
| **Break-Even Sell** | The minimum sell price needed to break even after the AH cut |

### Bottom Buttons

**Shopping List** — opens the Shopping List panel showing only this strategy's buy requirements.

**→ CraftSim** — pushes all scanned prices for this strategy's items into CraftSim's global price override database. Useful if you use CraftSim for crafting decisions and want it to use the same prices GAM scanned. Requires CraftSim to be installed and loaded.

**Scan All Items** — scans every reagent and output item for this strategy in one click. The AH must be open.

---

## Shopping List

Opens from the **Shopping List** button in the Strategy Detail panel.

Shows every reagent you need to purchase for the selected strategy:

| Column | Description |
|--------|-------------|
| **Item** | Reagent name |
| **Have** | Current bag + bank count |
| **Need to Buy** | Highlighted red if > 0 |

Items with nothing to buy (Have ≥ Qty/Craft) are shown in green with a 0 in the Need column.

**Copy button** — opens a small text popup with the shopping list pre-formatted:
```
-- Gold Advisor Midnight Shopping List --
Item | Have | Need
Tranquility Bloom | 240 | 5760
Argentleaf | 0 | 4000
...
```
Select all and copy (Ctrl+A, Ctrl+C) to paste into a note, Auctionator search list, etc.

---

## Settings

Open via **right-click** on the minimap button, or via the Blizzard Settings UI (Escape → Options → AddOns → Gold Advisor Midnight).

| Setting | Description | Default |
|---------|-------------|---------|
| **Active Patch** | Which patch tag to use for strategy data | midnight-1 |
| **Scan Delay (sec)** | Seconds between AH queries. Increase if you get throttle warnings. Decrease for faster scans (may cause throttling) | 3.0 |
| **Debug Verbosity** | 0 = off, 1 = info, 2 = debug, 3 = verbose. Use 0 for normal play, 2–3 only when troubleshooting | 1 |
| **Show Minimap Button** | Toggle the minimap coin button on/off | On |
| **Rank Selection Policy** | How to pick between quality tiers when an item has multiple ranks. **Lowest Rank** = cheapest tier (Q1), **Highest Rank** = best tier (Q2+), **Manual** = use highest as fallback | Lowest Rank |

**Reload Data** — re-reads the strategy tables from SavedVars. Use this if you edited `StratsManual.lua` and want the changes to take effect without a full `/reload`.

**Clear Price Cache** — wipes all cached AH prices for your realm. Useful if prices look obviously wrong. You'll need to run Scan All again after clearing.

**Open Debug Log** — opens the debug log window.

Apply your changes by clicking **Apply & Close**. Changes are also applied when you close the panel.

---

## Debug Log

Open via `/gam log`, the **Debug Log** button in the main window, or Settings.

A scrollable window showing all log entries from the current session. Useful for diagnosing scan failures or unexpected behaviour.

**Clear** — wipes all log entries.

**Copy All** — selects all log text so you can Ctrl+C to copy and paste it elsewhere (e.g. a bug report).

**Pause / Resume** — pauses the live feed so the log stops scrolling while you read it. New entries are still recorded in the buffer; they appear when you click Resume.

---

## CraftSim Integration

If **CraftSim** is installed and loaded, Gold Advisor Midnight automatically detects it at login and logs:
```
CraftSimBridge: CraftSim detected — integration active.
```

**What integrates:**
- The **→ CraftSim** button in Strategy Detail pushes all scanned prices for that strategy's items into CraftSim's price override database. CraftSim will then use those prices for its own profit calculations.

**What does NOT auto-sync:**
- Prices are not pushed automatically — you must click the button per strategy

If CraftSim is not installed, the button still appears but pressing it prints:
```
[GAM] CraftSim push failed: CraftSim not loaded
```
No errors will occur; the button is always safe to use.

---

## Slash Commands

| Command | Action |
|---------|--------|
| `/gam` | Toggle the main strategy window |
| `/gam log` | Toggle the debug log window |
| `/gam scan` | Queue all strategy items for AH scanning (AH must be open) |
| `/gam clearcache` | Wipe the price cache for the current realm |
| `/gam reload` | Reload strategy data (use after editing StratsManual.lua) |
| `/goldadvisor` | Same as `/gam` |

---

## Recommended Workflow

### Daily scan routine

1. Log in and open the **Auction House**
2. The Gold Advisor window opens automatically
3. If your prices are older than ~10 minutes (stale), click **Scan All**
4. Wait for the scan bar to disappear — all items are now priced
5. Sort by **Profit** or **ROI%** to find today's best opportunities
6. Filter by your crafting profession using the **Profession** dropdown

### Evaluating a strategy

1. Click a strategy row to open the **Strategy Detail** panel
2. Review the **In Bags** column — it shows what you already have
3. Check the **Need to Buy** column — this is your shopping list
4. If any items show `—` in the price column, click their **Scan** button (AH must be open)
5. Verify the **Profit** and **ROI** make sense for the batch size
6. If you want to scale up or down, edit the **Qty/Craft** field for any one reagent — all other quantities and outputs scale automatically

### Shopping for materials

1. In Strategy Detail, click **Shopping List**
2. Use the **Copy** button to grab the list as text
3. Paste into Auctionator, TradeSkillMaster, or a note

### Pushing prices to CraftSim

1. Run a scan (either Scan All Items in the detail panel, or Scan All from the main window)
2. Once prices are populated, click **→ CraftSim**
3. A confirmation message prints: `[GAM] Pushed N price(s) to CraftSim`
4. Switch to CraftSim — its profit calculations now use your freshly scanned prices

### Setting your batch size

The **Qty/Craft** column defaults to the spreadsheet's recommended starting amount (typically 2,000–5,000 units). To customise:

1. Open Strategy Detail for any strategy
2. Click into the **Qty/Craft** cell of any reagent
3. Type the amount you want to craft/process, then press Enter
4. All other reagent quantities and the output quantity update to match

Your custom quantities are saved per strategy per character session and persist across `/reload`.

### Finding items with no prices

Items that have never been scanned show `—` in the price column and `! Missing prices` in the main list. To fix:

1. Open Strategy Detail for the affected strategy
2. Click **Scan All Items** (AH must be open)
3. Once complete, all prices will appear

If an item still shows `—` after a scan, it may not be listed on the AH on your realm, or it may need a name scan to discover its itemID first. The scan will attempt both automatically.

---

## Tips & FAQ

**Q: Why is profit showing as a loss when I know I can sell it for more?**
A: Check the output item's price in the detail panel. If it's `—` or lower than your actual sell price, either scan the output item or set a price override in Settings (or edit `StratsManual.lua`).

**Q: Why is "In Bags" showing 0 when I have the item in my bank?**
A: The count includes both bags and bank but requires the bank to have been opened this session. Visit your bank and reopen the detail panel to refresh.

**Q: The scan seems stuck / the progress bar isn't moving.**
A: The AH throttles queries. The addon waits up to 10 seconds between queries. If it's truly stuck, click **Stop Scan** and try again. Check `/gam log` for timeout or throttle messages.

**Q: I closed the main window and now I can't find it.**
A: Left-click the minimap coin button, or type `/gam`. The window only opens automatically when the AH is open.

**Q: Profits look wildly different from the community spreadsheet.**
A: Older copies of the spreadsheet had a Jewelcrafting AH-cut formula bug. The March 10, 2026 workbook fixes that, and the addon is aligned to the corrected sheet values.

**Q: How do I reset everything and start fresh?**
A: `/gam clearcache` wipes prices. To also wipe your qty overrides and favorites, delete the `GoldAdvisorMidnightDB` entry from your SavedVariables file (in `WTF/Account/...`) and `/reload`.

**Q: Can I use this without CraftSim?**
A: Yes. CraftSim is completely optional. Every feature works without it. The only CraftSim-specific feature is the **→ CraftSim** button.

---

## Known Limitations

- **Item IDs**: Most raw materials are pre-mapped. If a crafted item or gem shows no price, it likely needs a name scan (clicking Scan will attempt this automatically).
- **JC prospecting display**: The output section shows the primary output item only. Revenue is calculated correctly from all gem yields; it's just not shown line-by-line in the panel.
- **Spreadsheet version matters**: Older community spreadsheet copies had Jewelcrafting formula issues. Gold Advisor Midnight is aligned to the corrected March 10, 2026 workbook.
- **Price freshness**: Cached prices expire after 10 minutes. Run Scan All at the start of each AH session for best accuracy.
- **Single realm**: Price cache is scoped to your realm+faction. If you play multiple realms, each has its own cache.

---

*Gold Advisor Midnight v1.0.2 — WoW Midnight (Interface 120001)*
