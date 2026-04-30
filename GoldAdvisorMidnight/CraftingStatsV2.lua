-- GoldAdvisorMidnight/CraftingStatsV2.lua
-- GAM-owned V2 crafting stat resolver. CraftSim may import snapshots here, but
-- pricing code should not depend on CraftSim directly.
-- Module: GAM.CraftingStatsV2

local ADDON_NAME, GAM = ...
local Stats = {}
GAM.CraftingStatsV2 = Stats

local CACHE_VERSION = 2
local SEASON_KEY = "midnight"
local PROFESSION_DEFS = {
    { name = "Alchemy",        skillLineID = 171, profiles = { "alchemy" }, aliases = { "alchemy", "alch" } },
    { name = "Blacksmithing",  skillLineID = 164, profiles = { "blacksmithing" }, aliases = { "blacksmith", "bs" } },
    { name = "Enchanting",     skillLineID = 333, profiles = { "ench_shatter", "ench_craft" }, aliases = { "enchant", "ench" } },
    { name = "Engineering",    skillLineID = 202, profiles = { "engineering_recycling", "engineering_craft" }, aliases = { "engineer", "eng" } },
    { name = "Inscription",    skillLineID = 773, profiles = { "insc_milling", "insc_ink", "insc_missive_estimated", "insc_codified" }, aliases = { "inscription", "insc" } },
    { name = "Jewelcrafting",  skillLineID = 755, profiles = { "jc_prospect", "jc_crush", "jc_craft" }, aliases = { "jewelcraft", "jc" } },
    { name = "Leatherworking", skillLineID = 165, profiles = { "leatherworking" }, aliases = { "leather", "lw" } },
    { name = "Tailoring",      skillLineID = 197, profiles = { "tailoring" }, aliases = { "tailor", "tail" } },
}
local PROFESSION_BY_PROFILE = {}
local PROFESSION_BY_NAME = {}
local PROFESSION_BY_SKILL_LINE = {}
for _, def in ipairs(PROFESSION_DEFS) do
    PROFESSION_BY_NAME[def.name:lower()] = def
    PROFESSION_BY_SKILL_LINE[def.skillLineID] = def
    for _, alias in ipairs(def.aliases or {}) do
        PROFESSION_BY_NAME[alias:lower()] = def
    end
    for _, profileKey in ipairs(def.profiles or {}) do
        PROFESSION_BY_PROFILE[profileKey] = def
    end
end

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

local function CopyShallowTable(source)
    if type(source) ~= "table" then return nil end
    local out = {}
    for key, value in pairs(source) do
        out[key] = value
    end
    return out
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
    character.nodeState = character.nodeState or {}
    return character, uid, cache
end

local function ResolveProfessionDef(profession)
    if type(profession) == "table" and profession.name then
        return profession
    end
    local text = tostring(profession or ""):lower()
    if text == "" then return nil end
    return PROFESSION_BY_NAME[text] or PROFESSION_BY_PROFILE[profession]
end

local function GetSpecializationCatalog(profession, season)
    local def = ResolveProfessionDef(profession)
    if not def then return nil end
    local root = GAM_SPECIALIZATION_DATA
    local seasonKey = tostring(season or SEASON_KEY):upper()
    return root
        and root[seasonKey]
        and root[seasonKey][def.name]
        or nil
end

local function IsSpecializationProfile(profileKey)
    local def = PROFESSION_BY_PROFILE[profileKey]
    return def and GetSpecializationCatalog(def.name, SEASON_KEY) ~= nil or false
end

local function GetProfessionForProfile(profileKey)
    local def = PROFESSION_BY_PROFILE[profileKey]
    return def and def.name or nil
end

local function ClampRank(value, maxRank)
    local n = math.floor(tonumber(value) or 0)
    if n < 0 then n = 0 end
    local maxValue = tonumber(maxRank) or n
    if maxValue >= 0 and n > maxValue then n = maxValue end
    return n
end

local function GetCatalogNode(catalog, nodeID)
    if type(catalog) ~= "table" or type(catalog.nodes) ~= "table" then
        return nil
    end
    local id = tonumber(nodeID)
    return (id and catalog.nodes[id]) or catalog.nodes[tostring(nodeID)]
end

local function NodeAppliesToProfile(node, profileKey)
    if type(node) ~= "table" then return false end
    if type(node.profiles) ~= "table" then return true end
    return node.profiles[profileKey] and true or false
end

local function NormalizeRecipeIDForLookup(recipeID)
    local n = tonumber(recipeID)
    if n and n > 0 then
        return tostring(math.floor(n))
    end
    return nil
end

local function GetRecipeNodeSet(catalog, recipeID)
    if type(catalog) ~= "table" or type(catalog.recipeMapping) ~= "table" then
        return nil
    end
    local recipeKey = NormalizeRecipeIDForLookup(recipeID)
    if not recipeKey then
        return nil
    end
    local mapping = catalog.recipeMapping[recipeKey] or catalog.recipeMapping[tonumber(recipeKey)]
    if type(mapping) ~= "table" then
        return nil
    end
    local out = {}
    for _, nodeID in ipairs(mapping) do
        out[tonumber(nodeID) or nodeID] = true
    end
    return out
end

local function NodeAppliesToContext(node, profileKey, recipeNodeSet)
    if not NodeAppliesToProfile(node, profileKey) then
        return false
    end
    if type(recipeNodeSet) == "table" then
        return recipeNodeSet[node.nodeID] or recipeNodeSet[tostring(node.nodeID)] or false
    end
    return true
end

local function CatalogHasContextStat(catalog, profileKey, recipeNodeSet, statKey)
    if type(catalog) ~= "table" or type(catalog.nodes) ~= "table" then
        return false
    end
    for _, node in pairs(catalog.nodes) do
        if type(node) == "table"
                and type(node.stats) == "table"
                and node.stats[statKey] ~= nil
                and NodeAppliesToContext(node, profileKey, recipeNodeSet) then
            return true
        end
    end
    return false
end

local function EnsureProfessionNodeState(character, profession, season)
    if type(character) ~= "table" then return nil end
    local def = ResolveProfessionDef(profession)
    if not def then return nil end
    local catalog = GetSpecializationCatalog(profession, season)
    if not catalog then return nil end

    character.nodeState = character.nodeState or {}
    local seasonKey = tostring(season or SEASON_KEY):lower()
    character.nodeState[seasonKey] = character.nodeState[seasonKey] or {}
    local professions = character.nodeState[seasonKey]
    professions[def.name] = professions[def.name] or {
        profession = def.name,
        season = seasonKey,
        skillLineID = catalog.skillLineID,
        nodes = {},
        manualOverrides = {},
    }

    local state = professions[def.name]
    state.nodes = state.nodes or {}
    state.manualOverrides = state.manualOverrides or {}
    state.skillLineID = state.skillLineID or catalog.skillLineID
    state.profession = def.name
    state.season = seasonKey
    return state, catalog
end

local function HasAnyRank(ranks)
    if type(ranks) ~= "table" then return false end
    for _, rank in pairs(ranks) do
        if tonumber(rank) ~= nil then
            return true
        end
    end
    return false
end

local function BuildNodeHash(rankMap)
    if type(rankMap) ~= "table" then return nil end
    local parts = {}
    for nodeID, rank in pairs(rankMap) do
        local n = tonumber(rank)
        if n and n > 0 then
            parts[#parts + 1] = tostring(nodeID) .. ":" .. tostring(n)
        end
    end
    table.sort(parts)
    return (#parts > 0) and table.concat(parts, "|") or nil
end

local function CopyNodeRankList(rankMap, catalog)
    if type(rankMap) ~= "table" then return nil end
    local rows = {}
    for nodeID, rank in pairs(rankMap) do
        local id = tonumber(nodeID)
        local node = GetCatalogNode(catalog, id or nodeID)
        rows[#rows + 1] = {
            nodeID = id or nodeID,
            rank = tonumber(rank) or 0,
            maxRank = node and node.maxRank or nil,
            name = node and node.name or nil,
        }
    end
    table.sort(rows, function(a, b)
        return tostring(a.nodeID) < tostring(b.nodeID)
    end)
    return (#rows > 0) and rows or nil
end

local function GetEffectiveNodeRanks(character, profession, season, includeDefaults)
    local state, catalog = EnsureProfessionNodeState(character, profession, season)
    if not state or not catalog then
        return nil, nil, nil
    end

    local ranks = {}
    local hasCaptured = false
    for nodeID, nodeState in pairs(state.nodes or {}) do
        local rank = type(nodeState) == "table" and nodeState.rank or nodeState
        if tonumber(rank) ~= nil then
            ranks[tonumber(nodeID) or nodeID] = rank
            hasCaptured = true
        end
    end

    local hasManual = false
    for nodeID, rank in pairs(state.manualOverrides or {}) do
        ranks[tonumber(nodeID) or nodeID] = rank
        hasManual = true
    end

    if includeDefaults and not hasCaptured and not hasManual then
        for nodeID, node in pairs(catalog.nodes or {}) do
            if node.defaultRank ~= nil then
                ranks[nodeID] = node.defaultRank
            end
        end
    end

    if not HasAnyRank(ranks) then
        return nil, catalog, state
    end
    return ranks, catalog, state, hasManual, hasCaptured
end

local function AddStatTotal(target, key, value, rank)
    local n = tonumber(value)
    if n == nil then return end
    target[key] = (target[key] or 0) + (n * (tonumber(rank) or 0))
end

local function SummarizeNodeRanks(profileKey, character, includeDefaults, recipeID)
    local profession = GetProfessionForProfile(profileKey)
    if not profession then return nil end
    local ranks, catalog, state, hasManual, hasCaptured = GetEffectiveNodeRanks(
        character,
        profession,
        SEASON_KEY,
        includeDefaults)
    if not ranks or not catalog then
        return nil
    end
    if catalog.recipeScoped and not NormalizeRecipeIDForLookup(recipeID) then
        return nil
    end

    local recipeNodeSet = GetRecipeNodeSet(catalog, recipeID)
    if NormalizeRecipeIDForLookup(recipeID) and type(catalog.recipeMapping) == "table" and not recipeNodeSet then
        return nil
    end

    local totals = {}
    local hasMulticraftExtraNode = CatalogHasContextStat(
        catalog,
        profileKey,
        recipeNodeSet,
        "additionalitemscraftedwithmulticraft")
    local hasResourcefulnessExtraNode = CatalogHasContextStat(
        catalog,
        profileKey,
        recipeNodeSet,
        "reagentssavedfromresourcefulness")
    for nodeID, rank in pairs(ranks) do
        local node = GetCatalogNode(catalog, nodeID)
        local clampedRank = node and ClampRank(rank, node.maxRank) or ClampNonNegative(rank)
        if node and clampedRank > 0 and NodeAppliesToContext(node, profileKey, recipeNodeSet) then
            for statKey, statValue in pairs(node.stats or {}) do
                AddStatTotal(totals, statKey, statValue, clampedRank)
            end
        end
    end

    local nodeStats = {}
    if totals.multicraft or totals.additionalitemscraftedwithmulticraft then
        nodeStats.multicraft = {
            rating = totals.multicraft,
            extra = totals.additionalitemscraftedwithmulticraft
                and (totals.additionalitemscraftedwithmulticraft / 100)
                or nil,
        }
    end
    if totals.resourcefulness or totals.reagentssavedfromresourcefulness then
        nodeStats.resourcefulness = {
            rating = totals.resourcefulness,
            extra = totals.reagentssavedfromresourcefulness
                and (totals.reagentssavedfromresourcefulness / 100)
                or nil,
        }
    end

    local source = "gam-native-nodes"
    if hasManual then
        source = "gam-manual-nodes"
    elseif not hasCaptured then
        source = "workbook-default"
    elseif state and state.source then
        source = state.source
    end

    return {
        statSource = source,
        nodeHash = BuildNodeHash(ranks),
        nodeRanks = CopyNodeRankList(ranks, catalog),
        nodeStats = next(nodeStats) and nodeStats or nil,
        totals = totals,
        multiExtra = hasMulticraftExtraNode
            and math.max(0, (totals.additionalitemscraftedwithmulticraft or 0) / 100)
            or nil,
        resExtra = hasResourcefulnessExtraNode
            and math.max(0, (totals.reagentssavedfromresourcefulness or 0) / 100)
            or nil,
    }
end

local function ApplySpecializationNodeState(result, profileKey, character, recipeID)
    if type(result) ~= "table" or not IsSpecializationProfile(profileKey) then
        return result
    end

    local summary = SummarizeNodeRanks(profileKey, character, false, recipeID or result.recipeID)
    if not summary then
        return result
    end

    if result.supportsMulticraft and summary.multiExtra ~= nil then
        result.multiExtra = summary.multiExtra
    end
    if result.supportsResourcefulness and summary.resExtra ~= nil then
        result.resExtra = summary.resExtra
    end

    result.statSource = summary.statSource or result.statSource
    result.nodeHash = summary.nodeHash or result.nodeHash
    result.nodeRanks = summary.nodeRanks or result.nodeRanks
    result.nodeStats = summary.nodeStats or result.nodeStats
    return result
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

    -- GAM/native/manual data is the authority. CraftSim imports can populate an
    -- empty cache, but they should not replace newer standalone captures.
    return (not IsCraftSimSnapshot(existing)) and IsCraftSimSnapshot(incoming)
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
local testOpenProfessionNodes = nil
local GetOpenNativeRecipeSnapshot

local function AddNodeCandidate(out, nodeID, rank, maxRank, name)
    local id = tonumber(nodeID)
    if not id then return end
    local n = tonumber(rank)
    if n == nil then return end
    local existing = out[id]
    if existing and (tonumber(existing.rank) or 0) >= n then
        return
    end
    out[id] = {
        nodeID = id,
        rank = n,
        maxRank = tonumber(maxRank) or (existing and existing.maxRank) or nil,
        name = name or (existing and existing.name) or nil,
    }
end

local function ResolveProfessionDefFromOpenName(name)
    local text = tostring(name or ""):lower()
    if text == "" then return nil end
    for _, def in ipairs(PROFESSION_DEFS) do
        for _, alias in ipairs(def.aliases or {}) do
            if text:find(alias, 1, true) then
                return def
            end
        end
    end
    return nil
end

local function GetOpenProfessionDef()
    if C_TradeSkillUI and type(C_TradeSkillUI.GetBaseProfessionInfo) == "function" then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and type(info) == "table" then
            local skillLineID = tonumber(info.professionID or info.skillLineID or info.parentProfessionID)
            local bySkillLine = skillLineID and PROFESSION_BY_SKILL_LINE[skillLineID] or nil
            if bySkillLine then return bySkillLine end
            local byName = ResolveProfessionDefFromOpenName(info.professionName or info.name)
            if byName then return byName end
        end
    end

    local openRecipe = GetOpenNativeRecipeSnapshot()
    if type(openRecipe) == "table" then
        local bySkillLine = PROFESSION_BY_SKILL_LINE[tonumber(openRecipe.parentSkillLineID)]
            or PROFESSION_BY_SKILL_LINE[tonumber(openRecipe.skillLineID)]
        if bySkillLine then return bySkillLine end
        local byName = ResolveProfessionDefFromOpenName(openRecipe.profession)
        if byName then return byName end
    end

    return nil
end

local function OpenProfessionMatches(profession)
    local def = ResolveProfessionDef(profession)
    if not def then
        return false
    end
    local openDef = GetOpenProfessionDef()
    if openDef then
        return openDef.name == def.name
    end
    return nil
end

local function ExtractNodeRanksFromTable(source, out, seen, depth)
    if type(source) ~= "table" or depth > 5 then
        return
    end
    if seen[source] then return end
    seen[source] = true

    local nodeID = source.nodeID or source.ID or source.id or source.traitNodeID
    local rank = source.rank
        or source.currentRank
        or source.activeRank
        or source.ranksPurchased
        or source.purchasedRanks
        or source.numRanksPurchased
    local maxRank = source.maxRank or source.maxRanks or source.maxVisibleRank
    local name = source.name or source.nodeName or source.displayName
    AddNodeCandidate(out, nodeID, rank, maxRank, name)

    for key, value in pairs(source) do
        if type(value) == "table" then
            local keyText = tostring(key):lower()
            if keyText:find("node", 1, true)
                    or keyText:find("rank", 1, true)
                    or keyText:find("trait", 1, true)
                    or keyText == "data"
                    or keyText == "nodes"
                    or tonumber(key) ~= nil then
                ExtractNodeRanksFromTable(value, out, seen, depth + 1)
            end
        end
    end
end

local function GetOpenNativeProfessionNodeRanks(profession)
    if testOpenProfessionNodes ~= nil then
        return testOpenProfessionNodes
    end
    if not ResolveProfessionDef(profession) then
        return nil
    end
    if OpenProfessionMatches(profession) == false then
        return nil
    end

    local out = {}
    local roots = {
        ProfessionsFrame and ProfessionsFrame.SpecPage,
        ProfessionsFrame and ProfessionsFrame.CraftingPage,
        ProfessionsFrame and ProfessionsFrame.OrdersPage,
    }
    for _, root in ipairs(roots) do
        if type(root) == "table" then
            pcall(ExtractNodeRanksFromTable, root, out, {}, 0)
        end
    end

    return next(out) and out or nil
end

GetOpenNativeRecipeSnapshot = function()
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
            return ApplySpecializationNodeState(
                ApplySnapshotToDefaults(manualDefaults, cached, source),
                profileKey,
                character), source
        end
        if type(manual) == "table" then
            return ApplySpecializationNodeState(manualDefaults, profileKey, character), "manual"
        end
    end
    return ApplySpecializationNodeState(defaults, profileKey, character), "workbook-default"
end

function Stats.ResolveForStrat(strat, opts)
    opts = opts or ((GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {})
    local profileKey = GetProfileKeyForStrat(strat)
    local defaults = GetProfileDefaults(profileKey, opts)
    local recipeID = NormalizeRecipeID(strat and strat.recipeID)
    local character = EnsureCache()
    local manualDefaults = defaults
    local hasManualProfile = false

    if type(character) == "table" then
        local manual = profileKey and character.manualProfiles and character.manualProfiles[profileKey]
        if type(manual) == "table" then
            hasManualProfile = true
            manualDefaults = ApplySnapshotToDefaults(defaults, manual, "manual")
        end
    end

    local recipeSnapshot = GetCachedRecipeSnapshot(character, recipeID, profileKey)
    local profileSnapshot = GetCachedProfileSnapshot(character, profileKey)

    local openSnapshot = GetOpenNativeRecipeSnapshot()
    local openMatchKind = GetSnapshotMatchKind(openSnapshot, strat, profileKey)
    if openMatchKind == "recipe" then
        Stats.SaveSnapshot(openSnapshot)
        return ApplySpecializationNodeState(
            ApplySnapshotToDefaults(manualDefaults, openSnapshot, "native-open"),
            profileKey,
            character,
            recipeID)
    end

    if recipeSnapshot and not IsCraftSimSnapshot(recipeSnapshot) then
        return ApplySpecializationNodeState(
            ApplySnapshotToDefaults(manualDefaults, recipeSnapshot,
                SourceForCachedSnapshot(recipeSnapshot, "gam-cache-recipe")),
            profileKey,
            character,
            recipeID)
    end

    if openMatchKind == "profile" then
        Stats.SaveSnapshot(openSnapshot)
        return ApplySpecializationNodeState(
            ApplySnapshotToDefaults(manualDefaults, openSnapshot, "native-open-profile"),
            profileKey,
            character,
            recipeID)
    end

    if IsCraftSimSnapshot(recipeSnapshot) then
        return ApplySnapshotToDefaults(manualDefaults, recipeSnapshot,
            SourceForCachedSnapshot(recipeSnapshot, "gam-cache-recipe"))
    end

    if profileSnapshot and not IsCraftSimSnapshot(profileSnapshot) then
        return ApplySpecializationNodeState(
            ApplySnapshotToDefaults(manualDefaults, profileSnapshot,
                SourceForCachedSnapshot(profileSnapshot, "gam-cache-profile")),
            profileKey,
            character,
            recipeID)
    end

    local withNodes = ApplySpecializationNodeState(manualDefaults, profileKey, character, recipeID)
    if withNodes ~= manualDefaults or (withNodes and withNodes.nodeHash) then
        return withNodes
    end

    if IsCraftSimSnapshot(profileSnapshot) then
        return ApplySnapshotToDefaults(manualDefaults, profileSnapshot,
            SourceForCachedSnapshot(profileSnapshot, "gam-cache-profile"))
    end

    if hasManualProfile then
        return manualDefaults
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

function Stats.CaptureProfessionNodes(profession, nodes, source, meta)
    local character = EnsureCache()
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
        if type(value) == "table" then
            nodeID = value.nodeID or key
            rank = value.rank or value.currentRank or value.activeRank or value.ranksPurchased
            maxRank = value.maxRank or value.maxRanks
            name = value.name or value.nodeName
        else
            nodeID = key
            rank = value
        end

        local id = tonumber(nodeID)
        local node = id and GetCatalogNode(catalog, id) or nil
        if id and tonumber(rank) ~= nil then
            normalized[id] = {
                nodeID = id,
                rank = ClampRank(rank, (node and node.maxRank) or maxRank),
                maxRank = (node and node.maxRank) or tonumber(maxRank),
                name = (node and node.name) or name,
            }
        end
    end

    if not next(normalized) then
        return nil, "empty-nodes"
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

    return CopySerializableTable(state), nil
end

function Stats.CaptureOpenProfessionNodes(profession)
    if not profession then
        local def = GetOpenProfessionDef()
        profession = def and def.name or nil
    end
    profession = profession or "Engineering"
    local nodes = GetOpenNativeProfessionNodeRanks(profession)
    if not nodes then
        return nil, "no-open-profession-nodes"
    end
    return Stats.CaptureProfessionNodes(profession, nodes, "gam-native-nodes", {
        source = "Blizzard_Professions",
    })
end

function Stats.SetManualNodeRank(profession, nodeID, rank, season)
    local character = EnsureCache()
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
    local character = EnsureCache()
    local state = character and EnsureProfessionNodeState(character, profession, season or SEASON_KEY)
    if not state then
        return false, "unsupported-profession"
    end
    state.manualOverrides = {}
    state.manualUpdatedAt = GetCurrentTimestamp()
    return true, nil
end

function Stats.ResetProfessionNodesToDefaults(profession, season)
    local character = EnsureCache()
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
        local rank = type(nodeState) == "table" and nodeState.rank or nodeState
        captured[tonumber(nodeID) or nodeID] = rank
    end

    local groups = {}
    for _, group in ipairs(catalog.uiGroups or {}) do
        local rows = {}
        for _, nodeID in ipairs(group.nodeIDs or {}) do
            local node = GetCatalogNode(catalog, nodeID)
            if node then
                local manualRank = state.manualOverrides and state.manualOverrides[nodeID]
                local capturedRank = captured[nodeID]
                local effectiveRank = manualRank
                if effectiveRank == nil then
                    effectiveRank = capturedRank
                end
                if effectiveRank == nil then
                    effectiveRank = node.defaultRank or 0
                end
                rows[#rows + 1] = {
                    nodeID = nodeID,
                    name = node.name,
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
        groups[#groups + 1] = {
            label = group.label,
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
    nodeCaptureFrame:SetScript("OnEvent", function()
        if Stats.CaptureOpenProfessionNodes then
            pcall(Stats.CaptureOpenProfessionNodes)
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
    ["gam-native-nodes"] = true,
    ["gam-manual-nodes"] = true,
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
    local originalProfessionNodes = testOpenProfessionNodes
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
        local craftSimPreservedOK, craftSimPreservedStatus = Stats.SaveSnapshot({
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
        })
        assert(craftSimPreservedOK and craftSimPreservedStatus == "preserved-existing",
            "CraftSim import should not replace existing native/GAM snapshots")
        local preserved = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
            recipeID = 1002,
        }, {})
        assert(preserved.statSource == "gam-cache-recipe" and preserved.resPercent == 55,
            "native/GAM snapshot should outrank CraftSim imports")

        assert(Stats.SaveSnapshot({
            source = "craftsim-imported",
            recipeID = 1005,
            recipeName = "CraftSim Only Milling",
            profession = "Inscription",
            profileKey = "insc_milling",
            resPercent = 5,
            resExtra = 0.55,
            supportsResourcefulness = true,
            nodeHash = "111:2",
            nodeStats = {
                resourcefulness = { percent = 3, extra = 0.55 },
            },
        }))
        local craftSimOnly = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
            recipeID = 1005,
        }, {})
        assert(craftSimOnly.statSource == "craftsim-imported"
                and craftSimOnly.resPercent == 5
                and craftSimOnly.nodeHash == "111:2",
            "CraftSim import should populate empty stat cache")

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

        local nodeCapture = Stats.CaptureProfessionNodes("Engineering", {
            [106726] = 1,
            [106724] = 1,
            [106722] = 1,
            [106720] = 1,
            [106733] = 1,
            [106731] = 1,
            [106729] = 1,
            [106727] = 1,
        }, "gam-native-nodes")
        assert(nodeCapture and nodeCapture.nodeHash, "engineering node capture failed")
        local engineering = Stats.ResolveForStrat({
            profession = "Engineering",
            formulaProfile = "engineering_craft",
        }, {})
        assert(engineering.statSource == "gam-native-nodes"
                and math.abs((engineering.resExtra or 0) - 0.45) < 0.0001
                and math.abs((engineering.multiExtra or 0) - 1.0) < 0.0001,
            "engineering captured node extras failed")

        assert(Stats.SetManualNodeRank("Engineering", 106727, 0),
            "engineering manual node rank failed")
        local manualNodes = Stats.ResolveForStrat({
            profession = "Engineering",
            formulaProfile = "engineering_craft",
        }, {})
        assert(manualNodes.statSource == "gam-manual-nodes"
                and math.abs((manualNodes.multiExtra or 0) - 0.75) < 0.0001,
            "engineering manual node override failed")

        assert(Stats.ResetProfessionNodesToDefaults("Engineering"),
            "engineering reset node defaults failed")
        local defaultNodes = Stats.ResolveForStrat({
            profession = "Engineering",
            formulaProfile = "engineering_craft",
        }, {})
        assert(defaultNodes.statSource == "gam-manual-nodes"
                and math.abs((defaultNodes.multiExtra or 0) - 1.0) < 0.0001
                and math.abs((defaultNodes.resExtra or 0) - 0.45) < 0.0001,
            "engineering default node ranks failed")

        local rows = Stats.GetProfessionNodeRows("Engineering")
        assert(rows and rows.groups and rows.groups[1] and rows.groups[1].rows[1],
            "engineering node settings rows failed")

        assert(Stats.ResetProfessionNodesToDefaults("Alchemy"),
            "alchemy reset node defaults failed")
        local alchemyCauldron = Stats.ResolveForStrat({
            profession = "Alchemy",
            formulaProfile = "alchemy",
            recipeID = 1230857,
        }, {})
        assert(alchemyCauldron.statSource == "gam-manual-nodes"
                and math.abs((alchemyCauldron.multiExtra or 0) - 0.4) < 0.0001,
            "alchemy recipe-scoped node extras failed")
        local alchemyUnscoped = Stats.ResolveForStrat({
            profession = "Alchemy",
            formulaProfile = "alchemy",
        }, {})
        assert(math.abs((alchemyUnscoped.multiExtra or 0) - 0.2) < 0.0001,
            "alchemy unscoped profile default failed")

        assert(Stats.ResetProfessionNodesToDefaults("Tailoring"),
            "tailoring reset node defaults failed")
        local tailoring = Stats.ResolveForStrat({
            profession = "Tailoring",
            formulaProfile = "tailoring",
            recipeID = 1227926,
        }, {})
        assert(tailoring.statSource == "gam-manual-nodes"
                and math.abs((tailoring.multiExtra or 0) - 0.4) < 0.0001
                and math.abs((tailoring.resExtra or 0) - 0.5) < 0.0001,
            "tailoring node defaults failed")

        assert(Stats.ResetProfessionNodesToDefaults("Blacksmithing"),
            "blacksmithing reset node defaults failed")
        local blacksmithing = Stats.ResolveForStrat({
            profession = "Blacksmithing",
            formulaProfile = "blacksmithing",
            recipeID = 1229427,
        }, {})
        assert(blacksmithing.statSource == "gam-manual-nodes"
                and math.abs((blacksmithing.multiExtra or 0) - 0.12) < 0.0001,
            "blacksmithing rating-only catalog should preserve workbook node multiplier")
    end)
    testOpenSnapshot = originalOpen
    testOpenProfessionNodes = originalProfessionNodes
    GAM.db = originalDB
    GoldAdvisorMidnightDB = originalSavedDB
    return ok, err
end
