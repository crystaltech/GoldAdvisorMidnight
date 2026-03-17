-- GoldAdvisorMidnight/CraftSimBridge.lua
-- Optional CraftSim integration. Safe detection — never errors if absent.
-- Module: GAM.CraftSimBridge

local ADDON_NAME, GAM = ...
local Bridge = {}
GAM.CraftSimBridge = Bridge

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
        GAM.Log.Debug("CraftSimBridge: workbook defaults remain authoritative; node bonuses are available for manual compare/import only.")
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

-- ===== Node bonus reader =====

-- Maps WoW professionID → GAM profession key (used for DB node bonus fields).
local PROF_ID_TO_KEY = {
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
-- Reads per-profession Rs/MC spec node bonuses from CraftSimDB for the current
-- character. Returns decimal 0–1 values clamped to [0,1].
-- Returns an empty table if CraftSimDB is unavailable or has no data for this char.
function Bridge.GetAllProfessionNodeBonuses()
    if not CraftSimDBAvailable() then return {} end
    local uid = UnitName("player") .. "-" .. GetRealmName()
    local specData = CraftSimDB.crafterDB
                     and CraftSimDB.crafterDB.data
                     and CraftSimDB.crafterDB.data[uid]
                     and CraftSimDB.crafterDB.data[uid].specializationData
    if not specData then return {} end

    local result = {}
    for recipeID, entry in pairs(specData) do
        if entry and entry.professionStats then
            local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
            local profKey = ok and info and PROF_ID_TO_KEY[info.professionID]
            if profKey and not result[profKey] then
                local ps = entry.professionStats
                local rsNode = ps.resourcefulness
                               and ps.resourcefulness.extraValues
                               and ps.resourcefulness.extraValues[1]
                local mcNode = ps.multicraft
                               and ps.multicraft.extraValues
                               and ps.multicraft.extraValues[1]
                result[profKey] = {
                    rsNode = math.max(0, math.min(1, tonumber(rsNode) or 0)),
                    mcNode = math.max(0, math.min(1, tonumber(mcNode) or 0)),
                }
            end
        end
    end
    return result
end

-- SyncNodeBonusesFromCraftSim() → count (number of professions updated)
-- Reads CraftSim spec data and updates per-profession node bonus DB fields.
-- Returns 0 if CraftSim data is unavailable.
function Bridge.SyncNodeBonusesFromCraftSim()
    local bonuses = Bridge.GetAllProfessionNodeBonuses()
    local count   = 0
    local opts    = GAM.db and GAM.db.options
    if not opts then return 0 end

    for profKey, data in pairs(bonuses) do
        local mcField = profKey .. "McNode"
        local rsField = profKey .. "RsNode"
        -- Store as integer percent (0–100) to match the existing DB convention
        opts[mcField] = math.floor(data.mcNode * 100 + 0.5)
        opts[rsField] = math.floor(data.rsNode * 100 + 0.5)
        count = count + 1
    end
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

    -- Ensure DB structure exists
    CraftSimDB.priceOverrideDB            = CraftSimDB.priceOverrideDB or {}
    CraftSimDB.priceOverrideDB.data       = CraftSimDB.priceOverrideDB.data or {}
    local overrides = CraftSimDB.priceOverrideDB.data.globalOverrides or {}
    CraftSimDB.priceOverrideDB.data.globalOverrides = overrides

    local pushed = 0

    local function PushItem(item)
        if not item then return end
        local ids = item.itemIDs
        if (not ids or #ids == 0) and item.name then
            ids = pdb.rankGroups[item.name] or {}
        end
        if not ids then return end
        for _, id in ipairs(ids) do
            local price = GAM.Pricing.GetUnitPrice(id)
            if price and price > 0 then
                overrides[id] = { itemID = id, price = price }
                pushed = pushed + 1
            end
        end
    end

    for _, r in ipairs(strat.reagents or {}) do
        PushItem(r)
    end
    if strat.outputs and #strat.outputs > 0 then
        for _, o in ipairs(strat.outputs) do PushItem(o) end
    else
        PushItem(strat.output)
    end

    return pushed, nil
end
