-- Executable contract for the commodity pricing facade migration.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {
    C = {
        DEFAULT_PATCH = "midnight-1",
        DEFAULT_RANK_POLICY = "lowest",
        DEFAULT_V2_PRICING_MODE = "exhaust_materials",
        DEFAULT_FILL_QTY = 50,
        AH_CUT = 0.05,
    },
}

local function LoadModule(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk(ADDON_NAME, GAM)
end

local function AssertNear(actual, expected, label)
    local tolerance = math.max(0.000001, math.abs(expected) * 0.000001)
    assert(math.abs((actual or 0) - expected) <= tolerance,
        string.format("%s: expected %.9f, got %.9f", label, expected, actual or 0))
end

LoadModule("PricingContract.lua")
LoadModule("PricingV2Engine.lua")

local Contract = assert(GAM.PricingContract, "PricingContract unavailable")
local Engine = assert(GAM.PricingV2Engine, "PricingV2Engine unavailable")

local mcMetrics = { profit = 100, expectedConsumedCostFull = 900 }
local resMetrics = { profit = 125, expectedConsumedCostFull = 850 }
local selectedMetrics, selectedMode = Engine.SelectGearMetrics(mcMetrics, resMetrics)
assert(selectedMetrics == resMetrics and selectedMode == "resourcefulness",
    "Auto stat gear did not choose the higher-profit captured setup")
selectedMetrics, selectedMode = Engine.SelectGearMetrics(
    { expectedConsumedCostFull = 800 }, { expectedConsumedCostFull = 750 })
assert(selectedMode == "resourcefulness",
    "unpriced Auto stat gear did not choose the lower expected cost")
selectedMetrics, selectedMode = Engine.SelectGearMetrics(mcMetrics, {
    profit = 100,
    expectedConsumedCostFull = 800,
})
assert(selectedMetrics == mcMetrics and selectedMode == "multicraft",
    "Auto stat gear tie-breaking is not deterministic")

local rootStage = { id = "ink" }
local millingStage = { id = "milling" }
local stageStats = {
    GetGearModeForStrat = function(strat)
        return strat == millingStage and "resourcefulness" or "multicraft"
    end,
}
assert(Engine.ResolveStageGearMode(
        stageStats, rootStage, "midnight-1", rootStage, "multicraft") == "multicraft",
    "root stage did not use its Multicraft override")
assert(Engine.ResolveStageGearMode(
        stageStats, millingStage, "midnight-1", rootStage, "multicraft") == "resourcefulness",
    "VI producer did not retain its own Resourcefulness gear plan")
local strategy = {
    id = "test__commodity__midnight_1",
    recipeID = 424242,
}

local request, requestErr = Contract.BuildRequest({
    strategy = strategy,
    useVerticalIntegration = true,
})
assert(request, requestErr)
assert(request.contractVersion == 1, "request contract version")
assert(request.craftScale == 1, "request craft-scale default")
assert(request.inputQuantityOverride == nil and request.craftsOverride == nil,
    "request batch-override defaults")
assert(request.materialRank == "lowest", "request rank default")
assert(request.pricingMode == "exhaust_materials", "request pricing-mode default")
assert(request.inventoryPolicy == "opportunity_cost", "request inventory policy")
assert(request.pricePolicy == "runtime_market", "request price policy")
assert(request.useVerticalIntegration == true, "request VI policy")
assert(request.fillQuantity == 50, "request fill default")
AssertNear(request.auctionHouseCut, 0.05, "request AH cut")

local invalidRequest, invalidRequestErr = Contract.BuildRequest({
    strategy = strategy,
    materialRank = "surprise_rank",
})
assert(invalidRequest == nil and invalidRequestErr:find("materialRank", 1, true),
    "unsupported material rank was accepted")

local optimalRequest, optimalRequestErr = Contract.BuildRequest({
    strategy = strategy,
    materialRank = "optimal",
})
assert(optimalRequest and not optimalRequestErr and optimalRequest.materialRank == "optimal",
    "verified mixed-rank material policy was rejected")

invalidRequest, invalidRequestErr = Contract.BuildRequest({
    strategy = strategy,
    craftScale = 0,
})
assert(invalidRequest == nil and invalidRequestErr:find("craftScale", 1, true),
    "zero craft scale was accepted")

invalidRequest, invalidRequestErr = Contract.BuildRequest({
    strategy = strategy,
    craftsOverride = -1,
})
assert(invalidRequest == nil and invalidRequestErr:find("craftsOverride", 1, true),
    "negative saved crafts override was accepted")

local craftSimRequest, craftSimRequestErr = Contract.BuildRequest({
    strategy = strategy,
    pricePolicy = "craftsim_then_market",
})
assert(craftSimRequest, craftSimRequestErr)
assert(craftSimRequest.pricePolicy == "craftsim_then_market",
    "CraftSim price policy was rejected")

local formula = {
    pricingMode = "exhaust_materials",
    effectiveCrafts = 105.7,
}
local recipeReagents = {
    { itemID = 1001, required = 100, unitPrice = 1000 },
}
local shoppingReagents = {
    { itemID = 1002, required = 80, have = 20, needToBuy = 60, unitPrice = 1200 },
}
local metrics = {
    model = "v2",
    startingAmount = 100,
    crafts = 100,
    reagents = shoppingReagents,
    costReagents = recipeReagents,
    output = {
        itemID = 2001,
        expectedQtyRaw = 125,
        expectedQty = 125,
        unitPrice = 2000,
    },
    requiredCostFull = 100000,
    expectedConsumedCostFull = 100000,
    averageSavedCost = 0,
    totalCostToBuy = 72000,
    netRevenue = 237500,
    profit = 137500,
    roi = 137.5,
    breakEvenSell = 842.1052631579,
    missingPrices = {},
    hasStale = false,
    formula = formula,
    statUsages = { { recipeID = 424242, source = "test" } },
    economicChoices = { [1002] = { source = "direct" } },
}

local result, resultErr = Contract.FromV2Metrics(request, metrics)
assert(result, resultErr)
assert(result.engine == "commodity_expected_value", "canonical engine identity")
assert(result.strategyID == strategy.id and result.recipeID == strategy.recipeID,
    "canonical recipe identity")
assert(result.crafts == 100 and result.effectiveCrafts == 105.7,
    "planned and effective crafts are distinct")
assert(result.recommendedCrafts == 105,
    "actionable craft recommendation must conservatively floor expected attempts")
assert(result.expectedOutput == 125, "primary expected output")
assert(result.requiredCostFull == 100000, "required material budget cost")
assert(result.expectedConsumedCostFull == 100000, "expected consumed cost")
assert(result.buyNowCost == 72000, "owned inventory affects buy-now cost")
assert(result.shoppingReagents == shoppingReagents, "shopping reagent plan")
assert(result.recipeReagents == recipeReagents, "direct recipe reagent plan")
AssertNear(result.profitPerCraft, 1375, "profit per planned craft")
assert(result.diagnostics.formula == formula, "formula diagnostics")
assert(result.totalCostFull == nil, "ambiguous totalCostFull alias leaked into contract")
assert(result.costReagents == nil, "legacy costReagents alias leaked into contract")
assert(result.deltas == nil, "non-contract diagnostics leaked into production contract")

metrics.model = "v2-shadow"
local rejectedShadow, rejectedShadowErr = Contract.FromV2Metrics(request, metrics)
assert(rejectedShadow == nil and rejectedShadowErr:find("V2 pricing engine", 1, true),
    "retired shadow metrics were accepted")
metrics.model = "v2"

local valid, validationErr = Contract.ValidateResult(result, request)
assert(valid, validationErr)

local originalProfit = result.profit
result.profit = originalProfit + 1
valid, validationErr = Contract.ValidateResult(result, request)
assert(not valid and validationErr:find("netRevenue", 1, true),
    "inconsistent profit was accepted")
result.profit = originalProfit

local originalBreakEven = result.breakEvenSell
result.breakEvenSell = originalBreakEven + 1
valid, validationErr = Contract.ValidateResult(result, request)
assert(not valid and validationErr:find("breakEvenSell", 1, true),
    "inconsistent break-even was accepted")
result.breakEvenSell = originalBreakEven

local originalMode = result.diagnostics.formula.pricingMode
result.diagnostics.formula.pricingMode = "fixed_crafts"
valid, validationErr = Contract.ValidateResult(result, request)
assert(not valid and validationErr:find("pricing mode", 1, true),
    "mismatched formula pricing mode was accepted")
result.diagnostics.formula.pricingMode = originalMode

local missingPriceMetrics = {
    model = "v2",
    startingAmount = 10,
    crafts = 10,
    reagents = {},
    costReagents = {},
    output = { itemID = 2001, expectedQtyRaw = 10 },
    requiredCostFull = 0,
    expectedConsumedCostFull = 0,
    averageSavedCost = 0,
    totalCostToBuy = 0,
    missingPrices = { "Output" },
    hasStale = false,
    formula = { effectiveCrafts = 10 },
}
local missingPriceResult, missingPriceErr = Contract.FromV2Metrics(request, missingPriceMetrics)
assert(missingPriceResult, missingPriceErr)
assert(missingPriceResult.profit == nil and missingPriceResult.roi == nil,
    "unpriced result fabricated economic metrics")

local legacyResult, legacyErr = Contract.FromV2Metrics(request, {
    model = "legacy",
})
assert(legacyResult == nil and legacyErr:find("V2", 1, true),
    "legacy metrics crossed the canonical contract")

print("PASS: commodity pricing request/result contract")
