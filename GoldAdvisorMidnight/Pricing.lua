-- GoldAdvisorMidnight/Pricing.lua
-- Pricing engine: price lookup, effective price, strat metrics.
-- Module: GAM.Pricing

local ADDON_NAME, GAM = ...
local Pricing = {}
GAM.Pricing = Pricing
local Derivation = GAM.PricingDerivation or {}
local BuildCalcContext, BuildMergedReagentMap, BuildReagentMetrics, BuildDisplayReagentMetrics, BuildOutputMetrics, BuildFinalMetrics
local BuildEconomicReagentMetrics

-- ===== Internal helpers =====

local function GetDB()
    return (GAM.GetDB and GAM:GetDB()) or GAM.db
end

local function GetOpts()
    return (GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {}
end
local function GetPatchDB(pt) return GAM:GetPatchDB(pt) end
local function GetFormulaProfiles()
    return (GAM_WORKBOOK_GENERATED and GAM_WORKBOOK_GENERATED.formulaProfiles) or {}
end
local function GetItemLabel(item)
    if not item then return nil end
    return item.name or item.itemRef
end
local function SafeWholeText(n, useCommas)
    if n == nil then return "0" end
    if n == math.huge then return "inf" end
    if n == -math.huge then return "-inf" end
    local whole = math.floor(tonumber(n) or 0)
    local text = tostring(whole)
    if not useCommas then
        return text
    end
    local sign, digits = text:match("^([%-]?)(%d+)$")
    if not digits then
        return text
    end
    return sign .. digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function RequestItemData(itemID)
    if not itemID or itemID == 0 then return end
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    else
        GetItemInfo(itemID)
    end
end

local function BuildRecipeView(strat, variant)
    if not strat then return nil end
    variant = variant or {}
    return {
        defaultStartingAmount = variant.defaultStartingAmount or strat.defaultStartingAmount,
        defaultCrafts = variant.defaultCrafts or strat.defaultCrafts or strat.defaultStartingAmount,
        outputs = variant.outputs or strat.outputs,
        output = (variant.outputs and variant.outputs[1]) or variant.output or strat.output
            or (strat.outputs and strat.outputs[1]),
        reagents = variant.reagents or strat.reagents,
    }
end

local function GetRecipeViewForVariantKey(strat, variantKey)
    if not strat or not variantKey or not strat.rankVariants or not strat.rankVariants[variantKey] then
        return nil
    end
    return BuildRecipeView(strat, strat.rankVariants[variantKey])
end

local function GetActiveRecipeView(strat)
    if not strat then return nil end
    local policy = GetOpts().rankPolicy or "lowest"
    local variantView = GetRecipeViewForVariantKey(strat, policy)
    if variantView then
        return variantView
    end
    return BuildRecipeView(strat)
end

local GetInputRankPolicy, PickItemID

-- Public helper so non-pricing helpers (scan buttons, exports, CraftSim push)
-- can use the same rank-policy-resolved reagent/output set as pricing.
function Pricing.GetActiveRecipeView(strat)
    return GetActiveRecipeView(strat)
end

-- Shared helper for non-pricing actions that should mirror the currently displayed
-- strategy view. Outputs always come from the active rank-policy recipe view; reagents
-- may come from the expanded metrics list when a caller passes one in.
function Pricing.GetDisplayedItemSet(strat, patchTag, metrics)
    local active = GetActiveRecipeView(strat)
    if not active then return nil end
    local reagentItems = {}
    local inputPolicy = GetInputRankPolicy and GetInputRankPolicy(strat) or ((GetOpts().rankPolicy or "lowest"))
    if metrics and metrics.reagents and #metrics.reagents > 0 then
        for _, r in ipairs(metrics.reagents) do
            reagentItems[#reagentItems + 1] = {
                itemIDs = r.scanItemIDs or (r.itemID and { r.itemID } or {}),
                name = r.name,
            }
        end
    else
        for _, reagent in ipairs(active.reagents or {}) do
            local reagentIDs = reagent.itemIDs or {}
            local pickedID = PickItemID and PickItemID(reagentIDs, patchTag, inputPolicy) or nil
            reagentItems[#reagentItems + 1] = {
                itemIDs = pickedID and { pickedID } or reagentIDs,
                name = GetItemLabel(reagent),
            }
        end
    end
    local output = active.output and {
        itemIDs = active.output.itemIDs or {},
        name = GetItemLabel(active.output),
    } or nil
    local outputs = {}
    for _, out in ipairs(active.outputs or {}) do
        outputs[#outputs + 1] = {
            itemIDs = out.itemIDs or {},
            name = GetItemLabel(out),
        }
    end
    return {
        output = output,
        outputs = outputs,
        reagents = reagentItems,
    }
end

-- Extra scan targets that are not part of the visible displayed reagent list.
-- Used for flexible reagent groups like `cheapestOf`, where pricing needs every
-- eligible alternative scanned even though only one row is shown in the UI.
function Pricing.GetExtraScanItems(strat, patchTag)
    local active = GetActiveRecipeView(strat)
    if not active then return {} end

    local extras = {}
    for _, reagent in ipairs(active.reagents or {}) do
        if reagent.cheapestOf then
            for _, alt in ipairs(reagent.cheapestOf) do
                local altIDs = alt.itemIDs
                if (not altIDs or #altIDs == 0) and alt.itemRef then
                    local pdb = GetPatchDB(patchTag)
                    altIDs = pdb.rankGroups[alt.itemRef] or {}
                end
                extras[#extras + 1] = {
                    itemIDs = altIDs or {},
                    name = alt.itemRef,
                }
            end
        end
    end
    return extras
end

local function GetStrategyScoreFromMetrics(metrics)
    if not metrics then return nil, nil end
    local p, r, cost = metrics.profit, metrics.roi, metrics.totalCostFull
    if not p or not r then return nil, cost end
    return p * math.sqrt(r), cost
end

function Pricing.GetStrategyScore(metrics)
    return GetStrategyScoreFromMetrics(metrics)
end

local function GetResolvedItemIDs(item, patchTag)
    if not item then return {} end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GetPatchDB(patchTag)
    local ids = item.itemIDs
    local label = GetItemLabel(item)
    if (not ids or #ids == 0) and label then
        ids = pdb.rankGroups[label] or {}
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

local function GetExplicitItemQualityRank(itemID)
    if not itemID or itemID == 0 then return nil end
    RequestItemData(itemID)
    local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    local q = api and api(itemID) or nil
    if q and q > 0 then return q end
    if q == 0 then return 1 end
    return nil
end

local function GetItemName(itemID)
    return select(1, GetItemInfo(itemID))
end

local function FindItemIDByQuality(itemIDs, desiredQuality)
    if not desiredQuality or not itemIDs then return nil end
    local anyKnown = false
    for _, id in ipairs(itemIDs) do
        local q = GetExplicitItemQualityRank(id)
        if q then
            anyKnown = true
        end
        if q == desiredQuality then
            return id
        end
    end
    if not anyKnown and desiredQuality >= 1 and desiredQuality <= #itemIDs then
        return itemIDs[desiredQuality]
    end
    return nil
end

local function GetRankPolicyDesiredQuality(itemIDs, patchTag)
    if not itemIDs or #itemIDs <= 1 then return nil end
    local policy = GetOpts().rankPolicy or "lowest"
    local bestQ = nil
    for _, id in ipairs(itemIDs) do
        local q = GetExplicitItemQualityRank(id)
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

-- Dependency container for derivation functions (GetEffectivePrice, PickItemID).
-- Populated lazily by GetDerivationDeps() on first use.
local DERIVATION_DEPS = {}
local ResolveCheapestAlternative

GetInputRankPolicy = function(strat)
    if strat and strat.qualityPolicy == "force_q1_inputs" then
        return "lowest"
    end
    if strat and strat.qualityPolicy == "force_q2_inputs" then
        return "highest"
    end
    return GetOpts().rankPolicy or "lowest"
end

-- Pick best itemID from a list according to rankPolicy.
-- Uses C_TradeSkillUI.GetItemReagentQualityByItemInfo to sort by actual crafting
-- quality rather than array position (array order is not guaranteed to be Q1-first).
PickItemID = function(itemIDs, patchTag, policyOverride)
    if not itemIDs or #itemIDs == 0 then return nil end
    if #itemIDs == 1 then return itemIDs[1] end
    local policy = policyOverride or GetOpts().rankPolicy or "lowest"

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

local function GetDerivationDeps()
    DERIVATION_DEPS.PickItemID = PickItemID
    DERIVATION_DEPS.GetEffectivePrice = Pricing.GetEffectivePrice
    return DERIVATION_DEPS
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

-- Resolve localized item text for Auctionator shopping exports without changing
-- the addon's canonical English item keys used for workbook/catalog lookups.
function Pricing.GetShoppingSearchData(itemID, fallbackName)
    local resolvedName = fallbackName
    local resolvedLink = nil

    if itemID and itemID > 0 then
        RequestItemData(itemID)
        local localizedName, localizedLink = GetItemInfo(itemID)
        resolvedName = localizedName or resolvedName
        resolvedLink = localizedLink
    end

    return {
        itemID = itemID,
        displayName = resolvedName or fallbackName or "?",
        searchName = resolvedName,
        searchString = resolvedLink or resolvedName or fallbackName,
        itemLink = resolvedLink,
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
-- Priority: override > vendor price > CraftSim > live AH depth > AH cache avg
-- When live raw AH depth exists for the requested item, qty-aware repricing
-- uses the current scanned order book so larger craft counts can reflect the
-- real fill cost. If no live depth exists, we fall back to the cached/export
-- unit price basis.
function Pricing.GetEffectivePrice(itemID, patchTag, qty)
    if not itemID then return nil end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local opts = GetOpts()

    -- 1. Manual override (use ~= nil so an explicit 0 override is honoured)
    local pdb = GetPatchDB(patchTag)
    if pdb.priceOverrides and pdb.priceOverrides[itemID] ~= nil then
        return pdb.priceOverrides[itemID], false
    end

    -- 2. Vendor price (static — no scan needed)
    if GAM.C.VENDOR_PRICES and GAM.C.VENDOR_PRICES[itemID] then
        return GAM.C.VENDOR_PRICES[itemID], false
    end

    -- 3. CraftSim (if selected as source)
    if opts.priceSource == "craftsim" and GAM.CraftSimBridge then
        local csPrice = GAM.CraftSimBridge.GetPrice(itemID)
        if csPrice and csPrice > 0 then
            return csPrice, false
        end
    end

    -- 4. Live AH depth repricing when we have raw in-session scan data.
    local targetQty = tonumber(qty)
    if targetQty and targetQty > 0 and GAM.AHScan and GAM.AHScan.ComputePriceForQty then
        local liveAvg = GAM.AHScan.ComputePriceForQty(itemID, math.max(1, math.floor(targetQty + 0.5)))
        if liveAvg then
            return math.floor(liveAvg), false
        end
    end

    -- 5. AH cache fallback — used when only cached/export data exists.
    local cachedPrice, stale = Pricing.GetUnitPrice(itemID)
    return cachedPrice, stale
end

-- GetPreferredIngredientPrice(itemIDs, patchTag, qty) → price, isStale
-- Checks mill/craft derivation chains before falling back to AH price.
-- This ensures the full chain works: e.g. inks inside a recipe pick up
-- herb-derived pigment cost, and ingots inside alloy recipes pick up ore cost.
-- The derivation chain itself lives in PricingDerivation.lua.
local function GetPreferredIngredientPrice(itemIDs, patchTag, qty)
    return Derivation.GetPreferredIngredientPrice(itemIDs, patchTag, qty, GetDerivationDeps())
end

local function GetDirectEffectivePriceForItem(item, patchTag, qty)
    if not item then return nil, false end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GetPatchDB(patchTag)

    local ids = item.itemIDs
    local label = GetItemLabel(item)
    if (not ids or #ids == 0) and label then
        ids = pdb.rankGroups[label] or {}
    end
    if not ids or #ids == 0 then
        return nil, false
    end

    for _, id in ipairs(ids) do
        if pdb.priceOverrides and pdb.priceOverrides[id] ~= nil then
            return pdb.priceOverrides[id], false
        end
    end

    local picked = PickItemID(ids, patchTag, item.rankPolicyOverride)
    if not picked then
        return nil, false
    end

    local price, isStale = Pricing.GetEffectivePrice(picked, patchTag, qty)
    if price then
        return price, isStale
    end

    for _, id in ipairs(ids) do
        if id ~= picked then
            local altPrice, altStale = Pricing.GetEffectivePrice(id, patchTag, qty)
            if altPrice then
                return altPrice, altStale
            end
        end
    end

    return nil, false
end

-- GetEffectivePriceForItem(item, patchTag, qty) → price, isStale
-- item = { name, itemIDs = {}, ... }
-- qty (optional): actual units to buy; threads through to qty-aware AH fill.
-- Used for REAGENT pricing: selects the rank-policy preferred itemID via
-- PickItemID BEFORE checking mill/craft derivation, so R2 Mats correctly
-- uses R2 ingot/pigment recipes rather than defaulting to the first array entry.
function Pricing.GetEffectivePriceForItem(item, patchTag, qty)
    if not item then return nil, false end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GetPatchDB(patchTag)

    -- Resolve itemIDs: use rankGroups if item.itemIDs is empty
    local ids = item.itemIDs
    local label = GetItemLabel(item)
    if (not ids or #ids == 0) and label then
        ids = pdb.rankGroups[label] or {}
    end
    if not ids or #ids == 0 then return nil, false end

    -- Manual price overrides win over all derivation. Check every ID.
    for _, id in ipairs(ids) do
        if pdb.priceOverrides and pdb.priceOverrides[id] ~= nil then
            return pdb.priceOverrides[id], false
        end
    end

    -- Pick rank-policy ID FIRST so mill/craft derivation honours R1/R2 selection.
    -- (Previously the loop checked ids in array order and could pick R1 even when
    -- R2 Mats was selected because R1's entry appeared first in the array.)
    local picked = PickItemID(ids, patchTag, item.rankPolicyOverride)
    if not picked then return nil, false end

    if not item.skipDerivation then
        if GetOpts().pigmentCostSource == "mill" and Derivation.HasMillMapping(picked) then
            local millCost, millStale = Derivation.GetMillDerivedPigmentCost(picked, patchTag, qty, GetDerivationDeps())
            if millCost then return millCost, millStale end
        end
        if Derivation.HasCraftedMapping(picked) then
            local craftCost, craftStale = Derivation.GetCraftDerivedReagentCost(picked, patchTag, qty, GetDerivationDeps())
            if craftCost then return craftCost, craftStale end
        end
    end

    return GetDirectEffectivePriceForItem({
        itemIDs = ids,
        name = item.name,
        itemRef = item.itemRef,
        rankPolicyOverride = item.rankPolicyOverride,
    }, patchTag, qty)
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

local function GetOutputPriceForItem(item, patchTag, preferredQuality, qty)
    if not item then return nil, false end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local ids = GetResolvedItemIDs(item, patchTag)
    if not ids or #ids == 0 then return nil, false end

    local desiredQuality = GetDesiredOutputQuality(item, patchTag, preferredQuality)
    local exactID = FindItemIDByQuality(ids, desiredQuality)
    if exactID then
        local p, s = Pricing.GetEffectivePrice(exactID, patchTag, qty)
        if p then return p, s end
    end

    local policyID = PickItemID(ids, patchTag)
    if policyID then
        local p, s = Pricing.GetEffectivePrice(policyID, patchTag, qty)
        if p then return p, s end
    end

    for _, id in ipairs(ids) do
        if id ~= exactID and id ~= policyID then
            local p, s = Pricing.GetEffectivePrice(id, patchTag, qty)
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
    if g > 0 then parts[#parts+1] = "|cffffd700" .. SafeWholeText(g, true) .. "g|r" end
    if s > 0 then parts[#parts+1] = "|cffc0c0c0" .. SafeWholeText(s) .. "s|r" end
    if c > 0 or #parts == 0 then parts[#parts+1] = "|cffae8f0a" .. SafeWholeText(c) .. "c|r" end
    local result = table.concat(parts, " ")
    return neg and ("-" .. result) or result
end

function Pricing.RunSmokeChecks()
    local ok, err = pcall(function()
        local profiles = GetFormulaProfiles()
        assert(type(profiles) == "table", "formula profiles unavailable")

        local craftInfo = Derivation.GetAnyCraftInfo()
        assert(craftInfo and craftInfo.yield, "crafted reagent map unavailable")

        local effectiveYield = Derivation.GetEffectiveCraftYield(craftInfo)
        assert(type(effectiveYield) == "number" and effectiveYield > 0, "effective craft yield invalid")

        local largeSample = Pricing.FormatPrice(245000 * 10000)
        assert(largeSample:find("245,000g", 1, true), "FormatPrice missing gold comma separators")

        local mixedSample = Pricing.FormatPrice((245000 * 10000) + (56 * 100) + 78)
        assert(mixedSample:find("245,000g", 1, true), "FormatPrice failed for mixed gold value")
        assert(mixedSample:find("56s", 1, true), "FormatPrice failed for silver value")
        assert(mixedSample:find("78c", 1, true), "FormatPrice failed for copper value")

        local negativeSample = Pricing.FormatPrice(-245000 * 10000)
        assert(negativeSample:sub(1, 1) == "-", "FormatPrice failed for negative value")
        assert(negativeSample:find("245,000g", 1, true), "FormatPrice failed for negative gold value")

        assert(Pricing.FormatPrice(0) == "0g", "FormatPrice failed for zero value")

        local originalGetUnitPrice = Pricing.GetUnitPrice
        local originalAHScan = GAM.AHScan
        local qtyPricingOK, qtyPricingErr = pcall(function()
            Pricing.GetUnitPrice = function(itemID)
                if itemID == 424242 then
                    return 12345, false
                end
                return nil, false
            end
            GAM.AHScan = {
                ComputePriceForQty = function(itemID, qty)
                    if itemID == 424242 and qty == 5000 then
                        return 67890
                    end
                    return nil
                end,
            }

            local price = Pricing.GetEffectivePrice(424242, GAM.C.DEFAULT_PATCH, 5000)
            assert(price == 67890, string.format(
                "qty-aware repricing failed: got %s expected 67890",
                tostring(price)))
        end)
        Pricing.GetUnitPrice = originalGetUnitPrice
        GAM.AHScan = originalAHScan
        assert(qtyPricingOK, qtyPricingErr)
        assert((GAM.C.VENDOR_PRICES and GAM.C.VENDOR_PRICES[243060]) == 5000,
            "Luminant Flux vendor-price baseline missing")
        assert((GAM.C.VENDOR_PRICES and GAM.C.VENDOR_PRICES[251665]) == 5000,
            "Silverleaf Thread vendor-price baseline missing")

        local originalGetEffectivePriceForItem = Pricing.GetEffectivePriceForItem
        local cheapestOK, cheapestErr = pcall(function()
            Pricing.GetEffectivePriceForItem = function(item)
                local exactID = item and item.itemIDs and item.itemIDs[1] or nil
                local prices = {
                    [1001] = 400,
                    [1002] = 450,
                    [1003] = 410,
                    [1004] = 399,
                }
                return prices[exactID], false
            end

            local opts = GetOpts()
            local savedPolicy = opts.rankPolicy
            opts.rankPolicy = "highest"
            local resolved = ResolveCheapestAlternative({
                cheapestOf = {
                    { itemRef = "Amani Lapis", itemIDs = { 1001, 1002 } },
                    { itemRef = "Flawless Amani Lapis", itemIDs = { 1003, 1004 } },
                },
            }, {
                patchTag = GAM.C.DEFAULT_PATCH,
                pdb = { rankGroups = {} },
            }, 15)
            opts.rankPolicy = savedPolicy
            assert(resolved and resolved.itemID == 1004, "cheapestOf rank-policy selection regressed")
        end)
        Pricing.GetEffectivePriceForItem = originalGetEffectivePriceForItem
        assert(cheapestOK, cheapestErr)

        local originalCraftUI = C_TradeSkillUI
        local originalGetItemInfo = GetItemInfo
        local originalGetEffectivePrice = Pricing.GetEffectivePrice
        local dazzlingRankOK, dazzlingRankErr = pcall(function()
            C_TradeSkillUI = {
                GetItemReagentQualityByItemInfo = function(itemID)
                    return ({
                        [242786] = 1,
                        [242787] = 2,
                    })[itemID]
                end,
            }
            GetItemInfo = function(itemID)
                return itemID and ("Item-" .. tostring(itemID)) or nil
            end
            Pricing.GetEffectivePrice = function(itemID)
                return ({
                    [242786] = 20500,
                    [242787] = 3605500,
                })[itemID], false
            end

            local dazzling = GAM.Importer and GAM.Importer.GetStratByID
                and GAM.Importer.GetStratByID("jewelcrafting__dazzling_thorium_prospecting__midnight_1") or nil
            assert(dazzling and dazzling.outputs and dazzling.outputs[7], "dazzling strat unavailable")
            assert(#(dazzling.outputs[7].itemIDs or {}) >= 2,
                "dazzling Crystalline Glass must keep both ranked itemIDs for runtime q1 selection")

            local price = GetOutputPriceForItem(dazzling.outputs[7], GAM.C.DEFAULT_PATCH, 1, 800)
            assert(price == 20500, string.format(
                "Dazzling Crystalline Glass rank resolution failed: got %s expected 20500",
                tostring(price)))
        end)
        C_TradeSkillUI = originalCraftUI
        GetItemInfo = originalGetItemInfo
        Pricing.GetEffectivePrice = originalGetEffectivePrice
        assert(dazzlingRankOK, dazzlingRankErr)

        local originalGetOptions = GAM.GetOptions
        local oilRankOK, oilRankErr = pcall(function()
            C_TradeSkillUI = {
                GetItemReagentQualityByItemInfo = function(itemID)
                    return nil
                end,
            }
            GetItemInfo = function(itemID)
                return itemID and ("Item-" .. tostring(itemID)) or nil
            end
            GAM.GetOptions = function()
                return { rankPolicy = "highest" }
            end
            Pricing.GetEffectivePrice = function(itemID)
                return ({
                    [243735] = 17500,
                    [243736] = 0,
                })[itemID], false
            end

            local function assertRankedIDs(ids, q1ID, q2ID, label)
                ids = ids or {}
                assert(#ids == 2 and ids[1] == q1ID and ids[2] == q2ID,
                    string.format("%s must keep Q1/Q2 IDs %s,%s: got %s",
                        label, tostring(q1ID), tostring(q2ID), table.concat(ids, ",")))
                local r2ID = PickItemID(ids, GAM.C.DEFAULT_PATCH, "highest")
                assert(r2ID == q2ID,
                    string.format("%s R2 must resolve to Q2 ID %s: got %s",
                        label, tostring(q2ID), tostring(r2ID)))
            end

            local oil = GAM.Importer and GAM.Importer.GetStratByID
                and GAM.Importer.GetStratByID("enchanting__oil_of_dawn__midnight_1") or nil
            assert(oil and oil.outputs and oil.outputs[1], "oil of dawn strat unavailable")
            assert(oil.reagents and oil.reagents[3] and oil.reagents[4], "oil of dawn ranked reagents unavailable")
            assertRankedIDs(oil.outputs[1].itemIDs, 243735, 243736, "Oil of Dawn output")
            assertRankedIDs(oil.reagents[3].itemIDs, 243599, 243600, "Oil of Dawn Eversinging Dust")
            assertRankedIDs(oil.reagents[4].itemIDs, 240990, 240991, "Oil of Dawn Sunglass Vial")

            local priceByPolicy = GetOutputPriceForItem(oil.outputs[1], GAM.C.DEFAULT_PATCH, nil, 8295)
            assert(priceByPolicy == 0, string.format(
                "Oil of Dawn rank-policy resolution failed: got %s expected 0",
                tostring(priceByPolicy)))

            local priceByPreferredQuality = GetOutputPriceForItem(oil.outputs[1], GAM.C.DEFAULT_PATCH, 2, 8295)
            assert(priceByPreferredQuality == 0, string.format(
                "Oil of Dawn R2 rank resolution failed: got %s expected 0",
                tostring(priceByPreferredQuality)))

            local phoenix = GAM.Importer and GAM.Importer.GetStratByID
                and GAM.Importer.GetStratByID("enchanting__thalassian_phoenix_oil__midnight_1") or nil
            assert(phoenix and phoenix.reagents and phoenix.reagents[2] and phoenix.reagents[3],
                "thalassian phoenix oil ranked reagents unavailable")
            assertRankedIDs(phoenix.reagents[2].itemIDs, 243599, 243600, "Thalassian Phoenix Oil Eversinging Dust")
            assertRankedIDs(phoenix.reagents[3].itemIDs, 240990, 240991, "Thalassian Phoenix Oil Sunglass Vial")

            local smuggler = GAM.Importer and GAM.Importer.GetStratByID
                and GAM.Importer.GetStratByID("enchanting__smuggler_s_enchanted_edge__midnight_1") or nil
            assert(smuggler and smuggler.outputs and smuggler.outputs[1]
                and smuggler.reagents and smuggler.reagents[3] and smuggler.reagents[4],
                "smuggler's enchanted edge ranked items unavailable")
            assertRankedIDs(smuggler.outputs[1].itemIDs, 243737, 243738, "Smuggler's Enchanted Edge output")
            assertRankedIDs(smuggler.reagents[3].itemIDs, 243599, 243600, "Smuggler's Enchanted Edge Eversinging Dust")
            assertRankedIDs(smuggler.reagents[4].itemIDs, 240990, 240991, "Smuggler's Enchanted Edge Sunglass Vial")
        end)
        C_TradeSkillUI = originalCraftUI
        GetItemInfo = originalGetItemInfo
        GAM.GetOptions = originalGetOptions
        Pricing.GetEffectivePrice = originalGetEffectivePrice
        assert(oilRankOK, oilRankErr)

        local originalGetEffectivePriceForOutputQty = Pricing.GetEffectivePrice
        local outputFillQtyOK, outputFillQtyErr = pcall(function()
            Pricing.GetEffectivePrice = function(itemID, patchTag, qty)
                return qty, false
            end

            local singleOutput = {
                itemIDs = { 424242 },
                baseYield = 3000,
                name = "Test Single Output",
            }
            local multiOutputA = {
                itemIDs = { 424243 },
                baseYield = 1200,
                name = "Test Multi Output A",
            }
            local multiOutputB = {
                itemIDs = { 424244 },
                baseYield = 800,
                name = "Test Multi Output B",
            }
            local baseCtx = {
                strat = {},
                patchTag = GAM.C.DEFAULT_PATCH,
                fillQty = 50,
                ahCut = GAM.C.AH_CUT,
                profileDef = nil,
                statDenom = nil,
                statMCp = nil,
                statMCm_tot = nil,
                startingAmt = 1,
                crafts = 1,
            }

            local singleMetrics = BuildOutputMetrics({
                strat = baseCtx.strat,
                active = {
                    output = singleOutput,
                    outputs = { singleOutput },
                    reagents = {},
                },
                patchTag = baseCtx.patchTag,
                fillQty = baseCtx.fillQty,
                ahCut = baseCtx.ahCut,
                profileDef = baseCtx.profileDef,
                statDenom = baseCtx.statDenom,
                statMCp = baseCtx.statMCp,
                statMCm_tot = baseCtx.statMCm_tot,
                startingAmt = baseCtx.startingAmt,
                crafts = baseCtx.crafts,
            })
            assert(singleMetrics and singleMetrics.output and singleMetrics.output.unitPrice == 50,
                string.format("single-output fill qty regression: got %s expected 50",
                    tostring(singleMetrics and singleMetrics.output and singleMetrics.output.unitPrice)))

            local multiMetrics = BuildOutputMetrics({
                strat = baseCtx.strat,
                active = {
                    output = multiOutputA,
                    outputs = { multiOutputA, multiOutputB },
                    reagents = {},
                },
                patchTag = baseCtx.patchTag,
                fillQty = baseCtx.fillQty,
                ahCut = baseCtx.ahCut,
                profileDef = baseCtx.profileDef,
                statDenom = baseCtx.statDenom,
                statMCp = baseCtx.statMCp,
                statMCm_tot = baseCtx.statMCm_tot,
                startingAmt = baseCtx.startingAmt,
                crafts = baseCtx.crafts,
            })
            assert(multiMetrics and multiMetrics.outputs and multiMetrics.outputs[1]
                and multiMetrics.outputs[1].unitPrice == 50,
                string.format("multi-output fill qty regression: got %s expected 50",
                    tostring(multiMetrics and multiMetrics.outputs and multiMetrics.outputs[1]
                        and multiMetrics.outputs[1].unitPrice)))
            assert(multiMetrics and multiMetrics.outputs and multiMetrics.outputs[2]
                and multiMetrics.outputs[2].unitPrice == 50,
                string.format("second multi-output fill qty regression: got %s expected 50",
                    tostring(multiMetrics and multiMetrics.outputs and multiMetrics.outputs[2]
                        and multiMetrics.outputs[2].unitPrice)))
        end)
        Pricing.GetEffectivePrice = originalGetEffectivePriceForOutputQty
        assert(outputFillQtyOK, outputFillQtyErr)

        local originalGetOptions = GAM.GetOptions
        local originalCraftUIForDrums = C_TradeSkillUI
        local originalGetEffectivePriceForDrums = Pricing.GetEffectivePrice
        local drumsRankOK, drumsRankErr = pcall(function()
            C_TradeSkillUI = {
                GetItemReagentQualityByItemInfo = function(itemID)
                    return ({
                        [238511] = 1,
                        [238512] = 2,
                        [238513] = 1,
                        [238514] = 2,
                    })[itemID]
                end,
            }
            GAM.GetOptions = function()
                return {
                    rankPolicy = "highest",
                    lwMulti = 32.0,
                    lwRes = 14.9,
                }
            end
            Pricing.GetEffectivePrice = function(itemID)
                return ({
                    [236952] = 8100,
                    [238525] = 5280357,
                    [238522] = 1319835,
                    [238511] = 49400,
                    [238512] = 620000,
                    [238513] = 167500,
                    [238514] = 480000,
                })[itemID], false
            end

            local drums = GAM.Importer and GAM.Importer.GetStratByID
                and GAM.Importer.GetStratByID("leatherworking__void_touched_drums__midnight_1") or nil
            assert(drums and drums.qualityPolicy == "force_q1_inputs", "void-touched drums strat unavailable")

            local ctx = BuildCalcContext(
                drums, GetActiveRecipeView(drums), GAM.C.DEFAULT_PATCH, 1, GAM.GetOptions(),
                GetPatchDB(GAM.C.DEFAULT_PATCH), GAM.C.AH_CUT)
            local reagents = BuildReagentMetrics(ctx)
            assert((reagents.reagentResults[4] and reagents.reagentResults[4].itemID) == 238511,
                "Void-Touched Drums must force Q1 Void-Tempered Leather")
            assert((reagents.reagentResults[5] and reagents.reagentResults[5].itemID) == 238513,
                "Void-Touched Drums must force Q1 Void-Tempered Scales")
        end)
        GAM.GetOptions = originalGetOptions
        C_TradeSkillUI = originalCraftUIForDrums
        Pricing.GetEffectivePrice = originalGetEffectivePriceForDrums
        assert(drumsRankOK, drumsRankErr)

        if GAM.Importer and GAM.Importer.GetStratByID then
            local crushing = GAM.Importer.GetStratByID("jewelcrafting__crushing__midnight_1")
            assert(crushing and crushing.reagents and crushing.reagents[1], "crushing strat unavailable")
            assert(type(crushing.reagents[1].cheapestOf) == "table" and #crushing.reagents[1].cheapestOf > 0,
                "normalized cheapestOf pool unavailable")
        end

        local score = Pricing.GetStrategyScore({ profit = 2500, roi = 9, totalCostFull = 1000 })
        assert(type(score) == "number", "strategy score unavailable")

        local viEconomicsOK, viEconomicsErr = pcall(function()
            local originalBuildDisplayReagentMetrics = BuildDisplayReagentMetrics
            local originalBuildEconomicReagentMetrics = BuildEconomicReagentMetrics
            local ok, err = pcall(function()
                BuildDisplayReagentMetrics = function()
                    return {
                        reagentResults = {
                            {
                                name = "Tranquility Bloom",
                                itemID = 236761,
                                required = 40,
                                needToBuy = 40,
                                totalCost = 120000,
                                totalCostFull = 120000,
                            },
                        },
                        hasStale = false,
                        totalCostToBuy = 120000,
                        totalCostRequired = 120000,
                        missingPrices = {},
                    }
                end
                BuildEconomicReagentMetrics = function()
                    return {
                        reagentResults = {
                            {
                                name = "Munsell Ink",
                                itemID = 245801,
                                required = 2,
                                requiredRaw = 2,
                                needToBuy = 2,
                                totalCost = 60000,
                                totalCostFull = 60000,
                            },
                        },
                        hasStale = false,
                        totalCostToBuy = 60000,
                        totalCostRequired = 60000,
                        missingPrices = {},
                    }
                end

                local metrics = BuildFinalMetrics(
                    {
                        ahCut = GAM.C.AH_CUT,
                        crafts = 1,
                        startingAmt = 1,
                        chainActive = true,
                    },
                    {
                        reagentResults = {
                            {
                                name = "Munsell Ink",
                                itemID = 245801,
                                required = 2,
                                needToBuy = 2,
                                totalCost = 60000,
                                totalCostFull = 60000,
                            },
                        },
                        hasStale = false,
                        totalCostToBuy = 60000,
                        totalCostRequired = 60000,
                        missingPrices = {},
                        selectionNotes = {},
                    },
                    {
                        output = {
                            name = "Thalassian Missive of the Fireflash",
                            itemID = 245785,
                            expectedQty = 2,
                            expectedQtyRaw = 2,
                            unitPrice = 50000,
                            netRevenue = 95000,
                        },
                        outputs = nil,
                        netRevenue = 95000,
                        outputQtyRaw = 2,
                        hasStale = false,
                        isMultiOutput = false,
                        missingPrices = {},
                    })

                assert(metrics.reagents and metrics.reagents[1] and metrics.reagents[1].required == 40,
                    "VI display rows must keep rounded shopping quantities")
                assert(metrics.totalCostFull == 60000,
                    string.format("VI total cost must use expected-value reagent cost, got %s", tostring(metrics.totalCostFull)))
                assert(metrics.totalCostToBuy == 60000,
                    string.format("VI buy-now cost must use expected-value reagent cost, got %s", tostring(metrics.totalCostToBuy)))
                local expectedBreakEven = 60000 / (2 * (1 - GAM.C.AH_CUT))
                assert(math.abs((metrics.breakEvenSell or 0) - expectedBreakEven) < 0.001,
                    string.format("VI break-even regression: got %.6f expected %.6f",
                        metrics.breakEvenSell or 0, expectedBreakEven))
            end)
            BuildDisplayReagentMetrics = originalBuildDisplayReagentMetrics
            BuildEconomicReagentMetrics = originalBuildEconomicReagentMetrics
            assert(ok, err)
        end)
        assert(viEconomicsOK, viEconomicsErr)

        -- ── Spreadsheet-parity checks ─────────────────────────────────────────
        -- Verify formula profiles reproduce workbookExpectedQty at default stats.
        local profiles = GetFormulaProfiles()

        -- insc_ink: live sheet Inscription!A18=29.7 (multi) and A16=16.1 (res)
        local inkProfile = profiles["insc_ink"]
        assert(inkProfile, "insc_ink profile missing")
        assert(math.abs((inkProfile.defaultMulti or 0) - 29.7) < 0.01,
            string.format("insc_ink defaultMulti parity fail: got %.3f expected 29.7", inkProfile.defaultMulti or 0))
        local missiveProfile = profiles["insc_missive_estimated"]
        assert(missiveProfile, "insc_missive_estimated profile missing")
        assert((missiveProfile.multiKey or "") == (inkProfile.multiKey or ""),
            "insc_missive_estimated multiKey must mirror insc_ink")
        assert((missiveProfile.resKey or "") == (inkProfile.resKey or ""),
            "insc_missive_estimated resKey must mirror insc_ink")
        local codifiedProfile = profiles["insc_codified"]
        assert(codifiedProfile, "insc_codified profile missing")

        -- leatherworking: live sheet Leatherworking!A18=32.0
        local lwProfile = profiles["leatherworking"]
        assert(lwProfile, "leatherworking profile missing")
        assert(math.abs((lwProfile.defaultMulti or 0) - 32.0) < 0.01,
            string.format("leatherworking defaultMulti parity fail: got %.3f expected 32.0", lwProfile.defaultMulti or 0))
        local bsProfile = profiles["blacksmithing"]
        assert(bsProfile, "blacksmithing profile missing")
        assert(math.abs((bsProfile.defaultMulti or 0) - 33.0) < 0.01,
            string.format("blacksmithing defaultMulti parity fail: got %.3f expected 33.0", bsProfile.defaultMulti or 0))
        assert(math.abs((bsProfile.sheetMCm or 0) - 1.4) < 0.01,
            string.format("blacksmithing sheetMCm parity fail: got %.3f expected 1.4", bsProfile.sheetMCm or 0))

        -- Engineering profiles must be split
        assert(profiles["engineering_recycling"], "engineering_recycling profile missing")
        assert(profiles["engineering_craft"], "engineering_craft profile missing")
        assert(not profiles["engineering"], "stale unified engineering profile still present")

        if GAM.Importer and GAM.Importer.GetStratByID then
            local function assertNear(actual, expected, label)
                assert(math.abs(actual - expected) <= math.max(0.0001, math.abs(expected) * 0.001),
                    string.format("%s: got %.6f expected %.6f", label, actual, expected))
            end

            local originalGetOptions = GAM.GetOptions
            local derivedParityOK, derivedParityErr = pcall(function()
                local parityOpts = {
                    pigmentCostSource = "mill",
                    boltCostSource = "craft",
                    ingotCostSource = "craft",
                    inscMillingRes = 30.1,
                    inscInkMulti = 29.7,
                    inscInkRes = 16.1,
                }
                GAM.GetOptions = function()
                    return parityOpts
                end

                local priceMap = {
                    [236761] = 30798,  -- Tranquility Bloom
                    [236776] = 239300, -- Argentleaf
                    [236778] = 120000, -- Mana Lily
                    [236770] = 10400,  -- Sanguithorn
                    [245882] = 3595,   -- Thalassian Songwater
                }
                local deps = {
                    PickItemID = function(ids)
                        return ids and ids[1] or nil
                    end,
                    GetEffectivePrice = function(itemID)
                        return priceMap[itemID], false
                    end,
                }

                local pigmentYield = 1.3 / (1 - 0.301 * 0.465)
                local inkYield = 0.1 * (1 + 0.297 * 2.5) / (1 - 0.161 * 0.465)

                local powderCost = Derivation.GetMillDerivedPigmentCost(245807, GAM.C.DEFAULT_PATCH, 1512, deps)
                local argentleafCost = Derivation.GetMillDerivedPigmentCost(245803, GAM.C.DEFAULT_PATCH, 756, deps)
                local manaCost = Derivation.GetMillDerivedPigmentCost(245867, GAM.C.DEFAULT_PATCH, 378, deps)
                local sanguithornCost = Derivation.GetMillDerivedPigmentCost(245865, GAM.C.DEFAULT_PATCH, 756, deps)

                assertNear(powderCost or 0, math.floor(priceMap[236761] / pigmentYield + 0.5),
                    "inscription powder pigment derived cost")
                assertNear(argentleafCost or 0, math.floor(priceMap[236776] / pigmentYield + 0.5),
                    "inscription argentleaf pigment derived cost")
                assertNear(manaCost or 0, math.floor(priceMap[236778] / pigmentYield + 0.5),
                    "inscription mana pigment derived cost")
                assertNear(sanguithornCost or 0, math.floor(priceMap[236770] / pigmentYield + 0.5),
                    "inscription sanguithorn pigment derived cost")

                local expectedSienna = math.floor((
                    (powderCost * 1.0)
                    + (argentleafCost * 0.5)
                    + (manaCost * 0.25)
                ) / inkYield + 0.5)
                local expectedMunsell = math.floor((
                    (powderCost * 1.0)
                    + (sanguithornCost * 0.5)
                    + (manaCost * 0.25)
                ) / inkYield + 0.5)

                local siennaCost = Derivation.GetCraftDerivedReagentCost(245805, GAM.C.DEFAULT_PATCH, 285, deps)
                local munsellCost = Derivation.GetCraftDerivedReagentCost(245801, GAM.C.DEFAULT_PATCH, 285, deps)
                assertNear(siennaCost or 0, expectedSienna, "inscription sienna derived cost")
                assertNear(munsellCost or 0, expectedMunsell, "inscription munsell derived cost")

                local sienna = GAM.Importer.GetStratByID("inscription__sienna_ink__midnight_1")
                assert(sienna, "sienna strat unavailable")
                local active = GetActiveRecipeView(sienna)
                local ctx = BuildCalcContext(
                    sienna, active, GAM.C.DEFAULT_PATCH, 1, parityOpts,
                    GetPatchDB(GAM.C.DEFAULT_PATCH), GAM.C.AH_CUT)
                local mergedOrder, mergedMap = BuildMergedReagentMap(ctx)
                assert(#mergedOrder == 4, string.format(
                    "sienna reagent list regressed to raw-chain expansion: got %d entries expected 4",
                    #mergedOrder))
                assert(mergedMap[245807] and mergedMap[245803] and mergedMap[245867] and mergedMap[245882],
                    "sienna reagent list must stay at powder/pigment/songwater sheet level")
                assert(mergedMap[245882].excludeFromCost,
                    "sienna songwater must stay visible but excluded from sheet cost math")

                local originalGetUnitPrice = Pricing.GetUnitPrice
                local originalGetItemCount = GetItemCount
                local recyclingParityOK, recyclingParityErr = pcall(function()
                    Pricing.GetUnitPrice = function(itemID)
                        local recyclingPrices = {
                            [236761] = 27000, -- cheaper herb-derived pigment would regress engineering recycling
                            [245807] = 24800, -- Powder Pigment Q1 direct sheet price
                            [243581] = 68900, -- Evercore Q1
                        }
                        return recyclingPrices[itemID], false
                    end
                    GetItemCount = function()
                        return 0
                    end

                    local recycling = GAM.Importer.GetStratByID("engineering__recycling_powder_pigment__midnight_1")
                    assert(recycling, "engineering recycling powder pigment strat unavailable")
                    assert(recycling.reagents and recycling.reagents[1] and recycling.reagents[1].skipDerivation,
                        "engineering recycling reagent must preserve skipDerivation")
                    local recyclingActive = GetActiveRecipeView(recycling)
                    local recyclingCtx = BuildCalcContext(
                        recycling, recyclingActive, GAM.C.DEFAULT_PATCH, 1, {
                            pigmentCostSource = "mill",
                            engRecycleRes = 36.0,
                            rankPolicy = "lowest",
                        }, GetPatchDB(GAM.C.DEFAULT_PATCH), GAM.C.AH_CUT)
                    local recyclingReagents = BuildReagentMetrics(recyclingCtx)
                    assertNear((recyclingReagents.reagentResults[1] and recyclingReagents.reagentResults[1].unitPrice) or 0,
                        24800, "engineering recycling powder pigment direct reagent price")
                    local recyclingOutput = BuildOutputMetrics(recyclingCtx)
                    assertNear((recyclingOutput.output and recyclingOutput.output.unitPrice) or 0, 68900,
                        "engineering recycling powder pigment output price")
                end)
                Pricing.GetUnitPrice = originalGetUnitPrice
                GetItemCount = originalGetItemCount
                assert(recyclingParityOK, recyclingParityErr)

                local displayParityOK, displayParityErr = pcall(function()
                    local originalGetUnitPrice = Pricing.GetUnitPrice
                    local originalGetItemCount = GetItemCount
                    Pricing.GetUnitPrice = function(itemID)
                        local displayPrices = {
                            [236761] = 27000,  -- Tranquility Bloom Q1
                            [236776] = 239300, -- Argentleaf Q1
                            [236778] = 120000, -- Mana Lily Q1
                            [236770] = 10400,  -- Sanguithorn Q1
                            [236963] = 81400,  -- Bright Linen Q1
                            [251665] = 5000,   -- Silverleaf Thread
                            [237359] = 31500,  -- Refulgent Copper Ore Q1
                            [243060] = 5000,   -- Luminant Flux
                            [245807] = 24800,  -- Powder Pigment Q1
                            [243581] = 68900,  -- Evercore Q1
                        }
                        return displayPrices[itemID], false
                    end
                    GetItemCount = function()
                        return 0
                    end

                    local function collectSeenIDs(metricRows)
                        local seen = {}
                        for _, row in ipairs(metricRows or {}) do
                            if row.itemID then
                                seen[row.itemID] = true
                            end
                        end
                        return seen
                    end

                    local soulCipher = GAM.Importer.GetStratByID("inscription__soul_cipher__midnight_1")
                    assert(soulCipher, "soul cipher strat unavailable")
                    local soulMetrics = Pricing.CalculateStratMetrics(soulCipher, GAM.C.DEFAULT_PATCH, 1)
                    local soulSeen = collectSeenIDs(soulMetrics and soulMetrics.reagents)
                    assert((soulSeen[236761] or soulSeen[236767]), "soul cipher VI must expand to herbs")
                    assert(not soulSeen[245805] and not soulSeen[245806] and not soulSeen[245801] and not soulSeen[245802],
                        "soul cipher VI must not display ink rows")

                    local codified = GAM.Importer.GetStratByID("inscription__codified_azeroot__midnight_1")
                    assert(codified, "codified azeroot strat unavailable")
                    local codifiedMetrics = Pricing.CalculateStratMetrics(codified, GAM.C.DEFAULT_PATCH, 1)
                    local codifiedSeen = collectSeenIDs(codifiedMetrics and codifiedMetrics.reagents)
                    assert((codifiedSeen[236761] or codifiedSeen[236767]),
                        "codified azeroot VI must recurse through soul cipher herbs")
                    assert(not codifiedSeen[245766] and not codifiedSeen[245767],
                        "codified azeroot VI must not display direct soul cipher rows")

                    local peerless = GAM.Importer.GetStratByID("inscription__peerless_missive__midnight_1")
                    assert(peerless, "peerless missive strat unavailable")
                    local peerlessMetrics = Pricing.CalculateStratMetrics(peerless, GAM.C.DEFAULT_PATCH, 10)
                    local missiveProfileCtx = BuildProfileContext(peerless, parityOpts)
                    local expectedMissiveQty = ComputeOutputQuantity(
                        (peerless.outputs and peerless.outputs[1]) or peerless.output,
                        peerless,
                        missiveProfileCtx.profileDef,
                        missiveProfileCtx.statDenom,
                        missiveProfileCtx.statMCp,
                        missiveProfileCtx.statMCm_tot,
                        10,
                        10)
                    assertNear((peerlessMetrics and peerlessMetrics.output and peerlessMetrics.output.expectedQtyRaw) or 0,
                        expectedMissiveQty,
                        "peerless missive estimated formula output")
                    local displayQtyByID = {}
                    for _, row in ipairs(peerlessMetrics and peerlessMetrics.reagents or {}) do
                        if row.itemID then
                            displayQtyByID[row.itemID] = row.required
                        end
                    end
                    assert(displayQtyByID[236761] and displayQtyByID[236761] > 0,
                        "peerless missive VI must plan tranquility bloom")
                    assert(displayQtyByID[236776] and displayQtyByID[236776] > 0,
                        "peerless missive VI must plan argentleaf")
                    assert(displayQtyByID[236770] and displayQtyByID[236770] > 0,
                        "peerless missive VI must plan sanguithorn")
                    assert(displayQtyByID[236778] and displayQtyByID[236778] > 0,
                        "peerless missive VI must plan mana lily")
                    assert(not displayQtyByID[245801] and not displayQtyByID[245802]
                        and not displayQtyByID[245805] and not displayQtyByID[245806],
                        "peerless missive VI must not display direct ink rows")

                    local imbuedBolt = GAM.Importer.GetStratByID("tailoring__imbued_bright_linen_bolt__midnight_1")
                    assert(imbuedBolt, "imbued bright linen bolt strat unavailable")
                    local boltMetrics = Pricing.CalculateStratMetrics(imbuedBolt, GAM.C.DEFAULT_PATCH, 1)
                    local boltSeen = collectSeenIDs(boltMetrics and boltMetrics.reagents)
                    assert((boltSeen[236963] or boltSeen[236965]) and boltSeen[251665],
                        "imbued bright linen bolt VI must expand to linen + thread")
                    assert(not boltSeen[239700] and not boltSeen[239701],
                        "imbued bright linen bolt VI must not display direct bolt rows")

                    local refulgentIngot = GAM.Importer.GetStratByID("blacksmithing__refulgent_copper_ingot__midnight_1")
                    assert(refulgentIngot, "refulgent copper ingot strat unavailable")
                    local ingotMetrics = Pricing.CalculateStratMetrics(refulgentIngot, GAM.C.DEFAULT_PATCH, 1)
                    local ingotSeen = collectSeenIDs(ingotMetrics and ingotMetrics.reagents)
                    assert(ingotSeen[237359] and ingotSeen[243060], "refulgent copper ingot VI must expand to ore + flux")
                    assert(not ingotSeen[238197] and not ingotSeen[238198],
                        "refulgent copper ingot VI must not display ingot rows")

                    local recycling = GAM.Importer.GetStratByID("engineering__recycling_powder_pigment__midnight_1")
                    assert(recycling, "engineering recycling powder pigment strat unavailable")
                    local recyclingMetrics = Pricing.CalculateStratMetrics(recycling, GAM.C.DEFAULT_PATCH, 1)
                    local recyclingSeen = collectSeenIDs(recyclingMetrics and recyclingMetrics.reagents)
                    assert(recyclingSeen[245807] and not recyclingSeen[236761] and not recyclingSeen[236767],
                        "engineering recycling VI display must remain direct")

                    local crushing = GAM.Importer.GetStratByID("jewelcrafting__crushing__midnight_1")
                    assert(crushing, "crushing strat unavailable")
                    local analyzer = Pricing.GetCrushingAnalyzerData(crushing, GAM.C.DEFAULT_PATCH)
                    assert(analyzer and analyzer.entries and #analyzer.entries > 0, "crushing analyzer data unavailable")
                    local scaledCrushingMetrics = Pricing.CalculateStratMetrics(crushing, GAM.C.DEFAULT_PATCH, 2)
                    local scaledAnalyzer = Pricing.GetCrushingAnalyzerData(crushing, GAM.C.DEFAULT_PATCH, scaledCrushingMetrics)
                    assert(scaledAnalyzer and scaledAnalyzer.crafts == scaledCrushingMetrics.crafts,
                        "crushing analyzer must inherit current craft quantity")
                    local selectedAnalyzerProfit = nil
                    for _, entry in ipairs(scaledAnalyzer.entries or {}) do
                        if entry.isSelected then
                            selectedAnalyzerProfit = entry.profit
                            break
                        end
                    end
                    assertNear(selectedAnalyzerProfit or 0, scaledCrushingMetrics.profit or 0,
                        "crushing analyzer selected profit must follow current craft quantity")
                end)
                Pricing.GetUnitPrice = originalGetUnitPrice
                GetItemCount = originalGetItemCount
                assert(displayParityOK, displayParityErr)
            end)
            GAM.GetOptions = originalGetOptions
            assert(derivedParityOK, derivedParityErr)

            local function checkWorkbookParity(stratID, outputIdx, expectedQty, label)
                local strat = GAM.Importer.GetStratByID(stratID)
                if not strat then return end
                local profileDef = profiles[strat.formulaProfile]
                if not profileDef then return end
                -- Build a default-opts snapshot for this profile so we evaluate at
                -- spreadsheet baseline stats (independent of the user's saved values).
                local defaultOpts = {}
                if profileDef.multiKey then
                    defaultOpts[profileDef.multiKey] = profileDef.defaultMulti or 0
                end
                if profileDef.resKey then
                    defaultOpts[profileDef.resKey] = profileDef.defaultRes or 0
                end
                local ctx = BuildProfileContext(strat, defaultOpts)
                local outputDef = strat.outputs and strat.outputs[outputIdx]
                if not outputDef then return end
                local sa = strat.defaultStartingAmount or 1
                local cr = strat.defaultCrafts or sa
                local qty = ComputeOutputQuantity(outputDef, strat, ctx.profileDef, ctx.statDenom, ctx.statMCp, ctx.statMCm_tot, sa, cr)
                assertNear(qty, expectedQty, "Parity " .. label)
            end

            local function checkVariantWorkbookParity(stratID, variantKey, outputIdx, expectedQty, label)
                local strat = GAM.Importer.GetStratByID(stratID)
                if not strat or not strat.rankVariants or not strat.rankVariants[variantKey] then
                    return
                end
                local variant = strat.rankVariants[variantKey]
                local profileDef = profiles[strat.formulaProfile]
                if not profileDef then return end
                local defaultOpts = {}
                if profileDef.multiKey then
                    defaultOpts[profileDef.multiKey] = profileDef.defaultMulti or 0
                end
                if profileDef.resKey then
                    defaultOpts[profileDef.resKey] = profileDef.defaultRes or 0
                end
                local ctx = BuildProfileContext(strat, defaultOpts)
                local outputDef = variant.outputs and variant.outputs[outputIdx]
                if not outputDef then return end
                local sa = variant.defaultStartingAmount or strat.defaultStartingAmount or 1
                local cr = variant.defaultCrafts or strat.defaultCrafts or sa
                assertNear(outputDef.workbookExpectedQty or 0, expectedQty, label .. " workbookExpectedQty")
                local qty = ComputeOutputQuantity(outputDef, strat, ctx.profileDef, ctx.statDenom, ctx.statMCp, ctx.statMCm_tot, sa, cr)
                assertNear(qty, expectedQty, "Parity " .. label)
            end

            local engineeringRecyclingIDs = {
                "engineering__recycling_argentleaf_pigment__midnight_1",
                "engineering__recycling_bright_linen_bolt__midnight_1",
                "engineering__recycling_codified_azeroot__midnight_1",
                "engineering__recycling_imbued_bright_linen_bolt__midnight_1",
                "engineering__recycling_powder_pigment__midnight_1",
            }
            for _, stratID in ipairs(engineeringRecyclingIDs) do
                local strat = GAM.Importer.GetStratByID(stratID)
                if strat then
                    assertNear(strat.defaultStartingAmount or 0, 5000, stratID .. " defaultStartingAmount")
                    assertNear(strat.defaultCrafts or 0, 1000, stratID .. " defaultCrafts")
                    assertNear((strat.outputs and strat.outputs[1] and strat.outputs[1].baseYieldPerCraft) or 0, 2.776595,
                        stratID .. " baseYieldPerCraft")
                    assertNear((strat.reagents and strat.reagents[1] and strat.reagents[1].qtyPerCraft) or 0, 5.0,
                        stratID .. " reagent qtyPerCraft")
                    assertNear((strat.reagents and strat.reagents[1] and strat.reagents[1].qtyPerStart) or 0, 1.0,
                        stratID .. " reagent qtyPerStart")
                end
                checkWorkbookParity(stratID, 1, 3292.144942, stratID .. " Engineering recycling")
            end

            local refulgent = GAM.Importer.GetStratByID("blacksmithing__refulgent_copper_ingot__midnight_1")
            if refulgent then
                assertNear(refulgent.defaultStartingAmount or 0, 5000.0, "Refulgent Copper Ingot defaultStartingAmount")
                assertNear(refulgent.defaultCrafts or 0, 1000.0, "Refulgent Copper Ingot defaultCrafts")
                assertNear((refulgent.rankVariants and refulgent.rankVariants.lowest
                    and refulgent.rankVariants.lowest.defaultStartingAmount) or 0,
                    5000.0, "Refulgent Copper Ingot lowest defaultStartingAmount")
                assertNear((refulgent.rankVariants and refulgent.rankVariants.lowest
                    and refulgent.rankVariants.lowest.defaultCrafts) or 0,
                    1000.0, "Refulgent Copper Ingot lowest defaultCrafts")
                assertNear((refulgent.rankVariants and refulgent.rankVariants.highest
                    and refulgent.rankVariants.highest.defaultStartingAmount) or 0,
                    5000.0, "Refulgent Copper Ingot highest defaultStartingAmount")
                assertNear((refulgent.rankVariants and refulgent.rankVariants.highest
                    and refulgent.rankVariants.highest.defaultCrafts) or 0,
                    1000.0, "Refulgent Copper Ingot highest defaultCrafts")
            end
            checkVariantWorkbookParity("blacksmithing__refulgent_copper_ingot__midnight_1", "lowest", 1, 1548.892891,
                "Blacksmithing Refulgent Copper Ingot Q1")
            checkVariantWorkbookParity("blacksmithing__refulgent_copper_ingot__midnight_1", "highest", 1, 1548.892891,
                "Blacksmithing Refulgent Copper Ingot Q2")

            local gloaming = GAM.Importer.GetStratByID("blacksmithing__gloaming_alloy__midnight_1")
            if gloaming then
                assertNear((gloaming.defaultStartingAmount or 0), 600.0, "Gloaming Alloy defaultStartingAmount")
                assertNear((gloaming.defaultCrafts or 0), 100.0, "Gloaming Alloy defaultCrafts")
                assertNear((gloaming.rankVariants and gloaming.rankVariants.lowest
                    and gloaming.rankVariants.lowest.defaultStartingAmount) or 0,
                    600.0, "Gloaming Alloy lowest defaultStartingAmount")
                assertNear((gloaming.rankVariants and gloaming.rankVariants.lowest
                    and gloaming.rankVariants.lowest.defaultCrafts) or 0,
                    100.0, "Gloaming Alloy lowest defaultCrafts")
                assertNear((gloaming.rankVariants and gloaming.rankVariants.highest
                    and gloaming.rankVariants.highest.defaultStartingAmount) or 0,
                    600.0, "Gloaming Alloy highest defaultStartingAmount")
                assertNear((gloaming.rankVariants and gloaming.rankVariants.highest
                    and gloaming.rankVariants.highest.defaultCrafts) or 0,
                    100.0, "Gloaming Alloy highest defaultCrafts")
            end
            checkVariantWorkbookParity("blacksmithing__gloaming_alloy__midnight_1", "lowest", 1, 154.8892891,
                "Blacksmithing Gloaming Alloy Q1")
            checkVariantWorkbookParity("blacksmithing__gloaming_alloy__midnight_1", "highest", 1, 154.8892891,
                "Blacksmithing Gloaming Alloy Q2")

            local sterling = GAM.Importer.GetStratByID("blacksmithing__sterling_alloy__midnight_1")
            if sterling then
                assertNear((sterling.defaultStartingAmount or 0), 6000.0, "Sterling Alloy defaultStartingAmount")
                assertNear((sterling.defaultCrafts or 0), 1000.0, "Sterling Alloy defaultCrafts")
                assertNear((sterling.rankVariants and sterling.rankVariants.lowest
                    and sterling.rankVariants.lowest.defaultStartingAmount) or 0,
                    6000.0, "Sterling Alloy lowest defaultStartingAmount")
                assertNear((sterling.rankVariants and sterling.rankVariants.lowest
                    and sterling.rankVariants.lowest.defaultCrafts) or 0,
                    1000.0, "Sterling Alloy lowest defaultCrafts")
                assertNear((sterling.rankVariants and sterling.rankVariants.highest
                    and sterling.rankVariants.highest.defaultStartingAmount) or 0,
                    1590.0, "Sterling Alloy highest defaultStartingAmount")
                assertNear((sterling.rankVariants and sterling.rankVariants.highest
                    and sterling.rankVariants.highest.defaultCrafts) or 0,
                    265.0, "Sterling Alloy highest defaultCrafts")
            end
            checkVariantWorkbookParity("blacksmithing__sterling_alloy__midnight_1", "lowest", 1, 1548.892891,
                "Blacksmithing Sterling Alloy Q1")
            checkVariantWorkbookParity("blacksmithing__sterling_alloy__midnight_1", "highest", 1, 410.456616,
                "Blacksmithing Sterling Alloy Q2")

            local dawn = GAM.Importer.GetStratByID("enchanting__dawn_shatter_q2__midnight_1")
            if dawn then
                assertNear((dawn.outputs and dawn.outputs[1] and dawn.outputs[1].workbookExpectedQty) or 0, 3086.673801,
                    "dawn_shatter_q2 top-level workbookExpectedQty")
                assertNear((dawn.rankVariants and dawn.rankVariants.lowest and dawn.rankVariants.lowest.outputs
                    and dawn.rankVariants.lowest.outputs[1] and dawn.rankVariants.lowest.outputs[1].workbookExpectedQty) or 0,
                    3086.673801, "dawn_shatter_q2 lowest workbookExpectedQty")
            end
            checkVariantWorkbookParity("enchanting__dawn_shatter_q2__midnight_1", "highest", 1, 2262.531896,
                "Dawn Shatter highest output 1")
            checkVariantWorkbookParity("enchanting__dawn_shatter_q2__midnight_1", "highest", 2, 824.141905,
                "Dawn Shatter highest output 2")

            local radiant = GAM.Importer.GetStratByID("enchanting__radiant_shatter_q2__midnight_1")
            if radiant then
                assertNear((radiant.outputs and radiant.outputs[1] and radiant.outputs[1].workbookExpectedQty) or 0, 3086.673801,
                    "radiant_shatter_q2 top-level workbookExpectedQty")
                assertNear((radiant.rankVariants and radiant.rankVariants.lowest and radiant.rankVariants.lowest.outputs
                    and radiant.rankVariants.lowest.outputs[1] and radiant.rankVariants.lowest.outputs[1].workbookExpectedQty) or 0,
                    3086.673801, "radiant_shatter_q2 lowest workbookExpectedQty")
            end
            checkVariantWorkbookParity("enchanting__radiant_shatter_q2__midnight_1", "highest", 1, 2262.531896,
                "Radiant Shatter highest output 1")
            checkVariantWorkbookParity("enchanting__radiant_shatter_q2__midnight_1", "highest", 2, 824.141905,
                "Radiant Shatter highest output 2")

            local crushing = GAM.Importer.GetStratByID("jewelcrafting__crushing__midnight_1")
            if crushing then
                assertNear(crushing.defaultStartingAmount or 0, 426.0, "jc_crush defaultStartingAmount")
                assertNear(crushing.defaultCrafts or 0, 142.0, "jc_crush defaultCrafts")
                assertNear((crushing.outputs and crushing.outputs[1] and crushing.outputs[1].baseYieldPerCraft) or 0, 2.09,
                    "jc_crush baseYieldPerCraft")
                assertNear((crushing.reagents and crushing.reagents[1] and crushing.reagents[1].qtyPerCraft) or 0, 3.0,
                    "jc_crush cheapest gem qtyPerCraft")
            end
            checkWorkbookParity("jewelcrafting__crushing__midnight_1", 1, 348.5378743,
                "Jewelcrafting crushing G23")

            local jcRefulgent = GAM.Importer.GetStratByID("jewelcrafting__refulgent_copper_ore_prospecting__midnight_1")
            if jcRefulgent then
                assertNear(jcRefulgent.defaultStartingAmount or 0, 2000.0,
                    "jc prospect refulgent defaultStartingAmount")
                assertNear(jcRefulgent.defaultCrafts or 0, 400.0,
                    "jc prospect refulgent defaultCrafts")
                assertNear((jcRefulgent.outputs and jcRefulgent.outputs[1] and jcRefulgent.outputs[1].baseYieldPerCraft) or 0,
                    0.115, "jc prospect refulgent baseYieldPerCraft")
                assertNear((jcRefulgent.reagents and jcRefulgent.reagents[1] and jcRefulgent.reagents[1].qtyPerStart) or 0,
                    1.0, "jc prospect refulgent qtyPerStart")
            end
            checkWorkbookParity("jewelcrafting__refulgent_copper_ore_prospecting__midnight_1", 1, 55.48854041,
                "Jewelcrafting refulgent output 1")
            checkWorkbookParity("jewelcrafting__refulgent_copper_ore_prospecting__midnight_1", 5, 12.06272618,
                "Jewelcrafting refulgent diamond")
            checkWorkbookParity("jewelcrafting__refulgent_copper_ore_prospecting__midnight_1", 6, 482.509047,
                "Jewelcrafting refulgent stone")
            checkWorkbookParity("jewelcrafting__refulgent_copper_ore_prospecting__midnight_1", 7, 337.7563329,
                "Jewelcrafting refulgent glass")

            local jcBrilliant = GAM.Importer.GetStratByID("jewelcrafting__brilliant_silver_ore_prospecting__midnight_1")
            if jcBrilliant then
                assertNear(jcBrilliant.defaultStartingAmount or 0, 15000.0,
                    "jc prospect brilliant defaultStartingAmount")
                assertNear(jcBrilliant.defaultCrafts or 0, 3000.0,
                    "jc prospect brilliant defaultCrafts")
                assertNear((jcBrilliant.outputs and jcBrilliant.outputs[1] and jcBrilliant.outputs[1].baseYieldPerCraft) or 0,
                    0.17, "jc prospect brilliant baseYieldPerCraft")
                assertNear((jcBrilliant.reagents and jcBrilliant.reagents[1] and jcBrilliant.reagents[1].qtyPerStart) or 0,
                    1.0, "jc prospect brilliant qtyPerStart")
            end
            checkWorkbookParity("jewelcrafting__brilliant_silver_ore_prospecting__midnight_1", 1, 615.199035,
                "Jewelcrafting brilliant output 1")
            checkWorkbookParity("jewelcrafting__brilliant_silver_ore_prospecting__midnight_1", 3, 568.1544029,
                "Jewelcrafting brilliant flawless output")
            checkWorkbookParity("jewelcrafting__brilliant_silver_ore_prospecting__midnight_1", 5, 155.6091677,
                "Jewelcrafting brilliant diamond")
            checkWorkbookParity("jewelcrafting__brilliant_silver_ore_prospecting__midnight_1", 6, 3437.87696,
                "Jewelcrafting brilliant stone")
            checkWorkbookParity("jewelcrafting__brilliant_silver_ore_prospecting__midnight_1", 7, 2757.539204,
                "Jewelcrafting brilliant glass")

            local jcUmbral = GAM.Importer.GetStratByID("jewelcrafting__umbral_tin_ore_prospecting__midnight_1")
            if jcUmbral then
                assertNear(jcUmbral.defaultStartingAmount or 0, 15000.0,
                    "jc prospect umbral defaultStartingAmount")
                assertNear(jcUmbral.defaultCrafts or 0, 3000.0,
                    "jc prospect umbral defaultCrafts")
                assertNear((jcUmbral.outputs and jcUmbral.outputs[1] and jcUmbral.outputs[1].baseYieldPerCraft) or 0,
                    0.17, "jc prospect umbral baseYieldPerCraft")
                assertNear((jcUmbral.reagents and jcUmbral.reagents[1] and jcUmbral.reagents[1].qtyPerStart) or 0,
                    1.0, "jc prospect umbral qtyPerStart")
            end
            checkWorkbookParity("jewelcrafting__umbral_tin_ore_prospecting__midnight_1", 1, 615.199035,
                "Jewelcrafting umbral output 1")
            checkWorkbookParity("jewelcrafting__umbral_tin_ore_prospecting__midnight_1", 3, 568.1544029,
                "Jewelcrafting umbral flawless output")
            checkWorkbookParity("jewelcrafting__umbral_tin_ore_prospecting__midnight_1", 5, 155.6091677,
                "Jewelcrafting umbral diamond")
            checkWorkbookParity("jewelcrafting__umbral_tin_ore_prospecting__midnight_1", 6, 3437.87696,
                "Jewelcrafting umbral stone")
            checkWorkbookParity("jewelcrafting__umbral_tin_ore_prospecting__midnight_1", 7, 2757.539204,
                "Jewelcrafting umbral glass")

            checkWorkbookParity("jewelcrafting__sin_dorei_lens_crafting__midnight_1", 1, 1873.492159,
                "Jewelcrafting lens crafting")
            local jcSunglass = GAM.Importer.GetStratByID("jewelcrafting__sunglass_vial_crafting__midnight_1")
            if jcSunglass then
                assertNear((jcSunglass.reagents and jcSunglass.reagents[1] and jcSunglass.reagents[1].qtyPerCraft) or 0, 5.0,
                    "Jewelcrafting sunglass glass qtyPerCraft")
                assertNear((jcSunglass.reagents and jcSunglass.reagents[2] and jcSunglass.reagents[2].qtyPerCraft) or 0, 1.0,
                    "Jewelcrafting sunglass stone qtyPerCraft")
                assertNear((jcSunglass.reagents and jcSunglass.reagents[2] and jcSunglass.reagents[2].qtyPerStart) or 0, 0.2,
                    "Jewelcrafting sunglass stone qtyPerStart")
            end
            checkWorkbookParity("jewelcrafting__sunglass_vial_crafting__midnight_1", 1, 337.2285887,
                "Jewelcrafting sunglass vial crafting")
            local amani = GAM.Importer.GetStratByID("alchemy__amani_extract__midnight_1")
            if amani then
                assertNear(amani.defaultStartingAmount or 0, 5000.0, "Amani Extract defaultStartingAmount")
                assertNear(amani.defaultCrafts or 0, 1000.0, "Amani Extract defaultCrafts")
                assertNear((amani.reagents and amani.reagents[1] and amani.reagents[1].qtyPerCraft) or 0, 5.0,
                    "Amani Extract sunglass vial qtyPerCraft")
            end
            checkWorkbookParity("alchemy__amani_extract__midnight_1", 1, 7591.623037,
                "Alchemy Amani Extract C57")
            checkWorkbookParity("inscription__codified_azeroot__midnight_1", 1, 1522.982248,
                "Inscription codified azeroot O31")

            local jcCrushProfile = profiles["jc_crush"]
            assert(jcCrushProfile, "jc_crush profile missing")
            assertNear(jcCrushProfile.defaultRes or 0, 33.0, "jc_crush defaultRes")
            assertNear(jcCrushProfile.defaultRsNode or 0, 50.0, "jc_crush defaultRsNode")
            assertNear(jcCrushProfile.sheetRs or 0, 0.45, "jc_crush sheetRs")
            assertNear(codifiedProfile.sheetRs or 0, 0.495, "insc_codified sheetRs")

            -- Engineering!C56 craft parity
            checkWorkbookParity("engineering__soul_sprocket__midnight_1", 1, 1950.595878,
                "Engineering craft C56")
            -- Engineering!O37 craft parity (500-craft baseline)
            checkWorkbookParity("engineering__emergency_soul_link__midnight_1", 1, 975.297939,
                "Engineering craft O37")
        end
    end)
    return ok, err
end

-- ===== Stat scaling (Workbook-driven formula profiles) =====

-- ===== Chain expansion for shopping list =====

-- ===== Core calculation =====

local function GetFormulaFactor(strat, profileDef, statDenom, statMCp, statMCm_tot)
    if strat.calcMode == "formula" and profileDef and statDenom then
        return (1 + statMCp * statMCm_tot) / statDenom
    end
    return 1
end

local function ComputeOutputQuantity(outputDef, strat, profileDef, statDenom, statMCp, statMCm_tot, startingAmt, crafts)
    if not outputDef then
        return 0, 0
    end

    local baseYield = outputDef.baseYield
    if baseYield == nil then
        baseYield = outputDef.baseYieldMultiplier
    end
    if baseYield == nil then
        baseYield = outputDef.qtyMultiplier
    end
    if outputDef.baseYieldPerCraft ~= nil then
        baseYield = outputDef.baseYieldPerCraft
    end

    local factor = GetFormulaFactor(strat, profileDef, statDenom, statMCp, statMCm_tot)
    local qtyRaw
    if outputDef.baseYieldPerCraft ~= nil then
        qtyRaw = crafts * (baseYield or 0) * factor
    else
        qtyRaw = startingAmt * (baseYield or 0) * factor
    end

    return qtyRaw, math.floor(qtyRaw + 0.5)
end

local function BuildProfileContext(strat, opts)
    local profileKey = strat.formulaProfile
    local profileDef = profileKey and GetFormulaProfiles()[profileKey] or nil
    local statMCp, statRp, statMCm_tot, statRs_tot, statDenom

    if strat.calcMode == "formula" and profileDef then
        local function GetNodeValue(key, defaultValue)
            if not key then
                return defaultValue or 0
            end
            local value = opts[key]
            if value == nil then
                return defaultValue or 0
            end
            return value
        end
        local function ScaleSheetBonus(sheetValue, defaultNodeValue, actualNodeValue)
            local baseline = tonumber(sheetValue)
            if baseline == nil then
                return nil
            end
            local defaultFactor = 1 + ((tonumber(defaultNodeValue) or 0) / 100)
            local actualFactor = 1 + ((tonumber(actualNodeValue) or 0) / 100)
            if defaultFactor <= 0 then
                return baseline
            end
            return baseline * (actualFactor / defaultFactor)
        end

        statMCp = profileDef.multiKey and ((opts[profileDef.multiKey] or 0) / 100) or 0
        statRp = profileDef.resKey and ((opts[profileDef.resKey] or 0) / 100) or 0
        -- Preserve workbook parity at the sheet's default node bonuses, then
        -- scale those baked effective multipliers to the player's live node values.
        statMCm_tot = profileDef.multiKey and (
            ScaleSheetBonus(
                profileDef.sheetMCm or GAM.C.BASE_MCM,
                profileDef.defaultMcNode or 0,
                GetNodeValue(profileDef.mcNodeKey, profileDef.defaultMcNode))
            or (profileDef.sheetMCm or GAM.C.BASE_MCM)
        ) or 0
        statRs_tot = ScaleSheetBonus(
            profileDef.sheetRs or GAM.C.BASE_RS,
            profileDef.defaultRsNode or 0,
            GetNodeValue(profileDef.rsNodeKey, profileDef.defaultRsNode))
            or (profileDef.sheetRs or GAM.C.BASE_RS)
        statDenom = 1 - statRp * statRs_tot
        if statDenom <= 0 then
            statDenom = 1
        end
    end

    return {
        profileDef = profileDef,
        statMCp = statMCp,
        statRp = statRp,
        statMCm_tot = statMCm_tot,
        statRs_tot = statRs_tot,
        statDenom = statDenom,
    }
end

local function ResolveStartingAmountAndCrafts(strat, active, pdb, craftQty)
    local startingAmt = (active.defaultStartingAmount or strat.defaultStartingAmount or 1) * craftQty

    if pdb.inputQtyOverrides and pdb.inputQtyOverrides[strat.id] then
        startingAmt = pdb.inputQtyOverrides[strat.id]
    end

    local defaultCrafts = active.defaultCrafts or strat.defaultCrafts
        or active.defaultStartingAmount or strat.defaultStartingAmount or 1
    if defaultCrafts <= 0 then
        defaultCrafts = 1
    end

    local crafts = defaultCrafts
    local baseStartingAmount = active.defaultStartingAmount or strat.defaultStartingAmount or 0
    if baseStartingAmount > 0 then
        crafts = defaultCrafts * (startingAmt / baseStartingAmount)
    end

    if pdb.craftsOverrides and pdb.craftsOverrides[strat.id] then
        crafts = pdb.craftsOverrides[strat.id]
        local dsa = active.defaultStartingAmount or strat.defaultStartingAmount or 0
        local dc = active.defaultCrafts or strat.defaultCrafts or dsa or 1
        if dsa > 0 and dc > 0 then
            startingAmt = crafts * dsa / dc
        else
            startingAmt = crafts
        end
    end

    return startingAmt, crafts
end

local function IsVerticalIntegrationEnabled(opts)
    opts = opts or GetOpts()
    return (opts.pigmentCostSource == "mill")
        or (opts.ingotCostSource == "craft")
        or (opts.boltCostSource == "craft")
end

BuildCalcContext = function(strat, active, patchTag, craftQty, opts, pdb, ahCut)
    local profile = BuildProfileContext(strat, opts)
    local startingAmt, crafts = ResolveStartingAmountAndCrafts(strat, active, pdb, craftQty)

    return {
        strat = strat,
        active = active,
        patchTag = patchTag,
        opts = opts,
        pdb = pdb,
        ahCut = ahCut,
        fillQty = opts.shallowFillQty or GAM.C.DEFAULT_FILL_QTY,
        -- The UI's single VI toggle flips the legacy source knobs together; pricing
        -- treats that combined state as the authoritative recurse-or-buy decision.
        chainActive = IsVerticalIntegrationEnabled(opts),
        startingAmt = startingAmt,
        crafts = crafts,
        profileDef = profile.profileDef,
        statMCp = profile.statMCp,
        statRp = profile.statRp,
        statMCm_tot = profile.statMCm_tot,
        statRs_tot = profile.statRs_tot,
        statDenom = profile.statDenom,
    }
end

local function GetResolvedReagentItemIDs(reagent, pdb)
    local reagentIDs = reagent.itemIDs
    local label = GetItemLabel(reagent)
    if (not reagentIDs or #reagentIDs == 0) and label then
        reagentIDs = pdb.rankGroups[label] or {}
    end
    return reagentIDs
end

local function GetRequiredReagentAmountRaw(reagent, startingAmt, crafts)
    local qtyPerCraft = reagent.qtyPerCraft
    local requiredRaw
    if qtyPerCraft ~= nil then
        requiredRaw = qtyPerCraft * crafts
    else
        local qtyPerStart = reagent.qtyPerStart or reagent.qtyMultiplier or 0
        requiredRaw = qtyPerStart * startingAmt
    end
    return requiredRaw or 0
end

local function QuantizeRequiredAmount(requiredRaw, roundMode)
    local value = tonumber(requiredRaw) or 0
    if roundMode == "none" then
        return value
    end
    if roundMode == "ceil" then
        if value <= 0 then
            return 0
        end
        return math.ceil(value - 1e-9)
    end
    return math.floor(value + 0.5)
end

local function AddMergedReagentEntry(mergedMap, mergedOrder, key, itemIDs, qty, name, cheapestOf, excludeFromCost, skipDerivation)
    if mergedMap[key] then
        mergedMap[key].qty = mergedMap[key].qty + qty
        mergedMap[key].excludeFromCost = mergedMap[key].excludeFromCost or excludeFromCost
        mergedMap[key].skipDerivation = mergedMap[key].skipDerivation or skipDerivation
        return
    end
    mergedMap[key] = {
        itemIDs = itemIDs,
        qty = qty,
        name = name,
        cheapestOf = cheapestOf,
        excludeFromCost = excludeFromCost and true or false,
        skipDerivation = skipDerivation and true or false,
    }
    tinsert(mergedOrder, key)
end

BuildMergedReagentMap = function(ctx, roundMode)
    roundMode = roundMode or "nearest"
    local mergedMap = {}
    local mergedOrder = {}

    for _, reagent in ipairs(ctx.active.reagents or {}) do
        local required = QuantizeRequiredAmount(
            GetRequiredReagentAmountRaw(reagent, ctx.startingAmt, ctx.crafts),
            roundMode)
        local reagentIDs = GetResolvedReagentItemIDs(reagent, ctx.pdb)
        local reagentName = GetItemLabel(reagent)
        local inputPolicy = GetInputRankPolicy(ctx.strat)
        local key = PickItemID(reagentIDs, ctx.patchTag, inputPolicy) or (reagentIDs and reagentIDs[1]) or reagentName
        AddMergedReagentEntry(
            mergedMap, mergedOrder, key, reagentIDs, required, reagentName,
            reagent.cheapestOf, reagent.excludeFromCost, reagent.skipDerivation)
    end

    return mergedOrder, mergedMap
end

ResolveCheapestAlternative = function(entry, ctx, required)
    if not (entry and entry.cheapestOf) then
        return nil
    end

    local best = nil
    local inputPolicy = GetInputRankPolicy(ctx.strat)
    for _, alt in ipairs(entry.cheapestOf) do
        local altIDs = alt.itemIDs
        if (not altIDs or #altIDs == 0) and alt.itemRef then
            altIDs = ctx.pdb.rankGroups[alt.itemRef] or {}
        end

        if altIDs and #altIDs > 0 then
            -- Compare alternatives within the active rank policy so an R2 pool
            -- chooses the cheapest R2 reagent, not the cheapest reagent of any rank.
            local pickedAltID = PickItemID(altIDs, ctx.patchTag, inputPolicy)
            local altPrice, altStale = Pricing.GetEffectivePriceForItem({
                itemIDs = pickedAltID and { pickedAltID } or altIDs,
                name = alt.itemRef,
                rankPolicyOverride = inputPolicy,
            }, ctx.patchTag, required)
            if altPrice and pickedAltID and (not best or altPrice < best.price) then
                best = {
                    itemID = pickedAltID,
                    itemIDs = altIDs,
                    name = alt.itemRef,
                    price = altPrice,
                    stale = altStale or false,
                }
            end
        else
            local altProxy = { itemIDs = altIDs or {}, name = alt.itemRef, rankPolicyOverride = inputPolicy }
            local altPrice, altStale = Pricing.GetEffectivePriceForItem(altProxy, ctx.patchTag, required)
            if altPrice and (not best or altPrice < best.price) then
                best = {
                    itemID = PickItemID(altIDs, ctx.patchTag, inputPolicy),
                    itemIDs = altIDs,
                    name = alt.itemRef,
                    price = altPrice,
                    stale = altStale or false,
                }
            end
        end
    end

    return best
end

local function CountOwnedReagentItems(itemID, entryIDs)
    local userHave = 0
    if itemID then
        return GetItemCount(itemID, true) or 0
    end
    if entryIDs and #entryIDs > 0 then
        for _, reagentID in ipairs(entryIDs) do
            userHave = userHave + (GetItemCount(reagentID, true) or 0)
        end
    end
    return userHave
end

local function GetCheapestAlternativeScanIDs(entry, ctx)
    if not (entry and entry.cheapestOf) then
        return nil
    end
    local seen = {}
    local scanIDs = {}
    for _, alt in ipairs(entry.cheapestOf) do
        local altIDs = alt.itemIDs
        if (not altIDs or #altIDs == 0) and alt.itemRef then
            altIDs = ctx.pdb.rankGroups[alt.itemRef] or {}
        end
        for _, altID in ipairs(altIDs or {}) do
            if not seen[altID] then
                seen[altID] = true
                scanIDs[#scanIDs + 1] = altID
            end
        end
    end
    return (#scanIDs > 0) and scanIDs or nil
end

local function MergeUniqueItemIDs(target, source)
    if not source or #source == 0 then
        return target
    end
    target = target or {}
    local seen = {}
    for _, itemID in ipairs(target) do
        seen[itemID] = true
    end
    for _, itemID in ipairs(source) do
        if itemID and not seen[itemID] then
            seen[itemID] = true
            target[#target + 1] = itemID
        end
    end
    return target
end

local function GetScaledStartingAmountForCrafts(active, crafts)
    local defaultCrafts = (active and active.defaultCrafts) or (active and active.defaultStartingAmount) or 1
    local defaultStartingAmount = (active and active.defaultStartingAmount) or defaultCrafts
    if defaultCrafts and defaultCrafts > 0 then
        return crafts * (defaultStartingAmount / defaultCrafts)
    end
    return crafts
end

local function AddGraphLeafEntry(leafMap, leafOrder, entry)
    local key = entry.itemID or entry.name or tostring(#leafOrder + 1)
    local existing = leafMap[key]
    if existing then
        existing.qty = (existing.qty or 0) + (entry.qty or 0)
        existing.excludeFromCost = existing.excludeFromCost or entry.excludeFromCost
        existing.skipDerivation = existing.skipDerivation or entry.skipDerivation
        existing.scanItemIDs = MergeUniqueItemIDs(existing.scanItemIDs, entry.scanItemIDs)
        return
    end
    leafMap[key] = {
        itemID = entry.itemID,
        itemIDs = entry.itemIDs,
        name = entry.name,
        qty = entry.qty or 0,
        excludeFromCost = entry.excludeFromCost and true or false,
        skipDerivation = entry.skipDerivation and true or false,
        scanItemIDs = entry.scanItemIDs,
    }
    leafOrder[#leafOrder + 1] = key
end

local function ResolveGraphNodeEntry(ctx, node, qtyForPricing)
    if not node then
        return nil
    end

    local inputPolicy = GetInputRankPolicy(ctx.strat)
    local displayName = GetItemLabel(node)
    local itemIDs = GetResolvedReagentItemIDs(node, ctx.pdb)
    local itemID = nil
    local scanItemIDs = nil

    if node.cheapestOf then
        local resolved = ResolveCheapestAlternative(node, ctx, qtyForPricing)
        scanItemIDs = GetCheapestAlternativeScanIDs(node, ctx)
        if resolved then
            itemIDs = resolved.itemIDs or itemIDs
            itemID = resolved.itemID
            displayName = resolved.name or displayName
        end
    end

    if not itemID then
        itemID = PickItemID(itemIDs, ctx.patchTag, inputPolicy)
    end

    return {
        itemID = itemID,
        itemIDs = itemIDs,
        name = displayName,
        scanItemIDs = scanItemIDs or (itemID and { itemID } or itemIDs),
        excludeFromCost = node.excludeFromCost and true or false,
        skipDerivation = node.skipDerivation and true or false,
    }
end

local function GetProducerCandidateResolvedOutputID(candidate, patchTag)
    if not candidate or not candidate.stratID or not (GAM.Importer and GAM.Importer.GetStratByID) then
        return nil, nil, nil
    end

    local strat = GAM.Importer.GetStratByID(candidate.stratID)
    if not strat then
        return nil, nil, nil
    end

    local active = candidate.variantKey and GetRecipeViewForVariantKey(strat, candidate.variantKey) or BuildRecipeView(strat)
    local output = active and ((active.outputs and active.outputs[1]) or active.output) or nil
    if not output then
        return strat, active, nil
    end

    local outputPolicy = nil
    if candidate.variantKey == "lowest" or candidate.variantKey == "highest" then
        outputPolicy = candidate.variantKey
    end

    return strat, active, PickItemID(GetResolvedItemIDs(output, patchTag), patchTag, outputPolicy)
end

local function GetExpectedOutputPerCraft(strat, active, opts)
    if not strat or not active then
        return nil
    end
    local output = (active.outputs and active.outputs[1]) or active.output
    if not output then
        return nil
    end
    local profile = BuildProfileContext(strat, opts or GetOpts())
    local qtyRaw = ComputeOutputQuantity(
        output, strat, profile.profileDef, profile.statDenom, profile.statMCp, profile.statMCm_tot, 1, 1)
    return qtyRaw
end

local function FindProducerMatch(ctx, itemID, state)
    if not ctx.chainActive or not itemID or not (GAM.Importer and GAM.Importer.GetProducerCandidates) then
        return nil
    end

    local candidates = GAM.Importer.GetProducerCandidates(itemID, ctx.patchTag)
    for _, candidate in ipairs(candidates or {}) do
        local strat, active, candidateOutputID = GetProducerCandidateResolvedOutputID(candidate, ctx.patchTag)
        if strat and active and candidateOutputID == itemID and type(active.outputs) == "table" and #active.outputs == 1 then
            local key = tostring(candidate.stratID) .. "::" .. tostring(candidate.variantKey or "base")
            if not (state.activeProducerKeys and state.activeProducerKeys[key]) then
                return {
                    key = key,
                    strat = strat,
                    active = active,
                    outputItemID = candidateOutputID,
                }
            end
        end
    end

    return nil
end

local function BuildGraphLeafPlan(ctx, mode)
    local leafMap = {}
    local leafOrder = {}
    local state = {
        activeProducerKeys = {},
    }
    local rootOrder, rootMap = BuildMergedReagentMap(ctx, "none")

    local function AddResolvedLeaf(resolvedEntry, qty)
        if not resolvedEntry or not qty or qty <= 0 then
            return
        end
        AddGraphLeafEntry(leafMap, leafOrder, {
            itemID = resolvedEntry.itemID,
            itemIDs = resolvedEntry.itemIDs,
            name = resolvedEntry.name,
            qty = qty,
            excludeFromCost = resolvedEntry.excludeFromCost,
            skipDerivation = resolvedEntry.skipDerivation,
            scanItemIDs = resolvedEntry.scanItemIDs,
        })
    end

    local function ExpandNode(node, requiredQty, depth)
        if not node or not requiredQty or requiredQty <= 0 or depth > 12 then
            return
        end

        local qtyForPricing = math.max(1, QuantizeRequiredAmount(requiredQty, "nearest"))
        local resolvedEntry = ResolveGraphNodeEntry(ctx, node, qtyForPricing)
        if not resolvedEntry then
            return
        end

        if resolvedEntry.excludeFromCost then
            if mode == "execution" and depth == 0 then
                AddResolvedLeaf(resolvedEntry, requiredQty)
            end
            return
        end

        if resolvedEntry.skipDerivation or not ctx.chainActive then
            AddResolvedLeaf(resolvedEntry, requiredQty)
            return
        end

        local producer = FindProducerMatch(ctx, resolvedEntry.itemID, state)
        if not producer then
            AddResolvedLeaf(resolvedEntry, requiredQty)
            return
        end

        local expectedOutputPerCraft = GetExpectedOutputPerCraft(producer.strat, producer.active, ctx.opts)
        if not expectedOutputPerCraft or expectedOutputPerCraft <= 0 then
            AddResolvedLeaf(resolvedEntry, requiredQty)
            return
        end

        local craftsNeeded = requiredQty / expectedOutputPerCraft
        if mode == "execution" then
            craftsNeeded = QuantizeRequiredAmount(craftsNeeded, "ceil")
        end
        if not craftsNeeded or craftsNeeded <= 0 then
            return
        end

        local scaledStartingAmt = GetScaledStartingAmountForCrafts(producer.active, craftsNeeded)
        state.activeProducerKeys[producer.key] = true
        for _, reagent in ipairs(producer.active.reagents or {}) do
            local childQty = GetRequiredReagentAmountRaw(reagent, scaledStartingAmt, craftsNeeded)
            ExpandNode(reagent, childQty, depth + 1)
        end
        state.activeProducerKeys[producer.key] = nil
    end

    for _, key in ipairs(rootOrder) do
        local rootEntry = rootMap[key]
        ExpandNode(rootEntry, rootEntry.qty or 0, 0)
    end

    return {
        leafMap = leafMap,
        leafOrder = leafOrder,
    }
end

local function BuildGraphLeafMetrics(ctx, mode)
    local plan = BuildGraphLeafPlan(ctx, mode)
    local results = {}
    local totalCostToBuy = 0
    local totalCostRequired = 0
    local hasStale = false
    local missingPrices = {}
    local quantityMode = (mode == "economic") and "none" or "nearest"
    local inputPolicy = GetInputRankPolicy(ctx.strat)

    for _, key in ipairs(plan.leafOrder or {}) do
        local entry = plan.leafMap[key]
        local requiredRaw = tonumber(entry and entry.qty) or 0
        local required = QuantizeRequiredAmount(requiredRaw, quantityMode)
        local itemID = entry and entry.itemID or nil
        local itemIDs = (entry and entry.itemIDs) or (itemID and { itemID }) or {}
        local price, stale = Pricing.GetEffectivePriceForItem({
            itemIDs = itemID and { itemID } or itemIDs,
            name = entry and entry.name or nil,
            skipDerivation = entry and entry.skipDerivation or false,
            rankPolicyOverride = inputPolicy,
        }, ctx.patchTag, (mode == "economic") and requiredRaw or required)
        local userHave = CountOwnedReagentItems(itemID, itemIDs)
        local needToBuy = math.max(0, required - userHave)
        local totalCost = (entry and entry.excludeFromCost) and 0
            or ((needToBuy == 0) and 0 or (price and (needToBuy * price) or nil))
        local totalCostFull = (entry and entry.excludeFromCost) and 0
            or (price and (required * price) or nil)
        local missingPrice = (entry and not entry.excludeFromCost) and (needToBuy > 0) and not price

        if stale then
            hasStale = true
        end

        if missingPrice then
            missingPrices[#missingPrices + 1] = entry.name
        else
            totalCostToBuy = totalCostToBuy + (totalCost or 0)
            totalCostRequired = totalCostRequired + (totalCostFull or 0)
        end

        results[#results + 1] = {
            name = entry.name,
            itemID = itemID,
            sourceItemIDs = itemIDs,
            scanItemIDs = entry.scanItemIDs or (itemID and { itemID } or itemIDs),
            unitPrice = price,
            required = required,
            requiredRaw = requiredRaw,
            have = userHave,
            needToBuy = needToBuy,
            totalCost = totalCost,
            totalCostFull = totalCostFull,
            isStale = stale,
            missingPrice = missingPrice,
            excludeFromCost = entry.excludeFromCost and true or false,
            skipDerivation = entry.skipDerivation and true or false,
        }
    end

    return {
        reagentResults = results,
        totalCostToBuy = totalCostToBuy,
        totalCostRequired = totalCostRequired,
        hasStale = hasStale,
        missingPrices = missingPrices,
    }
end

local function BuildBreakdownNodePricing(ctx, resolvedEntry, requiredRaw, required)
    local inputPolicy = GetInputRankPolicy(ctx.strat)
    local itemID = resolvedEntry and resolvedEntry.itemID or nil
    local itemIDs = (resolvedEntry and resolvedEntry.itemIDs) or (itemID and { itemID }) or {}
    local have = CountOwnedReagentItems(itemID, itemIDs)
    local needToBuy = math.max(0, required - have)

    if resolvedEntry and resolvedEntry.excludeFromCost then
        return {
            have = have,
            needToBuy = needToBuy,
            effectiveUnitPrice = nil,
            effectiveTotalCostToBuy = 0,
            effectiveTotalCostFull = 0,
            effectiveMissingPrice = false,
            effectiveIsStale = false,
            directUnitPrice = nil,
            directTotalCostToBuy = 0,
            directTotalCostFull = 0,
            directMissingPrice = false,
            directIsStale = false,
        }
    end

    local effectivePrice, effectiveStale = Pricing.GetEffectivePriceForItem({
        itemIDs = itemID and { itemID } or itemIDs,
        name = resolvedEntry and resolvedEntry.name or nil,
        skipDerivation = resolvedEntry and resolvedEntry.skipDerivation or false,
        rankPolicyOverride = inputPolicy,
    }, ctx.patchTag, requiredRaw)

    local directPrice, directStale = GetDirectEffectivePriceForItem({
        itemIDs = itemID and { itemID } or itemIDs,
        name = resolvedEntry and resolvedEntry.name or nil,
        rankPolicyOverride = inputPolicy,
    }, ctx.patchTag, requiredRaw)

    local function BuildTotals(price)
        local totalCostToBuy = (needToBuy == 0) and 0 or (price and (needToBuy * price) or nil)
        local totalCostFull = price and (requiredRaw * price) or nil
        local missingPrice = (needToBuy > 0) and not price
        return totalCostToBuy, totalCostFull, missingPrice
    end

    local effectiveTotalCostToBuy, effectiveTotalCostFull, effectiveMissingPrice = BuildTotals(effectivePrice)
    local directTotalCostToBuy, directTotalCostFull, directMissingPrice = BuildTotals(directPrice)

    return {
        have = have,
        needToBuy = needToBuy,
        effectiveUnitPrice = effectivePrice,
        effectiveTotalCostToBuy = effectiveTotalCostToBuy,
        effectiveTotalCostFull = effectiveTotalCostFull,
        effectiveMissingPrice = effectiveMissingPrice,
        effectiveIsStale = effectiveStale,
        directUnitPrice = directPrice,
        directTotalCostToBuy = directTotalCostToBuy,
        directTotalCostFull = directTotalCostFull,
        directMissingPrice = directMissingPrice,
        directIsStale = directStale,
    }
end

local function BuildVIBreakdownData(ctx, metrics)
    local rootOrder, rootMap = BuildMergedReagentMap(ctx, "none")
    local state = {
        activeProducerKeys = {},
        entries = {},
        rootIndices = {},
    }
    local usedFallbackRows = false

    local function AddEntry(entry)
        entry.index = #state.entries + 1
        state.entries[#state.entries + 1] = entry
        return entry
    end

    local function ExpandNode(node, requiredQtyRaw, depth, parentIndex, inheritedExcluded)
        if not node or not requiredQtyRaw or requiredQtyRaw <= 0 or depth > 12 then
            return {
                chainTotalCostFull = 0,
                chainTotalCostToBuy = 0,
                hasMissingPrice = false,
                hasStale = false,
            }, nil
        end

        local qtyForPricing = math.max(1, QuantizeRequiredAmount(requiredQtyRaw, "nearest"))
        local resolvedEntry = ResolveGraphNodeEntry(ctx, node, qtyForPricing)
        if not resolvedEntry then
            return {
                chainTotalCostFull = 0,
                chainTotalCostToBuy = 0,
                hasMissingPrice = false,
                hasStale = false,
            }, nil
        end

        if inheritedExcluded then
            resolvedEntry.excludeFromCost = true
        end

        local required = QuantizeRequiredAmount(requiredQtyRaw, "nearest")
        local pricingData = BuildBreakdownNodePricing(ctx, resolvedEntry, requiredQtyRaw, required)
        local producer = nil
        local expectedOutputPerCraft = nil
        local stopReason = nil

        if resolvedEntry.excludeFromCost then
            stopReason = "exclude_from_cost"
        elseif resolvedEntry.skipDerivation then
            stopReason = "skip_derivation"
        elseif not ctx.chainActive then
            stopReason = "vi_disabled"
        else
            producer = FindProducerMatch(ctx, resolvedEntry.itemID, state)
            if not producer then
                stopReason = "no_producer"
            else
                expectedOutputPerCraft = GetExpectedOutputPerCraft(producer.strat, producer.active, ctx.opts)
                if not expectedOutputPerCraft or expectedOutputPerCraft <= 0 then
                    producer = nil
                    stopReason = "invalid_output"
                end
            end
        end

        local entry = AddEntry({
            parentIndex = parentIndex,
            childIndices = {},
            depth = depth,
            kind = producer and "craft" or "leaf",
            name = resolvedEntry.name,
            itemID = resolvedEntry.itemID,
            itemIDs = resolvedEntry.itemIDs,
            scanItemIDs = resolvedEntry.scanItemIDs,
            requiredRaw = requiredQtyRaw,
            required = required,
            have = pricingData.have,
            needToBuy = pricingData.needToBuy,
            excludeFromCost = resolvedEntry.excludeFromCost and true or false,
            skipDerivation = resolvedEntry.skipDerivation and true or false,
            stopReason = stopReason,
            effectiveUnitPrice = pricingData.effectiveUnitPrice,
            effectiveTotalCostToBuy = pricingData.effectiveTotalCostToBuy,
            effectiveTotalCostFull = pricingData.effectiveTotalCostFull,
            effectiveMissingPrice = pricingData.effectiveMissingPrice,
            directUnitPrice = pricingData.directUnitPrice,
            directTotalCostToBuy = pricingData.directTotalCostToBuy,
            directTotalCostFull = pricingData.directTotalCostFull,
            directMissingPrice = pricingData.directMissingPrice,
            hasStale = pricingData.effectiveIsStale or pricingData.directIsStale,
        })

        if producer then
            local craftsEconomic = requiredQtyRaw / expectedOutputPerCraft
            local craftsExecution = QuantizeRequiredAmount(craftsEconomic, "ceil")
            entry.producerStratID = producer.strat.id
            entry.producerStratName = producer.strat.stratName
            entry.profileKey = producer.strat.formulaProfile
            entry.expectedOutputPerCraft = expectedOutputPerCraft
            entry.craftsEconomic = craftsEconomic
            entry.craftsExecution = craftsExecution

            local chainTotalCostFull = 0
            local chainTotalCostToBuy = 0
            local hasMissingPrice = false
            local hasStale = entry.hasStale
            local scaledStartingAmt = GetScaledStartingAmountForCrafts(producer.active, craftsEconomic)

            state.activeProducerKeys[producer.key] = true
            for _, reagent in ipairs(producer.active.reagents or {}) do
                local childQty = GetRequiredReagentAmountRaw(reagent, scaledStartingAmt, craftsEconomic)
                local childSummary, childIndex = ExpandNode(reagent, childQty, depth + 1, entry.index, resolvedEntry.excludeFromCost)
                if childIndex then
                    entry.childIndices[#entry.childIndices + 1] = childIndex
                end
                if childSummary then
                    chainTotalCostFull = chainTotalCostFull + (childSummary.chainTotalCostFull or 0)
                    chainTotalCostToBuy = chainTotalCostToBuy + (childSummary.chainTotalCostToBuy or 0)
                    hasMissingPrice = hasMissingPrice or childSummary.hasMissingPrice
                    hasStale = hasStale or childSummary.hasStale
                end
            end
            state.activeProducerKeys[producer.key] = nil

            entry.chainTotalCostFull = chainTotalCostFull
            entry.chainTotalCostToBuy = chainTotalCostToBuy
            entry.hasMissingPrice = hasMissingPrice
            entry.hasStale = hasStale

            return {
                chainTotalCostFull = chainTotalCostFull,
                chainTotalCostToBuy = chainTotalCostToBuy,
                hasMissingPrice = hasMissingPrice,
                hasStale = hasStale,
            }, entry.index
        end

        entry.chainTotalCostFull = pricingData.effectiveTotalCostFull or 0
        entry.chainTotalCostToBuy = pricingData.effectiveTotalCostToBuy or 0
        entry.hasMissingPrice = pricingData.effectiveMissingPrice

        return {
            chainTotalCostFull = pricingData.effectiveTotalCostFull or 0,
            chainTotalCostToBuy = pricingData.effectiveTotalCostToBuy or 0,
            hasMissingPrice = pricingData.effectiveMissingPrice,
            hasStale = entry.hasStale,
        }, entry.index
    end

    for _, key in ipairs(rootOrder) do
        local rootEntry = rootMap[key]
        local _, rootIndex = ExpandNode(rootEntry, rootEntry.qty or 0, 0, nil, false)
        if rootIndex then
            state.rootIndices[#state.rootIndices + 1] = rootIndex
        end
    end

    if #state.entries == 0 and metrics and type(metrics.reagents) == "table" then
        for _, reagent in ipairs(metrics.reagents) do
            local itemIDs = reagent.sourceItemIDs or (reagent.itemID and { reagent.itemID }) or {}
            local scanItemIDs = reagent.scanItemIDs or (reagent.itemID and { reagent.itemID }) or itemIDs
            local entry = AddEntry({
                parentIndex = nil,
                childIndices = {},
                depth = 0,
                kind = "leaf",
                name = reagent.name,
                itemID = reagent.itemID,
                itemIDs = itemIDs,
                scanItemIDs = scanItemIDs,
                requiredRaw = reagent.requiredRaw or reagent.required or 0,
                required = reagent.required or 0,
                have = reagent.have,
                needToBuy = reagent.needToBuy,
                excludeFromCost = reagent.excludeFromCost and true or false,
                skipDerivation = reagent.skipDerivation and true or false,
                stopReason = "fallback_metrics",
                effectiveUnitPrice = reagent.unitPrice,
                effectiveTotalCostToBuy = reagent.totalCost,
                effectiveTotalCostFull = reagent.totalCostFull,
                effectiveMissingPrice = reagent.missingPrice and true or false,
                directUnitPrice = reagent.unitPrice,
                directTotalCostToBuy = reagent.totalCost,
                directTotalCostFull = reagent.totalCostFull,
                directMissingPrice = reagent.missingPrice and true or false,
                hasStale = reagent.isStale and true or false,
                chainTotalCostFull = reagent.totalCostFull or 0,
                chainTotalCostToBuy = reagent.totalCost or 0,
                hasMissingPrice = reagent.missingPrice and true or false,
            })
            state.rootIndices[#state.rootIndices + 1] = entry.index
        end
        usedFallbackRows = (#state.entries > 0)
    end

    return {
        stratID = ctx.strat and ctx.strat.id or nil,
        stratName = ctx.strat and ctx.strat.stratName or nil,
        patchTag = ctx.patchTag,
        chainActive = ctx.chainActive and true or false,
        crafts = ctx.crafts,
        startingAmount = ctx.startingAmt,
        totalCostFull = metrics and metrics.totalCostFull or nil,
        totalCostToBuy = metrics and metrics.totalCostToBuy or nil,
        netRevenue = metrics and metrics.netRevenue or nil,
        profit = metrics and metrics.profit or nil,
        roi = metrics and metrics.roi or nil,
        breakEvenSell = metrics and metrics.breakEvenSell or nil,
        rootIndices = state.rootIndices,
        entries = state.entries,
        usedFallbackRows = usedFallbackRows,
    }
end

BuildEconomicReagentMetrics = function(ctx)
    return BuildGraphLeafMetrics(ctx, "economic")
end

BuildReagentMetrics = function(ctx)
    local mergedOrder, mergedMap = BuildMergedReagentMap(ctx)
    local reagentResults = {}
    local totalCostToBuy = 0
    local totalCostRequired = 0
    local hasStale = false
    local selectionNotes = {}
    local missingPrices = {}
    local inputPolicy = GetInputRankPolicy(ctx.strat)

    for _, key in ipairs(mergedOrder) do
        local entry = mergedMap[key]
        local entryIDs = entry.itemIDs
        local required = math.floor(entry.qty + 0.5)
        local excludeFromCost = entry.excludeFromCost and true or false
        local itemID, price, stale, displayName

        if entry.cheapestOf then
            local resolved = ResolveCheapestAlternative(entry, ctx, required)
            if resolved then
                entryIDs = resolved.itemIDs
                itemID = resolved.itemID
                displayName = resolved.name
                price = resolved.price
                stale = resolved.stale
            else
                entryIDs = entry.itemIDs
                itemID = PickItemID(entryIDs, ctx.patchTag, inputPolicy)
                displayName = entry.name
                price = nil
                stale = false
            end
        else
            itemID      = PickItemID(entryIDs, ctx.patchTag, inputPolicy)
            displayName = entry.name
            local itemProxy = {
                itemIDs = itemID and { itemID } or entryIDs,
                name = entry.name,
                skipDerivation = entry.skipDerivation and true or false,
                rankPolicyOverride = inputPolicy,
            }
            price, stale = Pricing.GetEffectivePriceForItem(itemProxy, ctx.patchTag, required)
        end

        local userHave = CountOwnedReagentItems(itemID, entryIDs)
        local needToBuy = math.max(0, required - userHave)
        if stale then
            hasStale = true
        end

        local totalCost = excludeFromCost and 0 or ((needToBuy == 0) and 0 or (price and (needToBuy * price) or nil))
        local totalCostFull = excludeFromCost and 0 or (price and (required * price) or nil)
        local missingPrice = (not excludeFromCost) and (needToBuy > 0) and not price

        if missingPrice then
            missingPrices[#missingPrices + 1] = displayName
        else
            totalCostToBuy = totalCostToBuy + (totalCost or 0)
            totalCostRequired = totalCostRequired + (totalCostFull or 0)
        end

        reagentResults[#reagentResults + 1] = {
            name = displayName,
            itemID = itemID,
            sourceItemIDs = entryIDs,
            scanItemIDs = GetCheapestAlternativeScanIDs(entry, ctx),
            unitPrice = price,
            required = required,
            have = userHave,
            needToBuy = needToBuy,
            totalCost = totalCost,
            totalCostFull = totalCostFull,
            isStale = stale,
            missingPrice = missingPrice,
            excludeFromCost = excludeFromCost,
            skipDerivation = entry.skipDerivation and true or false,
            selectedAlternativeName = entry.cheapestOf and displayName or nil,
            selectedAlternativeItemID = entry.cheapestOf and itemID or nil,
            selectionMode = entry.cheapestOf and "cheapest_pool" or nil,
        }

        if entry.cheapestOf and displayName then
            selectionNotes[#selectionNotes + 1] = displayName
        end
    end

    return {
        reagentResults = reagentResults,
        totalCostToBuy = totalCostToBuy,
        totalCostRequired = totalCostRequired,
        hasStale = hasStale,
        selectionNotes = selectionNotes,
        missingPrices = missingPrices,
    }
end

BuildDisplayReagentMetrics = function(ctx, modelReagents)
    return BuildGraphLeafMetrics(ctx, "execution")
end

local function GetPrimaryOutput(ctx)
    return (ctx.active.outputs and ctx.active.outputs[1]) or ctx.active.output or {}
end

local function GetPrimaryInputQuality(ctx)
    if ctx.strat.qualityPolicy == "force_q1_inputs" then
        return 1
    end
    if ctx.strat.qualityPolicy == "force_q2_inputs" then
        return 2
    end
    if not (ctx.active.reagents and #ctx.active.reagents > 0) then
        return nil
    end

    local firstReagent = ctx.active.reagents[1]
    local pickedID = nil
    if firstReagent.cheapestOf then
        local required = QuantizeRequiredAmount(
            GetRequiredReagentAmountRaw(firstReagent, ctx.startingAmt, ctx.crafts),
            "nearest")
        local resolved = ResolveCheapestAlternative(firstReagent, ctx, required)
        pickedID = resolved and resolved.itemID or nil
    else
        local reagentIDs = GetResolvedReagentItemIDs(firstReagent, ctx.pdb)
        if not (reagentIDs and #reagentIDs > 0) then
            return nil
        end
        pickedID = PickItemID(reagentIDs, ctx.patchTag, GetInputRankPolicy(ctx.strat))
    end
    local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    if api and pickedID then
        local quality = api(pickedID)
        if quality and quality > 0 then
            return quality
        end
    end
    return nil
end

local function BuildSingleOutputMetrics(ctx, primaryOut, outputQtyRaw, outPrice, outMissingPrice, missingPrices)
    local netRevenue = nil
    if outMissingPrice then
        missingPrices[#missingPrices + 1] = GetItemLabel(primaryOut) or "Output"
    elseif outPrice and outputQtyRaw > 0 then
        netRevenue = math.floor(outputQtyRaw * outPrice * (1 - ctx.ahCut))
    end
    return nil, netRevenue
end

local function GetOutputPriceQty(ctx)
    local fillQty = tonumber(ctx and ctx.fillQty) or GAM.C.DEFAULT_FILL_QTY
    return math.max(1, math.floor(fillQty + 0.5))
end

local function BuildMultiOutputMetrics(ctx, outputPreferredQuality, missingPrices)
    local totalRevenue = 0
    local allHavePrices = true
    local outResults = {}
    local hasStale = false
    local priceQty = GetOutputPriceQty(ctx)

    for _, outputDef in ipairs(ctx.active.outputs) do
        local outputQtyRaw, outputQty = ComputeOutputQuantity(
            outputDef, ctx.strat, ctx.profileDef, ctx.statDenom, ctx.statMCp, ctx.statMCm_tot, ctx.startingAmt, ctx.crafts)
        local price, stale = GetOutputPriceForItem(outputDef, ctx.patchTag, outputPreferredQuality, priceQty)
        if stale then
            hasStale = true
        end
        local netRevenue = price and math.floor(outputQtyRaw * price * (1 - ctx.ahCut)) or nil
        if not price then
            allHavePrices = false
            missingPrices[#missingPrices + 1] = GetItemLabel(outputDef) or "Output"
        else
            totalRevenue = totalRevenue + netRevenue
        end
        outResults[#outResults + 1] = {
            name = GetItemLabel(outputDef),
            itemID = GetOutputItemIDForDisplay(outputDef, ctx.patchTag, outputPreferredQuality),
            unitPrice = price,
            expectedQty = outputQty,
            expectedQtyRaw = outputQtyRaw,
            netRevenue = netRevenue,
            isStale = stale,
            missingPrice = not price,
        }
    end

    return outResults, allHavePrices and totalRevenue or nil, hasStale
end

BuildOutputMetrics = function(ctx)
    local primaryOut = GetPrimaryOutput(ctx)
    if not primaryOut.name and not primaryOut.itemRef and not primaryOut.itemIDs then
        if GAM.Log and GAM.Log.Warn then
            GAM.Log.Warn("Pricing: strat '%s' missing active output", tostring(ctx.strat.stratName or ctx.strat.id or "?"))
        end
        return nil
    end

    local missingPrices = {}
    local outputQtyRaw, outputQty = ComputeOutputQuantity(
        primaryOut, ctx.strat, ctx.profileDef, ctx.statDenom, ctx.statMCp, ctx.statMCm_tot, ctx.startingAmt, ctx.crafts)
    local primaryQuality = GetPrimaryInputQuality(ctx)
    local outputPreferredQuality = (ctx.strat.outputQualityMode == "match_input") and primaryQuality or nil
    local priceQty = GetOutputPriceQty(ctx)
    local outPrice, outStale = GetOutputPriceForItem(primaryOut, ctx.patchTag, outputPreferredQuality, priceQty)
    local outMissingPrice = not outPrice
    local isMultiOutput = ctx.active.outputs and #ctx.active.outputs > 1
    local outputs, netRevenue, extraStale

    if isMultiOutput then
        outputs, netRevenue, extraStale = BuildMultiOutputMetrics(ctx, outputPreferredQuality, missingPrices)
    else
        outputs, netRevenue = BuildSingleOutputMetrics(ctx, primaryOut, outputQtyRaw, outPrice, outMissingPrice, missingPrices)
        extraStale = false
    end

    local outItemID = GetOutputItemIDForDisplay(primaryOut, ctx.patchTag, outputPreferredQuality)

    return {
        primaryOut = primaryOut,
        outputQtyRaw = outputQtyRaw,
        output = {
            name = GetItemLabel(primaryOut),
            itemID = outItemID,
            unitPrice = outPrice,
            expectedQty = outputQty,
            expectedQtyRaw = outputQtyRaw,
            netRevenue = (not isMultiOutput) and netRevenue or nil,
            isStale = outStale,
            missingPrice = outMissingPrice,
        },
        outputs = outputs,
        netRevenue = netRevenue,
        hasStale = outStale or extraStale,
        isMultiOutput = isMultiOutput,
        missingPrices = missingPrices,
    }
end

BuildFinalMetrics = function(ctx, reagentData, outputData)
    local displayReagentData = BuildDisplayReagentMetrics(ctx, reagentData.reagentResults)
    -- Keep top-level costReagents for analyzers/debugging, but drive economics from
    -- the VI graph so recursive craft costs and AH-intermediate fallback stay in sync.
    local economicReagentData = BuildEconomicReagentMetrics(ctx)
    local profit = nil
    local roi = nil
    local breakEven = nil
    local missingPrices = {}
    local seenMissing = {}

    local function AddMissingNames(names)
        for _, name in ipairs(names or {}) do
            if name and not seenMissing[name] then
                seenMissing[name] = true
                missingPrices[#missingPrices + 1] = name
            end
        end
    end

    AddMissingNames(economicReagentData.missingPrices)
    AddMissingNames(displayReagentData.missingPrices)
    AddMissingNames(outputData.missingPrices)

    if outputData.netRevenue and #missingPrices == 0 then
        profit = outputData.netRevenue - economicReagentData.totalCostRequired
        if economicReagentData.totalCostRequired > 0 then
            roi = (profit / economicReagentData.totalCostRequired) * 100
        end
    end

    if economicReagentData.totalCostRequired > 0 and outputData.outputQtyRaw > 0 and not outputData.isMultiOutput then
        breakEven = economicReagentData.totalCostRequired / (outputData.outputQtyRaw * (1 - ctx.ahCut))
    end

    return {
        startingAmount = ctx.startingAmt,
        crafts = ctx.crafts,
        reagents = displayReagentData.reagentResults,
        costReagents = reagentData.reagentResults,
        output = outputData.output,
        outputs = outputData.outputs,
        totalCostToBuy = economicReagentData.totalCostToBuy,
        totalCostFull = economicReagentData.totalCostRequired,
        netRevenue = outputData.netRevenue,
        profit = profit,
        roi = roi,
        breakEvenSell = breakEven,
        missingPrices = missingPrices,
        hasStale = reagentData.hasStale or economicReagentData.hasStale or displayReagentData.hasStale or outputData.hasStale,
        selectionNotes = reagentData.selectionNotes,
    }
end

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
    if not active or type(active.reagents) ~= "table" or #active.reagents == 0 then
        if GAM.Log and GAM.Log.Warn then
            GAM.Log.Warn("Pricing: strat '%s' missing active reagents", tostring(strat.stratName or strat.id or "?"))
        end
        return nil
    end

    local ctx = BuildCalcContext(strat, active, patchTag, craftQty, opts, pdb, ahCut)
    local reagentData = BuildReagentMetrics(ctx)
    local outputData = BuildOutputMetrics(ctx)
    if not outputData then
        return nil
    end

    return BuildFinalMetrics(ctx, reagentData, outputData)
end

function Pricing.GetVIBreakdownData(strat, patchTag, metrics)
    if not strat then
        return nil
    end

    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local opts = GetOpts()
    local ahCut = opts.ahCut or GAM.C.AH_CUT
    local pdb = GetPatchDB(patchTag)
    local active = GetActiveRecipeView(strat)
    if not active then
        return nil
    end

    local ctx = BuildCalcContext(strat, active, patchTag, 1, opts, pdb, ahCut)
    if not metrics then
        metrics = Pricing.CalculateStratMetrics(strat, patchTag, 1)
    end
    return BuildVIBreakdownData(ctx, metrics)
end

local function ShallowCloneArrayOfTables(source)
    local out = {}
    for i, entry in ipairs(source or {}) do
        local cloned = {}
        for key, value in pairs(entry) do
            if type(value) == "table" then
                local inner = {}
                for innerKey, innerValue in pairs(value) do
                    if type(innerValue) == "table" then
                        local nested = {}
                        for nestedKey, nestedValue in pairs(innerValue) do
                            nested[nestedKey] = nestedValue
                        end
                        inner[innerKey] = nested
                    else
                        inner[innerKey] = innerValue
                    end
                end
                cloned[key] = inner
            else
                cloned[key] = value
            end
        end
        out[i] = cloned
    end
    return out
end

function Pricing.GetCrushingAnalyzerData(strat, patchTag, baseMetrics)
    if not strat or strat.id ~= "jewelcrafting__crushing__midnight_1" then
        return nil
    end

    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local active = GetActiveRecipeView(strat)
    local reagent = active and active.reagents and active.reagents[1] or nil
    if not (reagent and reagent.cheapestOf and #reagent.cheapestOf > 0) then
        return nil
    end

    local currentMetrics = baseMetrics or Pricing.CalculateStratMetrics(strat, patchTag)
    local selectedItemID = currentMetrics
        and currentMetrics.costReagents
        and currentMetrics.costReagents[1]
        and currentMetrics.costReagents[1].selectedAlternativeItemID
        or nil
    local selectedCrafts = currentMetrics and currentMetrics.crafts or nil
    local selectedStartingAmount = currentMetrics and currentMetrics.startingAmount or nil
    local pdb = GetPatchDB(patchTag)
    local inputPolicy = GetInputRankPolicy(strat)
    local entries = {}

    for _, alt in ipairs(reagent.cheapestOf) do
        local altIDs = alt.itemIDs
        if (not altIDs or #altIDs == 0) and alt.itemRef then
            altIDs = pdb.rankGroups[alt.itemRef] or {}
        end

        local tempStrat = {}
        for key, value in pairs(strat) do
            tempStrat[key] = value
        end
        tempStrat.rankVariants = nil
        tempStrat.reagents = ShallowCloneArrayOfTables(active.reagents)
        tempStrat.outputs = ShallowCloneArrayOfTables(active.outputs or {})
        tempStrat.output = tempStrat.outputs[1] or active.output or (active.outputs and active.outputs[1]) or strat.output
        if selectedStartingAmount and selectedStartingAmount > 0 then
            tempStrat.defaultStartingAmount = selectedStartingAmount
        end
        if selectedCrafts and selectedCrafts > 0 then
            tempStrat.defaultCrafts = selectedCrafts
        end

        local altReagent = tempStrat.reagents[1] or {}
        altReagent.cheapestOf = nil
        altReagent.itemRef = alt.itemRef or altReagent.itemRef
        altReagent.name = alt.itemRef or altReagent.name
        altReagent.itemIDs = altIDs or {}
        tempStrat.reagents[1] = altReagent

        local altMetrics = Pricing.CalculateStratMetrics(tempStrat, patchTag)
        local pickedAltID = PickItemID(altIDs, patchTag, inputPolicy)
        local altCostReagent = altMetrics and altMetrics.costReagents and altMetrics.costReagents[1] or nil
        entries[#entries + 1] = {
            name = alt.itemRef or altReagent.name or "?",
            itemID = pickedAltID,
            unitPrice = altCostReagent and altCostReagent.unitPrice or nil,
            profit = altMetrics and altMetrics.profit or nil,
            roi = altMetrics and altMetrics.roi or nil,
            breakEvenSell = altMetrics and altMetrics.breakEvenSell or nil,
            isSelected = selectedItemID and pickedAltID and (selectedItemID == pickedAltID) or false,
        }
    end

    return {
        selectedItemID = selectedItemID,
        crafts = selectedCrafts,
        startingAmount = selectedStartingAmount,
        entries = entries,
    }
end

-- GetBestStrategy(patchTag, profFilter) — returns (strat, profit, roi) for the top
-- scoring strategy that clears both minimum thresholds. Returns nil,nil,nil if none qualify.
-- Score = profit × √ROI; capital tie-break on full craft cost.
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
                local p, r = m.profit, m.roi
                if p and p >= minProfit and r and r >= minROI then
                    local score, cost = GetStrategyScoreFromMetrics(m)
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
    -- Store only price + timestamp; raw order-book arrays are no longer persisted
    -- to SavedVariables (they caused progressive lag after multiple scans).
    cache[itemID] = {
        price = price,
        ts    = time(),
    }
    GAM.Log.Debug("Stored price: itemID=%s price=%s", tostring(itemID), tostring(price))
end

-- StoreRaw / GetRawCache — no-ops. Raw AH listings are kept in session-only
-- commodityCache/itemCache in AHScan.lua; they are no longer written to the
-- persistent DB to prevent SavedVariables bloat across scans.
function Pricing.StoreRaw(itemID, sortedRaw)   end
function Pricing.GetRawCache(itemID) return nil end

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
