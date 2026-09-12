-- GoldAdvisorMidnight/AuctionHouseScan.lua
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
local POLL_INTERVAL       = GAM.C.AH_POLL_INTERVAL or 0.35
local MAX_MORE_REQUESTS   = GAM.C.AH_MAX_MORE_REQUESTS or 5

local Results = assert(GAM.AuctionHouseResults, "AuctionHouseResults must load before AuctionHouseScan")
local Query = assert(GAM.AuctionHouseQuery, "AuctionHouseQuery must load before AuctionHouseScan")

local function GetOpts()
    return (GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {}
end

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
local activeAttempt     = 0
local pollToken         = 0
local completedDiagnostics = {}

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

-- Pre-warm session itemKey cache from persisted DB.
-- Called from Core.lua on AUCTION_HOUSE_SHOW. Ensures all known full itemKeys
-- are in the fast session cache before scanning begins.
function AHScan.PreWarmCache()
    local n = Results.PreWarmItemKeys()
    if n > 0 then
        GAM.Log.Debug("AHScan: pre-warmed %d itemKeys from DB", n)
    end
end

function AHScan.GetCachedResults(itemID)
    return Results.GetCachedResults(itemID)
end

function AHScan.GetRawScanSnapshot(itemID)
    return Results.GetRawScanSnapshot(itemID)
end

-- ComputePriceForQty: average unit price for `requiredQty` units using live
-- session caches (commodity → item) then persisted raw as fallback.
-- Returns avg in copper, or nil if no raw data is available.
function AHScan.ComputePriceForQty(itemID, requiredQty)
    return Results.ComputePriceForQty(itemID, requiredQty)
end

-- ===== Queue helpers =====

-- Internal: add a price-scan entry (de-dup by itemID).
-- itemName  (optional) — stored so OnCommodityResults can issue a browse fallback
--                        without a separate GetItemInfo call.
-- noFallback (optional) — pre-marks browseFallbackUsed=true to prevent a second
--                        browse escalation when re-queued from OnBrowseResults.
local function AddQueueMetadata(entry, reason, strategyKey)
    if not entry then return end
    if reason and reason ~= "" then
        entry.reasons = entry.reasons or {}
        entry._reasonSet = entry._reasonSet or {}
        if not entry._reasonSet[reason] then
            entry._reasonSet[reason] = true
            entry.reasons[#entry.reasons + 1] = reason
        end
    end
    if strategyKey and strategyKey ~= "" then
        entry.strategyKeys = entry.strategyKeys or {}
        entry._strategySet = entry._strategySet or {}
        if not entry._strategySet[strategyKey] then
            entry._strategySet[strategyKey] = true
            entry.strategyKeys[#entry.strategyKeys + 1] = strategyKey
        end
    end
end

local priceScanQueued = {}  -- [itemID] = queueEntry; reset at StartScan
local function EnqueuePriceScan(itemID, callback, itemName, noFallback, reason, strategyKey)
    if not itemID or itemID == 0 then return end
    if priceScanQueued[itemID] then
        AddQueueMetadata(priceScanQueued[itemID], reason, strategyKey)
        return
    end
    totalEver = totalEver + 1
    local entry = {
        itemID             = itemID,
        callback           = callback,
        isNameScan         = false,
        name               = itemName,      -- browse fallback search term
        browseFallbackUsed = noFallback or nil, -- true → skip browse escalation
        -- _gen              assigned lazily when browse fallback is triggered
    }
    AddQueueMetadata(entry, reason or "price", strategyKey)
    scanQueue[#scanQueue + 1] = entry
    priceScanQueued[itemID] = entry
end

-- Internal: add a name-scan entry (de-dup by name)
local nameScanQueued = {}  -- [name] = queueEntry; reset at StartScan
local function EnqueueNameScan(itemName, patchTag, callback, reason, strategyKey)
    if not itemName then return end
    if nameScanQueued[itemName] then
        AddQueueMetadata(nameScanQueued[itemName], reason, strategyKey)
        return
    end
    totalEver = totalEver + 1
    local entry = {
        itemID     = 0,
        name       = itemName,
        patchTag   = patchTag or GAM.C.DEFAULT_PATCH,
        callback   = callback,
        isNameScan = true,
    }
    AddQueueMetadata(entry, reason or "name", strategyKey)
    scanQueue[#scanQueue + 1] = entry
    nameScanQueued[itemName] = entry
end

-- ===== Query sender: price scan =====
-- Midnight removed SendCommoditySearchQuery; SendSearchQuery handles all item types.
-- Blizzard fires COMMODITY_SEARCH_RESULTS_UPDATED for commodities and
-- ITEM_SEARCH_RESULTS_UPDATED for non-commodities — both handlers wired in Core.

local function SendPriceQuery(entry)
    local itemKey = Results.GetCachedItemKey(entry.itemID)
    if not itemKey then
        GAM.Log.Warn("AHScan: no itemKey for itemID=%d", entry.itemID)
        return false
    end
    entry.queryItemKey = itemKey
    local ok = Query.SendSearch(itemKey)
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
    local ok = Query.SendBrowse(entry.name)
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

local function IsCurrentAttempt(entry, attempt)
    return scanning
        and waitingForResults
        and pendingEntry == entry
        and activeAttempt == attempt
end

local function InvalidatePendingAttempt()
    activeAttempt = activeAttempt + 1
    pollToken = pollToken + 1
    waitingForResults = false
    pendingEntry = nil
end

local function SaveDiagnostic(entry, outcome)
    completedDiagnostics[#completedDiagnostics + 1] = Query.Snapshot(entry, outcome)
end

local function CompleteFailure(entry, outcome)
    Query.Record(entry, "COMPLETE", outcome or "failed")
    SaveDiagnostic(entry, outcome or "failed")
    scanFailCount = scanFailCount + 1
    doneCount     = doneCount + 1
    FireProgress(false)
end

local function RetryOrCompleteFailure(entry, outcome)
    if not entry.isNameScan and not isRetryPass then
        Query.Record(entry, "RETRY_QUEUED", outcome or "failed")
        failedQueue[#failedQueue + 1] = entry
        return
    end
    CompleteFailure(entry, outcome)
end

local function PauseScanForAHClose()
    if pendingEntry then
        -- The queue head advances before a query is sent. Move it back so a
        -- paused in-flight entry is issued again when the Auction House opens.
        queueHead = math.max(1, queueHead - 1)
        scanQueue[queueHead] = pendingEntry
    end
    InvalidatePendingAttempt()
    AHScan._pendingResume = true
    scanning = false
    if ticker then ticker:Cancel(); ticker = nil end
    GAM.Log.Info(GAM.L["SCAN_AH_CLOSED"])
end

local ScheduleAttemptTimeout
local SchedulePendingPoll
local BeginBrowseFallback

local function CompletePriceSuccess(entry, resultType, rows, depthComplete)
    local targetQty = GetOpts().shallowFillQty or GAM.C.DEFAULT_FILL_QTY
    local avg, minPrice, maxPrice, count
    if resultType == "commodity" then
        avg, minPrice, maxPrice, count = Results.StoreCommodityRows(entry.itemID, rows, targetQty)
    else
        avg, minPrice, maxPrice, count = Results.StoreItemRows(entry.itemID, rows, targetQty)
        if avg then avg = math.floor(avg) end
    end
    if not avg then return false end

    GAM.Pricing.StorePrice(entry.itemID, avg, minPrice)
    if entry.callback then
        pcall(entry.callback, entry.itemID, avg, minPrice, maxPrice, count)
    end
    entry.lastResultType = resultType
    entry.depthComplete = depthComplete and true or false
    Query.Record(entry, "COMPLETE", depthComplete and resultType or (resultType .. "_partial"))
    SaveDiagnostic(entry, depthComplete and resultType or (resultType .. "_partial"))
    scanSuccessCount = scanSuccessCount + 1
    doneCount = doneCount + 1
    pollToken = pollToken + 1
    waitingForResults = false
    pendingEntry = nil
    GAM.Log.Debug("AHScan: price itemID=%d avg=%d source=%s depth=%s",
        entry.itemID, math.floor(avg), resultType, tostring(depthComplete))
    FireProgress(false)
    return true
end

local function RequestMoreIfNeeded(entry, attempt, resultType, rows)
    local targetQty = GetOpts().shallowFillQty or GAM.C.DEFAULT_FILL_QTY
    local listed = Results.GetListedQuantity(rows)
    local full = Query.HasFullResults(resultType, entry.itemID, entry.resultItemKey or entry.queryItemKey)
    if listed >= targetQty or full == true or (entry.moreRequests or 0) >= MAX_MORE_REQUESTS then
        return false, full == true or listed >= targetQty
    end

    local ok, nowFull = Query.RequestMoreResults(
        resultType, entry.itemID, entry.resultItemKey or entry.queryItemKey)
    if not ok or nowFull ~= false then
        return false, nowFull == true
    end

    entry.moreRequests = (entry.moreRequests or 0) + 1
    Query.Record(entry, "MORE", resultType .. ":" .. tostring(listed))
    -- A new page is a new pending phase. Renewing the attempt invalidates the
    -- previous timeout and delayed result callbacks.
    activeAttempt = activeAttempt + 1
    local nextAttempt = activeAttempt
    ScheduleAttemptTimeout(entry, nextAttempt)
    SchedulePendingPoll(entry, nextAttempt, POLL_INTERVAL)
    return true, false
end

local function TryProcessAvailableResults(entry, attempt, preferredType)
    if not IsCurrentAttempt(entry, attempt) then return false end
    local types = preferredType and { preferredType } or { "commodity", "item" }
    for _, resultType in ipairs(types) do
        local rows
        if resultType == "commodity" then
            rows = Results.ReadCommodityRows(entry.itemID)
        else
            rows = Results.ReadItemRows(entry.resultItemKey or entry.queryItemKey)
        end
        if #rows > 0 then
            Query.Record(entry, "CACHE_ROWS", resultType .. ":" .. tostring(#rows))
            local waitingForMore, depthComplete = RequestMoreIfNeeded(entry, attempt, resultType, rows)
            if waitingForMore then return true end
            return CompletePriceSuccess(entry, resultType, rows, depthComplete)
        end
    end
    return false
end

local function RetryEmptySearch(entry)
    if entry.emptyResultRetrySent or not Query.IsThrottleReady() then return false end
    entry.emptyResultRetrySent = true
    entry.moreRequests = 0
    entry.queryAttempts = (entry.queryAttempts or 0) + 1
    Query.Record(entry, "EMPTY_RETRY")
    local ok = Query.SendSearch(entry.queryItemKey)
    if not ok then
        Query.Record(entry, "EMPTY_RETRY_SEND_FAILED")
        return false
    end
    lastQueryTime = GetTime()
    activeAttempt = activeAttempt + 1
    local nextAttempt = activeAttempt
    ScheduleAttemptTimeout(entry, nextAttempt)
    SchedulePendingPoll(entry, nextAttempt, POLL_INTERVAL)
    return true
end

local function HandleConfirmedEmpty(entry, attempt, resultType)
    if not IsCurrentAttempt(entry, attempt) then return end
    Query.Record(entry, "EMPTY", resultType)
    if RetryEmptySearch(entry) then return end
    if resultType == "commodity" and not entry.browseFallbackUsed then
        BeginBrowseFallback(entry)
        return
    end
    waitingForResults = false
    pendingEntry = nil
    CompleteFailure(entry, "confirmed_empty")
end

SchedulePendingPoll = function(entry, attempt, delay)
    pollToken = pollToken + 1
    local token = pollToken
    C_Timer.After(delay or POLL_INTERVAL, function()
        if token ~= pollToken or not IsCurrentAttempt(entry, attempt) then return end
        if TryProcessAvailableResults(entry, attempt) then return end
        SchedulePendingPoll(entry, attempt, POLL_INTERVAL)
    end)
end

ScheduleAttemptTimeout = function(entry, attempt)
    C_Timer.After(RESULT_WAIT, function()
        if not IsCurrentAttempt(entry, attempt) then return end
        Query.Record(entry, "TIMEOUT")
        if not Query.IsThrottleReady() then
            Query.Record(entry, "THROTTLE_WAIT")
            ScheduleAttemptTimeout(entry, attempt)
            return
        end
        -- Blizzard can populate the result cache without delivering the
        -- item-specific event. Always inspect it before retrying or failing.
        if not entry.isNameScan and TryProcessAvailableResults(entry, attempt) then return end
        if entry.isNameScan or entry.isBrowseFallback then
            waitingForResults = false
            pendingEntry = nil
            RetryOrCompleteFailure(entry, "timeout")
            return
        end
        HandleConfirmedEmpty(entry, attempt, entry.lastResultType or "commodity")
    end)
end

BeginBrowseFallback = function(entry)
    entry.browseFallbackUsed = true
    entry.isBrowseFallback = true
    entry.name = entry.name or GetItemInfo(entry.itemID)
    if not entry.name then
        waitingForResults = false
        pendingEntry = nil
        CompleteFailure(entry, "confirmed_empty")
        return false
    end

    Query.Record(entry, "BROWSE_FALLBACK", entry.name)
    activeAttempt = activeAttempt + 1
    local attempt = activeAttempt
    local browseWait = math.max(0, SCAN_DELAY - (GetTime() - lastQueryTime))
    C_Timer.After(browseWait, function()
        if not IsCurrentAttempt(entry, attempt) then return end
        if not GAM.ahOpen then
            PauseScanForAHClose()
            return
        end
        if not Query.IsThrottleReady() then
            Query.Record(entry, "BROWSE_THROTTLED")
            waitingForResults = false
            pendingEntry = nil
            RetryOrCompleteFailure(entry, "browse_throttled")
            return
        end
        if not SendBrowseQuery(entry) then
            waitingForResults = false
            pendingEntry = nil
            RetryOrCompleteFailure(entry, "browse_send_failed")
            return
        end
        ScheduleAttemptTimeout(entry, attempt)
    end)
    return true
end

local function ProcessNextInQueue()
    if not scanning then return end
    if not GAM.ahOpen then
        PauseScanForAHClose()
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
    if not Query.IsThrottleReady() then
        GAM.Log.Debug(GAM.L["SCAN_THROTTLED"])
        return
    end

    local entry = scanQueue[queueHead]
    queueHead         = queueHead + 1
    pendingEntry      = entry
    waitingForResults = true
    activeAttempt     = activeAttempt + 1
    local attempt     = activeAttempt
    Query.NewDiagnostic(entry, attempt)

    if entry.isNameScan then
        local sent = SendBrowseQuery(entry)
        if not sent then
            waitingForResults = false
            pendingEntry      = nil
            CompleteFailure(entry, "send_failed")
            return
        end
    else
        local sent = SendPriceQuery(entry)
        if not sent then
            waitingForResults = false
            pendingEntry      = nil
            RetryOrCompleteFailure(entry, "send_failed")
            return
        end
    end

    ScheduleAttemptTimeout(entry, attempt)
    if not entry.isNameScan then
        SchedulePendingPoll(entry, attempt, POLL_INTERVAL)
    end
end

-- ===== Event callbacks (called from Core.lua) =====

-- COMMODITY_SEARCH_RESULTS_UPDATED → price data for a commodity itemID
function AHScan.OnCommodityResults(itemID)
    if not waitingForResults then return end
    if not pendingEntry or pendingEntry.isNameScan then return end
    if tonumber(pendingEntry.itemID) ~= tonumber(itemID) then return end

    local entry = pendingEntry
    local attempt = activeAttempt
    entry.lastResultType = "commodity"
    Query.Record(entry, "COMMODITY_UPDATED", tostring(itemID))

    local function TryRead(attemptsLeft)
        if not IsCurrentAttempt(entry, attempt) then return end
        if TryProcessAvailableResults(entry, attempt, "commodity") then return end
        if attemptsLeft > 0 then
            C_Timer.After(RESULT_RETRY_DELAY, function() TryRead(attemptsLeft - 1) end)
        else
            HandleConfirmedEmpty(entry, attempt, "commodity")
        end
    end
    C_Timer.After(EVENT_PROCESS_DELAY, function() TryRead(MAX_RETRY - 1) end)
end

function AHScan.OnCommodityResultsReceived()
    if not (waitingForResults and pendingEntry and not pendingEntry.isNameScan) then return end
    pendingEntry.lastResultType = "commodity"
    Query.Record(pendingEntry, "COMMODITY_RECEIVED")
    SchedulePendingPoll(pendingEntry, activeAttempt, 0.05)
end

-- ITEM_SEARCH_RESULTS_UPDATED → price data for a non-commodity item
function AHScan.OnItemResults(itemKey)
    if not waitingForResults then return end
    if not pendingEntry or pendingEntry.isNameScan then return end
    if not Query.ItemKeysMatch(pendingEntry.queryItemKey, itemKey) then return end

    local entry = pendingEntry
    local attempt = activeAttempt
    entry.lastResultType = "item"
    entry.resultItemKey = itemKey
    Query.Record(entry, "ITEM_UPDATED",
        tostring(itemKey.itemID) .. ":" .. tostring(itemKey.itemLevel or 0))

    local function TryRead(attemptsLeft)
        if not IsCurrentAttempt(entry, attempt) then return end
        if TryProcessAvailableResults(entry, attempt, "item") then return end
        if attemptsLeft > 0 then
            C_Timer.After(RESULT_RETRY_DELAY, function() TryRead(attemptsLeft - 1) end)
        else
            HandleConfirmedEmpty(entry, attempt, "item")
        end
    end
    C_Timer.After(EVENT_PROCESS_DELAY, function() TryRead(MAX_RETRY - 1) end)
end

function AHScan.OnThrottleReady()
    if waitingForResults and pendingEntry and not pendingEntry.isNameScan then
        SchedulePendingPoll(pendingEntry, activeAttempt, 0)
    else
        ProcessNextInQueue()
    end
end

function AHScan.OnThrottleMessageDropped()
    if not (waitingForResults and pendingEntry) then return end
    local entry = pendingEntry
    Query.Record(entry, "DROPPED")
    waitingForResults = false
    pendingEntry = nil
    pollToken = pollToken + 1
    RetryOrCompleteFailure(entry, "message_dropped")
end

function AHScan.OnThrottleResponseReceived()
    if not (waitingForResults and pendingEntry and not pendingEntry.isNameScan) then
        ProcessNextInQueue()
        return
    end
    Query.Record(pendingEntry, "GENERIC_RESPONSE")
    SchedulePendingPoll(pendingEntry, activeAttempt, 0.05)
end

function AHScan.OnNewResults(itemKey)
    if not (waitingForResults and pendingEntry and not pendingEntry.isNameScan) then return end
    if itemKey and not Query.ItemKeysMatch(pendingEntry.queryItemKey, itemKey) then return end
    if itemKey then pendingEntry.resultItemKey = itemKey end
    Query.Record(pendingEntry, "NEW_RESULTS",
        tostring(itemKey and itemKey.itemID or "-") .. ":" .. tostring(itemKey and itemKey.itemLevel or "-"))
    SchedulePendingPoll(pendingEntry, activeAttempt, 0.05)
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
    local attempt = activeAttempt

    C_Timer.After(EVENT_PROCESS_DELAY, function()
        -- Stale-timer guard: handles stop, pause, retry, and a newer request
        -- reusing the same queue entry.
        if not IsCurrentAttempt(entry, attempt) then return end

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
                        Results.StoreDiscoveredItemKey(result.itemKey)

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
                Query.Record(entry, "COMPLETE", "browse_discovery")
                SaveDiagnostic(entry, "browse_discovery")
            else
                GAM.Log.Warn(
                    "AHScan: browse fallback empty for itemID=%d '%s'",
                    entry.itemID, tostring(entry.name))
                scanFailCount = scanFailCount + 1
                Query.Record(entry, "COMPLETE", "browse_empty")
                SaveDiagnostic(entry, "browse_empty")
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
        Query.Record(entry, "COMPLETE", "name_discovery")
        SaveDiagnostic(entry, "name_discovery")
        waitingForResults = false
        pendingEntry      = nil
        FireProgress(false)
    end)
end

function AHScan.OnAHClosed()
    if scanning then
        PauseScanForAHClose()
    end
end

-- ===== Public API =====

function AHScan.QueueItemScan(itemID, callback, reason, strategyKey)
    if not itemID or itemID == 0 then return end
    EnqueuePriceScan(itemID, callback, nil, nil, reason or "manual item", strategyKey)
end

function AHScan.QueueNameScan(itemName, patchTag, callback, reason, strategyKey)
    if not itemName then return end
    EnqueueNameScan(itemName, patchTag, callback, reason or "manual name", strategyKey)
end

local function QueueCheapestAlternatives(reagent, patchTag, strategyKey)
    if not (reagent and reagent.cheapestOf) then
        return
    end
    for _, alt in ipairs(reagent.cheapestOf) do
        if alt and alt.name then
            local ids = alt.itemIDs
            if ids and #ids > 0 then
                for _, id in ipairs(ids) do
                    EnqueuePriceScan(id, nil, alt.name, nil, "flexible pool", strategyKey)
                end
            else
                EnqueueNameScan(alt.name, patchTag, nil, "flexible pool", strategyKey)
            end
        end
    end
end

-- QueueStratListItems: queues price scans for a specific list of strats.
-- Use this when scanning a filtered/selected subset (e.g. one profession).
function AHScan.QueueStratListItems(stratList, patchTag)
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GAM:GetPatchDB(patchTag)

    local function tryQueueItem(item, reason, strategyKey)
        if not item or not item.name then return end
        local ids = item.itemIDs
        if (not ids or #ids == 0) then
            ids = pdb.rankGroups[item.name] or {}
        end
        if ids and #ids > 0 then
            for _, id in ipairs(ids) do
                EnqueuePriceScan(id, nil, item.name, nil, reason, strategyKey)  -- pass name for browse fallback
            end
        else
            EnqueueNameScan(item.name, patchTag, nil, reason, strategyKey)
        end
    end

    for _, strat in ipairs(stratList or {}) do
        local strategyKey = strat.id or strat.key or strat.stratName
        tryQueueItem(strat.output, "strategy output", strategyKey)
        for _, r in ipairs(strat.reagents or {}) do
            tryQueueItem(r, "strategy input", strategyKey)
            QueueCheapestAlternatives(r, patchTag, strategyKey)
        end
        if strat.outputs then
            for _, o in ipairs(strat.outputs) do tryQueueItem(o, "strategy output", strategyKey) end
        end
        -- Also queue items that only appear in non-default rank variants
        -- (e.g. R2-only reagents in the "highest" variant won't be in strat.reagents)
        if strat.rankVariants then
            for _, variant in pairs(strat.rankVariants) do
                for _, r in ipairs(variant.reagents or {}) do
                    tryQueueItem(r, "rank variant input", strategyKey)
                    QueueCheapestAlternatives(r, patchTag, strategyKey)
                end
                for _, o in ipairs(variant.outputs  or {}) do tryQueueItem(o, "rank variant output", strategyKey) end
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

    local function tryQueueItem(item, reason, strategyKey)
        if not item or not item.name then return end
        -- Resolve itemIDs: from strat definition or from saved rankGroups
        local ids = item.itemIDs
        if (not ids or #ids == 0) then
            ids = pdb.rankGroups[item.name] or {}
        end
        if ids and #ids > 0 then
            for _, id in ipairs(ids) do
                EnqueuePriceScan(id, nil, item.name, nil, reason, strategyKey)  -- pass name for browse fallback
            end
        else
            -- No itemID known yet — queue a name/browse scan to discover it
            EnqueueNameScan(item.name, patchTag, nil, reason, strategyKey)
        end
    end

    for _, strat in ipairs(strats) do
        local strategyKey = strat.id or strat.key or strat.stratName
        tryQueueItem(strat.output, "strategy output", strategyKey)
        for _, r in ipairs(strat.reagents or {}) do
            tryQueueItem(r, "strategy input", strategyKey)
            QueueCheapestAlternatives(r, patchTag, strategyKey)
        end
        if strat.outputs then
            for _, o in ipairs(strat.outputs) do tryQueueItem(o, "strategy output", strategyKey) end
        end
        -- Also queue items that only appear in non-default rank variants
        if strat.rankVariants then
            for _, variant in pairs(strat.rankVariants) do
                for _, r in ipairs(variant.reagents or {}) do
                    tryQueueItem(r, "rank variant input", strategyKey)
                    QueueCheapestAlternatives(r, patchTag, strategyKey)
                end
                for _, o in ipairs(variant.outputs  or {}) do tryQueueItem(o, "rank variant output", strategyKey) end
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
    local isResume = AHScan._pendingResume
    AHScan._pendingResume = false
    scanning = true
    if not isResume then
        scanSuccessCount = 0
        scanFailCount    = 0
        doneCount        = 0
        -- totalEver was already set as items were queued; don't reset it here
        failedQueue      = {}
        isRetryPass      = false
        GAM.Log.Info(GAM.L["SCAN_STARTED"], totalEver)
    else
        GAM.Log.Info("AHScan: resumed with %d of %d items complete", doneCount, totalEver)
    end
    FireProgress(false)

    ticker = C_Timer.NewTicker(0.5, function()
        ProcessNextInQueue()
    end)
end

function AHScan.StopScan()
    scanning = false
    if ticker then ticker:Cancel(); ticker = nil end
    InvalidatePendingAttempt()
    AHScan._pendingResume = false
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

function AHScan.GetQueueSnapshot()
    local out = {}
    for i = queueHead, #scanQueue do
        local entry = scanQueue[i]
        out[#out + 1] = {
            itemID = entry.itemID,
            name = entry.name,
            isNameScan = entry.isNameScan and true or false,
            patchTag = entry.patchTag,
            reasons = entry.reasons or {},
            strategyKeys = entry.strategyKeys or {},
        }
    end
    return out
end

function AHScan.GetDiagnostics()
    local out = {}
    for index, diagnostic in ipairs(completedDiagnostics) do
        local copy = {
            itemID = diagnostic.itemID,
            name = diagnostic.name,
            outcome = diagnostic.outcome,
            duration = diagnostic.duration,
            queryAttempts = diagnostic.queryAttempts,
            moreRequests = diagnostic.moreRequests,
            events = {},
        }
        for eventIndex, event in ipairs(diagnostic.events or {}) do
            copy.events[eventIndex] = {
                at = event.at,
                event = event.event,
                detail = event.detail,
            }
        end
        out[index] = copy
    end
    return out
end

-- Reset queuing dedup tables (call before building a new scan queue)
function AHScan.ResetQueue()
    scanning = false
    if ticker then ticker:Cancel(); ticker = nil end
    InvalidatePendingAttempt()
    AHScan._pendingResume = false
    scanQueue       = {}
    queueHead       = 1
    failedQueue     = {}
    priceScanQueued = {}
    nameScanQueued  = {}
    totalEver       = 0
    doneCount       = 0
    completedDiagnostics = {}
    -- Clear session caches so old raw arrays are GC'd before the next scan.
    Results.ClearSessionCaches()
end
