-- GoldAdvisorMidnight/CraftingStatsResolution.lua
-- Source-precedence policy for resolving crafting stats for a strategy.
-- Module: GAM.CraftingStatsResolution

local ADDON_NAME, GAM = ...
local Resolution = {}
GAM.CraftingStatsResolution = Resolution

function Resolution.Create(deps)
    assert(type(deps) == "table", "CraftingStatsResolution dependencies are required")
    local NormalizeGearMode = assert(deps.NormalizeGearMode, "NormalizeGearMode dependency is required")
    local GetProfileKeyForStrat = assert(deps.GetProfileKeyForStrat, "GetProfileKeyForStrat dependency is required")
    local GetProfileDefaults = assert(deps.GetProfileDefaults, "GetProfileDefaults dependency is required")
    local NormalizeRecipeID = assert(deps.NormalizeRecipeID, "NormalizeRecipeID dependency is required")
    local EnsureCache = assert(deps.EnsureCache, "EnsureCache dependency is required")
    local GetGearPreset = assert(deps.GetGearPreset, "GetGearPreset dependency is required")
    local FindCachedGearPresetCrafter = assert(deps.FindCachedGearPresetCrafter, "FindCachedGearPresetCrafter dependency is required")
    local FindCachedRecipeCrafter = assert(deps.FindCachedRecipeCrafter, "FindCachedRecipeCrafter dependency is required")
    local ApplySnapshotToDefaults = assert(deps.ApplySnapshotToDefaults, "ApplySnapshotToDefaults dependency is required")
    local ApplySpecializationNodeState = assert(deps.ApplySpecializationNodeState, "ApplySpecializationNodeState dependency is required")
    local AnnotateCrafter = assert(deps.AnnotateCrafter, "AnnotateCrafter dependency is required")
    local GetCachedRecipeSnapshot = assert(deps.GetCachedRecipeSnapshot, "GetCachedRecipeSnapshot dependency is required")
    local GetCachedProfileSnapshot = assert(deps.GetCachedProfileSnapshot, "GetCachedProfileSnapshot dependency is required")
    local GetSnapshotMatchKind = assert(deps.GetSnapshotMatchKind, "GetSnapshotMatchKind dependency is required")
    local GetOpenNativeRecipeSnapshot = assert(deps.GetOpenNativeRecipeSnapshot, "GetOpenNativeRecipeSnapshot dependency is required")
    local ApplyLiveNativeVisibleStats = assert(deps.ApplyLiveNativeVisibleStats, "ApplyLiveNativeVisibleStats dependency is required")
    local IsCraftSimSnapshot = assert(deps.IsCraftSimSnapshot, "IsCraftSimSnapshot dependency is required")
    local SourceForCachedSnapshot = assert(deps.SourceForCachedSnapshot, "SourceForCachedSnapshot dependency is required")
    local SaveSnapshot = assert(deps.SaveSnapshot, "SaveSnapshot dependency is required")

local function ResolveForStrat(strat, opts)
    opts = opts or ((GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {})
    local profileKey = GetProfileKeyForStrat(strat)
    local defaults = GetProfileDefaults(profileKey, opts)
    local recipeID = NormalizeRecipeID(strat and strat.recipeID)
    local character, currentUID, cache = EnsureCache()
    local manualDefaults = defaults
    local hasManualProfile = false

    local requestedGearMode = NormalizeGearMode(opts and opts._gamGearModeOverride)
    if requestedGearMode ~= "auto" and recipeID then
        local presetCharacter, presetUID = character, currentUID
        local preset = GetGearPreset(character, recipeID, profileKey, requestedGearMode)
        local crossCharacter = false
        if not preset then
            presetCharacter, presetUID, preset = FindCachedGearPresetCrafter(
                cache, currentUID, recipeID, profileKey, requestedGearMode)
            crossCharacter = preset ~= nil
        end
        if preset then
            local presetDefaults = defaults
            local presetManual = profileKey
                and presetCharacter.manualProfiles
                and presetCharacter.manualProfiles[profileKey]
            if type(presetManual) == "table" then
                presetDefaults = ApplySnapshotToDefaults(defaults, presetManual, "manual")
            end
            local result = ApplySnapshotToDefaults(
                presetDefaults, preset, "gear-preset-" .. requestedGearMode, nil, false)
            result = ApplySpecializationNodeState(
                result, profileKey, presetCharacter, recipeID)
            result.gearModeRequested = requestedGearMode
            result.gearModeResolved = requestedGearMode
            return AnnotateCrafter(
                result, presetCharacter, presetUID, crossCharacter)
        end
    end

    if type(character) == "table" then
        local manual = profileKey and character.manualProfiles and character.manualProfiles[profileKey]
        if type(manual) == "table" then
            hasManualProfile = true
            manualDefaults = ApplySnapshotToDefaults(defaults, manual, "manual")
        end
    end

    local recipeSnapshot = GetCachedRecipeSnapshot(character, recipeID, profileKey)
    local profileSnapshot = not recipeID
        and GetCachedProfileSnapshot(character, profileKey)
        or nil
    local openSnapshot = GetOpenNativeRecipeSnapshot()
    local openMatchKind = GetSnapshotMatchKind(openSnapshot, strat, profileKey)

    -- CraftSim remains an optional exact-recipe/capability source. Hidden node
    -- modifiers are deliberately excluded and replaced with GAM's own captured
    -- specialization state (or workbook/manual defaults until capture).
    if IsCraftSimSnapshot(recipeSnapshot) then
        local result = ApplySnapshotToDefaults(manualDefaults, recipeSnapshot,
            SourceForCachedSnapshot(recipeSnapshot, "gam-cache-recipe"),
            nil, false)
        result = ApplySpecializationNodeState(result, profileKey, character, recipeID)
        if openMatchKind == "recipe" then
            result = ApplyLiveNativeVisibleStats(
                result, openSnapshot, profileKey, character, recipeID)
        end
        return AnnotateCrafter(result, character, currentUID, false)
    end

    if openMatchKind == "recipe" then
        SaveSnapshot(openSnapshot)
        return AnnotateCrafter(ApplySpecializationNodeState(
            ApplySnapshotToDefaults(manualDefaults, openSnapshot, "native-open"),
            profileKey,
            character,
            recipeID), character, currentUID, false)
    end

    if recipeSnapshot and not IsCraftSimSnapshot(recipeSnapshot) then
        return AnnotateCrafter(ApplySpecializationNodeState(
            ApplySnapshotToDefaults(manualDefaults, recipeSnapshot,
                SourceForCachedSnapshot(recipeSnapshot, "gam-cache-recipe")),
            profileKey,
            character,
            recipeID), character, currentUID, false)
    end

    -- Exact recipe data is safe to reuse across characters because the
    -- visible stats and learned-node state are resolved from the same cached
    -- crafter. Profile-only data is deliberately not shared across toons.
    if recipeID then
        local cachedCharacter, cachedUID, cachedSnapshot = FindCachedRecipeCrafter(
            cache, currentUID, recipeID, profileKey)
        if cachedSnapshot then
            local cachedDefaults = defaults
            local cachedManual = profileKey
                and cachedCharacter.manualProfiles
                and cachedCharacter.manualProfiles[profileKey]
            if type(cachedManual) == "table" then
                cachedDefaults = ApplySnapshotToDefaults(defaults, cachedManual, "manual")
            end
            local cachedResult = ApplySnapshotToDefaults(
                cachedDefaults,
                cachedSnapshot,
                SourceForCachedSnapshot(cachedSnapshot, "gam-cache-recipe"),
                "cached-crafter",
                false)
            cachedResult = ApplySpecializationNodeState(
                cachedResult, profileKey, cachedCharacter, recipeID)
            cachedResult.fallbackReason = "cached-crafter"
            return AnnotateCrafter(cachedResult, cachedCharacter, cachedUID, true)
        end
    end

    if openMatchKind == "profile" then
        SaveSnapshot(openSnapshot)
        return AnnotateCrafter(ApplySpecializationNodeState(
            ApplySnapshotToDefaults(manualDefaults, openSnapshot, "native-open-profile",
                "profile-visible-stats-only", false),
            profileKey,
            character,
            recipeID), character, currentUID, false)
    end

    if profileSnapshot and not IsCraftSimSnapshot(profileSnapshot) then
        return AnnotateCrafter(ApplySpecializationNodeState(
            ApplySnapshotToDefaults(manualDefaults, profileSnapshot,
                SourceForCachedSnapshot(profileSnapshot, "gam-cache-profile"),
                "profile-visible-stats-only", false),
            profileKey,
            character,
            recipeID), character, currentUID, false)
    end

    local withNodes = ApplySpecializationNodeState(manualDefaults, profileKey, character, recipeID)
    if withNodes ~= manualDefaults or (withNodes and withNodes.nodeHash) then
        return AnnotateCrafter(withNodes, character, currentUID, false)
    end

    if IsCraftSimSnapshot(profileSnapshot) then
        return AnnotateCrafter(ApplySpecializationNodeState(
            ApplySnapshotToDefaults(manualDefaults, profileSnapshot,
                SourceForCachedSnapshot(profileSnapshot, "gam-cache-profile"),
                "profile-visible-stats-only", false),
            profileKey,
            character,
            recipeID), character, currentUID, false)
    end

    if hasManualProfile then
        return AnnotateCrafter(manualDefaults, character, currentUID, false)
    end

    return defaults
end

    return {
        ResolveForStrat = ResolveForStrat,
    }
end
