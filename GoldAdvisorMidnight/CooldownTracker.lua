-- GoldAdvisorMidnight/CooldownTracker.lua
-- Account-wide tracked profession cooldowns, refreshed by the logged-in crafter.
-- Module: GAM.CooldownTracker

local ADDON_NAME, GAM = ...

local Tracker = {}
GAM.CooldownTracker = Tracker

local GCD_MAX_SECONDS = 1.5
local runtimeRevision = 0
local changedCallback
local eventFrame
local refreshGeneration = 0

local function EpochNow()
    if type(time) == "function" then
        return time()
    end
    if os and type(os.time) == "function" then
        return os.time()
    end
    return 0
end

local function SessionNow()
    if type(GetTime) == "function" then
        return GetTime()
    end
    return 0
end

local function IsRestricted(value)
    if type(issecretvalue) ~= "function" then
        return false
    end
    local ok, result = pcall(issecretvalue, value)
    return ok and result and true or false
end

local function SafeNumber(value)
    if value == nil or IsRestricted(value) then
        return nil
    end
    local ok, number = pcall(tonumber, value)
    if not ok then
        return nil
    end
    return number
end

local function CurrentIdentity()
    local name = type(UnitName) == "function" and UnitName("player") or nil
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil
    name = name or "Unknown"
    realm = realm or "Unknown"
    return name .. "-" .. realm, name, realm
end

local function EnsureCache()
    local db = GAM.db or GoldAdvisorMidnightDB
    if type(db) ~= "table" then
        return nil
    end

    db.v2StatCache = type(db.v2StatCache) == "table" and db.v2StatCache or {}
    local cache = db.v2StatCache
    cache.version = tonumber(cache.version) or 2
    cache.characters = type(cache.characters) == "table" and cache.characters or {}

    local uid, name, realm = CurrentIdentity()
    cache.characters[uid] = type(cache.characters[uid]) == "table" and cache.characters[uid] or {}
    local character = cache.characters[uid]
    character.uid = uid
    character.name = name
    character.realm = realm
    return cache, character, uid
end

local function EnsureTrackerShape(character)
    if type(character) ~= "table" then
        return nil
    end
    character.cooldownTracker = type(character.cooldownTracker) == "table"
        and character.cooldownTracker or {}
    local data = character.cooldownTracker
    data.tracked = type(data.tracked) == "table" and data.tracked or {}
    data.recipes = type(data.recipes) == "table" and data.recipes or {}
    return data
end

local function Touch()
    runtimeRevision = runtimeRevision + 1
    local cache = EnsureCache()
    if cache then
        cache.revision = (tonumber(cache.revision) or 0) + 1
    end
    if changedCallback then
        pcall(changedCallback, runtimeRevision)
    end
end

local function GetCharacter(uid)
    local cache, currentCharacter, currentUID = EnsureCache()
    if not cache then
        return nil, nil, nil
    end
    uid = uid or currentUID
    local character = cache.characters[uid]
    if not character and uid == currentUID then
        character = currentCharacter
    end
    if type(character) ~= "table" then
        return nil, currentUID, cache
    end
    character.uid = character.uid or uid
    EnsureTrackerShape(character)
    return character, currentUID, cache
end

local function CopyIdentity(target, identity)
    if type(identity) ~= "table" then
        return
    end
    target.name = identity.recipeName or identity.name or identity.stratName or target.name
    target.profession = identity.profession or target.profession
    target.icon = identity.icon or target.icon
    target.strategyID = identity.id or identity.strategyID or target.strategyID
end

function Tracker.GetRevision()
    return runtimeRevision
end

function Tracker.SetChangedCallback(callback)
    changedCallback = type(callback) == "function" and callback or nil
end

function Tracker.GetCurrentCrafterUID()
    local uid = CurrentIdentity()
    return uid
end

function Tracker.GetCharacters()
    local cache, _, currentUID = EnsureCache()
    local rows = {}
    if not cache then
        return rows
    end

    for uid, character in pairs(cache.characters) do
        if type(character) == "table" then
            local name = character.name
            local realm = character.realm
            if not name or name == "" then
                name = tostring(uid):match("^(.-)%-(.+)$") or tostring(uid)
            end
            rows[#rows + 1] = {
                uid = uid,
                name = name,
                realm = realm,
                label = realm and realm ~= "" and (name .. " - " .. realm) or tostring(uid),
                isCurrent = uid == currentUID,
                trackedCount = (function()
                    local count = 0
                    local data = EnsureTrackerShape(character)
                    for _, tracked in pairs(data.tracked) do
                        if tracked then count = count + 1 end
                    end
                    return count
                end)(),
            }
        end
    end

    table.sort(rows, function(a, b)
        if a.isCurrent ~= b.isCurrent then
            return a.isCurrent
        end
        return a.label:lower() < b.label:lower()
    end)
    return rows
end

function Tracker.TrackRecipe(uid, identity)
    local recipeID = type(identity) == "table" and SafeNumber(identity.recipeID) or SafeNumber(identity)
    if not recipeID or recipeID <= 0 then
        return false, "missing_recipe"
    end

    local character = GetCharacter(uid)
    if not character then
        return false, "unknown_crafter"
    end
    local data = EnsureTrackerShape(character)
    data.tracked[recipeID] = true
    data.recipes[recipeID] = type(data.recipes[recipeID]) == "table" and data.recipes[recipeID] or {
        recipeID = recipeID,
        lastStatus = "pending",
    }
    CopyIdentity(data.recipes[recipeID], identity)
    Touch()
    return true, data.recipes[recipeID]
end

function Tracker.UntrackRecipe(uid, recipeID)
    recipeID = SafeNumber(recipeID)
    local character = GetCharacter(uid)
    if not character or not recipeID then
        return false
    end
    local data = EnsureTrackerShape(character)
    if not data.tracked[recipeID] then
        return false
    end
    data.tracked[recipeID] = nil
    data.recipes[recipeID] = nil
    Touch()
    return true
end

local function GetOpenRecipeInfo()
    local form = ProfessionsFrame
        and ProfessionsFrame.CraftingPage
        and ProfessionsFrame.CraftingPage.SchematicForm
    if not form then
        return nil
    end

    local ok, recipeInfo = pcall(function()
        if type(form.GetRecipeInfo) == "function" then
            return form:GetRecipeInfo()
        end
        return form.recipeInfo
    end)
    if not ok or type(recipeInfo) ~= "table" or not SafeNumber(recipeInfo.recipeID) then
        return nil
    end

    local identity = {
        recipeID = SafeNumber(recipeInfo.recipeID),
        recipeName = recipeInfo.name,
        icon = recipeInfo.icon or recipeInfo.iconTexture,
    }
    if C_TradeSkillUI and type(C_TradeSkillUI.GetTradeSkillLineForRecipe) == "function" then
        local okProfession, _, profession = pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, identity.recipeID)
        if okProfession then
            identity.profession = profession
        end
    end
    return identity
end

function Tracker.GetOpenRecipeIdentity()
    return GetOpenRecipeInfo()
end

function Tracker.TrackOpenRecipe()
    local identity = GetOpenRecipeInfo()
    if not identity then
        return false, "no_open_recipe"
    end
    local uid = Tracker.GetCurrentCrafterUID()
    local ok, result = Tracker.TrackRecipe(uid, identity)
    if ok then
        Tracker.RefreshCurrentCharacter(identity.recipeID)
    end
    return ok, result
end

local function RemainingToEpoch(startTime, duration, modRate)
    startTime = SafeNumber(startTime)
    duration = SafeNumber(duration)
    modRate = SafeNumber(modRate) or 1
    if not startTime or not duration or modRate <= 0 then
        return nil
    end
    local elapsed = math.max(0, SessionNow() - startTime)
    local remaining = (duration / modRate) - elapsed
    if remaining <= 0 then
        return nil
    end
    return EpochNow() + remaining
end

local function GetRecipeLearned(recipeID)
    if not C_TradeSkillUI then
        return nil, nil
    end
    local recipeInfo
    if type(C_TradeSkillUI.GetRecipeInfo) == "function" then
        local ok, result = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and type(result) == "table" then
            recipeInfo = result
        end
    end
    if type(C_TradeSkillUI.IsRecipeProfessionLearned) == "function" then
        local ok, learned = pcall(C_TradeSkillUI.IsRecipeProfessionLearned, recipeID)
        if ok and not IsRestricted(learned) then
            return learned and true or false, recipeInfo
        end
    end
    if recipeInfo and recipeInfo.learned ~= nil and not IsRestricted(recipeInfo.learned) then
        return recipeInfo.learned and true or false, recipeInfo
    end
    return nil, recipeInfo
end

local function ReadTradeSkillCooldown(recipeID)
    if not C_TradeSkillUI or type(C_TradeSkillUI.GetRecipeCooldown) ~= "function" then
        return nil, "unavailable"
    end
    local ok, cooldown, isDayCooldown, currentCharges, maxCharges =
        pcall(C_TradeSkillUI.GetRecipeCooldown, recipeID)
    if not ok then
        return nil, "restricted"
    end

    -- Keep this tolerant of clients that expose the result as a structure
    -- instead of the traditional four return values.
    if type(cooldown) == "table" then
        local info = cooldown
        cooldown = info.cooldown or info.duration or info.cooldownDuration
        isDayCooldown = info.isDayCooldown
        currentCharges = info.charges or info.currentCharges
        maxCharges = info.maxCharges
    end
    if IsRestricted(cooldown) or IsRestricted(isDayCooldown)
            or IsRestricted(currentCharges) or IsRestricted(maxCharges) then
        return nil, "restricted"
    end
    cooldown = SafeNumber(cooldown)
    currentCharges = SafeNumber(currentCharges)
    maxCharges = SafeNumber(maxCharges)
    if cooldown == nil and currentCharges == nil and maxCharges == nil then
        return nil, "missing"
    end
    return {
        cooldown = cooldown,
        isDayCooldown = isDayCooldown and true or false,
        currentCharges = currentCharges,
        maxCharges = maxCharges,
    }
end

local function ReadCooldown(recipeID)
    local profession, professionErr = ReadTradeSkillCooldown(recipeID)
    if profession then
        local duration = profession.cooldown
        return {
            startTime = duration and SessionNow() or 0,
            duration = duration or 0,
            isEnabled = true,
            modRate = 1,
        }
    end
    if professionErr == "restricted" then
        return nil, professionErr
    end
    if not C_Spell or type(C_Spell.GetSpellCooldown) ~= "function" then
        return nil, "unavailable"
    end
    local ok, info = pcall(C_Spell.GetSpellCooldown, recipeID)
    if not ok then
        return nil, "restricted"
    end
    if type(info) ~= "table" then
        return nil, "missing"
    end
    if IsRestricted(info.startTime) or IsRestricted(info.duration) or IsRestricted(info.isEnabled) then
        return nil, "restricted"
    end
    return info
end

local function ReadCharges(recipeID)
    local profession, professionErr = ReadTradeSkillCooldown(recipeID)
    if profession and profession.currentCharges ~= nil
            and profession.maxCharges ~= nil and profession.maxCharges > 0 then
        local duration = profession.cooldown
        return {
            currentCharges = profession.currentCharges,
            maxCharges = profession.maxCharges,
            cooldownStartTime = duration and SessionNow() or 0,
            cooldownDuration = duration or 0,
            chargeModRate = 1,
        }
    end
    if professionErr == "restricted" then
        return nil, professionErr
    end
    if not C_Spell or type(C_Spell.GetSpellCharges) ~= "function" then
        return nil
    end
    local ok, info = pcall(C_Spell.GetSpellCharges, recipeID)
    if not ok or type(info) ~= "table" then
        return nil
    end
    if IsRestricted(info.currentCharges) or IsRestricted(info.maxCharges)
            or IsRestricted(info.cooldownStartTime) or IsRestricted(info.cooldownDuration) then
        return nil, "restricted"
    end
    return info
end

-- Returns the number of crafts that can be started immediately when Blizzard
-- exposes a charge/cooldown limit. Nil means no finite live limit was detected,
-- so callers should preserve their normal behavior instead of assuming zero.
function Tracker.GetImmediateCraftCapacity(recipeID)
    recipeID = SafeNumber(recipeID)
    if not recipeID then return nil, "invalid_recipe" end

    local charges, chargesErr = ReadCharges(recipeID)
    if chargesErr == "restricted" then return nil, "restricted" end
    local currentCharges = charges and SafeNumber(charges.currentCharges) or nil
    local maxCharges = charges and SafeNumber(charges.maxCharges) or nil
    if currentCharges ~= nil and maxCharges and maxCharges > 0 then
        return math.max(0, math.floor(currentCharges)), "charges"
    end

    local cooldown, cooldownErr = ReadCooldown(recipeID)
    if cooldownErr == "restricted" then return nil, "restricted" end
    local duration = cooldown and SafeNumber(cooldown.duration) or nil
    if duration and duration > GCD_MAX_SECONDS then
        local readyAt = RemainingToEpoch(cooldown.startTime, duration, cooldown.modRate)
        if readyAt and readyAt > EpochNow() then
            return 0, "cooldown"
        end
    end
    return nil, "unlimited_or_ready"
end

local function RefreshRecipe(row)
    local recipeID = row.recipeID
    local learned, recipeInfo = GetRecipeLearned(recipeID)
    if recipeInfo then
        row.name = recipeInfo.name or row.name
        row.icon = recipeInfo.icon or recipeInfo.iconTexture or row.icon
    end
    if learned == false then
        row.lastCheckedAt = EpochNow()
        row.lastStatus = "unlearned"
        row.readyAt = nil
        row.currentCharges = nil
        row.maxCharges = nil
        row.nextChargeAt = nil
        return
    end

    local cooldown, cooldownErr = ReadCooldown(recipeID)
    local charges, chargesErr = ReadCharges(recipeID)
    if cooldownErr == "restricted" or chargesErr == "restricted" then
        row.lastCheckedAt = EpochNow()
        row.lastStatus = "restricted"
        return
    end

    if charges then
        row.currentCharges = SafeNumber(charges.currentCharges)
        row.maxCharges = SafeNumber(charges.maxCharges)
        row.chargeDuration = SafeNumber(charges.cooldownDuration)
        row.nextChargeAt = RemainingToEpoch(
            charges.cooldownStartTime,
            charges.cooldownDuration,
            charges.chargeModRate)
    else
        row.currentCharges = nil
        row.maxCharges = nil
        row.chargeDuration = nil
        row.nextChargeAt = nil
    end

    local duration = cooldown and SafeNumber(cooldown.duration) or nil
    row.duration = duration
    if duration and duration > GCD_MAX_SECONDS then
        row.readyAt = RemainingToEpoch(cooldown.startTime, duration, cooldown.modRate)
    else
        row.readyAt = nil
    end
    row.lastCheckedAt = EpochNow()
    row.lastStatus = "ready"
    if row.currentCharges ~= nil and row.maxCharges ~= nil then
        row.lastStatus = row.currentCharges > 0 and "ready" or "cooldown"
    elseif row.readyAt then
        row.lastStatus = "cooldown"
    elseif not cooldown and cooldownErr == "unavailable" then
        row.lastStatus = "unavailable"
    elseif not cooldown and learned == nil then
        row.lastStatus = "pending"
    end
end

function Tracker.RefreshCurrentCharacter(onlyRecipeID)
    local character, currentUID = GetCharacter()
    if not character then
        return false, "no_cache"
    end
    local data = EnsureTrackerShape(character)
    local requestedID = SafeNumber(onlyRecipeID)
    local refreshed = 0
    for recipeID, tracked in pairs(data.tracked) do
        if tracked and (not requestedID or recipeID == requestedID) then
            data.recipes[recipeID] = type(data.recipes[recipeID]) == "table"
                and data.recipes[recipeID] or { recipeID = recipeID }
            data.recipes[recipeID].recipeID = recipeID
            RefreshRecipe(data.recipes[recipeID])
            refreshed = refreshed + 1
        end
    end
    character.cooldownTracker.lastRefreshAt = EpochNow()
    character.cooldownTracker.lastRefreshUID = currentUID
    Touch()
    return true, refreshed
end

function Tracker.GetTrackedRows(uid)
    local character, currentUID = GetCharacter(uid)
    local rows = {}
    if not character then
        return rows, false
    end
    local data = EnsureTrackerShape(character)
    for recipeID, tracked in pairs(data.tracked) do
        if tracked then
            local stored = data.recipes[recipeID] or { recipeID = recipeID, lastStatus = "pending" }
            stored.recipeID = recipeID
            rows[#rows + 1] = stored
        end
    end
    table.sort(rows, function(a, b)
        local aName = tostring(a.name or a.recipeID):lower()
        local bName = tostring(b.name or b.recipeID):lower()
        if a.profession ~= b.profession then
            return tostring(a.profession or "") < tostring(b.profession or "")
        end
        return aName < bName
    end)
    return rows, character.uid == currentUID
end

function Tracker.FormatDuration(seconds)
    seconds = math.max(0, math.floor(SafeNumber(seconds) or 0))
    if seconds <= 0 then return "Ready" end
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if days > 0 then return string.format("%dd %dh", days, hours) end
    if hours > 0 then return string.format("%dh %dm", hours, minutes) end
    if minutes > 0 then return string.format("%dm %02ds", minutes, secs) end
    return string.format("%ds", secs)
end

function Tracker.GetDisplayStatus(row, now)
    now = SafeNumber(now) or EpochNow()
    if type(row) ~= "table" then return "Unknown", "unknown" end
    if row.lastStatus == "unlearned" then return "Not learned", "unlearned" end
    if row.lastStatus == "restricted" then return "Restricted", "restricted" end
    if row.lastStatus == "unavailable" then return "Unavailable", "unavailable" end

    local currentCharges = SafeNumber(row.currentCharges)
    local maxCharges = SafeNumber(row.maxCharges)
    if currentCharges and maxCharges and maxCharges > 0 then
        local prefix = string.format("%d/%d available", currentCharges, maxCharges)
        local nextChargeAt = SafeNumber(row.nextChargeAt)
        if currentCharges < maxCharges and nextChargeAt and nextChargeAt > now then
            return prefix .. " - next " .. Tracker.FormatDuration(nextChargeAt - now),
                currentCharges > 0 and "ready" or "cooldown"
        end
        if currentCharges < maxCharges and nextChargeAt and nextChargeAt <= now then
            return currentCharges > 0 and (prefix .. " - charge ready") or "Charge ready",
                "ready"
        end
        if currentCharges == 0 then
            return "Refresh charges", "pending"
        end
        return prefix, currentCharges > 0 and "ready" or "cooldown"
    end

    local readyAt = SafeNumber(row.readyAt)
    if readyAt and readyAt > now then
        return Tracker.FormatDuration(readyAt - now), "cooldown"
    end
    if row.lastCheckedAt then
        return "Ready", "ready"
    end
    return "Refresh on crafter", "pending"
end

local function ScheduleRefresh(delay)
    refreshGeneration = refreshGeneration + 1
    local generation = refreshGeneration
    local function Run()
        if generation == refreshGeneration then
            Tracker.RefreshCurrentCharacter()
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay or 0.5, Run)
    else
        Run()
    end
end

local function IsTrackedByCurrentCrafter(recipeID)
    recipeID = SafeNumber(recipeID)
    if not recipeID then return false end
    local character = GetCharacter()
    local data = EnsureTrackerShape(character)
    return data and data.tracked[recipeID] and true or false
end

function Tracker.Init()
    EnsureCache()
    if eventFrame or type(CreateFrame) ~= "function" then
        ScheduleRefresh(2)
        return
    end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
    eventFrame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit, _, spellID = ...
            if unit ~= "player" or not IsTrackedByCurrentCrafter(spellID) then return end
            ScheduleRefresh(0.75)
        else
            ScheduleRefresh(0.5)
        end
    end)
    ScheduleRefresh(2)
end
