-- Offline tests for account-wide craft cooldown tracking.

local failures = 0

local function Check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. message .. "\n")
    end
end

local epochNow = 1700000000
local sessionNow = 1000

function time() return epochNow end
function GetTime() return sessionNow end
function UnitName() return "Alpha" end
function GetRealmName() return "TestRealm" end

GoldAdvisorMidnightDB = {
    v2StatCache = {
        version = 2,
        characters = {
            ["Beta-TestRealm"] = {
                uid = "Beta-TestRealm",
                name = "Beta",
                realm = "TestRealm",
            },
        },
    },
}

local learned = {
    [101] = true,
    [102] = true,
    [103] = false,
    [104] = true,
}

C_TradeSkillUI = {
    GetRecipeInfo = function(recipeID)
        return { recipeID = recipeID, name = "Recipe " .. recipeID, learned = learned[recipeID] }
    end,
    IsRecipeProfessionLearned = function(recipeID)
        return learned[recipeID]
    end,
    GetTradeSkillLineForRecipe = function()
        return 2871, "Tailoring"
    end,
}

C_Spell = {
    GetSpellCooldown = function(recipeID)
        if recipeID == 101 then
            return { startTime = 990, duration = 3610, isEnabled = true, modRate = 1 }
        end
        return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
    end,
    GetSpellCharges = function(recipeID)
        if recipeID == 102 then
            return {
                currentCharges = 0,
                maxCharges = 2,
                cooldownStartTime = 980,
                cooldownDuration = 120,
                chargeModRate = 1,
            }
        end
        return nil
    end,
}

local GAM = { db = GoldAdvisorMidnightDB }
assert(loadfile("CooldownTracker.lua"))("GoldAdvisorMidnight", GAM)
local Tracker = GAM.CooldownTracker

Check(Tracker.GetCurrentCrafterUID() == "Alpha-TestRealm", "current crafter UID uses name and realm")

local ok = Tracker.TrackRecipe("Alpha-TestRealm", {
    recipeID = 101,
    recipeName = "Daily Bolt",
    profession = "Tailoring",
})
Check(ok, "current character recipe can be tracked")
Tracker.RefreshCurrentCharacter()

local rows, isCurrent = Tracker.GetTrackedRows("Alpha-TestRealm")
Check(isCurrent, "current character is identified in tracked rows")
Check(#rows == 1, "current character has one tracked recipe")
Check(rows[1].readyAt == epochNow + 3600, "session cooldown is converted to an absolute epoch timestamp")
local status, statusKind = Tracker.GetDisplayStatus(rows[1], epochNow)
Check(status == "1h 0m" and statusKind == "cooldown", "cooldown has a readable display status")

ok = Tracker.TrackRecipe("Alpha-TestRealm", {
    recipeID = 102,
    recipeName = "Charged Weave",
    profession = "Tailoring",
})
Check(ok, "charged recipe can be tracked")
Tracker.RefreshCurrentCharacter(102)
rows = Tracker.GetTrackedRows("Alpha-TestRealm")
local charged
for _, row in ipairs(rows) do
    if row.recipeID == 102 then charged = row end
end
Check(charged and charged.currentCharges == 0 and charged.maxCharges == 2,
    "recipe charges are cached")
Check(charged and charged.nextChargeAt == epochNow + 100,
    "next charge is stored as an absolute epoch timestamp")
local chargeText, chargeKind = Tracker.GetDisplayStatus(charged, epochNow)
Check(chargeText:find("1m 40s", 1, true) ~= nil and chargeKind == "cooldown",
    "next charge countdown is shown")

Tracker.TrackRecipe("Alpha-TestRealm", { recipeID = 103, recipeName = "Unknown Pattern" })
Tracker.RefreshCurrentCharacter(103)
rows = Tracker.GetTrackedRows("Alpha-TestRealm")
local unlearned
for _, row in ipairs(rows) do
    if row.recipeID == 103 then unlearned = row end
end
Check(unlearned and unlearned.lastStatus == "unlearned", "unlearned recipes are explicit")

ok = Tracker.TrackRecipe("Beta-TestRealm", {
    recipeID = 101,
    recipeName = "Daily Bolt",
    profession = "Tailoring",
})
Check(ok, "an offline cached crafter can be assigned a recipe")
local altRows, altIsCurrent = Tracker.GetTrackedRows("Beta-TestRealm")
Check(not altIsCurrent and #altRows == 1, "offline crafter row remains separate")
Check(altRows[1].lastCheckedAt == nil, "refreshing current crafter does not overwrite an offline crafter")
Check(Tracker.GetDisplayStatus(altRows[1], epochNow) == "Refresh on crafter",
    "offline pending recipe asks for a crafter refresh")

ProfessionsFrame = {
    CraftingPage = {
        SchematicForm = {
            GetRecipeInfo = function()
                return { recipeID = 104, name = "Open Recipe" }
            end,
        },
    },
}
ok = Tracker.TrackOpenRecipe()
Check(ok, "currently open Blizzard profession recipe can be tracked")
rows = Tracker.GetTrackedRows("Alpha-TestRealm")
local foundOpen = false
for _, row in ipairs(rows) do
    if row.recipeID == 104 and row.name == "Recipe 104" then foundOpen = true end
end
Check(foundOpen, "open recipe is attached to the logged-in crafter and refreshed")

Check(Tracker.UntrackRecipe("Beta-TestRealm", 101), "tracked alt recipe can be removed")
altRows = Tracker.GetTrackedRows("Beta-TestRealm")
Check(#altRows == 0, "removed alt recipe no longer appears")

local characters = Tracker.GetCharacters()
Check(#characters == 2 and characters[1].uid == "Alpha-TestRealm" and characters[1].isCurrent,
    "character picker lists current crafter first")

GAM.UI = {}
assert(loadfile("UI/CooldownTrackerWindow.lua"))("GoldAdvisorMidnight", GAM)
local CooldownWindow = GAM.UI.CooldownTrackerWindow
local visible, hostHeight, menuHeight, overflow = CooldownWindow.GetCrafterMenuMetrics(9)
Check(visible == 6 and hostHeight == 198 and menuHeight == 136 and overflow,
    "crafter dropdown does not cap and scroll after six characters")
visible, hostHeight, menuHeight, overflow = CooldownWindow.GetCrafterMenuMetrics(2)
Check(visible == 2 and hostHeight == 44 and menuHeight == 48 and not overflow,
    "small crafter dropdown uses unnecessary scroll space")

if failures > 0 then
    os.exit(1)
end

print("PASS: craft cooldown tracker")
