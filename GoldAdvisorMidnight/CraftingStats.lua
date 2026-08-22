-- GoldAdvisorMidnight/CraftingStats.lua
-- GAM-owned crafting stat resolver. CraftSim may import snapshots here, but
-- pricing code should not depend on CraftSim directly.
-- Module: GAM.CraftingStats

local ADDON_NAME, GAM = ...
local Stats = {}
GAM.CraftingStats = Stats
GAM.CraftingStatsV2 = Stats -- Compatibility alias for pre-refocus callers.
local NodeDisplay = GAM.ProfessionNodeDisplay
local Cache = assert(GAM.CraftingStatsCache, "CraftingStatsCache must load before CraftingStats")
local Specialization = assert(
    GAM.CraftingStatsSpecialization,
    "CraftingStatsSpecialization must load before CraftingStats")

local CACHE_VERSION = Cache.VERSION
local SEASON_KEY = "midnight"
local RECIPE_SNAPSHOT_STALE_SECONDS = 24 * 60 * 60
local pendingRecipeRefreshes = {}
local PROFESSION_DEFS = Specialization.GetProfessionDefs()

local function GetFormulaProfiles()
    return (GAM_WORKBOOK_GENERATED and GAM_WORKBOOK_GENERATED.formulaProfiles) or {}
end

local function ClampNonNegative(value)
    local n = tonumber(value) or 0
    if n < 0 then return 0 end
    return n
end

local function ClampPercent(value)
    local n = tonumber(value) or 0
    if n < 0 then return 0 end
    if n > 100 then return 100 end
    return n
end

local CopyNumericTable = Cache.CopyNumericTable
local CopySerializableTable = Cache.CopySerializableTable
local CopyShallowTable = Cache.CopyShallowTable
local GetCurrentTimestamp = Cache.GetCurrentTimestamp
local EnsureCache = Cache.Ensure
local TouchRevision = Cache.TouchRevision
local SnapshotMateriallyEqual = Cache.SnapshotMateriallyEqual

function Stats.GetRevision()
    return Cache.GetRevision()
end

local ResolveProfessionDef = Specialization.ResolveProfessionDef
local ResolveProfessionDefBySkillLine = Specialization.ResolveProfessionDefBySkillLine
local GetSpecializationCatalog = Specialization.GetCatalog
local IsSpecializationProfile = Specialization.IsProfile
local GetProfessionForProfile = Specialization.GetProfessionForProfile
local ClampRank = Specialization.ClampRank
local GetCatalogNode = Specialization.GetCatalogNode
local EnsureProfessionNodeState = Specialization.EnsureNodeState
local BuildNodeHash = Specialization.BuildNodeHash
local ApplySpecializationNodeState = Specialization.ApplyNodeState

local function NormalizeRecipeID(recipeID)
    local n = tonumber(recipeID)
    if n and n > 0 then
        return math.floor(n)
    end
    return nil
end

local function GetProfileKeyForStrat(strat)
    if type(strat) ~= "table" then
        return nil
    end
    return strat.statProfileKey or strat.formulaProfile
end

local function GetProfileDefaults(profileKey, opts)
    local profile = profileKey and GetFormulaProfiles()[profileKey] or nil
    local supportsMulticraft = profile and profile.multiKey ~= nil or false
    local supportsResourcefulness = profile and profile.resKey ~= nil or false

    local multiValue = supportsMulticraft and tonumber(opts and opts[profile.multiKey]) or nil
    local resValue = supportsResourcefulness and tonumber(opts and opts[profile.resKey]) or nil
    local multiExtraValue = supportsMulticraft and tonumber(opts and opts[profile.mcNodeKey]) or nil
    local resExtraValue = supportsResourcefulness and tonumber(opts and opts[profile.rsNodeKey]) or nil

    local source = "workbook-default"
    if (supportsMulticraft and multiValue ~= nil and math.abs(multiValue - (profile.defaultMulti or 0)) > 0.0001)
            or (supportsResourcefulness and resValue ~= nil and math.abs(resValue - (profile.defaultRes or 0)) > 0.0001)
            or (supportsMulticraft and multiExtraValue ~= nil and math.abs(multiExtraValue - (profile.defaultMcNode or 0)) > 0.0001)
            or (supportsResourcefulness and resExtraValue ~= nil and math.abs(resExtraValue - (profile.defaultRsNode or 0)) > 0.0001) then
        source = "manual"
    end

    return {
        profileKey = profileKey,
        statSource = source,
        -- Do not use `profile and nil or "missing-profile"` here. Lua's
        -- and/or idiom cannot represent a nil true branch, so that expression
        -- labels every valid workbook profile as missing.
        fallbackReason = profile == nil and "missing-profile" or nil,
        supportsMulticraft = supportsMulticraft,
        supportsResourcefulness = supportsResourcefulness,
        multiPercent = supportsMulticraft and ClampPercent(multiValue or profile.defaultMulti or 0) or 0,
        resPercent = supportsResourcefulness and ClampPercent(resValue or profile.defaultRes or 0) or 0,
        multiExtra = supportsMulticraft and ClampNonNegative((multiExtraValue or profile.defaultMcNode or 0) / 100) or 0,
        resExtra = supportsResourcefulness and ClampNonNegative((resExtraValue or profile.defaultRsNode or 0) / 100) or 0,
    }
end

local function CopySnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return nil
    end

    local out = {}
    local fields = {
        "profileKey",
        "recipeID",
        "recipeName",
        "profession",
        "source",
        "capturedAt",
        "cachedSource",
        "statQuality",
        "multiPercent",
        "resPercent",
        "multiExtra",
        "resExtra",
        "supportsMulticraft",
        "supportsResourcefulness",
        "mcConstant",
        "resourcefulnessSaveBase",
        "toolFingerprint",
        "equipmentNote",
        "skillLineID",
        "parentSkillLineID",
        "nodeHash",
        "nodeCount",
        "gearPreset",
    }
    for _, field in ipairs(fields) do
        if snapshot[field] ~= nil then
            out[field] = snapshot[field]
        end
    end
    out.recipeID = NormalizeRecipeID(out.recipeID)
    out.multicraftConstants = CopyNumericTable(snapshot.multicraftConstants)
    local nestedFields = {
        "totalStats",
        "nodeStats",
        "baseStats",
        "gearStats",
        "buffStats",
        "modifierStats",
        "nodeRanks",
    }
    for _, field in ipairs(nestedFields) do
        out[field] = CopySerializableTable(snapshot[field])
    end
    return out
end

local function IsCraftSimSnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return false
    end
    local source = tostring(snapshot.source or snapshot.statSource or "")
    local cachedSource = tostring(snapshot.cachedSource or "")
    return source == "craftsim-imported"
        or cachedSource == "craftsim"
        or cachedSource == "craftsim-open"
        or cachedSource == "craftsim-cache"
        or cachedSource == "craftsim-imported"
end

local function SourceForCachedSnapshot(snapshot, cacheSource)
    if type(snapshot) ~= "table" then
        return cacheSource or "gam-cache-profile"
    end
    if IsCraftSimSnapshot(snapshot) then
        return "craftsim-imported"
    end
    return cacheSource or "gam-cache-profile"
end

local function ShouldPreserveExistingSnapshot(existing, incoming)
    if type(existing) ~= "table" or type(incoming) ~= "table" then
        return false
    end

    -- Source precedence must hold for writes as well as reads. Refreshing the
    -- strategy list can observe the same open Blizzard recipe through a
    -- profile-only strategy after CraftSim captured it exactly; that native
    -- observation must not downgrade the recipe-scoped CraftSim snapshot.
    if IsCraftSimSnapshot(existing) and not IsCraftSimSnapshot(incoming) then
        return true
    end

    -- Explicit manual snapshots remain authoritative. Incoming exact CraftSim
    -- snapshots may otherwise replace native data for recipe identity,
    -- capability flags, visible stats, and shared formula constants. Hidden
    -- node state is excluded later by the resolver.
    local existingSource = tostring(existing.source or existing.statSource or "")
    return existingSource == "manual" and IsCraftSimSnapshot(incoming)
end

local function ApplySnapshotToDefaults(defaults, snapshot, statSource, fallbackReason, includeHiddenNodeState)
    if includeHiddenNodeState == nil then
        includeHiddenNodeState = true
    end

    local result = {}
    for key, value in pairs(defaults or {}) do
        result[key] = value
    end
    snapshot = snapshot or {}

    result.profileKey = snapshot.profileKey or result.profileKey
    if includeHiddenNodeState then
        result.recipeID = NormalizeRecipeID(snapshot.recipeID) or result.recipeID
        result.recipeName = snapshot.recipeName or result.recipeName
    end
    result.profession = snapshot.profession or result.profession
    result.statSource = statSource or snapshot.source or result.statSource
    result.fallbackReason = fallbackReason
    result.capturedAt = snapshot.capturedAt
    result.cachedSource = snapshot.cachedSource
    result.statQuality = snapshot.statQuality
    if includeHiddenNodeState then
        result.nodeHash = snapshot.nodeHash
        result.nodeCount = snapshot.nodeCount
    end

    if snapshot.supportsMulticraft ~= nil then
        result.supportsMulticraft = snapshot.supportsMulticraft and true or false
        if not result.supportsMulticraft then
            result.multiPercent = 0
            result.multiExtra = 0
        end
    end
    if snapshot.supportsResourcefulness ~= nil then
        result.supportsResourcefulness = snapshot.supportsResourcefulness and true or false
        if not result.supportsResourcefulness then
            result.resPercent = 0
            result.resExtra = 0
        end
    end

    if snapshot.multiPercent ~= nil and result.supportsMulticraft then
        result.multiPercent = ClampPercent(snapshot.multiPercent)
    end
    if snapshot.resPercent ~= nil and result.supportsResourcefulness then
        result.resPercent = ClampPercent(snapshot.resPercent)
    end
    if includeHiddenNodeState and snapshot.multiExtra ~= nil and result.supportsMulticraft then
        result.multiExtra = ClampNonNegative(snapshot.multiExtra)
    end
    if includeHiddenNodeState and snapshot.resExtra ~= nil and result.supportsResourcefulness then
        result.resExtra = ClampNonNegative(snapshot.resExtra)
    end

    if snapshot.resourcefulnessSaveBase ~= nil then
        result.resourcefulnessSaveBase = ClampNonNegative(snapshot.resourcefulnessSaveBase)
    end
    if snapshot.mcConstant ~= nil then
        result.mcConstant = ClampNonNegative(snapshot.mcConstant)
    end
    result.multicraftConstants = CopyNumericTable(snapshot.multicraftConstants)
    local nestedFields = {
        "totalStats",
        "baseStats",
        "gearStats",
        "buffStats",
        "modifierStats",
    }
    for _, field in ipairs(nestedFields) do
        result[field] = CopySerializableTable(snapshot[field])
    end
    if includeHiddenNodeState then
        result.nodeStats = CopySerializableTable(snapshot.nodeStats)
        result.nodeRanks = CopySerializableTable(snapshot.nodeRanks)
    end
    return result
end

local function GetSnapshotMatchKind(snapshot, strat, profileKey)
    if type(snapshot) ~= "table" then
        return nil
    end

    local recipeID = NormalizeRecipeID(strat and strat.recipeID)
    local snapshotRecipeID = NormalizeRecipeID(snapshot.recipeID)
    if recipeID and snapshotRecipeID and recipeID == snapshotRecipeID then
        return "recipe"
    end

    -- Visible profession stats belong to the recipe that produced the
    -- snapshot. Two recipes in the same broad profile can use different node
    -- paths and capabilities, so a same-profile match is not recipe parity.
    if recipeID then
        return nil
    end

    if profileKey ~= nil and snapshot.profileKey == profileKey then
        return "profile"
    end
    return nil
end

local function GetCachedRecipeSnapshot(character, recipeID, profileKey)
    if not recipeID or type(character) ~= "table" or type(character.recipes) ~= "table" then
        return nil
    end

    local snapshot = character.recipes[tostring(recipeID)]
    if type(snapshot) == "table"
            and (not snapshot.profileKey or not profileKey or snapshot.profileKey == profileKey) then
        return snapshot
    end
    return nil
end

local function GetCachedProfileSnapshot(character, profileKey)
    if not profileKey or type(character) ~= "table" or type(character.profiles) ~= "table" then
        return nil
    end

    local snapshot = character.profiles[profileKey]
    return type(snapshot) == "table" and snapshot or nil
end

local Gear = assert(GAM.CraftingStatsGear, "CraftingStatsGear must load before CraftingStats")
local NormalizeGearMode = Gear.NormalizeMode
local GetGearPreset = Gear.GetPreset
local FindCachedGearPresetCrafter = Gear.FindPresetCrafter

local function GetRecipeValidatedAt(character, recipeID, snapshot)
    local recipeKey = recipeID and tostring(recipeID) or nil
    local validatedAt = recipeKey
        and type(character) == "table"
        and type(character.recipeValidatedAt) == "table"
        and tonumber(character.recipeValidatedAt[recipeKey])
        or nil
    return validatedAt or tonumber(snapshot and snapshot.capturedAt) or 0
end

local function FindCachedRecipeCrafter(cache, currentUID, recipeID, profileKey)
    if not recipeID or type(cache) ~= "table" or type(cache.characters) ~= "table" then
        return nil
    end

    local bestCharacter, bestUID, bestSnapshot, bestValidatedAt
    for uid, character in pairs(cache.characters) do
        if uid ~= currentUID and type(character) == "table" then
            local snapshot = GetCachedRecipeSnapshot(character, recipeID, profileKey)
            if snapshot then
                local validatedAt = GetRecipeValidatedAt(character, recipeID, snapshot)
                if not bestSnapshot
                        or validatedAt > bestValidatedAt
                        or (validatedAt == bestValidatedAt and tostring(uid) < tostring(bestUID)) then
                    bestCharacter = character
                    bestUID = uid
                    bestSnapshot = snapshot
                    bestValidatedAt = validatedAt
                end
            end
        end
    end
    return bestCharacter, bestUID, bestSnapshot, bestValidatedAt
end

local function AnnotateCrafter(result, character, uid, crossCharacter)
    if type(result) ~= "table" then return result end
    result.crafterUID = uid
    result.crafterName = type(character) == "table" and character.name or nil
    result.crafterRealm = type(character) == "table" and character.realm or nil
    result.crossCharacter = crossCharacter and true or nil
    return result
end

local function InferProfileKey(recipeName, profession, supportsMulticraft)
    local name = tostring(recipeName or ""):lower()
    local prof = tostring(profession or ""):lower()

    if prof:find("inscription", 1, true) or prof == "insc" then
        if name:find("codified", 1, true) then
            return "insc_codified"
        end
        if supportsMulticraft then
            return "insc_ink"
        end
        return "insc_milling"
    end
    if prof:find("jewelcraft", 1, true) or prof == "jc" then
        if name:find("prospecting", 1, true) then
            return "jc_prospect"
        end
        if name:find("crushing", 1, true) then
            return "jc_crush"
        end
        if name:find("refine", 1, true) then
            return "jc_refine"
        end
        return "jc_craft"
    end
    if prof:find("enchant", 1, true) or prof == "ench" then
        if name:find("shatter", 1, true) then
            return "ench_shatter"
        end
        return "ench_craft"
    end
    if prof:find("engineer", 1, true) or prof == "eng" then
        if name:find("recycling", 1, true) then
            return "engineering_recycling"
        end
        return "engineering_craft"
    end
    if prof:find("alchemy", 1, true) or prof == "alch" then return "alchemy" end
    if prof:find("tailor", 1, true) or prof == "tail" then return "tailoring" end
    if prof:find("blacksmith", 1, true) or prof == "bs" then return "blacksmithing" end
    if prof:find("leather", 1, true) or prof == "lw" then return "leatherworking" end
    if prof:find("cooking", 1, true) or prof == "cook" then return "cooking" end
    return nil
end

local testOpenSnapshot = nil
local testOpenProfessionNodes = nil
local testPlayerProfessionSet = nil

local NativeCapture = assert(
    GAM.CraftingStatsCapture,
    "CraftingStatsCapture must load before CraftingStats")
    .Create({
        InferProfileKey = InferProfileKey,
        GetTestOpenSnapshot = function() return testOpenSnapshot end,
        GetTestOpenProfessionNodes = function() return testOpenProfessionNodes end,
    })
local GetOpenNativeRecipeSnapshot = NativeCapture.GetOpenRecipeSnapshot
local GetOpenProfessionContext = NativeCapture.GetOpenProfessionContext
local GetOpenProfessionDef = NativeCapture.GetOpenProfessionDef
local OpenProfessionMatches = NativeCapture.OpenProfessionMatches
local GetOpenNativeProfessionNodeRanks = NativeCapture.GetOpenProfessionNodeRanks

function Stats.SaveSnapshot(snapshot)
    local normalized = CopySnapshot(snapshot)
    if not normalized or not normalized.profileKey then
        return false, "missing-profile"
    end

    local character, _, cache = EnsureCache()
    if not character then
        return false, "no-db"
    end

    normalized.capturedAt = normalized.capturedAt or GetCurrentTimestamp()
    normalized.source = normalized.source or "gam-cache-profile"
    local preservedExisting = false
    local changed = false

    if normalized.recipeID then
        local recipeKey = tostring(normalized.recipeID)
        character.recipeValidatedAt[recipeKey] = GetCurrentTimestamp()
        if ShouldPreserveExistingSnapshot(character.recipes[recipeKey], normalized) then
            preservedExisting = true
        elseif not SnapshotMateriallyEqual(character.recipes[recipeKey], normalized) then
            character.recipes[recipeKey] = CopySnapshot(normalized)
            changed = true
        end
    end

    if ShouldPreserveExistingSnapshot(character.profiles[normalized.profileKey], normalized) then
        preservedExisting = true
    elseif not SnapshotMateriallyEqual(character.profiles[normalized.profileKey], normalized) then
        character.profiles[normalized.profileKey] = CopySnapshot(normalized)
        changed = true
    end

    if changed then
        TouchRevision(character, cache)
        return true, nil
    end
    if preservedExisting then
        return true, "preserved-existing"
    end
    return true, "unchanged"
end

function Stats.SetManualProfile(profileKey, values)
    if not profileKey then
        return false, "missing-profile"
    end
    local character, _, cache = EnsureCache()
    if not character then
        return false, "no-db"
    end

    local manual = CopySnapshot(values or {}) or {}
    manual.profileKey = profileKey
    manual.source = "manual"
    manual.capturedAt = GetCurrentTimestamp()
    if not SnapshotMateriallyEqual(character.manualProfiles[profileKey], manual) then
        character.manualProfiles[profileKey] = manual
        TouchRevision(character, cache)
    end
    return true, nil
end

function Stats.GetProfile(profileKey)
    local defaults = GetProfileDefaults(profileKey, (GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {})
    local character = EnsureCache()
    if type(character) == "table" then
        local manual = character.manualProfiles and character.manualProfiles[profileKey]
        local manualDefaults = type(manual) == "table"
            and ApplySnapshotToDefaults(defaults, manual, "manual")
            or defaults
        local cached = character.profiles and character.profiles[profileKey]
        if type(cached) == "table" then
            local source = SourceForCachedSnapshot(cached, "gam-cache-profile")
            return ApplySpecializationNodeState(
                ApplySnapshotToDefaults(manualDefaults, cached, source,
                    "profile-visible-stats-only", false),
                profileKey,
                character), source
        end
        if type(manual) == "table" then
            return ApplySpecializationNodeState(manualDefaults, profileKey, character), "manual"
        end
    end
    return ApplySpecializationNodeState(defaults, profileKey, character), "workbook-default"
end

local function ApplyLiveNativeVisibleStats(result, openSnapshot, profileKey, character, recipeID)
    if type(result) ~= "table" or type(openSnapshot) ~= "table" then
        return result
    end

    local merged = false
    if openSnapshot.multiPercent ~= nil then
        result.supportsMulticraft = true
        result.multiPercent = ClampPercent(openSnapshot.multiPercent)
        merged = true
    end
    if openSnapshot.resPercent ~= nil then
        result.supportsResourcefulness = true
        result.resPercent = ClampPercent(openSnapshot.resPercent)
        merged = true
    end

    if not merged then
        return result
    end

    -- Hidden specialization bonuses are always GAM-owned. CraftSim can still
    -- contribute recipe capability/visible-stat data, but never node extras.
    ApplySpecializationNodeState(result, profileKey, character, recipeID)

    result.statSource = "craftsim+native-open"
    result.visibleStatSource = "native-open"
    return result
end

function Stats.GetGearModeForStrat(strat, patchTag)
    return Gear.GetModeForStrategy(strat, patchTag)
end

function Stats.SetGearModeForStrat(strat, mode, patchTag)
    return Gear.SetModeForStrategy(strat, mode, patchTag)
end

function Stats.GetAvailableGearPresetModes(strat)
    local recipeID = NormalizeRecipeID(strat and strat.recipeID)
    local profileKey = GetProfileKeyForStrat(strat)
    local character, currentUID, cache = EnsureCache()
    local available = { multicraft = false, resourcefulness = false }
    local crafters = {}
    for _, mode in ipairs({ "multicraft", "resourcefulness" }) do
        local snapshot = GetGearPreset(character, recipeID, profileKey, mode)
        local owner, uid = character, currentUID
        if not snapshot then
            owner, uid, snapshot = FindCachedGearPresetCrafter(
                cache, currentUID, recipeID, profileKey, mode)
        end
        available[mode] = snapshot ~= nil
        if snapshot then
            crafters[mode] = {
                uid = uid,
                name = owner and owner.name,
                realm = owner and owner.realm,
                isCurrent = uid == currentUID,
                capturedAt = snapshot.capturedAt,
            }
        end
    end
    return available, crafters
end

function Stats.GetGearPresetStatus(strat, patchTag)
    local available, crafters = Stats.GetAvailableGearPresetModes(strat)
    local selected = Stats.GetGearModeForStrat(strat, patchTag)
    local openSnapshot = GetOpenNativeRecipeSnapshot()
    local canCapture = GetSnapshotMatchKind(
        openSnapshot, strat, GetProfileKeyForStrat(strat)) == "recipe"
    return {
        selected = selected,
        available = available,
        crafters = crafters,
        canCapture = canCapture,
        selectedMissing = selected ~= "auto" and not available[selected] or false,
    }
end

function Stats.CaptureOpenRecipeAsGearPreset(mode)
    mode = NormalizeGearMode(mode)
    if mode == "auto" then return nil, "invalid-gear-mode" end
    local snapshot = GetOpenNativeRecipeSnapshot()
    if not snapshot or not snapshot.recipeID then
        return nil, "no-open-native-recipe"
    end
    local ok, err = Stats.SaveSnapshot(snapshot)
    if not ok then return nil, err end

    local character, _, cache = EnsureCache()
    if not character then return nil, "no-db" end
    local recipeKey = tostring(snapshot.recipeID)
    character.gearPresets[recipeKey] = character.gearPresets[recipeKey] or {}
    local preset = CopySnapshot(snapshot)
    preset.gearPreset = mode
    preset.source = "gear-preset-" .. mode
    preset.capturedAt = GetCurrentTimestamp()
    character.gearPresets[recipeKey][mode] = preset
    TouchRevision(character, cache)
    return preset, nil
end

local Resolution = assert(
    GAM.CraftingStatsResolution,
    "CraftingStatsResolution must load before CraftingStats")
    .Create({
        NormalizeGearMode = NormalizeGearMode,
        GetProfileKeyForStrat = GetProfileKeyForStrat,
        GetProfileDefaults = GetProfileDefaults,
        NormalizeRecipeID = NormalizeRecipeID,
        EnsureCache = EnsureCache,
        GetGearPreset = GetGearPreset,
        FindCachedGearPresetCrafter = FindCachedGearPresetCrafter,
        FindCachedRecipeCrafter = FindCachedRecipeCrafter,
        ApplySnapshotToDefaults = ApplySnapshotToDefaults,
        ApplySpecializationNodeState = ApplySpecializationNodeState,
        AnnotateCrafter = AnnotateCrafter,
        GetCachedRecipeSnapshot = GetCachedRecipeSnapshot,
        GetCachedProfileSnapshot = GetCachedProfileSnapshot,
        GetSnapshotMatchKind = GetSnapshotMatchKind,
        GetOpenNativeRecipeSnapshot = GetOpenNativeRecipeSnapshot,
        ApplyLiveNativeVisibleStats = ApplyLiveNativeVisibleStats,
        IsCraftSimSnapshot = IsCraftSimSnapshot,
        SourceForCachedSnapshot = SourceForCachedSnapshot,
        SaveSnapshot = Stats.SaveSnapshot,
    })

function Stats.ResolveForStrat(strat, opts)
    return Resolution.ResolveForStrat(strat, opts)
end

function Stats.CaptureOpenRecipe(expectedRecipeID)
    local snapshot = GetOpenNativeRecipeSnapshot()
    if not snapshot then
        return nil, "no-open-native-recipe"
    end
    local expectedID = NormalizeRecipeID(expectedRecipeID)
    local visibleID = NormalizeRecipeID(snapshot.recipeID)
    if expectedID and visibleID ~= expectedID then
        return nil, "open-recipe-mismatch:" .. tostring(visibleID or "unknown")
    end
    local ok, err = Stats.SaveSnapshot(snapshot)
    if not ok then
        return nil, err
    end
    return snapshot, nil
end

local function PlayerHasProfession(profession)
    local def = ResolveProfessionDef(profession)
    if not def then return false end
    if type(testPlayerProfessionSet) == "table" then
        return testPlayerProfessionSet[def.name] == true
    end
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
        return nil
    end

    local indices = { GetProfessions() }
    for i = 1, 6 do
        local index = indices[i]
        if index then
            local professionName, _, _, _, _, _, skillLineID, _, _, _, skillLineName =
                GetProfessionInfo(index)
            if tonumber(skillLineID) == tonumber(def.skillLineID)
                    or ResolveProfessionDef(professionName) == def
                    or ResolveProfessionDef(skillLineName) == def then
                return true
            end
        end
    end
    return false
end

function Stats.PlayerHasProfession(profession)
    return PlayerHasProfession(profession)
end

function Stats.GetCachedCraftersForStrat(strat)
    local recipeID = NormalizeRecipeID(strat and strat.recipeID)
    local profileKey = GetProfileKeyForStrat(strat)
    local _, currentUID, cache = EnsureCache()
    local rows = {}
    if not recipeID or type(cache) ~= "table" then return rows end

    for uid, character in pairs(cache.characters or {}) do
        local snapshot = GetCachedRecipeSnapshot(character, recipeID, profileKey)
        if snapshot then
            rows[#rows + 1] = {
                uid = uid,
                name = character.name,
                realm = character.realm,
                isCurrent = uid == currentUID,
                capturedAt = GetRecipeValidatedAt(character, recipeID, snapshot),
                source = snapshot.source,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.isCurrent ~= b.isCurrent then return a.isCurrent end
        if a.capturedAt ~= b.capturedAt then return a.capturedAt > b.capturedAt end
        return tostring(a.uid) < tostring(b.uid)
    end)
    return rows
end

function Stats.GetRecipeCacheStatus(strat, staleSeconds)
    local recipeID = NormalizeRecipeID(strat and strat.recipeID)
    local profileKey = GetProfileKeyForStrat(strat)
    local character, currentUID, cache = EnsureCache()
    local currentSnapshot = GetCachedRecipeSnapshot(character, recipeID, profileKey)
    local currentValidatedAt = GetRecipeValidatedAt(character, recipeID, currentSnapshot)
    local now = GetCurrentTimestamp()
    local maxAge = tonumber(staleSeconds) or RECIPE_SNAPSHOT_STALE_SECONDS
    local stale = currentSnapshot ~= nil
        and currentValidatedAt > 0
        and now > currentValidatedAt
        and (now - currentValidatedAt) > maxAge
        or false
    local cachedCharacter, cachedUID, cachedSnapshot, cachedValidatedAt
    if not currentSnapshot then
        cachedCharacter, cachedUID, cachedSnapshot, cachedValidatedAt =
            FindCachedRecipeCrafter(cache, currentUID, recipeID, profileKey)
    end
    local hasProfession = PlayerHasProfession(strat and strat.profession)

    return {
        recipeID = recipeID,
        currentCrafterUID = currentUID,
        currentHasProfession = hasProfession,
        hasCurrentSnapshot = currentSnapshot ~= nil,
        currentValidatedAt = currentValidatedAt > 0 and currentValidatedAt or nil,
        stale = stale,
        needsRefresh = hasProfession ~= false and (currentSnapshot == nil or stale),
        cachedCrafterUID = cachedUID,
        cachedCrafterName = cachedCharacter and cachedCharacter.name or nil,
        cachedCrafterRealm = cachedCharacter and cachedCharacter.realm or nil,
        cachedValidatedAt = cachedSnapshot and cachedValidatedAt or nil,
        hasCachedCrafter = cachedSnapshot ~= nil,
    }
end

function Stats.CanOpenRecipeForStrat(strat)
    local recipeID = NormalizeRecipeID(strat and strat.recipeID)
    if not recipeID then
        return false, "missing-recipe-id"
    end
    if type(C_TradeSkillUI) ~= "table"
            or type(C_TradeSkillUI.OpenRecipe) ~= "function" then
        return false, "profession-api-unavailable"
    end
    if not ResolveProfessionDef(strat and strat.profession) then
        return false, "unsupported-profession"
    end
    if PlayerHasProfession(strat and strat.profession) == false then
        return false, "profession-not-known"
    end
    return true, nil
end

-- Must be called directly from a hardware event (the Strategy Detail button).
-- We open only the selected strategy's recipe. Existing profession events then
-- capture the visible recipe stats and learned node ranks into GAM's own cache.
function Stats.OpenRecipeForStrat(strat, onRefresh, onFailure)
    local canOpen, reason = Stats.CanOpenRecipeForStrat(strat)
    if not canOpen then
        return false, reason
    end

    local recipeID = NormalizeRecipeID(strat.recipeID)
    if pendingRecipeRefreshes[recipeID] then
        return true, "open-pending"
    end
    local profession = ResolveProfessionDef(strat.profession)
    if type(C_TradeSkillUI.OpenTradeSkill) == "function" then
        local opened, openError = pcall(C_TradeSkillUI.OpenTradeSkill, profession.skillLineID)
        if not opened then
            return false, "open-profession-failed:" .. tostring(openError)
        end
    end

    local completed = false
    local lastReason = nil
    local function IsRecipeInCurrentProfession()
        local api = C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs
        if type(api) ~= "function" then return nil end
        local ok, recipeIDs = pcall(api)
        if not ok or type(recipeIDs) ~= "table" or #recipeIDs == 0 then
            return nil
        end
        for _, visibleRecipeID in ipairs(recipeIDs) do
            if NormalizeRecipeID(visibleRecipeID) == recipeID then
                return true
            end
        end
        return false
    end
    local function OpenAndCapture(isFinalAttempt)
        if completed then return true end
        -- OpenTradeSkill is asynchronous. Only classify the catalog recipe as
        -- unavailable after the final retry, once Blizzard has had time to
        -- populate the profession's complete learned + unlearned recipe list.
        if isFinalAttempt and IsRecipeInCurrentProfession() == false then
            lastReason = "recipe-not-in-current-profession"
            pendingRecipeRefreshes[recipeID] = nil
            if type(onFailure) == "function" then
                pcall(onFailure, lastReason, recipeID)
            end
            return false
        end
        local called, openError = pcall(C_TradeSkillUI.OpenRecipe, recipeID)
        if not called then
            lastReason = "open-recipe-failed:" .. tostring(openError)
        else
            local snapshot, captureReason = Stats.CaptureOpenRecipe(recipeID)
            if snapshot then
                completed = true
                pendingRecipeRefreshes[recipeID] = nil
            else
                lastReason = captureReason or "open-recipe-not-visible"
            end
        end
        if not completed then
            if isFinalAttempt then
                pendingRecipeRefreshes[recipeID] = nil
                if type(onFailure) == "function" then
                    pcall(onFailure, lastReason, recipeID)
                end
            end
            return false
        end
        if type(onRefresh) == "function" then
            pcall(onRefresh, recipeID)
        end
        return true
    end

    local openedImmediately = OpenAndCapture(false)
    if C_Timer and type(C_Timer.After) == "function" then
        -- Profession data can still be changing immediately after OpenTradeSkill.
        -- Verify the visible recipe on each bounded retry; OpenRecipe has no
        -- success return and the frame may otherwise remain on the old recipe.
        if not openedImmediately then
            pendingRecipeRefreshes[recipeID] = true
        end
        local delays = { 0.2, 0.8, 1.6 }
        for index, delay in ipairs(delays) do
            local isFinalAttempt = index == #delays
            C_Timer.After(delay, function()
                OpenAndCapture(isFinalAttempt)
            end)
        end
        return true, nil
    end
    if openedImmediately then
        return true, nil
    end
    return false, lastReason or "open-recipe-not-visible"
end

function Stats.CaptureProfessionNodes(profession, nodes, source, meta)
    local character, _, cache = EnsureCache()
    if not character then
        return nil, "no-db"
    end

    local state, catalog = EnsureProfessionNodeState(character, profession, SEASON_KEY)
    if not state or not catalog then
        return nil, "unsupported-profession"
    end
    if type(nodes) ~= "table" then
        return nil, "missing-nodes"
    end

    local normalized = {}
    for key, value in pairs(nodes) do
        local nodeID = nil
        local rank = nil
        local maxRank = nil
        local name = nil
        local description = nil
        local nameSource = nil
        if type(value) == "table" then
            nodeID = value.nodeID or key
            rank = value.rank or value.currentRank or value.activeRank or value.ranksPurchased
            maxRank = value.maxRank or value.maxRanks
            name = value.name or value.nodeName
            description = value.description or value.nodeDescription
            nameSource = value.nameSource
        else
            nodeID = key
            rank = value
        end

        local id = tonumber(nodeID)
        local node = id and GetCatalogNode(catalog, id) or nil
        if id and tonumber(rank) ~= nil then
            local previous = state.nodes and state.nodes[id]
            normalized[id] = {
                nodeID = id,
                rank = ClampRank(rank, (node and node.maxRank) or maxRank),
                maxRank = (node and node.maxRank) or tonumber(maxRank),
                name = name or (type(previous) == "table" and previous.name) or (node and node.name),
                description = description or (type(previous) == "table" and previous.description) or nil,
                nameSource = nameSource or (name and "blizzard")
                    or (type(previous) == "table" and previous.nameSource) or "catalog",
            }
        end
    end

    if not next(normalized) then
        return nil, "empty-nodes"
    end

    local changed = false
    for nodeID, node in pairs(normalized) do
        local existing = state.nodes and state.nodes[nodeID]
        local existingRank = type(existing) == "table" and existing.rank or existing
        if tonumber(existingRank) ~= tonumber(node.rank) then
            changed = true
            break
        end
    end
    if not changed then
        for nodeID in pairs(state.nodes or {}) do
            if normalized[nodeID] == nil then
                changed = true
                break
            end
        end
    end

    state.nodes = normalized
    state.source = source or "gam-native-nodes"
    state.capturedAt = GetCurrentTimestamp()
    state.skillLineID = catalog.skillLineID
    state.catalogVersion = catalog.version
    state.nodeHash = BuildNodeHash((function()
        local ranks = {}
        for nodeID, node in pairs(normalized) do
            ranks[nodeID] = node.rank
        end
        return ranks
    end)())
    if type(meta) == "table" then
        state.meta = CopySerializableTable(meta)
    end
    if changed then
        TouchRevision(character, cache)
    end

    return CopySerializableTable(state), nil
end

function Stats.CaptureOpenProfessionNodes(profession)
    if not profession then
        local def = GetOpenProfessionDef()
        profession = def and def.name or nil
    end
    if not profession then
        return nil, "no-open-profession"
    end
    local nodes, captureMeta = GetOpenNativeProfessionNodeRanks(profession)
    if not nodes then
        return nil, "no-open-profession-nodes"
    end
    return Stats.CaptureProfessionNodes(
        profession,
        nodes,
        "gam-native-nodes",
        captureMeta or { source = "Blizzard_Professions" })
end

function Stats.SetManualNodeRank(profession, nodeID, rank, season)
    local character, _, cache = EnsureCache()
    if not character then
        return false, "no-db"
    end
    local state, catalog = EnsureProfessionNodeState(character, profession, season or SEASON_KEY)
    if not state or not catalog then
        return false, "unsupported-profession"
    end
    local node = GetCatalogNode(catalog, nodeID)
    if not node then
        return false, "unknown-node"
    end

    state.manualOverrides = state.manualOverrides or {}
    state.manualOverrides[tonumber(nodeID)] = ClampRank(rank, node.maxRank)
    state.manualUpdatedAt = GetCurrentTimestamp()
    TouchRevision(character, cache)
    return true, nil
end

function Stats.SetManualNodeRanks(profession, ranks, season)
    if type(ranks) ~= "table" then
        return false, "missing-ranks"
    end
    for nodeID, rank in pairs(ranks) do
        local ok, err = Stats.SetManualNodeRank(profession, nodeID, rank, season)
        if not ok then
            return false, err
        end
    end
    return true, nil
end

function Stats.ResetProfessionNodesToCaptured(profession, season)
    local character, _, cache = EnsureCache()
    local state = character and EnsureProfessionNodeState(character, profession, season or SEASON_KEY)
    if not state then
        return false, "unsupported-profession"
    end
    state.manualOverrides = {}
    state.manualUpdatedAt = GetCurrentTimestamp()
    TouchRevision(character, cache)
    return true, nil
end

function Stats.ResetProfessionNodesToDefaults(profession, season)
    local character, _, cache = EnsureCache()
    if not character then
        return false, "no-db"
    end
    local state, catalog = EnsureProfessionNodeState(character, profession, season or SEASON_KEY)
    if not state or not catalog then
        return false, "unsupported-profession"
    end

    state.manualOverrides = {}
    local function applyDefault(nodeID)
        local node = GetCatalogNode(catalog, nodeID)
        if node and node.defaultRank ~= nil then
            state.manualOverrides[tonumber(nodeID)] = ClampRank(node.defaultRank, node.maxRank)
        end
    end
    for _, group in ipairs(catalog.uiGroups or {}) do
        for _, nodeID in ipairs(group.nodeIDs or {}) do
            applyDefault(nodeID)
        end
    end
    state.manualUpdatedAt = GetCurrentTimestamp()
    TouchRevision(character, cache)
    return true, nil
end

function Stats.GetProfessionNodeRows(profession, season)
    local character = EnsureCache()
    local def = ResolveProfessionDef(profession)
    local state, catalog
    if character and def then
        state, catalog = EnsureProfessionNodeState(character, def.name, season or SEASON_KEY)
    end
    if not state or not catalog then
        return nil, "unsupported-profession"
    end

    local captured = {}
    for nodeID, nodeState in pairs(state.nodes or {}) do
        local id = tonumber(nodeID) or nodeID
        if type(nodeState) == "table" then
            captured[id] = nodeState
        else
            captured[id] = { rank = nodeState }
        end
    end

    local groups = {}
    for _, group in ipairs(catalog.uiGroups or {}) do
        local rows = {}
        for _, nodeID in ipairs(group.nodeIDs or {}) do
            local node = GetCatalogNode(catalog, nodeID)
            if node then
                local manualRank = state.manualOverrides and state.manualOverrides[nodeID]
                local capturedNode = captured[nodeID]
                local capturedRank = capturedNode and capturedNode.rank
                local fallbackName = NodeDisplay and NodeDisplay.GetFallbackName
                    and NodeDisplay.GetFallbackName(nodeID)
                local capturedName = capturedNode and capturedNode.name
                local capturedNameSource = capturedNode and capturedNode.nameSource
                local preferredName = capturedNameSource == "blizzard" and capturedName
                    or fallbackName or capturedName or node.name
                local preferredNameSource = capturedNameSource == "blizzard" and "blizzard"
                    or (fallbackName and "hardcoded") or capturedNameSource or "catalog"
                local effectiveRank = manualRank
                if effectiveRank == nil then
                    effectiveRank = capturedRank
                end
                if effectiveRank == nil then
                    effectiveRank = node.defaultRank or 0
                end
                rows[#rows + 1] = {
                    nodeID = nodeID,
                    name = preferredName,
                    nameSource = preferredNameSource,
                    description = capturedNode and capturedNode.description,
                    maxRank = node.maxRank,
                    defaultRank = node.defaultRank or 0,
                    capturedRank = capturedRank,
                    manualRank = manualRank,
                    rank = ClampRank(effectiveRank, node.maxRank),
                    stats = CopyShallowTable(node.stats),
                    pricingNote = node.pricingNote,
                }
            end
        end
        local rootRow = rows[1]
        groups[#groups + 1] = {
            label = (rootRow and rootRow.nameSource ~= "catalog" and rootRow.name) or group.label,
            catalogLabel = group.label,
            rootNodeID = group.nodeIDs and group.nodeIDs[1],
            rows = rows,
        }
    end

    return {
        profession = def.name,
        season = SEASON_KEY,
        source = state.source or "workbook-default",
        capturedAt = state.capturedAt,
        nodeHash = state.nodeHash,
        groups = groups,
    }, nil
end

if type(CreateFrame) == "function" then
    local nodeCaptureFrame = CreateFrame("Frame")
    nodeCaptureFrame:RegisterEvent("TRADE_SKILL_SHOW")
    nodeCaptureFrame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
    nodeCaptureFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    nodeCaptureFrame:RegisterEvent("TRADE_SKILL_CLOSE")

    local captureGeneration = 0
    local function captureOpenProfession()
        if not Stats.CaptureOpenProfessionNodes then return false end
        if type(ProfessionsFrame) == "table"
                and type(ProfessionsFrame.IsShown) == "function" then
            local okShown, shown = pcall(ProfessionsFrame.IsShown, ProfessionsFrame)
            if okShown and not shown then return false end
        end
        if C_TradeSkillUI and type(C_TradeSkillUI.IsDataSourceChanging) == "function" then
            local okChanging, changing = pcall(C_TradeSkillUI.IsDataSourceChanging)
            if okChanging and changing then return false end
        end
        local ok, state = pcall(Stats.CaptureOpenProfessionNodes)
        return ok and type(state) == "table"
    end

    local function scheduleRetry()
        if not (C_Timer and type(C_Timer.After) == "function") then return end
        captureGeneration = captureGeneration + 1
        local generation = captureGeneration
        for _, delay in ipairs({ 0.2, 1.0 }) do
            C_Timer.After(delay, function()
                if generation == captureGeneration and captureOpenProfession() then
                    captureGeneration = captureGeneration + 1
                end
            end)
        end
    end

    nodeCaptureFrame:SetScript("OnEvent", function(_, event)
        if event == "TRADE_SKILL_CLOSE" then
            captureGeneration = captureGeneration + 1
            return
        end
        if not captureOpenProfession() then
            scheduleRetry()
        end
    end)
end

function Stats.GetSupportedNodeProfessions()
    local out = {}
    for _, def in ipairs(PROFESSION_DEFS) do
        if GetSpecializationCatalog(def.name, SEASON_KEY) then
            out[#out + 1] = def.name
        end
    end
    return out
end

function Stats.GetAllProfiles()
    local profiles = {}
    for profileKey in pairs(GetFormulaProfiles()) do
        profiles[profileKey] = Stats.GetProfile(profileKey)
    end
    local character = EnsureCache()
    if type(character) == "table" then
        for profileKey, snapshot in pairs(character.profiles or {}) do
            if not profiles[profileKey] then
                profiles[profileKey] = Stats.GetProfile(profileKey)
            end
        end
        for profileKey, snapshot in pairs(character.manualProfiles or {}) do
            if not profiles[profileKey] then
                profiles[profileKey] = Stats.GetProfile(profileKey)
            end
        end
    end
    return profiles
end
