-- GoldAdvisorMidnight/UI/VIBreakdownPlan.lua
-- Pure projection of the VI pricing tree into an executable shopping/crafting plan.
-- Module: GAM.UI.VIBreakdownPlan

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local Plan = {}
GAM.UI.VIBreakdownPlan = Plan

local function CeilWhole(value)
    value = tonumber(value) or 0
    if value <= 0 then
        return 0
    end
    return math.ceil(value - 1e-9)
end

local function StableEntryKey(entry, prefix)
    local identity
    if prefix == "craft" then
        identity = entry and (entry.producerStratID or entry.itemID or entry.name)
    else
        identity = entry and (entry.itemID or entry.name)
    end
    return tostring(prefix or "entry") .. ":" .. tostring(identity or "unknown")
end

local function MergeIDs(target, source)
    local seen = {}
    for _, itemID in ipairs(target) do
        seen[itemID] = true
    end
    for _, itemID in ipairs(source or {}) do
        if itemID and not seen[itemID] then
            seen[itemID] = true
            target[#target + 1] = itemID
        end
    end
end

local function AddPurchase(groups, order, entry, purchaseSource, fallbackUnitPrice)
    local key = StableEntryKey(entry, purchaseSource)
    local group = groups[key]
    if not group then
        group = {
            kind = "buy",
            purchaseSource = purchaseSource,
            name = entry.name,
            itemID = entry.itemID,
            itemIDs = {},
            scanItemIDs = {},
            requiredRaw = 0,
            have = 0,
            _pricedRequired = 0,
            _fullCost = 0,
            effectiveMissingPrice = false,
            hasStale = false,
            excludedFromEstimate = false,
        }
        groups[key] = group
        order[#order + 1] = key
    end

    group.requiredRaw = group.requiredRaw + (tonumber(entry.requiredRaw or entry.required) or 0)
    group.have = math.max(group.have, tonumber(entry.have) or 0)
    group._pricedRequired = group._pricedRequired + (tonumber(entry.requiredRaw or entry.required) or 0)
    local entryUnitPrice = entry.effectiveUnitPrice or entry.unitPrice or fallbackUnitPrice
    group._fullCost = group._fullCost
        + (tonumber(entry.effectiveTotalCostFull or entry.totalCostFull)
            or (entryUnitPrice and entryUnitPrice * (tonumber(entry.requiredRaw or entry.required) or 0)) or 0)
    group.effectiveMissingPrice = group.effectiveMissingPrice
        or entry.effectiveMissingPrice or entry.missingPrice
    group.hasStale = group.hasStale or entry.hasStale or entry.isStale
    group.excludedFromEstimate = group.excludedFromEstimate or entry.excludeFromCost
    group.effectiveUnitPrice = group.effectiveUnitPrice or entryUnitPrice
    MergeIDs(group.itemIDs,
        entry.itemIDs or entry.sourceItemIDs or (entry.itemID and { entry.itemID }) or {})
    MergeIDs(group.scanItemIDs, entry.scanItemIDs or {})
end

local function FinishPurchases(groups, order)
    local result = {}
    for _, key in ipairs(order) do
        local group = groups[key]
        group.required = CeilWhole(group.requiredRaw)
        group.needToBuy = math.max(0, group.required - math.floor(group.have))
        if group._pricedRequired > 0 and group._fullCost > 0 then
            group.effectiveUnitPrice = group._fullCost / group._pricedRequired
        end
        if group.effectiveUnitPrice then
            group.effectiveTotalCostFull = group.effectiveUnitPrice * group.requiredRaw
            group.effectiveTotalCostToBuy = group.effectiveUnitPrice * group.needToBuy
        elseif group.needToBuy > 0 then
            group.effectiveMissingPrice = true
        end
        group._pricedRequired = nil
        group._fullCost = nil
        if group.needToBuy > 0 then
            result[#result + 1] = group
        end
    end
    table.sort(result, function(left, right)
        return tostring(left.name or ""):lower() < tostring(right.name or ""):lower()
    end)
    return result
end

local function AddCraft(groups, order, entry)
    local key = StableEntryKey(entry, "craft")
    local group = groups[key]
    if not group then
        group = {
            kind = "craft",
            name = entry.name,
            itemID = entry.itemID,
            producerStratID = entry.producerStratID,
            producerStratName = entry.producerStratName,
            gearModeRequested = entry.gearModeRequested,
            gearModeResolved = entry.gearModeResolved,
            gearPresetMissing = entry.gearPresetMissing and true or false,
            expectedOutputPerCraft = entry.expectedOutputPerCraft,
            requiredRaw = 0,
            craftsEconomic = 0,
            chainTotalCostFull = 0,
            hasMissingPrice = false,
            hasStale = false,
            _dependencyKeys = {},
            _dependencyOrder = {},
            selectedInputNames = {},
            _selectedInputSet = {},
        }
        groups[key] = group
        order[#order + 1] = key
    end
    group.requiredRaw = group.requiredRaw + (tonumber(entry.requiredRaw or entry.required) or 0)
    group.craftsEconomic = group.craftsEconomic + (tonumber(entry.craftsEconomic) or 0)
    group.chainTotalCostFull = group.chainTotalCostFull + (tonumber(entry.chainTotalCostFull) or 0)
    group.hasMissingPrice = group.hasMissingPrice or entry.hasMissingPrice
    group.hasStale = group.hasStale or entry.hasStale
    for _, selectedName in ipairs(entry.selectedInputNames or {}) do
        if selectedName and not group._selectedInputSet[selectedName] then
            group._selectedInputSet[selectedName] = true
            group.selectedInputNames[#group.selectedInputNames + 1] = selectedName
        end
    end
    return key, group
end

local function BuildCraftSteps(breakdown)
    local entries = breakdown.entries or {}
    local groups, order, entryGroupKeys = {}, {}, {}

    for index, entry in ipairs(entries) do
        if entry.kind == "craft" and not entry.excludeFromCost then
            local key = AddCraft(groups, order, entry)
            entryGroupKeys[index] = key
        end
    end

    for parentIndex, parent in ipairs(entries) do
        local parentKey = entryGroupKeys[parentIndex]
        local parentGroup = parentKey and groups[parentKey]
        if parentGroup then
            for _, childIndex in ipairs(parent.childIndices or {}) do
                local childKey = entryGroupKeys[childIndex]
                if childKey and childKey ~= parentKey and not parentGroup._dependencyKeys[childKey] then
                    parentGroup._dependencyKeys[childKey] = true
                    parentGroup._dependencyOrder[#parentGroup._dependencyOrder + 1] = childKey
                end
            end
        end
    end

    local result, visited, visiting = {}, {}, {}
    local function Visit(key)
        if visited[key] or visiting[key] then
            return
        end
        visiting[key] = true
        local group = groups[key]
        for _, dependencyKey in ipairs((group and group._dependencyOrder) or {}) do
            Visit(dependencyKey)
        end
        visiting[key] = nil
        visited[key] = true
        if group then
            group.craftsExecution = CeilWhole(group.craftsEconomic)
            group.required = CeilWhole(group.requiredRaw)
            group._dependencyKeys = nil
            group._dependencyOrder = nil
            group._selectedInputSet = nil
            if #group.selectedInputNames == 0 then
                group.selectedInputNames = nil
            end
            result[#result + 1] = group
        end
    end
    for _, key in ipairs(order) do
        Visit(key)
    end
    return result
end

local function BuildFinalCraft(breakdown)
    local craftPlan = tonumber(breakdown.finalCraftsEconomic or breakdown.crafts) or 0
    local craftCount = tonumber(breakdown.finalCraftsExecution)
    if craftCount == nil then
        craftCount = CeilWhole(craftPlan)
    end
    return {
        kind = "craft",
        isFinalCraft = true,
        name = breakdown.finalOutputName or breakdown.stratName or "Final Output",
        itemID = breakdown.finalOutputItemID,
        requiredRaw = breakdown.finalExpectedOutput or breakdown.startingAmount or craftCount,
        required = CeilWhole(breakdown.finalExpectedOutput or breakdown.startingAmount or craftCount),
        craftsEconomic = craftPlan,
        craftsExecution = math.max(0, math.floor(craftCount)),
        chainTotalCostFull = breakdown.totalCostFull,
        hasMissingPrice = breakdown.totalCostFull == nil,
        gearModeRequested = breakdown.finalGearModeRequested,
        gearModeResolved = breakdown.finalGearModeResolved,
        gearPresetMissing = breakdown.finalGearPresetMissing and true or false,
    }
end

local function AddSection(rows, sectionKey, label, entries)
    if #entries == 0 then
        return
    end
    rows[#rows + 1] = {
        rowType = "section",
        sectionKey = sectionKey,
        name = label,
        count = #entries,
    }
    for _, entry in ipairs(entries) do
        rows[#rows + 1] = entry
    end
end

function Plan.Build(breakdown, vendorPrices, labels)
    breakdown = breakdown or {}
    vendorPrices = vendorPrices or {}
    labels = labels or {}

    local vendorGroups, vendorOrder = {}, {}
    local auctionGroups, auctionOrder = {}, {}
    local purchaseEntries = breakdown.shoppingReagents
    if type(purchaseEntries) ~= "table" or #purchaseEntries == 0 then
        purchaseEntries = breakdown.entries or {}
    end
    for _, entry in ipairs(purchaseEntries) do
        if entry.kind ~= "craft" then
            local isVendor = entry.itemID and vendorPrices[entry.itemID] ~= nil
            if isVendor then
                AddPurchase(vendorGroups, vendorOrder, entry, "vendor", vendorPrices[entry.itemID])
            else
                AddPurchase(auctionGroups, auctionOrder, entry, "auction")
            end
        end
    end

    local vendorBuys = FinishPurchases(vendorGroups, vendorOrder)
    local auctionBuys = FinishPurchases(auctionGroups, auctionOrder)
    local craftSteps = BuildCraftSteps(breakdown)
    craftSteps[#craftSteps + 1] = BuildFinalCraft(breakdown)

    local rows = {}
    AddSection(rows, "vendor", labels.vendor or "Vendor Purchases", vendorBuys)
    AddSection(rows, "auction", labels.auction or "Auction House Purchases", auctionBuys)
    AddSection(rows, "craft", labels.craft or "Crafting Order", craftSteps)
    for index, entry in ipairs(craftSteps) do
        entry.craftOrder = index
    end

    return {
        vendorBuys = vendorBuys,
        auctionBuys = auctionBuys,
        craftSteps = craftSteps,
        rows = rows,
    }
end

return Plan
