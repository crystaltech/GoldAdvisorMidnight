-- GoldAdvisorMidnight/CraftingStatsV2.lua
-- GAM-owned V2 crafting stat resolver. CraftSim may import snapshots here, but
-- pricing code should not depend on CraftSim directly.
-- Module: GAM.CraftingStatsV2

local ADDON_NAME, GAM = ...
local Stats = {}
GAM.CraftingStatsV2 = Stats

local CACHE_VERSION = 1

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

local function CopyNumericTable(source)
    if type(source) ~= "table" then return nil end
    local out = {}
    for key, value in pairs(source) do
        local n = tonumber(value)
        if n ~= nil then
            out[key] = n
        end
    end
    return next(out) and out or nil
end

local function CopySerializableTable(source, depth)
    if type(source) ~= "table" then return nil end
    if (depth or 0) > 6 then return nil end

    local out = {}
    for key, value in pairs(source) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" then
            local valueType = type(value)
            if valueType == "table" then
                out[key] = CopySerializableTable(value, (depth or 0) + 1)
            elseif valueType == "string" or valueType == "number" or valueType == "boolean" then
                out[key] = value
            end
        end
    end
    return next(out) and out or nil
end

local function GetCurrentTimestamp()
    if type(time) == "function" then
        return time()
    end
    if os and type(os.time) == "function" then
        return os.time()
    end
    return 0
end

local function GetCrafterUID()
    local name = type(UnitName) == "function" and UnitName("player") or nil
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil
    return (name or "Unknown") .. "-" .. (realm or "Unknown")
end

local function EnsureCache()
    local db = GAM.db or GoldAdvisorMidnightDB
    if type(db) ~= "table" then
        return nil
    end

    db.v2StatCache = db.v2StatCache or {}
    local cache = db.v2StatCache
    cache.version = CACHE_VERSION
    cache.characters = cache.characters or {}

    -- Lazily migrate the first test-branch profile cache shape:
    -- v2StatCache.profiles[crafterUID][profileKey] = snapshot
    if type(cache.profiles) == "table" and not cache._migratedProfileCacheV1 then
        for uid, profiles in pairs(cache.profiles) do
            if type(profiles) == "table" then
                cache.characters[uid] = cache.characters[uid] or {}
                cache.characters[uid].profiles = cache.characters[uid].profiles or {}
                for profileKey, snapshot in pairs(profiles) do
                    if type(snapshot) == "table" and cache.characters[uid].profiles[profileKey] == nil then
                        cache.characters[uid].profiles[profileKey] = snapshot
                    end
                end
            end
        end
        cache._migratedProfileCacheV1 = true
    end

    local uid = GetCrafterUID()
    cache.characters[uid] = cache.characters[uid] or {}
    local character = cache.characters[uid]
    character.recipes = character.recipes or {}
    character.profiles = character.profiles or {}
    character.manualProfiles = character.manualProfiles or {}
    return character, uid, cache
end

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
        fallbackReason = profile and nil or "missing-profile",
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

    -- CraftSim snapshots carry the learned-node and total recipe stat breakdowns.
    -- Keep them authoritative when a leaner native fallback is captured later.
    return IsCraftSimSnapshot(existing) and not IsCraftSimSnapshot(incoming)
end

local function ApplySnapshotToDefaults(defaults, snapshot, statSource, fallbackReason)
    local result = {}
    for key, value in pairs(defaults or {}) do
        result[key] = value
    end
    snapshot = snapshot or {}

    result.profileKey = snapshot.profileKey or result.profileKey
    result.recipeID = NormalizeRecipeID(snapshot.recipeID) or result.recipeID
    result.recipeName = snapshot.recipeName or result.recipeName
    result.profession = snapshot.profession or result.profession
    result.statSource = statSource or snapshot.source or result.statSource
    result.fallbackReason = fallbackReason
    result.capturedAt = snapshot.capturedAt
    result.cachedSource = snapshot.cachedSource
    result.statQuality = snapshot.statQuality
    result.nodeHash = snapshot.nodeHash
    result.nodeCount = snapshot.nodeCount

    if snapshot.supportsMulticraft ~= nil then
        result.supportsMulticraft = snapshot.supportsMulticraft and true or false
    end
    if snapshot.supportsResourcefulness ~= nil then
        result.supportsResourcefulness = snapshot.supportsResourcefulness and true or false
    end

    if snapshot.multiPercent ~= nil and result.supportsMulticraft then
        result.multiPercent = ClampPercent(snapshot.multiPercent)
    end
    if snapshot.resPercent ~= nil and result.supportsResourcefulness then
        result.resPercent = ClampPercent(snapshot.resPercent)
    end
    if snapshot.multiExtra ~= nil and result.supportsMulticraft then
        result.multiExtra = ClampNonNegative(snapshot.multiExtra)
    end
    if snapshot.resExtra ~= nil and result.supportsResourcefulness then
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
        "nodeStats",
        "baseStats",
        "gearStats",
        "buffStats",
        "modifierStats",
        "nodeRanks",
    }
    for _, field in ipairs(nestedFields) do
        result[field] = CopySerializableTable(snapshot[field])
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

local function ReadPercentFromBonusStat(statInfo)
    if type(statInfo) ~= "table" then
        return nil
    end
    local value = tonumber(statInfo.ratingPct)
    if value ~= nil then
        return value
    end
    value = tonumber(statInfo.bonusStatPercent)
    if value ~= nil then
        return value
    end
    value = tonumber(statInfo.percent)
    if value ~= nil then
        return value
    end
    return nil
end

local function ApplyOperationBonusStats(snapshot, operationInfo)
    local bonusStats = operationInfo and operationInfo.bonusStats
    if type(bonusStats) ~= "table" then
        return
    end

    for _, statInfo in ipairs(bonusStats) do
        local name = tostring(statInfo.bonusStatName or statInfo.name or ""):lower()
        if name:find("multicraft", 1, true) then
            snapshot.multiPercent = ReadPercentFromBonusStat(statInfo)
            snapshot.supportsMulticraft = snapshot.multiPercent ~= nil
        elseif name:find("resourcefulness", 1, true) then
            snapshot.resPercent = ReadPercentFromBonusStat(statInfo)
            snapshot.supportsResourcefulness = snapshot.resPercent ~= nil
        end
    end
end

local testOpenSnapshot = nil

local function GetOpenNativeRecipeSnapshot()
    if testOpenSnapshot ~= nil then
        return testOpenSnapshot
    end

    local form = ProfessionsFrame
        and ProfessionsFrame.CraftingPage
        and ProfessionsFrame.CraftingPage.SchematicForm
    if not form then
        return nil
    end

    local okRecipe, recipeInfo = pcall(function()
        if type(form.GetRecipeInfo) == "function" then
            return form:GetRecipeInfo()
        end
        return nil
    end)
    if not okRecipe or not recipeInfo or not recipeInfo.recipeID then
        return nil
    end

    local snapshot = {
        source = "native-open",
        recipeID = NormalizeRecipeID(recipeInfo.recipeID),
        recipeName = recipeInfo.name,
    }

    local okOp, operationInfo = pcall(function()
        if type(form.GetRecipeOperationInfo) == "function" then
            return form:GetRecipeOperationInfo()
        end
        return nil
    end)
    if okOp then
        ApplyOperationBonusStats(snapshot, operationInfo)
    end

    if C_TradeSkillUI and type(C_TradeSkillUI.GetTradeSkillLineForRecipe) == "function" then
        local okSkill, skillLineID, skillLineName, parentSkillLineID = pcall(function()
            return C_TradeSkillUI.GetTradeSkillLineForRecipe(snapshot.recipeID)
        end)
        if okSkill then
            snapshot.profession = skillLineName
            snapshot.skillLineID = skillLineID
            snapshot.parentSkillLineID = parentSkillLineID
        end
    end

    snapshot.profileKey = InferProfileKey(
        snapshot.recipeName,
        snapshot.profession,
        snapshot.supportsMulticraft)
    return snapshot.profileKey and snapshot or nil
end

function Stats.SaveSnapshot(snapshot)
    local normalized = CopySnapshot(snapshot)
    if not normalized or not normalized.profileKey then
        return false, "missing-profile"
    end

    local character = EnsureCache()
    if not character then
        return false, "no-db"
    end

    normalized.capturedAt = normalized.capturedAt or GetCurrentTimestamp()
    normalized.source = normalized.source or "gam-cache-profile"
    local preservedExisting = false

    if normalized.recipeID then
        local recipeKey = tostring(normalized.recipeID)
        if ShouldPreserveExistingSnapshot(character.recipes[recipeKey], normalized) then
            preservedExisting = true
        else
            character.recipes[recipeKey] = CopySnapshot(normalized)
        end
    end

    if ShouldPreserveExistingSnapshot(character.profiles[normalized.profileKey], normalized) then
        preservedExisting = true
    else
        character.profiles[normalized.profileKey] = CopySnapshot(normalized)
    end
    return true, preservedExisting and "preserved-existing" or nil
end

function Stats.SetManualProfile(profileKey, values)
    if not profileKey then
        return false, "missing-profile"
    end
    local character = EnsureCache()
    if not character then
        return false, "no-db"
    end

    local manual = CopySnapshot(values or {}) or {}
    manual.profileKey = profileKey
    manual.source = "manual"
    manual.capturedAt = GetCurrentTimestamp()
    character.manualProfiles[profileKey] = manual
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
            return ApplySnapshotToDefaults(manualDefaults, cached, source), source
        end
        if type(manual) == "table" then
            return manualDefaults, "manual"
        end
    end
    return defaults, "workbook-default"
end

function Stats.ResolveForStrat(strat, opts)
    opts = opts or ((GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {})
    local profileKey = GetProfileKeyForStrat(strat)
    local defaults = GetProfileDefaults(profileKey, opts)
    local recipeID = NormalizeRecipeID(strat and strat.recipeID)
    local character = EnsureCache()
    local manualDefaults = defaults

    if type(character) == "table" then
        local manual = profileKey and character.manualProfiles and character.manualProfiles[profileKey]
        if type(manual) == "table" then
            manualDefaults = ApplySnapshotToDefaults(defaults, manual, "manual")
        end
    end

    local recipeSnapshot = GetCachedRecipeSnapshot(character, recipeID, profileKey)
    local profileSnapshot = GetCachedProfileSnapshot(character, profileKey)

    if IsCraftSimSnapshot(recipeSnapshot) then
        return ApplySnapshotToDefaults(manualDefaults, recipeSnapshot,
            SourceForCachedSnapshot(recipeSnapshot, "gam-cache-recipe"))
    end

    local openSnapshot = GetOpenNativeRecipeSnapshot()
    local openMatchKind = GetSnapshotMatchKind(openSnapshot, strat, profileKey)
    if openMatchKind == "recipe" then
        Stats.SaveSnapshot(openSnapshot)
        return ApplySnapshotToDefaults(manualDefaults, openSnapshot, "native-open")
    end

    if recipeSnapshot then
        return ApplySnapshotToDefaults(manualDefaults, recipeSnapshot,
            SourceForCachedSnapshot(recipeSnapshot, "gam-cache-recipe"))
    end

    if IsCraftSimSnapshot(profileSnapshot) then
        return ApplySnapshotToDefaults(manualDefaults, profileSnapshot,
            SourceForCachedSnapshot(profileSnapshot, "gam-cache-profile"))
    end

    if openMatchKind == "profile" then
        Stats.SaveSnapshot(openSnapshot)
        return ApplySnapshotToDefaults(manualDefaults, openSnapshot, "native-open-profile")
    end

    if profileSnapshot then
        return ApplySnapshotToDefaults(manualDefaults, profileSnapshot,
            SourceForCachedSnapshot(profileSnapshot, "gam-cache-profile"))
    end

    if type(character) == "table" then
        local manual = profileKey and character.manualProfiles and character.manualProfiles[profileKey]
        if type(manual) == "table" then
            return manualDefaults
        end
    end

    return defaults
end

function Stats.CaptureOpenRecipe()
    local snapshot = GetOpenNativeRecipeSnapshot()
    if not snapshot then
        return nil, "no-open-native-recipe"
    end
    local ok, err = Stats.SaveSnapshot(snapshot)
    if not ok then
        return nil, err
    end
    return snapshot, nil
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

function Stats.DumpProfiles(query)
    query = tostring(query or ""):lower()
    local profiles = Stats.GetAllProfiles()
    local keys = {}
    for key in pairs(profiles) do
        if query == "" or tostring(key):lower():find(query, 1, true) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)

    GAM.Log.Info("=== GAM V2 Stat Profiles ===")
    if #keys == 0 then
        GAM.Log.Info("no profile matched '%s'", query)
    end
    for _, key in ipairs(keys) do
        local p = profiles[key] or {}
        GAM.Log.Info("%s source=%s recipeID=%s nodeHash=%s mc=%s mcExtra=%s res=%s resExtra=%s captured=%s",
            tostring(key),
            tostring(p.statSource or p.source or "-"),
            tostring(p.recipeID or "-"),
            tostring(p.nodeHash or "-"),
            tostring(p.multiPercent or "-"),
            tostring(p.multiExtra or "-"),
            tostring(p.resPercent or "-"),
            tostring(p.resExtra or "-"),
            tostring(p.capturedAt or "-"))
    end
    GAM.Log.Info("=== End V2 Stat Profiles ===")
end

local READY_SOURCES = {
    ["native-open"] = true,
    ["native-open-profile"] = true,
    ["gam-cache-recipe"] = true,
    ["gam-cache-profile"] = true,
    ["craftsim-imported"] = true,
}

local function BuildProfileUsage()
    local usage = {}
    local missing = {}
    local total = 0
    if not (GAM.Importer and type(GAM.Importer.GetAllStrats) == "function") then
        return usage, missing, total
    end

    local ok, strats = pcall(function()
        return GAM.Importer.GetAllStrats()
    end)
    if not ok or type(strats) ~= "table" then
        return usage, missing, total
    end

    for _, strat in ipairs(strats) do
        local isFormula = type(strat) == "table" and (strat.calcMode == "formula" or strat.formulaProfile ~= nil)
        if isFormula then
            total = total + 1
            local profileKey = strat.statProfileKey or strat.formulaProfile
            if profileKey then
                usage[profileKey] = (usage[profileKey] or 0) + 1
            else
                missing[#missing + 1] = strat
            end
        end
    end
    return usage, missing, total
end

local function GetAuditBucket(profile)
    local source = tostring((profile and (profile.statSource or profile.source)) or "workbook-default")
    if source == "manual" then
        return "manual"
    end
    if READY_SOURCES[source] then
        return "ready"
    end
    return "needsCapture"
end

function Stats.GetAudit(query)
    query = tostring(query or ""):lower()
    local profiles = Stats.GetAllProfiles()
    local usage, missingStrats, formulaCount = BuildProfileUsage()
    local audit = {
        query = query,
        formulaCount = formulaCount,
        missingStrategyProfiles = missingStrats,
        ready = {},
        manual = {},
        needsCapture = {},
    }

    for profileKey, profile in pairs(profiles) do
        if query == "" or tostring(profileKey):lower():find(query, 1, true) then
            local entry = {
                profileKey = profileKey,
                profile = profile,
                source = tostring(profile.statSource or profile.source or "workbook-default"),
                usageCount = usage[profileKey] or 0,
            }
            local bucket = GetAuditBucket(profile)
            audit[bucket][#audit[bucket] + 1] = entry
        end
    end

    local function sortEntries(a, b)
        if (a.usageCount or 0) ~= (b.usageCount or 0) then
            return (a.usageCount or 0) > (b.usageCount or 0)
        end
        return tostring(a.profileKey) < tostring(b.profileKey)
    end
    table.sort(audit.ready, sortEntries)
    table.sort(audit.manual, sortEntries)
    table.sort(audit.needsCapture, sortEntries)
    return audit
end

local function DumpAuditBucket(label, entries, emptyText, limit)
    GAM.Log.Info("%s (%d)", label, #entries)
    if #entries == 0 then
        GAM.Log.Info("  %s", emptyText)
        return
    end
    for i, entry in ipairs(entries) do
        if limit and i > limit then
            GAM.Log.Info("  ... %d more", #entries - limit)
            break
        end
        local p = entry.profile or {}
        GAM.Log.Info("  %s source=%s strats=%d recipeID=%s captured=%s nodeHash=%s mc=%s/%s res=%s/%s",
            tostring(entry.profileKey),
            tostring(entry.source),
            tonumber(entry.usageCount) or 0,
            tostring(p.recipeID or "-"),
            tostring(p.capturedAt or "-"),
            tostring(p.nodeHash or "-"),
            tostring(p.multiPercent or "-"),
            tostring(p.multiExtra or "-"),
            tostring(p.resPercent or "-"),
            tostring(p.resExtra or "-"))
    end
end

function Stats.DumpAudit(query)
    local audit = Stats.GetAudit(query)
    GAM.Log.Info("=== GAM V2 Stat Audit ===")
    if audit.query and audit.query ~= "" then
        GAM.Log.Info("filter=%s", audit.query)
    end
    GAM.Log.Info("formulaStrategies=%d readyProfiles=%d manualProfiles=%d needsCapture=%d missingStrategyProfiles=%d",
        audit.formulaCount or 0,
        #audit.ready,
        #audit.manual,
        #audit.needsCapture,
        #(audit.missingStrategyProfiles or {}))

    DumpAuditBucket("Ready", audit.ready, "No captured/imported profiles matched.", 20)
    DumpAuditBucket("Manual", audit.manual, "No manual profiles matched.", 20)
    DumpAuditBucket("Needs capture", audit.needsCapture, "No workbook-default profiles matched.", 20)

    if audit.missingStrategyProfiles and #audit.missingStrategyProfiles > 0 then
        GAM.Log.Info("Strategies missing stat profile (%d)", #audit.missingStrategyProfiles)
        for i, strat in ipairs(audit.missingStrategyProfiles) do
            if i > 12 then
                GAM.Log.Info("  ... %d more", #audit.missingStrategyProfiles - 12)
                break
            end
            GAM.Log.Info("  %s [%s]",
                tostring(strat.stratName or "?"),
                tostring(strat.id or "-"))
        end
    end
    GAM.Log.Info("=== End V2 Stat Audit ===")
end

function Stats.RunSmokeChecks()
    local originalDB = GAM.db
    local originalSavedDB = GoldAdvisorMidnightDB
    local originalOpen = testOpenSnapshot
    local ok, err = pcall(function()
        GAM.db = {
            options = {},
            v2StatCache = {
                version = CACHE_VERSION,
                characters = {},
            },
        }
        GoldAdvisorMidnightDB = GAM.db

        local strat = {
            profession = "Inscription",
            formulaProfile = "insc_ink",
            statProfileKey = "insc_ink",
            recipeID = 1001,
        }
        local base = Stats.ResolveForStrat(strat, {})
        assert(base and base.statSource == "workbook-default", "default profile stat source failed")

        local manualOK = Stats.SetManualProfile("insc_milling", {
            resPercent = 31,
            resExtra = 0.55,
            supportsResourcefulness = true,
        })
        assert(manualOK, "manual profile save failed")
        local manual = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
        }, {})
        assert(manual.statSource == "manual" and manual.resPercent == 31,
            "manual profile resolve failed")

        assert(Stats.SaveSnapshot({
            source = "craftsim-imported",
            recipeID = 1001,
            recipeName = "Munsell Ink",
            profession = "Inscription",
            profileKey = "insc_ink",
            resPercent = 12.5,
            resExtra = 0.35,
            supportsResourcefulness = true,
        }))
        local imported = Stats.ResolveForStrat(strat, {})
        assert(imported.statSource == "craftsim-imported" and imported.resPercent == 12.5,
            "imported recipe snapshot resolve failed")

        assert(Stats.SetManualProfile("insc_ink", {
            resExtra = 0.9,
            supportsResourcefulness = true,
        }))
        assert(Stats.SaveSnapshot({
            source = "craftsim-imported",
            recipeID = 1004,
            recipeName = "Manual-Filled Ink",
            profession = "Inscription",
            profileKey = "insc_ink",
            resPercent = 10,
            supportsResourcefulness = true,
        }))
        local manualFilled = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1004,
        }, {})
        assert(manualFilled.statSource == "craftsim-imported"
                and manualFilled.resPercent == 10
                and math.abs((manualFilled.resExtra or 0) - 0.9) < 0.0001,
            "manual profile values should fill missing imported snapshot extras")

        testOpenSnapshot = {
            source = "native-open",
            recipeID = 1002,
            recipeName = "Some Milling",
            profession = "Inscription",
            profileKey = "insc_milling",
            resPercent = 55,
            resExtra = 0.55,
            supportsResourcefulness = true,
        }
        local native = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
            recipeID = 1002,
        }, {})
        assert(native.statSource == "native-open" and native.resPercent == 55,
            "native open snapshot resolve failed")

        testOpenSnapshot = nil
        assert(Stats.SaveSnapshot({
            source = "craftsim-imported",
            recipeID = 1002,
            recipeName = "Some Milling",
            profession = "Inscription",
            profileKey = "insc_milling",
            resPercent = 5,
            resExtra = 0.55,
            supportsResourcefulness = true,
            nodeHash = "111:2",
            totalStats = {
                resourcefulness = { percent = 5, extra = 0.55 },
            },
            nodeStats = {
                resourcefulness = { percent = 3, extra = 0.55 },
            },
        }))
        local preserved = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
            recipeID = 1002,
        }, {})
        assert(preserved.statSource == "craftsim-imported"
                and preserved.resPercent == 5
                and preserved.nodeHash == "111:2"
                and preserved.nodeStats
                and preserved.nodeStats.resourcefulness
                and preserved.nodeStats.resourcefulness.extra == 0.55,
            "CraftSim import should replace native fallback and preserve node details")

        local audit = Stats.GetAudit("insc")
        assert(type(audit) == "table" and type(audit.ready) == "table"
                and type(audit.manual) == "table"
                and type(audit.needsCapture) == "table",
            "stat profile audit shape failed")

        testOpenSnapshot = {
            source = "native-open",
            recipeID = 1003,
            recipeName = "Munsell Ink",
            profession = "Inscription",
            profileKey = "insc_ink",
            resPercent = 90,
            supportsResourcefulness = true,
        }
        local mismatch = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
        }, {})
        assert(mismatch.statSource ~= "native-open" and mismatch.profileKey == "insc_milling",
            "open profile mismatch leaked into another profile")
    end)
    testOpenSnapshot = originalOpen
    GAM.db = originalDB
    GoldAdvisorMidnightDB = originalSavedDB
    return ok, err
end
