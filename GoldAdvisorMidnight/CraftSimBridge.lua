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

local PROFESSION_DEFS = {
    { enumName = "Inscription",    skillLineID = 773, profKey = "insc" },
    { enumName = "Jewelcrafting",  skillLineID = 755, profKey = "jc" },
    { enumName = "Enchanting",     skillLineID = 333, profKey = "ench" },
    { enumName = "Alchemy",        skillLineID = 171, profKey = "alch" },
    { enumName = "Tailoring",      skillLineID = 197, profKey = "tail" },
    { enumName = "Blacksmithing",  skillLineID = 164, profKey = "bs" },
    { enumName = "Leatherworking", skillLineID = 165, profKey = "lw" },
    { enumName = "Engineering",    skillLineID = 202, profKey = "eng" },
}

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
        local syncedCount = Bridge.SyncNodeBonusesFromCraftSim and Bridge.SyncNodeBonusesFromCraftSim() or 0
        if syncedCount and syncedCount > 0 then
            GAM.Log.Info("CraftSimBridge: synced node bonuses for %d profession(s).", syncedCount)
        else
            GAM.Log.Debug("CraftSimBridge: no cached node bonuses were available to sync at login.")
        end
        local importedCount = Bridge.ImportCachedV2StatSnapshotsFromCraftSim
            and Bridge.ImportCachedV2StatSnapshotsFromCraftSim()
            or 0
        if importedCount and importedCount > 0 then
            GAM.Log.Info("CraftSimBridge: imported %d V2 stat profile snapshot(s).", importedCount)
        else
            GAM.Log.Debug("CraftSimBridge: no cached V2 stat profile snapshots were available to import.")
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
        GAM.Log.Debug("CraftSimBridge: legacy options keep workbook baselines; V2 uses CraftSim snapshots when available.")
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
    if not crafterData.name or not crafterData.realm then
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

local PROF_KEY_TO_FIELDS = {
    insc = {
        multiFields = { "inscInkMulti" },
        resFields = { "inscMillingRes", "inscInkRes" },
        mcNodeField = "inscMcNode",
        rsNodeField = "inscRsNode",
    },
    jc = {
        multiFields = { "jcCraftMulti" },
        resFields = { "jcProspectRes", "jcCrushRes", "jcCraftRes" },
        mcNodeField = "jcMcNode",
        rsNodeField = "jcRsNode",
    },
    ench = {
        multiFields = { "enchCraftMulti" },
        resFields = { "enchShatterRes", "enchCraftRes" },
        mcNodeField = "enchMcNode",
        rsNodeField = "enchRsNode",
    },
    alch = {
        multiFields = { "alchMulti" },
        resFields = { "alchRes" },
        mcNodeField = "alchMcNode",
        rsNodeField = "alchRsNode",
    },
    tail = {
        multiFields = { "tailMulti" },
        resFields = { "tailRes" },
        mcNodeField = "tailMcNode",
        rsNodeField = "tailRsNode",
    },
    bs = {
        multiFields = { "bsMulti" },
        resFields = { "bsRes" },
        mcNodeField = "bsMcNode",
        rsNodeField = "bsRsNode",
    },
    lw = {
        multiFields = { "lwMulti" },
        resFields = { "lwRes" },
        mcNodeField = "lwMcNode",
        rsNodeField = "lwRsNode",
    },
    eng = {
        multiFields = { "engCraftMulti" },
        resFields = { "engRecycleRes", "engCraftRes" },
        mcNodeField = "engMcNode",
        rsNodeField = "engRsNode",
    },
}

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

    if GAM.CraftingStatsV2 and type(GAM.CraftingStatsV2.SaveSnapshot) == "function" then
        return GAM.CraftingStatsV2.SaveSnapshot(stored)
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

local function FormatCraftSimStat(stat)
    if not stat then
        return "nil"
    end

    local percent = GetStatPercent(stat)
    local percentText = percent ~= nil and string.format("%.3f%%", percent) or "-"
    local decimalText = "-"
    local okDecimal, decimal = pcall(function()
        return type(stat.GetPercent) == "function" and stat:GetPercent(true) or nil
    end)
    if okDecimal and tonumber(decimal) ~= nil then
        decimalText = string.format("%.6f", decimal)
    end

    return string.format("value=%s denom=%s pct=%s decimal=%s extra=%s",
        tostring(stat.value),
        tostring(stat.percentDivisionFactor),
        percentText,
        decimalText,
        tostring(GetExtraValue(stat) or 0))
end

local function DumpCraftSimStatBucket(label, stats)
    if not stats then
        GAM.Log.Info("  %s: nil", label)
        return
    end
    GAM.Log.Info("  %s: mc[%s] res[%s] skill=%s difficulty=%s",
        label,
        FormatCraftSimStat(stats.multicraft),
        FormatCraftSimStat(stats.resourcefulness),
        tostring(stats.skill and stats.skill.value or nil),
        tostring(stats.recipeDifficulty and stats.recipeDifficulty.value or nil))
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

local function GetProfessionSyncDataFromCraftSim()
    if not CraftSimDBAvailable() then return {} end

    local syncData = {}
    for _, profDef in ipairs(PROFESSION_DEFS) do
        local profKey = profDef.profKey
        local fieldInfo = PROF_KEY_TO_FIELDS[profKey]
        local wantsMulti = fieldInfo and fieldInfo.multiFields and #fieldInfo.multiFields > 0
        local snapshot = BuildProfessionSnapshot(profDef, wantsMulti)
        if snapshot then
            syncData[profKey] = snapshot
        end
    end
    return syncData
end

local function BuildProfileStatSnapshotsFromCraftSim()
    if not CraftSimDBAvailable() then return {} end

    local result = {}
    local openRecipeData = GetOpenRecipeData()

    for _, profDef in ipairs(PROFESSION_DEFS) do
        local seenRecipeIDs = {}

        local function capture(recipeData, cachedSource)
            if not recipeData or not RecipeMatchesProfession(recipeData, profDef) then
                return
            end

            local profileKey = InferFormulaProfileKey(recipeData, profDef)
            if not profileKey or result[profileKey] then
                return
            end

            local supportsMulti, supportsRes = GetProfileSupports(profileKey)
            if supportsMulti == nil then
                supportsMulti = recipeData.supportsMulticraft and true or false
            end
            if supportsRes == nil then
                supportsRes = recipeData.supportsResourcefulness and true or false
            end

            local snapshot = {
                source = "craftsim-imported",
                cachedSource = cachedSource or "craftsim",
                profession = profDef.profKey,
                profileKey = profileKey,
                recipeID = recipeData.recipeID,
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
                result[profileKey] = snapshot
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
    local snapshots = BuildProfileStatSnapshotsFromCraftSim()
    local count = 0
    for _, snapshot in pairs(snapshots) do
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
    if GAM.CraftingStatsV2 and type(GAM.CraftingStatsV2.GetAllProfiles) == "function" then
        local result = {}
        local ok, profiles = pcall(function()
            return GAM.CraftingStatsV2.GetAllProfiles()
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

function Bridge.DumpOpenRecipeStats()
    if not CraftSimAvailable() then
        GAM.Log.Warn("CraftSimBridge: CraftSim API unavailable")
        return
    end

    local recipeData = GetOpenRecipeData()
    if not recipeData then
        GAM.Log.Warn("CraftSimBridge: no open CraftSim recipe data")
        return
    end

    local info = recipeData.professionData and recipeData.professionData.professionInfo or {}
    GAM.Log.Info("=== GAM CraftSim Open Recipe Dump ===")
    GAM.Log.Info("recipe=%s id=%s baseItemAmount=%s supports stats=%s mc=%s res=%s",
        tostring(recipeData.recipeName or (recipeData.recipeInfo and recipeData.recipeInfo.name) or "?"),
        tostring(recipeData.recipeID),
        tostring(recipeData.baseItemAmount),
        tostring(recipeData.supportsCraftingStats),
        tostring(recipeData.supportsMulticraft),
        tostring(recipeData.supportsResourcefulness))
    GAM.Log.Info("profession enum=%s skillLine=%s parent=%s",
        tostring(info.profession),
        tostring(info.professionID),
        tostring(info.parentProfessionName))

    DumpCraftSimStatBucket("professionStats", recipeData.professionStats)
    DumpCraftSimStatBucket("baseProfessionStats", recipeData.baseProfessionStats)
    DumpCraftSimStatBucket("specializationStats",
        recipeData.specializationData and recipeData.specializationData.professionStats)
    DumpCraftSimStatBucket("gearStats",
        recipeData.professionGearSet and recipeData.professionGearSet.professionStats)
    DumpCraftSimStatBucket("buffStats",
        recipeData.buffData and recipeData.buffData.professionStats)
    DumpCraftSimStatBucket("modifierStats", recipeData.professionStatModifiers)

    local operationInfo = recipeData.baseOperationInfo
    if operationInfo and type(operationInfo.bonusStats) == "table" then
        GAM.Log.Info("  operation bonusStats=%d", #operationInfo.bonusStats)
        for i, statInfo in ipairs(operationInfo.bonusStats) do
            if i > 12 then
                GAM.Log.Info("    ... %d more stat row(s)", #operationInfo.bonusStats - 12)
                break
            end
            GAM.Log.Info("    bonus %02d: name=%s value=%s ratingPct=%s",
                i,
                tostring(statInfo.bonusStatName),
                tostring(statInfo.bonusStatValue),
                tostring(statInfo.ratingPct))
        end
    else
        GAM.Log.Info("  operation bonusStats=nil")
    end

    local openSnapshots = Bridge.GetOpenProfessionStatSnapshots()
    for _, profDef in ipairs(PROFESSION_DEFS) do
        if RecipeMatchesProfession(recipeData, profDef) then
            local snapshot = openSnapshots and openSnapshots[profDef.profKey]
            GAM.Log.Info("snapshot prof=%s mc=%s mcExtra=%s res=%s resExtra=%s",
                tostring(profDef.profKey),
                tostring(snapshot and snapshot.multiPercent),
                tostring(snapshot and snapshot.multiExtra),
                tostring(snapshot and snapshot.resPercent),
                tostring(snapshot and snapshot.resExtra))
            GAM.Log.Info("snapshot recipeID=%s profile=%s source=%s",
                tostring(snapshot and snapshot.recipeID),
                tostring(snapshot and snapshot.profileKey),
                tostring(snapshot and snapshot.source))
            GAM.Log.Info("snapshot nodeHash=%s nodes=%s totalMC=%s nodeMC=%s totalRes=%s nodeRes=%s",
                tostring(snapshot and snapshot.nodeHash or "-"),
                tostring(snapshot and snapshot.nodeCount or 0),
                tostring(snapshot and snapshot.totalStats
                    and snapshot.totalStats.multicraft
                    and snapshot.totalStats.multicraft.percent or "-"),
                tostring(snapshot and snapshot.nodeStats
                    and snapshot.nodeStats.multicraft
                    and snapshot.nodeStats.multicraft.percent or "-"),
                tostring(snapshot and snapshot.totalStats
                    and snapshot.totalStats.resourcefulness
                    and snapshot.totalStats.resourcefulness.percent or "-"),
                tostring(snapshot and snapshot.nodeStats
                    and snapshot.nodeStats.resourcefulness
                    and snapshot.nodeStats.resourcefulness.percent or "-"))
            break
        end
    end
    GAM.Log.Info("=== End CraftSim Open Recipe Dump ===")
end

-- SyncOptionsFromCraftSim() → count, updatedFields
-- Syncs only node bonus fields from cached CraftSim data.
function Bridge.SyncOptionsFromCraftSim()
    local syncData = GetProfessionSyncDataFromCraftSim()
    local opts = GetOpts()
    local count = 0
    local updatedFields = {}

    for profKey, snapshot in pairs(syncData) do
        local fieldInfo = PROF_KEY_TO_FIELDS[profKey]
        if fieldInfo then
            local updated = false

            if fieldInfo.mcNodeField and snapshot.mcNode ~= nil then
                local rounded = math.floor(snapshot.mcNode * 100 + 0.5)
                opts[fieldInfo.mcNodeField] = rounded
                updatedFields[fieldInfo.mcNodeField] = rounded
                updated = true
            end

            if fieldInfo.rsNodeField and snapshot.rsNode ~= nil then
                local rounded = math.floor(snapshot.rsNode * 100 + 0.5)
                opts[fieldInfo.rsNodeField] = rounded
                updatedFields[fieldInfo.rsNodeField] = rounded
                updated = true
            end

            if updated then
                count = count + 1
            end
        end
    end

    return count, updatedFields
end

-- SyncNodeBonusesFromCraftSim() → count (number of professions updated)
-- Imports CraftSim's cached node bonuses so runtime output can scale from the
-- workbook's baked default nodes to the player's actual specialization tree.
function Bridge.SyncNodeBonusesFromCraftSim()
    local count = Bridge.SyncOptionsFromCraftSim()
    return count or 0
end

if GAM.CraftSimPriceOverrides and type(GAM.CraftSimPriceOverrides.Install) == "function" then
    GAM.CraftSimPriceOverrides.Install(Bridge, {
        GetOpts = GetOpts,
        CraftSimDBAvailable = CraftSimDBAvailable,
        GetCraftSimAddon = GetCraftSimAddon,
    })
end

local BuildPushOverrideEntries = Bridge._BuildPushOverrideEntries
local FindPushOverrideEntry = Bridge._FindPushOverrideEntry

function Bridge.RunSmokeChecks()
    assert(type(BuildPushOverrideEntries) == "function", "CraftSim price override helper unavailable")
    assert(type(FindPushOverrideEntry) == "function", "CraftSim price override lookup unavailable")

    local originalGetPatchDB = GAM.GetPatchDB
    local originalGetOptions = GAM.GetOptions
    local originalAHScan = GAM.AHScan
    local originalGetUnitPrice = GAM.Pricing and GAM.Pricing.GetUnitPrice
    local originalGetActiveRecipeView = GAM.Pricing and GAM.Pricing.GetActiveRecipeView
    local originalVendorPrices = GAM.C.VENDOR_PRICES
    local fakePDB = {
        rankGroups = {},
        priceOverrides = {},
    }
    local fakeOpts = {
        shallowFillQty = 50,
        priceSource = "craftsim",
    }
    local cachedPrices = {
        [51001] = 111,
        [51002] = 112,
        [52001] = 211,
        [52002] = 212,
        [53001] = 311,
        [53101] = 411,
    }
    local livePrices = {
        [51001] = { [1000] = 4101 },
        [51002] = { [1000] = 4102 },
        [52001] = { [50] = 5201 },
        [52002] = { [50] = 5202 },
        [53001] = { [25] = 6301 },
        [53002] = { [25] = 6302 },
    }

    local function RestoreState()
        GAM.GetPatchDB = originalGetPatchDB
        GAM.GetOptions = originalGetOptions
        GAM.AHScan = originalAHScan
        if GAM.Pricing then
            GAM.Pricing.GetUnitPrice = originalGetUnitPrice
            GAM.Pricing.GetActiveRecipeView = originalGetActiveRecipeView
        end
        GAM.C.VENDOR_PRICES = originalVendorPrices
    end

    local ok, err = pcall(function()
        GAM.GetPatchDB = function() return fakePDB end
        GAM.GetOptions = function() return fakeOpts end
        GAM.AHScan = {
            ComputePriceForQty = function(itemID, qty)
                local byQty = livePrices[itemID]
                return byQty and byQty[qty] or nil
            end,
        }
        GAM.C.VENDOR_PRICES = {}
        if not GAM.Pricing then
            error("Pricing module unavailable")
        end
        GAM.Pricing.GetUnitPrice = function(itemID)
            return cachedPrices[itemID], false
        end
        GAM.Pricing.GetActiveRecipeView = function(strat)
            return strat
        end

        local originalCraftSimForStats = CraftSim
        local statSnapshotOK, statSnapshotErr = pcall(function()
            CraftSim = {
                CONST = {
                    BASE_RESOURCEFULNESS_AVERAGE_SAVE_FACTOR = 0.31,
                    MULTICRAFT_CONSTANTS = {
                        DEFAULT = 2.5,
                        [1] = 2.1,
                    },
                },
                DB = {
                    OPTIONS = {
                        Get = function(_, key)
                            if key == "PROFIT_CALCULATION_RESOURCEFULNESS_CONSTANT" then
                                return 0.32
                            end
                            if key == "PROFIT_CALCULATION_MULTICRAFT_CONSTANTS" then
                                return {
                                    DEFAULT = 2.55,
                                    [2] = 1.83,
                                }
                            end
                            return nil
                        end,
                    },
                },
            }

            local function FakeStat(percent, extra)
                return {
                    value = percent,
                    GetPercent = function()
                        return percent
                    end,
                    GetExtraValue = function()
                        return extra
                    end,
                }
            end

            local originalEnum = Enum
            local professionMatchOK, professionMatchErr = pcall(function()
                Enum = {
                    Profession = {
                        Inscription = 9001,
                    },
                }
                assert(RecipeMatchesProfession({
                    professionData = {
                        professionInfo = {
                            profession = 9001,
                            professionID = 999999,
                        },
                    },
                }, PROFESSION_DEFS[1]), "CraftSim enum profession match failed")
                assert(RecipeMatchesProfession({
                    professionData = {
                        professionInfo = {
                            professionID = 773,
                        },
                    },
                }, PROFESSION_DEFS[1]), "CraftSim skill-line profession fallback failed")
                assert(not RecipeMatchesProfession({
                    professionData = {
                        professionInfo = {
                            profession = 9002,
                            professionID = 999999,
                        },
                    },
                }, PROFESSION_DEFS[1]), "CraftSim profession mismatch should not match")
            end)
            Enum = originalEnum
            assert(professionMatchOK, professionMatchErr)

            local originalCraftSimAPI = CraftSimAPI
            local originalGAMDB = GAM.db
            local originalSavedDB = GoldAdvisorMidnightDB
            local openSnapshotOK, openSnapshotErr = pcall(function()
                Enum = {
                    Profession = {
                        Inscription = 9001,
                    },
                }
                GAM.db = {
                    v2StatCache = {
                        profiles = {},
                    },
                }
                GoldAdvisorMidnightDB = GAM.db
                CraftSimAPI = {
                    GetRecipeData = function() end,
                    GetOpenRecipeData = function()
                        return {
                            recipeID = 12345,
                            supportsResourcefulness = true,
                            supportsMulticraft = true,
                            professionData = {
                                professionInfo = {
                                    profession = 9001,
                                    professionID = 2913,
                                },
                            },
                            professionStats = {
                                resourcefulness = FakeStat(15.778, 0.55),
                                multicraft = FakeStat(13.273, 0.25),
                            },
                            specializationData = {
                                professionStats = {
                                    resourcefulness = FakeStat(0, 0.55),
                                    multicraft = FakeStat(0, 0.25),
                                },
                            },
                        }
                    end,
                }
                local snapshots = Bridge.GetOpenProfessionStatSnapshots()
                local insc = snapshots and snapshots.insc
                assert(insc and insc.source == "craftsim-imported", "open CraftSim snapshot source failed")
                assert(insc.recipeID == 12345, "open CraftSim snapshot recipe id failed")
                assert(insc.profileKey == "insc_ink", "open CraftSim snapshot profile failed")
                assert(insc.multiPercent == 13.273, "open CraftSim multicraft snapshot failed")
                assert(insc.resPercent == 15.778, "open CraftSim resourcefulness snapshot failed")
                assert(insc.cachedSource == "craftsim-open", "open CraftSim snapshot cached source failed")
                assert(insc.totalStats
                        and insc.nodeStats
                        and insc.totalStats.resourcefulness.extra == 0.55
                        and insc.nodeStats.multicraft.extra == 0.25,
                    "open CraftSim stat breakdown snapshot failed")
                local cached = Bridge.GetCachedProfileStatSnapshots()
                assert(cached
                        and cached.insc_ink
                        and cached.insc_ink.source == "craftsim-imported"
                        and cached.insc_ink.multiPercent == 13.273,
                    "open CraftSim snapshot profile cache failed")
            end)
            CraftSimAPI = originalCraftSimAPI
            GAM.db = originalGAMDB
            GoldAdvisorMidnightDB = originalSavedDB
            Enum = originalEnum
            assert(openSnapshotOK, openSnapshotErr)

            local snapshot = {}
            ApplyProfessionSnapshot(snapshot, {
                supportsResourcefulness = true,
                supportsMulticraft = true,
                professionStats = {
                    resourcefulness = FakeStat(12.5, 0.99),
                    multicraft = FakeStat(25.0, 0.99),
                },
                specializationData = {
                    professionStats = {
                        resourcefulness = FakeStat(0, 0.35),
                        multicraft = FakeStat(0, 0.25),
                    },
                },
            }, true)

            assert(snapshot.resPercent == 12.5, "resourcefulness percent snapshot failed")
            assert(snapshot.multiPercent == 25.0, "multicraft percent snapshot failed")
            assert(snapshot.rsNode == 0.35 and snapshot.resExtra == 0.99,
                "resourcefulness extra snapshot failed")
            assert(snapshot.mcNode == 0.25 and snapshot.multiExtra == 0.99,
                "multicraft extra snapshot failed")
            assert(snapshot.totalStats
                    and snapshot.nodeStats
                    and snapshot.totalStats.resourcefulness.extra == 0.99
                    and snapshot.nodeStats.resourcefulness.extra == 0.35,
                "CraftSim learned node stat breakdown failed")
            assert(snapshot.resourcefulnessSaveBase == 0.32,
                "CraftSim resourcefulness constant snapshot failed")
            assert(snapshot.multicraftConstants and snapshot.multicraftConstants[2] == 1.83
                and snapshot.multicraftConstants.DEFAULT == 2.55,
                "CraftSim multicraft constants snapshot failed")
            local constants = Bridge.GetFormulaConstants()
            assert(constants and constants.resourcefulnessSaveBase == 0.32,
                "CraftSim formula constant reader failed")
            assert(constants.multicraftConstants and constants.multicraftConstants[2] == 1.83,
                "CraftSim formula multicraft constant reader failed")
        end)
        CraftSim = originalCraftSimForStats
        assert(statSnapshotOK, statSnapshotErr)

        local originalCraftSimForCache = CraftSim
        local originalCraftSimAPIForCache = CraftSimAPI
        local cacheAccessorOK, cacheAccessorErr = pcall(function()
            local fakeCraftSim = {
                DB = {
                    CRAFTER = {
                        GetCachedRecipeIDs = function(_, _, profession)
                            if profession == 9001 then
                                return { 71001, 71002 }
                            end
                            return nil
                        end,
                    },
                },
            }
            CraftSim = nil
            CraftSimAPI = {
                GetCraftSim = function()
                    return fakeCraftSim
                end,
            }
            local ids = GetCachedRecipeIDsForProfession(9001)
            assert(ids and ids[1] == 71001 and ids[2] == 71002,
                "CraftSim cached recipe repository accessor failed")
        end)
        CraftSim = originalCraftSimForCache
        CraftSimAPI = originalCraftSimAPIForCache
        assert(cacheAccessorOK, cacheAccessorErr)

        local strat = {
            id = "bridge_smoke",
            reagents = {
                { itemRef = "Original Reagent", itemIDs = { 51001, 51002 } },
            },
            output = { itemRef = "Output", itemIDs = { 52001, 52002 } },
            outputs = {
                { itemRef = "Output", itemIDs = { 52001, 52002 } },
            },
        }
        local metrics = {
            costReagents = {
                {
                    name = "Original Reagent",
                    itemID = 51001,
                    sourceItemIDs = { 51001, 51002 },
                    required = 1000,
                },
            },
            reagents = {
                {
                    name = "Expanded Leaf",
                    itemID = 59999,
                    sourceItemIDs = { 59999 },
                    required = 4000,
                },
            },
        }

        local entries = BuildPushOverrideEntries(strat, GAM.C.DEFAULT_PATCH, metrics)
        assert((FindPushOverrideEntry(entries, 51001) or {}).price == 4101,
            "qty-aware reagent push failed")
        assert((FindPushOverrideEntry(entries, 51002) or {}).price == 4102,
            "qty-aware reagent rank coverage failed")
        assert((FindPushOverrideEntry(entries, 52001) or {}).price == 5201,
            "output fill-qty push failed")
        assert((FindPushOverrideEntry(entries, 52002) or {}).price == 5202,
            "output rank coverage failed")
        assert(not FindPushOverrideEntry(entries, 59999),
            "VI leaf rows leaked into CraftSim push")

        fakePDB.priceOverrides[51001] = 9901
        entries = BuildPushOverrideEntries(strat, GAM.C.DEFAULT_PATCH, metrics)
        assert((FindPushOverrideEntry(entries, 51001) or {}).price == 9901,
            "manual override precedence failed")
        fakePDB.priceOverrides[51001] = nil

        GAM.C.VENDOR_PRICES[51001] = 8801
        entries = BuildPushOverrideEntries(strat, GAM.C.DEFAULT_PATCH, metrics)
        assert((FindPushOverrideEntry(entries, 51001) or {}).price == 8801,
            "vendor precedence failed")
        GAM.C.VENDOR_PRICES[51001] = nil

        local cheapestStrat = {
            id = "bridge_smoke_cheapest",
            reagents = {
                { itemRef = "Cheapest Pool", itemIDs = { 54001, 54002 } },
            },
            output = { itemRef = "Cheapest Output", itemIDs = { 53101 } },
            outputs = {
                { itemRef = "Cheapest Output", itemIDs = { 53101 } },
            },
        }
        local cheapestMetrics = {
            costReagents = {
                {
                    name = "Chosen Alternative",
                    itemID = 53001,
                    sourceItemIDs = { 53001, 53002 },
                    required = 25,
                    selectedAlternativeItemID = 53001,
                },
            },
            reagents = {
                {
                    name = "Expanded Cheapest Leaf",
                    itemID = 54999,
                    sourceItemIDs = { 54999 },
                    required = 100,
                },
            },
        }
        entries = BuildPushOverrideEntries(cheapestStrat, GAM.C.DEFAULT_PATCH, cheapestMetrics)
        assert((FindPushOverrideEntry(entries, 53001) or {}).price == 6301,
            "selected cheapest alternative price failed")
        assert((FindPushOverrideEntry(entries, 53002) or {}).price == 6302,
            "selected cheapest alternative rank coverage failed")
        assert(not FindPushOverrideEntry(entries, 54001) and not FindPushOverrideEntry(entries, 54002),
            "unselected cheapest pool entries leaked into push")
        assert(not FindPushOverrideEntry(entries, 54999),
            "expanded cheapest leaf leaked into push")

        local originalCraftSimForPush = CraftSim
        local originalCraftSimAPIForPush = CraftSimAPI
        local originalCraftSimDBForPush = CraftSimDB
        local pushAPIPathOK, pushAPIPathErr = pcall(function()
            local savedOverrides = {}
            local fakeCraftSim = {
                DB = {
                    PRICE_OVERRIDE = {
                        SaveGlobalOverride = function(_, overrideData)
                            savedOverrides[overrideData.itemID] = overrideData
                        end,
                    },
                },
            }
            CraftSimDB = {
                priceOverrideDB = {
                    data = {
                        globalOverrides = {},
                    },
                },
            }
            CraftSim = nil
            CraftSimAPI = {
                GetCraftSim = function()
                    return fakeCraftSim
                end,
            }

            local pushed = Bridge.PushStratPrices(strat, GAM.C.DEFAULT_PATCH, metrics)
            assert(pushed > 0, "CraftSim push API path pushed no overrides")
            assert(savedOverrides[51001] and savedOverrides[51001].price == 4101,
                "CraftSim SaveGlobalOverride API path failed")
            assert(not CraftSimDB.priceOverrideDB.data.globalOverrides[51001],
                "CraftSim SaveGlobalOverride API path should not require direct SavedVariables fallback")
        end)
        CraftSim = originalCraftSimForPush
        CraftSimAPI = originalCraftSimAPIForPush
        CraftSimDB = originalCraftSimDBForPush
        assert(pushAPIPathOK, pushAPIPathErr)
    end)

    RestoreState()
    return ok, err
end
