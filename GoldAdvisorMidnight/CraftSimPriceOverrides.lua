-- GoldAdvisorMidnight/CraftSimPriceOverrides.lua
-- CraftSim price override push support.
-- Module: GAM.CraftSimPriceOverrides

local ADDON_NAME, GAM = ...
local Overrides = {}
GAM.CraftSimPriceOverrides = Overrides

function Overrides.Install(Bridge, deps)
    if type(Bridge) ~= "table" or type(deps) ~= "table" then
        return false, "missing-dependencies"
    end

    local GetOpts = deps.GetOpts
    local CraftSimDBAvailable = deps.CraftSimDBAvailable
    local GetCraftSimAddon = deps.GetCraftSimAddon

    local function GetResolvedItemIDs(item, pdb)
        if not item then return {} end
        local ids = item.itemIDs
        local label = item.name or item.itemRef
        if (not ids or #ids == 0) and label then
            ids = pdb.rankGroups[label] or {}
        end
        return ids or {}
    end

    local function NormalizeQuantity(qty)
        local n = tonumber(qty)
        if not n or n <= 0 then
            return nil
        end
        return math.max(1, math.floor(n + 0.5))
    end

    local function GetDirectOverridePrice(itemID, patchTag, qty)
        if not itemID then return nil end

        patchTag = patchTag or GAM.C.DEFAULT_PATCH
        local pdb = GAM:GetPatchDB(patchTag)
        if pdb.priceOverrides and pdb.priceOverrides[itemID] ~= nil then
            return pdb.priceOverrides[itemID]
        end

        if GAM.C.VENDOR_PRICES and GAM.C.VENDOR_PRICES[itemID] then
            return GAM.C.VENDOR_PRICES[itemID]
        end

        local targetQty = NormalizeQuantity(qty)
        if targetQty and GAM.AHScan and GAM.AHScan.ComputePriceForQty then
            local liveAvg = GAM.AHScan.ComputePriceForQty(itemID, targetQty)
            if liveAvg then
                return math.floor(liveAvg)
            end
        end

        if GAM.Pricing and GAM.Pricing.GetUnitPrice then
            return GAM.Pricing.GetUnitPrice(itemID)
        end
        return nil
    end

    local function AddPushOverrideEntry(entries, seen, itemID, price)
        if not itemID or seen[itemID] or not price or price <= 0 then
            return false
        end

        seen[itemID] = true
        entries[#entries + 1] = {
            itemID = itemID,
            price = price,
        }
        return true
    end

    local function GetOutputPushQty()
        local fillQty = tonumber(GetOpts().shallowFillQty) or GAM.C.DEFAULT_FILL_QTY
        return math.max(1, math.floor(fillQty + 0.5))
    end

    local function BuildPushOverrideEntries(strat, patchTag, metrics)
        patchTag = patchTag or GAM.C.DEFAULT_PATCH
        local pdb = GAM:GetPatchDB(patchTag)
        local active = (GAM.Pricing and GAM.Pricing.GetActiveRecipeView and GAM.Pricing.GetActiveRecipeView(strat)) or strat
        local entries = {}
        local seen = {}

        local function PushIDs(itemIDs, qty)
            for _, id in ipairs(itemIDs or {}) do
                AddPushOverrideEntry(entries, seen, id, GetDirectOverridePrice(id, patchTag, qty))
            end
        end

        local reagentRows = metrics and (metrics.recipeReagents or metrics.costReagents)
        if reagentRows and #reagentRows > 0 then
            for _, reagent in ipairs(reagentRows) do
                local itemIDs = reagent.sourceItemIDs
                if (not itemIDs or #itemIDs == 0) and reagent.itemID then
                    itemIDs = { reagent.itemID }
                end
                PushIDs(itemIDs, reagent.required)
            end
        else
            for _, reagent in ipairs(active.reagents or {}) do
                PushIDs(GetResolvedItemIDs(reagent, pdb), nil)
            end
        end

        local outputQty = GetOutputPushQty()
        local function PushOutput(item)
            PushIDs(GetResolvedItemIDs(item, pdb), outputQty)
        end

        PushOutput(active.output)
        if active.outputs and #active.outputs > 0 then
            for _, output in ipairs(active.outputs) do
                PushOutput(output)
            end
        else
            PushOutput(active.output)
        end

        return entries
    end

    local function FindPushOverrideEntry(entries, itemID)
        for _, entry in ipairs(entries or {}) do
            if entry.itemID == itemID then
                return entry
            end
        end
        return nil
    end

    -- PushStratPrices(strat, patchTag, metrics) -> pushed (number), err (string or nil)
    -- Writes direct AH-backed prices for this strat's active items into CraftSim
    -- global overrides, using CraftSim's override API when available.
    function Bridge.PushStratPrices(strat, patchTag, metrics)
        if not CraftSimDBAvailable() then
            return 0, "CraftSim not loaded"
        end
        if not strat then return 0, "no strat" end

        patchTag = patchTag or GAM.C.DEFAULT_PATCH
        if not metrics and GAM.PricingFacade and GAM.PricingFacade.CalculateCurrent then
            metrics = GAM.PricingFacade.CalculateCurrent(strat, patchTag)
        elseif not metrics then
            return 0, "canonical pricing unavailable"
        end

        CraftSimDB.priceOverrideDB = CraftSimDB.priceOverrideDB or {}
        CraftSimDB.priceOverrideDB.data = CraftSimDB.priceOverrideDB.data or {}
        local overrides = CraftSimDB.priceOverrideDB.data.globalOverrides or {}
        CraftSimDB.priceOverrideDB.data.globalOverrides = overrides

        local pushed = 0
        for _, entry in ipairs(BuildPushOverrideEntries(strat, patchTag, metrics)) do
            local overrideData = {
                itemID = entry.itemID,
                price = entry.price,
            }
            local savedByAPI = false
            local craftSim = GetCraftSimAddon()
            local repo = craftSim
                and craftSim.DB
                and craftSim.DB.PRICE_OVERRIDE
            if repo and type(repo.SaveGlobalOverride) == "function" then
                local ok = pcall(function()
                    repo:SaveGlobalOverride(overrideData)
                end)
                savedByAPI = ok and true or false
            end
            if not savedByAPI then
                overrides[entry.itemID] = overrideData
            end
            pushed = pushed + 1
        end

        return pushed, nil
    end

    Bridge._BuildPushOverrideEntries = BuildPushOverrideEntries
    Bridge._FindPushOverrideEntry = FindPushOverrideEntry
    return true
end
