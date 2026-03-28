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

local PROF_ID_TO_KEY

-- ===== Detection =====
local function CraftSimAvailable()
    return CraftSimAPI ~= nil
        and type(CraftSimAPI.GetRecipeData) == "function"
        and type(CraftSimAPI.GetOpenRecipeData) == "function"
end

-- ===== Price lookup via CraftSim =====

-- GetPrice(itemID) → price in copper, or nil
-- Uses CraftSim.PRICE_SOURCE (private struct, subject to change between CraftSim versions).
function Bridge.GetPrice(itemID)
    if not CraftSimAvailable() then return nil end
    if not itemID then return nil end

    local ok, price = pcall(function()
        if CraftSim and CraftSim.PRICE_SOURCE then
            return CraftSim.PRICE_SOURCE:GetMinBuyoutByItemID(itemID)
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
        GAM.Log.Debug("CraftSimBridge: workbook defaults remain authoritative; cached CraftSim stats can be imported for compare/sync.")
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
    return (UnitName("player") or "Unknown") .. "-" .. (GetRealmName() or "Unknown")
end

local function GetPlayerCrafterData()
    return {
        name = UnitName("player"),
        realm = GetRealmName(),
        class = select(2, UnitClass("player")),
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
    local crafterData = GetCachedCrafterData()
    local cached = crafterData and crafterData.cachedRecipeIDs and crafterData.cachedRecipeIDs[professionID]
    if type(cached) == "table" then
        return cached
    end
    return {}
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
        multiFields = { "engMulti" },
        resFields = { "engRes" },
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

local function GetExportProfessionStats(recipeData)
    if not recipeData or not recipeData.professionStats then return nil end

    local ok, exportStats = pcall(function()
        if type(recipeData.professionStats.Copy) == "function" then
            local copy = recipeData.professionStats:Copy()
            if copy and type(copy.subtract) == "function"
                    and recipeData.buffData
                    and recipeData.buffData.professionStats then
                copy:subtract(recipeData.buffData.professionStats)
            end
            return copy
        end
        return recipeData.professionStats
    end)

    if ok then
        return exportStats
    end
    return recipeData.professionStats
end

local function ApplyProfessionSnapshot(snapshot, recipeData, wantsMulti)
    if not snapshot or not recipeData then return end

    local exportStats = GetExportProfessionStats(recipeData)
    if exportStats then
        if snapshot.resPercent == nil then
            local supportsRes = recipeData.supportsResourcefulness
            local resStat = exportStats.resourcefulness
            local resValue = resStat and tonumber(resStat.value)
            if supportsRes or resValue ~= nil then
                snapshot.resPercent = RoundDecimal(GetStatPercent(resStat) or 0, 3)
            end
        end

        if wantsMulti and snapshot.multiPercent == nil then
            local supportsMulti = recipeData.supportsMulticraft
            local mcStat = exportStats.multicraft
            local mcValue = mcStat and tonumber(mcStat.value)
            if supportsMulti or mcValue ~= nil then
                snapshot.multiPercent = RoundDecimal(GetStatPercent(mcStat) or 0, 3)
            end
        end
    end

    local specStats = recipeData.specializationData and recipeData.specializationData.professionStats
    if specStats then
        if snapshot.rsNode == nil then
            snapshot.rsNode = math.max(0, math.min(1, GetExtraValue(specStats.resourcefulness) or 0))
        end
        if wantsMulti and snapshot.mcNode == nil then
            snapshot.mcNode = math.max(0, math.min(1, GetExtraValue(specStats.multicraft) or 0))
        end
    end
end

local function BuildProfessionSnapshot(professionID, wantsMulti)
    local snapshot = {}
    local seenRecipeIDs = {}
    local openRecipeData = GetOpenRecipeData()

    local function capture(recipeData)
        if not recipeData then return false end
        local info = recipeData.professionData and recipeData.professionData.professionInfo
        if not info or info.profession ~= professionID then
            return false
        end

        if recipeData.recipeID then
            seenRecipeIDs[recipeData.recipeID] = true
        end

        ApplyProfessionSnapshot(snapshot, recipeData, wantsMulti)
        return snapshot.resPercent ~= nil
            and ((not wantsMulti) or snapshot.multiPercent ~= nil)
            and snapshot.rsNode ~= nil
            and ((not wantsMulti) or snapshot.mcNode ~= nil)
    end

    if capture(openRecipeData) then
        return snapshot
    end

    for _, recipeID in ipairs(GetCachedRecipeIDsForProfession(professionID)) do
        if not seenRecipeIDs[recipeID] then
            local recipeData = BuildCachedRecipeData(recipeID)
            if capture(recipeData) then
                return snapshot
            end
        end
    end

    return next(snapshot) and snapshot or nil
end

local function GetProfessionSyncDataFromCraftSim()
    if not CraftSimDBAvailable() then return {} end

    local syncData = {}
    for professionID, profKey in pairs(PROF_ID_TO_KEY) do
        local fieldInfo = PROF_KEY_TO_FIELDS[profKey]
        local wantsMulti = fieldInfo and fieldInfo.multiFields and #fieldInfo.multiFields > 0
        local snapshot = BuildProfessionSnapshot(professionID, wantsMulti)
        if snapshot then
            syncData[profKey] = snapshot
        end
    end
    return syncData
end

-- ===== Node bonus reader =====

-- Maps WoW professionID → GAM profession key (used for DB node bonus fields).
PROF_ID_TO_KEY = {
    [773] = "insc",  -- Inscription
    [755] = "jc",    -- Jewelcrafting
    [333] = "ench",  -- Enchanting
    [171] = "alch",  -- Alchemy
    [197] = "tail",  -- Tailoring
    [164] = "bs",    -- Blacksmithing
    [165] = "lw",    -- Leatherworking
    [202] = "eng",   -- Engineering
}

-- GetAllProfessionNodeBonuses() → { profKey → { rsNode, mcNode } } or {}
-- Reconstructs per-profession spec extra values from CraftSim's cached recipe data.
function Bridge.GetAllProfessionNodeBonuses()
    local result = {}
    for professionID, profKey in pairs(PROF_ID_TO_KEY) do
        local snapshot = BuildProfessionSnapshot(professionID, true)
        if snapshot and (snapshot.rsNode ~= nil or snapshot.mcNode ~= nil) then
            result[profKey] = {
                rsNode = math.max(0, math.min(1, tonumber(snapshot.rsNode) or 0)),
                mcNode = math.max(0, math.min(1, tonumber(snapshot.mcNode) or 0)),
            }
        end
    end
    return result
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
-- Reads CraftSim spec data and updates per-profession node bonus DB fields.
-- Returns 0 if CraftSim data is unavailable.
function Bridge.SyncNodeBonusesFromCraftSim()
    local count = Bridge.SyncOptionsFromCraftSim()
    return count
end

-- PushStratPrices(strat, patchTag) → pushed (number), err (string or nil)
-- Writes every cached AH price for this strat's items into CraftSim's global
-- price overrides (CraftSimDB.priceOverrideDB.data.globalOverrides).
-- Covers all reagent itemIDs and all output itemIDs (all ranks).
function Bridge.PushStratPrices(strat, patchTag)
    if not CraftSimDBAvailable() then
        return 0, "CraftSim not loaded"
    end
    if not strat then return 0, "no strat" end

    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GAM:GetPatchDB(patchTag)
    local active = (GAM.Pricing and GAM.Pricing.GetActiveRecipeView and GAM.Pricing.GetActiveRecipeView(strat)) or strat

    -- Ensure DB structure exists
    CraftSimDB.priceOverrideDB            = CraftSimDB.priceOverrideDB or {}
    CraftSimDB.priceOverrideDB.data       = CraftSimDB.priceOverrideDB.data or {}
    local overrides = CraftSimDB.priceOverrideDB.data.globalOverrides or {}
    CraftSimDB.priceOverrideDB.data.globalOverrides = overrides

    local pushed = 0
    local pushedIDs = {}

    local function PushItem(item)
        if not item then return end
        local ids = item.itemIDs
        if (not ids or #ids == 0) and item.name then
            ids = pdb.rankGroups[item.name] or {}
        end
        if not ids then return end
        for _, id in ipairs(ids) do
            if not pushedIDs[id] then
                local price = GAM.Pricing.GetUnitPrice(id)
                if price and price > 0 then
                    pushedIDs[id] = true
                    overrides[id] = { itemID = id, price = price }
                    pushed = pushed + 1
                end
            end
        end
    end

    -- Push the active strat item set (respecting rank policy), not expanded raw-mat
    -- metrics, so CraftSim overrides stay attached to the strat's actual reagent items.
    for _, r in ipairs(active.reagents or {}) do
        PushItem(r)
    end
    PushItem(active.output)
    if active.outputs and #active.outputs > 0 then
        for _, o in ipairs(active.outputs) do PushItem(o) end
    else
        PushItem(active.output)
    end

    return pushed, nil
end
