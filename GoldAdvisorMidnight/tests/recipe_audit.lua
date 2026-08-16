-- Offline regression checks for the live recipe schematic auditor.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {
    C = {
        PROFESSION_REGISTRY = {
            { name = "Inscription", enumName = "Inscription" },
        },
    },
}

local function LoadModule(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk(ADDON_NAME, GAM)
end

local function AssertEqual(actual, expected, label)
    assert(actual == expected,
        string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

LoadModule("RecipeAudit.lua")

local enum = {
    Profession = { Inscription = 9 },
    CraftingReagentType = {
        Optional = 0,
        Basic = 1,
        Modifying = 2,
        Finishing = 3,
    },
    TradeskillSlotDataType = {
        Reagent = 1,
        ModifiedReagent = 2,
    },
}

local function Reagent(name, itemIDs, quantity)
    return {
        itemRef = name,
        itemIDs = itemIDs,
        quantityPerCraft = quantity,
    }
end

local function Output(name, itemIDs, quantity)
    return {
        itemRef = name,
        itemIDs = itemIDs,
        baseYieldPerCraft = quantity,
    }
end

local strategies = {
    {
        id = "audit__pass",
        profession = "Inscription",
        stratName = "Audit Pass",
        recipeID = 100,
        recipeName = "Audit Pass",
        reagents = {
            Reagent("Vellum", { 1 }, 1),
            Reagent("Mote", { 2 }, 1),
            Reagent("Ink A", { 3, 4 }, 2),
        },
        outputs = { Output("Pass Output", { 5001, 5002 }, 1) },
    },
    {
        id = "audit__mismatch",
        profession = "Inscription",
        stratName = "Audit Mismatch",
        recipeID = 101,
        recipeName = "Audit Mismatch",
        reagents = { Reagent("Pigment", { 10, 11 }, 2) },
        outputs = { Output("Mismatch Output", { 5101 }, 1) },
    },
    {
        id = "audit__salvage",
        profession = "Inscription",
        stratName = "Audit Milling",
        recipeID = 102,
        recipeName = "Midnight Milling",
        reagents = { Reagent("Herb", { 20, 21 }, 10) },
        outputs = {
            Output("Pigment A", { 5201 }, 13),
            Output("Pigment B", { 5202 }, 1),
        },
    },
    {
        id = "audit__unlearned",
        profession = "Inscription",
        stratName = "Audit Unlearned",
        recipeID = 103,
        recipeName = "Audit Unlearned",
        reagents = {},
        outputs = { Output("Unlearned Output", { 5301 }, 1) },
    },
    {
        id = "audit__unavailable",
        profession = "Inscription",
        stratName = "Audit Unavailable",
        recipeID = 104,
        recipeName = "Audit Unavailable",
        reagents = {},
        outputs = { Output("Unavailable Output", { 5401 }, 1) },
    },
    {
        id = "audit__user_missing_id",
        profession = "Inscription",
        stratName = "User Missing ID",
        recipeName = "User Missing ID",
        _isUser = true,
        reagents = {},
        outputs = { Output("User Output", { 5501 }, 1) },
    },
}

local recipeInfo = {
    [100] = { name = "Audit Pass", learned = true, isSalvageRecipe = false },
    [101] = { name = "Audit Mismatch", learned = true, isSalvageRecipe = false },
    [102] = { name = "Midnight Milling", learned = true, isSalvageRecipe = true },
    [103] = { name = "Audit Unlearned", learned = false, isSalvageRecipe = false },
    [104] = { name = "Audit Unavailable", learned = true, isSalvageRecipe = false },
}

local schematics = {
    [100] = {
        recipeID = 100,
        outputItemID = 5002,
        quantityMin = 1,
        quantityMax = 1,
        reagentSlotSchematics = {
            { reagentType = 1, dataSlotType = 1, quantityRequired = 1,
                reagents = { { itemID = 1 } } },
            { reagentType = 1, dataSlotType = 2, quantityRequired = 1,
                reagents = { { itemID = 2 } } },
            { reagentType = 2, required = true, quantityRequired = 2,
                reagents = { { itemID = 3 }, { itemID = 4 } } },
            -- Optional and finishing slots must never become fixed-reagent failures.
            { reagentType = 0, required = false, quantityRequired = 1,
                reagents = { { itemID = 9001 } } },
            { reagentType = 3, required = false, quantityRequired = 1,
                reagents = { { itemID = 9002 } } },
        },
    },
    [101] = {
        recipeID = 101,
        outputItemID = 9999,
        quantityMin = 2,
        quantityMax = 2,
        reagentSlotSchematics = {
            { reagentType = 1, dataSlotType = 1, quantityRequired = 3,
                reagents = { { itemID = 10 }, { itemID = 11 } } },
        },
    },
    [102] = {
        recipeID = 102,
        -- Processing schematics may expose an unrelated placeholder output.
        outputItemID = 9998,
        quantityMin = 1,
        quantityMax = 10,
        reagentSlotSchematics = {},
    },
    [103] = {
        recipeID = 103,
        outputItemID = 5301,
        quantityMin = 1,
        quantityMax = 1,
        reagentSlotSchematics = {},
    },
}

local deps = {
    enum = enum,
    getRecipeInfo = function(recipeID)
        assert(recipeID ~= nil, "nil recipe ID passed to GetRecipeInfo")
        return recipeInfo[recipeID]
    end,
    getRecipeSchematic = function(recipeID)
        assert(recipeID ~= nil, "nil recipe ID passed to GetRecipeSchematic")
        return schematics[recipeID]
    end,
    getChildProfessionInfo = function() return { profession = 9 } end,
    getBaseProfessionInfo = function() return nil end,
    resolveStats = function(strat)
        if strat.recipeID == 102 then
            return {
                recipeID = 999,
                statSource = "gam-manual-nodes",
                supportsMulticraft = false,
                supportsResourcefulness = true,
            }
        end
        return {
            recipeID = strat.recipeID,
            statSource = "craftsim-imported",
            supportsMulticraft = true,
            supportsResourcefulness = true,
        }
    end,
    options = {},
}

AssertEqual(GAM.RecipeAudit.GetOpenProfessionName(deps), "Inscription",
    "open profession resolution")

local result = GAM.RecipeAudit.AuditStrategies(strategies, deps, "Inscription")
AssertEqual(#result.rows, 6, "audited strategy count")
AssertEqual(result.uniqueRecipes, 5, "unique recipe count")
AssertEqual(result.counts.PASS, 2, "pass count")
AssertEqual(result.counts.MISMATCH, 1, "mismatch count")
AssertEqual(result.counts.UNLEARNED, 1, "unlearned count")
AssertEqual(result.counts.UNAVAILABLE, 2, "unavailable count")
AssertEqual(result.exactStats, 3, "exact stat count")
AssertEqual(result.fallbackStats, 1, "fallback stat count")

local byID = {}
for _, row in ipairs(result.rows) do
    if row.recipeID then byID[row.recipeID] = row end
end
AssertEqual(byID[100].status, "PASS", "required/optional slot pass")
AssertEqual(#byID[100].findings, 0, "optional slots ignored")
AssertEqual(byID[101].status, "MISMATCH", "mismatch classification")
assert(#byID[101].findings == 3, "quantity/output/yield mismatches were not all reported")
AssertEqual(byID[102].status, "PASS", "salvage quantity pass")
AssertEqual(byID[102].statStatus, "fallback", "salvage stat fallback")
AssertEqual(byID[103].status, "UNLEARNED", "unlearned classification")
AssertEqual(byID[104].status, "UNAVAILABLE", "unavailable classification")
local missingID = nil
for _, row in ipairs(result.rows) do
    if row.strategyID == "audit__user_missing_id" then missingID = row end
end
assert(missingID and missingID.status == "UNAVAILABLE", "missing user ID classification")
AssertEqual(missingID.findings[1].code, "missing_recipe_id", "missing user ID detail")

local report = GAM.RecipeAudit.BuildReport(result)
assert(report:find("scope=Inscription", 1, true), "report scope missing")
assert(report:find("mismatch=1", 1, true), "report summary missing")
assert(report:find("reagent_quantity", 1, true), "report detail missing")

print("PASS: live recipe schematic audit classification and report")
