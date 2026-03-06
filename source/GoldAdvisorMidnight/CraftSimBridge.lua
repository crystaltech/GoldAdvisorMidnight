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
