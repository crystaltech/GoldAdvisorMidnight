-- Production identity, UI defaults, and private catalog initialization.

local function Load(path, addonName, addonTable)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk(addonName, addonTable)
end

local production = {}
local secondLoad = {}

for _, target in ipairs({
    { name = "GoldAdvisorMidnight", namespace = production },
    { name = "GoldAdvisorMidnight", namespace = secondLoad },
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

assert(production.WorkbookGenerated ~= secondLoad.WorkbookGenerated,
    "workbook data leaked across addon namespaces")
assert(production.CommodityManifest ~= secondLoad.CommodityManifest,
    "commodity manifest leaked across addon namespaces")
assert(production.RecipesGenerated ~= secondLoad.RecipesGenerated,
    "recipe catalog leaked across addon namespaces")
assert(production.SpecializationData ~= secondLoad.SpecializationData,
    "specialization catalog leaked across addon namespaces")
assert(#production.RecipesGenerated == 607 and #secondLoad.RecipesGenerated == 607,
    "side-by-side recipe loading duplicated or lost strategies")
assert(production.RuntimeName("GAMWindow") == "GAMWindow",
    "production runtime name changed")
assert(production.C.ADDON_ID == "GoldAdvisorMidnight"
        and production.C.PRIMARY_SLASH_COMMAND == "/gam"
        and production.C.ADDON_DISPLAY_NAME == "Gold Advisor Midnight"
        and production.C.ADDON_VERSION == "2.1.0",
    "production identity constants are incomplete")
production.UI = {}
Load("UI/MainWindowCommon.lua", "GoldAdvisorMidnight", production)
local common = production.UI.MainWindowCommon
for _, opts in ipairs({ {}, { v2Theme = "classic" }, { v2Theme = "soft" } }) do
    assert(common.GetThemeKey(opts) == "comfortable",
        "production identity or obsolete theme setting disabled Comfortable")
end
assert(common.GetThemeDef({}).frame == common.THEMES.comfortable.frame,
    "production default appearance is not Comfortable")
assert(GAM_WORKBOOK_GENERATED == nil
        and GAM_COMMODITY_MANIFEST == nil
        and GAM_RECIPES_GENERATED == nil
        and GAM_SPECIALIZATION_DATA == nil,
    "legacy process-global data tables were published")

print("PASS: production identity retains Comfortable and private catalog data")
