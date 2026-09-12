-- Offline golden calculations for the mass-crafting formula models.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {}
local TestLoader = assert(loadfile("../tests/TestLoader.lua"))()

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

TestLoader.LoadModuleWithFixture(
    "PricingFormula.lua",
    "../tests/fixtures/PricingFormulaSmoke.lua",
    ADDON_NAME,
    GAM)

local Formula = assert(GAM.PricingFormula, "PricingFormula unavailable")
assert(GAM.PricingV2Formula == Formula, "legacy pricing-formula alias is unavailable")

local noStats = Formula.CalculateExhaustMaterials({
    crafts = 100,
    baseYield = 1,
    requiredCraftCost = 100000,
})
assert(noStats.model == "exhaustMaterials", "Exhaust Materials model name")
AssertNear(noStats.effectiveCrafts, 100, "no-stats effective crafts")
AssertNear(noStats.expectedYieldPerActualCraft, 1, "no-stats actual yield")
AssertNear(noStats.expectedOutput, 100, "no-stats output")
AssertNear(noStats.expectedConsumedCost, 100000, "no-stats input budget")

local resourcefulnessOnly = Formula.CalculateExhaustMaterials({
    crafts = 100,
    baseYield = 1,
    resPercent = 0.15,
    resExtra = 0.10,
    supportsResourcefulness = true,
})
AssertNear(resourcefulnessOnly.resourceSaveFraction, 0.33,
    "Resourcefulness save fraction")
AssertNear(resourcefulnessOnly.consumptionFactor, 0.9505,
    "Resourcefulness consumption factor")
AssertNear(resourcefulnessOnly.effectiveCrafts, 105.207785376,
    "Resourcefulness reinvested crafts")
AssertNear(resourcefulnessOnly.expectedOutput, 105.207785376,
    "Resourcefulness-only output")

local multicraftOnly = Formula.CalculateExhaustMaterials({
    crafts = 100,
    baseYield = 1,
    mcPercent = 0.20,
    mcExtra = 0.25,
    supportsMulticraft = true,
})
AssertNear(multicraftOnly.mcConstant, 2.1, "base-yield-one Multicraft constant")
AssertNear(multicraftOnly.expectedExtraOnProc, 1.8125,
    "Multicraft average extra on proc")
AssertNear(multicraftOnly.expectedYieldPerActualCraft, 1.3625,
    "Multicraft actual yield")
AssertNear(multicraftOnly.expectedOutput, 136.25, "Multicraft-only output")

local both = Formula.CalculateExhaustMaterials({
    crafts = 100,
    baseYield = 1,
    mcPercent = 0.20,
    mcExtra = 0.25,
    resPercent = 0.15,
    resExtra = 0.10,
    supportsMulticraft = true,
    supportsResourcefulness = true,
    requiredCraftCost = 250000,
})
AssertNear(both.effectiveCrafts, 105.207785376, "combined effective crafts")
AssertNear(both.expectedYieldPerActualCraft, 1.3625, "combined actual yield")
AssertNear(both.expectedOutput, 143.345607575, "combined output")
AssertNear(both.expectedConsumedCost, 250000, "combined full material budget")
AssertNear(both.averageSavedCost, 0, "combined no double-counted savings")

local unsupported = Formula.CalculateExhaustMaterials({
    crafts = 100,
    baseYield = 2,
    mcPercent = 1,
    resPercent = 1,
    mcExtra = 1,
    resExtra = 1,
    supportsMulticraft = false,
    supportsResourcefulness = false,
})
AssertNear(unsupported.effectiveCrafts, 100, "unsupported stats effective crafts")
AssertNear(unsupported.expectedOutput, 200, "unsupported stats output")

local fixed = Formula.CalculateFixedCrafts({
    crafts = 100,
    baseYield = 1,
    mcPercent = 0.20,
    resPercent = 0.15,
    requiredCraftCost = 250000,
    supportsMulticraft = true,
    supportsResourcefulness = true,
})
AssertNear(fixed.effectiveCrafts, 100, "fixed-crafts attempt count")
assert(fixed.expectedOutput < both.expectedOutput,
    "Exhaust Materials should produce more than Fixed Crafts when Resourcefulness is active")
assert(fixed.expectedConsumedCost < fixed.requiredCraftCost,
    "Fixed Crafts should value saved materials instead of reinvesting them")

local compatibility = Formula.CalculateFixedInputEquivalent({
    crafts = 100,
    baseYield = 1,
    resPercent = 0.15,
    supportsResourcefulness = true,
    mcMultiplier = 999,
    resourceSaveFraction = 0.99,
})
AssertNear(compatibility.expectedOutput, 100 / 0.955,
    "legacy entry point uses CraftSim Resourcefulness constant")

local smokeOK, smokeErr = Formula.RunSmokeChecks()
assert(smokeOK, smokeErr)

-- Minimal orchestration check: the engine must select Exhaust Materials,
-- apply a recipe-scoped snapshot, and keep Fixed Crafts as the comparison.
local opts = {
    v2PricingMode = "exhaust_materials",
    testMulti = 0,
    testRes = 0,
    testMcExtra = 0,
    testResExtra = 0,
}
local profiles = {
    test_commodity = {
        multiKey = "testMulti",
        resKey = "testRes",
        mcNodeKey = "testMcExtra",
        rsNodeKey = "testResExtra",
    },
}
GAM.C = {
    DEFAULT_V2_PRICING_MODE = "exhaust_materials",
}
GAM.CraftingStats = {
    ResolveForStrat = function(strat)
        if strat.recipeID == 434343 then
            return {
                profileKey = "test_commodity",
                recipeID = 434343,
                statSource = "craftsim-imported",
                supportsMulticraft = false,
                supportsResourcefulness = true,
                multiPercent = 24.5,
                resPercent = 18,
                multiExtra = 0.50,
                resExtra = 0,
            }
        end
        assert(strat.recipeID == 424242, "engine requested stats for the wrong recipe")
        return {
            profileKey = "test_commodity",
            recipeID = 424242,
            statSource = "craftsim-imported",
            supportsMulticraft = true,
            supportsResourcefulness = true,
            multiPercent = 20,
            resPercent = 15,
            multiExtra = 0.25,
            resExtra = 0.10,
        }
    end,
}
LoadModule("PricingEngine.lua")

local Pricing = {}
local installed, installErr = GAM.PricingEngine.Install(Pricing, {
    GetOpts = function() return opts end,
    GetFormulaProfiles = function() return profiles end,
    GetOutputBaseYield = function(output) return output.baseYieldPerCraft end,
})
assert(installed, installErr)

local strategy = {
    id = "test_exhaust_engine",
    recipeID = 424242,
    calcMode = "formula",
    formulaProfile = "test_commodity",
}
local active = {
    outputs = {
        { baseYieldPerCraft = 1 },
    },
}
local exhaustPerBudgetCraft = Pricing.GetV2ExpectedOutputPerCraft(strategy, active)
AssertNear(exhaustPerBudgetCraft, 1.43345607575,
    "engine Exhaust Materials recipe-scoped yield")

opts.v2PricingMode = "fixed_crafts"
local fixedPerCraft = Pricing.GetV2ExpectedOutputPerCraft(strategy, active)
AssertNear(fixedPerCraft, 1.3625, "engine Fixed Crafts comparison yield")
assert(exhaustPerBudgetCraft > fixedPerCraft,
    "engine mode selection did not reinvest Resourcefulness")

opts.v2PricingMode = "fixed_input"
local migratedAliasYield = Pricing.GetV2ExpectedOutputPerCraft(strategy, active)
AssertNear(migratedAliasYield, exhaustPerBudgetCraft,
    "legacy fixed-input mode alias")

opts.v2PricingMode = "exhaust_materials"
local resourcefulnessOnlyStrategy = {
    id = "test_resourcefulness_only_engine",
    recipeID = 434343,
    calcMode = "formula",
    formulaProfile = "test_commodity",
}
local resourcefulnessOnlyYield = Pricing.GetV2ExpectedOutputPerCraft(
    resourcefulnessOnlyStrategy, active)
AssertNear(resourcefulnessOnlyYield, 1 / (1 - (0.18 * 0.30)),
    "recipe capability suppresses profile Multicraft")

print("PASS: Exhaust Materials and Fixed Crafts golden calculations")

-- Even an oversized manual bonus cannot save more than all reagents per proc.
local cappedSave = GAM.PricingFormula.CalculateFixedCrafts({
    crafts=10,baseYield=1,requiredCraftCost=1000,
    supportsResourcefulness=true,resPercent=0.5,resExtra=4,
})
AssertNear(cappedSave.averageSavedCost,500,"resourcefulness is bounded per proc, before probability")
AssertNear(cappedSave.expectedConsumedCost,500,"bounded resourcefulness consumption")
