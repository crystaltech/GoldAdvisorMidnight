-- Offline regression checks for CraftSim integration and profession mapping.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {}
local TestLoader = assert(loadfile("../tests/TestLoader.lua"))()

function CreateFrame()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:UnregisterAllEvents() end
    function frame:SetScript() end
    return frame
end

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
LoadModule("Constants.lua")

GAM.Log = {
    Info = function() end,
    Warn = function() end,
    Debug = function() end,
}
GAM.Pricing = {}

LoadModule("CraftingStatsCache.lua")
LoadModule("CraftingStatsSpecialization.lua")
LoadModule("CraftingStatsCapture.lua")
LoadModule("CraftingStatsGear.lua")
LoadModule("CraftingStatsResolution.lua")
LoadModule("CraftingStats.lua")
LoadModule("CraftSimPriceOverrides.lua")
TestLoader.LoadModuleWithFixture(
    "CraftSimBridge.lua",
    "../tests/fixtures/CraftSimBridgeSmoke.lua",
    ADDON_NAME,
    GAM)

local ok, err = GAM.CraftSimBridge.RunSmokeChecks()
assert(ok, err)

print("PASS: CraftSim bridge uses the shared profession registry")
