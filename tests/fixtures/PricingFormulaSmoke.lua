-- Test-only fixture extracted from PricingFormula.lua.
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
