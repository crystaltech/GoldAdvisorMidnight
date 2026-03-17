-- GoldAdvisorMidnight/Pricing.lua
-- Pricing engine: price lookup, effective price, strat metrics.
-- Module: GAM.Pricing

local ADDON_NAME, GAM = ...
local Pricing = {}
GAM.Pricing = Pricing

-- ===== Internal helpers =====

local function GetDB() return GAM.db end
local function GetOpts() return GAM.db and GAM.db.options or {} end
local function GetPatchDB(pt) return GAM:GetPatchDB(pt) end

local function RequestItemData(itemID)
    if not itemID or itemID == 0 then return end
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    else
        GetItemInfo(itemID)
    end
end

local function GetActiveRecipeView(strat)
    if not strat then return nil end
    local policy = GetOpts().rankPolicy or "lowest"
    if strat.rankVariants and strat.rankVariants[policy] then
        local variant = strat.rankVariants[policy]
        return {
            defaultStartingAmount = variant.defaultStartingAmount or strat.defaultStartingAmount,
            defaultCrafts = variant.defaultCrafts or strat.defaultCrafts or strat.defaultStartingAmount,
            outputs = variant.outputs or strat.outputs,
            output = (variant.outputs and variant.outputs[1]) or variant.output or strat.output,
            reagents = variant.reagents or strat.reagents,
        }
    end
    return {
        defaultStartingAmount = strat.defaultStartingAmount,
        defaultCrafts = strat.defaultCrafts or strat.defaultStartingAmount,
        outputs = strat.outputs,
        output = strat.output or (strat.outputs and strat.outputs[1]),
        reagents = strat.reagents,
    }
end

local function GetResolvedItemIDs(item, patchTag)
    if not item then return {} end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GetPatchDB(patchTag)
    local ids = item.itemIDs
    if (not ids or #ids == 0) and item.name then
        ids = pdb.rankGroups[item.name] or {}
    end
    return ids or {}
end

local function GetItemQualityRank(itemID)
    if not itemID or itemID == 0 then return nil end
    RequestItemData(itemID)
    local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    local q = api and api(itemID) or nil
    if q and q > 0 then return q end
    if q == 0 then return 1 end
    if GetItemInfo(itemID) ~= nil then
        return 1
    end
    return nil
end

local function FindItemIDByQuality(itemIDs, desiredQuality)
    if not desiredQuality or not itemIDs then return nil end
    for _, id in ipairs(itemIDs) do
        if GetItemQualityRank(id) == desiredQuality then
            return id
        end
    end
    return nil
end

local function GetRankPolicyDesiredQuality(itemIDs, patchTag)
    if not itemIDs or #itemIDs <= 1 then return nil end
    local policy = GetOpts().rankPolicy or "lowest"
    local bestQ = nil
    for _, id in ipairs(itemIDs) do
        local q = GetItemQualityRank(id)
        if q then
            if not bestQ then
                bestQ = q
            elseif policy == "highest" and q > bestQ then
                bestQ = q
            elseif policy ~= "highest" and q < bestQ then
                bestQ = q
            end
        end
    end
    return bestQ
end

-- ===== Pigment → herb mapping for "Mill Own Herbs" cost mode =====
-- Maps each pigment itemID → { herbIDs, yieldPerHerb }
-- yieldPerHerb = output.qtyMultiplier (1.53) / reagent.qtyMultiplier (1.0)
local PIGMENT_MILL_MAP = {
    [245807] = { herbIDs = {236761,236767}, yieldPerHerb = 1.530000 }, -- Powder Pigment Q1
    [245808] = { herbIDs = {236761,236767}, yieldPerHerb = 1.530000 }, -- Powder Pigment Q2
    [245803] = { herbIDs = {236776,236777}, yieldPerHerb = 1.530000 }, -- Argentleaf Pigment Q1
    [245804] = { herbIDs = {236776,236777}, yieldPerHerb = 1.530000 }, -- Argentleaf Pigment Q2
    [245867] = { herbIDs = {236778,236779}, yieldPerHerb = 1.530000 }, -- Mana Lily Pigment Q1
    [245866] = { herbIDs = {236778,236779}, yieldPerHerb = 1.530000 }, -- Mana Lily Pigment Q2
    [245865] = { herbIDs = {236770,236771}, yieldPerHerb = 1.530000 }, -- Sanguithorn Pigment Q1
    [245864] = { herbIDs = {236770,236771}, yieldPerHerb = 1.530000 }, -- Sanguithorn Pigment Q2
}

-- Crafted reagent cost derivations for "craft your own" reagent modes.
-- Each entry maps crafted output itemID -> recipe ingredients and expected output
-- per source unit, mirroring the spreadsheet-baked strategy definition.
local CRAFTED_REAGENT_MAP = {
    -- Bright Linen Bolt Q1/Q2
    [239700] = {
        optionKey = "boltCostSource",
        modeValue = "craft",
        ingredients = {
            { itemIDs = { 236963, 236965 }, qty = 1.000000 }, -- Bright Linen
            { itemIDs = { 251665 },         qty = 4.000000 }, -- Silverleaf Thread
        },
        yield = 0.942977,
    },
    [239701] = {
        optionKey = "boltCostSource",
        modeValue = "craft",
        ingredients = {
            { itemIDs = { 236963, 236965 }, qty = 1.000000 },
            { itemIDs = { 251665 },         qty = 4.000000 },
        },
        yield = 0.942977,
    },
    -- Refulgent Copper Ingot Q1/Q2
    [238197] = {
        optionKey = "ingotCostSource",
        modeValue = "craft",
        ingredients = {
            { itemIDs = { 237359, 237361 }, qty = 1.000000 }, -- Refulgent Copper Ore
            { itemIDs = { 243060 },         qty = 0.400000 }, -- Luminant Flux
        },
        yield = 0.199624,
    },
    [238198] = {
        optionKey = "ingotCostSource",
        modeValue = "craft",
        ingredients = {
            { itemIDs = { 237359, 237361 }, qty = 1.000000 },
            { itemIDs = { 243060 },         qty = 0.666667 },
        },
        yield = 0.332707,
    },
}

-- Pick best itemID from a list according to rankPolicy.
-- Uses C_TradeSkillUI.GetItemReagentQualityByItemInfo to sort by actual crafting
-- quality rather than array position (array order is not guaranteed to be Q1-first).
local function PickItemID(itemIDs, patchTag)
    if not itemIDs or #itemIDs == 0 then return nil end
    if #itemIDs == 1 then return itemIDs[1] end
    local policy = GetOpts().rankPolicy or "lowest"

    -- Build quality-aware sorted list
    local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    local sorted = {}
    local anyKnown = false
    for _, id in ipairs(itemIDs) do
        local q = api and api(id)
        if q and q > 0 then
            anyKnown = true
            tinsert(sorted, { id = id, q = q })
        elseif q == 0 then
            -- Non-tiered item loaded → treat as rank 1
            anyKnown = true
            tinsert(sorted, { id = id, q = 1 })
        else
            -- Uncached: push to end so known ranks are preferred
            tinsert(sorted, { id = id, q = 999 })
        end
    end

    if anyKnown then
        table.sort(sorted, function(a, b) return a.q < b.q end)
        return (policy == "highest") and sorted[#sorted].id or sorted[1].id
    end

    -- All uncached: fall back to array position
    return (policy == "highest") and itemIDs[#itemIDs] or itemIDs[1]
end

function Pricing.PreloadStratItemData(strat, patchTag)
    if not strat then return end
    local seen = {}
    local active = GetActiveRecipeView(strat)
    local function touch(item)
        for _, id in ipairs(GetResolvedItemIDs(item, patchTag)) do
            if not seen[id] then
                seen[id] = true
                RequestItemData(id)
            end
        end
    end
    touch(active.output)
    for _, o in ipairs(active.outputs or {}) do touch(o) end
    for _, r in ipairs(active.reagents or {}) do touch(r) end
end

function Pricing.GetItemDisplayData(itemID, fallbackName)
    if itemID and itemID > 0 then
        RequestItemData(itemID)
        local name, link = GetItemInfo(itemID)
        if link then
            return {
                itemID = itemID,
                displayText = link,
                itemLink = link,
                hasSafeLink = true,
                fallbackName = fallbackName or name or "?",
            }
        end
        return {
            itemID = itemID,
            displayText = fallbackName or name or ("item:" .. tostring(itemID)),
            itemLink = nil,
            hasSafeLink = false,
            fallbackName = fallbackName or name or "?",
        }
    end
    return {
        itemID = itemID,
        displayText = fallbackName or "?",
        itemLink = nil,
        hasSafeLink = false,
        fallbackName = fallbackName or "?",
    }
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

-- GetEffectivePrice(itemID, patchTag, qty) → price in copper, or nil
-- Priority: override > CraftSim > qty-aware AH fill > AH cache avg
-- qty (optional): when provided, uses ComputePriceForQty for the actual fill
--                 cost at that volume rather than the shallowFillQty cached avg.
function Pricing.GetEffectivePrice(itemID, patchTag, qty)
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

    -- 3. AH cache — use qty-aware fill when qty is supplied and raw data exists.
    -- Always derive stale status from the cached timestamp (ComputePriceForQty
    -- does not check age, so we get correctness from GetUnitPrice's ts check).
    local cachedPrice, stale = Pricing.GetUnitPrice(itemID)
    if qty and qty > 0 and GAM.AHScan and GAM.AHScan.ComputePriceForQty then
        local qp = GAM.AHScan.ComputePriceForQty(itemID, qty)
        if qp then return qp, stale end
    end
    return cachedPrice, stale
end

-- GetMillDerivedPigmentCost(itemID, patchTag, pigmentQty) → cost per pigment (copper), isStale
-- Derives pigment cost from herb AH price ÷ milling yield.
-- pigmentQty (optional): when provided the herb price lookup uses the actual
--   herb volume needed (pigmentQty / yieldPerHerb) for a qty-aware fill price.
-- Returns nil if the item is not a known pigment or herb prices are unavailable
-- (caller falls through to AH pigment price).
local function GetMillDerivedPigmentCost(itemID, patchTag, pigmentQty)
    local info = PIGMENT_MILL_MAP[itemID]
    if not info then return nil, false end
    local herbQty = (pigmentQty and pigmentQty > 0 and info.yieldPerHerb and info.yieldPerHerb > 0)
                    and math.ceil(pigmentQty / info.yieldPerHerb) or nil
    local bestPrice, isStale = nil, false
    for _, hid in ipairs(info.herbIDs) do
        local p, s = Pricing.GetEffectivePrice(hid, patchTag, herbQty)
        if p and (not bestPrice or p < bestPrice) then
            bestPrice = p
            isStale   = isStale or s
        end
    end
    if not bestPrice then return nil, false end
    return math.floor(bestPrice / info.yieldPerHerb + 0.5), isStale
end

-- GetPreferredIngredientPrice(itemIDs, patchTag, qty) → price, isStale
-- qty (optional): passed through to GetEffectivePrice for qty-aware fill.
local function GetPreferredIngredientPrice(itemIDs, patchTag, qty)
    if not itemIDs or #itemIDs == 0 then return nil, false end
    local picked = PickItemID(itemIDs, patchTag)
    if picked then
        local price, isStale = Pricing.GetEffectivePrice(picked, patchTag, qty)
        if price then return price, isStale end
    end
    for _, itemID in ipairs(itemIDs) do
        if itemID ~= picked then
            local price, isStale = Pricing.GetEffectivePrice(itemID, patchTag, qty)
            if price then return price, isStale end
        end
    end
    return nil, false
end

-- GetCraftDerivedReagentCost(itemID, patchTag, outputQty) → cost per output unit (copper), isStale
-- outputQty (optional): when provided the ingredient price lookups use the
--   actual per-ingredient volume needed for a qty-aware fill price.
local function GetCraftDerivedReagentCost(itemID, patchTag, outputQty)
    local info = CRAFTED_REAGENT_MAP[itemID]
    if not info then return nil, false end
    if (GetOpts()[info.optionKey] or "ah") ~= info.modeValue then return nil, false end

    local totalCost, anyStale = 0, false
    for _, ingredient in ipairs(info.ingredients) do
        local ingQty = (outputQty and outputQty > 0 and info.yield and info.yield > 0)
                       and math.ceil(ingredient.qty * outputQty / info.yield) or nil
        local unitPrice, isStale = GetPreferredIngredientPrice(ingredient.itemIDs, patchTag, ingQty)
        if not unitPrice then return nil, false end
        totalCost = totalCost + (unitPrice * ingredient.qty)
        anyStale = anyStale or isStale
    end

    if not info.yield or info.yield <= 0 then return nil, false end
    return math.floor(totalCost / info.yield + 0.5), anyStale
end

-- GetEffectivePriceForItem(item, patchTag, qty) → price, isStale
-- item = { name, itemIDs = {}, ... }
-- qty (optional): actual units to buy; threads through to qty-aware AH fill.
-- Used for REAGENT pricing: tries the rank-policy preferred itemID first, then
-- falls back through remaining variants (you'd buy the cheapest available rank).
function Pricing.GetEffectivePriceForItem(item, patchTag, qty)
    if not item then return nil, false end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GetPatchDB(patchTag)

    -- Resolve itemIDs: use rankGroups if item.itemIDs is empty
    local ids = item.itemIDs
    if (not ids or #ids == 0) and item.name then
        ids = pdb.rankGroups[item.name] or {}
    end

    if not ids or #ids == 0 then return nil, false end

    -- Derived reagent pricing modes. Manual price overrides still win.
    local pdb2 = GetPatchDB(patchTag)
    for _, id in ipairs(ids) do
        if not (pdb2.priceOverrides and pdb2.priceOverrides[id] ~= nil) then
            if GetOpts().pigmentCostSource == "mill" and PIGMENT_MILL_MAP[id] then
                local millCost, millStale = GetMillDerivedPigmentCost(id, patchTag, qty)
                if millCost then return millCost, millStale end
                break
            end
            if CRAFTED_REAGENT_MAP[id] then
                local craftCost, craftStale = GetCraftDerivedReagentCost(id, patchTag, qty)
                if craftCost then return craftCost, craftStale end
                break
            end
        elseif PIGMENT_MILL_MAP[id] or CRAFTED_REAGENT_MAP[id] then
            break
        end
    end

    local picked = PickItemID(ids, patchTag)
    if not picked then return nil, false end

    -- Try preferred itemID first
    local price, isStale = Pricing.GetEffectivePrice(picked, patchTag, qty)
    if price then return price, isStale end

    -- Fallback: check remaining quality variants in array order
    for _, id in ipairs(ids) do
        if id ~= picked then
            local p, s = Pricing.GetEffectivePrice(id, patchTag, qty)
            if p then return p, s end
        end
    end

    return nil, false
end

-- GetOutputPriceForItem(item, patchTag, preferredQuality) → price, isStale
-- Used for OUTPUT pricing. When preferredQuality is provided (1/2/3 crafting
-- quality tier), finds the output itemID with that quality and prices it — used
-- so milling/processing output rank matches the input reagent rank (R1 input →
-- R1 output, R2 input → R2 output). Falls back to cheapest-rank logic when the
-- preferred quality has no matching ID or no price data.
-- A cross-rank trim (RANK_TRIM) excludes extreme outlier ranks before the
-- fallback minimum is chosen.
local RANK_TRIM = 3.0

local function GetDesiredOutputQuality(item, patchTag, preferredQuality)
    if preferredQuality then
        return preferredQuality
    end
    local ids = GetResolvedItemIDs(item, patchTag)
    return GetRankPolicyDesiredQuality(ids, patchTag)
end

local function GetOutputPriceForItem(item, patchTag, preferredQuality)
    if not item then return nil, false end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local ids = GetResolvedItemIDs(item, patchTag)
    if not ids or #ids == 0 then return nil, false end

    local desiredQuality = GetDesiredOutputQuality(item, patchTag, preferredQuality)
    local exactID = FindItemIDByQuality(ids, desiredQuality)
    if exactID then
        local p, s = Pricing.GetEffectivePrice(exactID, patchTag)
        if p then return p, s end
    end

    local policyID = PickItemID(ids, patchTag)
    if policyID then
        local p, s = Pricing.GetEffectivePrice(policyID, patchTag)
        if p then return p, s end
    end

    for _, id in ipairs(ids) do
        if id ~= exactID and id ~= policyID then
            local p, s = Pricing.GetEffectivePrice(id, patchTag)
            if p then return p, s end
        end
    end

    return nil, false
end

local function GetOutputItemIDForDisplay(item, patchTag, preferredQuality)
    if not item then return nil end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local ids = GetResolvedItemIDs(item, patchTag)
    if not ids or #ids == 0 then return nil end
    local desiredQuality = GetDesiredOutputQuality(item, patchTag, preferredQuality)
    local exactID = FindItemIDByQuality(ids, desiredQuality)
    if exactID then
        return exactID
    end
    return PickItemID(ids, patchTag)
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

-- ===== Stat scaling (Workbook-driven formula profiles) =====

local function GetFormulaProfiles()
    return (GAM_WORKBOOK_GENERATED and GAM_WORKBOOK_GENERATED.formulaProfiles) or {}
end

-- ===== Core calculation =====

-- CalculateStratMetrics(strat, patchTag, craftQty) → metrics table or nil
-- strat = one entry from GAM_RECIPES_GENERATED / importer-normalized data
-- craftQty = scalar applied to the recipe's workbook baseline starting amount
-- Runtime uses defaultStartingAmount -> defaultCrafts scaling so workbook
-- "Start Amount" and "Crafts" stay distinct.
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
    local active = GetActiveRecipeView(strat)

    -- Direct formula stat factors:  Y = X × B × (1 + MCp × MCm_total) / (1 − Rp × Rs_total)
    -- MCm_total = BASE_MCM × (1 + mcNodeBonus/100)
    -- Rs_total  = BASE_RS  × (1 + rsNodeBonus/100)
    -- Computed once here and reused for all outputs (primary + multi-output strats).
    local profileKey = strat.formulaProfile
    local profileDef = profileKey and GetFormulaProfiles()[profileKey] or nil
    local statMCp, statRp, statMCm_tot, statRs_tot, statDenom
    if strat.calcMode == "formula" and profileDef then
        statMCp = profileDef.multiKey and ((opts[profileDef.multiKey] or 0) / 100) or 0
        statRp = profileDef.resKey and ((opts[profileDef.resKey] or 0) / 100) or 0
        statMCm_tot = profileDef.multiKey and (GAM.C.BASE_MCM * (1 + ((profileDef.mcNodeKey and (opts[profileDef.mcNodeKey] or 0) or 0) / 100))) or 0
        statRs_tot = GAM.C.BASE_RS * (1 + ((profileDef.rsNodeKey and (opts[profileDef.rsNodeKey] or 0) or 0) / 100))
        statDenom = 1 - statRp * statRs_tot
        if statDenom <= 0 then statDenom = 1 end  -- guard against degenerate inputs
    end

    -- Helper: apply formula to a base yield multiplier B.
    -- Returns outputQtyRaw (float, used for revenue math).
    local function ApplyYieldFormula(B, startAmt)
        if strat.calcMode == "formula" and profileDef and statDenom then
            return startAmt * B * (1 + statMCp * statMCm_tot) / statDenom
        else
            return startAmt * B  -- custom strats: no stat bonuses
        end
    end

    local startingAmt = (active.defaultStartingAmount or strat.defaultStartingAmount or 1) * craftQty

    -- If the user has set a desired input (primary reagent) qty, use it directly.
    if pdb.inputQtyOverrides and pdb.inputQtyOverrides[strat.id] then
        startingAmt = pdb.inputQtyOverrides[strat.id]
    end
    local defaultCrafts = active.defaultCrafts or strat.defaultCrafts or active.defaultStartingAmount or strat.defaultStartingAmount or 1
    if defaultCrafts <= 0 then defaultCrafts = 1 end
    local crafts = defaultCrafts
    if (active.defaultStartingAmount or strat.defaultStartingAmount or 0) > 0 then
        crafts = defaultCrafts * (startingAmt / (active.defaultStartingAmount or strat.defaultStartingAmount))
    end

    local totalCostToBuy = 0
    local missingPrices  = {}
    local hasStale       = false
    local reagentResults = {}

    -- ── Reagents ──
    for _, r in ipairs(active.reagents or {}) do
        -- Use nearest-integer rounding to avoid float precision issues
        -- (e.g. 1.53 * 5000 = 7649.999... in binary; +0.5 floors to 7650)
        local qtyPerCraft = r.qtyPerCraft
        local requiredRaw
        if qtyPerCraft ~= nil then
            requiredRaw = qtyPerCraft * crafts
        else
            local qtyPerStart = r.qtyPerStart or r.qtyMultiplier or 0
            requiredRaw = qtyPerStart * startingAmt
        end
        local required = math.floor(requiredRaw + 0.5)

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
        -- Pass needToBuy so the AH fill is computed for the actual purchase
        -- volume, not just the shallowFillQty (default 50) cached average.
        local price, stale = Pricing.GetEffectivePriceForItem(r, patchTag, needToBuy)
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
    local primaryOut = (active.outputs and active.outputs[1]) or active.output or {}
    -- Raw float used for revenue calculation (expected value over many crafts).
    -- Nearest-integer rounding only for the display qty field.
    local B = primaryOut.baseYield or primaryOut.baseYieldMultiplier or primaryOut.qtyMultiplier or 0
    if primaryOut.baseYieldPerCraft ~= nil and crafts > 0 then
        B = primaryOut.baseYieldPerCraft
    end
    local outputQtyRaw
    if primaryOut.baseYieldPerCraft ~= nil then
        local factor = (strat.calcMode == "formula" and profileDef and statDenom) and ((1 + statMCp * statMCm_tot) / statDenom) or 1
        outputQtyRaw = crafts * B * factor
    else
        outputQtyRaw = ApplyYieldFormula(B, startingAmt)
    end
    local outputQty    = math.floor(outputQtyRaw + 0.5)

    -- Determine the crafting quality of the primary reagent so output pricing can
    -- match the same rank (R1 herb → R1 pigment, R2 herb → R2 pigment).
    local primaryQuality = nil
    if active.reagents and #active.reagents > 0 then
        local r0   = active.reagents[1]
        local rIds = r0.itemIDs
        if (not rIds or #rIds == 0) and r0.name then
            rIds = pdb.rankGroups[r0.name] or {}
        end
        if rIds and #rIds > 0 then
            local pickedId = PickItemID(rIds, patchTag)
            local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
            if api and pickedId then
                local q = api(pickedId)
                if q and q > 0 then primaryQuality = q end
            end
        end
    end

    local outputPreferredQuality = (strat.outputQualityMode == "match_input") and primaryQuality or nil
    local outPrice, outStale = GetOutputPriceForItem(primaryOut, patchTag, outputPreferredQuality)
    if outStale then hasStale = true end
    local outMissingPrice = not outPrice

    local netRevenue  = nil
    local outResults  = nil  -- non-nil only for JC multi-output strats

    if active.outputs and #active.outputs > 1 then
        -- JC prospecting / Enchanting shatter: sum revenues from all output items.
        -- Each output item gets its own netRevenue field so the display row can show
        -- the correct net value without recomputing the AH cut separately.
        local totalRev      = 0
        local allHavePrices = true
        outResults = {}
        for _, o in ipairs(active.outputs) do
            local oB = o.baseYield or o.baseYieldMultiplier or o.qtyMultiplier or 0
            if o.baseYieldPerCraft ~= nil then
                oB = o.baseYieldPerCraft
            end
            local oQtyRaw
            if o.baseYieldPerCraft ~= nil then
                local factor = (strat.calcMode == "formula" and profileDef and statDenom) and ((1 + statMCp * statMCm_tot) / statDenom) or 1
                oQtyRaw = crafts * oB * factor
            else
                oQtyRaw = ApplyYieldFormula(oB, startingAmt)                       -- float for revenue
            end
            local oQty    = math.floor(oQtyRaw + 0.5)                               -- integer for display
            local oPrice, oStale2 = GetOutputPriceForItem(o, patchTag, outputPreferredQuality)
            if oStale2 then hasStale = true end
            local oNetRev = oPrice and math.floor(oQtyRaw * oPrice * (1 - ahCut)) or nil
            if not oPrice then
                allHavePrices = false
                missingPrices[#missingPrices + 1] = o.name or "Output"
            else
                totalRev = totalRev + oNetRev
            end
            outResults[#outResults + 1] = {
                name         = o.name,
                itemID       = GetOutputItemIDForDisplay(o, patchTag, outputPreferredQuality),
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

    local outItemID = GetOutputItemIDForDisplay(primaryOut, patchTag, outputPreferredQuality)

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
        if totalCostToBuy > 0 and outputQtyRaw > 0 and not (active.outputs and #active.outputs > 1) then
            breakEven = totalCostToBuy / (outputQtyRaw * (1 - ahCut))
        end

    return {
        startingAmount = startingAmt,
        crafts         = crafts,
        reagents       = reagentResults,
        output = {
            name         = primaryOut.name,
            itemID       = outItemID,
            unitPrice    = outPrice,
            expectedQty  = outputQty,
            netRevenue   = (not (active.outputs and #active.outputs > 1)) and netRevenue or nil,
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

-- GetBestStrategy(patchTag, profFilter) — returns (strat, profit, roi) for the top
-- scoring strategy that clears both minimum thresholds. Returns nil,nil,nil if none qualify.
-- Score = profit × √ROI; capital tie-break on totalCostToBuy.
-- Called only on: scan complete, filter change, window open — never per-frame.
function Pricing.GetBestStrategy(patchTag, profFilter)
    patchTag   = patchTag  or GAM.C.DEFAULT_PATCH
    profFilter = profFilter or "All"
    local minProfit = GAM.C.BEST_STRAT_MIN_PROFIT
    local minROI    = GAM.C.BEST_STRAT_MIN_ROI
    local all = GAM.Importer.GetAllStrats(patchTag)
    if not all or #all == 0 then return nil, nil, nil end

    local bestStrat, bestScore, bestProfit, bestROI, bestCost =
        nil, -math.huge, nil, nil, nil

    for _, strat in ipairs(all) do
        if profFilter == "All" or strat.profession == profFilter then
            local m = Pricing.CalculateStratMetrics(strat, patchTag)
            if m then
                local p, r, cost = m.profit, m.roi, m.totalCostToBuy
                if p and p >= minProfit and r and r >= minROI then
                    -- Composite score: profit × √ROI (balances magnitude vs capital efficiency)
                    local score = p * math.sqrt(r)
                    local better = not bestStrat
                        or score > bestScore
                        or (score == bestScore
                            and (cost or math.huge) < (bestCost or math.huge))
                    if better then
                        bestStrat, bestScore   = strat, score
                        bestProfit, bestROI, bestCost = p, r, cost
                    end
                end
            end
        end
    end
    return bestStrat, bestProfit, bestROI
end

-- StorePrice(itemID, price) — called by AHScan after scan
function Pricing.StorePrice(itemID, price)
    if not itemID or not price then return end
    local cache = GAM:GetRealmCache()
    local existing = cache[itemID]
    cache[itemID] = {
        price = price,
        ts    = time(),
        raw   = existing and existing.raw or nil,  -- preserve raw if already stored
    }
    GAM.Log.Debug("Stored price: itemID=%d price=%d", itemID, price)
end

-- StoreRaw(itemID, sortedRaw) — persist raw AH listings alongside the avg price
-- so ComputePriceForQty can give qty-aware prices between sessions.
function Pricing.StoreRaw(itemID, sortedRaw)
    if not itemID or not sortedRaw then return end
    local cache = GAM:GetRealmCache()
    local entry = cache[itemID]
    if entry then
        entry.raw = sortedRaw
    end
end

-- GetRawCache(itemID) — return persisted raw listings, or nil.
function Pricing.GetRawCache(itemID)
    if not itemID then return nil end
    local cache = GAM:GetRealmCache()
    local entry = cache[itemID]
    return entry and entry.raw or nil
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
