-- Offline regression checks for shared profession and crafting-stat ownership.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {}
local TestLoader = assert(loadfile("../tests/TestLoader.lua"))()

local function LoadGlobal(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk(ADDON_NAME, GAM)
end

local function LoadModule(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk(ADDON_NAME, GAM)
end

LoadGlobal("Data/WorkbookGenerated.lua")
for _, profession in ipairs({
    "Alchemy",
    "Blacksmithing",
    "Enchanting",
    "Engineering",
    "Inscription",
    "Jewelcrafting",
    "Leatherworking",
    "Tailoring",
}) do
    LoadGlobal("Data/SpecializationData/Midnight/" .. profession .. ".lua")
end
LoadModule("Constants.lua")
LoadModule("ProfessionNodeDisplay.lua")
LoadModule("CraftingStatsCache.lua")
LoadModule("CraftingStatsSpecialization.lua")
LoadModule("CraftingStatsCapture.lua")
LoadModule("CraftingStatsGear.lua")
LoadModule("CraftingStatsResolution.lua")

GAM.Log = {
    Info = function() end,
    Warn = function() end,
    Debug = function() end,
}

TestLoader.LoadModuleWithFixture(
    "CraftingStats.lua",
    "../tests/fixtures/CraftingStatsSmoke.lua",
    ADDON_NAME,
    GAM)
assert(GAM.CraftingStatsV2 == GAM.CraftingStats,
    "legacy crafting-stats alias is unavailable")
LoadModule("CraftingStatsDiagnostics.lua")

local ok, err = GAM.CraftingStats.RunSmokeChecks()
assert(ok, err)

local cooking = GAM.CraftingStats.GetProfile("cooking")
assert(cooking and cooking.profileKey == "cooking", "Cooking stat profile is unavailable")
assert(cooking.supportsMulticraft and cooking.supportsResourcefulness,
    "Cooking stat capabilities are incomplete")
assert(cooking.fallbackReason == nil,
    "Known workbook profile was incorrectly labeled missing-profile")

local unknown = GAM.CraftingStats.GetProfile("unknown_profile")
assert(unknown and unknown.fallbackReason == "missing-profile",
    "Unknown stat profile did not retain its missing-profile diagnostic")

print("PASS: shared profession registry and crafting-stat resolution")
