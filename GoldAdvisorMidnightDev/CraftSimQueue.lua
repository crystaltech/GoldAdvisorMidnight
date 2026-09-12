-- GoldAdvisorMidnight/CraftSimQueue.lua
-- Validated adapter for CraftSim's CraftQueue API.  No queue writes occur
-- until every step has been resolved and accepted by CraftSim.

local ADDON_NAME, GAM = ...
local Queue = {}
GAM.CraftSimQueue = Queue
local queuedPlanKeys = {}

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

local function CurrentCrafter()
    local craftSim = GetCraftSimAddon()
    local util = craftSim and craftSim.UTIL
    local data
    if util and type(util.GetPlayerCrafterData) == "function" then
        local ok, result = pcall(function()
            return util:GetPlayerCrafterData()
        end)
        if ok and type(result) == "table" then
            data = result
        end
    end

    local name = data and data.name
    if not name and type(UnitNameUnmodified) == "function" then
        name = select(1, UnitNameUnmodified("player"))
    elseif not name and type(UnitName) == "function" then
        name = UnitName("player")
    end

    local realm = data and data.realm
    if not realm and type(GetNormalizedRealmName) == "function" then
        realm = GetNormalizedRealmName()
    end
    if not realm and type(GetRealmName) == "function" then
        realm = GetRealmName()
    end

    if not name or not realm then return nil end
    return { name = name, realm = realm,
        class = data and data.class
            or (type(UnitClass) == "function" and select(2, UnitClass("player")) or nil) }
end

local function RecipeID(step, strategy)
    return tonumber(step and (step.recipeID or step.recipeId))
        or tonumber(step and step.strategy and step.strategy.recipeID)
        or tonumber(strategy and strategy.recipeID)
end

local function CopyReagents(reagents)
    if type(reagents) ~= "table" then return nil end
    local out = {}
    for index, reagent in ipairs(reagents) do
        local ids = reagent.itemIDs
        local selectedID = tonumber(reagent.selectedItemID or reagent.resolvedItemID)
        local id = selectedID or tonumber(reagent.itemID or reagent.itemId)
        if not id and type(ids) == "table" and #ids == 1 then
            id = tonumber(ids[1])
        end
        -- Never turn an unresolved multi-rank pool into a queue entry for
        -- whichever item happens to be first in the source table.
        if type(ids) == "table" and #ids > 1 and not selectedID then
            return nil, string.format("reagent %d has no exact rank allocation", index)
        end
        local qty = tonumber(reagent.quantity or reagent.quantityPerCraft or reagent.qtyPerCraft)
        if not (id and qty and qty > 0) then
            return nil, string.format("reagent %d is incomplete", index)
        end
        out[#out + 1] = { itemID = id, quantity = qty, dataSlotIndex = reagent.dataSlotIndex }
    end
    return #out > 0 and out or nil
end

function Queue.IsAvailable()
    local craftsim = type(CraftSim) == "table" and CraftSim or nil
    local craftq = craftsim and craftsim.CRAFTQ
    return CraftSimAPI and type(CraftSimAPI.GetRecipeData) == "function"
        and craftq and type(craftq.AddRecipe) == "function"
end

function Queue.BuildQueueEntries(breakdown, plan, opts)
    opts = opts or {}
    if type(breakdown) ~= "table" then return nil, "missing breakdown" end
    plan = plan or (GAM.UI and GAM.UI.VIBreakdownPlan and GAM.UI.VIBreakdownPlan.Build(breakdown))
    local steps = breakdown.executionSteps
    if type(steps) ~= "table" or #steps == 0 then
        steps = plan and plan.craftSteps
    end
    if type(steps) ~= "table" or #steps == 0 then return nil, "no executable craft steps" end
    local strategy = opts.strategy
    local resolve = opts.resolveStrategy or function(id)
        return GAM.Importer and GAM.Importer.GetStratByID and GAM.Importer.GetStratByID(id)
    end
    local entries = {}
    for index, step in ipairs(steps) do
        local source = step.producerStratID and resolve(step.producerStratID) or strategy
        local recipeID = RecipeID(step, source)
        local amount = math.floor(tonumber(step.craftsExecution or step.amount) or 0)
        if amount <= 0 then return nil, string.format("step %d has no execution quantity", index) end
        if not recipeID then return nil, string.format("step %d (%s) has no recipe ID", index, tostring(step.name or "?")) end
        local rawReagents = step.reagents or (source and source.reagents)
        local reagents, reagentErr = CopyReagents(rawReagents)
        if rawReagents and not reagents then
            return nil, string.format("step %d (%s): %s", index,
                tostring(step.name or "?"), tostring(reagentErr or "invalid reagent mix"))
        end
        entries[#entries + 1] = {
            step = step, strategy = source, recipeID = recipeID, amount = amount,
            reagents = reagents,
        }
    end
    return entries
end

function Queue.Preflight(breakdown, plan, opts)
    opts = opts or {}
    if not Queue.IsAvailable() then
        return nil, "CraftSim API is unavailable"
    end
    local craftsim = type(CraftSim) == "table" and CraftSim or nil
    local craftq = craftsim and craftsim.CRAFTQ
    if not (craftq and type(craftq.AddRecipe) == "function") then return nil, "CraftSim CraftQueue is unavailable" end
    local entries, err = Queue.BuildQueueEntries(breakdown, plan, opts)
    if not entries then return nil, err end
    local crafter = opts.crafterData or CurrentCrafter()
    if not crafter then return nil, "current crafter identity is unavailable" end
    local out = {}
    for index, entry in ipairs(entries) do
        local ok, data = pcall(function() return CraftSimAPI:GetRecipeData({ recipeID = entry.recipeID, crafterData = crafter, forceCache = true }) end)
        if not ok or not data then return nil, string.format("step %d recipe %d could not be loaded", index, entry.recipeID) end
        local queueable = not craftq.IsRecipeQueueable or craftq:IsRecipeQueueable(data)
        if not queueable then return nil, string.format("step %d recipe %d is not queueable", index, entry.recipeID) end
        if entry.reagents and type(data.SetReagents) == "function" then
            local setOK, setErr = pcall(function() data:SetReagents(entry.reagents) end)
            if not setOK then return nil, string.format("step %d reagent mix rejected: %s", index, tostring(setErr)) end
        end
        out[#out + 1] = {
            recipeData = data, amount = entry.amount, step = entry.step,
            reagents = entry.reagents,
        }
    end
    return out
end

local function PlanKey(breakdown, entries, crafter)
    local parts = {
        tostring(breakdown and breakdown.stratID or ""),
        tostring(breakdown and breakdown.patchTag or ""),
        tostring(crafter and crafter.name or ""),
        tostring(crafter and crafter.realm or ""),
    }
    for _, entry in ipairs(entries or {}) do
        parts[#parts + 1] = tostring(entry.recipeData and entry.recipeData.recipeID or "")
            .. ":" .. tostring(entry.amount or 0)
        for _, reagent in ipairs(entry.reagents or {}) do
            parts[#parts + 1] = ":" .. tostring(reagent.itemID) .. "=" .. tostring(reagent.quantity)
        end
        parts[#parts + 1] = ";"
    end
    return table.concat(parts, "|")
end

function Queue.QueueBreakdown(breakdown, plan, opts)
    opts = opts or {}
    local entries, err = Queue.Preflight(breakdown, plan, opts)
    if not entries then return 0, err end
    local crafter = opts.crafterData or CurrentCrafter()
    local key = PlanKey(breakdown, entries, crafter)
    if queuedPlanKeys[key] then
        return 0, "plan already queued"
    end
    local craftq = CraftSim.CRAFTQ
    local queued = 0
    for index, entry in ipairs(entries) do
        local ok, callErr = pcall(function() craftq:AddRecipe({ recipeData = entry.recipeData, amount = entry.amount }) end)
        if not ok then return queued, string.format("queue write failed at step %d: %s", index, tostring(callErr)) end
        queued = queued + 1
    end
    queuedPlanKeys[key] = true
    return queued
end

return Queue
