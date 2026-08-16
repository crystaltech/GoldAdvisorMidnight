-- Regression checks for grouped VI purchases and dependency-safe craft ordering.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = { UI = {} }

local chunk, err = loadfile("UI/VIBreakdownPlan.lua")
assert(chunk, err)
chunk(ADDON_NAME, GAM)

local Plan = assert(GAM.UI.VIBreakdownPlan, "VI breakdown plan unavailable")

local breakdown = {
    stratName = "Final Widget",
    crafts = 50,
    finalOutputName = "Final Widget",
    finalExpectedOutput = 50,
    finalCraftsEconomic = 50.9,
    finalCraftsExecution = 50,
    totalCostFull = 50000,
    entries = {
        {
            kind = "craft", name = "Ink A", itemID = 201, producerStratID = "ink-a",
            requiredRaw = 10, craftsEconomic = 5, childIndices = { 2, 3 }, chainTotalCostFull = 10000,
        },
        {
            kind = "craft", name = "Shared Pigment", itemID = 202, producerStratID = "pigment",
            requiredRaw = 4.5, craftsEconomic = 2.25, childIndices = { 4 }, chainTotalCostFull = 4000,
            selectedInputNames = { "Tenebrous Amethyst" },
        },
        {
            kind = "leaf", name = "Vendor Solvent", itemID = 100,
            requiredRaw = 10, required = 10, have = 0, needToBuy = 10, excludeFromCost = true,
        },
        {
            kind = "leaf", name = "Shared Herb", itemID = 101,
            requiredRaw = 10, required = 10, have = 2, needToBuy = 8,
            effectiveUnitPrice = 100, effectiveTotalCostFull = 1000,
        },
        {
            kind = "craft", name = "Ink B", itemID = 203, producerStratID = "ink-b",
            requiredRaw = 12, craftsEconomic = 6, childIndices = { 6 }, chainTotalCostFull = 12000,
        },
        {
            kind = "craft", name = "Shared Pigment", itemID = 202, producerStratID = "pigment",
            requiredRaw = 6.5, craftsEconomic = 3.25, childIndices = { 7 }, chainTotalCostFull = 6000,
            selectedInputNames = { "Tenebrous Amethyst" },
        },
        {
            kind = "leaf", name = "Shared Herb", itemID = 101,
            requiredRaw = 5, required = 5, have = 2, needToBuy = 3,
            effectiveUnitPrice = 100, effectiveTotalCostFull = 500,
        },
        {
            kind = "leaf", name = "Owned Item", itemID = 102,
            requiredRaw = 2, required = 2, have = 10, needToBuy = 0,
            effectiveUnitPrice = 200, effectiveTotalCostFull = 400,
        },
    },
}

local plan = Plan.Build(breakdown, { [100] = 50 })

assert(#plan.vendorBuys == 1, "vendor purchases should be grouped separately")
assert(plan.vendorBuys[1].name == "Vendor Solvent", "vendor purchase name")
assert(plan.vendorBuys[1].needToBuy == 10, "vendor purchase quantity")
assert(plan.vendorBuys[1].effectiveTotalCostToBuy == 500, "vendor catalog price should price the buy list")
assert(plan.vendorBuys[1].excludedFromEstimate, "required excluded materials must remain visible to the crafter")

assert(#plan.auctionBuys == 1, "owned items should not appear in needed AH purchases")
assert(plan.auctionBuys[1].name == "Shared Herb", "AH purchase name")
assert(plan.auctionBuys[1].required == 15, "duplicate AH requirements should be combined")
assert(plan.auctionBuys[1].needToBuy == 13,
    "owned inventory must be subtracted once after duplicate requirements are combined")

assert(#plan.craftSteps == 4, "three intermediate recipes plus the final craft")
assert(plan.craftSteps[1].name == "Shared Pigment", "dependency must be crafted before consumers")
assert(plan.craftSteps[1].craftsEconomic == 5.5, "duplicate intermediate crafts should be combined")
assert(plan.craftSteps[1].craftsExecution == 6, "combined intermediate crafts should round up once")
assert(#plan.craftSteps[1].selectedInputNames == 1
        and plan.craftSteps[1].selectedInputNames[1] == "Tenebrous Amethyst",
    "selected flexible input should survive duplicate craft merging")
assert(plan.craftSteps[2].name == "Ink A", "first consuming craft follows its dependency")
assert(plan.craftSteps[3].name == "Ink B", "second consuming craft follows its dependency")
assert(plan.craftSteps[4].isFinalCraft and plan.craftSteps[4].name == "Final Widget",
    "final output must always be the last craft")
assert(plan.craftSteps[4].craftsExecution == 50, "final execution quantity")
assert(plan.craftSteps[4].craftsEconomic == 50.9, "final expected-value craft count")

assert(plan.rows[1].sectionKey == "vendor", "vendor section first")
assert(plan.rows[3].sectionKey == "auction", "Auction House section second")
assert(plan.rows[5].sectionKey == "craft", "crafting section last")

print("PASS: grouped VI shopping and dependency-safe crafting plan")
