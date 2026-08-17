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
    [201] = 1, [202] = 2,
    [301] = 1, [302] = 2,
    [901] = 0, [902] = 0, [903] = 0,
}
local concentrationFlags = {}

C_TradeSkillUI = {
    GetRecipeSchematic = function(recipeID, isRecraft)
        assert(recipeID == 424242 and isRecraft == false)
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
        return qualities[itemID]
    end,
    GetItemCraftedQualityByItemInfo = function(itemID)
        return qualities[itemID]
    end,
    GetCraftingOperationInfo = function(recipeID, allocation, allocationItemGUID, applyConcentration)
        assert(recipeID == 424242)
        assert(allocationItemGUID == nil)
        concentrationFlags[#concentrationFlags + 1] = applyConcentration
        local skill = 0
        for _, reagent in ipairs(allocation or {}) do
            local itemID = reagent.reagent and reagent.reagent.itemID
            if itemID == 102 then skill = skill + reagent.quantity * 10 end
            if itemID == 112 then skill = skill + reagent.quantity * 10 end
            if itemID == 202 then skill = skill + reagent.quantity * 25 end
        end
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

print("PASS: reagent mix optimizer regression checks")
