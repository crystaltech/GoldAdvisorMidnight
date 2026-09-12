-- Verify that production and Dev data can coexist in one WoW Lua process.

local function Load(path, addonName, addonTable)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk(addonName, addonTable)
end

local production = {}
local development = {}

for _, target in ipairs({
    { name = "GoldAdvisorMidnight", namespace = production },
    { name = "GoldAdvisorMidnightDev", namespace = development },
}) do
    Load("Data/WorkbookGenerated.lua", target.name, target.namespace)
    Load("Data/CommodityManifest.lua", target.name, target.namespace)
    Load("Data/ProfessionCrafts.lua", target.name, target.namespace)
    Load("Data/ProfessionCraftsPatch12_1.lua", target.name, target.namespace)
    Load("Data/RecipesGenerated.lua", target.name, target.namespace)
    Load("Data/Recipes/Patch12_1.lua", target.name, target.namespace)
    Load("Data/SpecializationData/Midnight/Blacksmithing.lua", target.name, target.namespace)
    Load("Constants.lua", target.name, target.namespace)
end

assert(production.WorkbookGenerated ~= development.WorkbookGenerated,
    "workbook data leaked across addon namespaces")
assert(production.CommodityManifest ~= development.CommodityManifest,
    "commodity manifest leaked across addon namespaces")
assert(production.RecipesGenerated ~= development.RecipesGenerated,
    "recipe catalog leaked across addon namespaces")
assert(production.SpecializationData ~= development.SpecializationData,
    "specialization catalog leaked across addon namespaces")
assert(#production.RecipesGenerated == 607 and #development.RecipesGenerated == 607,
    "side-by-side recipe loading duplicated or lost strategies")
assert(production.RuntimeName("GAMWindow") == "GAMWindow",
    "production runtime name changed")
assert(development.RuntimeName("GAMWindow") == "GAMWindowDev",
    "Dev runtime name was not isolated")
assert(development.C.IS_DEV_BUILD
        and development.C.PRIMARY_SLASH_COMMAND == "/gamdev"
        and development.C.ADDON_DISPLAY_NAME == "Gold Advisor Midnight Dev",
    "Dev identity constants are incomplete")
assert(GAM_WORKBOOK_GENERATED == nil
        and GAM_COMMODITY_MANIFEST == nil
        and GAM_RECIPES_GENERATED == nil
        and GAM_SPECIALIZATION_DATA == nil,
    "legacy process-global data tables were published")

print("PASS: production and Dev addon data identities coexist")
