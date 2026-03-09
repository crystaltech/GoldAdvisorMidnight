# GoldAdvisorMidnight — Session Memory

## Project
- WoW Midnight AddOn. Lua 5.1, Blizzard AH APIs.
- Addon name: **GoldAdvisorMidnight**
- Current version: **1.2.0-RC3**
- Repo: `git@github.com:crystaltech/GoldAdvisorMidnight.git` (private)
- Working directory: `/Users/terry.pike/Desktop/Coding Projects/GoldAdvisorAddon/`

## Repo Layout (post-RC3 reorganization)
- `source/GoldAdvisorMidnight/` — active addon source (protected, do not touch during cleanup)
- `releases/` — packaged zip artifacts (e.g. `GoldAdvisorMidnight-v1.2.0-RC3.zip`)
- `scripts/` — `sync_memory_mac.sh`, `sync_memory_win.ps1`
- `references/` — WoW API docs, Ace3 libs, working addons, WIP/broken addons
- `memory/` — this file + snapshots (tracked in git via `.gitignore` exception)
- `Package_Addon.command` — builds from `source/` → `releases/`
- `Sync_Addon.command` — syncs addon to WoW install

## Load Order
Constants → Locale → Log → Core → Minimap → Settings → Pricing → AHScan → Importer → Data/* → CraftSimBridge → UI/*

## Key Architecture
- `GAM.AHScan` — queue-based AH scanner in AHScan.lua
- `GAM.Pricing` — price storage/lookup in Pricing.lua
- `GAM.C` — constants in Constants.lua (SCAN_DELAY=3, RESULT_WAIT=10, MAX_RETRY=5)
- Core.lua wires events: COMMODITY_SEARCH_RESULTS_UPDATED, ITEM_SEARCH_RESULTS_UPDATED, AUCTION_HOUSE_BROWSE_RESULTS_UPDATED

## Browse Fallback Fix (applied)
Root cause: `SendSearchQuery(MakeItemKey(id,0,0,0))` returns 0 commodity rows for quality-tier reagents.
Fix in AHScan.lua:
- `EnqueuePriceScan` now accepts `(itemID, callback, itemName, noFallback)`
- `entry._gen` generation counter lets ProcessNextInQueue safety timeout be superseded by browse fallback
- `OnCommodityResults`: after retries exhausted → if `browseFallbackUsed=false` → escalate to browse
- `OnBrowseResults`: handles `isBrowseFallback=true` path — updates `itemKeyCache` with FULL itemKey from browse results (the real fix), re-queues scans
- `OnItemResults`: stray-result guard added (checks itemKey.itemID == pendingEntry.itemID)
- `tryQueueItem` in both QueueAllStratItems/QueueStratListItems passes `item.name` to EnqueuePriceScan
