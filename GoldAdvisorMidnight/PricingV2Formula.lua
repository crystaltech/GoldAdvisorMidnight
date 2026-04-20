-- GoldAdvisorMidnight/PricingV2Formula.lua
-- Pure expected-value math for the shadow V2 pricing engine.
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

function Formula.CalculateFixedCrafts(input)
    input = input or {}

    local crafts = ClampNonNegative(input.crafts)
    local baseYield = ClampNonNegative(input.baseYield)
    local requiredCraftCost = ClampNonNegative(input.requiredCraftCost)
    local mcPercent = Clamp01(input.mcPercent)
    local resPercent = Clamp01(input.resPercent)
    local mcExtra = ClampNonNegative(input.mcExtra)
    local resExtra = ClampNonNegative(input.resExtra)
    local supportsMulticraft = input.supportsMulticraft and true or false
    local supportsResourcefulness = input.supportsResourcefulness and true or false
    local constants = input.multicraftConstants or Formula.DEFAULT_MULTICRAFT_CONSTANTS
    local saveBase = ClampNonNegative(input.resourcefulnessSaveBase or Formula.DEFAULT_RESOURCEFULNESS_SAVE_BASE)

    local expectedExtraOnProc = 0
    local expectedYieldPerCraft = baseYield
    local mcConstant = Formula.GetMulticraftConstant(baseYield, constants)

    if supportsMulticraft and baseYield > 0 and mcPercent > 0 then
        local maxExtra = mcConstant * baseYield * (1 + mcExtra)
        expectedExtraOnProc = (1 + maxExtra) / 2
        expectedYieldPerCraft = baseYield + (mcPercent * expectedExtraOnProc)
    end

    local averageSavedCost = 0
    if supportsResourcefulness and requiredCraftCost > 0 and resPercent > 0 then
        averageSavedCost = requiredCraftCost * resPercent * saveBase * (1 + resExtra)
        if averageSavedCost > requiredCraftCost then
            averageSavedCost = requiredCraftCost
        end
    end

    local expectedOutput = crafts * expectedYieldPerCraft
    local expectedConsumedCost = requiredCraftCost - averageSavedCost
    local expectedCostPerItem = nil
    if expectedOutput > 0 then
        expectedCostPerItem = expectedConsumedCost / expectedOutput
    end

    return {
        model = "fixedCrafts",
        crafts = crafts,
        baseYield = baseYield,
        mcPercent = mcPercent,
        resPercent = resPercent,
        mcExtra = mcExtra,
        resExtra = resExtra,
        mcConstant = mcConstant,
        expectedExtraOnProc = expectedExtraOnProc,
        expectedYieldPerCraft = expectedYieldPerCraft,
        expectedOutput = expectedOutput,
        requiredCraftCost = requiredCraftCost,
        averageSavedCost = averageSavedCost,
        expectedConsumedCost = expectedConsumedCost,
        expectedCostPerItem = expectedCostPerItem,
        supportsMulticraft = supportsMulticraft,
        supportsResourcefulness = supportsResourcefulness,
    }
end

function Formula.CalculateFixedInputEquivalent(input)
    input = input or {}

    local crafts = ClampNonNegative(input.crafts)
    local baseYield = ClampNonNegative(input.baseYield)
    local mcPercent = Clamp01(input.mcPercent)
    local resPercent = Clamp01(input.resPercent)
    local mcMultiplier = ClampNonNegative(input.mcMultiplier)
    local resourceSaveFraction = ClampNonNegative(input.resourceSaveFraction)
    local denominator = 1 - (resPercent * resourceSaveFraction)

    if denominator <= 0 then
        denominator = 1
    end

    local expectedOutput = (crafts * baseYield * (1 + (mcPercent * mcMultiplier))) / denominator

    return {
        model = "fixedInputEquivalent",
        crafts = crafts,
        baseYield = baseYield,
        mcPercent = mcPercent,
        resPercent = resPercent,
        mcMultiplier = mcMultiplier,
        resourceSaveFraction = resourceSaveFraction,
        denominator = denominator,
        expectedOutput = expectedOutput,
        expectedYieldPerCraft = (crafts > 0) and (expectedOutput / crafts) or 0,
    }
end

function Formula.RunSmokeChecks()
    local ok, err = pcall(function()
        local function assertNear(actual, expected, label)
            assert(math.abs((actual or 0) - expected) <= math.max(0.0001, math.abs(expected) * 0.001),
                string.format("%s: got %.6f expected %.6f", label, actual or 0, expected))
        end

        local fixedInput = Formula.CalculateFixedInputEquivalent({
            crafts = 1000,
            baseYield = 2,
            mcPercent = 0.25,
            mcMultiplier = 2.5,
            resPercent = 0.15,
            resourceSaveFraction = 0.375,
        })
        assertNear(fixedInput.expectedOutput, 3443.708609, "fixed-input formula example")

        local fixedCrafts = Formula.CalculateFixedCrafts({
            crafts = 1000,
            baseYield = 2,
            mcPercent = 0.25,
            resPercent = 0.15,
            requiredCraftCost = 100000,
            supportsMulticraft = true,
            supportsResourcefulness = true,
        })
        assert(math.abs(fixedCrafts.expectedOutput - fixedInput.expectedOutput) > 100,
            "fixed-craft CraftSim parity should differ from fixed-input reinvestment math")
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

