-- Offline regression checks for CraftSim integration and profession mapping.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {}

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
    return chunk()
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

LoadModule("CraftingStatsV2.lua")
LoadModule("CraftSimPriceOverrides.lua")
LoadModule("CraftSimBridge.lua")

local ok, err = GAM.CraftSimBridge.RunSmokeChecks()
assert(ok, err)

print("PASS: CraftSim bridge uses the shared profession registry")
