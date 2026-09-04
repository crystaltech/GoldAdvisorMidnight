-- GoldAdvisorMidnight/CraftSimBridge.lua
-- Optional CraftSim integration. Safe detection — never errors if absent.
-- Module: GAM.CraftSimBridge

local ADDON_NAME, GAM = ...
local Bridge = {}
GAM.CraftSimBridge = Bridge

local function GetOpts()
    return (GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {}
end

local function RoundDecimal(value, places)
    local n = tonumber(value)
    if not n then return nil end
    local mult = 10 ^ (places or 0)
    return math.floor(n * mult + 0.5) / mult
end

local PROFESSION_DEFS = (GAM.C and GAM.C.PROFESSION_REGISTRY) or {}

local function GetProfessionEnumValue(profDef)
    if not (profDef and Enum and Enum.Profession) then
        return nil
    end
    return Enum.Profession[profDef.enumName]
end

local function RecipeMatchesProfession(recipeData, profDef)
    local info = recipeData
        and recipeData.professionData
        and recipeData.professionData.professionInfo
    if not (info and profDef) then
        return false
    end

    local enumValue = GetProfessionEnumValue(profDef)
    if enumValue ~= nil and info.profession == enumValue then
        return true
    end

    return info.professionID == profDef.skillLineID
end

local function InferFormulaProfileKey(recipeData, profDef)
    if not recipeData or not profDef then
        return nil
    end

    local recipeName = tostring(recipeData.recipeName or (recipeData.recipeInfo and recipeData.recipeInfo.name) or ""):lower()
    if profDef.profKey == "insc" then
        if recipeName:find("codified", 1, true) then
            return "insc_codified"
        end
        if recipeData.supportsMulticraft then
            return "insc_ink"
        end
        return "insc_milling"
    end
    if profDef.profKey == "jc" then
        if recipeName:find("prospecting", 1, true) then
            return "jc_prospect"
        end
        if recipeName:find("crushing", 1, true) then
            return "jc_crush"
        end
        return "jc_craft"
    end
    if profDef.profKey == "ench" then
        if recipeName:find("shatter", 1, true) then
            return "ench_shatter"
        end
        return "ench_craft"
    end
    if profDef.profKey == "eng" then
        if recipeName:find("recycling", 1, true) then
            return "engineering_recycling"
        end
        return "engineering_craft"
    end

    local directProfiles = {
        alch = "alchemy",
        tail = "tailoring",
        bs = "blacksmithing",
        lw = "leatherworking",
        cook = "cooking",
    }
    return directProfiles[profDef.profKey]
end

-- ===== Detection =====
local function CraftSimAvailable()
    return CraftSimAPI ~= nil
        and type(CraftSimAPI.GetRecipeData) == "function"
        and type(CraftSimAPI.GetOpenRecipeData) == "function"
end

local function GetCraftSimAddon()
    if type(CraftSim) == "table" then
        return CraftSim
    end
    if CraftSimAPI and type(CraftSimAPI.GetCraftSim) == "function" then
        local ok, addon = pcall(function()
            return CraftSimAPI:GetCraftSim()
        end)
        if ok and type(addon) == "table" then
            return addon
        end
    end
    return nil
end

-- ===== Price lookup via CraftSim =====

-- GetPrice(itemID) → price in copper, or nil
-- Uses CraftSim.PRICE_SOURCE via CraftSimAPI:GetCraftSim() when available.
function Bridge.GetPrice(itemID)
    if not CraftSimAvailable() then return nil end
    if not itemID then return nil end

    local ok, price = pcall(function()
        local craftSim = GetCraftSimAddon()
        if craftSim and craftSim.PRICE_SOURCE then
            return craftSim.PRICE_SOURCE:GetMinBuyoutByItemID(itemID)
        end
        return nil
    end)
    if ok and type(price) == "number" and price > 0 then
        return price
    end
    return nil
end

-- ===== Logging at load =====
local function OnLoad()
    if CraftSimAvailable() then
        GAM.Log.Info("CraftSimBridge: CraftSim detected — integration active.")
        local importedCount = Bridge.ImportCachedV2StatSnapshotsFromCraftSim
            and Bridge.ImportCachedV2StatSnapshotsFromCraftSim()
            or 0
        if importedCount and importedCount > 0 then
            GAM.Log.Info("CraftSimBridge: imported %d recipe-scoped V2 stat snapshot(s).", importedCount)
        else
            GAM.Log.Debug("CraftSimBridge: no cached recipe-scoped V2 stat snapshots were available to import.")
        end
    else
        GAM.Log.Info("CraftSimBridge: CraftSim not found — running standalone.")
    end
end

-- Register to fire after PLAYER_LOGIN so CraftSim has had a chance to init
local bridgeFrame = CreateFrame("Frame")
bridgeFrame:RegisterEvent("PLAYER_LOGIN")
bridgeFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        OnLoad()
        GAM.Log.Debug("CraftSimBridge: recipe snapshots are optional; GAM owns specialization node bonuses.")
        bridgeFrame:UnregisterAllEvents()
    end
end)

function Bridge.IsAvailable()
    return CraftSimAvailable()
end

-- CraftSimDB is accessible even without the full CraftSimAPI (direct SavedVars).
local function CraftSimDBAvailable()
    return CraftSimDB ~= nil and type(CraftSimDB) == "table"
end

local function GetPlayerCrafterUID()
    local name = type(UnitName) == "function" and UnitName("player") or nil
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil
    return (name or "Unknown") .. "-" .. (realm or "Unknown")
end

local function GetPlayerCrafterData()
    return {
        name = type(UnitName) == "function" and UnitName("player") or nil,
        realm = type(GetRealmName) == "function" and GetRealmName() or nil,
        class = type(UnitClass) == "function" and select(2, UnitClass("player")) or nil,
    }
end

local function GetCachedCrafterData()
    local uid = GetPlayerCrafterUID()
    return CraftSimDB
        and CraftSimDB.crafterDB
        and CraftSimDB.crafterDB.data
        and CraftSimDB.crafterDB.data[uid]
end

local function GetOpenRecipeData()
    if not CraftSimAvailable() then return nil end
    local ok, recipeData = pcall(function()
        return CraftSimAPI:GetOpenRecipeData()
    end)
    if ok then
        return recipeData
    end
    return nil
end

local function BuildCachedRecipeData(recipeID)
    if not CraftSimAvailable() or not recipeID then return nil end
    local crafterData = GetPlayerCrafterData()
    if not crafterData or not crafterData.name or not crafterData.realm then
        return nil
    end

    local ok, recipeData = pcall(function()
        return CraftSimAPI:GetRecipeData({
            recipeID = recipeID,
            crafterData = crafterData,
            forceCache = true,
        })
    end)
    if ok and recipeData then
        return recipeData
    end
    return nil
end

local function GetCachedRecipeIDsForProfession(professionID)
    local uid = GetPlayerCrafterUID()
    local craftSim = GetCraftSimAddon()
    local repo = craftSim
        and craftSim.DB
        and craftSim.DB.CRAFTER
    if repo and type(repo.GetCachedRecipeIDs) == "function" then
        local ok, cached = pcall(function()
            return repo:GetCachedRecipeIDs(uid, professionID)
        end)
        if ok and type(cached) == "table" then
            return cached
        end
    end

    local crafterData = GetCachedCrafterData()
    local cached = crafterData and crafterData.cachedRecipeIDs and crafterData.cachedRecipeIDs[professionID]
    if type(cached) == "table" then
        return cached
    end
    return {}
end

local function GetCachedRecipeIDsForProfessionDef(profDef)
    local seen = {}
    local out = {}

    local function addFrom(professionID)
        if professionID == nil then
            return
        end
        for _, recipeID in ipairs(GetCachedRecipeIDsForProfession(professionID)) do
            if not seen[recipeID] then
                seen[recipeID] = true
                out[#out + 1] = recipeID
            end
        end
    end

    addFrom(GetProfessionEnumValue(profDef))
    addFrom(profDef and profDef.skillLineID)
    return out
end

local function GetStatPercent(professionStat)
    if not professionStat then return nil end

    local ok, value = pcall(function()
        if type(professionStat.GetPercent) == "function" then
            return professionStat:GetPercent()
        end
        local raw = tonumber(professionStat.value)
        local denom = tonumber(professionStat.percentDivisionFactor)
        if raw and denom and denom > 0 then
            return (raw / denom) * 100
        end
        return nil
    end)

    if ok and type(value) == "number" then
        return math.max(0, value)
    end
    return nil
end

local function GetExtraValue(professionStat)
    if not professionStat then return nil end

    local ok, value = pcall(function()
        if type(professionStat.GetExtraValue) == "function" then
            return professionStat:GetExtraValue()
        end
        return professionStat.extraValues and professionStat.extraValues[1] or nil
    end)

    if ok and value ~= nil then
        return tonumber(value)
    end
    return nil
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

local function ReadStatDetail(professionStat)
    if not professionStat then return nil end

    local detail = {}
    local percent = GetStatPercent(professionStat)
    if percent ~= nil then
        detail.percent = RoundDecimal(percent, 3)
    end

    local okDecimal, decimal = pcall(function()
        return type(professionStat.GetPercent) == "function" and professionStat:GetPercent(true) or nil
    end)
    if okDecimal and tonumber(decimal) ~= nil then
        detail.decimal = RoundDecimal(decimal, 6)
    end

    local value = tonumber(professionStat.value)
    if value ~= nil then
        detail.rating = RoundDecimal(value, 3)
    end

    local denom = tonumber(professionStat.percentDivisionFactor)
    if denom ~= nil then
        detail.percentDivisionFactor = denom
    end

    local extra = GetExtraValue(professionStat)
    if extra ~= nil then
        detail.extra = RoundDecimal(extra, 6)
    end

    return next(detail) and detail or nil
end

local function ReadProfessionStats(stats)
    if type(stats) ~= "table" then return nil end

    local out = {
        multicraft = ReadStatDetail(stats.multicraft),
        resourcefulness = ReadStatDetail(stats.resourcefulness),
    }

    if stats.skill and tonumber(stats.skill.value) ~= nil then
        out.skill = RoundDecimal(stats.skill.value, 3)
    end
    if stats.recipeDifficulty and tonumber(stats.recipeDifficulty.value) ~= nil then
        out.recipeDifficulty = RoundDecimal(stats.recipeDifficulty.value, 3)
    end

    return next(out) and out or nil
end

local function GetDetailPercent(detail)
    if type(detail) ~= "table" then return nil end
    local percent = tonumber(detail.percent)
    if percent ~= nil then return percent end

    local decimal = tonumber(detail.decimal)
    if decimal ~= nil then
        return decimal * 100
    end
    return nil
end

local function GetDetailExtra(detail)
    if type(detail) ~= "table" then return nil end
    return tonumber(detail.extra)
end

local function GetNodeName(nodeData)
    if not nodeData then return nil end
    if nodeData.name then
        return tostring(nodeData.name)
    end
    if type(nodeData.GetName) == "function" then
        local ok, name = pcall(function()
            return nodeData:GetName()
        end)
        if ok and name then
            return tostring(name)
        end
    end
    return nil
end

local function CollectNodeRanks(specializationData)
    local nodes = specializationData and specializationData.nodeData
    if type(nodes) ~= "table" then return nil end

    local out = {}
    for _, nodeData in pairs(nodes) do
        local rank = tonumber(nodeData and nodeData.rank) or 0
        local nodeID = tonumber(nodeData and nodeData.nodeID)
        if nodeID and rank > 0 then
            out[#out + 1] = {
                nodeID = nodeID,
                rank = rank,
                maxRank = tonumber(nodeData.maxRank),
                name = GetNodeName(nodeData),
                stats = ReadProfessionStats(nodeData.professionStats),
            }
        end
    end

    table.sort(out, function(a, b)
        return (tonumber(a.nodeID) or 0) < (tonumber(b.nodeID) or 0)
    end)
    return #out > 0 and out or nil
end

local function BuildNodeHash(nodeRanks)
    if type(nodeRanks) ~= "table" then return nil end
    local parts = {}
    for _, node in ipairs(nodeRanks) do
        if node.nodeID and node.rank then
            parts[#parts + 1] = tostring(node.nodeID) .. ":" .. tostring(node.rank)
        end
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ",") or nil
end

local function ApplyCraftSimStatBreakdown(snapshot, recipeData)
    if not snapshot or not recipeData then return end

    snapshot.totalStats = ReadProfessionStats(recipeData.professionStats)
    snapshot.baseStats = ReadProfessionStats(recipeData.baseProfessionStats)
    snapshot.nodeStats = ReadProfessionStats(
        recipeData.specializationData and recipeData.specializationData.professionStats)
    snapshot.gearStats = ReadProfessionStats(
        recipeData.professionGearSet and recipeData.professionGearSet.professionStats)
    snapshot.buffStats = ReadProfessionStats(
        recipeData.buffData and recipeData.buffData.professionStats)
    snapshot.modifierStats = ReadProfessionStats(recipeData.professionStatModifiers)
    snapshot.nodeRanks = CollectNodeRanks(recipeData.specializationData)
    snapshot.nodeHash = BuildNodeHash(snapshot.nodeRanks)
    snapshot.nodeCount = snapshot.nodeRanks and #snapshot.nodeRanks or 0
    snapshot.statQuality = "craftsim-recipe"
end

local function GetFormulaProfiles()
    return (GAM_WORKBOOK_GENERATED and GAM_WORKBOOK_GENERATED.formulaProfiles) or {}
end

local function GetProfileSupports(profileKey)
    local profile = profileKey and GetFormulaProfiles()[profileKey] or nil
    if not profile then
        return nil, nil
    end
    return profile.multiKey ~= nil, profile.resKey ~= nil
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

local function GetV2StatProfileCache(create)
    local db = GAM.db or GoldAdvisorMidnightDB
    if type(db) ~= "table" then
        return nil
    end
    if create then
        db.v2StatCache = db.v2StatCache or {}
        db.v2StatCache.profiles = db.v2StatCache.profiles or {}
    end
    local profiles = db.v2StatCache and db.v2StatCache.profiles
    if type(profiles) ~= "table" then
        return nil
    end

    local uid = GetPlayerCrafterUID()
    if create then
        profiles[uid] = profiles[uid] or {}
    end
    if type(profiles[uid]) ~= "table" then
        return nil
    end
    return profiles[uid]
end

local function CopyStatSnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return nil
    end

    local out = {}
    local scalarFields = {
        "profKey",
        "profileKey",
        "recipeID",
        "recipeName",
        "profession",
        "source",
        "cachedSource",
        "cachedAt",
        "capturedAt",
        "statQuality",
        "multiPercent",
        "multiExtra",
        "resPercent",
        "resExtra",
        "supportsMulticraft",
        "supportsResourcefulness",
        "mcNode",
        "rsNode",
        "mcConstant",
        "resourcefulnessSaveBase",
        "skillLineID",
        "parentSkillLineID",
        "nodeHash",
        "nodeCount",
    }
    for _, field in ipairs(scalarFields) do
        if snapshot[field] ~= nil then
            out[field] = snapshot[field]
        end
    end
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

local function StoreV2ProfileSnapshot(profKey, snapshot)
    if type(snapshot) ~= "table" or not snapshot.profileKey then
        return false
    end

    local stored = CopyStatSnapshot(snapshot)
    if not stored then
        return false
    end
    stored.profession = stored.profession or profKey
    stored.source = "craftsim-imported"
    stored.cachedSource = snapshot.cachedSource or snapshot.source or "craftsim"
    stored.capturedAt = GetCurrentTimestamp()

    if GAM.CraftingStats and type(GAM.CraftingStats.SaveSnapshot) == "function" then
        return GAM.CraftingStats.SaveSnapshot(stored)
    end

    local cache = GetV2StatProfileCache(true)
    if not cache then
        return false
    end

    stored.profKey = profKey
    stored.cachedAt = GetCurrentTimestamp()
    cache[stored.profileKey] = stored
    return true
end

local function GetCraftSimOption(key)
    local craftSim = GetCraftSimAddon()
    if not (craftSim and craftSim.DB and craftSim.DB.OPTIONS and type(craftSim.DB.OPTIONS.Get) == "function") then
        return nil
    end

    local ok, value = pcall(function()
        return craftSim.DB.OPTIONS:Get(key)
    end)
    if ok then
        return value
    end
    return nil
end

local function ApplyCraftSimConstants(snapshot)
    if not snapshot then return end
    local craftSim = GetCraftSimAddon()

    if snapshot.resourcefulnessSaveBase == nil then
        local value = tonumber(GetCraftSimOption("PROFIT_CALCULATION_RESOURCEFULNESS_CONSTANT"))
        if value == nil and craftSim and craftSim.CONST then
            value = tonumber(craftSim.CONST.BASE_RESOURCEFULNESS_AVERAGE_SAVE_FACTOR)
        end
        if value ~= nil then
            snapshot.resourcefulnessSaveBase = value
        end
    end

    if snapshot.multicraftConstants == nil then
        local constants = CopyNumericTable(GetCraftSimOption("PROFIT_CALCULATION_MULTICRAFT_CONSTANTS"))
        if not constants and craftSim and craftSim.CONST then
            constants = CopyNumericTable(craftSim.CONST.MULTICRAFT_CONSTANTS)
        end
        if constants then
            snapshot.multicraftConstants = constants
        end
    end
end

local function GetRecipeProfessionStats(recipeData)
    if not recipeData or not recipeData.professionStats then return nil end
    return recipeData.professionStats
end

local function ApplyProfessionSnapshot(snapshot, recipeData, wantsMulti)
    if not snapshot or not recipeData then return end

    if recipeData.supportsMulticraft ~= nil then
        snapshot.supportsMulticraft = recipeData.supportsMulticraft and true or false
    end
    if recipeData.supportsResourcefulness ~= nil then
        snapshot.supportsResourcefulness = recipeData.supportsResourcefulness and true or false
    end

    ApplyCraftSimStatBreakdown(snapshot, recipeData)
    local recipeStats = GetRecipeProfessionStats(recipeData)
    if recipeStats then
        local totalStats = snapshot.totalStats or ReadProfessionStats(recipeStats)
        if snapshot.resPercent == nil then
            local supportsRes = recipeData.supportsResourcefulness
            local resDetail = totalStats and totalStats.resourcefulness
            local resValue = resDetail and tonumber(resDetail.rating)
            if supportsRes or resValue ~= nil then
                snapshot.resPercent = RoundDecimal(GetDetailPercent(resDetail) or 0, 3)
            end
        end

        if wantsMulti and snapshot.multiPercent == nil then
            local supportsMulti = recipeData.supportsMulticraft
            local mcDetail = totalStats and totalStats.multicraft
            local mcValue = mcDetail and tonumber(mcDetail.rating)
            if supportsMulti or mcValue ~= nil then
                snapshot.multiPercent = RoundDecimal(GetDetailPercent(mcDetail) or 0, 3)
            end
        end

        if snapshot.resExtra == nil then
            local extra = GetDetailExtra(totalStats and totalStats.resourcefulness)
            if extra ~= nil then
                snapshot.resExtra = math.max(0, extra)
            end
        end
        if wantsMulti and snapshot.multiExtra == nil then
            local extra = GetDetailExtra(totalStats and totalStats.multicraft)
            if extra ~= nil then
                snapshot.multiExtra = math.max(0, extra)
            end
        end
    end

    local nodeStats = snapshot.nodeStats
        or ReadProfessionStats(recipeData.specializationData and recipeData.specializationData.professionStats)
    if nodeStats then
        if snapshot.rsNode == nil then
            snapshot.rsNode = math.max(0, GetDetailExtra(nodeStats.resourcefulness) or 0)
        end
        if wantsMulti and snapshot.mcNode == nil then
            snapshot.mcNode = math.max(0, GetDetailExtra(nodeStats.multicraft) or 0)
        end
    end

    if snapshot.resExtra == nil and snapshot.rsNode ~= nil then
        snapshot.resExtra = snapshot.rsNode
    end
    if wantsMulti and snapshot.multiExtra == nil and snapshot.mcNode ~= nil then
        snapshot.multiExtra = snapshot.mcNode
    end
    ApplyCraftSimConstants(snapshot)
end

local function BuildProfessionSnapshot(profDef, wantsMulti)
    local snapshot = {}
    local seenRecipeIDs = {}
    local openRecipeData = GetOpenRecipeData()

    local function capture(recipeData, cachedSource)
        if not recipeData then return false end
        if not RecipeMatchesProfession(recipeData, profDef) then
            return false
        end

        if recipeData.recipeID then
            seenRecipeIDs[recipeData.recipeID] = true
        end

        snapshot.cachedSource = cachedSource or snapshot.cachedSource
        ApplyProfessionSnapshot(snapshot, recipeData, wantsMulti)
        return snapshot.resPercent ~= nil
            and ((not wantsMulti) or snapshot.multiPercent ~= nil)
            and snapshot.rsNode ~= nil
            and ((not wantsMulti) or snapshot.mcNode ~= nil)
    end

    if capture(openRecipeData, "craftsim-open") then
        return snapshot
    end

    for _, recipeID in ipairs(GetCachedRecipeIDsForProfessionDef(profDef)) do
        if not seenRecipeIDs[recipeID] then
            local recipeData = BuildCachedRecipeData(recipeID)
            if capture(recipeData, "craftsim-cache") then
                return snapshot
            end
        end
    end

    return next(snapshot) and snapshot or nil
end

local function BuildRecipeStatSnapshotsFromCraftSim()
    if not CraftSimDBAvailable() then return {} end

    local result = {}
    local seenSnapshotKeys = {}
    local openRecipeData = GetOpenRecipeData()

    for _, profDef in ipairs(PROFESSION_DEFS) do
        local seenRecipeIDs = {}

        local function capture(recipeData, cachedSource)
            if not recipeData or not RecipeMatchesProfession(recipeData, profDef) then
                return
            end

            local profileKey = InferFormulaProfileKey(recipeData, profDef)
            local recipeID = tonumber(recipeData.recipeID)
            local snapshotKey = recipeID and ("recipe:" .. tostring(recipeID))
                or ("profile:" .. tostring(profileKey or "?") .. ":" .. tostring(cachedSource or "?"))
            if not profileKey or seenSnapshotKeys[snapshotKey] then
                return
            end
            seenSnapshotKeys[snapshotKey] = true

            local profileSupportsMulti, profileSupportsRes = GetProfileSupports(profileKey)
            local supportsMulti = recipeData.supportsMulticraft
            local supportsRes = recipeData.supportsResourcefulness
            if supportsMulti == nil then supportsMulti = profileSupportsMulti end
            if supportsRes == nil then supportsRes = profileSupportsRes end

            local snapshot = {
                source = "craftsim-imported",
                cachedSource = cachedSource or "craftsim",
                profession = profDef.profKey,
                profileKey = profileKey,
                recipeID = recipeID,
                recipeName = recipeData.recipeName or (recipeData.recipeInfo and recipeData.recipeInfo.name),
                supportsMulticraft = supportsMulti and true or false,
                supportsResourcefulness = supportsRes and true or false,
            }
            ApplyProfessionSnapshot(snapshot, recipeData, supportsMulti)
            if not snapshot.supportsMulticraft then
                snapshot.multiPercent = 0
                snapshot.multiExtra = 0
            end
            if not snapshot.supportsResourcefulness then
                snapshot.resPercent = 0
                snapshot.resExtra = 0
            end

            if snapshot.resPercent ~= nil or snapshot.multiPercent ~= nil then
                result[#result + 1] = snapshot
            end
        end

        if openRecipeData and openRecipeData.recipeID then
            seenRecipeIDs[openRecipeData.recipeID] = true
        end
        capture(openRecipeData, "craftsim-open")

        for _, recipeID in ipairs(GetCachedRecipeIDsForProfessionDef(profDef)) do
            if not seenRecipeIDs[recipeID] then
                seenRecipeIDs[recipeID] = true
                capture(BuildCachedRecipeData(recipeID), "craftsim-cache")
            end
        end
    end

    return result
end

function Bridge.ImportCachedV2StatSnapshotsFromCraftSim()
    local snapshots = BuildRecipeStatSnapshotsFromCraftSim()
    local count = 0
    for _, snapshot in ipairs(snapshots) do
        local ok, status = StoreV2ProfileSnapshot(snapshot.profession, snapshot)
        if ok and not status then
            count = count + 1
        end
    end
    return count
end

-- ===== Node bonus reader =====

-- GetAllProfessionNodeBonuses() → { profKey → { rsNode, mcNode } } or {}
-- Reconstructs per-profession spec extra values from CraftSim's cached recipe data.
function Bridge.GetAllProfessionNodeBonuses()
    local result = {}
    for _, profDef in ipairs(PROFESSION_DEFS) do
        local snapshot = BuildProfessionSnapshot(profDef, true)
        if snapshot and (snapshot.rsNode ~= nil or snapshot.mcNode ~= nil) then
            result[profDef.profKey] = {
                rsNode = math.max(0, math.min(1, tonumber(snapshot.rsNode) or 0)),
                mcNode = math.max(0, math.min(1, tonumber(snapshot.mcNode) or 0)),
            }
        end
    end
    return result
end

function Bridge.GetAllProfessionStatSnapshots()
    local result = {}
    for _, profDef in ipairs(PROFESSION_DEFS) do
        local snapshot = BuildProfessionSnapshot(profDef, true)
        if snapshot then
            result[profDef.profKey] = snapshot
        end
    end
    return result
end

function Bridge.GetOpenProfessionStatSnapshots()
    local result = {}
    local recipeData = GetOpenRecipeData()
    if not recipeData then
        return result
    end

    for _, profDef in ipairs(PROFESSION_DEFS) do
        if RecipeMatchesProfession(recipeData, profDef) then
            local snapshot = {}
            ApplyProfessionSnapshot(snapshot, recipeData, true)
            if next(snapshot) then
                snapshot.source = "craftsim-imported"
                snapshot.cachedSource = "craftsim-open"
                snapshot.recipeID = recipeData.recipeID
                snapshot.recipeName = recipeData.recipeName or (recipeData.recipeInfo and recipeData.recipeInfo.name)
                snapshot.profession = profDef.profKey
                snapshot.profileKey = InferFormulaProfileKey(recipeData, profDef)
                if not snapshot.supportsMulticraft then
                    snapshot.multiPercent = 0
                    snapshot.multiExtra = 0
                end
                if not snapshot.supportsResourcefulness then
                    snapshot.resPercent = 0
                    snapshot.resExtra = 0
                end
                result[profDef.profKey] = snapshot
                StoreV2ProfileSnapshot(profDef.profKey, snapshot)
            end
            break
        end
    end
    return result
end

function Bridge.CaptureOpenRecipeStatsV2()
    local snapshots = Bridge.GetOpenProfessionStatSnapshots()
    for _, profDef in ipairs(PROFESSION_DEFS) do
        local snapshot = snapshots and snapshots[profDef.profKey]
        if snapshot then
            return snapshot, nil
        end
    end
    return nil, "no-open-craftsim-recipe"
end

function Bridge.GetCachedProfileStatSnapshots()
    if GAM.CraftingStats and type(GAM.CraftingStats.GetAllProfiles) == "function" then
        local result = {}
        local ok, profiles = pcall(function()
            return GAM.CraftingStats.GetAllProfiles()
        end)
        if ok and type(profiles) == "table" then
            for profileKey, snapshot in pairs(profiles) do
                if type(snapshot) == "table"
                        and snapshot.statSource
                        and snapshot.statSource ~= "workbook-default" then
                    local copy = CopyStatSnapshot(snapshot)
                    if copy then
                        copy.profileKey = copy.profileKey or profileKey
                        copy.source = snapshot.statSource
                        result[profileKey] = copy
                    end
                end
            end
        end
        return result
    end

    local cache = GetV2StatProfileCache(false)
    local result = {}
    if type(cache) ~= "table" then
        return result
    end

    for profileKey, snapshot in pairs(cache) do
        local copy = CopyStatSnapshot(snapshot)
        if copy then
            copy.profileKey = copy.profileKey or profileKey
            copy.source = "gam-cache"
            result[profileKey] = copy
        end
    end
    return result
end

function Bridge.GetFormulaConstants()
    local snapshot = {}
    ApplyCraftSimConstants(snapshot)
    if snapshot.resourcefulnessSaveBase ~= nil or snapshot.multicraftConstants ~= nil then
        return {
            resourcefulnessSaveBase = snapshot.resourcefulnessSaveBase,
            multicraftConstants = snapshot.multicraftConstants,
        }
    end
    return nil
end

if GAM.CraftSimPriceOverrides and type(GAM.CraftSimPriceOverrides.Install) == "function" then
    GAM.CraftSimPriceOverrides.Install(Bridge, {
        GetOpts = GetOpts,
        CraftSimDBAvailable = CraftSimDBAvailable,
        GetCraftSimAddon = GetCraftSimAddon,
    })
end
