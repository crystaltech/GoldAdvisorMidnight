-- GoldAdvisorMidnight/PricingContract.lua
-- Stable request/result boundary for the commodity pricing migration.
--
-- Production consumers use this contract through PricingFacade. The canonical
-- V2 calculator is the only accepted runtime pricing implementation.

local ADDON_NAME, GAM = ...

local Contract = {}
GAM.PricingContract = Contract

Contract.VERSION = 1

local VALID_RANK_POLICIES = {
    lowest = true,
    highest = true,
    optimal = true,
}

local VALID_PRICING_MODES = {
    exhaust_materials = true,
    fixed_crafts = true,
}

local VALID_INVENTORY_POLICIES = {
    -- Profit uses the full opportunity cost of materials. Owned inventory only
    -- reduces buyNowCost and never makes a bad craft appear profitable.
    opportunity_cost = true,
}

local VALID_PRICE_POLICIES = {
    -- Resolve prices from the addon's current runtime market-price store.
    runtime_market = true,
    -- Preserve the current optional CraftSim source, with the runtime market
    -- store remaining its fallback.
    craftsim_then_market = true,
}

local function IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function IsNonNegativeNumber(value)
    return IsFiniteNumber(value) and value >= 0
end

local function NearlyEqual(actual, expected)
    if not IsFiniteNumber(actual) or not IsFiniteNumber(expected) then
        return false
    end
    local tolerance = math.max(0.000001, math.abs(expected) * 0.000001)
    return math.abs(actual - expected) <= tolerance
end

local function ValidateEnum(value, allowed, fieldName)
    if not allowed[value] then
        return false, string.format("%s has unsupported value '%s'", fieldName, tostring(value))
    end
    return true
end

local function DefaultConstant(name, fallback)
    local constants = GAM.C or {}
    local value = constants[name]
    if value == nil then
        return fallback
    end
    return value
end

function Contract.ValidateRequest(request)
    if type(request) ~= "table" then
        return false, "request must be a table"
    end
    if request.contractVersion ~= Contract.VERSION then
        return false, "request contractVersion must match PricingContract.VERSION"
    end
    if type(request.strategy) ~= "table" then
        return false, "request.strategy must be a canonical strategy"
    end
    if type(request.strategy.id) ~= "string" or request.strategy.id == "" then
        return false, "request.strategy.id must be a non-empty string"
    end
    if not IsFiniteNumber(request.strategy.recipeID) or request.strategy.recipeID <= 0 then
        return false, "request.strategy.recipeID must be a positive number"
    end
    if type(request.patchTag) ~= "string" or request.patchTag == "" then
        return false, "request.patchTag must be a non-empty string"
    end
    if not IsFiniteNumber(request.craftScale) or request.craftScale <= 0 then
        return false, "request.craftScale must be greater than zero"
    end
    for _, fieldName in ipairs({ "inputQuantityOverride", "craftsOverride" }) do
        local value = request[fieldName]
        if value ~= nil and (not IsFiniteNumber(value) or value <= 0) then
            return false, "request." .. fieldName .. " must be nil or greater than zero"
        end
    end

    local ok, err = ValidateEnum(request.materialRank, VALID_RANK_POLICIES, "request.materialRank")
    if not ok then return false, err end
    ok, err = ValidateEnum(request.pricingMode, VALID_PRICING_MODES, "request.pricingMode")
    if not ok then return false, err end
    ok, err = ValidateEnum(request.inventoryPolicy, VALID_INVENTORY_POLICIES, "request.inventoryPolicy")
    if not ok then return false, err end
    ok, err = ValidateEnum(request.pricePolicy, VALID_PRICE_POLICIES, "request.pricePolicy")
    if not ok then return false, err end

    if type(request.useVerticalIntegration) ~= "boolean" then
        return false, "request.useVerticalIntegration must be a boolean"
    end
    if not IsFiniteNumber(request.fillQuantity)
        or request.fillQuantity < 1
        or request.fillQuantity % 1 ~= 0
    then
        return false, "request.fillQuantity must be a positive integer"
    end
    if not IsFiniteNumber(request.auctionHouseCut)
        or request.auctionHouseCut < 0
        or request.auctionHouseCut >= 1
    then
        return false, "request.auctionHouseCut must be at least zero and less than one"
    end
    return true
end

function Contract.BuildRequest(args)
    args = args or {}
    local request = {
        contractVersion = Contract.VERSION,
        strategy = args.strategy,
        patchTag = args.patchTag or DefaultConstant("DEFAULT_PATCH", "midnight-1"),
        -- Compatibility meaning: multiplier applied to the strategy's stored
        -- baseline amount/crafts when no persisted override takes precedence.
        -- The result exposes the resolved craft count.
        craftScale = args.craftScale or 1,
        inputQuantityOverride = args.inputQuantityOverride,
        craftsOverride = args.craftsOverride,
        materialRank = args.materialRank or DefaultConstant("DEFAULT_RANK_POLICY", "lowest"),
        pricingMode = args.pricingMode
            or DefaultConstant("DEFAULT_V2_PRICING_MODE", "exhaust_materials"),
        inventoryPolicy = args.inventoryPolicy or "opportunity_cost",
        pricePolicy = args.pricePolicy or "runtime_market",
        useVerticalIntegration = args.useVerticalIntegration and true or false,
        fillQuantity = args.fillQuantity or DefaultConstant("DEFAULT_FILL_QTY", 50),
        auctionHouseCut = args.auctionHouseCut,
    }
    if request.auctionHouseCut == nil then
        request.auctionHouseCut = DefaultConstant("AH_CUT", 0.05)
    end

    local ok, err = Contract.ValidateRequest(request)
    if not ok then
        return nil, err
    end
    return request
end

local function NormalizeOutputs(metrics)
    local outputs = {}
    if type(metrics.outputs) == "table" and #metrics.outputs > 0 then
        for index, output in ipairs(metrics.outputs) do
            outputs[index] = output
        end
    elseif type(metrics.output) == "table" then
        outputs[1] = metrics.output
    end
    return outputs
end

-- Translate the internal V2 metrics shape into the canonical consumer shape.
function Contract.FromV2Metrics(request, metrics)
    local ok, err = Contract.ValidateRequest(request)
    if not ok then
        return nil, err
    end
    if type(metrics) ~= "table" then
        return nil, "metrics must be a table"
    end
    if metrics.model ~= "v2" then
        return nil, "metrics must come from the V2 pricing engine"
    end

    local outputs = NormalizeOutputs(metrics)
    local primaryOutput = outputs[1]
    local crafts = metrics.crafts
    local profitPerCraft = nil
    if IsFiniteNumber(metrics.profit) and IsFiniteNumber(crafts) and crafts > 0 then
        profitPerCraft = metrics.profit / crafts
    end

    local effectiveCrafts = metrics.formula and metrics.formula.effectiveCrafts or crafts
    local recommendedCrafts = math.floor(math.max(0, tonumber(effectiveCrafts) or 0) + 0.0000001)
    local result = {
        contractVersion = Contract.VERSION,
        engine = "commodity_expected_value",
        strategyID = request.strategy.id,
        recipeID = request.strategy.recipeID,
        patchTag = request.patchTag,
        pricingMode = request.pricingMode,

        startingAmount = metrics.startingAmount,
        crafts = crafts,
        effectiveCrafts = effectiveCrafts,
        recommendedCrafts = recommendedCrafts,
        expectedOutput = primaryOutput and primaryOutput.expectedQtyRaw or nil,

        requiredCostFull = metrics.requiredCostFull,
        expectedConsumedCostFull = metrics.expectedConsumedCostFull,
        averageSavedCost = metrics.averageSavedCost,
        buyNowCost = metrics.totalCostToBuy,
        netRevenue = metrics.netRevenue,
        profit = metrics.profit,
        profitPerCraft = profitPerCraft,
        roi = metrics.roi,
        breakEvenSell = metrics.breakEvenSell,

        shoppingReagents = metrics.reagents or {},
        recipeReagents = metrics.costReagents or {},
        outputs = outputs,
        missingPrices = metrics.missingPrices or {},
        hasStale = metrics.hasStale and true or false,
        selectionNotes = metrics.selectionNotes,
        rankMixStatus = metrics.rankMixStatus,
        rankMixReason = metrics.rankMixReason,
        rankMixTargetQuality = metrics.rankMixTargetQuality,
        rankMixOutputQuality = metrics.rankMixOutputQuality,
        rankMixHighSkill = metrics.rankMixHighSkill,
        rankMixRequiredSkill = metrics.rankMixRequiredSkill,
        rankMixSkillDeficit = metrics.rankMixSkillDeficit,
        rankMixConcentrationCost = metrics.rankMixConcentrationCost,
        gearModeRequested = metrics.gearModeRequested,
        gearModeResolved = metrics.gearModeResolved,
        gearPresetMissing = metrics.gearPresetMissing and true or false,

        diagnostics = {
            formula = metrics.formula,
            statUsages = metrics.statUsages,
            economicChoices = metrics.economicChoices,
            rankMixPlan = metrics.rankMixPlan,
            rankMixTargetQuality = metrics.rankMixTargetQuality,
            rankMixOutputQuality = metrics.rankMixOutputQuality,
            rankMixHighSkill = metrics.rankMixHighSkill,
            rankMixRequiredSkill = metrics.rankMixRequiredSkill,
            rankMixSkillDeficit = metrics.rankMixSkillDeficit,
            rankMixConcentrationCost = metrics.rankMixConcentrationCost,
        },
    }

    ok, err = Contract.ValidateResult(result, request)
    if not ok then
        return nil, err
    end
    return result
end

function Contract.ValidateResult(result, request)
    if type(result) ~= "table" then
        return false, "result must be a table"
    end
    if result.contractVersion ~= Contract.VERSION then
        return false, "result contractVersion must match PricingContract.VERSION"
    end
    if result.engine ~= "commodity_expected_value" then
        return false, "result.engine must be commodity_expected_value"
    end
    if type(result.strategyID) ~= "string" or result.strategyID == "" then
        return false, "result.strategyID must be a non-empty string"
    end
    if not IsFiniteNumber(result.recipeID) or result.recipeID <= 0 then
        return false, "result.recipeID must be a positive number"
    end
    if type(result.patchTag) ~= "string" or result.patchTag == "" then
        return false, "result.patchTag must be a non-empty string"
    end
    if not VALID_PRICING_MODES[result.pricingMode] then
        return false, "result.pricingMode is unsupported"
    end

    if request then
        local requestOK, requestErr = Contract.ValidateRequest(request)
        if not requestOK then return false, requestErr end
        if result.strategyID ~= request.strategy.id
            or result.recipeID ~= request.strategy.recipeID
            or result.patchTag ~= request.patchTag
            or result.pricingMode ~= request.pricingMode
        then
            return false, "result identity or pricing mode does not match its request"
        end
    end

    for _, fieldName in ipairs({
        "startingAmount",
        "crafts",
        "effectiveCrafts",
        "recommendedCrafts",
        "expectedOutput",
        "requiredCostFull",
        "expectedConsumedCostFull",
        "averageSavedCost",
        "buyNowCost",
    }) do
        if not IsNonNegativeNumber(result[fieldName]) then
            return false, "result." .. fieldName .. " must be a non-negative number"
        end
    end

    if type(result.shoppingReagents) ~= "table"
        or type(result.recipeReagents) ~= "table"
        or type(result.outputs) ~= "table"
        or #result.outputs == 0
        or type(result.missingPrices) ~= "table"
        or type(result.diagnostics) ~= "table"
    then
        return false, "result collections are incomplete"
    end
    if type(result.hasStale) ~= "boolean" then
        return false, "result.hasStale must be a boolean"
    end
    if result.expectedConsumedCostFull > result.requiredCostFull
        and not NearlyEqual(result.expectedConsumedCostFull, result.requiredCostFull)
    then
        return false, "result.expectedConsumedCostFull cannot exceed requiredCostFull"
    end
    if result.pricingMode == "fixed_crafts"
        and not NearlyEqual(result.effectiveCrafts, result.crafts)
    then
        return false, "fixed-crafts results must not reinvest saved materials"
    end
    if result.pricingMode == "exhaust_materials"
        and result.effectiveCrafts < result.crafts
        and not NearlyEqual(result.effectiveCrafts, result.crafts)
    then
        return false, "exhaust-materials effective crafts cannot be below planned crafts"
    end
    if result.recommendedCrafts ~= math.floor(result.recommendedCrafts)
            or result.recommendedCrafts > result.effectiveCrafts
                and not NearlyEqual(result.recommendedCrafts, result.effectiveCrafts) then
        return false, "recommendedCrafts must be a conservative whole-craft count"
    end
    local diagnosticMode = result.diagnostics.formula
        and result.diagnostics.formula.pricingMode
    if diagnosticMode and diagnosticMode ~= result.pricingMode then
        return false, "formula pricing mode does not match the canonical result"
    end

    local hasMissingPrices = #result.missingPrices > 0
    if not hasMissingPrices then
        if not IsFiniteNumber(result.netRevenue)
            or not IsFiniteNumber(result.profit)
            or not IsFiniteNumber(result.profitPerCraft)
        then
            return false, "fully priced results must include revenue and profit metrics"
        end
        local expectedProfit = result.netRevenue - result.expectedConsumedCostFull
        if not NearlyEqual(result.profit, expectedProfit) then
            return false, "result.profit must equal netRevenue minus expectedConsumedCostFull"
        end
        if result.crafts <= 0 then
            return false, "fully priced results must have a positive craft count"
        end
        if not NearlyEqual(result.profitPerCraft, result.profit / result.crafts) then
            return false, "result.profitPerCraft must use the resolved craft count"
        end
        if result.expectedConsumedCostFull > 0 then
            local expectedROI = result.profit / result.expectedConsumedCostFull * 100
            if not NearlyEqual(result.roi, expectedROI) then
                return false, "result.roi must use expectedConsumedCostFull"
            end
        elseif result.roi ~= nil then
            return false, "result.roi must be nil when expected consumed cost is zero"
        end

        if #result.outputs == 1
            and result.expectedConsumedCostFull > 0
            and result.expectedOutput > 0
        then
            if not request then
                return false, "request is required to validate break-even"
            end
            local expectedBreakEven = result.expectedConsumedCostFull
                / (result.expectedOutput * (1 - request.auctionHouseCut))
            if not NearlyEqual(result.breakEvenSell, expectedBreakEven) then
                return false, "result.breakEvenSell must recover consumed cost after the AH cut"
            end
        elseif #result.outputs > 1 and result.breakEvenSell ~= nil then
            return false, "multi-output results cannot expose one break-even unit price"
        end
    end

    return true
end
