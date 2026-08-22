-- GoldAdvisorMidnight/CraftingStatsSpecialization.lua
-- Profession registry lookup and specialization-node stat resolution.
-- Module: GAM.CraftingStatsSpecialization

local ADDON_NAME, GAM = ...
local Specialization = {}
GAM.CraftingStatsSpecialization = Specialization

local SEASON_KEY = "midnight"
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

local function ClampNonNegative(value)
    local n = tonumber(value) or 0
    if n < 0 then return 0 end
    return n
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

Specialization.GetProfessionDefs = function()
    return PROFESSION_DEFS
end
Specialization.ResolveProfessionDef = ResolveProfessionDef
Specialization.ResolveProfessionDefBySkillLine = function(skillLineID)
    return PROFESSION_BY_SKILL_LINE[tonumber(skillLineID)]
end
Specialization.GetCatalog = GetSpecializationCatalog
Specialization.IsProfile = IsSpecializationProfile
Specialization.GetProfessionForProfile = GetProfessionForProfile
Specialization.ClampRank = ClampRank
Specialization.GetCatalogNode = GetCatalogNode
Specialization.EnsureNodeState = EnsureProfessionNodeState
Specialization.BuildNodeHash = BuildNodeHash
Specialization.ApplyNodeState = ApplySpecializationNodeState
