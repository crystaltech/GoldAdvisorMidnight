-- GoldAdvisorMidnight/AuctionHouseQuery.lua
-- Small, testable boundary around Blizzard Auction House query capabilities.
-- Lifecycle patterns are adapted from CraftSimEnhancer's MIT-licensed scanner.
-- Module: GAM.AuctionHouseQuery

local ADDON_NAME, GAM = ...
local Query = {}
GAM.AuctionHouseQuery = Query

function Query.IsThrottleReady()
    return C_AuctionHouse
        and C_AuctionHouse.IsThrottledMessageSystemReady
        and C_AuctionHouse.IsThrottledMessageSystemReady()
end

function Query.SendSearch(itemKey)
    if not (C_AuctionHouse and C_AuctionHouse.SendSearchQuery and itemKey) then
        return false, "SendSearchQuery unavailable"
    end
    return pcall(C_AuctionHouse.SendSearchQuery, itemKey, {}, false)
end

function Query.SendBrowse(name)
    if not (C_AuctionHouse and C_AuctionHouse.SendBrowseQuery and name) then
        return false, "SendBrowseQuery unavailable"
    end
    return pcall(C_AuctionHouse.SendBrowseQuery, {
        searchString = name,
        minLevel = 0,
        maxLevel = 0,
        filters = {},
        itemClassFilters = {},
        sorts = {},
    })
end

function Query.ItemKeysMatch(expected, actual)
    if not (expected and actual) then return false end
    if tonumber(expected.itemID) ~= tonumber(actual.itemID) then return false end
    for _, field in ipairs({ "itemLevel", "itemSuffix", "battlePetSpeciesID" }) do
        local wanted = tonumber(expected[field]) or 0
        local observed = tonumber(actual[field]) or 0
        if wanted ~= 0 and observed ~= 0 and wanted ~= observed then return false end
    end
    return true
end

function Query.HasFullResults(resultType, itemID, itemKey)
    local api, argument
    if resultType == "commodity" then
        api, argument = C_AuctionHouse.HasFullCommoditySearchResults, itemID
    else
        api, argument = C_AuctionHouse.HasFullItemSearchResults, itemKey
    end
    if type(api) ~= "function" then return nil end
    local ok, full = pcall(api, argument)
    if not ok then return nil end
    return full == true
end

function Query.RequestMoreResults(resultType, itemID, itemKey)
    local api, argument
    if resultType == "commodity" then
        api, argument = C_AuctionHouse.RequestMoreCommoditySearchResults, itemID
    else
        api, argument = C_AuctionHouse.RequestMoreItemSearchResults, itemKey
    end
    if type(api) ~= "function" then return false, nil end
    local ok, full = pcall(api, argument)
    return ok, full
end

function Query.NewDiagnostic(entry, attempt)
    entry.queryAttempts = (entry.queryAttempts or 0) + 1
    entry.moreRequests = 0
    entry.emptyResultRetrySent = false
    entry.queryStartedAt = GetTime()
    entry.firstQueryStartedAt = entry.firstQueryStartedAt or entry.queryStartedAt
    entry.lastResultType = nil
    entry.diagnosticEvents = entry.diagnosticEvents or {}
    entry.diagnosticEvents[#entry.diagnosticEvents + 1] = {
        at = entry.queryStartedAt,
        event = "SEND",
        detail = tostring(attempt),
    }
end

function Query.Record(entry, event, detail)
    if not entry then return end
    entry.diagnosticEvents = entry.diagnosticEvents or {}
    entry.diagnosticEvents[#entry.diagnosticEvents + 1] = {
        at = GetTime(),
        event = event,
        detail = detail,
    }
end

function Query.Snapshot(entry, outcome)
    local events = {}
    for index, event in ipairs(entry and entry.diagnosticEvents or {}) do
        events[index] = { at = event.at, event = event.event, detail = event.detail }
    end
    local startedAt = entry and (entry.firstQueryStartedAt or entry.queryStartedAt)
    return {
        itemID = entry and entry.itemID,
        name = entry and entry.name,
        outcome = outcome,
        duration = startedAt and math.max(0, GetTime() - startedAt) or 0,
        queryAttempts = entry and (entry.queryAttempts or 0) or 0,
        moreRequests = entry and (entry.moreRequests or 0) or 0,
        events = events,
    }
end
