-- GoldAdvisorMidnight/CraftingStatsV2.lua
-- GAM-owned V2 crafting stat resolver. CraftSim may import snapshots here, but
-- pricing code should not depend on CraftSim directly.
-- Module: GAM.CraftingStatsV2

local ADDON_NAME, GAM = ...
local Stats = {}
GAM.CraftingStatsV2 = Stats
local NodeDisplay = GAM.ProfessionNodeDisplay

local CACHE_VERSION = 2
local SEASON_KEY = "midnight"
local RECIPE_SNAPSHOT_STALE_SECONDS = 24 * 60 * 60
local pendingRecipeRefreshes = {}
local PROFESSION_DEFS = (GAM.C and GAM.C.PROFESSION_REGISTRY) or {}
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

local function GetCrafterIdentity()
    local name = type(UnitName) == "function" and UnitName("player") or nil
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil
    name = name or "Unknown"
    realm = realm or "Unknown"
    return name .. "-" .. realm, name, realm
end

local function EnsureCharacterCacheShape(character, uid, name, realm)
    if type(character) ~= "table" then return nil end
    character.recipes = character.recipes or {}
    character.recipeValidatedAt = character.recipeValidatedAt or {}
    character.profiles = character.profiles or {}
    character.manualProfiles = character.manualProfiles or {}
    character.nodeState = character.nodeState or {}
    character.gearPresets = character.gearPresets or {}
    if uid then character.uid = uid end
    if name then character.name = name end
    if realm then character.realm = realm end
    return character
end

local function EnsureCache()
    local db = GAM.db or GoldAdvisorMidnightDB
    if type(db) ~= "table" then
        return nil
    end

    db.v2StatCache = db.v2StatCache or {}
    local cache = db.v2StatCache
    cache.version = CACHE_VERSION
    cache.revision = tonumber(cache.revision) or 0
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

    local uid, name, realm = GetCrafterIdentity()
    cache.characters[uid] = cache.characters[uid] or {}
    local character = EnsureCharacterCacheShape(cache.characters[uid], uid, name, realm)
    return character, uid, cache
end

local runtimeRevision = 0

local function TouchRevision(character, cache)
    runtimeRevision = runtimeRevision + 1
    if type(cache) ~= "table" then
        local ignoredCharacter, ignoredUID
        ignoredCharacter, ignoredUID, cache = EnsureCache()
    end
    if type(cache) == "table" then
        cache.revision = (tonumber(cache.revision) or 0) + 1
    end
    if type(character) == "table" then
        character.revision = (tonumber(character.revision) or 0) + 1
    end
end

function Stats.GetRevision()
    local _, _, cache = EnsureCache()
    if type(cache) == "table" then
        return tonumber(cache.revision) or 0
    end
    return runtimeRevision
end

local MATERIAL_SNAPSHOT_FIELDS = {
    "source",
    "cachedSource",
    "profileKey",
    "recipeID",
    "recipeName",
    "profession",
    "statQuality",
    "multiPercent",
    "resPercent",
    "multiExtra",
    "resExtra",
    "supportsMulticraft",
    "supportsResourcefulness",
    "mcConstant",
    "resourcefulnessSaveBase",
    "nodeHash",
}

local function ScalarEqual(a, b)
    local na = tonumber(a)
    local nb = tonumber(b)
    if na ~= nil or nb ~= nil then
        return na ~= nil and nb ~= nil and math.abs(na - nb) < 0.000001
    end
    return a == b
end

local function NumericTableEqual(a, b)
    if a == nil and b == nil then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    for key, value in pairs(a) do
        if not ScalarEqual(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

local function SnapshotMateriallyEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    for _, field in ipairs(MATERIAL_SNAPSHOT_FIELDS) do
        if not ScalarEqual(a[field], b[field]) then
            return false
        end
    end
    return NumericTableEqual(a.multicraftConstants, b.multicraftConstants)
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

local HIDDEN_NODE_BONUS_STATS = {
    additionalitemscraftedwithmulticraft = "multicraft",
    reagentssavedfromresourcefulness = "resourcefulness",
}

local function AddNodeBonusContribution(details, node, rank, statKey, statValue)
    local bucketKey = HIDDEN_NODE_BONUS_STATS[statKey]
    local bucket = bucketKey and details[bucketKey] or nil
    local value = tonumber(statValue)
    if not bucket or not value then
        return
    end

    local extra = math.max(0, value * (tonumber(rank) or 0) / 100)
    if extra <= 0 then
        return
    end

    bucket.extra = (bucket.extra or 0) + extra
    bucket.nodes[#bucket.nodes + 1] = {
        nodeID = tonumber(node.nodeID) or node.nodeID,
        name = node.name,
        rank = tonumber(rank) or 0,
        extra = extra,
    }
end

local function SortNodeBonusContributors(details)
    for _, bucketKey in ipairs({ "multicraft", "resourcefulness" }) do
        local bucket = details and details[bucketKey]
        if bucket and type(bucket.nodes) == "table" then
            table.sort(bucket.nodes, function(a, b)
                local aID = tonumber(a.nodeID)
                local bID = tonumber(b.nodeID)
                if aID and bID then
                    return aID < bID
                end
                return tostring(a.nodeID) < tostring(b.nodeID)
            end)
        end
    end
end

local function BuildUnavailableNodeBonusDetails(profileKey, recipeID)
    local profession = GetProfessionForProfile(profileKey)
    local catalog = profession and GetSpecializationCatalog(profession, SEASON_KEY) or nil
    if not catalog then
        return nil
    end

    local normalizedRecipeID = NormalizeRecipeIDForLookup(recipeID)
    local status = "not-captured"
    if catalog.recipeScoped and not normalizedRecipeID then
        status = "recipe-unavailable"
    elseif normalizedRecipeID
            and type(catalog.recipeMapping) == "table"
            and not GetRecipeNodeSet(catalog, recipeID) then
        status = "mapping-unavailable"
    end

    return {
        status = status,
        source = "workbook-default",
        profession = profession,
        recipeID = normalizedRecipeID and tonumber(normalizedRecipeID) or nil,
    }
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
    local nodeBonusDetails = {
        status = "resolved",
        profession = profession,
        recipeID = tonumber(NormalizeRecipeIDForLookup(recipeID)),
        multicraft = hasMulticraftExtraNode and { extra = 0, nodes = {} } or nil,
        resourcefulness = hasResourcefulnessExtraNode and { extra = 0, nodes = {} } or nil,
    }
    for nodeID, rank in pairs(ranks) do
        local node = GetCatalogNode(catalog, nodeID)
        local clampedRank = node and ClampRank(rank, node.maxRank) or ClampNonNegative(rank)
        if node and clampedRank > 0 and NodeAppliesToContext(node, profileKey, recipeNodeSet) then
            for statKey, statValue in pairs(node.stats or {}) do
                AddStatTotal(totals, statKey, statValue, clampedRank)
                AddNodeBonusContribution(
                    nodeBonusDetails, node, clampedRank, statKey, statValue)
            end
        end
    end
    SortNodeBonusContributors(nodeBonusDetails)

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
    nodeBonusDetails.source = source

    return {
        statSource = source,
        nodeHash = BuildNodeHash(ranks),
        nodeRanks = CopyNodeRankList(ranks, catalog),
        nodeStats = next(nodeStats) and nodeStats or nil,
        totals = totals,
        nodeBonusDetails = nodeBonusDetails,
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
        result.nodeBonusDetails = BuildUnavailableNodeBonusDetails(
            profileKey, recipeID or result.recipeID)
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
    local nodeBonusDetails = summary.nodeBonusDetails
    if nodeBonusDetails then
        if not result.supportsMulticraft then
            nodeBonusDetails.multicraft = nil
        end
        if not result.supportsResourcefulness then
            nodeBonusDetails.resourcefulness = nil
        end
        result.nodeBonusDetails = nodeBonusDetails
    end
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

local GEAR_MODES = {
    auto = true,
    multicraft = true,
    resourcefulness = true,
}

local function NormalizeGearMode(mode)
    mode = tostring(mode or "auto"):lower()
    return GEAR_MODES[mode] and mode or "auto"
end

local function GetGearPreset(character, recipeID, profileKey, mode)
    mode = NormalizeGearMode(mode)
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

local function FindCachedGearPresetCrafter(cache, currentUID, recipeID, profileKey, mode)
    if not recipeID or type(cache) ~= "table" or type(cache.characters) ~= "table" then
        return nil
    end
    local bestCharacter, bestUID, bestSnapshot, bestCapturedAt
    for uid, character in pairs(cache.characters) do
        if uid ~= currentUID and type(character) == "table" then
            local snapshot = GetGearPreset(character, recipeID, profileKey, mode)
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
local testPlayerProfessionSet = nil
local GetOpenNativeRecipeSnapshot

local function AddNodeCandidate(out, nodeID, rank, maxRank, name, description, nameSource)
    local id = tonumber(nodeID)
    if not id then return end
    local n = tonumber(rank)
    if n == nil then return end
    local existing = out[id]
    if existing and (tonumber(existing.rank) or 0) >= n then
        existing.name = name or existing.name
        existing.description = description or existing.description
        existing.nameSource = nameSource or existing.nameSource
        return
    end
    out[id] = {
        nodeID = id,
        rank = n,
        maxRank = tonumber(maxRank) or (existing and existing.maxRank) or nil,
        name = name or (existing and existing.name) or nil,
        description = description or (existing and existing.description) or nil,
        nameSource = nameSource or (existing and existing.nameSource) or nil,
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

local function ResolveProfessionDefFromInfo(info)
    if type(info) ~= "table" then return nil end

    -- professionID is the selected expansion skill line (Midnight, in this
    -- case); parentProfessionID is the stable base profession ID in our shared
    -- registry. Prefer the parent so this keeps working across expansions.
    local stableSkillLineID = tonumber(info.parentProfessionID
        or info.baseProfessionID
        or info.skillLineID
        or info.professionID)
    local bySkillLine = stableSkillLineID and PROFESSION_BY_SKILL_LINE[stableSkillLineID] or nil
    if bySkillLine then return bySkillLine end

    return ResolveProfessionDefFromOpenName(
        info.professionName or info.parentProfessionName or info.name)
end

local function GetOpenProfessionContext()
    local candidates = {}
    if type(ProfessionsFrame) == "table" then
        candidates[#candidates + 1] = ProfessionsFrame.professionInfo
        if type(ProfessionsFrame.GetProfessionInfo) == "function" then
            local ok, info = pcall(ProfessionsFrame.GetProfessionInfo, ProfessionsFrame)
            if ok then candidates[#candidates + 1] = info end
        end
    end

    if C_TradeSkillUI and type(C_TradeSkillUI.GetBaseProfessionInfo) == "function" then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok then candidates[#candidates + 1] = info end
    end

    for _, info in ipairs(candidates) do
        local def = ResolveProfessionDefFromInfo(info)
        if def then
            return def, tonumber(info.professionID or info.skillLineID), info
        end
    end

    local openRecipe = GetOpenNativeRecipeSnapshot()
    if type(openRecipe) == "table" then
        local bySkillLine = PROFESSION_BY_SKILL_LINE[tonumber(openRecipe.parentSkillLineID)]
            or PROFESSION_BY_SKILL_LINE[tonumber(openRecipe.skillLineID)]
        if bySkillLine then
            return bySkillLine, tonumber(openRecipe.skillLineID), openRecipe
        end
        local byName = ResolveProfessionDefFromOpenName(openRecipe.profession)
        if byName then
            return byName, tonumber(openRecipe.skillLineID), openRecipe
        end
    end

    return nil
end

local function GetOpenProfessionDef()
    return GetOpenProfessionContext()
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
    local description = source.description or source.nodeDescription
    AddNodeCandidate(out, nodeID, rank, maxRank, name, description, name and "blizzard-ui" or nil)

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

local function AddUniqueNumber(out, seen, value)
    local n = tonumber(value)
    if n and n > 0 and not seen[n] then
        seen[n] = true
        out[#out + 1] = n
    end
end

local function GetProfessionTraitContext(profession)
    if not (C_ProfSpecs and C_Traits
            and type(C_ProfSpecs.GetConfigIDForSkillLine) == "function") then
        return nil
    end

    local def = ResolveProfessionDef(profession)
    local openDef, openSkillLineID = GetOpenProfessionContext()
    if not def then def = openDef end
    if not def or (openDef and openDef.name ~= def.name) then
        return nil
    end

    -- Blizzard specializes the selected expansion skill line, not the stable
    -- base profession ID. GetDefaultSpecSkillLine is a useful fallback during
    -- the first frames of profession-window initialization.
    local skillLineCandidates, seenSkillLines = {}, {}
    AddUniqueNumber(skillLineCandidates, seenSkillLines, openSkillLineID)
    if type(C_ProfSpecs.GetDefaultSpecSkillLine) == "function" then
        local ok, skillLineID = pcall(C_ProfSpecs.GetDefaultSpecSkillLine)
        if ok then AddUniqueNumber(skillLineCandidates, seenSkillLines, skillLineID) end
    end
    AddUniqueNumber(skillLineCandidates, seenSkillLines, def.skillLineID)

    for _, skillLineID in ipairs(skillLineCandidates) do
        local ok, configID = pcall(C_ProfSpecs.GetConfigIDForSkillLine, skillLineID)
        configID = ok and tonumber(configID) or nil
        if configID and configID > 0 then
            return {
                profession = def,
                skillLineID = skillLineID,
                configID = configID,
            }
        end
    end
    return nil
end

local function CollectProfessionTraitNodeIDs(context)
    local nodeIDs, seenNodeIDs = {}, {}
    local tabIDs = {}
    if type(C_ProfSpecs.GetSpecTabIDsForSkillLine) == "function" then
        local ok, result = pcall(C_ProfSpecs.GetSpecTabIDsForSkillLine, context.skillLineID)
        if ok and type(result) == "table" then tabIDs = result end
    end

    local function addNodeID(nodeID)
        AddUniqueNumber(nodeIDs, seenNodeIDs, nodeID)
    end

    -- GetTreeNodes is the direct public trait API and avoids depending on any
    -- profession-frame widget layout.
    if type(C_Traits.GetTreeNodes) == "function" then
        for _, treeID in ipairs(tabIDs) do
            local ok, result = pcall(C_Traits.GetTreeNodes, treeID)
            if ok and type(result) == "table" then
                for _, nodeID in ipairs(result) do addNodeID(nodeID) end
            end
        end
    end

    -- Some client builds do not expose profession paths through GetTreeNodes.
    -- Walk the same root/child graph Blizzard's 12.1 profession UI uses.
    local function walkPath(pathID)
        local id = tonumber(pathID)
        if not id or seenNodeIDs[id] then return end
        addNodeID(id)
        if type(C_ProfSpecs.GetChildrenForPath) == "function" then
            local ok, children = pcall(C_ProfSpecs.GetChildrenForPath, id)
            if ok and type(children) == "table" then
                for _, childID in ipairs(children) do walkPath(childID) end
            end
        end
    end

    for _, treeID in ipairs(tabIDs) do
        local rootPathID = nil
        if type(C_ProfSpecs.GetRootPathForTab) == "function" then
            local ok, result = pcall(C_ProfSpecs.GetRootPathForTab, treeID)
            if ok then rootPathID = result end
        end
        if not rootPathID and type(C_ProfSpecs.GetTabInfo) == "function" then
            local ok, tabInfo = pcall(C_ProfSpecs.GetTabInfo, treeID)
            if ok and type(tabInfo) == "table" then
                rootPathID = tabInfo.rootNodeID
            end
        end
        walkPath(rootPathID)
    end

    return nodeIDs, #tabIDs
end

local function GetProfessionNodeRanksFromTraits(profession)
    local context = GetProfessionTraitContext(profession)
    if not context or type(C_Traits.GetNodeInfo) ~= "function" then
        return nil
    end

    local nodeIDs, treeCount = CollectProfessionTraitNodeIDs(context)
    local out = {}
    for _, nodeID in ipairs(nodeIDs) do
        local ok, nodeInfo = pcall(C_Traits.GetNodeInfo, context.configID, nodeID)
        if ok and type(nodeInfo) == "table" then
            local displayInfo = NodeDisplay and NodeDisplay.ResolveLiveNodeInfo
                and NodeDisplay.ResolveLiveNodeInfo(context.configID, nodeID, nodeInfo)
            -- currentRank includes granted ranks, which ranksPurchased omits.
            -- On ordinary profession-frame opening there are no staged edits,
            -- so it represents the learned rank the formula must use.
            AddNodeCandidate(out,
                nodeInfo.ID or nodeID,
                nodeInfo.currentRank or nodeInfo.activeRank or nodeInfo.ranksPurchased,
                nodeInfo.maxRanks or nodeInfo.totalMaxRanks,
                displayInfo and displayInfo.name,
                displayInfo and displayInfo.description,
                displayInfo and displayInfo.source)
        end
    end

    if not next(out) then return nil end
    return out, {
        source = "Blizzard_C_ProfSpecs+C_Traits",
        captureMethod = "traits-api",
        skillLineID = context.skillLineID,
        configID = context.configID,
        treeCount = treeCount,
        nodeCount = #nodeIDs,
    }
end

local function GetOpenNativeProfessionNodeRanks(profession)
    if testOpenProfessionNodes ~= nil then
        return testOpenProfessionNodes, { captureMethod = "test" }
    end
    if not ResolveProfessionDef(profession) then
        return nil
    end
    if OpenProfessionMatches(profession) == false then
        return nil
    end

    local apiNodes, apiMeta = GetProfessionNodeRanksFromTraits(profession)
    if apiNodes then
        return apiNodes, apiMeta
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

    return next(out) and out or nil, {
        source = "Blizzard_Professions",
        captureMethod = "frame-fallback",
    }
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
    local stratID = type(strat) == "table" and strat.id or nil
    local patch = stratID and GAM.GetPatchDB and GAM:GetPatchDB(patchTag or GAM.C.DEFAULT_PATCH) or nil
    return NormalizeGearMode(patch and patch.gearModes and patch.gearModes[stratID])
end

function Stats.SetGearModeForStrat(strat, mode, patchTag)
    local stratID = type(strat) == "table" and strat.id or nil
    if not stratID then return false, "missing-strategy" end
    local patch = GAM.GetPatchDB and GAM:GetPatchDB(patchTag or GAM.C.DEFAULT_PATCH) or nil
    if not patch then return false, "no-db" end
    patch.gearModes = patch.gearModes or {}
    mode = NormalizeGearMode(mode)
    if patch.gearModes[stratID] ~= mode then
        patch.gearModes[stratID] = mode
        local character, _, cache = EnsureCache()
        TouchRevision(character, cache)
    end
    return true, mode
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

function Stats.ResolveForStrat(strat, opts)
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
        Stats.SaveSnapshot(openSnapshot)
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
        Stats.SaveSnapshot(openSnapshot)
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

function Stats.RunSmokeChecks()
    local originalDB = GAM.db
    local originalSavedDB = GoldAdvisorMidnightDB
    local originalOpen = testOpenSnapshot
    local originalProfessionNodes = testOpenProfessionNodes
    local originalPlayerProfessionSet = testPlayerProfessionSet
    local originalProfessionsFrame = ProfessionsFrame
    local originalCProfSpecs = C_ProfSpecs
    local originalCTraits = C_Traits
    local originalCTradeSkillUI = C_TradeSkillUI
    local originalCTimer = C_Timer
    local ok, err = pcall(function()
        GAM.db = {
            options = {},
            v2StatCache = {
                version = CACHE_VERSION,
                characters = {},
            },
        }
        GoldAdvisorMidnightDB = GAM.db
        testPlayerProfessionSet = { Alchemy = true, Inscription = true }

        local openedSkillLine
        local openedRecipe
        C_TradeSkillUI = {
            OpenTradeSkill = function(skillLineID)
                openedSkillLine = skillLineID
            end,
            OpenRecipe = function(recipeID)
                openedRecipe = recipeID
            end,
        }
        C_Timer = nil
        testOpenSnapshot = {
            source = "native-open",
            recipeID = 1289744,
            recipeName = "Concentrated Silvermoon Health Potion",
            profession = "Alchemy",
            profileKey = "alchemy",
            multiPercent = 20,
            resPercent = 10,
            supportsMulticraft = true,
            supportsResourcefulness = true,
        }
        local refreshedRecipe
        local opened, openReason = Stats.OpenRecipeForStrat({
            profession = "Alchemy",
            formulaProfile = "alchemy",
            recipeID = 1289744,
        }, function(recipeID)
            refreshedRecipe = recipeID
        end)
        assert(opened and openReason == nil
                and openedSkillLine == 171
                and openedRecipe == 1289744
                and refreshedRecipe == 1289744,
            "selected recipe open/refresh failed")

        -- OpenRecipe has no success return. A non-throwing call must not capture
        -- or refresh while Blizzard is still displaying a different recipe.
        testOpenSnapshot = {
            source = "native-open",
            recipeID = 1230049,
            recipeName = "Thalassian Missive of Ingenuity",
            profession = "Inscription",
            profileKey = "insc_ink",
            resPercent = 10,
            supportsResourcefulness = true,
        }
        refreshedRecipe = nil
        local mismatchOpened, mismatchReason = Stats.OpenRecipeForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1230048,
        }, function(recipeID)
            refreshedRecipe = recipeID
        end)
        assert(not mismatchOpened
                and mismatchReason == "open-recipe-mismatch:1230049"
                and refreshedRecipe == nil,
            "mismatched visible recipe was treated as a successful refresh")

        local retries = {}
        local refreshCount = 0
        C_Timer = {
            After = function(delay, callback)
                retries[#retries + 1] = { delay = delay, callback = callback }
            end,
        }
        local retryOpened, retryReason = Stats.OpenRecipeForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1230048,
        }, function(recipeID)
            refreshedRecipe = recipeID
            refreshCount = refreshCount + 1
        end)
        assert(retryOpened and retryReason == nil and #retries == 3
                and refreshedRecipe == nil,
            "recipe mismatch retries were not scheduled")
        testOpenSnapshot.recipeID = 1230048
        testOpenSnapshot.recipeName = "Thalassian Missive of Resourcefulness"
        retries[1].callback()
        retries[2].callback()
        retries[3].callback()
        assert(refreshedRecipe == 1230048 and refreshCount == 1,
            "verified recipe retry did not refresh exactly once")

        -- Multiple hardware clicks while Blizzard is still switching recipes
        -- must share one bounded refresh attempt. On the final retry, the
        -- complete profession recipe list gives a precise unavailable reason.
        testOpenSnapshot.recipeID = 1269575
        testOpenSnapshot.recipeName = "Milling"
        C_TradeSkillUI.GetAllRecipeIDs = function()
            return { 1269575 }
        end
        retries = {}
        local unavailableReason
        local unavailableOpened = Stats.OpenRecipeForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1303144,
        }, nil, function(reason)
            unavailableReason = reason
        end)
        local duplicateOpened, duplicateReason = Stats.OpenRecipeForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1303144,
        })
        assert(unavailableOpened and duplicateOpened
                and duplicateReason == "open-pending"
                and #retries == 3,
            "duplicate recipe refresh queued another retry set")
        retries[1].callback()
        retries[2].callback()
        retries[3].callback()
        assert(unavailableReason == "recipe-not-in-current-profession",
            "missing profession recipe did not return its precise failure reason")
        C_TradeSkillUI.GetAllRecipeIDs = nil
        C_Timer = nil
        testOpenSnapshot = nil

        local cooking = Stats.GetProfile("cooking")
        assert(cooking and cooking.profileKey == "cooking",
            "Cooking profile is missing from the shared profession registry")

        local strat = {
            profession = "Inscription",
            formulaProfile = "insc_ink",
            statProfileKey = "insc_ink",
            recipeID = 1001,
        }
        local base = Stats.ResolveForStrat(strat, {})
        assert(base and base.statSource == "workbook-default", "default profile stat source failed")

        testOpenSnapshot = {
            source = "native-open",
            recipeID = 1001,
            recipeName = "Munsell Ink",
            profession = "Inscription",
            profileKey = "insc_ink",
            multiPercent = 35,
            resPercent = 10,
            supportsMulticraft = true,
            supportsResourcefulness = true,
        }
        local mcPreset, mcPresetErr = Stats.CaptureOpenRecipeAsGearPreset("multicraft")
        assert(mcPreset and not mcPresetErr, "Multicraft gear preset capture failed")
        testOpenSnapshot.multiPercent = 15
        testOpenSnapshot.resPercent = 40
        local resPreset, resPresetErr = Stats.CaptureOpenRecipeAsGearPreset("resourcefulness")
        assert(resPreset and not resPresetErr, "Resourcefulness gear preset capture failed")
        testOpenSnapshot = nil

        local gearAvailable = Stats.GetAvailableGearPresetModes(strat)
        assert(gearAvailable.multicraft and gearAvailable.resourcefulness,
            "exact recipe gear preset availability failed")
        local forcedMC = Stats.ResolveForStrat(strat, { _gamGearModeOverride = "multicraft" })
        local forcedRes = Stats.ResolveForStrat(strat, { _gamGearModeOverride = "resourcefulness" })
        assert(forcedMC.statSource == "gear-preset-multicraft"
                and forcedMC.multiPercent == 35
                and forcedMC.resPercent == 10,
            "Multicraft gear preset resolution failed")
        assert(forcedRes.statSource == "gear-preset-resourcefulness"
                and forcedRes.multiPercent == 15
                and forcedRes.resPercent == 40,
            "Resourcefulness gear preset resolution failed")

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

        local sameProfileDifferentRecipe = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            statProfileKey = "insc_ink",
            recipeID = 1006,
        }, {})
        assert(sameProfileDifferentRecipe.statSource == "workbook-default"
                and sameProfileDifferentRecipe.resPercent ~= 12.5,
            "recipe snapshot leaked into another strategy in the same profile")

        GAM.db.v2StatCache.characters["AltCrafter-TestRealm"] = {
            uid = "AltCrafter-TestRealm",
            name = "AltCrafter",
            realm = "TestRealm",
            recipes = {
                ["1006"] = {
                    source = "native-open",
                    recipeID = 1006,
                    recipeName = "Cross-Character Ink",
                    profession = "Inscription",
                    profileKey = "insc_ink",
                    resPercent = 44,
                    supportsMulticraft = true,
                    supportsResourcefulness = true,
                    capturedAt = GetCurrentTimestamp(),
                },
            },
            recipeValidatedAt = { ["1006"] = GetCurrentTimestamp() },
            profiles = {},
            manualProfiles = {},
            nodeState = {},
        }
        local cachedCrafter = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1006,
        }, {})
        assert(cachedCrafter.crossCharacter
                and cachedCrafter.crafterUID == "AltCrafter-TestRealm"
                and cachedCrafter.crafterName == "AltCrafter"
                and cachedCrafter.resPercent == 44
                and cachedCrafter.fallbackReason == "cached-crafter",
            "exact cross-character crafter cache resolution failed")
        local cachedStatus = Stats.GetRecipeCacheStatus({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1006,
        })
        assert(cachedStatus.hasCachedCrafter
                and cachedStatus.cachedCrafterUID == "AltCrafter-TestRealm",
            "cross-character recipe cache status failed")

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
        local craftSimUpgradeOK, craftSimUpgradeStatus = Stats.SaveSnapshot({
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
        assert(craftSimUpgradeOK and craftSimUpgradeStatus == nil,
            "exact CraftSim recipe should upgrade an incomplete native snapshot")
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
        local upgraded = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
            recipeID = 1002,
        }, {})
        assert(upgraded.statSource == "craftsim+native-open"
                and upgraded.resPercent == 55
                and math.abs((upgraded.resExtra or 0) - 0.55) < 0.0001
                and not upgraded.nodeHash,
            "CraftSim recipe should merge visible stats without owning node extras")

        local nativeDowngradeOK, nativeDowngradeStatus = Stats.SaveSnapshot({
            source = "native-open",
            recipeID = 1002,
            recipeName = "Some Milling",
            profession = "Inscription",
            profileKey = "insc_milling",
            resPercent = 55,
            resExtra = 0.55,
            supportsResourcefulness = true,
        })
        assert(nativeDowngradeOK and nativeDowngradeStatus == "preserved-existing",
            "native refresh should preserve an exact CraftSim recipe snapshot")
        testOpenSnapshot = nil
        local afterNativeDowngrade = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
            recipeID = 1002,
        }, {})
        assert(afterNativeDowngrade.statSource == "craftsim-imported"
                and afterNativeDowngrade.resPercent == 5
                and math.abs((afterNativeDowngrade.resExtra or 0) - 0.55) < 0.0001
                and not afterNativeDowngrade.nodeHash,
            "native refresh downgraded an exact CraftSim recipe snapshot")

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
                and math.abs((craftSimOnly.resExtra or 0) - 0.55) < 0.0001
                and not craftSimOnly.nodeHash,
            "CraftSim import leaked hidden node state")

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

        -- 12.1 native capture uses the selected expansion skill line and the
        -- public profession-trait APIs; it must not depend on frame internals
        -- or CraftSim's cached specialization model.
        ProfessionsFrame = {
            professionInfo = {
                professionID = 999202,
                parentProfessionID = 202,
                professionName = "Midnight Engineering",
            },
        }
        C_ProfSpecs = {
            GetConfigIDForSkillLine = function(skillLineID)
                return skillLineID == 999202 and 7001 or 0
            end,
            GetDefaultSpecSkillLine = function() return 999202 end,
            GetSpecTabIDsForSkillLine = function(skillLineID)
                return skillLineID == 999202 and { 8001 } or {}
            end,
            GetRootPathForTab = function() return 106720 end,
            GetChildrenForPath = function() return {} end,
            GetSpendEntryForPath = function(nodeID) return nodeID + 1000 end,
            GetDescriptionForPath = function(nodeID)
                return "Live description " .. tostring(nodeID)
            end,
        }
        C_Traits = {
            GetTreeNodes = function(treeID)
                return treeID == 8001 and { 106720, 106727 } or {}
            end,
            GetNodeInfo = function(configID, nodeID)
                assert(configID == 7001, "native node capture used wrong config")
                return {
                    ID = nodeID,
                    currentRank = 1,
                    ranksPurchased = 0,
                    maxRanks = 1,
                }
            end,
            GetEntryInfo = function(configID, entryID)
                assert(configID == 7001, "node name lookup used wrong config")
                return { definitionID = entryID + 1000 }
            end,
            GetDefinitionInfo = function(definitionID)
                return { overrideName = "Live Engineering Path " .. tostring(definitionID - 2000) }
            end,
        }
        local apiCapture = Stats.CaptureOpenProfessionNodes()
        assert(apiCapture
                and apiCapture.meta
                and apiCapture.meta.captureMethod == "traits-api"
                and apiCapture.nodes[106720].rank == 1
                and apiCapture.nodes[106727].rank == 1
                and apiCapture.nodes[106720].name == "Live Engineering Path 106720"
                and apiCapture.nodes[106720].description == "Live description 106720"
                and apiCapture.nodes[106720].nameSource == "blizzard",
            "12.1 profession trait API capture failed")
        local liveRows = Stats.GetProfessionNodeRows("Engineering")
        local liveSettingsNode = nil
        for _, group in ipairs(liveRows.groups or {}) do
            for _, row in ipairs(group.rows or {}) do
                if row.nodeID == 106720 then liveSettingsNode = row end
            end
        end
        assert(liveSettingsNode
                and liveSettingsNode.name == "Live Engineering Path 106720"
                and liveSettingsNode.nameSource == "blizzard",
            "captured in-game profession node names did not reach settings rows")
        local revisionAfterAPICapture = Stats.GetRevision()
        assert(Stats.CaptureOpenProfessionNodes(), "repeat native node capture failed")
        assert(Stats.GetRevision() == revisionAfterAPICapture,
            "unchanged profession frame refresh invalidated pricing revision")
        ProfessionsFrame = originalProfessionsFrame
        C_ProfSpecs = originalCProfSpecs
        C_Traits = originalCTraits

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

        local jcOpts = {
            jcCraftMulti = 30,
            jcCraftRes = 20,
            jcMcNode = 50,
            jcRsNode = 50,
        }
        local jcDefault = Stats.ResolveForStrat({
            profession = "Jewelcrafting",
            formulaProfile = "jc_craft",
            recipeID = 1230476,
        }, jcOpts)
        assert(jcDefault and math.abs((jcDefault.multiExtra or 0) - 0.50) < 0.0001,
            "JC Sunglass Vial workbook hidden MC default failed")

        local jcNodes = Stats.CaptureProfessionNodes("Jewelcrafting", {
            [106991] = 1,
            [106995] = 1,
            [106998] = 1,
            [107000] = 1,
        }, "gam-native-nodes")
        assert(jcNodes and jcNodes.nodeHash, "JC node capture failed")
        local jcCaptured = Stats.ResolveForStrat({
            profession = "Jewelcrafting",
            formulaProfile = "jc_craft",
            recipeID = 1230476,
        }, jcOpts)
        assert(jcCaptured.statSource == "gam-native-nodes"
                and math.abs((jcCaptured.multiExtra or 0) - 0.25) < 0.0001
                and math.abs((jcCaptured.resExtra or 0) - 0.35) < 0.0001,
            "JC recipe-scoped captured hidden nodes failed")
        assert(jcCaptured.nodeBonusDetails
                and jcCaptured.nodeBonusDetails.status == "resolved"
                and jcCaptured.nodeBonusDetails.multicraft
                and #jcCaptured.nodeBonusDetails.multicraft.nodes == 2
                and jcCaptured.nodeBonusDetails.multicraft.nodes[1].nodeID == 106991
                and jcCaptured.nodeBonusDetails.multicraft.nodes[2].nodeID == 106995
                and math.abs((jcCaptured.nodeBonusDetails.multicraft.extra or 0) - 0.25) < 0.0001
                and jcCaptured.nodeBonusDetails.resourcefulness
                and #jcCaptured.nodeBonusDetails.resourcefulness.nodes == 2
                and math.abs((jcCaptured.nodeBonusDetails.resourcefulness.extra or 0) - 0.35) < 0.0001,
            "JC applied-node diagnostic failed")

        assert(Stats.SaveSnapshot({
            source = "native-open",
            recipeID = 1230475,
            recipeName = "Sin'dorei Lens",
            profession = "Jewelcrafting",
            profileKey = "jc_craft",
            multiPercent = 30,
            multiExtra = 0.25,
            supportsMulticraft = true,
            resPercent = 20,
            resExtra = 0.35,
            supportsResourcefulness = true,
            nodeHash = "106991:1|106995:1",
        }))
        local jcUnscoped = Stats.ResolveForStrat({
            profession = "Jewelcrafting",
            formulaProfile = "jc_craft",
        }, jcOpts)
        assert(jcUnscoped.statSource == "gam-cache-profile"
                and jcUnscoped.fallbackReason == "profile-visible-stats-only"
                and math.abs((jcUnscoped.multiPercent or 0) - 30) < 0.0001
                and math.abs((jcUnscoped.multiExtra or 0) - 0.50) < 0.0001
                and not jcUnscoped.nodeHash,
            "JC unscoped profile snapshot leaked hidden node extras")

        assert(Stats.SaveSnapshot({
            source = "craftsim-imported",
            recipeID = 1230476,
            recipeName = "Sunglass Vial",
            profession = "Jewelcrafting",
            profileKey = "jc_craft",
            multiPercent = 30,
            multiExtra = 0.50,
            supportsMulticraft = true,
            resPercent = 20,
            resExtra = 0.50,
            supportsResourcefulness = true,
            nodeHash = "current-craftsim-layout",
        }))
        testOpenSnapshot = {
            source = "native-open",
            recipeID = 1230476,
            recipeName = "Sunglass Vial",
            profession = "Jewelcrafting",
            profileKey = "jc_craft",
            multiPercent = 31,
            resPercent = 21,
            supportsMulticraft = true,
            supportsResourcefulness = true,
        }
        local jcExactMerged = Stats.ResolveForStrat({
            profession = "Jewelcrafting",
            formulaProfile = "jc_craft",
            recipeID = 1230476,
        }, jcOpts)
        assert(jcExactMerged.statSource == "craftsim+native-open"
                and math.abs((jcExactMerged.multiPercent or 0) - 31) < 0.0001
                and math.abs((jcExactMerged.resPercent or 0) - 21) < 0.0001
                and math.abs((jcExactMerged.multiExtra or 0) - 0.25) < 0.0001
                and math.abs((jcExactMerged.resExtra or 0) - 0.35) < 0.0001
                and jcExactMerged.nodeHash,
            "CraftSim snapshot overrode GAM-owned learned node extras")
    end)
    testOpenSnapshot = originalOpen
    testOpenProfessionNodes = originalProfessionNodes
    testPlayerProfessionSet = originalPlayerProfessionSet
    ProfessionsFrame = originalProfessionsFrame
    C_ProfSpecs = originalCProfSpecs
    C_Traits = originalCTraits
    C_TradeSkillUI = originalCTradeSkillUI
    C_Timer = originalCTimer
    GAM.db = originalDB
    GoldAdvisorMidnightDB = originalSavedDB
    return ok, err
end
