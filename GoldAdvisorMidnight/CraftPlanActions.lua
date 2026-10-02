-- Recovery actions preserve the user's goal and confirmed progress.
local ADDON_NAME, GAM = ...
local function L(key, fallback, ...)
    local value = (GAM.L and GAM.L[key]) or fallback
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end
local Plan = GAM.CraftPlan
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = Copy(v) end
    return out
end
local function Invalidate(plan)
    plan.breakEven, plan.estimateInvalid = nil, true
    plan.revision = (plan.revision or 0) + 1
end

function Plan.ExtraCapacity(plan)
    if Plan.IsBusy() or plan.needsReview or plan.optionalExtra or plan.completed < plan.target then return 0 end
    for _, saved in ipairs(Plan.GetData().plans) do if saved.needsReview then return 0 end end
    local projection, totals = Plan.Project(), {}
    for _, reagent in ipairs(plan.nodes[plan.root].reagents) do
        totals[reagent.itemID] = (totals[reagent.itemID] or 0) + reagent.quantity
    end
    local amount = 100000
    if next(totals) == nil then return 0 end
    for id, quantity in pairs(totals) do
        amount = math.min(amount, math.floor(math.max(0, Plan.Count(id) - (projection.reserved[id] or 0)) / quantity))
    end
    return amount
end

function Plan.QueueExtras(plan, quantity)
    quantity = tonumber(quantity)
    local present = false
    for _, saved in ipairs(Plan.GetData().plans) do if saved == plan then present = true end end
    if not present or not quantity or quantity <= 0 or quantity % 1 ~= 0 or quantity > Plan.ExtraCapacity(plan) then
        return false, L("WF_SURPLUS_CHANGED", "Available surplus changed. Review the remaining materials again.")
    end
    local extra, data = Copy(plan), Plan.GetData()
    extra.id, extra.target, extra.completed = data.nextID, quantity, 0
    data.nextID = data.nextID + 1
    extra.optionalExtra, extra.history, extra.outputs, extra.confirmedCasts = true, {}, {}, {}
    extra.intermediateOutputs = {}
    -- Its own batch: none of the finished plan's material use or state.
    extra.consumed, extra.marketShort, extra.needsReview, extra.ownUse = nil, nil, nil, true
    extra.createdAt = GetServerTime and GetServerTime() or nil
    extra.name = L("WF_EXTRA_NAME", "%s · extra crafts", plan.name)
    extra.breakEven = nil
    local node = extra.nodes[extra.root]
    for _, reagent in ipairs(node.reagents) do reagent.producer = nil end
    extra.nodes = {[extra.root] = node}
    data.plans[#data.plans + 1] = extra
    Plan.Notify(L("WF_EXTRAS_QUEUED", "Extra crafts queued using unreserved materials in your bags and banks only."))
    return true
end
function Plan.TogglePause(plan)
    if Plan.IsBusy() then return false, L("WF_STOP_BATCH_FIRST", "Stop the current batch first.") end
    plan.paused = not plan.paused
    plan.revision = (plan.revision or 0) + 1
    Plan.Notify(plan.paused and L("WF_PAUSED_NOTICE", "Strategy paused. Its materials are available to other strategies.")
        or L("WF_RESUMED_NOTICE", "Strategy resumed. Materials recalculated."))
    return true
end
function Plan.RefreshStrategy(plan)
    if plan.optionalExtra then return false, L("WF_EXTRA_REQUEUE", "Remove this extra batch and queue it again from available surplus.") end
    if Plan.IsBusy() or plan.needsReview then return false, L("WF_REFRESH_BUSY", "Finish the batch and confirm progress before refreshing.") end
    local strat = GAM.Importer and GAM.Importer.GetStratByID(plan.strategyID)
    if not strat then return false, L("WF_STRATEGY_UNAVAILABLE", "The original strategy is unavailable.") end
    local remaining = math.max(1, plan.target - plan.completed)
    local result, err = GAM.PricingFacade.CalculateForCrafts(strat, plan.patchTag, remaining)
    if not result then return false, err end
    result = Copy(result)
    local ok, snapshot = pcall(GAM.Pricing.BuildCraftPlanSnapshot, strat, plan.patchTag, result)
    if not ok then return false, tostring(snapshot) end
    if Plan.PrepareRecipeType then
        for _, node in pairs(snapshot.nodes) do
            local supported, reason = Plan.PrepareRecipeType(node)
            if not supported then return false, reason end
        end
    end
    for key, node in pairs(snapshot.nodes) do
        node.craftLimitHistory = (plan.history and plan.history[key]) or 0
    end
    -- Keep old node descriptions for history even if a rank change replaced a key.
    for key, node in pairs(plan.nodes) do
        if not snapshot.nodes[key] then snapshot.nodes[key] = node end
    end
    plan.nodes, plan.root, plan.vi, plan.rankPolicy = snapshot.nodes, snapshot.root, snapshot.vi, snapshot.rankPolicy
    Invalidate(plan)
    plan.breakEven = result.breakEvenSell
    Plan.Notify(L("WF_PLAN_REFRESHED", "Remaining plan refreshed from current settings. Completed crafts and outputs retained; break-even recalculated."))
    return true
end

local function OutputID(node, rank)
    local api = C_TradeSkillUI
    local ids = api.GetRecipeQualityItemIDs and api.GetRecipeQualityItemIDs(node.recipeID)
    local id = ids and tonumber(ids[rank])
    if not id and api.GetRecipeOutputItemData then
        local output = api.GetRecipeOutputItemData(node.recipeID, {}, nil, rank)
        id = output and tonumber(output.itemID)
    end
    return id
end

-- Build a detached proposal. No craft is submitted and saved nodes are not changed.
function Plan.PreviewRankChange(task)
    if Plan.IsBusy() or task.plan.needsReview or task.plan.paused then return nil, L("WF_RANK_REVIEW_BUSY", "Finish or review the active batch first.") end
    local checked, ready, reason, code = pcall(Plan.Preflight, task)
    if not checked then return nil, tostring(ready) end
    if ready or code ~= "rank-mismatch" then return nil, reason or L("WF_RANK_ACHIEVABLE", "The saved output rank is already achievable.") end
    local plan = task.plan
    local nodes, changes, visiting = Copy(plan.nodes), {}, {}
    local reachable = {}
    local function Visit(key)
        if reachable[key] then return end
        reachable[key] = true
        for _, reagent in ipairs(nodes[key].reagents) do if reagent.producer then Visit(reagent.producer) end end
    end
    Visit(plan.root)
    local function Recheck(key)
        if visiting[key] then error(L("WF_CIRCULAR_RANKS", "Circular dependency while checking output ranks.")) end
        visiting[key] = true
        local node = nodes[key]
        local api = C_TradeSkillUI
        local info = api.GetRecipeInfo(node.recipeID)
        local schematic = api.GetRecipeSchematic(node.recipeID, false)
        if not info or not schematic then error(L("WF_OPEN_LOAD_RECIPE", "Open %s to load its recipe data, then retry.", node.name)) end
        local allocation, err = Plan.BuildAllocation(node, schematic)
        if not allocation then error(node.name .. ": " .. err) end
        if info.supportsQualities then
            local operation = api.GetCraftingOperationInfo(node.recipeID, allocation, nil, false)
            local rank = operation and (tonumber(operation.craftingQuality) or tonumber(operation.quality))
            if not rank or rank < 1 or rank % 1 ~= 0 then error(L("WF_OUTPUT_RANK_UNKNOWN", "Output rank is unknown for %s. Open that recipe and retry.", node.name)) end
            local id = OutputID(node, rank)
            if not id then error(L("WF_OUTPUT_ID_UNKNOWN", "Blizzard has not identified the rank %s output for %s.", tostring(rank), node.name)) end
            local oldID = node.outputItemID
            if rank ~= node.targetQuality or id ~= oldID then
                changes[#changes + 1] = L("WF_RANK_CHANGE", "%s: rank %s -> %s", node.name, tostring(node.targetQuality or "?"), tostring(rank))
                node.targetQuality, node.outputItemID = rank, id
                local found = false
                for _, output in ipairs(node.outputs) do if output == id then found = true end end
                if not found then node.outputs[#node.outputs + 1] = id end
                for consumerKey, consumer in pairs(nodes) do
                    local changed = false
                    for _, reagent in ipairs(consumer.reagents) do
                        if reachable[consumerKey] and reagent.producer == key then
                            reagent.itemID = id
                            changed = true
                        end
                    end
                    if changed then Recheck(consumerKey) end
                end
            end
        end
        visiting[key] = nil
    end
    local ok, err = pcall(Recheck, task.node.key)
    if not ok then return nil, tostring(err) end
    changes = {}
    for key in pairs(reachable) do
        local old, updated = plan.nodes[key], nodes[key]
        if old.targetQuality ~= updated.targetQuality or old.outputItemID ~= updated.outputItemID then
            changes[#changes + 1] = L("WF_RANK_CHANGE", "%s: rank %s -> %s", updated.name, tostring(old.targetQuality or "?"), tostring(updated.targetQuality))
        end
    end
    table.sort(changes)
    return { plan = plan, nodeKey = task.node.key, revision = plan.revision or 0,
        completed = plan.completed, nodes = nodes, changes = changes,
        summary = table.concat(changes, "\n") .. "\n" .. L("WF_RANK_PROPOSAL_NOTE", "Concentration off. Minimum crafts unchanged. Saved cost estimate will be cleared.") }
end

-- Prefer a usable batch over shopping for later steps. Preserve dependency
-- reservations; pausing a blocked strategy explicitly releases them.
-- A step the player can fix now (rank review, setup) goes before one that
-- only waits for cooldown charges, so it is not hidden behind it.
function Plan.NextTask(projection)
    local fallback, waiting
    for _, task in ipairs(projection.tasks) do
        if task.ready > 0 and not task.plan.needsReview then
            local ok, allocation, message, code = pcall(Plan.Preflight, task)
            if ok and allocation then return task, allocation, message end
            local entry = { task, nil, ok and message or tostring(allocation), ok and code or nil }
            if entry[4] == "cooldown" then waiting = waiting or entry else fallback = fallback or entry end
        end
    end
    fallback = fallback or waiting
    if fallback then return fallback[1], nil, fallback[3], fallback[4] end
end
function Plan.AcceptRankChange(proposal)
    local plan = proposal and proposal.plan
    if not plan or Plan.IsBusy() or (plan.revision or 0) ~= proposal.revision or plan.completed ~= proposal.completed then
        return false, L("WF_PLAN_CHANGED", "The plan changed. Review the ranks again.")
    end
    local task
    for _, candidate in ipairs(Plan.Project().tasks) do
        if candidate.plan == plan and candidate.node.key == proposal.nodeKey then task = candidate; break end
    end
    if not task then return false, L("WF_STEP_NOT_PENDING", "This step is no longer pending.") end
    local fresh, err = Plan.PreviewRankChange(task)
    if not fresh then return false, err end
    -- Recheck after gear/skill changes; never approve a different preview silently.
    if fresh.summary ~= proposal.summary then return false, L("WF_RANKS_CHANGED", "Output ranks changed. Review the updated ranks before accepting.") end
    plan.nodes = fresh.nodes
    Invalidate(plan)
    Plan.Notify(L("WF_RANKS_UPDATED", "Output ranks updated for this plan. Review materials, then click Craft. Concentration stays off."))
    return true
end

-- Replacement-cost estimate, not historical purchase cost. Base yield excludes
-- bonus output/resourcefulness; missing prices never turn into free materials.
function Plan.OutputBreakEven(plan, key, visiting)
    local node = plan.nodes[key]
    local yield = node and tonumber(node.baseYield)
    if not yield or yield <= 0 then return nil end
    visiting = visiting or {}
    if visiting[key] then return nil end
    visiting[key] = true
    local total = 0
    for _, reagent in ipairs(node.reagents) do
        local price
        if reagent.producer then
            price = Plan.OutputBreakEven(plan, reagent.producer, visiting)
            local cut = tonumber(GAM.db.options and GAM.db.options.ahCut) or 0.05
            if price then price = price * (1 - cut) end
        elseif GAM.VendorPrices and GAM.VendorPrices.ResolvePurchase then
            local source
            source, price = GAM.VendorPrices.ResolvePurchase(reagent.itemID, reagent.quantity)
        end
        if not price then visiting[key] = nil; return nil end
        total = total + price * reagent.quantity
    end
    visiting[key] = nil
    local cut = tonumber(GAM.db.options and GAM.db.options.ahCut) or 0.05
    if cut < 0 or cut >= 1 then return nil end
    return total / yield / (1 - cut)
end

function Plan.OutputSummary(projection)
    local rows, byID = {}, {}
    for _, plan in ipairs(Plan.GetData().plans) do
        for id, quantity in pairs(plan.outputs) do
            local estimate = plan.breakEven or Plan.OutputBreakEven(plan, plan.root)
            if not byID[id] then
                byID[id] = { itemID = id, produced = 0, breakEven = estimate, currentEstimate = not plan.breakEven }
                rows[#rows + 1] = byID[id]
            elseif byID[id].breakEven ~= estimate then byID[id].breakEven = nil end
            byID[id].produced = byID[id].produced + quantity
        end
        -- Include leftover intermediate stock even for queues created before
        -- intermediate result tracking was introduced.
        local seen = {}
        for key, node in pairs(plan.nodes) do
            if key ~= plan.root then
                for _, id in ipairs(node.outputs or {}) do
                    if not seen[id] then
                        seen[id] = true
                        local produced = (plan.intermediateOutputs or {})[id] or 0
                        local free = math.max(0, Plan.Count(id) - ((projection.reserved or {})[id] or 0))
                        if produced > 0 or free > 0 then
                            local estimate = Plan.OutputBreakEven(plan, key)
                            local row = byID[id]
                            if not row then
                                row = {itemID=id, produced=0, breakEven=estimate, currentEstimate=true}
                                byID[id]=row; rows[#rows+1]=row
                            elseif row.breakEven ~= estimate then row.breakEven=nil end
                            row.produced = row.produced + produced
                        end
                    end
                end
            end
        end
    end
    for _, row in ipairs(rows) do
        row.free = math.max(0, Plan.Count(row.itemID) - ((projection.reserved or {})[row.itemID] or 0))
    end
    table.sort(rows, function(a,b) return a.itemID < b.itemID end)
    return rows
end
