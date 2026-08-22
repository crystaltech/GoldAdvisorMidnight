-- GoldAdvisorMidnight/PricingRecipe.lua
-- Formula context, recipe quantities, and direct reagent-plan construction.
-- Module: GAM.PricingRecipe

local ADDON_NAME, GAM = ...
local Recipe = {}
GAM.PricingRecipe = Recipe

function Recipe.Install(Pricing, deps)
    assert(type(Pricing) == "table", "Pricing facade is required")
    assert(type(deps) == "table", "PricingRecipe dependencies are required")
    local GetFormulaProfiles = assert(deps.GetFormulaProfiles, "GetFormulaProfiles dependency is required")
    local GetOpts = assert(deps.GetOpts, "GetOpts dependency is required")
    local GetItemLabel = assert(deps.GetItemLabel, "GetItemLabel dependency is required")
    local GetInputRankPolicy = assert(deps.GetInputRankPolicy, "GetInputRankPolicy dependency is required")
    local PickItemID = assert(deps.PickItemID, "PickItemID dependency is required")
    local GetOutputBaseYield, GetOutputQuantityBasis, ComputeOutputQuantity, BuildProfileContext
    local BuildCalcContext, BuildMergedReagentMap, ResolveCheapestAlternative

local function GetFormulaFactor(strat, profileDef, statDenom, statMCp, statMCm_tot)
    if strat.calcMode == "formula" and profileDef and statDenom then
        return (1 + statMCp * statMCm_tot) / statDenom
    end
    return 1
end

GetOutputBaseYield = function(outputDef)
    if not outputDef then
        return nil
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
    return baseYield
end

GetOutputQuantityBasis = function(outputDef, startingAmt, crafts)
    if outputDef and outputDef.baseYieldPerCraft ~= nil then
        return crafts
    end
    return startingAmt
end

ComputeOutputQuantity = function(outputDef, strat, profileDef, statDenom, statMCp, statMCm_tot, startingAmt, crafts)
    if not outputDef then
        return 0, 0
    end

    local baseYield = GetOutputBaseYield(outputDef)

    local factor = GetFormulaFactor(strat, profileDef, statDenom, statMCp, statMCm_tot)
    local qtyRaw = GetOutputQuantityBasis(outputDef, startingAmt, crafts) * (baseYield or 0) * factor

    return qtyRaw, math.floor(qtyRaw + 0.5)
end

BuildProfileContext = function(strat, opts)
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

BuildCalcContext = function(strat, active, patchTag, craftQty, opts, pdb, ahCut, runtimeOverrides)
    local profile = BuildProfileContext(strat, opts)
    local startingAmt, crafts = ResolveStartingAmountAndCrafts(strat, active, pdb, craftQty)

    -- Runtime planning constraints must not rewrite the user's persisted batch
    -- size. Scale both sides together so a craft-now plan can honor live recipe
    -- charges while the main estimate continues to show the requested batch.
    local runtimeCrafts = type(runtimeOverrides) == "table"
        and tonumber(runtimeOverrides.crafts) or nil
    if runtimeCrafts ~= nil then
        runtimeCrafts = math.max(0, runtimeCrafts)
        if crafts > 0 then
            startingAmt = startingAmt * (runtimeCrafts / crafts)
        else
            startingAmt = 0
        end
        crafts = runtimeCrafts
    end

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

    return {
        GetOutputBaseYield = GetOutputBaseYield,
        GetOutputQuantityBasis = GetOutputQuantityBasis,
        ComputeOutputQuantity = ComputeOutputQuantity,
        BuildProfileContext = BuildProfileContext,
        BuildCalcContext = BuildCalcContext,
        GetResolvedReagentItemIDs = GetResolvedReagentItemIDs,
        GetRequiredReagentAmountRaw = GetRequiredReagentAmountRaw,
        QuantizeRequiredAmount = QuantizeRequiredAmount,
        BuildMergedReagentMap = BuildMergedReagentMap,
        ResolveCheapestAlternative = ResolveCheapestAlternative,
    }
end
