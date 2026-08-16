-- Offline fixtures for SavedVariables initialization and migration ordering.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {}

function wipe(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end

SlashCmdList = {}
UIParent = {}

function CreateFrame()
    local frame = { scripts = {}, events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(kind, callback) self.scripts[kind] = callback end
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

local function AssertEqual(actual, expected, label)
    assert(actual == expected,
        string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

LoadGlobal("Data/WorkbookGenerated.lua")
LoadModule("Constants.lua")

GAM.Log = {
    Init = function() end,
    Info = function() end,
    Warn = function() end,
    Debug = function() end,
}
GAM.L = { LOADED_MSG = "loaded" }
GAM.Importer = { Init = function() end }
GAM.Minimap = { Init = function() end }
GAM.Settings = { Init = function() end }
GAM.AHScan = {
    SetScanDelay = function() end,
    SetProgressCallback = function() end,
}

LoadModule("Core.lua")

local onEvent = GAM._eventFrame and GAM._eventFrame.scripts.OnEvent
assert(type(onEvent) == "function", "Core did not register its event dispatcher")

local savedUser = { id = "legacy-user-strategy", sentinel = true }
local savedUsers = { savedUser }
local savedPrices = { realm = { [241334] = { price = 12345 } } }
GoldAdvisorMidnightDB = {
    dataVersion = 9,
    addonVersion = "1.9.0-testing",
    options = {
        autoOpenWithAH = false,
        closeWithAH = true,
        pricingEngine = "legacy",
        customSentinel = "preserve-me",
    },
    userStrats = savedUsers,
    priceCache = savedPrices,
}

onEvent(GAM._eventFrame, "ADDON_LOADED", ADDON_NAME)

local upgraded = GoldAdvisorMidnightDB
AssertEqual(upgraded.dataVersion, GAM.C.DATA_VERSION,
    "migration version matches release metadata")
AssertEqual(upgraded.dataVersion, 18, "legacy fixture data version")
AssertEqual(upgraded.strategySchemaVersion, 1, "legacy fixture strategy schema")
AssertEqual(upgraded.addonVersion, "2.0.1", "legacy fixture addon version")
AssertEqual(upgraded.options.rememberAHWindowState, false,
    "legacy disabled AH auto-open preference")
AssertEqual(upgraded.options.lastAHWindowOpen, false,
    "legacy disabled AH window state")
assert(upgraded.options.autoOpenWithAH == nil, "legacy auto-open key was not retired")
assert(upgraded.options.closeWithAH == nil, "legacy close-with-AH key was not retired")
assert(upgraded.options.pricingEngine == nil, "legacy pricing-engine key was not retired")
AssertEqual(upgraded.options.customSentinel, "preserve-me", "custom option preservation")
AssertEqual(upgraded.options.v2PricingMode, "exhaust_materials",
    "legacy fixture Exhaust Materials migration")
assert(upgraded.userStrats == savedUsers and upgraded.userStrats[1] == savedUser,
    "user strategies changed identity during migration")
assert(upgraded.priceCache == savedPrices, "price cache table changed identity")

GoldAdvisorMidnightDB = {}
onEvent(GAM._eventFrame, "ADDON_LOADED", ADDON_NAME)

local fresh = GoldAdvisorMidnightDB
AssertEqual(fresh.dataVersion, 18, "fresh fixture data version")
AssertEqual(fresh.strategySchemaVersion, 1, "fresh fixture strategy schema")
AssertEqual(fresh.options.rememberAHWindowState, true, "fresh AH preference default")
AssertEqual(fresh.options.v2PricingMode, "exhaust_materials",
    "fresh Exhaust Materials default")
assert(fresh.options.pricingEngine == nil, "fresh database retained pricing-engine option")
assert(type(fresh.userStrats) == "table", "fresh user strategy container missing")
assert(type(fresh.patch) == "table" and type(fresh.priceCache) == "table",
    "fresh database containers missing")

print("PASS: SavedVariables migrations run before defaults and preserve user data")
