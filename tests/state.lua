-- Offline regression checks for rank-scoped state and legacy favorites.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {
    C = {
        DEFAULT_PATCH = "midnight-1",
        DEFAULT_STARTING_CRAFTS = 1000,
        MIN_STARTING_CRAFTS = 1,
        MAX_STARTING_CRAFTS = 1000000,
    },
    db = {
        options = {},
        patch = {},
        priceCache = {},
        scanState = {},
        itemKeyDB = {},
        userStrats = {},
    },
}
local TestLoader = assert(loadfile("../tests/TestLoader.lua"))()

function wipe(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end

TestLoader.LoadModuleWithFixture(
    "State.lua",
    "../tests/fixtures/StateSmoke.lua",
    ADDON_NAME,
    GAM)

local ok, err = GAM.State.RunSmokeChecks()
assert(ok, err)

assert(GAM.State.GetGlobalStartingCrafts() == 1000,
    "missing global starting crafts did not use the default")
local normalized, normalizeErr = GAM.State.SetGlobalStartingCrafts("2,500")
assert(normalized == 2500 and not normalizeErr,
    "comma-formatted global starting crafts was not accepted")
assert(GAM.State.GetGlobalStartingCrafts() == 2500,
    "global starting crafts was not persisted")
normalized, normalizeErr = GAM.State.SetGlobalStartingCrafts("10.5")
assert(normalized == nil and normalizeErr,
    "fractional global starting crafts was accepted")
assert(GAM.State.GetGlobalStartingCrafts() == 2500,
    "invalid global starting crafts changed the saved value")

print("PASS: rank-scoped state and legacy favorite migration")
