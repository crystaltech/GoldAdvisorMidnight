-- GoldAdvisorMidnight/Pricing.lua
-- Pricing engine: price lookup, effective price, strat metrics.
-- Module: GAM.Pricing

local ADDON_NAME, GAM = ...
local Pricing = {}
GAM.Pricing = Pricing

-- ===== Internal helpers =====

local function GetDB() return GAM.db end
local function GetOpts() return GAM.db.options end
local function GetPatchDB(pt) return GAM:GetPatchDB(pt) end

-- Pick best itemID from a list according to rankPolicy
local function PickItemID(itemIDs, patchTag)
    if not itemIDs or #itemIDs == 0 then return nil end
    if #itemIDs == 1 then return itemIDs[1] end
    local policy = GetOpts().rankPolicy or "lowest"
    if policy == "highest" then
        return itemIDs[#itemIDs]
    elseif policy == "lowest" then
        return itemIDs[1]
    else
        -- "manual" — use highest as fallback (user sets via StratDetail rank picker)
        return itemIDs[#itemIDs]
    end
end

-- ===== Public API =====

-- GetUnitPrice(itemID) → price in copper, or nil
-- Reads from realm-scoped price cache.
function Pricing.GetUnitPrice(itemID)
    if not itemID then return nil end
    local cache = GAM:GetRealmCache()
    local entry = cache[itemID]
    if not entry then return nil end
    -- Stale check
    local staleThresh = GAM.C.PRICE_STALE_SECONDS
    if (time() - (entry.ts or 0)) > staleThresh then
        return entry.price, true  -- price, isStale
    end
    return entry.price, false
end

-- GetEffectivePrice(itemID, patchTag) → price in copper, or nil
-- Priority: override > AH cache > CraftSim bridge
function Pricing.GetEffectivePrice(itemID, patchTag)
    if not itemID then return nil end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local opts = GetOpts()

    -- 1. Manual override (use ~= nil so an explicit 0 override is honoured)
    local pdb = GetPatchDB(patchTag)
    if pdb.priceOverrides and pdb.priceOverrides[itemID] ~= nil then
        return pdb.priceOverrides[itemID], false
    end

    -- 2. CraftSim (if selected as source)
    if opts.priceSource == "craftsim" and GAM.CraftSimBridge then
        local csPrice = GAM.CraftSimBridge.GetPrice(itemID)
        if csPrice and csPrice > 0 then
            return csPrice, false
        end
    end

    -- 3. AH cache
    return Pricing.GetUnitPrice(itemID)
end

-- GetEffectivePriceForItem(item, patchTag) → price, isStale
-- item = { name, itemIDs = {}, ... }
-- Used for REAGENT pricing: tries the rank-policy preferred itemID first, then
-- falls back through remaining variants (you'd buy the cheapest available rank).
function Pricing.GetEffectivePriceForItem(item, patchTag)
    if not item then return nil, false end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GetPatchDB(patchTag)

    -- Resolve itemIDs: use rankGroups if item.itemIDs is empty
    local ids = item.itemIDs
    if (not ids or #ids == 0) and item.name then
        ids = pdb.rankGroups[item.name] or {}
    end

    if not ids or #ids == 0 then return nil, false end

    local picked = PickItemID(ids, patchTag)
    if not picked then return nil, false end

    -- Try preferred itemID first
    local price, isStale = Pricing.GetEffectivePrice(picked, patchTag)
    if price then return price, isStale end

    -- Fallback: check remaining quality variants in array order
    for _, id in ipairs(ids) do
        if id ~= picked then
            local p, s = Pricing.GetEffectivePrice(id, patchTag)
            if p then return p, s end
        end
    end

    return nil, false
end

-- GetOutputPriceForItem(item, patchTag) → price, isStale
-- Used for OUTPUT pricing: crafted/milled outputs produce a random mix of quality
-- tiers. Returns the average price across all ranked variants that have AH data,
-- giving a more accurate revenue estimate than any single rank's price.
-- Applies a cross-rank trim: ranks priced more than RANK_TRIM × the cheapest
-- rank are excluded (a thin/niche high-rank market, e.g. one listing at 5000g
-- when rank 1 is 285g, should not inflate the expected revenue estimate).
-- Falls back to single-rank behaviour when only one rank has data.
local RANK_TRIM = 3.0

local function GetOutputPriceForItem(item, patchTag)
    if not item then return nil, false end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GetPatchDB(patchTag)

    local ids = item.itemIDs
    if (not ids or #ids == 0) and item.name then
        ids = pdb.rankGroups[item.name] or {}
    end
    if not ids or #ids == 0 then return nil, false end

    -- Single rank: no averaging needed
    if #ids == 1 then
        return Pricing.GetEffectivePrice(ids[1], patchTag)
    end

    -- Multiple ranks: collect all prices that have AH data
    local prices, anyStale = {}, false
    for _, id in ipairs(ids) do
        local p, s = Pricing.GetEffectivePrice(id, patchTag)
        if p then
            prices[#prices + 1] = p
            if s then anyStale = true end
        end
    end

    if #prices == 0 then return nil, false end
    if #prices == 1 then return prices[1], anyStale end

    -- Cross-rank trim: find cheapest tier, exclude any rank priced > RANK_TRIM × that.
    local minPrice = prices[1]
    for _, p in ipairs(prices) do
        if p < minPrice then minPrice = p end
    end
    local threshold = minPrice * RANK_TRIM

    local totalPrice, count = 0, 0
    for _, p in ipairs(prices) do
        if p <= threshold then
            totalPrice = totalPrice + p
            count      = count + 1
        end
    end

    if count > 0 then
        return math.floor(totalPrice / count), anyStale
    end
    return minPrice, anyStale  -- safety: everything was trimmed, return cheapest
end

-- FormatPrice(copper) → "1,234g 56s 78c" string (handles negatives)
function Pricing.FormatPrice(copper)
    if not copper or copper == 0 then return "0g" end
    local neg = copper < 0
    copper = math.floor(math.abs(copper))
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts+1] = string.format("|cffffd700%dg|r", g) end
    if s > 0 then parts[#parts+1] = string.format("|cffc0c0c0%ds|r", s) end
    if c > 0 or #parts == 0 then parts[#parts+1] = string.format("|cffae8f0a%dc|r", c) end
    local result = table.concat(parts, " ")
    return neg and ("-" .. result) or result
end

-- ===== Core calculation =====

-- CalculateStratMetrics(strat, patchTag, craftQty) → metrics table or nil
-- strat = one entry from GAM_STRATS_GENERATED
-- craftQty = how many "batches" (multiplied by defaultStartingAmount)
-- Returns:
--   {
--     startingAmount,   -- defaultStartingAmount * craftQty
--     reagents = {      -- per-reagent results
--       { name, itemID, unitPrice, required, have, needToBuy, totalCost, isStale, missingPrice }
--     },
--     output = { name, itemID, unitPrice, expectedQty, netRevenue, isStale, missingPrice },
--     totalCostToBuy,
--     netRevenue,
--     profit,
--     roi,              -- nil if no cost
--     breakEvenSell,    -- nil if no output qty
--     missingPrices,    -- list of item names without prices
--     hasStale,
--   }
function Pricing.CalculateStratMetrics(strat, patchTag, craftQty)
    if not strat then return nil end
    patchTag  = patchTag  or GAM.C.DEFAULT_PATCH
    craftQty  = craftQty  or 1

    local opts   = GetOpts()
    local ahCut  = opts.ahCut or GAM.C.AH_CUT
    local pdb    = GetPatchDB(patchTag)

    local startingAmt = (strat.defaultStartingAmount or 1) * craftQty

    -- If the user has set a desired input (primary reagent) qty, use it directly.
    if pdb.inputQtyOverrides and pdb.inputQtyOverrides[strat.id] then
        startingAmt = pdb.inputQtyOverrides[strat.id]
    end

    local totalCostToBuy = 0
    local missingPrices  = {}
    local hasStale       = false
    local reagentResults = {}

    -- ── Reagents ──
    for _, r in ipairs(strat.reagents or {}) do
        -- Use nearest-integer rounding to avoid float precision issues
        -- (e.g. 1.53 * 5000 = 7649.999... in binary; +0.5 floors to 7650)
        local required = math.floor(r.qtyMultiplier * startingAmt + 0.5)

        -- Resolve how many the player currently has (bags + bank)
        local userHave = 0
        local rIds = r.itemIDs
        if (not rIds or #rIds == 0) and r.name then
            rIds = pdb.rankGroups[r.name] or {}
        end
        if rIds and #rIds > 0 then
            for _, rid in ipairs(rIds) do
                userHave = userHave + (GetItemCount(rid, true) or 0)
            end
        end

        local needToBuy = math.max(0, required - userHave)

        -- Price: only required if there is something left to buy.
        -- If the player already owns all copies (needToBuy == 0), cost is 0
        -- and a missing AH price should NOT block profit/ROI display.
        local price, stale = Pricing.GetEffectivePriceForItem(r, patchTag)
        if stale then hasStale = true end

        local totalCost    = (needToBuy == 0) and 0 or (price and (needToBuy * price) or nil)
        local missingPrice = (needToBuy > 0) and not price

        if missingPrice then
            missingPrices[#missingPrices + 1] = r.name
        else
            totalCostToBuy = totalCostToBuy + totalCost
        end

        -- Resolve itemID for display
        local ids    = r.itemIDs
        if (not ids or #ids == 0) and r.name then
            ids = pdb.rankGroups[r.name] or {}
        end
        local itemID = PickItemID(ids, patchTag)

        reagentResults[#reagentResults + 1] = {
            name         = r.name,
            itemID       = itemID,
            unitPrice    = price,
            required     = required,
            have         = userHave,
            needToBuy    = needToBuy,
            totalCost    = totalCost,
            isStale      = stale,
            missingPrice = missingPrice,
        }
    end

    -- ── Output(s) ──
    -- Primary output (always strat.output, used for display + single-output calcs)
    local primaryOut      = strat.output or {}
    -- Raw float used for revenue calculation (expected value over many crafts).
    -- Nearest-integer rounding only for the display qty field.
    local outputQtyRaw    = (primaryOut.qtyMultiplier or 0) * startingAmt
    local outputQty       = math.floor(outputQtyRaw + 0.5)
    -- Use average price across all quality ranks: craft output is a random mix of
    -- tiers (milling, inscription, etc.), so single-rank price over/understates revenue.
    local outPrice, outStale = GetOutputPriceForItem(primaryOut, patchTag)
    if outStale then hasStale = true end
    local outMissingPrice = not outPrice

    local netRevenue  = nil
    local outResults  = nil  -- non-nil only for JC multi-output strats

    if strat.outputs and #strat.outputs > 0 then
        -- JC prospecting / Enchanting shatter: sum revenues from all output items.
        -- Each output item gets its own netRevenue field so the display row can show
        -- the correct net value without recomputing the AH cut separately.
        local totalRev      = 0
        local allHavePrices = true
        outResults = {}
        for _, o in ipairs(strat.outputs) do
            local oQtyRaw = (o.qtyMultiplier or 0) * startingAmt                    -- float for revenue
            local oQty    = math.floor(oQtyRaw + 0.5)                               -- integer for display
            local oPrice, oStale2 = GetOutputPriceForItem(o, patchTag)
            if oStale2 then hasStale = true end
            local oIds = o.itemIDs
            if (not oIds or #oIds == 0) and o.name then
                oIds = pdb.rankGroups[o.name] or {}
            end
            local oNetRev = oPrice and math.floor(oQtyRaw * oPrice * (1 - ahCut)) or nil
            if not oPrice then
                allHavePrices = false
                missingPrices[#missingPrices + 1] = o.name or "Output"
            else
                totalRev = totalRev + oNetRev
            end
            outResults[#outResults + 1] = {
                name         = o.name,
                itemID       = PickItemID(oIds, patchTag),
                unitPrice    = oPrice,
                expectedQty  = oQty,
                netRevenue   = oNetRev,
                isStale      = oStale2,
                missingPrice = not oPrice,
            }
        end
        if allHavePrices then netRevenue = totalRev end
    else
        -- Standard single output
        if outMissingPrice then
            missingPrices[#missingPrices + 1] = primaryOut.name or "Output"
        elseif outPrice and outputQtyRaw > 0 then
            netRevenue = math.floor(outputQtyRaw * outPrice * (1 - ahCut))
        end
    end

    local outIds = primaryOut.itemIDs
    if (not outIds or #outIds == 0) and primaryOut.name then
        outIds = pdb.rankGroups[primaryOut.name] or {}
    end
    local outItemID = PickItemID(outIds, patchTag)

    -- ── Final metrics ──
    local profit    = nil
    local roi       = nil
    local breakEven = nil

    if netRevenue and #missingPrices == 0 then
        profit = netRevenue - totalCostToBuy
        if totalCostToBuy > 0 then
            roi = (profit / totalCostToBuy) * 100
        end
    end

    -- Break-even is only meaningful for single-output strats: it is the minimum
    -- sell price per output unit needed to cover all input costs.  For multi-output
    -- strats (JC prospecting, Enchanting shatters) there is no single output unit
    -- to price, so we leave breakEven nil and the UI shows "—".
    if totalCostToBuy > 0 and outputQtyRaw > 0 and not strat.outputs then
        breakEven = totalCostToBuy / (outputQtyRaw * (1 - ahCut))
    end

    return {
        startingAmount = startingAmt,
        reagents       = reagentResults,
        output = {
            name         = primaryOut.name,
            itemID       = outItemID,
            unitPrice    = outPrice,
            expectedQty  = outputQty,
            netRevenue   = (not strat.outputs) and netRevenue or nil,
            isStale      = outStale,
            missingPrice = outMissingPrice,
        },
        outputs        = outResults,   -- list; non-nil for multi-output (JC) strats
        totalCostToBuy = totalCostToBuy,
        netRevenue     = netRevenue,
        profit         = profit,
        roi            = roi,
        breakEvenSell  = breakEven,
        missingPrices  = missingPrices,
        hasStale       = hasStale,
    }
end

-- StorePrice(itemID, price) — called by AHScan after scan
function Pricing.StorePrice(itemID, price)
    if not itemID or not price then return end
    local cache = GAM:GetRealmCache()
    cache[itemID] = {
        price = price,
        ts    = time(),
    }
    GAM.Log.Debug("Stored price: itemID=%d price=%d", itemID, price)
end

-- SetPriceOverride(itemID, price, patchTag)
function Pricing.SetPriceOverride(itemID, price, patchTag)
    if not itemID then return end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GAM:GetPatchDB(patchTag)
    pdb.priceOverrides            = pdb.priceOverrides or {}
    pdb.priceOverrides[itemID]    = price
end

-- ClearPriceOverride(itemID, patchTag)
function Pricing.ClearPriceOverride(itemID, patchTag)
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GAM:GetPatchDB(patchTag)
    if pdb.priceOverrides then
        pdb.priceOverrides[itemID] = nil
    end
end
