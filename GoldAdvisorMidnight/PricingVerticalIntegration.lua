-- GoldAdvisorMidnight/PricingVerticalIntegration.lua
-- Recursive producer graph, owned-inventory consumption, and VI display planning.
-- Module: GAM.PricingVerticalIntegration

local ADDON_NAME, GAM = ...
local VerticalIntegration = {}
GAM.PricingVerticalIntegration = VerticalIntegration

function VerticalIntegration.Install(Pricing, deps)
    assert(type(Pricing) == "table", "Pricing facade is required")
    assert(type(deps) == "table", "PricingVerticalIntegration dependencies are required")
    local GetOpts = assert(deps.GetOpts, "GetOpts dependency is required")
    local GetPatchDB = assert(deps.GetPatchDB, "GetPatchDB dependency is required")
    local GetItemLabel = assert(deps.GetItemLabel, "GetItemLabel dependency is required")
    local GetActiveRecipeView = assert(deps.GetActiveRecipeView, "GetActiveRecipeView dependency is required")
    local GetInputRankPolicy = assert(deps.GetInputRankPolicy, "GetInputRankPolicy dependency is required")
    local PickItemID = assert(deps.PickItemID, "PickItemID dependency is required")
    local GetResolvedItemIDs = assert(deps.GetResolvedItemIDs, "GetResolvedItemIDs dependency is required")
    local GetOutputQualityForItem = assert(deps.GetOutputQualityForItem, "GetOutputQualityForItem dependency is required")
    local GetLowestOutputQuality = assert(deps.GetLowestOutputQuality, "GetLowestOutputQuality dependency is required")
    local GetHighestOutputQuality = assert(deps.GetHighestOutputQuality, "GetHighestOutputQuality dependency is required")
    local GetResolvedReagentItemIDs = assert(deps.GetResolvedReagentItemIDs, "GetResolvedReagentItemIDs dependency is required")
    local GetRequiredReagentAmountRaw = assert(deps.GetRequiredReagentAmountRaw, "GetRequiredReagentAmountRaw dependency is required")
    local QuantizeRequiredAmount = assert(deps.QuantizeRequiredAmount, "QuantizeRequiredAmount dependency is required")
    local BuildCalcContext = assert(deps.BuildCalcContext, "BuildCalcContext dependency is required")
    local BuildMergedReagentMap = assert(deps.BuildMergedReagentMap, "BuildMergedReagentMap dependency is required")
    local ResolveCheapestAlternative = assert(deps.ResolveCheapestAlternative, "ResolveCheapestAlternative dependency is required")
    local GetDirectEffectivePriceForItem = assert(deps.GetDirectEffectivePriceForItem, "GetDirectEffectivePriceForItem dependency is required")
    local ComputeOutputQuantity = assert(deps.ComputeOutputQuantity, "ComputeOutputQuantity dependency is required")
    local BuildProfileContext = assert(deps.BuildProfileContext, "BuildProfileContext dependency is required")
    local BuildRecipeView = assert(deps.BuildRecipeView, "BuildRecipeView dependency is required")
    local GetRecipeViewForVariantKey = assert(deps.GetRecipeViewForVariantKey, "GetRecipeViewForVariantKey dependency is required")
    local GetV2ExpectedOutputPerCraft = assert(deps.GetV2ExpectedOutputPerCraft, "GetV2ExpectedOutputPerCraft dependency is required")
    local Derivation = deps.Derivation or {}
    local PrepareOptimizedRecipeView
    local BuildEconomicReagentMetrics, BuildReagentMetrics, BuildDisplayReagentMetrics

local function GetOwnedItemCount(itemID)
    local modernAPI = C_Item and C_Item.GetItemCount
    if type(modernAPI) == "function" then
        local ok, count = pcall(modernAPI, itemID, true, false, true, true)
        if ok and count ~= nil then
            return tonumber(count) or 0
        end
    end
    if type(GetItemCount) == "function" then
        local ok, count = pcall(GetItemCount, itemID, true, false, true)
        if ok and count ~= nil then
            return tonumber(count) or 0
        end
    end
    return 0
end

local function CountOwnedReagentItems(itemID, entryIDs)
    local userHave = 0
    if itemID then
        return GetOwnedItemCount(itemID)
    end
    if entryIDs and #entryIDs > 0 then
        for _, reagentID in ipairs(entryIDs) do
            userHave = userHave + GetOwnedItemCount(reagentID)
        end
    end
    return userHave
end

-- An execution plan can encounter the same intermediate through more than one
-- branch. Track what has already been assigned so bag/bank stock is consumed
-- once before the remaining demand is expanded into producer materials.
local function NewInventoryLedger()
    return { remainingByKey = {} }
end

local function ConsumeOwnedFromLedger(ledger, itemID, entryIDs, required)
    required = tonumber(required) or 0
    if not ledger or required <= 0 then return 0 end

    local key
    if itemID then
        key = "item:" .. tostring(itemID)
    elseif entryIDs and #entryIDs > 0 then
        local ids = {}
        for _, id in ipairs(entryIDs) do ids[#ids + 1] = tonumber(id) or id end
        table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
        key = "pool:" .. table.concat(ids, ",")
    end
    if not key then return 0 end

    local remaining = ledger.remainingByKey[key]
    if remaining == nil then
        remaining = CountOwnedReagentItems(itemID, entryIDs)
    end
    local consumed = math.min(required, math.max(0, tonumber(remaining) or 0))
    ledger.remainingByKey[key] = math.max(0, remaining - consumed)
    return consumed
end

local function GetCheapestAlternativeScanIDs(entry, ctx)
    if not (entry and entry.cheapestOf) then
        return nil
    end
    local seen = {}
    local scanIDs = {}
    for _, alt in ipairs(entry.cheapestOf) do
        local altIDs = alt.itemIDs
        if (not altIDs or #altIDs == 0) and alt.itemRef then
            altIDs = ctx.pdb.rankGroups[alt.itemRef] or {}
        end
        for _, altID in ipairs(altIDs or {}) do
            if not seen[altID] then
                seen[altID] = true
                scanIDs[#scanIDs + 1] = altID
            end
        end
    end
    return (#scanIDs > 0) and scanIDs or nil
end

local function MergeUniqueItemIDs(target, source)
    if not source or #source == 0 then
        return target
    end
    target = target or {}
    local seen = {}
    for _, itemID in ipairs(target) do
        seen[itemID] = true
    end
    for _, itemID in ipairs(source) do
        if itemID and not seen[itemID] then
            seen[itemID] = true
            target[#target + 1] = itemID
        end
    end
    return target
end

local function GetScaledStartingAmountForCrafts(active, crafts)
    local defaultCrafts = (active and active.defaultCrafts) or (active and active.defaultStartingAmount) or 1
    local defaultStartingAmount = (active and active.defaultStartingAmount) or defaultCrafts
    if defaultCrafts and defaultCrafts > 0 then
        return crafts * (defaultStartingAmount / defaultCrafts)
    end
    return crafts
end

local function AddGraphLeafEntry(leafMap, leafOrder, entry)
    local key = entry.itemID or entry.name or tostring(#leafOrder + 1)
    local existing = leafMap[key]
    if existing then
        existing.qty = (existing.qty or 0) + (entry.qty or 0)
        existing.excludeFromCost = existing.excludeFromCost or entry.excludeFromCost
        existing.skipDerivation = existing.skipDerivation or entry.skipDerivation
        existing.scanItemIDs = MergeUniqueItemIDs(existing.scanItemIDs, entry.scanItemIDs)
        return
    end
    leafMap[key] = {
        itemID = entry.itemID,
        itemIDs = entry.itemIDs,
        name = entry.name,
        qty = entry.qty or 0,
        excludeFromCost = entry.excludeFromCost and true or false,
        skipDerivation = entry.skipDerivation and true or false,
        scanItemIDs = entry.scanItemIDs,
    }
    leafOrder[#leafOrder + 1] = key
end

local function ResolveGraphNodeEntry(ctx, node, qtyForPricing)
    if not node then
        return nil
    end

    local inputPolicy = GetInputRankPolicy(ctx.strat)
    local displayName = GetItemLabel(node)
    local itemIDs = GetResolvedReagentItemIDs(node, ctx.pdb)
    local itemID = nil
    local scanItemIDs = nil
    local selectedAlternativeName = nil
    local selectedAlternativeItemID = nil

    if node.cheapestOf then
        local resolved = ResolveCheapestAlternative(node, ctx, qtyForPricing)
        scanItemIDs = GetCheapestAlternativeScanIDs(node, ctx)
        if resolved then
            itemIDs = resolved.itemIDs or itemIDs
            itemID = resolved.itemID
            displayName = resolved.name or displayName
            selectedAlternativeName = resolved.name
            selectedAlternativeItemID = resolved.itemID
        end
    end

    if not itemID then
        itemID = PickItemID(itemIDs, ctx.patchTag, inputPolicy)
    end

    return {
        itemID = itemID,
        itemIDs = itemIDs,
        name = displayName,
        scanItemIDs = scanItemIDs or (itemID and { itemID } or itemIDs),
        excludeFromCost = node.excludeFromCost and true or false,
        skipDerivation = node.skipDerivation and true or false,
        selectedAlternativeName = selectedAlternativeName,
        selectedAlternativeItemID = selectedAlternativeItemID,
        selectionMode = node.cheapestOf and "cheapest_pool" or nil,
    }
end

local function GetProducerCandidateResolvedOutputID(candidate, patchTag, requestedItemID)
    if not candidate or not candidate.stratID or not (GAM.Importer and GAM.Importer.GetStratByID) then
        return nil, nil, nil
    end

    local strat = GAM.Importer.GetStratByID(candidate.stratID)
    if not strat then
        return nil, nil, nil
    end

    local active = candidate.variantKey and GetRecipeViewForVariantKey(strat, candidate.variantKey) or BuildRecipeView(strat)
    local output = active and ((active.outputs and active.outputs[1]) or active.output) or nil
    if not output then
        return strat, active, nil
    end

    local outputPolicy = nil
    if candidate.variantKey == "lowest" or candidate.variantKey == "highest" then
        outputPolicy = candidate.variantKey
    end

    local outputItemIDs = GetResolvedItemIDs(output, patchTag)
    for _, outputItemID in ipairs(outputItemIDs or {}) do
        if tonumber(outputItemID) == tonumber(requestedItemID) then
            return strat, active, outputItemID
        end
    end
    return strat, active, PickItemID(outputItemIDs, patchTag, outputPolicy)
end

local function GetExpectedOutputPerCraft(strat, active, opts)
    if not strat or not active then
        return nil
    end
    local output = (active.outputs and active.outputs[1]) or active.output
    if not output then
        return nil
    end
    local profile = BuildProfileContext(strat, opts or GetOpts())
    local qtyRaw = ComputeOutputQuantity(
        output, strat, profile.profileDef, profile.statDenom, profile.statMCp, profile.statMCm_tot, 1, 1)
    return qtyRaw
end

PrepareOptimizedRecipeView = function(ctx, strat, active, crafts, targetOutputItemID)
    if not ctx or not strat or not active or GetInputRankPolicy(strat) ~= "optimal" then
        return active
    end

    local output = (active.outputs and active.outputs[1]) or active.output
    local targetQuality = GetOutputQualityForItem(targetOutputItemID, strat.recipeID)
        or GetHighestOutputQuality(output, ctx.patchTag, strat.recipeID)
    if not targetQuality or targetQuality <= 0 then
        return active
    end
    local fallbackQuality = GetLowestOutputQuality(output, ctx.patchTag, strat.recipeID)

    local optimizer = GAM.ReagentMixOptimizer
    if not optimizer or type(optimizer.BuildLivePlan) ~= "function" then
        return active, nil, "optimizer-unavailable", targetQuality, fallbackQuality
    end

    local plan, reason, diagnostic = optimizer.BuildLivePlan({
        recipeID = strat.recipeID,
        targetQuality = targetQuality,
        crafts = crafts,
        recipeView = active,
        priceGetter = function(itemID, quantity)
            return Pricing.GetEffectivePriceForItem({
                itemIDs = { itemID },
                rankPolicyOverride = "highest",
            }, ctx.patchTag, quantity)
        end,
    })
    if not plan then
        local reachableQuality = diagnostic and tonumber(diagnostic.reachableQuality) or nil
        return active, nil, reason or "rank-mix-unavailable", targetQuality,
            reachableQuality or fallbackQuality
    end

    local optimized, applyReason = optimizer.ApplyPlan(active, plan)
    if not optimized then
        return active, nil, applyReason or "rank-mix-apply-failed", targetQuality,
            tonumber(plan.verifiedQuality)
    end
    return optimized, plan, reason, targetQuality, tonumber(plan.verifiedQuality)
end

local function GetPlannerExpectedOutputPerCraft(ctx, producer)
    if ctx and ctx.v2ExecutionPlan and GetV2ExpectedOutputPerCraft then
        return GetV2ExpectedOutputPerCraft(producer.strat, producer.active, ctx)
    end
    return GetExpectedOutputPerCraft(producer.strat, producer.active, ctx and ctx.opts)
end

local function FindProducerMatch(ctx, itemID, state)
    if not ctx.chainActive or not itemID or not (GAM.Importer and GAM.Importer.GetProducerCandidates) then
        return nil
    end

    local candidates = GAM.Importer.GetProducerCandidates(itemID, ctx.patchTag)
    for _, candidate in ipairs(candidates or {}) do
        local strat, active, candidateOutputID = GetProducerCandidateResolvedOutputID(
            candidate, ctx.patchTag, itemID)
        if strat
                and Derivation.CanVerticallyIntegrate(ctx.strat, strat)
                and active
                and candidateOutputID == itemID
                and type(active.outputs) == "table"
                and #active.outputs == 1 then
            local key = tostring(candidate.stratID) .. "::" .. tostring(candidate.variantKey or "base")
            if not (state.activeProducerKeys and state.activeProducerKeys[key]) then
                local craftCapacity, capacityReason = nil, nil
                local tracker = GAM.CooldownTracker
                if tracker and type(tracker.GetImmediateCraftCapacity) == "function" then
                    craftCapacity, capacityReason = tracker.GetImmediateCraftCapacity(strat.recipeID)
                end
                if craftCapacity ~= nil and craftCapacity <= 0 then
                    -- Try another producer, if one exists. A depleted charged or
                    -- actively cooling recipe cannot satisfy this dependency now.
                else
                    return {
                        key = key,
                        strat = strat,
                        active = active,
                        outputItemID = candidateOutputID,
                        craftCapacity = craftCapacity,
                        craftCapacityReason = capacityReason,
                    }
                end
            end
        end
    end

    return nil
end

local function TakeProducerCraftCapacity(state, producer, wantedCrafts)
    wantedCrafts = math.max(0, tonumber(wantedCrafts) or 0)
    local capacity = producer and tonumber(producer.craftCapacity) or nil
    if capacity == nil then return wantedCrafts end
    state.producerCraftsRemaining = state.producerCraftsRemaining or {}
    local key = tostring(producer.key or producer.strat and producer.strat.recipeID or "producer")
    local remaining = state.producerCraftsRemaining[key]
    if remaining == nil then remaining = math.max(0, capacity) end
    local granted = math.min(wantedCrafts, remaining)
    state.producerCraftsRemaining[key] = math.max(0, remaining - granted)
    return granted
end

local function BuildGraphLeafPlan(ctx, mode)
    local leafMap = {}
    local leafOrder = {}
    local state = {
        activeProducerKeys = {},
        inventoryLedger = mode == "execution" and NewInventoryLedger() or nil,
        producerCraftsRemaining = {},
    }
    local rootOrder, rootMap = BuildMergedReagentMap(ctx, "none")

    local function AddResolvedLeaf(resolvedEntry, qty)
        if not resolvedEntry or not qty or qty <= 0 then
            return
        end
        AddGraphLeafEntry(leafMap, leafOrder, {
            itemID = resolvedEntry.itemID,
            itemIDs = resolvedEntry.itemIDs,
            name = resolvedEntry.name,
            qty = qty,
            excludeFromCost = resolvedEntry.excludeFromCost,
            skipDerivation = resolvedEntry.skipDerivation,
            scanItemIDs = resolvedEntry.scanItemIDs,
        })
    end

    local function ExpandNode(node, requiredQty, depth)
        if not node or not requiredQty or requiredQty <= 0 or depth > 12 then
            return
        end

        local qtyForPricing = math.max(1, QuantizeRequiredAmount(requiredQty, "nearest"))
        local resolvedEntry = ResolveGraphNodeEntry(ctx, node, qtyForPricing)
        if not resolvedEntry then
            return
        end

        if resolvedEntry.excludeFromCost then
            if mode == "execution" and depth == 0 then
                AddResolvedLeaf(resolvedEntry, requiredQty)
            end
            return
        end

        if resolvedEntry.skipDerivation or not ctx.chainActive then
            AddResolvedLeaf(resolvedEntry, requiredQty)
            return
        end

        -- V2 records whether buying the intermediate or crafting it was the
        -- selected economic path. Execution rows must follow that same choice;
        -- otherwise the visible shopping plan can disagree with the totals.
        local economicChoice = mode == "execution"
            and ctx.v2EconomicChoices
            and resolvedEntry.itemID
            and ctx.v2EconomicChoices[tostring(resolvedEntry.itemID)]
            or nil
        if mode == "execution"
                and not Derivation.ShouldExpandDisplayIntermediate(mode, economicChoice) then
            AddResolvedLeaf(resolvedEntry, requiredQty)
            return
        end

        local producer = FindProducerMatch(ctx, resolvedEntry.itemID, state)
        if not producer then
            AddResolvedLeaf(resolvedEntry, requiredQty)
            return
        end

        local expectedOutputPerCraft = GetPlannerExpectedOutputPerCraft(ctx, producer)
        if not expectedOutputPerCraft or expectedOutputPerCraft <= 0 then
            AddResolvedLeaf(resolvedEntry, requiredQty)
            return
        end

        local requiredToProduce = requiredQty
        if mode == "execution" then
            requiredToProduce = math.max(0, requiredQty - ConsumeOwnedFromLedger(
                state.inventoryLedger,
                resolvedEntry.itemID,
                resolvedEntry.itemIDs,
                requiredQty))
        end
        if requiredToProduce <= 0 then
            return
        end

        local craftsNeeded = requiredToProduce / expectedOutputPerCraft
        if mode == "execution" then
            craftsNeeded = QuantizeRequiredAmount(craftsNeeded, "ceil")
        end
        if not craftsNeeded or craftsNeeded <= 0 then
            return
        end

        local craftsToProduce = TakeProducerCraftCapacity(state, producer, craftsNeeded)
        local producibleQty = craftsToProduce * expectedOutputPerCraft
        local unmetQty = math.max(0, requiredToProduce - producibleQty)
        if unmetQty > 1e-9 then
            AddResolvedLeaf(resolvedEntry, unmetQty)
        end
        if craftsToProduce <= 0 then return end

        local optimizedActive = PrepareOptimizedRecipeView(
            ctx, producer.strat, producer.active, craftsToProduce, producer.outputItemID)
        producer.active = optimizedActive or producer.active

        local scaledStartingAmt = GetScaledStartingAmountForCrafts(producer.active, craftsToProduce)
        state.activeProducerKeys[producer.key] = true
        for _, reagent in ipairs(producer.active.reagents or {}) do
            -- Only expand inputs for the crafts the live cooldown capacity
            -- actually granted. Passing craftsNeeded here made qtyPerCraft
            -- reagents retain the uncapped producer demand while the unmet
            -- intermediate was also added as an AH purchase.
            local childQty = GetRequiredReagentAmountRaw(
                reagent, scaledStartingAmt, craftsToProduce)
            ExpandNode(reagent, childQty, depth + 1)
        end
        state.activeProducerKeys[producer.key] = nil
    end

    for _, key in ipairs(rootOrder) do
        local rootEntry = rootMap[key]
        ExpandNode(rootEntry, rootEntry.qty or 0, 0)
    end

    return {
        leafMap = leafMap,
        leafOrder = leafOrder,
    }
end

-- Return every leaf material needed to price the selected strategy's available
-- same-profession craft chain.  The normal strategy scan already includes the
-- direct reagent, but V2 cannot compare direct-versus-crafted cost unless the
-- producer's underlying materials have prices as well.
function Pricing.GetVerticalIntegrationScanItems(strat, patchTag)
    if not strat then return {} end

    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local opts = GetOpts()
    local active = GetActiveRecipeView(strat)
    if not active then return {} end

    local ctx = BuildCalcContext(
        strat,
        active,
        patchTag,
        1,
        opts,
        GetPatchDB(patchTag),
        opts.ahCut or GAM.C.AH_CUT)
    if not ctx.chainActive then return {} end

    ctx.v2ExecutionPlan = true
    ctx.v2StatResolutions = {}

    local plan = BuildGraphLeafPlan(ctx, "economic")
    local items = {}
    for _, key in ipairs(plan.leafOrder or {}) do
        local leaf = plan.leafMap[key]
        if leaf and not leaf.excludeFromCost then
            items[#items + 1] = {
                itemIDs = leaf.scanItemIDs or leaf.itemIDs or (leaf.itemID and { leaf.itemID }) or {},
                name = leaf.name,
            }
        end
    end
    return items
end

local function BuildGraphLeafMetrics(ctx, mode)
    local plan = BuildGraphLeafPlan(ctx, mode)
    local results = {}
    local totalCostToBuy = 0
    local totalCostRequired = 0
    local hasStale = false
    local missingPrices = {}
    local quantityMode = (mode == "economic") and "none" or "nearest"
    local inputPolicy = GetInputRankPolicy(ctx.strat)

    for _, key in ipairs(plan.leafOrder or {}) do
        local entry = plan.leafMap[key]
        local requiredRaw = tonumber(entry and entry.qty) or 0
        local required = QuantizeRequiredAmount(requiredRaw, quantityMode)
        local itemID = entry and entry.itemID or nil
        local itemIDs = (entry and entry.itemIDs) or (itemID and { itemID }) or {}
        -- Producer expansion has already decided which nodes are crafted and
        -- which are terminal purchases.  Price every terminal row directly;
        -- applying legacy derivation here can label a row as an intermediate
        -- AH purchase while attaching its raw-material craft cost.
        local price, stale = GetDirectEffectivePriceForItem({
            itemIDs = itemID and { itemID } or itemIDs,
            name = entry and entry.name or nil,
            rankPolicyOverride = inputPolicy,
        }, ctx.patchTag, (mode == "economic") and requiredRaw or required)
        local userHave = CountOwnedReagentItems(itemID, itemIDs)
        local needToBuy = math.max(0, required - userHave)
        local totalCost = (entry and entry.excludeFromCost) and 0
            or ((needToBuy == 0) and 0 or (price and (needToBuy * price) or nil))
        local totalCostFull = (entry and entry.excludeFromCost) and 0
            or (price and (required * price) or nil)
        local missingPrice = (entry and not entry.excludeFromCost) and (needToBuy > 0) and not price

        if stale then
            hasStale = true
        end

        if missingPrice then
            missingPrices[#missingPrices + 1] = entry.name
        else
            totalCostToBuy = totalCostToBuy + (totalCost or 0)
            totalCostRequired = totalCostRequired + (totalCostFull or 0)
        end

        results[#results + 1] = {
            name = entry.name,
            itemID = itemID,
            sourceItemIDs = itemIDs,
            scanItemIDs = entry.scanItemIDs or (itemID and { itemID } or itemIDs),
            unitPrice = price,
            required = required,
            requiredRaw = requiredRaw,
            have = userHave,
            needToBuy = needToBuy,
            totalCost = totalCost,
            totalCostFull = totalCostFull,
            isStale = stale,
            missingPrice = missingPrice,
            excludeFromCost = entry.excludeFromCost and true or false,
            skipDerivation = entry.skipDerivation and true or false,
        }
    end

    return {
        reagentResults = results,
        totalCostToBuy = totalCostToBuy,
        totalCostRequired = totalCostRequired,
        hasStale = hasStale,
        missingPrices = missingPrices,
    }
end

local function SummarizeDisplayReagentRows(rows)
    local totalCostToBuy = 0
    local totalCostRequired = 0
    local hasStale = false
    local missingPrices = {}

    for _, row in ipairs(rows or {}) do
        if row.isStale then
            hasStale = true
        end
        if row.missingPrice then
            missingPrices[#missingPrices + 1] = row.name
        else
            totalCostToBuy = totalCostToBuy + (row.totalCost or 0)
            totalCostRequired = totalCostRequired + (row.totalCostFull or 0)
        end
    end

    return {
        reagentResults = rows or {},
        totalCostToBuy = totalCostToBuy,
        totalCostRequired = totalCostRequired,
        hasStale = hasStale,
        missingPrices = missingPrices,
    }
end

local function CloneContextForSingleReagent(ctx, reagent)
    local copy = {}
    for key, value in pairs(ctx or {}) do
        copy[key] = value
    end
    local active = {}
    for key, value in pairs(ctx.active or {}) do
        active[key] = value
    end
    active.reagents = { reagent }
    copy.active = active
    return copy
end

local function BuildDirectDisplayReagentMetrics(ctx, modelReagents)
    local rows = {}
    local inputPolicy = GetInputRankPolicy(ctx.strat)

    for index, reagent in ipairs(ctx.active.reagents or {}) do
        local requiredRaw = GetRequiredReagentAmountRaw(reagent, ctx.startingAmt, ctx.crafts)
        local required = QuantizeRequiredAmount(requiredRaw, "nearest")
        local qtyForPricing = math.max(1, required)
        local resolvedEntry = ResolveGraphNodeEntry(ctx, reagent, qtyForPricing)
        local model = modelReagents and modelReagents[index] or nil
        local itemID = resolvedEntry and resolvedEntry.itemID or (model and model.itemID) or nil
        local itemIDs = resolvedEntry and resolvedEntry.itemIDs or (model and model.sourceItemIDs) or {}
        local displayName = resolvedEntry and resolvedEntry.name or (model and model.name) or GetItemLabel(reagent)
        local excludeFromCost = reagent.excludeFromCost and true or false
        local userHave = CountOwnedReagentItems(itemID, itemIDs)
        local needToBuy = math.max(0, required - userHave)
        local unitPrice = model and model.unitPrice or nil
        local totalCost = model and model.totalCost or nil
        local totalCostFull = model and model.totalCostFull or nil
        local isStale = model and model.isStale or false
        local missingPrice = model and model.missingPrice or false
        local sourceNote = nil

        if ctx.chainActive and resolvedEntry and not resolvedEntry.excludeFromCost and not resolvedEntry.skipDerivation then
            local economicChoice = ctx.v2EconomicChoices
                and resolvedEntry.itemID
                and ctx.v2EconomicChoices[tostring(resolvedEntry.itemID)]
                or nil
            local producer = (not economicChoice or economicChoice.source == "producer")
                and FindProducerMatch(ctx, resolvedEntry.itemID, { activeProducerKeys = {} })
                or nil
            if producer then
                local singleCtx = CloneContextForSingleReagent(ctx, reagent)
                local chainMetrics = BuildGraphLeafMetrics(singleCtx, "economic")
                if chainMetrics then
                    local chainMissing = #(chainMetrics.missingPrices or {}) > 0
                    if chainMissing then
                        totalCostFull = nil
                        totalCost = nil
                        unitPrice = nil
                        missingPrice = true
                    elseif chainMetrics.totalCostRequired and chainMetrics.totalCostRequired > 0 then
                        totalCostFull = chainMetrics.totalCostRequired
                        totalCost = chainMetrics.totalCostToBuy
                        unitPrice = (requiredRaw and requiredRaw > 0)
                            and math.floor((chainMetrics.totalCostRequired / requiredRaw) + 0.5)
                            or unitPrice
                        missingPrice = false
                    end
                    isStale = chainMetrics.hasStale
                    sourceNote = "via " .. tostring(producer.strat and producer.strat.stratName or "craft chain")
                end
            end
        end

        if not unitPrice and model then
            unitPrice = model.unitPrice
        end
        if not totalCostFull and unitPrice then
            totalCostFull = excludeFromCost and 0 or (required * unitPrice)
        end
        if not totalCost and unitPrice then
            totalCost = excludeFromCost and 0 or ((needToBuy == 0) and 0 or (needToBuy * unitPrice))
        end
        missingPrice = (not excludeFromCost) and (needToBuy > 0) and not unitPrice

        rows[#rows + 1] = {
            name = displayName,
            itemID = itemID,
            sourceItemIDs = itemIDs,
            scanItemIDs = resolvedEntry and resolvedEntry.scanItemIDs or (model and model.scanItemIDs),
            unitPrice = unitPrice,
            required = required,
            requiredRaw = requiredRaw,
            have = userHave,
            needToBuy = needToBuy,
            totalCost = totalCost,
            totalCostFull = totalCostFull,
            isStale = isStale,
            missingPrice = missingPrice,
            excludeFromCost = excludeFromCost,
            skipDerivation = reagent.skipDerivation and true or false,
            sourceNote = sourceNote,
            selectedAlternativeName = model and model.selectedAlternativeName or nil,
            selectedAlternativeItemID = model and model.selectedAlternativeItemID or nil,
            selectionMode = model and model.selectionMode or nil,
        }
    end

    return SummarizeDisplayReagentRows(rows)
end

local function BuildBreakdownNodePricing(ctx, resolvedEntry, requiredRaw, required)
    local inputPolicy = GetInputRankPolicy(ctx.strat)
    local itemID = resolvedEntry and resolvedEntry.itemID or nil
    local itemIDs = (resolvedEntry and resolvedEntry.itemIDs) or (itemID and { itemID }) or {}
    local have = CountOwnedReagentItems(itemID, itemIDs)
    local needToBuy = math.max(0, required - have)

    if resolvedEntry and resolvedEntry.excludeFromCost then
        return {
            have = have,
            needToBuy = needToBuy,
            effectiveUnitPrice = nil,
            effectiveTotalCostToBuy = 0,
            effectiveTotalCostFull = 0,
            effectiveMissingPrice = false,
            effectiveIsStale = false,
            directUnitPrice = nil,
            directTotalCostToBuy = 0,
            directTotalCostFull = 0,
            directMissingPrice = false,
            directIsStale = false,
        }
    end

    local effectivePrice, effectiveStale = Pricing.GetEffectivePriceForItem({
        itemIDs = itemID and { itemID } or itemIDs,
        name = resolvedEntry and resolvedEntry.name or nil,
        skipDerivation = resolvedEntry and resolvedEntry.skipDerivation or false,
        rankPolicyOverride = inputPolicy,
    }, ctx.patchTag, requiredRaw)

    local directPrice, directStale = GetDirectEffectivePriceForItem({
        itemIDs = itemID and { itemID } or itemIDs,
        name = resolvedEntry and resolvedEntry.name or nil,
        rankPolicyOverride = inputPolicy,
    }, ctx.patchTag, requiredRaw)

    local function BuildTotals(price)
        local totalCostToBuy = (needToBuy == 0) and 0 or (price and (needToBuy * price) or nil)
        local totalCostFull = price and (requiredRaw * price) or nil
        local missingPrice = (needToBuy > 0) and not price
        return totalCostToBuy, totalCostFull, missingPrice
    end

    local effectiveTotalCostToBuy, effectiveTotalCostFull, effectiveMissingPrice = BuildTotals(effectivePrice)
    local directTotalCostToBuy, directTotalCostFull, directMissingPrice = BuildTotals(directPrice)

    return {
        have = have,
        needToBuy = needToBuy,
        effectiveUnitPrice = effectivePrice,
        effectiveTotalCostToBuy = effectiveTotalCostToBuy,
        effectiveTotalCostFull = effectiveTotalCostFull,
        effectiveMissingPrice = effectiveMissingPrice,
        effectiveIsStale = effectiveStale,
        directUnitPrice = directPrice,
        directTotalCostToBuy = directTotalCostToBuy,
        directTotalCostFull = directTotalCostFull,
        directMissingPrice = directMissingPrice,
        directIsStale = directStale,
    }
end

local function BuildVIBreakdownData(ctx, metrics)
    local rootOrder, rootMap = BuildMergedReagentMap(ctx, "none")
    local statUsages = metrics and (metrics.statUsages
        or (metrics.diagnostics and metrics.diagnostics.statUsages)) or {}
    local statUsageByStratID = {}
    for _, usage in ipairs(statUsages) do
        if usage and usage.stratID then
            statUsageByStratID[usage.stratID] = usage
        end
    end
    local state = {
        activeProducerKeys = {},
        inventoryLedger = NewInventoryLedger(),
        producerCraftsRemaining = {},
        entries = {},
        rootIndices = {},
    }
    local usedFallbackRows = false

    local function AddEntry(entry)
        entry.index = #state.entries + 1
        state.entries[#state.entries + 1] = entry
        return entry
    end

    local function ExpandNode(node, requiredQtyRaw, depth, parentIndex, inheritedExcluded)
        if not node or not requiredQtyRaw or requiredQtyRaw <= 0 or depth > 12 then
            return {
                chainTotalCostFull = 0,
                chainTotalCostToBuy = 0,
                hasMissingPrice = false,
                hasStale = false,
            }, nil
        end

        local qtyForPricing = math.max(1, QuantizeRequiredAmount(requiredQtyRaw, "nearest"))
        local resolvedEntry = ResolveGraphNodeEntry(ctx, node, qtyForPricing)
        if not resolvedEntry then
            return {
                chainTotalCostFull = 0,
                chainTotalCostToBuy = 0,
                hasMissingPrice = false,
                hasStale = false,
            }, nil
        end

        if inheritedExcluded then
            resolvedEntry.excludeFromCost = true
        end

        local required = QuantizeRequiredAmount(requiredQtyRaw, "nearest")
        local pricingData = BuildBreakdownNodePricing(ctx, resolvedEntry, requiredQtyRaw, required)
        local producer = nil
        local expectedOutputPerCraft = nil
        local stopReason = nil
        local economicChoice = ctx.v2EconomicChoices
            and resolvedEntry.itemID
            and ctx.v2EconomicChoices[tostring(resolvedEntry.itemID)]
            or nil

        if resolvedEntry.excludeFromCost then
            stopReason = "exclude_from_cost"
        elseif resolvedEntry.skipDerivation then
            stopReason = "skip_derivation"
        elseif not ctx.chainActive then
            stopReason = "vi_disabled"
        elseif economicChoice and economicChoice.source == "direct" then
            stopReason = "economic_direct"
        else
            producer = FindProducerMatch(ctx, resolvedEntry.itemID, state)
            if not producer then
                stopReason = "no_producer"
            else
                expectedOutputPerCraft = GetPlannerExpectedOutputPerCraft(ctx, producer)
                if not expectedOutputPerCraft or expectedOutputPerCraft <= 0 then
                    producer = nil
                    stopReason = "invalid_output"
                end
            end
        end

        local requiredToProduce = requiredQtyRaw
        local ownedIntermediateUsed = 0
        if producer then
            ownedIntermediateUsed = ConsumeOwnedFromLedger(
                state.inventoryLedger,
                resolvedEntry.itemID,
                resolvedEntry.itemIDs,
                requiredQtyRaw)
            requiredToProduce = math.max(0, requiredQtyRaw - ownedIntermediateUsed)
            if requiredToProduce <= 0 then
                producer = nil
                stopReason = "inventory"
            end
        end

        if producer then
            local craftsEconomicNeeded = requiredToProduce / expectedOutputPerCraft
            local craftsExecutionNeeded = QuantizeRequiredAmount(craftsEconomicNeeded, "ceil")
            local craftsExecutionAllowed = TakeProducerCraftCapacity(
                state, producer, craftsExecutionNeeded)
            if craftsExecutionAllowed <= 0 then
                producer = nil
                stopReason = "cooldown_capacity"
            else
                local producibleQty = craftsExecutionAllowed * expectedOutputPerCraft
                requiredToProduce = math.min(requiredToProduce, producibleQty)
            end
        end

        -- A non-craft node is an actual purchase in the selected plan.  Keep
        -- its displayed/purchase cost on the direct quote just like the main
        -- shopping projection; the derived quote is only meaningful for a
        -- producer node whose children are shown below it.
        local leafUsesDirectPrice = not producer and not resolvedEntry.excludeFromCost
        local selectedUnitPrice = pricingData.effectiveUnitPrice
        local selectedTotalCostToBuy = pricingData.effectiveTotalCostToBuy
        local selectedTotalCostFull = pricingData.effectiveTotalCostFull
        local selectedMissingPrice = pricingData.effectiveMissingPrice
        if leafUsesDirectPrice then
            selectedUnitPrice = pricingData.directUnitPrice
            selectedTotalCostToBuy = pricingData.directTotalCostToBuy
            selectedTotalCostFull = pricingData.directTotalCostFull
            selectedMissingPrice = pricingData.directMissingPrice
        end

        local entry = AddEntry({
            parentIndex = parentIndex,
            childIndices = {},
            depth = depth,
            kind = producer and "craft" or "leaf",
            name = resolvedEntry.name,
            itemID = resolvedEntry.itemID,
            itemIDs = resolvedEntry.itemIDs,
            scanItemIDs = resolvedEntry.scanItemIDs,
            requiredRaw = producer and requiredToProduce or requiredQtyRaw,
            required = producer and QuantizeRequiredAmount(requiredToProduce, "ceil") or required,
            have = pricingData.have,
            ownedUsed = ownedIntermediateUsed,
            needToBuy = pricingData.needToBuy,
            excludeFromCost = resolvedEntry.excludeFromCost and true or false,
            skipDerivation = resolvedEntry.skipDerivation and true or false,
            stopReason = stopReason,
            effectiveUnitPrice = selectedUnitPrice,
            effectiveTotalCostToBuy = selectedTotalCostToBuy,
            effectiveTotalCostFull = selectedTotalCostFull,
            effectiveMissingPrice = selectedMissingPrice,
            directUnitPrice = pricingData.directUnitPrice,
            directTotalCostToBuy = pricingData.directTotalCostToBuy,
            directTotalCostFull = pricingData.directTotalCostFull,
            directMissingPrice = pricingData.directMissingPrice,
            hasStale = pricingData.effectiveIsStale or pricingData.directIsStale,
            selectedAlternativeName = resolvedEntry.selectedAlternativeName,
            selectedAlternativeItemID = resolvedEntry.selectedAlternativeItemID,
            selectionMode = resolvedEntry.selectionMode,
        })

        if producer then
            local craftsEconomic = requiredToProduce / expectedOutputPerCraft
            local craftsExecution = QuantizeRequiredAmount(craftsEconomic, "ceil")
            local optimizedActive = PrepareOptimizedRecipeView(
                ctx, producer.strat, producer.active, craftsEconomic, producer.outputItemID)
            producer.active = optimizedActive or producer.active
            local statUsage = statUsageByStratID[producer.strat.id]
            entry.producerStratID = producer.strat.id
            entry.producerStratName = producer.strat.stratName
            entry.profileKey = producer.strat.formulaProfile
            entry.gearModeRequested = statUsage and statUsage.gearModeRequested or "auto"
            entry.gearModeResolved = statUsage and statUsage.gearModeResolved or "current"
            entry.gearPresetMissing = statUsage and statUsage.gearPresetMissing and true or false
            entry.expectedOutputPerCraft = expectedOutputPerCraft
            entry.craftsEconomic = craftsEconomic
            entry.craftsExecution = craftsExecution

            local chainTotalCostFull = 0
            local chainTotalCostToBuy = 0
            local hasMissingPrice = false
            local hasStale = entry.hasStale
            local scaledStartingAmt = GetScaledStartingAmountForCrafts(producer.active, craftsEconomic)
            entry.selectedInputNames = {}
            local selectedInputSet = {}

            state.activeProducerKeys[producer.key] = true
            for _, reagent in ipairs(producer.active.reagents or {}) do
                local childQty = GetRequiredReagentAmountRaw(reagent, scaledStartingAmt, craftsEconomic)
                local childSummary, childIndex = ExpandNode(reagent, childQty, depth + 1, entry.index, resolvedEntry.excludeFromCost)
                if childIndex then
                    entry.childIndices[#entry.childIndices + 1] = childIndex
                    local childEntry = state.entries[childIndex]
                    local selectedName = childEntry and childEntry.selectedAlternativeName
                    if selectedName and not selectedInputSet[selectedName] then
                        selectedInputSet[selectedName] = true
                        entry.selectedInputNames[#entry.selectedInputNames + 1] = selectedName
                    end
                end
                if childSummary then
                    chainTotalCostFull = chainTotalCostFull + (childSummary.chainTotalCostFull or 0)
                    chainTotalCostToBuy = chainTotalCostToBuy + (childSummary.chainTotalCostToBuy or 0)
                    hasMissingPrice = hasMissingPrice or childSummary.hasMissingPrice
                    hasStale = hasStale or childSummary.hasStale
                end
            end
            state.activeProducerKeys[producer.key] = nil

            if #entry.selectedInputNames == 0 then
                entry.selectedInputNames = nil
            end

            entry.chainTotalCostFull = chainTotalCostFull
            entry.chainTotalCostToBuy = chainTotalCostToBuy
            entry.hasMissingPrice = hasMissingPrice
            entry.hasStale = hasStale

            return {
                chainTotalCostFull = chainTotalCostFull,
                chainTotalCostToBuy = chainTotalCostToBuy,
                hasMissingPrice = hasMissingPrice,
                hasStale = hasStale,
            }, entry.index
        end

        entry.chainTotalCostFull = selectedTotalCostFull or 0
        entry.chainTotalCostToBuy = selectedTotalCostToBuy or 0
        entry.hasMissingPrice = selectedMissingPrice

        return {
            chainTotalCostFull = selectedTotalCostFull or 0,
            chainTotalCostToBuy = selectedTotalCostToBuy or 0,
            hasMissingPrice = selectedMissingPrice,
            hasStale = entry.hasStale,
        }, entry.index
    end

    for _, key in ipairs(rootOrder) do
        local rootEntry = rootMap[key]
        local _, rootIndex = ExpandNode(rootEntry, rootEntry.qty or 0, 0, nil, false)
        if rootIndex then
            state.rootIndices[#state.rootIndices + 1] = rootIndex
        end
    end

    local fallbackReagents = metrics
        and (metrics.shoppingReagents or metrics.reagents)
        or nil
    if #state.entries == 0 and type(fallbackReagents) == "table" then
        for _, reagent in ipairs(fallbackReagents) do
            local itemIDs = reagent.sourceItemIDs or (reagent.itemID and { reagent.itemID }) or {}
            local scanItemIDs = reagent.scanItemIDs or (reagent.itemID and { reagent.itemID }) or itemIDs
            local entry = AddEntry({
                parentIndex = nil,
                childIndices = {},
                depth = 0,
                kind = "leaf",
                name = reagent.name,
                itemID = reagent.itemID,
                itemIDs = itemIDs,
                scanItemIDs = scanItemIDs,
                requiredRaw = reagent.requiredRaw or reagent.required or 0,
                required = reagent.required or 0,
                have = reagent.have,
                needToBuy = reagent.needToBuy,
                excludeFromCost = reagent.excludeFromCost and true or false,
                skipDerivation = reagent.skipDerivation and true or false,
                stopReason = "fallback_metrics",
                effectiveUnitPrice = reagent.unitPrice,
                effectiveTotalCostToBuy = reagent.totalCost,
                effectiveTotalCostFull = reagent.totalCostFull,
                effectiveMissingPrice = reagent.missingPrice and true or false,
                directUnitPrice = reagent.unitPrice,
                directTotalCostToBuy = reagent.totalCost,
                directTotalCostFull = reagent.totalCostFull,
                directMissingPrice = reagent.missingPrice and true or false,
                hasStale = reagent.isStale and true or false,
                chainTotalCostFull = reagent.totalCostFull or 0,
                chainTotalCostToBuy = reagent.totalCost or 0,
                hasMissingPrice = reagent.missingPrice and true or false,
            })
            state.rootIndices[#state.rootIndices + 1] = entry.index
        end
        usedFallbackRows = (#state.entries > 0)
    end

    return {
        stratID = ctx.strat and ctx.strat.id or nil,
        stratName = ctx.strat and ctx.strat.stratName or nil,
        patchTag = ctx.patchTag,
        -- The canonical shopping projection already contains execution-safe
        -- quantities (including whole producer batches and inventory).  Keep
        -- it beside the economic branch tree so the VI action plan never
        -- reconstructs purchases from fractional expected-value leaves.
        shoppingReagents = fallbackReagents,
        chainActive = ctx.chainActive and true or false,
        crafts = ctx.crafts,
        startingAmount = ctx.startingAmt,
        totalCostFull = metrics and (metrics.requiredCostFull or metrics.totalCostFull) or nil,
        totalCostToBuy = metrics and (metrics.buyNowCost or metrics.totalCostToBuy) or nil,
        netRevenue = metrics and metrics.netRevenue or nil,
        profit = metrics and metrics.profit or nil,
        roi = metrics and metrics.roi or nil,
        breakEvenSell = metrics and metrics.breakEvenSell or nil,
        finalOutputName = metrics and metrics.outputs and metrics.outputs[1] and metrics.outputs[1].name
            or metrics and metrics.output and metrics.output.name
            or ctx.strat and ctx.strat.stratName,
        finalOutputItemID = metrics and metrics.outputs and metrics.outputs[1] and metrics.outputs[1].itemID
            or metrics and metrics.output and metrics.output.itemID,
        finalExpectedOutput = metrics and metrics.outputs and metrics.outputs[1]
            and (metrics.outputs[1].expectedQtyRaw or metrics.outputs[1].expectedQty)
            or metrics and metrics.output and (metrics.output.expectedQtyRaw or metrics.output.expectedQty),
        finalCraftsEconomic = metrics and metrics.effectiveCrafts or metrics and metrics.crafts or ctx.crafts,
        finalCraftsExecution = metrics and metrics.recommendedCrafts,
        finalGearModeRequested = metrics and metrics.gearModeRequested or "auto",
        finalGearModeResolved = metrics and metrics.gearModeResolved or "current",
        finalGearPresetMissing = metrics and metrics.gearPresetMissing and true or false,
        rootIndices = state.rootIndices,
        entries = state.entries,
        usedFallbackRows = usedFallbackRows,
    }
end

BuildEconomicReagentMetrics = function(ctx)
    return BuildGraphLeafMetrics(ctx, "economic")
end

BuildReagentMetrics = function(ctx)
    local mergedOrder, mergedMap = BuildMergedReagentMap(ctx)
    local reagentResults = {}
    local totalCostToBuy = 0
    local totalCostRequired = 0
    local hasStale = false
    local selectionNotes = {}
    local missingPrices = {}
    local inputPolicy = GetInputRankPolicy(ctx.strat)

    for _, key in ipairs(mergedOrder) do
        local entry = mergedMap[key]
        local entryIDs = entry.itemIDs
        local required = math.floor(entry.qty + 0.5)
        local excludeFromCost = entry.excludeFromCost and true or false
        local itemID, price, stale, displayName

        if entry.cheapestOf then
            local resolved = ResolveCheapestAlternative(entry, ctx, required)
            if resolved then
                entryIDs = resolved.itemIDs
                itemID = resolved.itemID
                displayName = resolved.name
                price = resolved.price
                stale = resolved.stale
            else
                entryIDs = entry.itemIDs
                itemID = PickItemID(entryIDs, ctx.patchTag, inputPolicy)
                displayName = entry.name
                price = nil
                stale = false
            end
        else
            itemID      = PickItemID(entryIDs, ctx.patchTag, inputPolicy)
            displayName = entry.name
            local itemProxy = {
                itemIDs = itemID and { itemID } or entryIDs,
                name = entry.name,
                skipDerivation = entry.skipDerivation and true or false,
                rankPolicyOverride = inputPolicy,
            }
            price, stale = Pricing.GetEffectivePriceForItem(itemProxy, ctx.patchTag, required)
        end

        local userHave = CountOwnedReagentItems(itemID, entryIDs)
        local needToBuy = math.max(0, required - userHave)
        if stale then
            hasStale = true
        end

        local totalCost = excludeFromCost and 0 or ((needToBuy == 0) and 0 or (price and (needToBuy * price) or nil))
        local totalCostFull = excludeFromCost and 0 or (price and (required * price) or nil)
        local missingPrice = (not excludeFromCost) and (needToBuy > 0) and not price

        if missingPrice then
            missingPrices[#missingPrices + 1] = displayName
        else
            totalCostToBuy = totalCostToBuy + (totalCost or 0)
            totalCostRequired = totalCostRequired + (totalCostFull or 0)
        end

        reagentResults[#reagentResults + 1] = {
            name = displayName,
            itemID = itemID,
            sourceItemIDs = entryIDs,
            scanItemIDs = GetCheapestAlternativeScanIDs(entry, ctx),
            unitPrice = price,
            required = required,
            have = userHave,
            needToBuy = needToBuy,
            totalCost = totalCost,
            totalCostFull = totalCostFull,
            isStale = stale,
            missingPrice = missingPrice,
            excludeFromCost = excludeFromCost,
            skipDerivation = entry.skipDerivation and true or false,
            selectedAlternativeName = entry.cheapestOf and displayName or nil,
            selectedAlternativeItemID = entry.cheapestOf and itemID or nil,
            selectionMode = entry.cheapestOf and "cheapest_pool" or nil,
        }

        if entry.cheapestOf and displayName then
            selectionNotes[#selectionNotes + 1] = displayName
        end
    end

    return {
        reagentResults = reagentResults,
        totalCostToBuy = totalCostToBuy,
        totalCostRequired = totalCostRequired,
        hasStale = hasStale,
        selectionNotes = selectionNotes,
        missingPrices = missingPrices,
    }
end

BuildDisplayReagentMetrics = function(ctx, modelReagents)
    -- The visible input list must describe the active acquisition plan. With VI
    -- disabled, show the selected recipe's direct reagents. With VI enabled,
    -- replace craftable intermediates with the recursively expanded materials
    -- the player needs to execute that plan.
    local displayMode = Derivation.GetDisplayPlanMode(ctx.chainActive)
    if displayMode == "execution" then
        return BuildGraphLeafMetrics(ctx, displayMode)
    end
    return BuildDirectDisplayReagentMetrics(ctx, modelReagents)
end

    return {
        PrepareOptimizedRecipeView = PrepareOptimizedRecipeView,
        GetScaledStartingAmountForCrafts = GetScaledStartingAmountForCrafts,
        ResolveGraphNodeEntry = ResolveGraphNodeEntry,
        FindProducerMatch = FindProducerMatch,
        BuildVIBreakdownData = BuildVIBreakdownData,
        BuildEconomicReagentMetrics = BuildEconomicReagentMetrics,
        BuildReagentMetrics = BuildReagentMetrics,
        BuildDisplayReagentMetrics = BuildDisplayReagentMetrics,
    }
end
