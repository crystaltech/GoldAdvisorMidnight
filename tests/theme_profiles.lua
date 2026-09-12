local GAM = { C = { USE_COMFORTABLE_UI = true }, UI = {}, db = { options = {} } }
local player = "Alice"
function UnitName() return player end
function GetRealmName() return "TestRealm" end
assert(loadfile("UI/MainWindowCommon.lua"))("GoldAdvisorMidnight", GAM)
local common = GAM.UI.MainWindowCommon
assert(common.CreateThemeProfile("Saved"))
assert(common.SetThemeProfileColor("Saved", "accent", {0.2, 0.3, 0.4, 1}))
local saved = GAM.db.themeProfiles.Saved
assert(common.SetActiveThemeProfile(common.THEME_PROFILE_DEFAULT))
assert(not common.CreateThemeProfile(" Saved "), "duplicate name must not overwrite saved colors")
assert(GAM.db.themeProfiles.Saved == saved and saved.accent[1] == 0.2)
assert(common.GetActiveThemeProfileName() == common.THEME_PROFILE_DEFAULT,
    "rejected creation must not change the active profile")

assert(common.SetActiveThemeProfile("Saved"))
player = "Bob"
assert(common.SetActiveThemeProfile("Saved"))
player = "Alice"
assert(common.DeleteThemeProfile("Saved"))
assert(common.CreateThemeProfile("Saved"))
player = "Bob"
assert(common.GetActiveThemeProfileName() == common.THEME_PROFILE_DEFAULT,
    "reusing a deleted name must not switch another character to the new profile")

for i = 1, 40 do assert(common.CreateThemeProfile("Profile " .. i)) end
local names = common.GetThemeProfileNames()
assert(#names == 42 and names[1] == common.THEME_PROFILE_DEFAULT)
for i = 3, #names do assert(names[i - 1]:lower() <= names[i]:lower()) end
print("PASS: theme profiles preserve duplicate names and clear deleted character selections")
