-- GoldAdvisorMidnight/PricingPriceSource.lua
-- Item identity, rank policy, price-source precedence, and output price selection.
-- Module: GAM.PricingPriceSource

local ADDON_NAME, GAM = ...
local PriceSource = {}
GAM.PricingPriceSource = PriceSource

function PriceSource.Install(Pricing, deps)
    assert(type(Pricing) == "table", "Pricing facade is required")
    assert(type(deps) == "table", "PricingPriceSource dependencies are required")
    local GetOpts = assert(deps.GetOpts, "GetOpts dependency is required")
    local GetPatchDB = assert(deps.GetPatchDB, "GetPatchDB dependency is required")
    local GetItemLabel = assert(deps.GetItemLabel, "GetItemLabel dependency is required")
    local RequestItemData = assert(deps.RequestItemData, "RequestItemData dependency is required")
    local GetActiveRecipeView = assert(deps.GetActiveRecipeView, "GetActiveRecipeView dependency is required")
    local Derivation = deps.Derivation or {}
    local GetInputRankPolicy, PickItemID

local function CallItemInfoAPI(api, itemID)
    if type(api) ~= "function" or not itemID then return nil end
    -- Retail's ItemInfo APIs expect the structured payload. Keep the numeric
    -- retry for older clients and lightweight test/API shims.
    local ok, value = pcall(api, { itemID = itemID })
    if ok and value ~= nil then return value end
    ok, value = pcall(api, itemID)
    return ok and value or nil
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

local function GetExplicitItemQualityRank(itemID)
    if not itemID or itemID == 0 then return nil end
    RequestItemData(itemID)
    local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    local q = tonumber(CallItemInfoAPI(api, itemID))
    if q and q > 0 then return q end
    if q == 0 then return 1 end
    return nil
end

local function GetPositiveReagentQualityRank(itemID)
    if not itemID or itemID == 0 then return nil end
    RequestItemData(itemID)
    local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    local quality = tonumber(CallItemInfoAPI(api, itemID))
    return quality and quality > 0 and quality or nil
end

-- Crafted outputs and recipe reagents use different Blizzard quality APIs.
-- Prefer the crafted-output APIs, then use the reagent-quality API for ranked
-- processing outputs such as pigments, gems, and prospecting byproducts.  A
-- reagent-quality result of 0 means "not a ranked reagent", not output rank 1,
-- so only a positive result is safe as the fallback.
local function GetExplicitOutputQualityRank(itemID)
    if not itemID or itemID == 0 then return nil end
    RequestItemData(itemID)
    local infoAPI = C_TradeSkillUI and C_TradeSkillUI.GetItemCraftedQualityInfo
    if type(infoAPI) == "function" then
        local info = CallItemInfoAPI(infoAPI, itemID)
        local quality = type(info) == "table" and tonumber(info.quality) or nil
        if quality and quality > 0 then return quality end
    end
    local legacyAPI = C_TradeSkillUI and C_TradeSkillUI.GetItemCraftedQualityByItemInfo
    if type(legacyAPI) == "function" then
        local quality = tonumber(CallItemInfoAPI(legacyAPI, itemID))
        if quality and quality > 0 then return quality end
    end
    return GetPositiveReagentQualityRank(itemID)
end

local function GetRecipeQualityItemIDs(recipeID)
    recipeID = tonumber(recipeID)
    local api = C_TradeSkillUI and C_TradeSkillUI.GetRecipeQualityItemIDs
    if not recipeID or type(api) ~= "function" then return nil end
    local ok, itemIDs = pcall(api, recipeID)
    if ok and type(itemIDs) == "table" and #itemIDs > 0 then
        return itemIDs
    end
    return nil
end

local function GetRecipeQualityIDs(recipeID)
    recipeID = tonumber(recipeID)
    if not recipeID then return nil end
    local api = C_TradeSkillUI and C_TradeSkillUI.GetQualitiesForRecipe
    if type(api) == "function" then
        local ok, qualityIDs = pcall(api, recipeID)
        if ok and type(qualityIDs) == "table" and #qualityIDs > 0 then
            return qualityIDs
        end
    end
    local infoAPI = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo
    if type(infoAPI) == "function" then
        local ok, info = pcall(infoAPI, recipeID)
        local qualityIDs = ok and type(info) == "table" and info.qualityIDs or nil
        if type(qualityIDs) == "table" and #qualityIDs > 0 then
            return qualityIDs
        end
    end
    return nil
end

-- GetRecipeOutputItemData's overrideQualityID argument is the one-based crafted
-- rank (1, 2, ...). GetQualitiesForRecipe returns a different set of opaque IDs
-- and must not be passed here. Blizzard also returns GetRecipeQualityItemIDs in
-- crafted-rank order, which gives us a stable fallback when output data is not
-- available (for example while recipe data is still loading).
local function GetRecipeOutputItemIDForQuality(recipeID, quality)
    recipeID = tonumber(recipeID)
    quality = tonumber(quality)
    local api = C_TradeSkillUI and C_TradeSkillUI.GetRecipeOutputItemData
    if recipeID and quality and quality >= 1 and type(api) == "function" then
        local ok, outputInfo = pcall(api, recipeID, {}, nil, quality)
        local itemID = ok and type(outputInfo) == "table" and tonumber(outputInfo.itemID) or nil
        if itemID and itemID > 0 then return itemID end
    end
    local itemIDs = GetRecipeQualityItemIDs(recipeID)
    local itemID = itemIDs and tonumber(itemIDs[quality]) or nil
    return itemID and itemID > 0 and itemID or nil
end

local function ContainsItemID(itemIDs, candidateID)
    candidateID = tonumber(candidateID)
    if not candidateID then return false end
    for _, itemID in ipairs(itemIDs or {}) do
        if tonumber(itemID) == candidateID then return true end
    end
    return false
end

local function GetOutputQualityForItem(itemID, recipeID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local recipeQualityIDs = GetRecipeQualityItemIDs(recipeID)
    for quality, recipeItemID in ipairs(recipeQualityIDs or {}) do
        if tonumber(recipeItemID) == itemID then return quality end
    end
    local qualityCount = #(recipeQualityIDs or {})
    if qualityCount == 0 then qualityCount = #(GetRecipeQualityIDs(recipeID) or {}) end
    for quality = 1, qualityCount do
        if GetRecipeOutputItemIDForQuality(recipeID, quality) == itemID then
            return quality
        end
    end
    return GetExplicitOutputQualityRank(itemID)
end

local function GetBoundaryOutputQuality(item, patchTag, recipeID, highest)
    local itemIDs = GetResolvedItemIDs(item, patchTag)
    if not itemIDs or #itemIDs == 0 then return nil end
    local boundary = nil
    local recipeQualityIDs = GetRecipeQualityItemIDs(recipeID)
    for quality, recipeItemID in ipairs(recipeQualityIDs or {}) do
        if ContainsItemID(itemIDs, recipeItemID)
                and (not boundary or (highest and quality > boundary) or (not highest and quality < boundary)) then
            boundary = quality
        end
    end
    if boundary then return boundary end
    local qualityCount = #(GetRecipeQualityIDs(recipeID) or {})
    for quality = 1, qualityCount do
        local recipeItemID = GetRecipeOutputItemIDForQuality(recipeID, quality)
        if ContainsItemID(itemIDs, recipeItemID)
                and (not boundary or (highest and quality > boundary) or (not highest and quality < boundary)) then
            boundary = quality
        end
    end
    if boundary then return boundary end
    for _, itemID in ipairs(itemIDs) do
        local quality = GetExplicitOutputQualityRank(itemID)
        if quality and (not boundary
                or (highest and quality > boundary)
                or (not highest and quality < boundary)) then
            boundary = quality
        end
    end
    if boundary then return boundary end
    return #itemIDs > 1 and (highest and #itemIDs or 1) or nil
end

local function GetLowestOutputQuality(item, patchTag, recipeID)
    return GetBoundaryOutputQuality(item, patchTag, recipeID, false)
end

local function GetHighestOutputQuality(item, patchTag, recipeID)
    return GetBoundaryOutputQuality(item, patchTag, recipeID, true)
end

local function GetItemName(itemID)
    return select(1, GetItemInfo(itemID))
end

local function FindItemIDByQuality(itemIDs, desiredQuality, recipeID)
    if not desiredQuality or not itemIDs then return nil end
    -- Processing recipes can expose several ranked reagent outputs under one
    -- recipe ID. Their per-item reagent rank is more specific than a recipe's
    -- single crafted-output mapping, so honor it first when it is available.
    for _, id in ipairs(itemIDs) do
        if GetPositiveReagentQualityRank(id) == desiredQuality then
            return id
        end
    end
    local recipeQualityIDs = GetRecipeQualityItemIDs(recipeID)
    local recipeItemID = recipeQualityIDs and recipeQualityIDs[desiredQuality]
    if recipeItemID and ContainsItemID(itemIDs, recipeItemID) then
        return recipeItemID
    end
    local exactOutputItemID = GetRecipeOutputItemIDForQuality(recipeID, desiredQuality)
    if exactOutputItemID and ContainsItemID(itemIDs, exactOutputItemID) then
        return exactOutputItemID
    end
    local anyKnown = false
    for _, id in ipairs(itemIDs) do
        local q = GetExplicitOutputQualityRank(id)
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

local function GetRankPolicyDesiredQuality(itemIDs, patchTag, recipeID)
    if not itemIDs or #itemIDs <= 1 then return nil end
    local policy = GetOpts().rankPolicy or "lowest"
    local firstExactQuality, lastExactQuality = nil, nil
    local recipeQualityIDs = GetRecipeQualityItemIDs(recipeID)
    for quality, recipeItemID in ipairs(recipeQualityIDs or {}) do
        if ContainsItemID(itemIDs, recipeItemID) then
            firstExactQuality = firstExactQuality or quality
            lastExactQuality = quality
        end
    end
    if firstExactQuality then
        return (policy == "highest" or policy == "optimal") and lastExactQuality or firstExactQuality
    end
    local qualityCount = #(GetRecipeQualityIDs(recipeID) or {})
    if qualityCount > 0 then
        local firstQuality, lastQuality = nil, nil
        for quality = 1, qualityCount do
            if ContainsItemID(itemIDs, GetRecipeOutputItemIDForQuality(recipeID, quality)) then
                firstQuality = firstQuality or quality
                lastQuality = quality
            end
        end
        if firstQuality then
            return (policy == "highest" or policy == "optimal") and lastQuality or firstQuality
        end
    end
    local bestQ = nil
    for _, id in ipairs(itemIDs) do
        local q = GetExplicitOutputQualityRank(id)
        if q then
            if not bestQ then
                bestQ = q
            elseif (policy == "highest" or policy == "optimal") and q > bestQ then
                bestQ = q
            elseif policy ~= "highest" and policy ~= "optimal" and q < bestQ then
                bestQ = q
            end
        end
    end
    if not bestQ then
        return (policy == "highest" or policy == "optimal") and #itemIDs or 1
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
        local q = tonumber(CallItemInfoAPI(api, id))
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
        return (policy == "highest" or policy == "optimal") and sorted[#sorted].id or sorted[1].id
    end

    -- All uncached: fall back to array position
    return (policy == "highest" or policy == "optimal") and itemIDs[#itemIDs] or itemIDs[1]
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
function Pricing.GetUnitPrice(itemID, preferMinimum)
    if not itemID then return nil end
    local cache = GAM:GetRealmCache()
    local entry = cache[itemID]
    if not entry then return nil end
    local price = (preferMinimum and entry.minPrice) or entry.price
    if not price then return nil end
    -- Stale check
    local staleThresh = GAM.C.PRICE_STALE_SECONDS
    if (time() - (entry.ts or 0)) > staleThresh then
        return price, true  -- price, isStale
    end
    return price, false
end

-- GetEffectivePrice(itemID, patchTag, qty) → price in copper, or nil
-- Priority: override > observed/static vendor price > CraftSim > live AH depth > AH cache avg
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

    -- 2. Vendor price. Use the current character's last observed merchant
    -- quote (including reputation/racial discounts), then the static fallback.
    local vendorPrice = GAM.VendorPrices and GAM.VendorPrices.GetPrice
        and GAM.VendorPrices.GetPrice(itemID)
        or (GAM.C.VENDOR_PRICES and GAM.C.VENDOR_PRICES[itemID])
    if vendorPrice then
        return vendorPrice, false
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
    local cachedPrice, stale = Pricing.GetUnitPrice(itemID, targetQty and targetQty <= 1)
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

local function GetDesiredOutputQuality(item, patchTag, preferredQuality, recipeID)
    if preferredQuality then
        return preferredQuality
    end
    local ids = GetResolvedItemIDs(item, patchTag)
    return GetRankPolicyDesiredQuality(ids, patchTag, recipeID)
end

local function GetOutputPriceForItem(item, patchTag, preferredQuality, qty, recipeID)
    if not item then return nil, false end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local ids = GetResolvedItemIDs(item, patchTag)
    if not ids or #ids == 0 then return nil, false end

    local desiredQuality = GetDesiredOutputQuality(item, patchTag, preferredQuality, recipeID)
    local exactID = FindItemIDByQuality(ids, desiredQuality, recipeID)
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

local function GetOutputItemIDForDisplay(item, patchTag, preferredQuality, recipeID)
    if not item then return nil end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local ids = GetResolvedItemIDs(item, patchTag)
    if not ids or #ids == 0 then return nil end
    local desiredQuality = GetDesiredOutputQuality(item, patchTag, preferredQuality, recipeID)
    local exactID = FindItemIDByQuality(ids, desiredQuality, recipeID)
    if exactID then
        return exactID
    end
    return PickItemID(ids, patchTag)
end

    return {
        GetResolvedItemIDs = GetResolvedItemIDs,
        GetInputRankPolicy = GetInputRankPolicy,
        PickItemID = PickItemID,
        GetOutputQualityForItem = GetOutputQualityForItem,
        GetLowestOutputQuality = GetLowestOutputQuality,
        GetHighestOutputQuality = GetHighestOutputQuality,
        GetDirectEffectivePriceForItem = GetDirectEffectivePriceForItem,
        GetOutputPriceForItem = GetOutputPriceForItem,
        GetOutputItemIDForDisplay = GetOutputItemIDForDisplay,
    }
end
