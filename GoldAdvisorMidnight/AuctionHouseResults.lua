-- GoldAdvisorMidnight/AuctionHouseResults.lua
-- Auction result collection, item-key persistence, raw depth caches, and
-- quantity-aware price statistics. Query lifecycle belongs to AuctionHouseQuery.
-- Module: GAM.AuctionHouseResults

local ADDON_NAME, GAM = ...
local Results = {}
GAM.AuctionHouseResults = Results

local itemKeyCache  = {}
local commodityCache = {}
local itemCache      = {}

local function GetOpts()
    return (GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {}
end

local function GetItemKeyDB()
    if GAM.State and GAM.State.GetItemKeyDB then
        return GAM.State.GetItemKeyDB()
    end
    return (GoldAdvisorMidnightDB and GoldAdvisorMidnightDB.itemKeyDB) or {}
end

local function NormalizeTargetQty(targetQty)
    local qty = tonumber(targetQty) or GetOpts().shallowFillQty or GAM.C.DEFAULT_FILL_QTY
    return math.max(1, math.floor(qty + 0.5))
end

local function EnsureResultsSorted(results)
    if not results or results._gamSortedByUnitPrice then return end
    table.sort(results, function(a, b)
        return (a.unitPrice or math.huge) < (b.unitPrice or math.huge)
    end)
    results._gamSortedByUnitPrice = true
end

-- Fill from the cheapest listing buckets, then remove GAM's configured top
-- percentage. This intentionally preserves GAM pricing semantics.
function Results.ComputeStatsFromRows(rows, targetQty)
    if not rows or #rows == 0 then return nil end
    targetQty = NormalizeTargetQty(targetQty)
    EnsureResultsSorted(rows)

    local totalUnits, totalSum = 0, 0
    local minPrice, maxPrice, lastIndex, lastTake
    for index, row in ipairs(rows) do
        local price = row and tonumber(row.unitPrice)
        local available = row and (tonumber(row.quantity) or 0) or 0
        if price and price > 0 and available > 0 then
            local take = math.min(available, targetQty - totalUnits)
            if take > 0 then
                minPrice = minPrice or price
                maxPrice = price
                totalUnits = totalUnits + take
                totalSum = totalSum + (price * take)
                lastIndex = index
                lastTake = take
            end
            if totalUnits >= targetQty then break end
        end
    end
    if totalUnits == 0 then return nil end

    local trimCount = math.floor(totalUnits * ((GAM.C.TRIM_PCT or 2) / 100))
    if trimCount >= totalUnits then trimCount = totalUnits - 1 end

    local removedSum, remainingTrim = 0, trimCount
    local keptMaxPrice = maxPrice
    if remainingTrim > 0 and lastIndex then
        keptMaxPrice = nil
        for index = lastIndex, 1, -1 do
            local row = rows[index]
            local price = row and tonumber(row.unitPrice)
            local rowTake = index == lastIndex and lastTake or (row and (tonumber(row.quantity) or 0) or 0)
            if price and price > 0 and rowTake > 0 then
                if remainingTrim <= 0 then
                    keptMaxPrice = price
                    break
                end
                local remove = math.min(rowTake, remainingTrim)
                removedSum = removedSum + (remove * price)
                remainingTrim = remainingTrim - remove
                if remove < rowTake then
                    keptMaxPrice = price
                    break
                end
            end
        end
    end

    local kept = totalUnits - trimCount
    return (totalSum - removedSum) / kept, minPrice, keptMaxPrice or minPrice, kept
end

function Results.ComputeStatsForCache(cached, targetQty)
    if not (cached and cached.prices and #cached.prices > 0) then return nil end
    local normalizedQty = NormalizeTargetQty(targetQty)
    cached.statsByQty = cached.statsByQty or {}
    local stats = cached.statsByQty[normalizedQty]
    if not stats then
        local avg, minPrice, maxPrice, count = Results.ComputeStatsFromRows(cached.prices, normalizedQty)
        if not avg then return nil end
        stats = { avg = avg, minP = minPrice, maxP = maxPrice, count = count }
        cached.statsByQty[normalizedQty] = stats
    end
    return stats.avg, stats.minP, stats.maxP, stats.count
end

function Results.GetCachedItemKey(itemID)
    if not itemID or itemID == 0 then return nil end
    if itemKeyCache[itemID] then return itemKeyCache[itemID] end
    local saved = GetItemKeyDB()[itemID]
    if saved then
        itemKeyCache[itemID] = C_AuctionHouse.MakeItemKey(
            itemID, saved.itemLevel or 0, saved.itemSuffix or 0, saved.battlePetSpeciesID or 0)
    else
        itemKeyCache[itemID] = C_AuctionHouse.MakeItemKey(itemID, 0, 0, 0)
    end
    return itemKeyCache[itemID]
end

function Results.StoreDiscoveredItemKey(itemKey)
    if not (itemKey and itemKey.itemID) then return end
    local itemID = itemKey.itemID
    itemKeyCache[itemID] = itemKey
    if itemKey.itemLevel ~= 0 or itemKey.itemSuffix ~= 0 or itemKey.battlePetSpeciesID ~= 0 then
        local db = GetItemKeyDB()
        db[itemID] = {
            itemLevel = itemKey.itemLevel or 0,
            itemSuffix = itemKey.itemSuffix or 0,
            battlePetSpeciesID = itemKey.battlePetSpeciesID or 0,
        }
    end
end

function Results.PreWarmItemKeys()
    local count = 0
    for itemID, saved in pairs(GetItemKeyDB()) do
        if not itemKeyCache[itemID] then
            itemKeyCache[itemID] = C_AuctionHouse.MakeItemKey(
                itemID, saved.itemLevel or 0, saved.itemSuffix or 0, saved.battlePetSpeciesID or 0)
            count = count + 1
        end
    end
    return count
end

function Results.ReadCommodityRows(itemID)
    local ok, numResults = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
    if not ok or not numResults then return {} end
    local rows = {}
    for index = 1, numResults do
        local rowOK, result = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, index)
        local price = rowOK and result and tonumber(result.unitPrice)
        local quantity = rowOK and result and (tonumber(result.quantity) or 0) or 0
        if price and price > 0 and quantity > 0 then
            rows[#rows + 1] = { unitPrice = price, quantity = quantity }
        end
    end
    EnsureResultsSorted(rows)
    return rows
end

function Results.ReadItemRows(itemKey)
    if not itemKey then return {} end
    local ok, numResults = pcall(C_AuctionHouse.GetNumItemSearchResults, itemKey)
    if not ok or not numResults then return {} end
    local rows = {}
    for index = 1, numResults do
        local rowOK, result = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, index)
        if rowOK and result and result.buyoutAmount and result.buyoutAmount > 0 then
            local quantity = tonumber(result.quantity) or 1
            rows[#rows + 1] = {
                unitPrice = math.floor(result.buyoutAmount / quantity),
                quantity = quantity,
            }
        end
    end
    EnsureResultsSorted(rows)
    return rows
end

function Results.GetListedQuantity(rows)
    local quantity = 0
    for _, row in ipairs(rows or {}) do
        quantity = quantity + (tonumber(row.quantity) or 0)
    end
    return quantity
end

function Results.StoreCommodityRows(itemID, rows, targetQty)
    if not rows or #rows == 0 then return nil end
    local cached = { prices = rows, ts = time() }
    commodityCache[itemID] = cached
    return Results.ComputeStatsForCache(cached, targetQty)
end

function Results.StoreItemRows(itemID, rows, targetQty)
    if not rows or #rows == 0 then return nil end
    local cached = { prices = rows, ts = time() }
    itemCache[itemID] = cached
    return Results.ComputeStatsForCache(cached, targetQty)
end

function Results.ComputePriceForQty(itemID, requiredQty)
    if not itemID or not requiredQty or requiredQty <= 0 then return nil end
    if commodityCache[itemID] and #commodityCache[itemID].prices > 0 then
        return Results.ComputeStatsForCache(commodityCache[itemID], requiredQty)
    end
    if itemCache[itemID] and #itemCache[itemID].prices > 0 then
        return Results.ComputeStatsForCache(itemCache[itemID], requiredQty)
    end
    if GAM.Pricing and GAM.Pricing.GetRawCache then
        local raw = GAM.Pricing.GetRawCache(itemID)
        if raw and #raw > 0 then
            return Results.ComputeStatsFromRows(raw, requiredQty)
        end
    end
    return nil
end

function Results.GetCachedResults(itemID)
    return commodityCache[itemID]
end

function Results.GetRawScanSnapshot(itemID)
    if not itemID then return nil end
    local source, cached
    if commodityCache[itemID] and #commodityCache[itemID].prices > 0 then
        source, cached = "commodity", commodityCache[itemID]
    elseif itemCache[itemID] and #itemCache[itemID].prices > 0 then
        source, cached = "item", itemCache[itemID]
    end
    if not cached then return nil end

    local prices = {}
    for index, row in ipairs(cached.prices) do
        prices[index] = { unitPrice = row.unitPrice, quantity = row.quantity or 0 }
    end
    table.sort(prices, function(a, b)
        if a.unitPrice == b.unitPrice then return a.quantity > b.quantity end
        return a.unitPrice < b.unitPrice
    end)
    return { itemID = itemID, source = source, ts = cached.ts, prices = prices }
end

function Results.ClearSessionCaches()
    wipe(commodityCache)
    wipe(itemCache)
end
