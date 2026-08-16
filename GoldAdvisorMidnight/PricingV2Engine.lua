-- GoldAdvisorMidnight/PricingV2Engine.lua
-- V2 pricing orchestration. Pricing.lua owns shared helpers; this module wires
-- those helpers into the expected-value V2 engine and attaches public APIs.
-- Module: GAM.PricingV2Engine

local ADDON_NAME, GAM = ...
local Engine = {}
GAM.PricingV2Engine = Engine

-- Pure chooser kept outside the WoW pricing context so Auto gear behavior is
-- deterministic and independently regression-testable.
function Engine.SelectGearMetrics(multicraft, resourcefulness)
    if not multicraft then return resourcefulness, "resourcefulness" end
    if not resourcefulness then return multicraft, "multicraft" end
    if multicraft.profit ~= nil and resourcefulness.profit ~= nil then
        if resourcefulness.profit > multicraft.profit then
            return resourcefulness, "resourcefulness"
        end
        return multicraft, "multicraft"
    end
    local multicraftCost = tonumber(multicraft.expectedConsumedCostFull)
    local resourcefulnessCost = tonumber(resourcefulness.expectedConsumedCostFull)
    if multicraftCost and resourcefulnessCost and resourcefulnessCost < multicraftCost then
        return resourcefulness, "resourcefulness"
    end
    return multicraft, "multicraft"
end

function Engine.Install(Pricing, deps)
    if type(Pricing) ~= "table" or type(deps) ~= "table" then
        return false, "missing-dependencies"
    end

    local FormulaV2 = GAM.PricingV2Formula or {}

    local GetOpts = deps.GetOpts
    local GetPatchDB = deps.GetPatchDB
    local GetFormulaProfiles = deps.GetFormulaProfiles
    local GetItemLabel = deps.GetItemLabel
    local GetActiveRecipeView = deps.GetActiveRecipeView
    local BuildCalcContext = deps.BuildCalcContext
    local BuildReagentMetrics = deps.BuildReagentMetrics
    local BuildDisplayReagentMetrics = deps.BuildDisplayReagentMetrics
    local GetOutputBaseYield = deps.GetOutputBaseYield
    local GetOutputQuantityBasis = deps.GetOutputQuantityBasis
    local GetPrimaryOutput = deps.GetPrimaryOutput
    local GetPrimaryInputQuality = deps.GetPrimaryInputQuality
    local GetOutputPriceQty = deps.GetOutputPriceQty
    local GetOutputPriceForItem = deps.GetOutputPriceForItem
    local GetOutputItemIDForDisplay = deps.GetOutputItemIDForDisplay
    local GetInputRankPolicy = deps.GetInputRankPolicy
    local QuantizeRequiredAmount = deps.QuantizeRequiredAmount
    local ResolveGraphNodeEntry = deps.ResolveGraphNodeEntry
    local FindProducerMatch = deps.FindProducerMatch
    local GetScaledStartingAmountForCrafts = deps.GetScaledStartingAmountForCrafts
    local GetRequiredReagentAmountRaw = deps.GetRequiredReagentAmountRaw

    local function GetFormulaV2()
        FormulaV2 = GAM.PricingV2Formula or FormulaV2 or {}
        return FormulaV2
    end

    local function GetV2ProfileDef(strat)
        if not strat or strat.calcMode ~= "formula" or not strat.formulaProfile then
            return nil
        end
        return GetFormulaProfiles()[strat.formulaProfile]
    end

    local function GetV2StatPercent(opts, key)
        if not key then
            return 0
        end
        return math.max(0, (tonumber(opts and opts[key]) or 0) / 100)
    end

    local function GetV2NodeExtra(opts, key, defaultValue)
        local raw = nil
        if key and opts then
            raw = opts[key]
        end
        if raw == nil then
            raw = defaultValue or 0
        end
        local value = (tonumber(raw) or 0) / 100
        if value < 0 then
            return 0
        end
        return value
    end

    local function BuildV2FormulaInput(strat, opts, baseYield, crafts, requiredCraftCost, constants)
        local profileDef = GetV2ProfileDef(strat)
        local input = {
            crafts = crafts or 0,
            baseYield = baseYield or 0,
            requiredCraftCost = requiredCraftCost or 0,
            mcPercent = 0,
            resPercent = 0,
            mcExtra = 0,
            resExtra = 0,
            supportsMulticraft = false,
            supportsResourcefulness = false,
            statSource = "options",
        }

        if profileDef then
            input.supportsMulticraft = profileDef.multiKey ~= nil
            input.supportsResourcefulness = profileDef.resKey ~= nil
            input.mcPercent = GetV2StatPercent(opts, profileDef.multiKey)
            input.resPercent = GetV2StatPercent(opts, profileDef.resKey)
            input.mcExtra = input.supportsMulticraft
                and GetV2NodeExtra(opts, profileDef.mcNodeKey, profileDef.defaultMcNode)
                or 0
            input.resExtra = input.supportsResourcefulness
                and GetV2NodeExtra(opts, profileDef.rsNodeKey, profileDef.defaultRsNode)
                or 0
        end

        if constants and constants.multicraftConstants then
            input.multicraftConstants = constants.multicraftConstants
        end
        if constants and constants.resourcefulnessSaveBase then
            input.resourcefulnessSaveBase = constants.resourcefulnessSaveBase
        end

        return input, profileDef
    end

    local function GetV2PricingMode(strat, opts)
        local mode = tostring(opts and opts.v2PricingMode or ""):lower()
        if mode == "fixed_crafts" or mode == "fixedcrafts" or mode == "craftsim" then
            return "fixed_crafts"
        end
        if mode == "exhaust_materials" or mode == "exhaust" or mode == "exhaustmaterials"
                or mode == "fixed_input" or mode == "fixedinput" or mode == "spreadsheet" then
            return "exhaust_materials"
        end

        local defaultMode = tostring(
            (GAM.C and GAM.C.DEFAULT_V2_PRICING_MODE) or "exhaust_materials"):lower()
        if defaultMode == "fixed_crafts" then
            return "fixed_crafts"
        end
        return "exhaust_materials"
    end

    local function GetV2StatsForStrat(strat, opts, ctx)
        local resolver = GAM.CraftingStatsV2 and GAM.CraftingStatsV2.ResolveForStrat
        if type(resolver) ~= "function" then
            return nil, "no-stat-resolver"
        end

        local gearMode = type(ctx) == "table"
            and ctx.gearModeOverride
            and ctx.strat == strat
            and ctx.gearModeOverride
            or "auto"
        local profileKey = strat and (strat.statProfileKey or strat.formulaProfile) or nil
        local cacheKey = table.concat({
            tostring(strat and (strat.id or strat.stratName) or "?"),
            tostring(profileKey or "-"),
            tostring(strat and strat.recipeID or "-"),
            tostring(gearMode),
        }, ":")

        if type(ctx) == "table" and type(ctx.v2StatResolutions) == "table" then
            local cached = ctx.v2StatResolutions[cacheKey]
            if cached == false then
                return nil, "stat-resolver-unavailable"
            end
            if cached ~= nil then
                return cached, nil
            end
        end

        local resolverOpts = opts or GetOpts()
        if gearMode ~= "auto" then
            resolverOpts = {}
            for key, value in pairs(opts or GetOpts()) do resolverOpts[key] = value end
            resolverOpts._gamGearModeOverride = gearMode
        end
        local ok, snapshot = pcall(function()
            return resolver(strat, resolverOpts)
        end)
        if not ok or type(snapshot) ~= "table" then
            if type(ctx) == "table" and type(ctx.v2StatResolutions) == "table" then
                ctx.v2StatResolutions[cacheKey] = false
            end
            return nil, ok and "stat-resolver-empty" or "stat-resolver-error"
        end

        if type(ctx) == "table" and type(ctx.v2StatResolutions) == "table" then
            ctx.v2StatResolutions[cacheKey] = snapshot
        end
        return snapshot, nil
    end

    local function ApplyV2ResolvedStats(input, snapshot)
        if type(input) ~= "table" or type(snapshot) ~= "table" then
            return
        end

        local used = false
        if snapshot.supportsMulticraft ~= nil then
            input.supportsMulticraft = snapshot.supportsMulticraft and true or false
            used = true
        end
        if snapshot.supportsResourcefulness ~= nil then
            input.supportsResourcefulness = snapshot.supportsResourcefulness and true or false
            used = true
        end

        if input.supportsMulticraft then
            local multiPercent = tonumber(snapshot.multiPercent)
            if multiPercent ~= nil then
                input.mcPercent = math.max(0, math.min(1, multiPercent / 100))
                used = true
            end
            local multiExtra = tonumber(snapshot.multiExtra)
            if multiExtra ~= nil then
                input.mcExtra = math.max(0, multiExtra)
                used = true
            end
        else
            input.mcPercent = 0
            input.mcExtra = 0
        end

        if input.supportsResourcefulness then
            local resPercent = tonumber(snapshot.resPercent)
            if resPercent ~= nil then
                input.resPercent = math.max(0, math.min(1, resPercent / 100))
                used = true
            end
            local resExtra = tonumber(snapshot.resExtra)
            if resExtra ~= nil then
                input.resExtra = math.max(0, resExtra)
                used = true
            end
        else
            input.resPercent = 0
            input.resExtra = 0
        end

        if snapshot.multicraftConstants then
            input.multicraftConstants = snapshot.multicraftConstants
        end
        if snapshot.mcConstant ~= nil then
            input.multicraftConstants = input.multicraftConstants or {}
            input.multicraftConstants.DEFAULT = tonumber(snapshot.mcConstant) or input.multicraftConstants.DEFAULT
        end
        if snapshot.resourcefulnessSaveBase ~= nil then
            input.resourcefulnessSaveBase = math.max(0, tonumber(snapshot.resourcefulnessSaveBase) or 0)
        end

        if used then
            input.statSource = snapshot.statSource or snapshot.source or input.statSource
            input.statQuality = snapshot.statQuality
            input.nodeHash = snapshot.nodeHash
            input.crafterUID = snapshot.crafterUID
            input.crafterName = snapshot.crafterName
            input.crafterRealm = snapshot.crafterRealm
            input.crossCharacter = snapshot.crossCharacter and true or nil
        end
    end

    local function CalculateV2Formula(strat, opts, baseYield, crafts, requiredCraftCost, constants, statSnapshot, statFallbackReason)
        local formula = GetFormulaV2()
        local input, profileDef = BuildV2FormulaInput(strat, opts, baseYield, crafts, requiredCraftCost, constants)
        input.statFallbackReason = (statSnapshot and statSnapshot.fallbackReason) or statFallbackReason
        input.pricingMode = GetV2PricingMode(strat, opts)
        ApplyV2ResolvedStats(input, statSnapshot)
        local result
        if input.pricingMode == "exhaust_materials"
                and formula
                and type(formula.CalculateExhaustMaterials) == "function" then
            result = formula.CalculateExhaustMaterials(input)
        elseif formula and type(formula.CalculateFixedCrafts) == "function" then
            result = formula.CalculateFixedCrafts(input)
        else
            result = {
                expectedYieldPerCraft = input.baseYield,
                expectedOutput = (input.crafts or 0) * (input.baseYield or 0),
                requiredCraftCost = input.requiredCraftCost or 0,
                averageSavedCost = 0,
                expectedConsumedCost = input.requiredCraftCost or 0,
            }
        end
        result.profileKey = statSnapshot and statSnapshot.profileKey
            or (strat and (strat.statProfileKey or strat.formulaProfile))
            or nil
        result.recipeID = statSnapshot and statSnapshot.recipeID or (strat and strat.recipeID) or nil
        result.recipeName = statSnapshot and statSnapshot.recipeName or (strat and strat.recipeName) or nil
        result.profileDef = profileDef
        result.statSource = input.statSource
        result.statFallbackReason = input.statFallbackReason
        result.statQuality = input.statQuality
        result.nodeHash = input.nodeHash
        result.crafterUID = input.crafterUID
        result.crafterName = input.crafterName
        result.crafterRealm = input.crafterRealm
        result.crossCharacter = input.crossCharacter
        result.pricingMode = input.pricingMode
        result.nodeStats = statSnapshot and statSnapshot.nodeStats or nil
        result.nodeBonusDetails = statSnapshot and statSnapshot.nodeBonusDetails or nil
        result.totalStats = statSnapshot and statSnapshot.totalStats or nil
        return result
    end

    local function ComputeV2OutputQuantity(outputDef, ctx, strat)
        if not outputDef then
            return 0, 0, nil
        end
        strat = strat or ctx.strat
        local baseYield = GetOutputBaseYield(outputDef) or 0
        local basis = GetOutputQuantityBasis(outputDef, ctx.startingAmt, ctx.crafts) or 0
        local formulaResult = CalculateV2Formula(
            strat,
            ctx.opts,
            baseYield,
            basis,
            0,
            nil,
            GetV2StatsForStrat(strat, ctx.opts, ctx))
        local qtyRaw = formulaResult.expectedOutput or 0
        return qtyRaw, math.floor(qtyRaw + 0.5), formulaResult
    end

    local function GetV2ExpectedOutputPerCraft(strat, active, ctx)
        if not strat or not active then
            return nil
        end
        local output = (active.outputs and active.outputs[1]) or active.output
        if not output then
            return nil
        end
        local baseYield = GetOutputBaseYield(output) or 0
        local formulaResult = CalculateV2Formula(
            strat,
            (ctx and ctx.opts) or GetOpts(),
            baseYield,
            1,
            0,
            nil,
            GetV2StatsForStrat(strat, (ctx and ctx.opts) or GetOpts(), ctx))
        return formulaResult and formulaResult.expectedOutput or baseYield
    end

    local function BuildV2SingleOutputMetrics(ctx, primaryOut, outputQtyRaw, outPrice, outMissingPrice, missingPrices)
        local netRevenue = nil
        if outMissingPrice then
            missingPrices[#missingPrices + 1] = GetItemLabel(primaryOut) or "Output"
        elseif outPrice and outputQtyRaw > 0 then
            netRevenue = math.floor(outputQtyRaw * outPrice * (1 - ctx.ahCut))
        end
        return nil, netRevenue
    end

    local function BuildV2MultiOutputMetrics(ctx, outputPreferredQuality, missingPrices)
        local totalRevenue = 0
        local allHavePrices = true
        local outResults = {}
        local hasStale = false
        local priceQty = GetOutputPriceQty(ctx)

        for _, outputDef in ipairs(ctx.active.outputs) do
            local outputQtyRaw, outputQty, formulaResult = ComputeV2OutputQuantity(outputDef, ctx)
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
                formula = formulaResult,
            }
        end

        return outResults, allHavePrices and totalRevenue or nil, hasStale
    end

    local function BuildV2OutputMetrics(ctx)
        local primaryOut = GetPrimaryOutput(ctx)
        if not primaryOut.name and not primaryOut.itemRef and not primaryOut.itemIDs then
            return nil
        end

        local missingPrices = {}
        local outputQtyRaw, outputQty, formulaResult = ComputeV2OutputQuantity(primaryOut, ctx)
        local primaryQuality = GetPrimaryInputQuality(ctx)
        local outputPreferredQuality = (ctx.strat.outputQualityMode == "match_input") and primaryQuality or nil
        local priceQty = GetOutputPriceQty(ctx)
        local outPrice, outStale = GetOutputPriceForItem(primaryOut, ctx.patchTag, outputPreferredQuality, priceQty)
        local outMissingPrice = not outPrice
        local isMultiOutput = ctx.active.outputs and #ctx.active.outputs > 1
        local outputs, netRevenue, extraStale

        if isMultiOutput then
            outputs, netRevenue, extraStale = BuildV2MultiOutputMetrics(ctx, outputPreferredQuality, missingPrices)
        else
            outputs, netRevenue = BuildV2SingleOutputMetrics(ctx, primaryOut, outputQtyRaw, outPrice, outMissingPrice, missingPrices)
            extraStale = false
        end

        return {
            primaryOut = primaryOut,
            outputQtyRaw = outputQtyRaw,
            output = {
                name = GetItemLabel(primaryOut),
                itemID = GetOutputItemIDForDisplay(primaryOut, ctx.patchTag, outputPreferredQuality),
                unitPrice = outPrice,
                expectedQty = outputQty,
                expectedQtyRaw = outputQtyRaw,
                netRevenue = (not isMultiOutput) and netRevenue or nil,
                isStale = outStale,
                missingPrice = outMissingPrice,
                formula = formulaResult,
            },
            outputs = outputs,
            netRevenue = netRevenue,
            hasStale = outStale or extraStale,
            isMultiOutput = isMultiOutput,
            missingPrices = missingPrices,
        }
    end

    local BuildV2RecipeEconomicCost

    local function MergeMissingPrices(target, source)
        for _, name in ipairs(source or {}) do
            target[#target + 1] = name
        end
    end

    local function HasMissingEconomicCost(result)
        return type(result) ~= "table"
            or (type(result.missingPrices) == "table" and #result.missingPrices > 0)
    end

    local function PreferProducerEconomicCost(directCost, producerCost)
        local directMissing = HasMissingEconomicCost(directCost)
        local producerMissing = HasMissingEconomicCost(producerCost)
        if directMissing ~= producerMissing then
            return directMissing and not producerMissing
        end
        if directMissing then
            return false
        end
        return (producerCost.expectedConsumedCostFull or math.huge)
            < (directCost.expectedConsumedCostFull or math.huge)
    end

    local function StoreV2EconomicChoice(ctx, itemID, source, producer, directCost, producerCost)
        if type(ctx) ~= "table" or type(ctx.v2EconomicChoices) ~= "table" or not itemID then
            return
        end
        ctx.v2EconomicChoices[tostring(itemID)] = {
            source = source,
            producerName = producer and producer.strat and producer.strat.stratName or nil,
            directExpectedCost = directCost and directCost.expectedConsumedCostFull or nil,
            producerExpectedCost = producerCost and producerCost.expectedConsumedCostFull or nil,
            directRequiredCost = directCost and directCost.requiredCostFull or nil,
            producerRequiredCost = producerCost and producerCost.requiredCostFull or nil,
            directMissing = HasMissingEconomicCost(directCost),
            producerMissing = HasMissingEconomicCost(producerCost),
        }
    end

    local function RecordV2StatUsage(ctx, strat, formulaResult)
        if type(ctx) ~= "table" or type(ctx.v2StatUsages) ~= "table" or type(formulaResult) ~= "table" then
            return
        end

        ctx.v2StatUsages[#ctx.v2StatUsages + 1] = {
            role = strat == ctx.strat and "root" or "producer",
            stratID = strat and strat.id or nil,
            stratName = strat and strat.stratName or nil,
            profileKey = formulaResult.profileKey,
            statSource = formulaResult.statSource,
            statFallbackReason = formulaResult.statFallbackReason,
            crafterUID = formulaResult.crafterUID,
            crafterName = formulaResult.crafterName,
            crafterRealm = formulaResult.crafterRealm,
            crossCharacter = formulaResult.crossCharacter,
            nodeHash = formulaResult.nodeHash,
            nodeBonusDetails = formulaResult.nodeBonusDetails,
            mcPercent = formulaResult.mcPercent,
            mcExtra = formulaResult.mcExtra,
            resPercent = formulaResult.resPercent,
            resExtra = formulaResult.resExtra,
            pricingMode = formulaResult.pricingMode,
            expectedYieldPerCraft = formulaResult.expectedYieldPerCraft,
            expectedYieldPerActualCraft = formulaResult.expectedYieldPerActualCraft,
            effectiveCrafts = formulaResult.effectiveCrafts,
            consumptionFactor = formulaResult.consumptionFactor,
        }
    end

    local function BuildV2LeafEconomicCost(ctx, resolvedEntry, requiredQty)
        if resolvedEntry and resolvedEntry.excludeFromCost then
            return {
                requiredCostFull = 0,
                expectedConsumedCostFull = 0,
                hasStale = false,
                missingPrices = {},
            }
        end

        local inputPolicy = GetInputRankPolicy(ctx.strat)
        local itemID = resolvedEntry and resolvedEntry.itemID or nil
        local itemIDs = (resolvedEntry and resolvedEntry.itemIDs) or (itemID and { itemID }) or {}
        local price, stale = Pricing.GetEffectivePriceForItem({
            itemIDs = itemID and { itemID } or itemIDs,
            name = resolvedEntry and resolvedEntry.name or nil,
            skipDerivation = resolvedEntry and resolvedEntry.skipDerivation or false,
            rankPolicyOverride = inputPolicy,
        }, ctx.patchTag, requiredQty)

        if not price then
            return {
                requiredCostFull = 0,
                expectedConsumedCostFull = 0,
                hasStale = stale and true or false,
                missingPrices = { (resolvedEntry and resolvedEntry.name) or "Reagent" },
            }
        end

        local cost = requiredQty * price
        return {
            requiredCostFull = cost,
            expectedConsumedCostFull = cost,
            hasStale = stale and true or false,
            missingPrices = {},
        }
    end

    local function BuildV2ReagentEconomicCost(ctx, node, requiredQty, state)
        if not node or not requiredQty or requiredQty <= 0 then
            return {
                requiredCostFull = 0,
                expectedConsumedCostFull = 0,
                hasStale = false,
                missingPrices = {},
            }
        end

        local qtyForPricing = math.max(1, QuantizeRequiredAmount(requiredQty, "nearest"))
        local resolvedEntry = ResolveGraphNodeEntry(ctx, node, qtyForPricing)
        if not resolvedEntry then
            return {
                requiredCostFull = 0,
                expectedConsumedCostFull = 0,
                hasStale = false,
                missingPrices = { GetItemLabel(node) or "Reagent" },
            }
        end

        local directCost = BuildV2LeafEconomicCost(ctx, resolvedEntry, requiredQty)

        if resolvedEntry.excludeFromCost or resolvedEntry.skipDerivation or not ctx.chainActive then
            return directCost
        end

        local producer = FindProducerMatch(ctx, resolvedEntry.itemID, state)
        if not producer then
            return directCost
        end

        local expectedOutputPerCraft = GetV2ExpectedOutputPerCraft(
            producer.strat,
            producer.active,
            ctx)
        if not expectedOutputPerCraft or expectedOutputPerCraft <= 0 then
            return directCost
        end

        local craftsNeeded = requiredQty / expectedOutputPerCraft
        local key = producer.key
        state.activeProducerKeys[key] = true
        local producerCost = BuildV2RecipeEconomicCost(ctx, producer.strat, producer.active, craftsNeeded, state)
        state.activeProducerKeys[key] = nil
        if PreferProducerEconomicCost(directCost, producerCost) then
            StoreV2EconomicChoice(ctx, resolvedEntry.itemID, "producer", producer, directCost, producerCost)
            return producerCost
        end
        StoreV2EconomicChoice(ctx, resolvedEntry.itemID, "direct", producer, directCost, producerCost)
        return directCost
    end

    BuildV2RecipeEconomicCost = function(ctx, strat, active, crafts, state)
        local startingAmt = GetScaledStartingAmountForCrafts(active, crafts)
        local requiredCostFull = 0
        local childExpectedCost = 0
        local hasStale = false
        local missingPrices = {}

        for _, reagent in ipairs(active.reagents or {}) do
            local childQty = GetRequiredReagentAmountRaw(reagent, startingAmt, crafts)
            local child = BuildV2ReagentEconomicCost(ctx, reagent, childQty, state)
            requiredCostFull = requiredCostFull + (child.requiredCostFull or 0)
            childExpectedCost = childExpectedCost + (child.expectedConsumedCostFull or 0)
            hasStale = hasStale or child.hasStale
            MergeMissingPrices(missingPrices, child.missingPrices)
        end

        local primaryOut = (active.outputs and active.outputs[1]) or active.output
        local baseYield = GetOutputBaseYield(primaryOut) or 0
        local formulaResult = CalculateV2Formula(
            strat,
            ctx.opts,
            baseYield,
            crafts,
            childExpectedCost,
            nil,
            GetV2StatsForStrat(strat, ctx.opts, ctx))
        RecordV2StatUsage(ctx, strat, formulaResult)

        return {
            crafts = crafts,
            startingAmount = startingAmt,
            requiredCostFull = requiredCostFull,
            expectedConsumedCostFull = formulaResult.expectedConsumedCost or childExpectedCost,
            averageSavedCost = formulaResult.averageSavedCost or 0,
            formula = formulaResult,
            hasStale = hasStale,
            missingPrices = missingPrices,
        }
    end

    local function BuildV2EconomicMetrics(ctx)
        local state = {
            activeProducerKeys = {},
        }
        return BuildV2RecipeEconomicCost(ctx, ctx.strat, ctx.active, ctx.crafts, state)
    end

    local function BuildV2FinalMetrics(ctx, outputData, displayReagentData, costReagentData, economicData)
        economicData = economicData or BuildV2EconomicMetrics(ctx)
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

        AddMissingNames(economicData.missingPrices)
        AddMissingNames(displayReagentData and displayReagentData.missingPrices)
        AddMissingNames(outputData.missingPrices)

        local profit = nil
        local roi = nil
        local breakEven = nil
        if outputData.netRevenue and #missingPrices == 0 then
            profit = outputData.netRevenue - economicData.expectedConsumedCostFull
            if economicData.expectedConsumedCostFull > 0 then
                roi = (profit / economicData.expectedConsumedCostFull) * 100
            end
        end
        if economicData.expectedConsumedCostFull > 0 and outputData.outputQtyRaw > 0 and not outputData.isMultiOutput then
            breakEven = economicData.expectedConsumedCostFull / (outputData.outputQtyRaw * (1 - ctx.ahCut))
        end

        return {
            model = "v2",
            startingAmount = ctx.startingAmt,
            crafts = ctx.crafts,
            reagents = displayReagentData and displayReagentData.reagentResults or nil,
            costReagents = costReagentData and costReagentData.reagentResults or nil,
            output = outputData.output,
            outputs = outputData.outputs,
            requiredCostFull = economicData.requiredCostFull,
            expectedConsumedCostFull = economicData.expectedConsumedCostFull,
            averageSavedCost = economicData.averageSavedCost,
            totalCostToBuy = displayReagentData and displayReagentData.totalCostToBuy or nil,
            totalCostFull = economicData.requiredCostFull,
            netRevenue = outputData.netRevenue,
            profit = profit,
            roi = roi,
            breakEvenSell = breakEven,
            missingPrices = missingPrices,
            hasStale = economicData.hasStale
                or (displayReagentData and displayReagentData.hasStale)
                or outputData.hasStale,
            selectionNotes = costReagentData and costReagentData.selectionNotes or nil,
            formula = economicData.formula,
            statUsages = ctx.v2StatUsages,
            economicChoices = ctx.v2EconomicChoices,
            gearModeRequested = ctx.gearModeRequested,
            gearModeResolved = ctx.gearModeResolved,
            gearPresetMissing = ctx.gearPresetMissing and true or false,
        }
    end

    local function CalculateStratMetricsV2Once(strat, patchTag, craftQty, gearModeOverride)
        local opts = GetOpts()
        local ahCut = opts.ahCut or GAM.C.AH_CUT
        local pdb = GetPatchDB(patchTag)
        local active = GetActiveRecipeView(strat)
        if not active or type(active.reagents) ~= "table" or #active.reagents == 0 then
            return nil
        end

        local ctx = BuildCalcContext(strat, active, patchTag, craftQty, opts, pdb, ahCut)
        ctx.v2StatResolutions = {}
        ctx.v2StatUsages = {}
        ctx.v2EconomicChoices = {}
        ctx.v2ExecutionPlan = true
        ctx.gearModeOverride = gearModeOverride
        local costReagentData = BuildReagentMetrics(ctx)
        local outputData = BuildV2OutputMetrics(ctx)
        if not outputData then
            return nil
        end
        local economicData = BuildV2EconomicMetrics(ctx)
        local displayReagentData = BuildDisplayReagentMetrics(ctx, costReagentData and costReagentData.reagentResults)
        return BuildV2FinalMetrics(ctx, outputData, displayReagentData, costReagentData, economicData)
    end

    function Pricing.CalculateStratMetricsV2(strat, patchTag, craftQty)
        if not strat then return nil end
        patchTag = patchTag or GAM.C.DEFAULT_PATCH
        craftQty = craftQty or 1

        local stats = GAM.CraftingStatsV2
        local requested = stats and stats.GetGearModeForStrat
            and stats.GetGearModeForStrat(strat, patchTag)
            or "auto"
        local available = stats and stats.GetAvailableGearPresetModes
            and stats.GetAvailableGearPresetModes(strat)
            or { multicraft = false, resourcefulness = false }
        local resolved = nil
        local metrics = nil

        if requested == "multicraft" or requested == "resourcefulness" then
            resolved = available[requested] and requested or "current"
            metrics = CalculateStratMetricsV2Once(
                strat, patchTag, craftQty, available[requested] and requested or nil)
        elseif available.multicraft and available.resourcefulness then
            local multicraft = CalculateStratMetricsV2Once(
                strat, patchTag, craftQty, "multicraft")
            local resourcefulness = CalculateStratMetricsV2Once(
                strat, patchTag, craftQty, "resourcefulness")
            metrics, resolved = Engine.SelectGearMetrics(multicraft, resourcefulness)
        elseif available.multicraft or available.resourcefulness then
            resolved = available.multicraft and "multicraft" or "resourcefulness"
            metrics = CalculateStratMetricsV2Once(strat, patchTag, craftQty, resolved)
        else
            resolved = "current"
            metrics = CalculateStratMetricsV2Once(strat, patchTag, craftQty, nil)
        end

        if metrics then
            metrics.gearModeRequested = requested
            metrics.gearModeResolved = resolved
            metrics.gearPresetMissing = requested ~= "auto"
                and not available[requested]
                or false
            if type(metrics.formula) == "table" then
                metrics.formula.gearModeRequested = requested
                metrics.formula.gearModeResolved = resolved
                metrics.formula.gearPresetMissing = metrics.gearPresetMissing
            end
        end
        return metrics
    end

    Pricing.GetFormulaV2 = GetFormulaV2
    Pricing.GetV2ExpectedOutputPerCraft = GetV2ExpectedOutputPerCraft
    return true
end
