-- GoldAdvisorMidnight/CraftingStatsGear.lua
-- Per-strategy gear-mode preferences and cached gear-preset lookup.
-- Module: GAM.CraftingStatsGear

local ADDON_NAME, GAM = ...
local Gear = {}
GAM.CraftingStatsGear = Gear

local Cache = assert(GAM.CraftingStatsCache, "CraftingStatsCache must load before CraftingStatsGear")
local GEAR_MODES = {
    auto = true,
    multicraft = true,
    resourcefulness = true,
}

function Gear.NormalizeMode(mode)
    mode = tostring(mode or "auto"):lower()
    return GEAR_MODES[mode] and mode or "auto"
end

function Gear.GetPreset(character, recipeID, profileKey, mode)
    mode = Gear.NormalizeMode(mode)
    if mode == "auto" or not recipeID or type(character) ~= "table"
            or type(character.gearPresets) ~= "table" then
        return nil
    end
    local recipePresets = character.gearPresets[tostring(recipeID)]
    local snapshot = type(recipePresets) == "table" and recipePresets[mode] or nil
    if type(snapshot) == "table"
            and (not snapshot.profileKey or not profileKey or snapshot.profileKey == profileKey) then
        return snapshot
    end
    return nil
end

function Gear.FindPresetCrafter(cache, currentUID, recipeID, profileKey, mode)
    if not recipeID or type(cache) ~= "table" or type(cache.characters) ~= "table" then
        return nil
    end
    local bestCharacter, bestUID, bestSnapshot, bestCapturedAt
    for uid, character in pairs(cache.characters) do
        if uid ~= currentUID and type(character) == "table" then
            local snapshot = Gear.GetPreset(character, recipeID, profileKey, mode)
            local capturedAt = snapshot and (tonumber(snapshot.capturedAt) or 0) or nil
            if snapshot and (not bestSnapshot
                    or capturedAt > bestCapturedAt
                    or (capturedAt == bestCapturedAt and tostring(uid) < tostring(bestUID))) then
                bestCharacter, bestUID, bestSnapshot, bestCapturedAt =
                    character, uid, snapshot, capturedAt
            end
        end
    end
    return bestCharacter, bestUID, bestSnapshot, bestCapturedAt
end

function Gear.GetModeForStrategy(strat, patchTag)
    local stratID = type(strat) == "table" and strat.id or nil
    local defaultPatch = GAM.C and GAM.C.DEFAULT_PATCH
    local patch = stratID and GAM.GetPatchDB and GAM:GetPatchDB(patchTag or defaultPatch) or nil
    return Gear.NormalizeMode(patch and patch.gearModes and patch.gearModes[stratID])
end

function Gear.SetModeForStrategy(strat, mode, patchTag)
    local stratID = type(strat) == "table" and strat.id or nil
    if not stratID then return false, "missing-strategy" end
    local defaultPatch = GAM.C and GAM.C.DEFAULT_PATCH
    local patch = GAM.GetPatchDB and GAM:GetPatchDB(patchTag or defaultPatch) or nil
    if not patch then return false, "no-db" end
    patch.gearModes = patch.gearModes or {}
    mode = Gear.NormalizeMode(mode)
    if patch.gearModes[stratID] ~= mode then
        patch.gearModes[stratID] = mode
        local character, _, cache = Cache.Ensure()
        Cache.TouchRevision(character, cache)
    end
    return true, mode
end
