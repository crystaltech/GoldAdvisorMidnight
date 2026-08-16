-- Boundary/parity fixtures for the authoritative commodity pricing facade.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {
    C = {
        DEFAULT_PATCH = "midnight-1",
        DEFAULT_RANK_POLICY = "lowest",
        DEFAULT_V2_PRICING_MODE = "exhaust_materials",
        DEFAULT_FILL_QTY = 50,
        AH_CUT = 0.05,
    },
    db = {
        options = {
            rankPolicy = "lowest",
            v2PricingMode = "exhaust_materials",
            priceSource = "ah",
            pigmentCostSource = "ah",
            ingotCostSource = "ah",
            boltCostSource = "ah",
            shallowFillQty = 50,
            ahCut = 0.05,
        },
        patch = {
            ["midnight-1"] = {
                inputQtyOverrides = {},
                craftsOverrides = {},
            },
        },
    },
}

function GAM:GetOptions()
    return self.db.options
end

function GAM:GetPatchDB(patchTag)
    return self.db.patch[patchTag]
end

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

local strategy = {
    id = "test__facade__midnight_1",
    recipeID = 424242,
}

local function SingleOutputMetrics(values)
    local crafts = values.crafts or 100
    local expectedOutput = values.expectedOutput or 100
    local consumedCost = values.consumedCost or 100000
    local revenue = values.revenue
    local missingPrices = values.missingPrices or {}
    local profit = revenue and #missingPrices == 0 and (revenue - consumedCost) or nil
    local roi = profit and consumedCost > 0 and (profit / consumedCost * 100) or nil
    return {
        model = "v2",
        startingAmount = crafts,
        crafts = crafts,
        reagents = values.shoppingReagents or {},
        costReagents = values.recipeReagents or {},
        output = {
            itemID = 2001,
            expectedQtyRaw = expectedOutput,
            expectedQty = math.floor(expectedOutput + 0.5),
            unitPrice = values.unitPrice,
            isStale = values.outputStale and true or false,
            missingPrice = values.outputMissing and true or false,
        },
        requiredCostFull = values.requiredCost or consumedCost,
        expectedConsumedCostFull = consumedCost,
        averageSavedCost = values.savedCost or 0,
        totalCostToBuy = values.buyNowCost or consumedCost,
        netRevenue = revenue,
        profit = profit,
        roi = roi,
        breakEvenSell = consumedCost > 0
            and (consumedCost / (expectedOutput * 0.95))
            or nil,
        missingPrices = missingPrices,
        hasStale = values.hasStale and true or false,
        formula = {
            pricingMode = "exhaust_materials",
            effectiveCrafts = values.effectiveCrafts or crafts,
        },
        statUsages = {},
        economicChoices = {},
    }
end

local fixtures = {
    {
        name = "profitable",
        metrics = SingleOutputMetrics({ revenue = 150000, unitPrice = 1579 }),
        expectedProfit = 50000,
        expectedROI = 50,
    },
    {
        name = "unprofitable",
        metrics = SingleOutputMetrics({ revenue = 50000, unitPrice = 526 }),
        expectedProfit = -50000,
        expectedROI = -50,
    },
    {
        name = "missing-price",
        metrics = SingleOutputMetrics({
            revenue = nil,
            outputMissing = true,
            missingPrices = { "Output" },
        }),
        expectedMissing = true,
    },
    {
        name = "stale-price",
        metrics = SingleOutputMetrics({
            revenue = 150000,
            unitPrice = 1579,
            hasStale = true,
            outputStale = true,
        }),
        expectedProfit = 50000,
        expectedROI = 50,
        expectedStale = true,
    },
    {
        name = "multi-output",
        metrics = {
            model = "v2",
            startingAmount = 100,
            crafts = 100,
            reagents = {},
            costReagents = {},
            output = { itemID = 3001, expectedQtyRaw = 60, expectedQty = 60 },
            outputs = {
                { itemID = 3001, expectedQtyRaw = 60, expectedQty = 60, netRevenue = 114000 },
                { itemID = 3002, expectedQtyRaw = 40, expectedQty = 40, netRevenue = 76000 },
            },
            requiredCostFull = 100000,
            expectedConsumedCostFull = 100000,
            averageSavedCost = 0,
            totalCostToBuy = 100000,
            netRevenue = 190000,
            profit = 90000,
            roi = 90,
            breakEvenSell = nil,
            missingPrices = {},
            hasStale = false,
            formula = { pricingMode = "exhaust_materials", effectiveCrafts = 100 },
            statUsages = {},
            economicChoices = {},
        },
        expectedProfit = 90000,
        expectedROI = 90,
        expectedOutputs = 2,
    },
}

local currentMetrics = nil
local v2Calls = 0
local activeCalls = 0
local viAdapterCalls = 0
local crushingAdapterCalls = 0
GAM.Pricing = {
    CalculateStratMetricsV2 = function(receivedStrategy, patchTag, craftScale)
        assert(receivedStrategy == strategy, "facade changed strategy identity")
        assert(patchTag == "midnight-1", "facade changed patch tag")
        assert(craftScale == 1, "facade changed craft scale")
        v2Calls = v2Calls + 1
        return currentMetrics
    end,
    CalculateStratMetricsActive = function()
        activeCalls = activeCalls + 1
        return currentMetrics
    end,
    GetVIBreakdownData = function(receivedStrategy, patchTag, canonicalResult)
        assert(receivedStrategy == strategy, "VI adapter changed strategy identity")
        assert(patchTag == "midnight-1", "VI adapter changed patch tag")
        assert(canonicalResult.engine == "commodity_expected_value",
            "VI adapter received compatibility metrics")
        viAdapterCalls = viAdapterCalls + 1
        return { kind = "vi", profit = canonicalResult.profit }
    end,
    GetCrushingAnalyzerData = function(receivedStrategy, patchTag, canonicalResult)
        assert(receivedStrategy == strategy, "crushing adapter changed strategy identity")
        assert(patchTag == "midnight-1", "crushing adapter changed patch tag")
        assert(canonicalResult.engine == "commodity_expected_value",
            "crushing adapter received compatibility metrics")
        crushingAdapterCalls = crushingAdapterCalls + 1
        return { kind = "crushing", profit = canonicalResult.profit }
    end,
}

LoadModule("PricingContract.lua")
LoadModule("PricingFacade.lua")

local Facade = assert(GAM.PricingFacade, "PricingFacade unavailable")
local request, requestErr = Facade.BuildCurrentRequest(strategy)
assert(request, requestErr)
assert(request.pricePolicy == "runtime_market", "AH request price policy")
assert(request.useVerticalIntegration == false, "VI request default")

local lastCanonicalResult = nil
for _, fixture in ipairs(fixtures) do
    currentMetrics = fixture.metrics
    local result, resultErr = Facade.Calculate(request)
    assert(result, fixture.name .. ": " .. tostring(resultErr))
    lastCanonicalResult = result
    assert(result.profit == fixture.metrics.profit,
        fixture.name .. ": profit changed at facade boundary")
    assert(result.roi == fixture.metrics.roi,
        fixture.name .. ": ROI changed at facade boundary")
    assert(result.hasStale == fixture.metrics.hasStale,
        fixture.name .. ": stale state changed at facade boundary")
    assert(#result.missingPrices == #fixture.metrics.missingPrices,
        fixture.name .. ": missing-price state changed at facade boundary")
    assert(result.requiredCostFull == fixture.metrics.requiredCostFull,
        fixture.name .. ": required cost changed at facade boundary")
    assert(result.buyNowCost == fixture.metrics.totalCostToBuy,
        fixture.name .. ": buy-now cost changed at facade boundary")
    assert(result.expectedOutput == fixture.metrics.output.expectedQtyRaw,
        fixture.name .. ": primary expected output changed at facade boundary")
    if fixture.expectedProfit then
        assert(result.profit == fixture.expectedProfit, fixture.name .. ": expected profit")
        AssertNear(result.roi, fixture.expectedROI, fixture.name .. ": expected ROI")
    end
    if fixture.expectedMissing then
        assert(result.profit == nil and result.roi == nil,
            fixture.name .. ": missing prices fabricated profit")
    end
    if fixture.expectedStale then
        assert(result.hasStale, fixture.name .. ": stale flag lost")
    end
    if fixture.expectedOutputs then
        assert(#result.outputs == fixture.expectedOutputs,
            fixture.name .. ": multi-output rows changed")
        assert(result.breakEvenSell == nil,
            fixture.name .. ": multi-output result gained one break-even price")
    end
end

assert(v2Calls == #fixtures, "facade did not call V2 exactly once per fixture")
assert(activeCalls == 0, "facade called the legacy-capable active engine")

local viResult = Facade.GetCurrentVIBreakdown(strategy, "midnight-1", lastCanonicalResult)
local crushingResult = Facade.GetCurrentCrushingAnalyzer(strategy, "midnight-1", lastCanonicalResult)
assert(viResult and viResult.kind == "vi", "canonical VI adapter failed")
assert(crushingResult and crushingResult.kind == "crushing", "canonical crushing adapter failed")
assert(viAdapterCalls == 1 and crushingAdapterCalls == 1,
    "specialized analyzer adapters were not called exactly once")
assert(v2Calls == #fixtures, "analyzer adapters recalculated a supplied canonical result")
assert(activeCalls == 0, "analyzer adapters called the legacy-capable active engine")

GAM.db.options.rankPolicy = "highest"
local rejected, rejectedErr = Facade.Calculate(request)
assert(rejected == nil and rejectedErr == "request-current-state-mismatch:materialRank",
    "stale request was not rejected after an option change")
GAM.db.options.rankPolicy = "lowest"

GAM.db.options.priceSource = "craftsim"
local craftSimRequest, craftSimErr = Facade.BuildCurrentRequest(strategy)
assert(craftSimRequest, craftSimErr)
assert(craftSimRequest.pricePolicy == "craftsim_then_market",
    "CraftSim price-source policy was not preserved")
GAM.db.options.priceSource = "ah"

GAM.db.options.v2PricingMode = "fixed_crafts"
local fixedMetrics = SingleOutputMetrics({
    revenue = 145000,
    requiredCost = 100000,
    consumedCost = 90000,
    savedCost = 10000,
})
fixedMetrics.formula.pricingMode = "fixed_crafts"
fixedMetrics.formula.effectiveCrafts = fixedMetrics.crafts
currentMetrics = fixedMetrics
local fixedRequest, fixedRequestErr = Facade.BuildCurrentRequest(strategy)
assert(fixedRequest, fixedRequestErr)
assert(fixedRequest.pricingMode == "fixed_crafts", "fixed-crafts request mode")
local fixedResult, fixedResultErr = Facade.Calculate(fixedRequest)
assert(fixedResult, fixedResultErr)
assert(fixedResult.expectedConsumedCostFull == 90000,
    "fixed-crafts consumed cost changed at facade boundary")
assert(fixedResult.averageSavedCost == 10000,
    "fixed-crafts saved cost changed at facade boundary")
GAM.db.options.v2PricingMode = "fixed_input"
local legacyAliasRequest, legacyAliasErr = Facade.BuildCurrentRequest(strategy)
assert(legacyAliasRequest, legacyAliasErr)
assert(legacyAliasRequest.pricingMode == "exhaust_materials",
    "fixed-input compatibility alias did not normalize to exhaust materials")
GAM.db.options.v2PricingMode = "exhaust_materials"

GAM.db.patch["midnight-1"].craftsOverrides[strategy.id] = 250
local overrideRequest, overrideErr = Facade.BuildCurrentRequest(strategy)
assert(overrideRequest, overrideErr)
assert(overrideRequest.craftsOverride == 250, "saved crafts override was not snapshotted")
GAM.db.patch["midnight-1"].craftsOverrides[strategy.id] = nil
rejected, rejectedErr = Facade.Calculate(overrideRequest)
assert(rejected == nil and rejectedErr == "request-current-state-mismatch:craftsOverride",
    "stale saved batch override was not rejected")

print("PASS: authoritative pricing facade parity fixtures")
