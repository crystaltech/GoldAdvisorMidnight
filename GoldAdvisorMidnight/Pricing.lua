-- GoldAdvisorMidnight/Pricing.lua
-- Pricing engine: price lookup, effective price, strat metrics.
-- Module: GAM.Pricing

local ADDON_NAME, GAM = ...
local Pricing = {}
GAM.Pricing = Pricing
local Derivation = GAM.PricingDerivation or {}
local BuildCalcContext, BuildMergedReagentMap, BuildReagentMetrics, BuildDisplayReagentMetrics, BuildOutputMetrics, BuildFinalMetrics

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

    -- AH price: preferred rank first, then remaining variants as fallback
    local price, isStale = Pricing.GetEffectivePrice(picked, patchTag, qty)
    if price then return price, isStale end
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

            local oil = GAM.Importer and GAM.Importer.GetStratByID
                and GAM.Importer.GetStratByID("enchanting__oil_of_dawn__midnight_1") or nil
            assert(oil and oil.outputs and oil.outputs[1], "oil of dawn strat unavailable")
            assert(#(oil.outputs[1].itemIDs or {}) >= 2,
                "Oil of Dawn must keep both ranked itemIDs for rank-policy output pricing")
            assert(oil.reagents and oil.reagents[3] and #(oil.reagents[3].itemIDs or {}) >= 2,
                "Oil of Dawn must keep both Eversinging Dust ranks for reagent rank-policy pricing")

            local priceByPolicy = GetOutputPriceForItem(oil.outputs[1], GAM.C.DEFAULT_PATCH, nil, 8295)
            assert(priceByPolicy == 0, string.format(
                "Oil of Dawn rank-policy resolution failed: got %s expected 0",
                tostring(priceByPolicy)))

            local priceByPreferredQuality = GetOutputPriceForItem(oil.outputs[1], GAM.C.DEFAULT_PATCH, 2, 8295)
            assert(priceByPreferredQuality == 0, string.format(
                "Oil of Dawn R2 rank resolution failed: got %s expected 0",
                tostring(priceByPreferredQuality)))
        end)
        C_TradeSkillUI = originalCraftUI
        GetItemInfo = originalGetItemInfo
        GAM.GetOptions = originalGetOptions
        Pricing.GetEffectivePrice = originalGetEffectivePrice
        assert(oilRankOK, oilRankErr)

        local phoenixDustOK, phoenixDustErr = pcall(function()
            local phoenix = GAM.Importer and GAM.Importer.GetStratByID
                and GAM.Importer.GetStratByID("enchanting__thalassian_phoenix_oil__midnight_1") or nil
            assert(phoenix and phoenix.reagents and phoenix.reagents[2], "thalassian phoenix oil strat unavailable")
            local dustIDs = phoenix.reagents[2].itemIDs or {}
            assert(#dustIDs == 1 and dustIDs[1] == 243599,
                string.format("Thalassian Phoenix Oil must pin Eversinging Dust to Q1: got %s",
                    table.concat(dustIDs, ",")))
        end)
        assert(phoenixDustOK, phoenixDustErr)

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
        local codifiedProfile = profiles["insc_codified"]
        assert(codifiedProfile, "insc_codified profile missing")

        -- leatherworking: live sheet Leatherworking!A18=32.0
        local lwProfile = profiles["leatherworking"]
        assert(lwProfile, "leatherworking profile missing")
        assert(math.abs((lwProfile.defaultMulti or 0) - 32.0) < 0.01,
            string.format("leatherworking defaultMulti parity fail: got %.3f expected 32.0", lwProfile.defaultMulti or 0))

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

                    local peerless = GAM.Importer.GetStratByID("inscription__peerless_missive__midnight_1")
                    assert(peerless, "peerless missive strat unavailable")
                    local peerlessMetrics = Pricing.CalculateStratMetrics(peerless, GAM.C.DEFAULT_PATCH, 10)
                    assertNear((peerlessMetrics and peerlessMetrics.output and peerlessMetrics.output.expectedQtyRaw) or 0, 10,
                        "peerless missive expected output must remain 1:1 per craft")
                    local displayQtyByID = {}
                    for _, row in ipairs(peerlessMetrics and peerlessMetrics.reagents or {}) do
                        if row.itemID then
                            displayQtyByID[row.itemID] = row.required
                        end
                    end
                    assert(displayQtyByID[236761] == 310, "peerless missive VI must plan 310 tranquility bloom for 10 crafts")
                    assert(displayQtyByID[236776] == 80, "peerless missive VI must plan 80 argentleaf for 10 crafts")
                    assert(displayQtyByID[236770] == 80, "peerless missive VI must plan 80 sanguithorn for 10 crafts")
                    assert(displayQtyByID[236778] == 80, "peerless missive VI must plan 80 mana lily for 10 crafts")

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
                    assertNear((strat.outputs and strat.outputs[1] and strat.outputs[1].baseYieldPerCraft) or 0, 3.0,
                        stratID .. " baseYieldPerCraft")
                    assertNear((strat.reagents and strat.reagents[1] and strat.reagents[1].qtyPerCraft) or 0, 5.0,
                        stratID .. " reagent qtyPerCraft")
                    assertNear((strat.reagents and strat.reagents[1] and strat.reagents[1].qtyPerStart) or 0, 1.0,
                        stratID .. " reagent qtyPerStart")
                end
                checkWorkbookParity(stratID, 1, 3557.031065, stratID .. " Engineering recycling")
            end

            local refulgent = GAM.Importer.GetStratByID("blacksmithing__refulgent_copper_ingot__midnight_1")
            if refulgent then
                assertNear(refulgent.defaultStartingAmount or 0, 5.0, "Refulgent Copper Ingot defaultStartingAmount")
                assertNear(refulgent.defaultCrafts or 0, 1.0, "Refulgent Copper Ingot defaultCrafts")
                assertNear((refulgent.rankVariants and refulgent.rankVariants.lowest
                    and refulgent.rankVariants.lowest.defaultStartingAmount) or 0,
                    5.0, "Refulgent Copper Ingot lowest defaultStartingAmount")
                assertNear((refulgent.rankVariants and refulgent.rankVariants.lowest
                    and refulgent.rankVariants.lowest.defaultCrafts) or 0,
                    1.0, "Refulgent Copper Ingot lowest defaultCrafts")
                assertNear((refulgent.rankVariants and refulgent.rankVariants.highest
                    and refulgent.rankVariants.highest.defaultStartingAmount) or 0,
                    5000.0, "Refulgent Copper Ingot highest defaultStartingAmount")
                assertNear((refulgent.rankVariants and refulgent.rankVariants.highest
                    and refulgent.rankVariants.highest.defaultCrafts) or 0,
                    1000.0, "Refulgent Copper Ingot highest defaultCrafts")
            end
            checkVariantWorkbookParity("blacksmithing__refulgent_copper_ingot__midnight_1", "lowest", 1, 1.428911961,
                "Blacksmithing Refulgent Copper Ingot Q1")
            checkVariantWorkbookParity("blacksmithing__refulgent_copper_ingot__midnight_1", "highest", 1, 1428.911961,
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
            checkVariantWorkbookParity("blacksmithing__gloaming_alloy__midnight_1", "lowest", 1, 142.8911961,
                "Blacksmithing Gloaming Alloy Q1")
            checkVariantWorkbookParity("blacksmithing__gloaming_alloy__midnight_1", "highest", 1, 142.8911961,
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
                    600.0, "Sterling Alloy highest defaultStartingAmount")
                assertNear((sterling.rankVariants and sterling.rankVariants.highest
                    and sterling.rankVariants.highest.defaultCrafts) or 0,
                    100.0, "Sterling Alloy highest defaultCrafts")
            end
            checkVariantWorkbookParity("blacksmithing__sterling_alloy__midnight_1", "lowest", 1, 1428.911961,
                "Blacksmithing Sterling Alloy Q1")
            checkVariantWorkbookParity("blacksmithing__sterling_alloy__midnight_1", "highest", 1, 142.8911961,
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
        statMCp = profileDef.multiKey and ((opts[profileDef.multiKey] or 0) / 100) or 0
        statRp = profileDef.resKey and ((opts[profileDef.resKey] or 0) / 100) or 0
        -- Node influence is temporarily disabled for spreadsheet parity.
        -- sheetMCm/sheetRs are fixed sheet-authoritative effective multipliers;
        -- node SavedVariables remain stored but are mathematically inert.
        statMCm_tot = profileDef.multiKey and (profileDef.sheetMCm or GAM.C.BASE_MCM) or 0
        statRs_tot = profileDef.sheetRs or GAM.C.BASE_RS
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
        -- chainActive: any mill/craft derivation path enabled; derived unit pricing
        -- stays active even when we keep the visible reagent list at sheet-level ingredients.
        chainActive = (opts.pigmentCostSource == "mill")
            or (opts.ingotCostSource == "craft")
            or (opts.boltCostSource == "craft"),
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

local function GetRequiredReagentAmount(reagent, startingAmt, crafts)
    local qtyPerCraft = reagent.qtyPerCraft
    local requiredRaw
    if qtyPerCraft ~= nil then
        requiredRaw = qtyPerCraft * crafts
    else
        local qtyPerStart = reagent.qtyPerStart or reagent.qtyMultiplier or 0
        requiredRaw = qtyPerStart * startingAmt
    end
    return math.floor(requiredRaw + 0.5)
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

BuildMergedReagentMap = function(ctx)
    local mergedMap = {}
    local mergedOrder = {}

    for _, reagent in ipairs(ctx.active.reagents or {}) do
        local required = GetRequiredReagentAmount(reagent, ctx.startingAmt, ctx.crafts)
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
    local displayResults = {}
    local hasStale = false
    local totalCostToBuy = 0
    local totalCostRequired = 0
    local missingPrices = {}
    local inputPolicy = GetInputRankPolicy(ctx.strat)
    local expansionDeps = {
        PickItemID = function(itemIDs, patchTag)
            return PickItemID(itemIDs, patchTag, inputPolicy)
        end,
    }

    local function AddDisplayEntry(displayMap, displayOrder, itemIDs, qty, fallbackName, excludeFromCost, skipDerivation)
        local pickedID = PickItemID(itemIDs, ctx.patchTag, inputPolicy) or (itemIDs and itemIDs[1]) or nil
        local key = pickedID or fallbackName or tostring(#displayOrder + 1)
        if displayMap[key] then
            displayMap[key].qty = displayMap[key].qty + (qty or 0)
            displayMap[key].excludeFromCost = displayMap[key].excludeFromCost or excludeFromCost
            displayMap[key].skipDerivation = displayMap[key].skipDerivation or skipDerivation
            return
        end
        displayMap[key] = {
            itemIDs = itemIDs,
            qty = qty or 0,
            name = fallbackName or (pickedID and GetItemName(pickedID)) or "?",
            excludeFromCost = excludeFromCost and true or false,
            skipDerivation = skipDerivation and true or false,
        }
        displayOrder[#displayOrder + 1] = key
    end

    local currentMap = {}
    local currentOrder = {}
    for _, reagentMetric in ipairs(modelReagents or {}) do
        local sourceIDs = reagentMetric.selectedAlternativeItemID and { reagentMetric.selectedAlternativeItemID }
            or reagentMetric.sourceItemIDs
            or (reagentMetric.itemID and { reagentMetric.itemID } or {})
        AddDisplayEntry(
            currentMap,
            currentOrder,
            sourceIDs,
            reagentMetric.required or 0,
            reagentMetric.selectedAlternativeName or reagentMetric.name,
            reagentMetric.excludeFromCost,
            reagentMetric.skipDerivation)
    end

    for _ = 1, 6 do
        local nextMap = {}
        local nextOrder = {}
        local expandedAny = false

        for _, key in ipairs(currentOrder) do
            local entry = currentMap[key]
            if entry.skipDerivation then
                AddDisplayEntry(nextMap, nextOrder, entry.itemIDs, entry.qty, entry.name, entry.excludeFromCost, true)
            else
                local expanded, didExpand = Derivation.ExpandReagentForDisplayOneLevel(entry.itemIDs, entry.qty, ctx.patchTag, expansionDeps)
                expandedAny = expandedAny or didExpand
                for _, expandedEntry in ipairs(expanded or {}) do
                    local entryIDs = expandedEntry.itemIDs or entry.itemIDs
                    local pickedID = PickItemID(entryIDs, ctx.patchTag, inputPolicy)
                    local fallbackName = expandedEntry.name or (pickedID and GetItemName(pickedID)) or entry.name
                    AddDisplayEntry(nextMap, nextOrder, entryIDs, expandedEntry.qty, fallbackName, entry.excludeFromCost, false)
                end
            end
        end

        currentMap = nextMap
        currentOrder = nextOrder
        if not expandedAny then
            break
        end
    end

    for _, key in ipairs(currentOrder) do
        local entry = currentMap[key]
        local itemID = PickItemID(entry.itemIDs, ctx.patchTag, inputPolicy)
        local required = math.floor((entry.qty or 0) + 0.5)
        local price, stale = Pricing.GetEffectivePriceForItem({
            itemIDs = itemID and { itemID } or entry.itemIDs,
            name = entry.name,
            skipDerivation = true,
            rankPolicyOverride = inputPolicy,
        }, ctx.patchTag, required)
        local userHave = CountOwnedReagentItems(itemID, entry.itemIDs)
        local needToBuy = math.max(0, required - userHave)
        local totalCost = entry.excludeFromCost and 0 or ((needToBuy == 0) and 0 or (price and (needToBuy * price) or nil))
        local totalCostFull = entry.excludeFromCost and 0 or (price and (required * price) or nil)
        local missingPrice = (not entry.excludeFromCost) and (needToBuy > 0) and not price

        if stale then
            hasStale = true
        end

        if missingPrice then
            missingPrices[#missingPrices + 1] = entry.name
        else
            totalCostToBuy = totalCostToBuy + (totalCost or 0)
            totalCostRequired = totalCostRequired + (totalCostFull or 0)
        end

        displayResults[#displayResults + 1] = {
            name = entry.name,
            itemID = itemID,
            scanItemIDs = itemID and { itemID } or entry.itemIDs,
            unitPrice = price,
            required = required,
            have = userHave,
            needToBuy = needToBuy,
            totalCost = totalCost,
            totalCostFull = totalCostFull,
            isStale = stale,
            missingPrice = missingPrice,
        }
    end

    return {
        reagentResults = displayResults,
        hasStale = hasStale,
        totalCostToBuy = totalCostToBuy,
        totalCostRequired = totalCostRequired,
        missingPrices = missingPrices,
    }
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
        local required = GetRequiredReagentAmount(firstReagent, ctx.startingAmt, ctx.crafts)
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

local function GetOutputSaleQty(outputQtyRaw, outputQtyRounded)
    if outputQtyRounded and outputQtyRounded > 0 then
        return outputQtyRounded
    end
    if outputQtyRaw and outputQtyRaw > 0 then
        return math.max(1, math.floor(outputQtyRaw + 0.5))
    end
    return 1
end

local function BuildMultiOutputMetrics(ctx, outputPreferredQuality, missingPrices)
    local totalRevenue = 0
    local allHavePrices = true
    local outResults = {}
    local hasStale = false

    for _, outputDef in ipairs(ctx.active.outputs) do
        local outputQtyRaw, outputQty = ComputeOutputQuantity(
            outputDef, ctx.strat, ctx.profileDef, ctx.statDenom, ctx.statMCp, ctx.statMCm_tot, ctx.startingAmt, ctx.crafts)
        local saleQty = GetOutputSaleQty(outputQtyRaw, outputQty)
        local price, stale = GetOutputPriceForItem(outputDef, ctx.patchTag, outputPreferredQuality, saleQty)
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
    local saleQty = GetOutputSaleQty(outputQtyRaw, outputQty)
    local outPrice, outStale = GetOutputPriceForItem(primaryOut, ctx.patchTag, outputPreferredQuality, saleQty)
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
    -- Rounded display rows are for shopping/execution planning. Expected-value
    -- economics must continue using the direct reagent model so break-even,
    -- profit, ROI, and summary costs are not inflated by whole-batch overbuy.
    local economicReagentData = reagentData
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
        hasStale = reagentData.hasStale or displayReagentData.hasStale or outputData.hasStale,
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
