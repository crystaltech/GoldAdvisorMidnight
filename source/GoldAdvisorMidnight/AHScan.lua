-- GoldAdvisorMidnight/AHScan.lua
-- C_AuctionHouse scanning: queue, throttle, commodity + item scans,
-- name→rank discovery via browse query, price caching, progress tracking.
-- Module: GAM.AHScan

local ADDON_NAME, GAM = ...
local AHScan = {}
GAM.AHScan = AHScan

-- ===== Configuration (hot-swappable via SetScanDelay) =====
local SCAN_DELAY          = GAM.C.SCAN_DELAY
local RESULT_WAIT         = GAM.C.RESULT_WAIT
local RESULT_RETRY_DELAY  = GAM.C.RESULT_RETRY_DELAY
local MAX_RETRY           = GAM.C.MAX_RETRY
local EVENT_PROCESS_DELAY = GAM.C.EVENT_PROCESS_DELAY

function AHScan.SetScanDelay(d)
    SCAN_DELAY = d or GAM.C.SCAN_DELAY
end

-- ===== State =====
local scanning          = false
local scanQueue         = {}
local queueHead         = 1     -- O(1) dequeue: advance head instead of table.remove
local pendingEntry      = nil   -- { itemID, callback, isNameScan, name, patchTag }
local waitingForResults = false
local lastQueryTime     = 0
local scanSuccessCount  = 0
local scanFailCount     = 0
local failedQueue       = {}
local isRetryPass       = false

-- Progress tracking
local totalEver   = 0   -- total items ever enqueued in this scan session
local doneCount   = 0   -- items completed (success or fail)

local progressCallback = nil  -- fn(done, total, isComplete)

AHScan._pendingResume = false

-- ===== Progress API =====
function AHScan.SetProgressCallback(fn)
    progressCallback = fn
end

local function FireProgress(isComplete)
    if not isComplete and not scanning then
        return
    end
    if progressCallback then
        -- During retry pass doneCount can exceed totalEver; clamp for display
        progressCallback(math.min(doneCount, totalEver), totalEver, isComplete or false)
    end
end

-- ===== ItemKey cache =====
local itemKeyCache = {}

local function GetCachedItemKey(itemID)
    if not itemID or itemID == 0 then return nil end
    if itemKeyCache[itemID] then return itemKeyCache[itemID] end
    -- Lazy-load from persisted DB (safety net; normally pre-warmed by PreWarmCache on AH open)
    local saved = GoldAdvisorMidnightDB
        and GoldAdvisorMidnightDB.itemKeyDB
        and GoldAdvisorMidnightDB.itemKeyDB[itemID]
    if saved then
        local key = C_AuctionHouse.MakeItemKey(
            itemID, saved.itemLevel or 0, saved.itemSuffix or 0, saved.battlePetSpeciesID or 0)
        itemKeyCache[itemID] = key
        return key
    end
    local key = C_AuctionHouse.MakeItemKey(itemID, 0, 0, 0)
    itemKeyCache[itemID] = key
    return key
end

-- Pre-warm session itemKey cache from persisted DB.
-- Called from Core.lua on AUCTION_HOUSE_SHOW. Ensures all known full itemKeys
-- are in the fast session cache before scanning begins.
function AHScan.PreWarmCache()
    local ikdb = GoldAdvisorMidnightDB and GoldAdvisorMidnightDB.itemKeyDB
    if not ikdb then return end
    local n = 0
    for id, saved in pairs(ikdb) do
        if not itemKeyCache[id] then
            itemKeyCache[id] = C_AuctionHouse.MakeItemKey(
                id, saved.itemLevel or 0, saved.itemSuffix or 0, saved.battlePetSpeciesID or 0)
            n = n + 1
        end
    end
    if n > 0 then
        GAM.Log.Debug("AHScan: pre-warmed %d itemKeys from DB", n)
    end
end

-- ===== Runtime caches (session only) =====
local commodityCache = {}   -- R1 commodity results
local itemCache      = {}   -- R2/quality item results

function AHScan.GetCachedResults(itemID)
    return commodityCache[itemID]
end

-- ===== Price computation =====

local function ExpandResultsToUnitPrices(results, targetQty)
    local out = {}
    if not results or #results == 0 then return out end
    table.sort(results, function(a, b) return a.unitPrice < b.unitPrice end)
    local collected = 0
    for _, r in ipairs(results) do
        local take = math.min(r.quantity or 0, targetQty - collected)
        if take <= 0 then break end
        for _ = 1, take do out[#out + 1] = r.unitPrice end
        collected = collected + take
        if collected >= targetQty then break end
    end
    return out
end

-- ARP-style percentage trim: fill to targetQty from cheapest listings first,
-- then drop the top TRIM_PCT% most expensive of the filled units.
-- Matches ARP Tracker default (Trim: 2) and is more predictable than a
-- median-multiple approach across both deep and thin markets.
local function ComputeStatsFromResults(results, targetQty)
    if not results or #results == 0 then return nil end

    local units = ExpandResultsToUnitPrices(results, targetQty)
    local n = #units
    if n == 0 then return nil end

    -- Sort descending so the most expensive units are at the front
    table.sort(units, function(a, b) return a > b end)

    local trimPct   = GAM.C.TRIM_PCT or 2
    local trimCount = math.floor(n * (trimPct / 100))
    if trimCount >= n then trimCount = n - 1 end  -- always keep at least 1

    -- After descending sort: cheapest is at index n, most expensive at index 1.
    local sum, minP, maxP = 0, units[n], units[n]
    for i = trimCount + 1, n do
        local p = units[i]
        sum = sum + p
        if p < minP then minP = p end
        if p > maxP then maxP = p end
    end
    local kept = n - trimCount
    return sum / kept, minP, maxP, kept
end

-- ComputePriceForQty: average unit price for `requiredQty` units using live
-- session caches (commodity → item) then persisted raw as fallback.
-- Returns avg in copper, or nil if no raw data is available.
function AHScan.ComputePriceForQty(itemID, requiredQty)
    if not itemID or not requiredQty or requiredQty <= 0 then return nil end
    -- 1. Live commodity session cache (R1 items)
    local cached = commodityCache[itemID]
    if cached and cached.prices and #cached.prices > 0 then
        return ComputeStatsFromResults(cached.prices, requiredQty)
    end
    -- 2. Live item session cache (R2 quality items)
    local icached = itemCache[itemID]
    if icached and icached.prices and #icached.prices > 0 then
        return ComputeStatsFromResults(icached.prices, requiredQty)
    end
    -- 3. Persisted raw from last session (via Pricing module)
    if GAM.Pricing and GAM.Pricing.GetRawCache then
        local raw = GAM.Pricing.GetRawCache(itemID)
        if raw and #raw > 0 then
            return ComputeStatsFromResults(raw, requiredQty)
        end
    end
    return nil
end

-- ===== Commodity result reader =====

local function ReadCommodityResults(itemID, targetQty)
    if targetQty == nil then
        -- Use configured fill qty.
        -- An explicit caller-supplied targetQty (non-nil) is always honoured unchanged.
        local opts = GAM.db and GAM.db.options
        targetQty = (opts and opts.shallowFillQty) or GAM.C.DEFAULT_FILL_QTY
    end
    local numResults = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    if not numResults or numResults == 0 then return nil end
    local raw = {}
    for i = 1, numResults do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if not r then break end
        raw[#raw + 1] = { unitPrice = r.unitPrice, quantity = r.quantity or 0 }
    end
    commodityCache[itemID] = { prices = raw, ts = time() }
    return ComputeStatsFromResults(raw, targetQty)
end

-- ===== Queue helpers =====

-- Internal: add a price-scan entry (de-dup by itemID).
-- itemName  (optional) — stored so OnCommodityResults can issue a browse fallback
--                        without a separate GetItemInfo call.
-- noFallback (optional) — pre-marks browseFallbackUsed=true to prevent a second
--                        browse escalation when re-queued from OnBrowseResults.
local priceScanQueued = {}  -- [itemID] = true; reset at StartScan
local function EnqueuePriceScan(itemID, callback, itemName, noFallback)
    if not itemID or itemID == 0 then return end
    if priceScanQueued[itemID] then return end
    priceScanQueued[itemID] = true
    totalEver = totalEver + 1
    scanQueue[#scanQueue + 1] = {
        itemID             = itemID,
        callback           = callback,
        isNameScan         = false,
        name               = itemName,      -- browse fallback search term
        browseFallbackUsed = noFallback or nil, -- true → skip browse escalation
        -- _gen              assigned lazily when browse fallback is triggered
    }
end

-- Internal: add a name-scan entry (de-dup by name)
local nameScanQueued = {}  -- [name] = true; reset at StartScan
local function EnqueueNameScan(itemName, patchTag, callback)
    if not itemName then return end
    if nameScanQueued[itemName] then return end
    nameScanQueued[itemName] = true
    totalEver = totalEver + 1
    scanQueue[#scanQueue + 1] = {
        itemID     = 0,
        name       = itemName,
        patchTag   = patchTag or GAM.C.DEFAULT_PATCH,
        callback   = callback,
        isNameScan = true,
    }
end

-- ===== Query sender: price scan =====
-- Midnight removed SendCommoditySearchQuery; SendSearchQuery handles all item types.
-- Blizzard fires COMMODITY_SEARCH_RESULTS_UPDATED for commodities and
-- ITEM_SEARCH_RESULTS_UPDATED for non-commodities — both handlers wired in Core.

local function SendPriceQuery(entry)
    local itemKey = GetCachedItemKey(entry.itemID)
    if not itemKey then
        GAM.Log.Warn("AHScan: no itemKey for itemID=%d", entry.itemID)
        return false
    end
    local ok = pcall(C_AuctionHouse.SendSearchQuery, itemKey, {}, false)
    if ok then
        lastQueryTime = GetTime()
        GAM.Log.Debug("AHScan: query itemID=%d", entry.itemID)
    else
        GAM.Log.Warn("AHScan: SendSearchQuery failed for itemID=%d", entry.itemID)
    end
    return ok
end

-- ===== Query sender: name/browse scan =====

local function SendBrowseQuery(entry)
    local ok = pcall(function()
        C_AuctionHouse.SendBrowseQuery({
            searchString     = entry.name,
            minLevel         = 0,
            maxLevel         = 0,
            filters          = {},
            itemClassFilters = {},
            sorts            = {},
        })
    end)
    if ok then
        lastQueryTime = GetTime()
        GAM.Log.Debug("AHScan: browse query '%s'", entry.name)
    else
        GAM.Log.Warn("AHScan: SendBrowseQuery failed for '%s'", entry.name)
    end
    return ok
end

-- ===== Ticker / queue processor =====
local ticker

local function OnItemFail(entry)
    scanFailCount = scanFailCount + 1
    doneCount     = doneCount + 1
    FireProgress(false)
end

local function ProcessNextInQueue()
    if not scanning then return end
    if not GAM.ahOpen then
        AHScan._pendingResume = true
        scanning = false
        if ticker then ticker:Cancel(); ticker = nil end
        GAM.Log.Info(GAM.L["SCAN_AH_CLOSED"])
        return
    end
    if waitingForResults then return end

    if queueHead > #scanQueue then
        -- Retry pass once
        if not isRetryPass and #failedQueue > 0 then
            isRetryPass = true
            scanQueue   = failedQueue
            queueHead   = 1
            failedQueue = {}
            GAM.Log.Info("AHScan: retry pass, %d items", #scanQueue)
            return
        end
        -- Done
        scanning    = false
        isRetryPass = false
        if ticker then ticker:Cancel(); ticker = nil end
        GAM.Log.Info(GAM.L["SCAN_COMPLETE"], scanSuccessCount, scanFailCount)
        FireProgress(true)
        local win = GAM.GetActiveMainWindow and GAM:GetActiveMainWindow() or (GAM.UI and GAM.UI.MainWindow)
        if win and win.OnScanComplete then
            win.OnScanComplete()
        end
        return
    end

    local now = GetTime()
    if (now - lastQueryTime) < SCAN_DELAY then return end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        GAM.Log.Debug(GAM.L["SCAN_THROTTLED"])
        return
    end

    local entry = scanQueue[queueHead]
    queueHead         = queueHead + 1
    pendingEntry      = entry
    waitingForResults = true

    if entry.isNameScan then
        local sent = SendBrowseQuery(entry)
        if not sent then
            waitingForResults = false
            pendingEntry      = nil
            OnItemFail(entry)
            return
        end
    else
        local sent = SendPriceQuery(entry)
        if not sent then
            waitingForResults = false
            pendingEntry      = nil
            failedQueue[#failedQueue + 1] = entry
            OnItemFail(entry)
            return
        end
    end

    -- Safety timeout (generation-aware).
    -- When OnCommodityResults escalates to a browse fallback it increments
    -- entry._gen, which causes this closure to become a no-op.  The fallback
    -- schedules its own fresh RESULT_WAIT timer with the new generation value.
    local entryGen         = entry._gen or 0
    local capturedRetry    = isRetryPass  -- capture now; avoids double-counting
    C_Timer.After(RESULT_WAIT, function()
        if waitingForResults and pendingEntry == entry
                and (entry._gen or 0) == entryGen then
            GAM.Log.Warn("AHScan: timeout for %s",
                entry.isNameScan and ("'"..entry.name.."'") or
                (entry.name
                    and string.format("'%s' (itemID=%d)", entry.name, entry.itemID)
                    or  ("itemID="..entry.itemID)))
            waitingForResults = false
            pendingEntry      = nil
            if not entry.isNameScan then
                failedQueue[#failedQueue + 1] = entry
            end
            if capturedRetry then
                -- Retry pass: permanent failure — count it.
                OnItemFail(entry)
            else
                -- First pass: item is queued for retry, not yet permanently failed.
                -- Advance progress so the bar moves, but don't count as a failure.
                doneCount = doneCount + 1
                FireProgress(false)
            end
        end
    end)
end

-- ===== Event callbacks (called from Core.lua) =====

-- COMMODITY_SEARCH_RESULTS_UPDATED → price data for a commodity itemID
function AHScan.OnCommodityResults(itemID)
    if not waitingForResults then return end
    if not pendingEntry or pendingEntry.isNameScan then return end
    if pendingEntry.itemID ~= itemID then return end

    local entry = pendingEntry

    C_Timer.After(EVENT_PROCESS_DELAY, function()
        local function TryRead(attemptsLeft)
            local avg, minP, maxP, count = ReadCommodityResults(entry.itemID)
            if avg then
                GAM.Pricing.StorePrice(entry.itemID, avg)
                if entry.callback then
                    pcall(entry.callback, entry.itemID, avg, minP, maxP, count)
                end
                scanSuccessCount  = scanSuccessCount + 1
                doneCount         = doneCount + 1
                waitingForResults = false
                pendingEntry      = nil
                GAM.Log.Debug("AHScan: price itemID=%d avg=%d", entry.itemID, math.floor(avg))
                FireProgress(false)
            elseif attemptsLeft > 0 then
                C_Timer.After(RESULT_RETRY_DELAY, function() TryRead(attemptsLeft - 1) end)
            else
                -- ── All retries exhausted with zero commodity rows. ──
                -- Attempt a ONE-TIME browse fallback (if not already used).
                -- The browse returns the actual itemKey as indexed in the AH,
                -- which may have non-zero quality/suffix fields that
                -- MakeItemKey(id,0,0,0) strips — that is the root cause of
                -- zero-row responses for quality-tier commodities.
                if not entry.browseFallbackUsed then
                    entry.browseFallbackUsed = true
                    entry.isBrowseFallback   = true

                    -- Resolve item name for the browse query.
                    local name = entry.name
                    if not name then
                        -- GetItemInfo returns name as its first value (sync, uses client cache).
                        name = (GetItemInfo(entry.itemID))
                    end

                    if name then
                        entry.name = name
                        GAM.Log.Info(
                            "AHScan: zero commodity rows itemID=%d → browse fallback '%s'",
                            entry.itemID, name)

                        -- Bump generation so the original ProcessNextInQueue safety
                        -- timeout becomes a no-op (see entryGen capture there).
                        -- A fresh RESULT_WAIT timer is scheduled below.
                        entry._gen = (entry._gen or 0) + 1
                        local gen  = entry._gen
                        C_Timer.After(RESULT_WAIT, function()
                            if waitingForResults and pendingEntry == entry
                                    and (entry._gen or 0) == gen then
                                GAM.Log.Warn(
                                    "AHScan: browse fallback timeout itemID=%d '%s'",
                                    entry.itemID, entry.name)
                                waitingForResults = false
                                pendingEntry      = nil
                                failedQueue[#failedQueue + 1] = entry
                                OnItemFail(entry)
                            end
                        end)

                        -- Honour SCAN_DELAY pacing before sending the browse query.
                        -- Use elapsed-aware wait: by the time TryRead retries exhaust
                        -- (~2.8s), most of SCAN_DELAY has already passed.
                        local browseWait = math.max(0, SCAN_DELAY - (GetTime() - lastQueryTime))
                        C_Timer.After(browseWait, function()
                            -- Guards: entry could have been cancelled by StopScan/AHClosed.
                            if not waitingForResults or pendingEntry ~= entry then return end
                            if not GAM.ahOpen then
                                waitingForResults = false
                                pendingEntry      = nil
                                OnItemFail(entry)
                                return
                            end
                            if not C_AuctionHouse.IsThrottledMessageSystemReady() then
                                -- Throttled — put in failedQueue for the retry pass.
                                GAM.Log.Debug(
                                    "AHScan: throttled during browse fallback itemID=%d",
                                    entry.itemID)
                                waitingForResults = false
                                pendingEntry      = nil
                                failedQueue[#failedQueue + 1] = entry
                                OnItemFail(entry)
                                return
                            end
                            local ok = SendBrowseQuery(entry)
                            if not ok then
                                waitingForResults = false
                                pendingEntry      = nil
                                failedQueue[#failedQueue + 1] = entry
                                OnItemFail(entry)
                            end
                            -- On success: waitingForResults stays true.
                            -- OnBrowseResults() will handle the result.
                        end)
                        return  -- defer failure; waiting for OnBrowseResults
                    else
                        GAM.Log.Warn(
                            "AHScan: zero commodity rows itemID=%d, no name for browse fallback",
                            entry.itemID)
                    end
                end

                -- No fallback attempted (name unavailable) or fallback already used
                -- on a previous attempt → normal failure path.
                GAM.Log.Warn("AHScan: no commodity results itemID=%d", entry.itemID)
                waitingForResults = false
                pendingEntry      = nil
                failedQueue[#failedQueue + 1] = entry
                OnItemFail(entry)
            end
        end
        TryRead(MAX_RETRY - 1)
    end)
end

-- ITEM_SEARCH_RESULTS_UPDATED → price data for a non-commodity item
function AHScan.OnItemResults(itemKey)
    if not waitingForResults then return end
    if not pendingEntry or pendingEntry.isNameScan then return end

    -- Stray-result guard: other addons (or a previous timed-out query) can
    -- trigger ITEM_SEARCH_RESULTS_UPDATED.  Verify the returned itemKey matches
    -- what we actually queried before processing the results.
    if itemKey and itemKey.itemID and pendingEntry.itemID ~= 0 then
        if itemKey.itemID ~= pendingEntry.itemID then
            GAM.Log.Debug(
                "AHScan: OnItemResults stray itemID=%d (expected %d), ignoring",
                itemKey.itemID, pendingEntry.itemID)
            return
        end
    end

    local entry = pendingEntry

    C_Timer.After(EVENT_PROCESS_DELAY, function()
        -- GetNumItemSearchResults and GetItemSearchResultInfo both require the
        -- itemKey that was searched (confirmed: AuctionHouseDocumentation.lua).
        local numResults = C_AuctionHouse.GetNumItemSearchResults(itemKey)
        if not numResults or numResults == 0 then
            waitingForResults = false
            pendingEntry      = nil
            failedQueue[#failedQueue + 1] = entry
            OnItemFail(entry)
            return
        end
        -- Collect per-unit prices with quantity=1 (equal weighting per listing),
        -- then apply the same ARP-style fill+trim as commodities.
        local raw = {}
        for i = 1, numResults do
            local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
            if r and r.buyoutAmount and r.buyoutAmount > 0 then
                -- buyoutAmount is the total stack price; divide by quantity for per-unit.
                -- quantity=1 so fill+trim weights each listing equally, not by stack size.
                local qty = r.quantity or 1
                raw[#raw + 1] = { unitPrice = math.floor(r.buyoutAmount / qty), quantity = 1 }
            end
        end
        table.sort(raw, function(a, b) return a.unitPrice < b.unitPrice end)

        -- Use configured fill qty.
        local opts = GAM.db and GAM.db.options
        local targetQty = (opts and opts.shallowFillQty) or GAM.C.DEFAULT_FILL_QTY

        itemCache[entry.itemID] = { prices = raw, ts = time() }

        local avg, minP, maxP, count = ComputeStatsFromResults(raw, targetQty)
        if avg then
            local price = math.floor(avg)
            GAM.Pricing.StorePrice(entry.itemID, price)
            if entry.callback then
                pcall(entry.callback, entry.itemID, price, minP, maxP, count)
            end
            scanSuccessCount  = scanSuccessCount + 1
            doneCount         = doneCount + 1
            waitingForResults = false
            pendingEntry      = nil
            GAM.Log.Debug("AHScan: price itemID=%d avg=%d", entry.itemID, price)
            FireProgress(false)
        else
            waitingForResults = false
            pendingEntry      = nil
            failedQueue[#failedQueue + 1] = entry
            OnItemFail(entry)
        end
    end)
end

-- AUCTION_HOUSE_BROWSE_RESULTS_UPDATED
-- Handles two cases:
--   isNameScan=true     → normal name→itemID discovery (existing behaviour)
--   isBrowseFallback=true → commodity zero-row escalation path (new)
function AHScan.OnBrowseResults()
    if not waitingForResults then return end
    if not pendingEntry then return end
    -- Accept both normal name-scans and browse-fallback price-scan entries.
    if not pendingEntry.isNameScan and not pendingEntry.isBrowseFallback then return end

    local entry = pendingEntry

    C_Timer.After(EVENT_PROCESS_DELAY, function()
        -- Stale-timer guard: handles StopScan / OnAHClosed during the delay.
        if pendingEntry ~= entry then return end

        -- Pagination guard: Blizzard fires AUCTION_HOUSE_BROWSE_RESULTS_UPDATED
        -- multiple times as result pages load.  HasFullBrowseResults() returns
        -- true only when every page has arrived.  If it's still false we bail
        -- out here; the next event fire will re-enter OnBrowseResults and try
        -- again.  The RESULT_WAIT safety timeout is the backstop if pages never
        -- fully load.
        if C_AuctionHouse.HasFullBrowseResults and
                not C_AuctionHouse.HasFullBrowseResults() then
            GAM.Log.Debug("AHScan: browse results still paginating for '%s', deferring",
                tostring(entry.name))
            return  -- wait for next AUCTION_HOUSE_BROWSE_RESULTS_UPDATED
        end

        -- GetBrowseResults() returns a table directly in Midnight 12.x.
        -- GetNumBrowseResults / GetBrowseResultByIndex do NOT exist in this API.
        local browseResults = C_AuctionHouse.GetBrowseResults and C_AuctionHouse.GetBrowseResults() or {}
        local num = #browseResults
        GAM.Log.Debug("AHScan: browse '%s' num=%d full=%s",
            tostring(entry.name), num,
            tostring(C_AuctionHouse.HasFullBrowseResults and C_AuctionHouse.HasFullBrowseResults()))

        -- ── Browse-fallback path (commodity zero-row escalation) ──────────────
        if entry.isBrowseFallback then
            local foundAny = false
            if num > 0 then
                for _, result in ipairs(browseResults) do
                    if result and result.itemKey and result.itemKey.itemID then
                        local id = result.itemKey.itemID

                        -- Overwrite cached itemKey with the full struct from the AH —
                        -- may include itemSuffix/quality fields that MakeItemKey(id,0,0,0)
                        -- zeroes out. Re-queued scan picks up the corrected key.
                        itemKeyCache[id] = result.itemKey
                        -- Persist full key to SavedVariables so future sessions skip browse
                        local ik = result.itemKey
                        if ik and (ik.itemLevel ~= 0 or ik.itemSuffix ~= 0 or ik.battlePetSpeciesID ~= 0) then
                            local ikdb = GoldAdvisorMidnightDB and GoldAdvisorMidnightDB.itemKeyDB
                            if ikdb then
                                ikdb[id] = {
                                    itemLevel          = ik.itemLevel or 0,
                                    itemSuffix         = ik.itemSuffix or 0,
                                    battlePetSpeciesID = ik.battlePetSpeciesID or 0,
                                }
                            end
                        end

                        -- For the original itemID: clear de-dup so it can be re-queued
                        -- with the corrected key.  Use noFallback=true so it doesn't
                        -- trigger a second browse if it still returns 0 rows.
                        -- For other discovered IDs: normal de-dup; allow one browse
                        -- fallback of their own if needed.
                        if id == entry.itemID then
                            priceScanQueued[id] = nil
                        end
                        EnqueuePriceScan(id, entry.callback, entry.name,
                            id == entry.itemID)  -- noFallback only for original id

                        GAM.Log.Debug("AHScan: fallback browse found itemID=%d for '%s'",
                            id, tostring(entry.name))
                        foundAny = true
                    end
                end
            end

            if foundAny then
                GAM.Log.Info(
                    "AHScan: browse fallback queued price scans for itemID=%d '%s'",
                    entry.itemID, tostring(entry.name))
                scanSuccessCount = scanSuccessCount + 1
            else
                GAM.Log.Warn(
                    "AHScan: browse fallback empty for itemID=%d '%s'",
                    entry.itemID, tostring(entry.name))
                scanFailCount = scanFailCount + 1
                -- Do NOT re-add to failedQueue — the browse was the last resort.
            end
            doneCount         = doneCount + 1
            waitingForResults = false
            pendingEntry      = nil
            FireProgress(false)
            return
        end

        -- ── Normal name-scan path ──────────────────────────────────────────────
        local pdb = GAM:GetPatchDB(entry.patchTag)
        pdb.rankGroups             = pdb.rankGroups or {}
        pdb.rankGroups[entry.name] = pdb.rankGroups[entry.name] or {}

        local foundIDs = {}
        if num > 0 then
            for _, result in ipairs(browseResults) do
                if result and result.itemKey and result.itemKey.itemID then
                    local id = result.itemKey.itemID
                    -- Deduplicate
                    local exists = false
                    for _, existing in ipairs(pdb.rankGroups[entry.name]) do
                        if existing == id then exists = true; break end
                    end
                    if not exists then
                        table.insert(pdb.rankGroups[entry.name], id)
                    end
                    foundIDs[id] = true
                end
            end
            table.sort(pdb.rankGroups[entry.name])
        end

        GAM.Log.Info("AHScan: browse '%s' → %d ID(s)", entry.name, #pdb.rankGroups[entry.name])

        -- Chain: queue price scans for each newly discovered itemID.
        -- Propagate callback so the UI refreshes when prices arrive.
        for id in pairs(foundIDs) do
            EnqueuePriceScan(id, entry.callback)
        end

        if entry.callback then
            pcall(entry.callback, entry.name, pdb.rankGroups[entry.name])
        end

        scanSuccessCount  = scanSuccessCount + 1
        doneCount         = doneCount + 1
        waitingForResults = false
        pendingEntry      = nil
        FireProgress(false)
    end)
end

function AHScan.OnAHClosed()
    if scanning then
        AHScan._pendingResume = true
        scanning = false
        if ticker then ticker:Cancel(); ticker = nil end
        GAM.Log.Info(GAM.L["SCAN_AH_CLOSED"])
    end
end

-- ===== Public API =====

function AHScan.QueueItemScan(itemID, callback)
    if not itemID or itemID == 0 then return end
    EnqueuePriceScan(itemID, callback)
end

function AHScan.QueueNameScan(itemName, patchTag, callback)
    if not itemName then return end
    EnqueueNameScan(itemName, patchTag, callback)
end

-- QueueStratListItems: queues price scans for a specific list of strats.
-- Use this when scanning a filtered/selected subset (e.g. one profession).
function AHScan.QueueStratListItems(stratList, patchTag)
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GAM:GetPatchDB(patchTag)

    local function tryQueueItem(item)
        if not item or not item.name then return end
        local ids = item.itemIDs
        if (not ids or #ids == 0) then
            ids = pdb.rankGroups[item.name] or {}
        end
        if ids and #ids > 0 then
            for _, id in ipairs(ids) do
                EnqueuePriceScan(id, nil, item.name)  -- pass name for browse fallback
            end
        else
            EnqueueNameScan(item.name, patchTag)
        end
    end

    for _, strat in ipairs(stratList or {}) do
        tryQueueItem(strat.output)
        for _, r in ipairs(strat.reagents or {}) do tryQueueItem(r) end
        if strat.outputs then
            for _, o in ipairs(strat.outputs) do tryQueueItem(o) end
        end
        -- Also queue items that only appear in non-default rank variants
        -- (e.g. R2-only reagents in the "highest" variant won't be in strat.reagents)
        if strat.rankVariants then
            for _, variant in pairs(strat.rankVariants) do
                for _, r in ipairs(variant.reagents or {}) do tryQueueItem(r) end
                for _, o in ipairs(variant.outputs  or {}) do tryQueueItem(o) end
            end
        end
    end

    GAM.Log.Info("AHScan: queued %d items for %d strats", totalEver, #(stratList or {}))
end

-- QueueAllStratItems: queues price scans for known itemIDs, name scans for unknown.
-- After name scans complete they auto-chain price scans for discovered IDs.
function AHScan.QueueAllStratItems(patchTag)
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local strats = GAM.Importer.GetAllStrats(patchTag)
    local pdb    = GAM:GetPatchDB(patchTag)

    local function tryQueueItem(item)
        if not item or not item.name then return end
        -- Resolve itemIDs: from strat definition or from saved rankGroups
        local ids = item.itemIDs
        if (not ids or #ids == 0) then
            ids = pdb.rankGroups[item.name] or {}
        end
        if ids and #ids > 0 then
            for _, id in ipairs(ids) do
                EnqueuePriceScan(id, nil, item.name)  -- pass name for browse fallback
            end
        else
            -- No itemID known yet — queue a name/browse scan to discover it
            EnqueueNameScan(item.name, patchTag)
        end
    end

    for _, strat in ipairs(strats) do
        tryQueueItem(strat.output)
        for _, r in ipairs(strat.reagents or {}) do tryQueueItem(r) end
        if strat.outputs then
            for _, o in ipairs(strat.outputs) do tryQueueItem(o) end
        end
        -- Also queue items that only appear in non-default rank variants
        if strat.rankVariants then
            for _, variant in pairs(strat.rankVariants) do
                for _, r in ipairs(variant.reagents or {}) do tryQueueItem(r) end
                for _, o in ipairs(variant.outputs  or {}) do tryQueueItem(o) end
            end
        end
    end

    GAM.Log.Info("AHScan: queued %d items (%d name, %d price) for %s",
        totalEver,
        (function()
            local n = 0
            for _, e in ipairs(scanQueue) do if e.isNameScan then n=n+1 end end
            return n
        end)(),
        (function()
            local n = 0
            for _, e in ipairs(scanQueue) do if not e.isNameScan then n=n+1 end end
            return n
        end)(),
        patchTag)
end

function AHScan.StartScan()
    if not GAM.ahOpen then
        GAM.Log.Warn(GAM.L["ERR_NO_AH"])
        return
    end
    if scanning then
        GAM.Log.Debug("AHScan: already scanning.")
        return
    end
    scanning         = true
    scanSuccessCount = 0
    scanFailCount    = 0
    doneCount        = 0
    -- totalEver was already set as items were queued; don't reset it here
    failedQueue      = {}
    isRetryPass      = false
    GAM.Log.Info(GAM.L["SCAN_STARTED"], totalEver)
    FireProgress(false)

    ticker = C_Timer.NewTicker(0.5, function()
        ProcessNextInQueue()
    end)
end

function AHScan.StopScan()
    scanning = false
    if ticker then ticker:Cancel(); ticker = nil end
    waitingForResults = false
    pendingEntry      = nil
    FireProgress(true)
    GAM.Log.Info("AHScan: stopped by user.")
end

function AHScan.GetPrice(itemID)
    return GAM.Pricing.GetUnitPrice(itemID)
end

function AHScan.IsScanning()
    return scanning
end

-- Returns done, total for external progress display
function AHScan.GetProgress()
    return doneCount, totalEver, scanSuccessCount, scanFailCount
end

-- Reset queuing dedup tables (call before building a new scan queue)
function AHScan.ResetQueue()
    scanQueue       = {}
    queueHead       = 1
    failedQueue     = {}
    priceScanQueued = {}
    nameScanQueued  = {}
    totalEver       = 0
    doneCount       = 0
    -- Clear session caches so old raw arrays are GC'd before the next scan
    wipe(commodityCache)
    wipe(itemCache)
end
