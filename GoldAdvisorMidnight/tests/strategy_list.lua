-- Integration fixture for the canonical facade-backed main strategy list.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {
    UI = {},
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

local strategies = {
    { id = "profitable", recipeID = 1, stratName = "Profitable", profession = "Alchemy" },
    { id = "unprofitable", recipeID = 2, stratName = "Unprofitable", profession = "Alchemy" },
    { id = "missing", recipeID = 3, stratName = "Missing", profession = "Alchemy" },
    { id = "stale", recipeID = 4, stratName = "Stale", profession = "Alchemy" },
    { id = "multi", recipeID = 5, stratName = "Multi-output", profession = "Alchemy" },
    { id = "hidden", recipeID = 6, stratName = "Hidden", profession = "Engineering" },
}

local results = {
    profitable = { profit = 50000, roi = 50, missingPrices = {}, hasStale = false },
    unprofitable = { profit = -50000, roi = -50, missingPrices = {}, hasStale = false },
    missing = { profit = nil, roi = nil, missingPrices = { "Output" }, hasStale = false },
    stale = { profit = 25000, roi = 25, missingPrices = {}, hasStale = true },
    multi = {
        profit = 90000,
        roi = 90,
        missingPrices = {},
        hasStale = false,
        outputs = { { itemID = 1 }, { itemID = 2 } },
    },
    hidden = { profit = 999999, roi = 999, missingPrices = {}, hasStale = false },
}

local calls = {}
local activeCalls = 0
local function BuildV2Metrics(strategyID)
    local fixture = results[strategyID]
    local outputs = nil
    local output = {
        itemID = 2000,
        expectedQtyRaw = 100,
        expectedQty = 100,
    }
    if strategyID == "multi" then
        outputs = {
            output,
            { itemID = 2001, expectedQtyRaw = 25, expectedQty = 25 },
        }
    end
    local breakEvenSell = 100000 / 95
    if outputs then
        breakEvenSell = nil
    end
    return {
        model = "v2",
        startingAmount = 100,
        crafts = 100,
        reagents = {},
        costReagents = {},
        output = output,
        outputs = outputs,
        requiredCostFull = 100000,
        expectedConsumedCostFull = 100000,
        averageSavedCost = 0,
        totalCostToBuy = 100000,
        netRevenue = fixture.profit and (100000 + fixture.profit) or nil,
        profit = fixture.profit,
        roi = fixture.roi,
        breakEvenSell = breakEvenSell,
        missingPrices = fixture.missingPrices,
        hasStale = fixture.hasStale,
        formula = { pricingMode = "exhaust_materials", effectiveCrafts = 100 },
        statUsages = {},
        economicChoices = {},
    }
end

GAM.Pricing = {
    CalculateStratMetricsV2 = function(strategy)
        calls[strategy.id] = (calls[strategy.id] or 0) + 1
        return BuildV2Metrics(strategy.id)
    end,
    CalculateStratMetricsActive = function()
        activeCalls = activeCalls + 1
        return nil
    end,
}

LoadModule("PricingContract.lua")
LoadModule("PricingFacade.lua")
LoadModule("UI/MainWindowV2Common.lua")
LoadModule("UI/CrushingAnalyzerWindow.lua")
LoadModule("UI/StrategyListModel.lua")

local ListModel = assert(GAM.UI.StrategyListModel, "StrategyListModel unavailable")
local Common = assert(GAM.UI.MainWindowV2Common, "MainWindowV2Common unavailable")

for _, width in ipairs({ 410, 840 }) do
    local columns = Common.BuildRuntimeColumns(width)
    assert(#columns == 3, "strategy list did not keep three stable columns at width " .. width)
    assert(columns[1].id == "stratName"
            and columns[2].id == "profit"
            and columns[3].id == "roi",
        "strategy list column order changed at width " .. width)
    assert(columns[2].j == "RIGHT" and columns[3].j == "RIGHT",
        "strategy list numeric columns are not right-aligned")
    assert(columns[1].w > 0 and columns[2].w >= 118 and columns[3].w == 68,
        "strategy list produced an invalid responsive width")
    assert(columns[3].x + columns[3].w <= width - 28,
        "strategy list did not reserve its right-side control gutter")
end

local CrushingWindow = assert(GAM.UI.CrushingAnalyzerWindow, "CrushingAnalyzerWindow unavailable")
assert(CrushingWindow.GetCompactHeight(0) == 168, "empty Crushing Analyzer height changed")
assert(CrushingWindow.GetCompactHeight(8) == 278, "eight-row Crushing Analyzer did not compact")
assert(CrushingWindow.GetCompactHeight(20) == 340, "Crushing Analyzer height cap changed")

local cache = ListModel.NewMetricCache(function(strategy, patchTag)
    return GAM.PricingFacade.CalculateCurrent(strategy, patchTag)
end)

local signature = "rank=lowest|mode=exhaust_materials"
local first = cache:Get(strategies[1], "midnight-1", signature)
local second = cache:Get(strategies[1], "midnight-1", signature)
assert(first.engine == "commodity_expected_value" and second == first,
    "canonical facade result changed in cache")
assert(first.profit == results.profitable.profit and first.roi == results.profitable.roi,
    "canonical facade changed visible profit or ROI")
assert(calls.profitable == 1, "strategy metric was recalculated inside one list snapshot")

cache:Invalidate("profitable", "midnight-1")
cache:Get(strategies[1], "midnight-1", signature)
assert(calls.profitable == 2, "strategy-specific invalidation did not reprice")

cache:Get(strategies[1], "midnight-1", signature .. "|rank=highest")
assert(calls.profitable == 3, "list-state signature change did not reset the cache")

for _, strategy in ipairs(strategies) do
    if strategy.id ~= "hidden" then
        local result, err = cache:Get(strategy, "midnight-1", signature)
        assert(result, strategy.id .. ": canonical list fixture failed: " .. tostring(err))
    end
end

local visible = ListModel.BuildVisibleList({
    strategies = strategies,
    matches = function(strategy)
        return strategy.profession == "Alchemy"
    end,
    isFavorite = function(strategyID)
        return strategyID == "unprofitable"
    end,
    getMetric = function(strategy)
        return cache:Get(strategy, "midnight-1", signature)
    end,
    sortKey = "roi",
    sortAscending = true,
})

local expectedROIOrder = { "unprofitable", "multi", "profitable", "stale", "missing" }
assert(#visible == #expectedROIOrder, "profession visibility filter returned the wrong count")
for index, strategyID in ipairs(expectedROIOrder) do
    assert(visible[index].id == strategyID,
        string.format("ROI order %d: expected %s, got %s", index, strategyID, visible[index].id))
end
assert(calls.hidden == nil, "hidden strategy was priced")
local missingResult = cache:Get(strategies[3], "midnight-1", signature)
local staleResult = cache:Get(strategies[4], "midnight-1", signature)
local multiResult = cache:Get(strategies[5], "midnight-1", signature)
assert(missingResult.profit == nil and #missingResult.missingPrices == 1,
    "missing-price state changed in the list")
assert(staleResult.hasStale, "stale-price state changed in the list")
assert(#multiResult.outputs == 2, "multi-output result changed in the list")

visible = ListModel.BuildVisibleList({
    strategies = strategies,
    matches = function(strategy)
        return strategy.profession == "Alchemy"
    end,
    getMetric = function(strategy)
        return cache:Get(strategy, "midnight-1", signature)
    end,
    sortKey = "profit",
    sortAscending = true,
})

local expectedProfitOrder = { "multi", "profitable", "stale", "unprofitable", "missing" }
for index, strategyID in ipairs(expectedProfitOrder) do
    assert(visible[index].id == strategyID,
        string.format("profit order %d: expected %s, got %s", index, strategyID, visible[index].id))
end
assert(activeCalls == 0, "strategy list reached the legacy-capable active pricing engine")

print("PASS: canonical strategy-list cache, visibility, and sorting")
