-- GoldAdvisorMidnight/Pricing.lua
-- Pricing engine: price lookup, effective price, strat metrics.
-- Module: GAM.Pricing

local ADDON_NAME, GAM = ...
local Pricing = {}
GAM.Pricing = Pricing
local Derivation = GAM.PricingDerivation or {}
local BuildCalcContext, BuildMergedReagentMap, BuildReagentMetrics, BuildDisplayReagentMetrics
local GetOutputBaseYield, GetOutputQuantityBasis, ComputeOutputQuantity, BuildProfileContext
local GetV2ExpectedOutputPerCraft
local PrepareOptimizedRecipeView

-- ===== Internal helpers =====

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
    local model = GAM.StrategyModel
    return model and model.ResolveRecipeView and model.ResolveRecipeView(strat, variant) or nil
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
    local model = GAM.StrategyModel
    if model and model.ResolveActiveRecipeView then
        return model.ResolveActiveRecipeView(strat, policy)
    end
    local variantView = GetRecipeViewForVariantKey(strat, policy)
    return variantView or BuildRecipeView(strat)
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
    local displayedReagents = metrics
        and (metrics.shoppingReagents or metrics.reagents)
        or nil
    if displayedReagents and #displayedReagents > 0 then
        for _, r in ipairs(displayedReagents) do
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

local PriceSource = assert(
    GAM.PricingPriceSource,
    "PricingPriceSource must load before Pricing")
local priceSource = PriceSource.Install(Pricing, {
    GetOpts = GetOpts,
    GetPatchDB = GetPatchDB,
    GetItemLabel = GetItemLabel,
    RequestItemData = RequestItemData,
    GetActiveRecipeView = GetActiveRecipeView,
    Derivation = Derivation,
})
local GetResolvedItemIDs = priceSource.GetResolvedItemIDs
GetInputRankPolicy = priceSource.GetInputRankPolicy
PickItemID = priceSource.PickItemID
local GetOutputQualityForItem = priceSource.GetOutputQualityForItem
local GetLowestOutputQuality = priceSource.GetLowestOutputQuality
local GetHighestOutputQuality = priceSource.GetHighestOutputQuality
local GetDirectEffectivePriceForItem = priceSource.GetDirectEffectivePriceForItem
local GetOutputPriceForItem = priceSource.GetOutputPriceForItem

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


-- ===== Stat scaling (Workbook-driven formula profiles) =====

-- ===== Chain expansion for shopping list =====

-- ===== Core calculation =====

local Recipe = assert(GAM.PricingRecipe, "PricingRecipe must load before Pricing")
local recipe = Recipe.Install(Pricing, {
    GetFormulaProfiles = GetFormulaProfiles,
    GetOpts = GetOpts,
    GetItemLabel = GetItemLabel,
    GetInputRankPolicy = GetInputRankPolicy,
    PickItemID = PickItemID,
})
GetOutputBaseYield = recipe.GetOutputBaseYield
GetOutputQuantityBasis = recipe.GetOutputQuantityBasis
ComputeOutputQuantity = recipe.ComputeOutputQuantity
BuildProfileContext = recipe.BuildProfileContext
BuildCalcContext = recipe.BuildCalcContext
local GetResolvedReagentItemIDs = recipe.GetResolvedReagentItemIDs
local GetRequiredReagentAmountRaw = recipe.GetRequiredReagentAmountRaw
local QuantizeRequiredAmount = recipe.QuantizeRequiredAmount
BuildMergedReagentMap = recipe.BuildMergedReagentMap
local ResolveCheapestAlternative = recipe.ResolveCheapestAlternative

local VerticalIntegration = assert(
    GAM.PricingVerticalIntegration,
    "PricingVerticalIntegration must load before Pricing")
local verticalIntegration = VerticalIntegration.Install(Pricing, {
    GetOpts = GetOpts,
    GetPatchDB = GetPatchDB,
    GetItemLabel = GetItemLabel,
    GetActiveRecipeView = GetActiveRecipeView,
    GetInputRankPolicy = GetInputRankPolicy,
    PickItemID = PickItemID,
    GetResolvedItemIDs = GetResolvedItemIDs,
    GetOutputQualityForItem = GetOutputQualityForItem,
    GetLowestOutputQuality = GetLowestOutputQuality,
    GetHighestOutputQuality = GetHighestOutputQuality,
    GetResolvedReagentItemIDs = GetResolvedReagentItemIDs,
    GetRequiredReagentAmountRaw = GetRequiredReagentAmountRaw,
    QuantizeRequiredAmount = QuantizeRequiredAmount,
    BuildCalcContext = BuildCalcContext,
    BuildMergedReagentMap = BuildMergedReagentMap,
    ResolveCheapestAlternative = ResolveCheapestAlternative,
    GetDirectEffectivePriceForItem = GetDirectEffectivePriceForItem,
    ComputeOutputQuantity = ComputeOutputQuantity,
    BuildProfileContext = BuildProfileContext,
    BuildRecipeView = BuildRecipeView,
    GetRecipeViewForVariantKey = GetRecipeViewForVariantKey,
    GetV2ExpectedOutputPerCraft = function(...) return GetV2ExpectedOutputPerCraft(...) end,
    Derivation = Derivation,
})
PrepareOptimizedRecipeView = verticalIntegration.PrepareOptimizedRecipeView
local GetScaledStartingAmountForCrafts = verticalIntegration.GetScaledStartingAmountForCrafts
local ResolveGraphNodeEntry = verticalIntegration.ResolveGraphNodeEntry
local FindProducerMatch = verticalIntegration.FindProducerMatch
local BuildVIBreakdownData = verticalIntegration.BuildVIBreakdownData
BuildReagentMetrics = verticalIntegration.BuildReagentMetrics
BuildDisplayReagentMetrics = verticalIntegration.BuildDisplayReagentMetrics

local function GetPrimaryOutput(ctx)
    return (ctx.active.outputs and ctx.active.outputs[1]) or ctx.active.output or {}
end

local function GetPrimaryInputQuality(ctx)
    if ctx and ctx.reachableOutputQuality and GetInputRankPolicy(ctx.strat) == "optimal" then
        return ctx.reachableOutputQuality
    end
    if ctx and ctx.targetOutputQuality and GetInputRankPolicy(ctx.strat) == "optimal" then
        return ctx.targetOutputQuality
    end
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
    local pickedID
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

local function GetOutputPriceQty(_ctx)
    -- Output revenue is a sell-side quote. Buying through multiple listings is
    -- appropriate for reagent acquisition, but averaging upward through the
    -- order book can wildly overvalue a thin commodity output. Price outputs
    -- at the current lowest listing; keep quantity-aware depth on inputs.
    return 1
end

if GAM.PricingEngine and type(GAM.PricingEngine.Install) == "function" then
    GAM.PricingEngine.Install(Pricing, {
        GetOpts = GetOpts,
        GetPatchDB = GetPatchDB,
        GetFormulaProfiles = GetFormulaProfiles,
        GetItemLabel = GetItemLabel,
        GetActiveRecipeView = GetActiveRecipeView,
        BuildCalcContext = BuildCalcContext,
        BuildReagentMetrics = BuildReagentMetrics,
        BuildDisplayReagentMetrics = BuildDisplayReagentMetrics,
        GetOutputBaseYield = GetOutputBaseYield,
        GetOutputQuantityBasis = GetOutputQuantityBasis,
        GetPrimaryOutput = GetPrimaryOutput,
        GetPrimaryInputQuality = GetPrimaryInputQuality,
        GetOutputPriceQty = GetOutputPriceQty,
        GetOutputPriceForItem = GetOutputPriceForItem,
        GetInputRankPolicy = GetInputRankPolicy,
        QuantizeRequiredAmount = QuantizeRequiredAmount,
        ResolveGraphNodeEntry = ResolveGraphNodeEntry,
        FindProducerMatch = FindProducerMatch,
        GetScaledStartingAmountForCrafts = GetScaledStartingAmountForCrafts,
        GetRequiredReagentAmountRaw = GetRequiredReagentAmountRaw,
        GetDirectEffectivePriceForItem = GetDirectEffectivePriceForItem,
        PrepareOptimizedRecipeView = PrepareOptimizedRecipeView,
    })
end

GetV2ExpectedOutputPerCraft = Pricing.GetV2ExpectedOutputPerCraft

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

    if not metrics then
        metrics = Pricing.CalculateStratMetricsV2(strat, patchTag, 1)
    end

    local requestedFinalCrafts = metrics
        and tonumber(metrics.recommendedCrafts or metrics.crafts) or nil
    local finalCraftCapacity, finalCapacityReason = nil, nil
    local tracker = GAM.CooldownTracker
    if tracker and type(tracker.GetImmediateCraftCapacity) == "function" then
        finalCraftCapacity, finalCapacityReason =
            tracker.GetImmediateCraftCapacity(strat.recipeID)
        finalCraftCapacity = tonumber(finalCraftCapacity)
        if finalCraftCapacity ~= nil then
            finalCraftCapacity = math.max(0, math.floor(finalCraftCapacity))
        end
    end

    local runtimeOverrides = nil
    local capacityLimited = finalCraftCapacity ~= nil
        and requestedFinalCrafts ~= nil
        and finalCraftCapacity < requestedFinalCrafts
    if capacityLimited then
        runtimeOverrides = { crafts = finalCraftCapacity }
        local immediateMetrics = Pricing.CalculateStratMetricsV2(
            strat, patchTag, 1, runtimeOverrides)
        if immediateMetrics then
            -- Raw engine metrics do not carry the facade's conservative action
            -- count, so pin it to the live limit for the breakdown plan.
            immediateMetrics.recommendedCrafts = finalCraftCapacity
            immediateMetrics.effectiveCrafts = finalCraftCapacity
            metrics = immediateMetrics
        else
            capacityLimited = false
            runtimeOverrides = nil
        end
    end
    -- The canonical calculation may replace the rank-policy recipe with a
    -- verified Best Mix. Reapply that exact plan before rebuilding the VI root
    -- so its material tree cannot drift back to the original/all-high inputs.
    local rankMixPlan = metrics and (metrics.rankMixPlan
        or (metrics.diagnostics and metrics.diagnostics.rankMixPlan)) or nil
    local optimizer = GAM.ReagentMixOptimizer
    if rankMixPlan and optimizer and type(optimizer.ApplyPlan) == "function" then
        local optimizedActive, applyReason = optimizer.ApplyPlan(active, rankMixPlan)
        if optimizedActive then
            active = optimizedActive
        elseif GAM.Log and GAM.Log.Warn then
            GAM.Log.Warn("VI breakdown: could not apply Best Mix plan for %s (%s)",
                tostring(strat.stratName or strat.id or "?"), tostring(applyReason or "unknown"))
        end
    end

    local ctx = BuildCalcContext(
        strat, active, patchTag, 1, opts, pdb, ahCut, runtimeOverrides)
    if metrics and (metrics.model == "v2" or metrics.engine == "commodity_expected_value") then
        ctx.v2StatResolutions = {}
        ctx.v2ExecutionPlan = true
        ctx.v2EconomicChoices = metrics.economicChoices
            or (metrics.diagnostics and metrics.diagnostics.economicChoices)
            or {}
    end
    local breakdown = BuildVIBreakdownData(ctx, metrics)
    if breakdown and capacityLimited then
        breakdown.capacityLimited = true
        breakdown.finalCraftCapacity = finalCraftCapacity
        breakdown.finalCapacityReason = finalCapacityReason
        breakdown.requestedFinalCraftsExecution = requestedFinalCrafts
    end
    return breakdown
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

function Pricing.GetCrushingAnalyzerData(strat, patchTag, baseMetrics, calculateMetrics)
    if not strat or strat.id ~= "jewelcrafting__crushing__midnight_1" then
        return nil
    end

    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local active = GetActiveRecipeView(strat)
    local reagent = active and active.reagents and active.reagents[1] or nil
    if not (reagent and reagent.cheapestOf and #reagent.cheapestOf > 0) then
        return nil
    end

    local function CalculateAnalyzerMetrics(strategy)
        if calculateMetrics then
            return calculateMetrics(strategy, patchTag)
        end
        return Pricing.CalculateStratMetricsV2(strategy, patchTag)
    end

    local currentMetrics = baseMetrics or CalculateAnalyzerMetrics(strat)
    local currentRecipeReagents = currentMetrics
        and (currentMetrics.recipeReagents or currentMetrics.costReagents)
        or nil
    local selectedItemID = currentMetrics
        and currentRecipeReagents
        and currentRecipeReagents[1]
        and currentRecipeReagents[1].selectedAlternativeItemID
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

        local altMetrics = CalculateAnalyzerMetrics(tempStrat)
        local pickedAltID = PickItemID(altIDs, patchTag, inputPolicy)
        local altRecipeReagents = altMetrics
            and (altMetrics.recipeReagents or altMetrics.costReagents)
            or nil
        local altCostReagent = altRecipeReagents and altRecipeReagents[1] or nil
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

-- StorePrice(itemID, price, minPrice) — called by AHScan after scan
function Pricing.StorePrice(itemID, price, minPrice)
    if not itemID or not price then return end
    local cache = GAM:GetRealmCache()
    -- Store only price + timestamp; raw order-book arrays are no longer persisted
    -- to SavedVariables (they caused progressive lag after multiple scans).
    cache[itemID] = {
        price = price,
        minPrice = tonumber(minPrice) or price,
        ts    = time(),
    }
    GAM.Log.Debug("Stored price: itemID=%s price=%s", tostring(itemID), tostring(price))
end

-- StoreRaw / GetRawCache — no-ops. Raw AH listings are kept in session-only
-- commodity/item caches in AuctionHouseResults.lua; they are no longer written to the
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
