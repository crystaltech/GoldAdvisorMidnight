local scheduled = {}
local tickerCallback = nil
local commodityRows = {}
local itemRows = {}
local storedPrices = {}
local browseRows = {}
local browseResultsComplete = true
local throttleReady = true
local searchQueryCount = 0
local browseQueryCount = 0
local lastSearchKey = nil

function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function GetTime()
    return 100
end

function time()
    return 123456
end

function GetItemInfo()
    return nil
end

C_Timer = {
    After = function(delay, callback)
        scheduled[#scheduled + 1] = { delay = delay, callback = callback }
    end,
    NewTicker = function(_, callback)
        tickerCallback = callback
        return { Cancel = function() end }
    end,
}

C_AuctionHouse = {
    MakeItemKey = function(itemID, itemLevel, itemSuffix, battlePetSpeciesID)
        return {
            itemID = itemID,
            itemLevel = itemLevel,
            itemSuffix = itemSuffix,
            battlePetSpeciesID = battlePetSpeciesID,
        }
    end,
    IsThrottledMessageSystemReady = function() return throttleReady end,
    SendSearchQuery = function(itemKey)
        searchQueryCount = searchQueryCount + 1
        lastSearchKey = itemKey
    end,
    SendBrowseQuery = function()
        browseQueryCount = browseQueryCount + 1
    end,
    HasFullBrowseResults = function() return browseResultsComplete end,
    GetBrowseResults = function() return browseRows end,
    GetNumCommoditySearchResults = function(itemID)
        return #(commodityRows[itemID] or {})
    end,
    GetCommoditySearchResultInfo = function(itemID, index)
        return (commodityRows[itemID] or {})[index]
    end,
    GetNumItemSearchResults = function(itemKey)
        return #(itemRows[itemKey.itemID] or {})
    end,
    GetItemSearchResultInfo = function(itemKey, index)
        return (itemRows[itemKey.itemID] or {})[index]
    end,
}

local GAM = {
    C = {
        SCAN_DELAY = 0,
        RESULT_WAIT = 10,
        RESULT_RETRY_DELAY = 0.25,
        MAX_RETRY = 1,
        EVENT_PROCESS_DELAY = 0,
        DEFAULT_FILL_QTY = 50,
        DEFAULT_PATCH = "midnight-1",
    },
    L = {
        SCAN_AH_CLOSED = "scan paused",
        SCAN_COMPLETE = "scan complete",
        SCAN_THROTTLED = "scan throttled",
        SCAN_STARTED = "scan started",
        ERR_NO_AH = "auction house closed",
    },
    Log = {
        Debug = function() end,
        Info = function() end,
        Warn = function() end,
    },
    Pricing = {
        StorePrice = function(itemID, average, minimum)
            storedPrices[#storedPrices + 1] = {
                itemID = itemID,
                average = average,
                minimum = minimum,
            }
        end,
        GetUnitPrice = function() return nil end,
    },
    State = {
        GetItemKeyDB = function() return {} end,
    },
    ahOpen = true,
}

function GAM:GetOptions()
    return { shallowFillQty = 50 }
end

function GAM:GetPatchDB()
    return { rankGroups = {} }
end

local chunk = assert(loadfile("AHScan.lua"))
chunk("GoldAdvisorMidnight", GAM)
local AHScan = GAM.AHScan

local function Tick()
    assert(tickerCallback, "scanner ticker is unavailable")
    tickerCallback()
end

local function RunScheduledDelay(delay)
    for index, task in ipairs(scheduled) do
        if task.delay == delay then
            table.remove(scheduled, index)
            task.callback()
            return true
        end
    end
    return false
end

local function AssertProgress(done, total, successes, failures, label)
    local actualDone, actualTotal, actualSuccesses, actualFailures = AHScan.GetProgress()
    assert(actualDone == done, label .. " done count")
    assert(actualTotal == total, label .. " total count")
    assert(actualSuccesses == successes, label .. " success count")
    assert(actualFailures == failures, label .. " failure count")
end

-- A delayed result from a canceled session must not store a price or clear the
-- pending request belonging to the replacement session.
AHScan.ResetQueue()
AHScan.QueueItemScan(101)
AHScan.StartScan()
Tick()
commodityRows[101] = { { unitPrice = 100, quantity = 50 } }
AHScan.OnCommodityResults(101)

AHScan.ResetQueue()
AHScan.QueueItemScan(202)
AHScan.StartScan()
Tick()
assert(RunScheduledDelay(0), "stale commodity callback was not scheduled")
assert(#storedPrices == 0, "stale commodity callback stored a price")
assert(AHScan.IsScanning(), "stale commodity callback stopped the replacement scan")

commodityRows[202] = { { unitPrice = 200, quantity = 50 } }
AHScan.OnCommodityResults(202)
assert(RunScheduledDelay(0), "current commodity callback was not scheduled")
assert(#storedPrices == 1 and storedPrices[1].itemID == 202,
    "current commodity result was not stored")
AssertProgress(1, 1, 1, 0, "replacement scan")

-- Non-commodity result processing has its own delayed callback and must obey
-- the same attempt boundary.
AHScan.ResetQueue()
AHScan.QueueItemScan(505)
AHScan.StartScan()
Tick()
itemRows[505] = { { buyoutAmount = 500, quantity = 1 } }
AHScan.OnItemResults({ itemID = 505 })

AHScan.ResetQueue()
AHScan.QueueItemScan(606)
AHScan.StartScan()
Tick()
assert(RunScheduledDelay(0), "stale item callback was not scheduled")
assert(#storedPrices == 1, "stale item callback stored a price")
assert(AHScan.IsScanning(), "stale item callback stopped the replacement scan")

itemRows[606] = { { buyoutAmount = 606, quantity = 1 } }
AHScan.OnItemResults({ itemID = 606 })
assert(RunScheduledDelay(0), "current item callback was not scheduled")
assert(#storedPrices == 2 and storedPrices[2].itemID == 606,
    "current item result was not stored")
AssertProgress(1, 1, 1, 0, "replacement item scan")

-- A recoverable first-pass failure remains pending until the retry resolves;
-- it must not inflate done/failure counts before then.
AHScan.ResetQueue()
AHScan.QueueItemScan(303)
AHScan.StartScan()
Tick()
AHScan.OnCommodityResults(303)
assert(RunScheduledDelay(0), "first-pass failure callback was not scheduled")
AssertProgress(0, 1, 0, 0, "first-pass retry queue")
Tick() -- switch to retry pass
Tick() -- send retry query
AHScan.OnCommodityResults(303)
assert(RunScheduledDelay(0), "retry failure callback was not scheduled")
AssertProgress(1, 1, 0, 1, "permanent retry failure")

-- Closing the Auction House pauses and requeues the in-flight entry. A delayed
-- pre-pause callback cannot complete the resumed attempt, even though the same
-- entry table is reused.
AHScan.ResetQueue()
AHScan.QueueItemScan(404)
AHScan.StartScan()
Tick()
commodityRows[404] = { { unitPrice = 400, quantity = 50 } }
AHScan.OnCommodityResults(404)
GAM.ahOpen = false
AHScan.OnAHClosed()
assert(not AHScan.IsScanning() and AHScan._pendingResume,
    "Auction House close did not pause the scan")

GAM.ahOpen = true
AHScan.StartScan()
Tick()
assert(RunScheduledDelay(0), "pre-pause callback was not scheduled")
assert(#storedPrices == 2, "pre-pause callback stored a stale price")
assert(AHScan.IsScanning(), "pre-pause callback stopped the resumed scan")

AHScan.OnCommodityResults(404)
assert(RunScheduledDelay(0), "resumed callback was not scheduled")
assert(#storedPrices == 3 and storedPrices[3].itemID == 404,
    "resumed scan did not store its result")
AssertProgress(1, 1, 1, 0, "resumed scan")

-- Duplicate result events for one attempt may schedule twice, but only the
-- first callback can complete and store that attempt.
scheduled = {}
AHScan.ResetQueue()
AHScan.QueueItemScan(707)
AHScan.StartScan()
Tick()
commodityRows[707] = { { unitPrice = 707, quantity = 50 } }
AHScan.OnCommodityResults(707)
AHScan.OnCommodityResults(707)
assert(RunScheduledDelay(0), "first duplicate event was not scheduled")
assert(RunScheduledDelay(0), "second duplicate event was not scheduled")
assert(#storedPrices == 4 and storedPrices[4].itemID == 707,
    "duplicate events stored more than one result")
AssertProgress(1, 1, 1, 0, "duplicate result event")

-- Throttling must leave the queue head untouched until Blizzard reports that
-- another request can be sent.
scheduled = {}
AHScan.ResetQueue()
AHScan.QueueItemScan(808)
AHScan.StartScan()
local queriesBeforeThrottle = searchQueryCount
throttleReady = false
Tick()
assert(searchQueryCount == queriesBeforeThrottle,
    "throttled tick sent a query")
AssertProgress(0, 1, 0, 0, "throttled queue")
throttleReady = true
Tick()
assert(searchQueryCount == queriesBeforeThrottle + 1,
    "queue did not resume after throttle cleared")
commodityRows[808] = { { unitPrice = 808, quantity = 50 } }
AHScan.OnCommodityResults(808)
assert(RunScheduledDelay(0), "post-throttle result was not scheduled")
AssertProgress(1, 1, 1, 0, "post-throttle queue")

-- Each timed-out item receives exactly one retry and one terminal failure.
scheduled = {}
AHScan.ResetQueue()
AHScan.QueueItemScan(909)
AHScan.StartScan()
Tick()
assert(RunScheduledDelay(10), "first-pass timeout was not scheduled")
AssertProgress(0, 1, 0, 0, "first-pass timeout")
Tick() -- move the failed entry into the retry pass
Tick() -- send its retry query
assert(RunScheduledDelay(10), "retry timeout was not scheduled")
AssertProgress(1, 1, 0, 1, "retry timeout")

-- A zero-row commodity can discover its full item key through browse once,
-- then requeue and price the corrected key without a second fallback loop.
scheduled = {}
browseRows = {}
browseResultsComplete = true
AHScan.ResetQueue()
AHScan.QueueStratListItems({ {
    id = "browse-fallback-fixture",
    outputs = { { name = "Fallback Commodity", itemIDs = { 1001 } } },
    reagents = {},
} }, "midnight-1")
AHScan.StartScan()
Tick()
commodityRows[1001] = {}
AHScan.OnCommodityResults(1001)
assert(RunScheduledDelay(0), "zero-row commodity event was not scheduled")
local browseBeforeFallback = browseQueryCount
assert(RunScheduledDelay(0), "browse fallback send was not scheduled")
assert(browseQueryCount == browseBeforeFallback + 1,
    "browse fallback query was not sent exactly once")

browseRows = { {
    itemKey = {
        itemID = 1001,
        itemLevel = 0,
        itemSuffix = 42,
        battlePetSpeciesID = 0,
    },
} }
AHScan.OnBrowseResults()
assert(RunScheduledDelay(0), "browse fallback result was not scheduled")
AssertProgress(1, 2, 1, 0, "browse discovery")

Tick()
assert(lastSearchKey and lastSearchKey.itemID == 1001
        and lastSearchKey.itemSuffix == 42,
    "browse fallback did not requery the discovered full item key")
commodityRows[1001] = { { unitPrice = 1001, quantity = 50 } }
AHScan.OnCommodityResults(1001)
assert(RunScheduledDelay(0), "corrected commodity result was not scheduled")
AssertProgress(2, 2, 2, 0, "browse fallback completion")

print("PASS: AH scan attempts cover stale, duplicate, throttle, timeout, retry, pause, and browse fallback lifecycles")
