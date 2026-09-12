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
    return chunk(ADDON_NAME, GAM)
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
LoadModule("State.lua")

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
        v2Theme = "soft",
        customSentinel = "preserve-me",
    },
    userStrats = savedUsers,
    priceCache = savedPrices,
}

onEvent(GAM._eventFrame, "ADDON_LOADED", ADDON_NAME)

local upgraded = GoldAdvisorMidnightDB
AssertEqual(upgraded.dataVersion, GAM.C.DATA_VERSION,
    "migration version matches release metadata")
AssertEqual(upgraded.dataVersion, 20, "legacy fixture data version")
AssertEqual(upgraded.strategySchemaVersion, 1, "legacy fixture strategy schema")
AssertEqual(upgraded.addonVersion, GAM.C.ADDON_VERSION, "legacy fixture addon version")
AssertEqual(upgraded.options.rememberAHWindowState, false,
    "legacy disabled AH auto-open preference")
AssertEqual(upgraded.options.lastAHWindowOpen, false,
    "legacy disabled AH window state")
assert(upgraded.options.autoOpenWithAH == nil, "legacy auto-open key was not retired")
assert(upgraded.options.closeWithAH == nil, "legacy close-with-AH key was not retired")
assert(upgraded.options.pricingEngine == nil, "legacy pricing-engine key was not retired")
assert(upgraded.options.v2Theme == nil, "unused theme option was not retired")
AssertEqual(upgraded.options.globalStartingCrafts, 50,
    "legacy fixture global starting-crafts default")
AssertEqual(upgraded.options.customSentinel, "preserve-me", "custom option preservation")
AssertEqual(upgraded.options.v2PricingMode, "exhaust_materials",
    "legacy fixture Exhaust Materials migration")
assert(upgraded.userStrats == savedUsers and upgraded.userStrats[1] == savedUser,
    "user strategies changed identity during migration")
assert(upgraded.priceCache == savedPrices, "price cache table changed identity")

-- Upgrade the actual prior production schema without importing isolated Dev data.
local geometry = { width = 1280, height = 800, point = "TOPLEFT", x = 20, y = -20 }
local gear = { sentinel = "saved-gear" }
local favorites = { alloy = true }
local profile = { Saved = { sentinel = "saved-colors" } }
local devSentinel = { options = { globalStartingCrafts = 999 }, untouched = true }
GoldAdvisorMidnightDevDB = devSentinel
local previous = {
    dataVersion = 19, addonVersion = "2.0.10",
    options = { globalStartingCrafts = 1000, mainWindowGeometry = geometry,
        mainDetailSize = { width = 500, height = 650 }, uiScale = 0.9,
        customSentinel = "keep" },
    userStrats = savedUsers, priceCache = savedPrices,
    patch = { [GAM.C.DEFAULT_PATCH] = { favorites = favorites,
        startingAmounts = { alloy = 250 }, priceOverrides = { [238198] = 490000 } } },
    v2StatCache = { version = 2, characters = { Character = { gearPresets = gear } } },
    themeProfiles = profile,
    themeProfileSelections = { Character = "Saved" }, activeThemeProfile = "Saved",
}
GoldAdvisorMidnightDB = previous
onEvent(GAM._eventFrame, "ADDON_LOADED", ADDON_NAME)
assert(GAM.db == previous and GoldAdvisorMidnightDB == previous,
    "production upgrade replaced the existing database")
assert(previous.dataVersion == 20 and previous.addonVersion == "2.1.0")
assert(previous.options.globalStartingCrafts == 1000
    and previous.patch[GAM.C.DEFAULT_PATCH].startingAmounts.alloy == 250
    and previous.options.uiScale == 0.9 and previous.options.customSentinel == "keep")
assert(previous.options.mainWindowGeometry == geometry
    and previous.options.mainDetailSize.width == 500 and previous.options.mainDetailSize.height == 650)
assert(previous.userStrats == savedUsers and previous.priceCache == savedPrices
    and previous.v2StatCache.characters.Character.gearPresets == gear
    and previous.patch[GAM.C.DEFAULT_PATCH].favorites == favorites
    and previous.patch[GAM.C.DEFAULT_PATCH].priceOverrides[238198] == 490000)
assert(previous.themeProfiles == profile and previous.activeThemeProfile == "Saved"
    and previous.themeProfileSelections.Character == "Saved")
onEvent(GAM._eventFrame, "ADDON_LOADED", ADDON_NAME)
assert(previous.options.mainWindowGeometry == geometry and previous.themeProfiles == profile,
    "repeated initialization changed saved state")
assert(GoldAdvisorMidnightDevDB == devSentinel and devSentinel.untouched,
    "production initialization touched the isolated development database")

GoldAdvisorMidnightDB = {}
onEvent(GAM._eventFrame, "ADDON_LOADED", ADDON_NAME)

local fresh = GoldAdvisorMidnightDB
AssertEqual(fresh.dataVersion, 20, "fresh fixture data version")
AssertEqual(fresh.strategySchemaVersion, 1, "fresh fixture strategy schema")
AssertEqual(fresh.options.rememberAHWindowState, true, "fresh AH preference default")
AssertEqual(fresh.options.v2PricingMode, "exhaust_materials",
    "fresh Exhaust Materials default")
assert(fresh.options.pricingEngine == nil, "fresh database retained pricing-engine option")
assert(fresh.options.v2Theme == nil, "fresh database retained theme option")
AssertEqual(fresh.options.globalStartingCrafts, 50,
    "fresh global starting-crafts default")
assert(type(fresh.userStrats) == "table", "fresh user strategy container missing")
assert(type(fresh.patch) == "table" and type(fresh.priceCache) == "table",
    "fresh database containers missing")
assert(type(fresh.vendorPriceCache) == "table"
        and type(fresh.vendorPriceCache.characters) == "table",
    "fresh live vendor-price cache missing")

local slashCommand = assert(SlashCmdList.GOLDADVISORMIDNIGHT,
    "GAM production slash command was not registered")
AssertEqual(SLASH_GOLDADVISORMIDNIGHT1, "/gam",
    "GAM production primary slash command")
AssertEqual(SLASH_GOLDADVISORMIDNIGHT2, "/goldadvisor",
    "GAM production secondary slash command")
local originalPrint = print
print = function() end
slashCommand("globalstartqty 2,500")
print = originalPrint
AssertEqual(fresh.options.globalStartingCrafts, 2500,
    "slash command global starting-crafts update")
print = function() end
slashCommand("globalstartqty 2.5")
print = originalPrint
AssertEqual(fresh.options.globalStartingCrafts, 2500,
    "invalid slash command changed global starting crafts")

print("PASS: SavedVariables migrations run before defaults and preserve user data")
