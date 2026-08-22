-- GoldAdvisorMidnight/CommodityCatalog.lua
-- Single runtime authority for the generated commodity-only product boundary.
-- Module: GAM.CommodityCatalog

local ADDON_NAME, GAM = ...
local Catalog = {}
GAM.CommodityCatalog = Catalog

local manifest = GAM_COMMODITY_MANIFEST or {}
local commodityItemIDs = manifest.itemIDs or {}

local function CopyFilteredItemIDs(itemIDs)
    local filtered = {}
    if type(itemIDs) ~= "table" then
        return filtered
    end
    for _, itemID in ipairs(itemIDs) do
        itemID = tonumber(itemID)
        if itemID and commodityItemIDs[itemID] then
            filtered[#filtered + 1] = itemID
        end
    end
    return filtered
end

local function GetOutputs(container)
    if type(container) ~= "table" then
        return nil
    end
    if type(container.outputs) == "table" and #container.outputs > 0 then
        return container.outputs
    end
    if type(container.output) == "table" then
        return { container.output }
    end
    return nil
end

local function OutputsAreEligible(container)
    local outputs = GetOutputs(container)
    if not outputs then
        return false, "missing outputs"
    end
    for outputIndex, output in ipairs(outputs) do
        if #CopyFilteredItemIDs(output and output.itemIDs) == 0 then
            return false, string.format("output %d has no commodity item IDs", outputIndex)
        end
    end
    return true
end

function Catalog.IsItemID(itemID)
    itemID = tonumber(itemID)
    return itemID ~= nil and commodityItemIDs[itemID] == true
end

function Catalog.FilterItemIDs(itemIDs)
    return CopyFilteredItemIDs(itemIDs)
end

function Catalog.IsStrategyEligible(strategy)
    if type(strategy) ~= "table" then
        return false, "strategy is not a table"
    end
    if strategy.disabledReason then
        return false, "strategy is disabled"
    end

    local eligible, reason = OutputsAreEligible(strategy)
    if not eligible then
        return false, reason
    end

    for variantKey, variant in pairs(strategy.rankVariants or {}) do
        eligible, reason = OutputsAreEligible(variant)
        if not eligible then
            return false, string.format("variant %s: %s", tostring(variantKey), reason)
        end
    end

    return true
end


function Catalog.GetManifest()
    return manifest
end

function Catalog.GetStrategyCount()
    return tonumber(manifest.strategyCount) or 0
end

function Catalog.GetProfessionCounts()
    return manifest.professionCounts or {}
end

function Catalog.GetSourceInfo()
    return manifest.source or {}
end
