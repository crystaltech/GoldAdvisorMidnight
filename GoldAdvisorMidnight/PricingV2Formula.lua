-- GoldAdvisorMidnight/PricingV2Formula.lua
-- Pure expected-value math for the V2 pricing engine.
-- Module: GAM.PricingV2Formula

local ADDON_NAME, GAM = ...
local Formula = {}
GAM.PricingV2Formula = Formula

Formula.DEFAULT_RESOURCEFULNESS_SAVE_BASE = 0.30
Formula.DEFAULT_MULTICRAFT_CONSTANTS = {
    DEFAULT = 2.5,
    [1] = 2.1,
    [2] = 1.83,
    [5] = 1.875,
}

local function Num(value, fallback)
    local n = tonumber(value)
    if n == nil then
        return fallback or 0
    end
    return n
end

local function Clamp01(value)
    local n = Num(value, 0)
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

local function ClampNonNegative(value)
    local n = Num(value, 0)
    if n < 0 then return 0 end
    return n
end

local function CopyConstants(constants)
    local source = constants or Formula.DEFAULT_MULTICRAFT_CONSTANTS
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    if copy.DEFAULT == nil then
        copy.DEFAULT = Formula.DEFAULT_MULTICRAFT_CONSTANTS.DEFAULT
    end
    return copy
end

function Formula.GetMulticraftConstant(baseYield, constants)
    local c = constants or Formula.DEFAULT_MULTICRAFT_CONSTANTS
    local exact = c[baseYield]
    if exact ~= nil then
        return Num(exact, Formula.DEFAULT_MULTICRAFT_CONSTANTS.DEFAULT)
    end
    return Num(c.DEFAULT, Formula.DEFAULT_MULTICRAFT_CONSTANTS.DEFAULT)
end

function Formula.GetDefaultMulticraftConstants()
    return CopyConstants(Formula.DEFAULT_MULTICRAFT_CONSTANTS)
end

local function ResolveFormulaInput(input)
    input = input or {}
    return {
        crafts = ClampNonNegative(input.crafts),
        baseYield = ClampNonNegative(input.baseYield),
        requiredCraftCost = ClampNonNegative(input.requiredCraftCost),
        mcPercent = Clamp01(input.mcPercent),
        resPercent = Clamp01(input.resPercent),
        mcExtra = ClampNonNegative(input.mcExtra),
        resExtra = ClampNonNegative(input.resExtra),
        supportsMulticraft = input.supportsMulticraft and true or false,
        supportsResourcefulness = input.supportsResourcefulness and true or false,
        multicraftConstants = input.multicraftConstants or Formula.DEFAULT_MULTICRAFT_CONSTANTS,
        resourcefulnessSaveBase = ClampNonNegative(
            input.resourcefulnessSaveBase or Formula.DEFAULT_RESOURCEFULNESS_SAVE_BASE),
    }
end

local function CalculateCraftYield(values)
    local expectedExtraOnProc = 0
    local expectedYieldPerActualCraft = values.baseYield
    local mcConstant = Formula.GetMulticraftConstant(values.baseYield, values.multicraftConstants)

    if values.supportsMulticraft and values.baseYield > 0 and values.mcPercent > 0 then
        local maxExtra = mcConstant * values.baseYield * (1 + values.mcExtra)
        expectedExtraOnProc = (1 + maxExtra) / 2
        expectedYieldPerActualCraft = values.baseYield
            + (values.mcPercent * expectedExtraOnProc)
    end

    return expectedYieldPerActualCraft, expectedExtraOnProc, mcConstant
end

function Formula.CalculateFixedCrafts(input)
    local values = ResolveFormulaInput(input)
    local expectedYieldPerCraft, expectedExtraOnProc, mcConstant = CalculateCraftYield(values)

    local averageSavedCost = 0
    if values.supportsResourcefulness
            and values.requiredCraftCost > 0
            and values.resPercent > 0 then
        averageSavedCost = values.requiredCraftCost
            * values.resPercent
            * values.resourcefulnessSaveBase
            * (1 + values.resExtra)
        if averageSavedCost > values.requiredCraftCost then
            averageSavedCost = values.requiredCraftCost
        end
    end

    local expectedOutput = values.crafts * expectedYieldPerCraft
    local expectedConsumedCost = values.requiredCraftCost - averageSavedCost
    local expectedCostPerItem = nil
    if expectedOutput > 0 then
        expectedCostPerItem = expectedConsumedCost / expectedOutput
    end

    return {
        model = "fixedCrafts",
        crafts = values.crafts,
        effectiveCrafts = values.crafts,
        baseYield = values.baseYield,
        mcPercent = values.mcPercent,
        resPercent = values.resPercent,
        mcExtra = values.mcExtra,
        resExtra = values.resExtra,
        mcConstant = mcConstant,
        expectedExtraOnProc = expectedExtraOnProc,
        expectedYieldPerCraft = expectedYieldPerCraft,
        expectedYieldPerActualCraft = expectedYieldPerCraft,
        expectedOutput = expectedOutput,
        requiredCraftCost = values.requiredCraftCost,
        averageSavedCost = averageSavedCost,
        expectedConsumedCost = expectedConsumedCost,
        expectedCostPerItem = expectedCostPerItem,
        supportsMulticraft = values.supportsMulticraft,
        supportsResourcefulness = values.supportsResourcefulness,
    }
end

-- Treat `crafts` as the initial reagent pool for that many ordinary crafts.
-- Resourcefulness is reinvested into additional expected craft attempts until
-- the pool is exhausted. Multicraft affects output, not the number of attempts.
function Formula.CalculateExhaustMaterials(input)
    local values = ResolveFormulaInput(input)
    local expectedYieldPerActualCraft, expectedExtraOnProc, mcConstant = CalculateCraftYield(values)

    local resourceSaveFraction = 0
    if values.supportsResourcefulness and values.resPercent > 0 then
        resourceSaveFraction = Clamp01(
            values.resourcefulnessSaveBase * (1 + values.resExtra))
    end

    local consumptionFactor = 1 - (values.resPercent * resourceSaveFraction)
    local resourceLoopBounded = consumptionFactor > 0
    local effectiveCrafts = values.crafts
    if resourceLoopBounded then
        effectiveCrafts = values.crafts / consumptionFactor
    end

    local expectedOutput = effectiveCrafts * expectedYieldPerActualCraft
    local expectedYieldPerCraft = values.crafts > 0
        and (expectedOutput / values.crafts)
        or expectedYieldPerActualCraft

    return {
        model = "exhaustMaterials",
        crafts = values.crafts,
        effectiveCrafts = effectiveCrafts,
        baseYield = values.baseYield,
        mcPercent = values.mcPercent,
        resPercent = values.resPercent,
        mcExtra = values.mcExtra,
        resExtra = values.resExtra,
        mcConstant = mcConstant,
        expectedExtraOnProc = expectedExtraOnProc,
        resourceSaveFraction = resourceSaveFraction,
        consumptionFactor = consumptionFactor,
        denominator = consumptionFactor,
        resourceLoopBounded = resourceLoopBounded,
        expectedOutput = expectedOutput,
        expectedYieldPerCraft = expectedYieldPerCraft,
        expectedYieldPerActualCraft = expectedYieldPerActualCraft,
        requiredCraftCost = values.requiredCraftCost,
        averageSavedCost = 0,
        expectedConsumedCost = values.requiredCraftCost,
        expectedCostPerItem = (expectedOutput > 0)
            and (values.requiredCraftCost / expectedOutput)
            or nil,
        supportsMulticraft = values.supportsMulticraft,
        supportsResourcefulness = values.supportsResourcefulness,
    }
end

-- Compatibility entry point for saved settings and third-party callers from
-- the first V2 test branch. Its manual multiplier fields are intentionally no
-- longer used; the CraftSim-derived model above is authoritative.
function Formula.CalculateFixedInputEquivalent(input)
    return Formula.CalculateExhaustMaterials(input)
end

function Formula.RunSmokeChecks()
    local ok, err = pcall(function()
        local function assertNear(actual, expected, label)
            assert(math.abs((actual or 0) - expected) <= math.max(0.0001, math.abs(expected) * 0.001),
                string.format("%s: got %.6f expected %.6f", label, actual or 0, expected))
        end

        local exhaust = Formula.CalculateExhaustMaterials({
            crafts = 1000,
            baseYield = 2,
            mcPercent = 0.25,
            resPercent = 0.15,
            supportsMulticraft = true,
            supportsResourcefulness = true,
        })
        assertNear(exhaust.effectiveCrafts, 1047.120419, "exhaust-materials effective crafts")
        assertNear(exhaust.expectedOutput, 2704.188482, "exhaust-materials formula example")

        local sunglassDefault = Formula.CalculateFixedCrafts({
            crafts = 20,
            baseYield = 1,
            mcPercent = 0.30,
            mcExtra = 0.50,
            supportsMulticraft = true,
        })
        assertNear(sunglassDefault.expectedOutput, 32.45, "Sunglass Vial default hidden MC")
        assert(math.floor((sunglassDefault.expectedOutput or 0) + 0.5) == 32,
            "Sunglass Vial default hidden MC should round to 32")

        local sunglassPartial = Formula.CalculateFixedCrafts({
            crafts = 20,
            baseYield = 1,
            mcPercent = 0.30,
            mcExtra = 0.25,
            supportsMulticraft = true,
        })
        assertNear(sunglassPartial.expectedOutput, 30.875, "Sunglass Vial partial hidden MC")
        assert(math.floor((sunglassPartial.expectedOutput or 0) + 0.5) == 31,
            "Sunglass Vial partial hidden MC should round to 31")

        local fixedCrafts = Formula.CalculateFixedCrafts({
            crafts = 1000,
            baseYield = 2,
            mcPercent = 0.25,
            resPercent = 0.15,
            requiredCraftCost = 100000,
            supportsMulticraft = true,
            supportsResourcefulness = true,
        })
        assert(math.abs(fixedCrafts.expectedOutput - exhaust.expectedOutput) > 100,
            "fixed-craft CraftSim parity should differ from exhaustion reinvestment math")
        assertNear(fixedCrafts.expectedOutput, 2582.5, "base-yield 2 CraftSim multicraft")
        assertNear(fixedCrafts.averageSavedCost, 4500, "CraftSim resourcefulness base savings")

        assertNear(Formula.GetMulticraftConstant(1), 2.1, "base-yield 1 multicraft constant")
        assertNear(Formula.GetMulticraftConstant(2), 1.83, "base-yield 2 multicraft constant")
        assertNear(Formula.GetMulticraftConstant(5), 1.875, "base-yield 5 multicraft constant")
        assertNear(Formula.GetMulticraftConstant(3), 2.5, "default multicraft constant")

        for _, extra in ipairs({ 0, 0.25, 0.5, 1.0 }) do
            local nodeCase = Formula.CalculateFixedCrafts({
                crafts = 10,
                baseYield = 1,
                mcPercent = 0.5,
                resPercent = 0.5,
                mcExtra = extra,
                resExtra = extra,
                requiredCraftCost = 10000,
                supportsMulticraft = true,
                supportsResourcefulness = true,
            })
            local expectedMaxExtra = 2.1 * (1 + extra)
            local expectedExtraOnProc = (1 + expectedMaxExtra) / 2
            assertNear(nodeCase.expectedYieldPerCraft, 1 + (0.5 * expectedExtraOnProc),
                "node multicraft extra " .. tostring(extra))
            assertNear(nodeCase.averageSavedCost, 10000 * 0.5 * 0.30 * (1 + extra),
                "node resourcefulness extra " .. tostring(extra))
        end
    end)
    return ok, err
end
