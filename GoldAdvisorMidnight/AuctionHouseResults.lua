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
    local db = GAM.db or _G[ADDON_NAME .. "DB"]
    return (db and db.itemKeyDB) or {}
end

local function NormalizeTargetQty(targetQty)
    local qty = tonumber(targetQty) or GAM.C.MARKET_SAMPLE_UNITS or 50
    return math.max(1, math.floor(qty + 0.5))
end

local function EnsureResultsSorted(results)
    if not results or results._gamSortedByUnitPrice then return end
    table.sort(results, function(a, b)
        return (a.unitPrice or math.huge) < (b.unitPrice or math.huge)
    end)
    results._gamSortedByUnitPrice = true
end

-- Lower quartile fence (Q1 - 1.5 x IQR, as in CraftSimEnhancer) over the
-- first `window` units, computed on price buckets instead of one entry per
-- unit. When most units share one price (IQR 0) anything cheaper is bait.
-- Returns nil when there are too few units to judge.
local function LowerFence(rows, window)
    local buckets, total = {}, 0
    for _, row in ipairs(rows) do
        local price = row and tonumber(row.unitPrice)
        local available = row and (tonumber(row.quantity) or 0) or 0
        if price and price > 0 and available > 0 then
            local take = math.min(available, window - total)
            if take <= 0 then break end
            buckets[#buckets + 1] = { price, take }
            total = total + take
        end
    end
    if total < (GAM.C.MARKET_FENCE_MIN_UNITS or 8) then return nil end
    local function Quantile(p)
        local target, seen = math.max(1, math.floor((total + 1) * p)), 0
        for _, bucket in ipairs(buckets) do
            seen = seen + bucket[2]
            if seen >= target then return bucket[1] end
        end
        return buckets[#buckets][1]
    end
    local q1, q3 = Quantile(0.25), Quantile(0.75)
    local iqr = q3 - q1
    if iqr <= 0 then return q1 end
    return math.max(0, q1 - 1.5 * iqr)
end

-- Cost of buying `targetQty` units, erring toward the higher price:
--   * bait below the lower fence is skipped, so it cannot make inputs look cheap;
--   * expensive units inside the quantity are kept, because they would be paid;
--   * units the market does not list are priced at the highest listed price.
-- One unit is the sell-side quote: the lowest listing, bait included, so sale
-- prices are never raised by filtering. The second return is always that raw
-- lowest listing. Returns avg, lowest, highest, filledUnits, depth.
function Results.ComputeStatsFromRows(rows, targetQty)
    if not rows or #rows == 0 then return nil end
    targetQty = NormalizeTargetQty(targetQty)
    EnsureResultsSorted(rows)

    local lowest
    for _, row in ipairs(rows) do
        local price = row and tonumber(row.unitPrice)
        if price and price > 0 and (tonumber(row.quantity) or 0) > 0 then lowest = price; break end
    end
    if not lowest then return nil end

    local fence = targetQty > 1 and LowerFence(rows, math.max(targetQty, GAM.C.MARKET_SAMPLE_UNITS or 50)) or nil
    local function Fill(skipBelow)
        local filled, sum, highest, bait = 0, 0, nil, 0
        for _, row in ipairs(rows) do
            local price = row and tonumber(row.unitPrice)
            local available = row and (tonumber(row.quantity) or 0) or 0
            if price and price > 0 and available > 0 then
                if skipBelow and price < skipBelow then
                    bait = bait + available
                else
                    local take = math.min(available, targetQty - filled)
                    if take > 0 then
                        filled, sum, highest = filled + take, sum + price * take, price
                    end
                    if filled >= targetQty then break end
                end
            end
        end
        return filled, sum, highest, bait
    end
    local filled, sum, highest, bait = Fill(fence)
    if filled == 0 then
        -- Everything was below the fence: too odd a market to call bait.
        fence = nil
        filled, sum, highest, bait = Fill(nil)
    end

    -- Every unit not filled from real-price listings costs the highest listed
    -- price. Skipped bait still exists, so it counts toward availability (at
    -- that higher price) rather than making the market look thin.
    local shortfall = targetQty - filled
    local avg = (sum + shortfall * highest) / targetQty
    local available = filled + math.min(shortfall, bait)
    return avg, lowest, highest, available, {
        requested = targetQty,
        filled = available,
        incomplete = available < targetQty,
        baitUnits = bait,
        lowerFence = fence,
    }
end

-- Compact price-by-quantity summary saved with each scanned price, so the
-- needed-quantity cost (bait rule and short-market rule included) is still
-- known after /reload, when the live listings are gone.
function Results.BuildDepthCurve(rows)
    if not rows or #rows == 0 then return nil end
    local points = {}
    for _, qty in ipairs(GAM.C.DEPTH_CURVE_POINTS or {}) do
        local avg = Results.ComputeStatsFromRows(rows, qty)
        if avg then points[#points + 1] = { qty, math.floor(avg + 0.5) } end
    end
    return #points > 0 and { listed = Results.GetListedQuantity(rows), points = points } or nil
end

-- Needed-quantity cost from a saved curve. Quantities between saved points
-- are interpolated; smaller ones use the first point (never cheaper than
-- that sample); larger ones use the last point.
function Results.PriceFromCurve(curve, qty)
    local points = curve and curve.points
    if not (points and #points > 0 and qty and qty > 0) then return nil end
    if qty <= points[1][1] then return points[1][2] end
    for index = 2, #points do
        local lowQty, lowAvg = points[index - 1][1], points[index - 1][2]
        local highQty, highAvg = points[index][1], points[index][2]
        if qty <= highQty then
            return lowAvg + (highAvg - lowAvg) * (qty - lowQty) / (highQty - lowQty)
        end
    end
    return points[#points][2]
end

function Results.ComputeStatsForCache(cached, targetQty)
    if not (cached and cached.prices and #cached.prices > 0) then return nil end
    local normalizedQty = NormalizeTargetQty(targetQty)
    cached.statsByQty = cached.statsByQty or {}
    local stats = cached.statsByQty[normalizedQty]
    if not stats then
        local avg, minPrice, maxPrice, count, depth = Results.ComputeStatsFromRows(cached.prices, normalizedQty)
        if not avg then return nil end
        stats = { avg = avg, minP = minPrice, maxP = maxPrice, count = count, depth = depth }
        cached.statsByQty[normalizedQty] = stats
    end
    return stats.avg, stats.minP, stats.maxP, stats.count, stats.depth
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
    if GAM.State and GAM.State.BumpPriceRevision then GAM.State.BumpPriceRevision() end
    return Results.ComputeStatsForCache(cached, targetQty)
end

function Results.StoreItemRows(itemID, rows, targetQty)
    if not rows or #rows == 0 then return nil end
    local cached = { prices = rows, ts = time() }
    itemCache[itemID] = cached
    if GAM.State and GAM.State.BumpPriceRevision then GAM.State.BumpPriceRevision() end
    return Results.ComputeStatsForCache(cached, targetQty)
end

function Results.ComputePriceForQty(itemID, requiredQty)
    if not itemID or not requiredQty or requiredQty <= 0 then return nil end
    local cached
    if commodityCache[itemID] and #commodityCache[itemID].prices > 0 then
        cached = commodityCache[itemID]
    elseif itemCache[itemID] and #itemCache[itemID].prices > 0 then
        cached = itemCache[itemID]
    end
    if cached then
        local avg, minPrice, maxPrice, count, depth = Results.ComputeStatsForCache(cached, requiredQty)
        local stale = not cached.ts or (time() - cached.ts) > (GAM.C.PRICE_STALE_SECONDS or 600)
        return avg, minPrice, maxPrice, count, stale, depth
    end
    if GAM.Pricing and GAM.Pricing.GetRawCache then
        local raw = GAM.Pricing.GetRawCache(itemID)
        if raw and #raw > 0 then
            local avg, minPrice, maxPrice, count, depth = Results.ComputeStatsFromRows(raw, requiredQty)
            -- Legacy raw rows have no timestamp of their own.
            local _, stale = GAM.Pricing.GetUnitPrice(itemID)
            return avg, minPrice, maxPrice, count, stale ~= false, depth
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
    if GAM.State and GAM.State.BumpPriceRevision then GAM.State.BumpPriceRevision() end
end
