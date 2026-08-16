-- Integration fixture for the canonical facade-backed base strategy detail.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = { UI = {} }

local function LoadModule(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk(ADDON_NAME, GAM)
end

local function AssertEqual(actual, expected, label)
    assert(actual == expected,
        string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

LoadModule("UI/StrategyDetailModel.lua")
local Model = assert(GAM.UI.StrategyDetailModel, "StrategyDetailModel unavailable")

local function BuildCanonicalResult(overrides)
    local result = {
        contractVersion = 1,
        engine = "commodity_expected_value",
        strategyID = "detail-fixture",
        patchTag = "midnight-1",
        pricingMode = "exhaust_materials",
        crafts = 100,
        effectiveCrafts = 112.5,
        recommendedCrafts = 112,
        gearModeRequested = "auto",
        gearModeResolved = "multicraft",
        gearPresetMissing = false,
        requiredCostFull = 100000,
        expectedConsumedCostFull = 90000,
        buyNowCost = 70000,
        netRevenue = 150000,
        profit = 60000,
        roi = 66.6667,
        breakEvenSell = 947.37,
        shoppingReagents = {
            { itemID = 1001, name = "Input", required = 100, needToBuy = 70, unitPrice = 1000 },
        },
        outputs = {
            { itemID = 2001, name = "Output", expectedQty = 150, expectedQtyRaw = 150, netRevenue = 150000 },
        },
        missingPrices = {},
        hasStale = false,
        diagnostics = {
            formula = {
                profileKey = "alchemy",
                statSource = "craftsim_recipe",
                crafterUID = "AltCrafter-TestRealm",
                crafterName = "AltCrafter",
                crafterRealm = "TestRealm",
                crossCharacter = true,
                supportsMulticraft = true,
                supportsResourcefulness = true,
                mcPercent = 0.12,
                mcExtra = 0.25,
                resPercent = 0.08,
                resExtra = 0.20,
                nodeBonusDetails = {
                    status = "resolved",
                    profession = "Alchemy",
                    recipeID = 424242,
                    multicraft = {
                        extra = 0.25,
                        nodes = {
                            { nodeID = 107060, name = "Multicraft Extra Items +20%", rank = 1, extra = 0.20 },
                            { nodeID = 107077, name = "Multicraft Extra Items +5%", rank = 1, extra = 0.05 },
                        },
                    },
                    resourcefulness = {
                        extra = 0,
                        nodes = {},
                    },
                },
            },
            statUsages = {},
            economicChoices = {},
        },
    }
    for key, value in pairs(overrides or {}) do
        result[key] = value
    end
    return result
end

local legacyVisible = {
    totalCostFull = 100000,
    expectedConsumedCostFull = 90000,
    totalCostToBuy = 70000,
    netRevenue = 150000,
    profit = 60000,
    roi = 66.6667,
    breakEvenSell = 947.37,
}

local projection = assert(Model.Project(BuildCanonicalResult()))
AssertEqual(projection.cost, legacyVisible.totalCostFull, "visible required cost parity")
AssertEqual(projection.expectedCost, legacyVisible.expectedConsumedCostFull, "visible expected cost parity")
AssertEqual(projection.buyNowCost, legacyVisible.totalCostToBuy, "visible buy-now parity")
AssertEqual(projection.revenue, legacyVisible.netRevenue, "visible revenue parity")
AssertEqual(projection.profit, legacyVisible.profit, "visible profit parity")
AssertEqual(projection.roi, legacyVisible.roi, "visible ROI parity")
AssertEqual(projection.breakEvenSell, legacyVisible.breakEvenSell, "visible break-even parity")
AssertEqual(#projection.reagents, 1, "shopping reagent rows")
AssertEqual(#projection.outputs, 1, "single-output rows")
assert(projection.statsCaption:find("MC 12%", 1, true), "visible Multicraft caption missing")
assert(projection.statsCaption:find("100 -> 112 crafts", 1, true),
    "whole-craft recommendation caption missing")
assert(projection.statsTooltip:find("expected-value attempts 112.5", 1, true),
    "precise expected attempts tooltip missing")
AssertEqual(projection.gearCaption, "Auto: Multicraft", "auto gear resolution caption")
assert(projection.statsTooltip:find("Using stats captured from this recipe", 1, true),
    "plain-language stat source tooltip missing")
assert(projection.statsTooltip:find("Crafter: AltCrafter (saved)", 1, true),
    "cached crafter tooltip missing")
AssertEqual(projection.crafterCaption, "AltCrafter (cached)",
    "cached crafter caption")
assert(projection.statsTooltip:find("extra items 25%", 1, true),
    "Multicraft bonus tooltip missing")
assert(projection.nodeBonusCaption:find("MC extra +25%", 1, true),
    "applied node caption missing")
assert(projection.nodeBonusCaption:find("Res save unchanged", 1, true),
    "zero-rank node caption missing")
assert(projection.nodeBonusTooltip:find("Multicraft Extra Items +20%", 1, true),
    "applied node tooltip missing node name")
assert(not projection.nodeBonusTooltip:find("107060", 1, true),
    "internal node ID leaked into the end-user tooltip")

local pendingResult = BuildCanonicalResult()
pendingResult.diagnostics.formula.nodeBonusDetails = {
    status = "not-captured",
    profession = "Alchemy",
    recipeID = 424242,
}
local pending = assert(Model.Project(pendingResult))
AssertEqual(pending.nodeBonusCaption,
    "Not updated yet — using saved defaults", "uncaptured node diagnostic")
assert(pending.nodeBonusTooltip:find("Open this recipe", 1, true),
    "uncaptured node refresh guidance missing")

local unprofitable = assert(Model.Project(BuildCanonicalResult({ profit = -50000, roi = -50 })))
AssertEqual(unprofitable.profit, -50000, "unprofitable value")
AssertEqual(unprofitable.roi, -50, "unprofitable ROI")

local missingResult = BuildCanonicalResult({ missingPrices = { "Input" } })
missingResult.profit = nil
missingResult.roi = nil
local missing = assert(Model.Project(missingResult))
AssertEqual(missing.profit, nil, "missing-price profit")
AssertEqual(#missing.missingPrices, 1, "missing-price rows")

local stale = assert(Model.Project(BuildCanonicalResult({ hasStale = true })))
assert(stale.hasStale, "stale-price state was lost")

local multiResult = BuildCanonicalResult({
    outputs = {
        { itemID = 2001, name = "Primary", expectedQty = 100 },
        { itemID = 2002, name = "Secondary", expectedQty = 25 },
    },
})
multiResult.breakEvenSell = nil
local multi = assert(Model.Project(multiResult))
AssertEqual(#multi.outputs, 2, "multi-output rows")
AssertEqual(multi.breakEvenSell, nil, "multi-output break-even")

local fixedCrafts = assert(Model.Project(BuildCanonicalResult({
    pricingMode = "fixed_crafts",
    effectiveCrafts = 100,
})))
assert(fixedCrafts.statsCaption:find("Fixed Crafts", 1, true), "fixed-crafts caption missing")

local invalid, invalidErr = Model.Project({ engine = "legacy" })
assert(invalid == nil and invalidErr, "legacy result entered canonical detail projection")

local snapshot = assert(Model.CreateSnapshot(BuildCanonicalResult()))
AssertEqual(snapshot.projection.cost, 100000, "snapshot canonical display cost")
AssertEqual(snapshot.projection.profit, 60000, "snapshot canonical display profit")
assert(snapshot.canonicalResult.engine == "commodity_expected_value",
    "snapshot did not preserve the canonical result")

local directInputs = assert(Model.Project(BuildCanonicalResult({
    shoppingReagents = {
        { itemID = 3001, name = "Crafted Intermediate", required = 100 },
    },
})))
local viInputs = assert(Model.Project(BuildCanonicalResult({
    shoppingReagents = {
        { itemID = 3002, name = "Raw Leaf A", required = 250 },
        { itemID = 3003, name = "Raw Leaf B", required = 500 },
    },
})))
AssertEqual(#directInputs.reagents, 1, "VI-off direct input projection")
AssertEqual(directInputs.reagents[1].itemID, 3001, "VI-off direct input identity")
AssertEqual(#viInputs.reagents, 2, "VI-on expanded input projection")
AssertEqual(viInputs.reagents[1].itemID, 3002, "VI-on replaced stale direct input")

print("PASS: canonical base-detail projection and visible-value parity")
