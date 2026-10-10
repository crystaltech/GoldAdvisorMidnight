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

        local manual = GAM.Pricing and GAM.Pricing.GetPriceOverride
            and GAM.Pricing.GetPriceOverride(itemID, patchTag)
        if manual ~= nil then
            return manual
        end

        local vendorPrice = GAM.VendorPrices and GAM.VendorPrices.GetPrice
            and GAM.VendorPrices.GetPrice(itemID)
            or (GAM.C.VENDOR_PRICES and GAM.C.VENDOR_PRICES[itemID])
        if vendorPrice then
            return vendorPrice
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
        return GAM.C.MARKET_SAMPLE_UNITS or 50
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

    -- One global (material) override, through CraftSim's repository when it
    -- has one, else straight into its saved table.
    local function SaveOverride(itemID, price)
        CraftSimDB.priceOverrideDB = CraftSimDB.priceOverrideDB or {}
        CraftSimDB.priceOverrideDB.data = CraftSimDB.priceOverrideDB.data or {}
        local overrides = CraftSimDB.priceOverrideDB.data.globalOverrides or {}
        CraftSimDB.priceOverrideDB.data.globalOverrides = overrides
        local overrideData = { itemID = itemID, price = price }
        local craftSim = GetCraftSimAddon()
        local repo = craftSim and craftSim.DB and craftSim.DB.PRICE_OVERRIDE
        if repo and type(repo.SaveGlobalOverride) == "function"
                and pcall(function() repo:SaveGlobalOverride(overrideData) end) then
            return
        end
        overrides[itemID] = overrideData
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

        local pushed = 0
        for _, entry in ipairs(BuildPushOverrideEntries(strat, patchTag, metrics)) do
            SaveOverride(entry.itemID, entry.price)
            pushed = pushed + 1
        end
        if pushed > 0 then Bridge.RefreshCraftSim() end
        return pushed, nil
    end

    -- CraftSim reads overrides whenever it prices a recipe; this is the event
    -- its own Price Overrides window fires after a change, so the recipe on
    -- screen is worked out again (others when they are opened).
    function Bridge.RefreshCraftSim()
        local craftSim = GetCraftSimAddon()
        local gutil = craftSim and craftSim.GUTIL
        if gutil and type(gutil.TriggerCustomEvent) == "function" then
            pcall(gutil.TriggerCustomEvent, gutil, "CRAFTSIM_RECIPE_DATA_MODIFIED")
        end
    end

    -- Settings > CraftSim (off by default): after a scan, send the material
    -- prices that scan read. Only strategy materials; sale prices are left
    -- to CraftSim. Overrides stay in CraftSim until replaced or cleared there.
    function Bridge.OnScanComplete(pricedItems)
        local opts = GetOpts and GetOpts() or {}
        if opts.craftSimAutoPush ~= true or type(pricedItems) ~= "table" or not CraftSimDBAvailable() then
            return 0
        end
        local materials = {}
        for _, strat in ipairs(GAM.Importer and GAM.Importer.GetAllStrats and GAM.Importer.GetAllStrats() or {}) do
            for _, reagent in ipairs(strat.reagents or {}) do
                for _, id in ipairs(reagent.itemIDs or {}) do materials[id] = true end
                for _, alternative in ipairs(reagent.cheapestOf or {}) do
                    for _, id in ipairs(alternative.itemIDs or {}) do materials[id] = true end
                end
            end
        end
        local pushed = 0
        for itemID in pairs(pricedItems) do
            if materials[itemID] then
                local price = GetDirectOverridePrice(itemID, GAM.C.DEFAULT_PATCH, GetOutputPushQty())
                if price and price > 0 then
                    SaveOverride(itemID, price)
                    pushed = pushed + 1
                end
            end
        end
        if pushed > 0 then
            Bridge.RefreshCraftSim()
            if GAM.Log and GAM.Log.Info then GAM.Log.Info("CraftSim: sent %d material prices from this scan.", pushed) end
            print("|cffff8800[GAM]|r " .. string.format((GAM.L and GAM.L["MSG_CRAFTSIM_AUTO_PUSHED"])
                or "Sent %d material prices to CraftSim.", pushed))
        end
        return pushed
    end

    -- What PushStratPrices needs: CraftSim's saved data, not its full API.
    function Bridge.CanPushPrices()
        return CraftSimDBAvailable() and true or false
    end

    Bridge._BuildPushOverrideEntries = BuildPushOverrideEntries
    Bridge._FindPushOverrideEntry = FindPushOverrideEntry
    return true
end
