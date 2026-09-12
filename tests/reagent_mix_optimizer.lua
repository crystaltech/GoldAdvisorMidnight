-- Offline regression checks for the no-Concentration reagent rank optimizer.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {}

function wipe(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end

local qualities = {
    [101] = 1, [102] = 2,
    [111] = 1, [112] = 2,
    [121] = 1, [122] = 2,
    [201] = 1, [202] = 2,
    [301] = 1, [302] = 2,
    [401] = 1, [402] = 2,
    [501] = 1, [502] = 2,
    [601] = 1, [602] = 2,
    [901] = 0, [902] = 0, [903] = 0,
}
local concentrationFlags = {}
local diagnosticOperationCalls = 0

C_TradeSkillUI = {
    GetRecipeSchematic = function(recipeID, isRecraft)
        assert(isRecraft == false)
        if recipeID == 434343 then
            return {
                reagentSlotSchematics = {
                    {
                        quantityRequired = 2,
                        dataSlotIndex = 1,
                        reagents = {
                            { itemID = 101 }, { itemID = 102 },
                            { itemID = 121 }, { itemID = 122 },
                        },
                    },
                },
            }
        end
        if recipeID == 444444 then
            return {
                reagentSlotSchematics = {
                    {
                        quantityRequired = 1,
                        dataSlotIndex = 1,
                        reagents = { { itemID = 901 } },
                    },
                },
            }
        end
        if recipeID == 454545 then
            return {
                reagentSlotSchematics = {
                    {
                        quantityRequired = 5,
                        dataSlotIndex = 1,
                        reagents = { { itemID = 601 }, { itemID = 602 } },
                    },
                },
            }
        end
        if recipeID == 464646 then
            return {
                reagentSlotSchematics = {
                    {
                        quantityRequired = 1,
                        dataSlotIndex = 1,
                        reagents = { { itemID = 601 }, { itemID = 602 } },
                    },
                },
            }
        end
        assert(recipeID == 424242)
        return {
            reagentSlotSchematics = {
                {
                    quantityRequired = 4,
                    dataSlotIndex = 1,
                    reagents = {
                        { itemID = 101 }, { itemID = 102 },
                        { itemID = 111 }, { itemID = 112 },
                    },
                },
                {
                    quantityRequired = 2,
                    dataSlotIndex = 2,
                    reagents = { { itemID = 201 }, { itemID = 202 } },
                },
                {
                    quantityRequired = 1,
                    dataSlotIndex = 3,
                    required = true,
                    reagents = { { itemID = 901 }, { itemID = 902 }, { itemID = 903 } },
                },
            },
        }
    end,
    GetItemReagentQualityByItemInfo = function(itemID)
        if type(itemID) == "table" then
            itemID = itemID.itemID
            if itemID == 601 then return 1 end
            if itemID == 602 then return 2 end
        elseif itemID == 601 or itemID == 602 then
            -- Live ItemInfo APIs can classify a bare numeric argument as
            -- unranked. The optimizer must use the structured payload first.
            return 0
        end
        return qualities[itemID]
    end,
    GetItemCraftedQualityByItemInfo = function(itemID)
        return qualities[itemID]
    end,
    GetCraftingOperationInfo = function(recipeID, allocation, allocationItemGUID, applyConcentration)
        assert(allocationItemGUID == nil)
        concentrationFlags[#concentrationFlags + 1] = applyConcentration
        if recipeID == 444444 then
            return {
                baseSkill = 100,
                bonusSkill = 0,
                quality = 2,
            }
        end
        if recipeID == 454545 then
            return {
                baseSkill = 100,
                bonusSkill = 0,
                quality = 1,
            }
        end
        if recipeID == 464646 then
            diagnosticOperationCalls = diagnosticOperationCalls + 1
            if diagnosticOperationCalls > 3 then return nil end
            local highCount = 0
            for _, reagent in ipairs(allocation or {}) do
                if reagent.reagent and reagent.reagent.itemID == 602 then
                    highCount = highCount + reagent.quantity
                end
            end
            return {
                baseSkill = 100,
                bonusSkill = highCount * 10,
                quality = highCount > 0 and 2 or 1,
            }
        end
        local skill = 0
        for _, reagent in ipairs(allocation or {}) do
            local itemID = reagent.reagent and reagent.reagent.itemID
            if itemID == 102 then skill = skill + reagent.quantity * 10 end
            if itemID == 112 then skill = skill + reagent.quantity * 10 end
            if itemID == 122 then skill = skill + reagent.quantity * 20 end
            if itemID == 202 then skill = skill + reagent.quantity * 25 end
        end
        if recipeID == 434343 then
            return {
                baseSkill = 100,
                bonusSkill = skill,
                quality = skill >= 40 and 2 or 1,
            }
        end
        assert(recipeID == 424242)
        return {
            baseSkill = 100,
            bonusSkill = skill,
            quality = skill >= 30 and 2 or 1,
        }
    end,
}

local chunk, err = loadfile("ReagentMixOptimizer.lua")
assert(chunk, err)
chunk(ADDON_NAME, GAM)

local prices = {
    [101] = 10, [102] = 18,
    [111] = 8, [112] = 17,
    [201] = 10, [202] = 100,
}
local recipeView = {
    defaultStartingAmount = 1,
    defaultCrafts = 1,
    outputs = { { itemIDs = { 301, 302 } } },
    reagents = {
        {
            itemRef = "First", name = "First", itemIDs = { 101, 102 },
            qtyPerCraft = 4, qtyPerStart = 4,
            cheapestOf = {
                { itemRef = "First A", itemIDs = { 101, 102 } },
                { itemRef = "First B", itemIDs = { 111, 112 } },
            },
        },
        { itemRef = "Second", name = "Second", itemIDs = { 201, 202 }, qtyPerCraft = 2, qtyPerStart = 2 },
    },
}
local plan, reason = GAM.ReagentMixOptimizer.BuildLivePlan({
    recipeID = 424242,
    targetQuality = 2,
    crafts = 1,
    recipeView = recipeView,
    priceGetter = function(itemID)
        return prices[itemID], false
    end,
})
assert(plan, reason)
assert(plan.applyConcentration == false, "plan did not record no-Concentration mode")
assert(plan.verifiedQuality == 2, "plan was not verified at rank 2")
assert(plan.rows[1].lowCount == 1 and plan.rows[1].highCount == 3,
    "optimizer did not choose the cheapest 1xR1 + 3xR2 mix")
assert(plan.rows[1].lowItemID == 111 and plan.rows[1].highItemID == 112,
    "optimizer did not keep the cheapest alternative's R1/R2 family together")
assert(plan.rows[2].lowCount == 2 and plan.rows[2].highCount == 0,
    "optimizer used the expensive second-slot upgrade")
for _, flag in ipairs(concentrationFlags) do
    assert(flag == false, "operation-info call enabled Concentration")
end

local view, applyReason = GAM.ReagentMixOptimizer.ApplyPlan(recipeView, plan)
assert(view, applyReason)
assert(#view.reagents == 3, "applied plan did not split only the mixed slot")
assert(view.reagents[1].itemIDs[1] == 111 and view.reagents[1].qtyPerCraft == 1)
assert(view.reagents[2].itemIDs[1] == 112 and view.reagents[2].qtyPerCraft == 3)
assert(view.reagents[3].itemIDs[1] == 201 and view.reagents[3].qtyPerCraft == 2)
assert(GAM.ReagentMixOptimizer.GetHighestOutputQuality({ itemIDs = { 301, 302 } }) == 2)

local unreachablePlan, unreachableReason, unreachableDiagnostic =
    GAM.ReagentMixOptimizer.BuildLivePlan({
        recipeID = 424242,
        targetQuality = 3,
        crafts = 1,
        recipeView = recipeView,
        priceGetter = function(itemID)
            return prices[itemID], false
        end,
    })
assert(unreachablePlan and unreachableReason == "target-quality-unreachable",
    "unreachable target did not produce a verified reachable-rank plan")
assert(unreachablePlan.requestedQuality == 3
        and unreachablePlan.targetQuality == 2
        and unreachablePlan.verifiedQuality == 2
        and unreachablePlan.targetQualityUnreachable,
    "reachable-rank plan lost its requested/effective quality boundary")
assert(unreachablePlan.rows[1].lowCount == 1 and unreachablePlan.rows[1].highCount == 3
        and unreachablePlan.rows[2].highCount == 0,
    "reachable-rank fallback did not retain the cheapest verified allocation")
assert(unreachableDiagnostic and unreachableDiagnostic.targetQuality == 3
        and unreachableDiagnostic.reachableQuality == 2,
    "unreachable target did not report Blizzard's all-high reachable quality")

-- Screenshot regression: when rank 2 is requested but even the all-R2
-- allocation only reaches rank 1, the optimizer must buy the cheaper all-R1
-- inputs because they produce the same verified output rank.
local rankOneFallbackPlan, rankOneFallbackReason = GAM.ReagentMixOptimizer.BuildLivePlan({
    recipeID = 454545,
    targetQuality = 2,
    crafts = 1,
    recipeView = {
        outputs = { { itemIDs = { 701, 702 } } },
        reagents = {
            { itemRef = "Ranked Input", itemIDs = { 601, 602 }, qtyPerCraft = 5 },
        },
    },
    priceGetter = function(itemID)
        return itemID == 601 and 10 or 100, false
    end,
})
assert(rankOneFallbackPlan and rankOneFallbackReason == "target-quality-unreachable",
    "rank-1 fallback did not return a verified unreachable-target plan")
assert(rankOneFallbackPlan.targetQuality == 1
        and rankOneFallbackPlan.verifiedQuality == 1
        and rankOneFallbackPlan.rows[1].lowCount == 5
        and rankOneFallbackPlan.rows[1].highCount == 0,
    "rank-1 fallback did not select the cheapest all-R1 allocation")

-- Lua's `and` expression collapses multiple returns. Preserve the second
-- operation-result value so a failed candidate reports the actual API reason.
local diagnosticPlan, diagnosticReason = GAM.ReagentMixOptimizer.BuildLivePlan({
    recipeID = 464646,
    targetQuality = 2,
    crafts = 1,
    recipeView = {
        outputs = { { itemIDs = { 701, 702 } } },
        reagents = {
            { itemRef = "Diagnostic Input", itemIDs = { 601, 602 }, qtyPerCraft = 1 },
        },
    },
    priceGetter = function() return 10, false end,
})
assert(diagnosticPlan == nil and diagnosticReason == "operation-api-returned-nil",
    "candidate operation diagnostic lost its second Lua return value")

-- Alternative families in one Blizzard slot are not guaranteed to contribute
-- the same skill. The cheaper family below cannot reach rank 2; the optimizer
-- must retain the more expensive, higher-weight family instead of pruning it as
-- an equivalent high-count choice.
local weightedFamilyView = {
    defaultStartingAmount = 1,
    defaultCrafts = 1,
    outputs = { { itemIDs = { 401, 402 } } },
    reagents = {
        {
            itemRef = "Weighted Family", itemIDs = { 101, 102 }, qtyPerCraft = 2,
            cheapestOf = {
                { itemRef = "Low Weight", itemIDs = { 101, 102 } },
                { itemRef = "High Weight", itemIDs = { 121, 122 } },
            },
        },
    },
}
local weightedPrices = { [101] = 1, [102] = 2, [121] = 1, [122] = 3 }
local weightedPlan, weightedReason = GAM.ReagentMixOptimizer.BuildLivePlan({
    recipeID = 434343,
    targetQuality = 2,
    crafts = 1,
    recipeView = weightedFamilyView,
    priceGetter = function(itemID) return weightedPrices[itemID], false end,
})
assert(weightedPlan, weightedReason)
assert(weightedPlan.rows[1].lowItemID == 121
        and weightedPlan.rows[1].highItemID == 122
        and weightedPlan.rows[1].highCount == 2,
    "optimizer pruned the viable higher-weight cheapestOf family")

-- Recipes with no ranked input decision still need a live operation snapshot so
-- their reachable crafted-output rank is verified (for example refining recipes).
local fixedInputPlan, fixedInputReason = GAM.ReagentMixOptimizer.BuildLivePlan({
    recipeID = 444444,
    targetQuality = 2,
    crafts = 1,
    recipeView = {
        outputs = { { itemIDs = { 501, 502 } } },
        reagents = { { itemRef = "Fixed Input", itemIDs = { 901 }, qtyPerCraft = 1 } },
    },
    priceGetter = function() return 1, false end,
})
assert(fixedInputPlan, fixedInputReason)
assert(fixedInputPlan.verifiedQuality == 2 and #fixedInputPlan.rows == 0,
    "fixed-input recipe did not retain its Blizzard-verified output quality")

print("PASS: reagent mix optimizer regression checks")
