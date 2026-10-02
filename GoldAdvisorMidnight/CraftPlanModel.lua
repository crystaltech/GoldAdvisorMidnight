-- Pure, inventory-aware projection of saved crafting plans.
local ADDON_NAME, GAM = ...
local function L(key, fallback, ...)
    local value = (GAM.L and GAM.L[key]) or fallback
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end
local Model = {}
GAM.CraftPlanModel = Model

local function Ceil(value) return math.max(0, math.ceil(value - 1e-8)) end

function Model.Project(plans, count, countReady)
    local ledger, actual, buys, buyOrder, tasks, reserved = {}, {}, {}, {}, {}, {}
    local function Owned(id)
        if ledger[id] == nil then
            ledger[id] = math.max(0, math.floor(tonumber(count(id)) or 0))
            actual[id] = math.max(0, math.floor(tonumber((countReady or count)(id)) or 0))
        end
        return ledger[id]
    end
    local function Consume(id, qty)
        local take = math.min(Owned(id), qty)
        ledger[id] = ledger[id] - take
        return qty - take
    end
    -- plans records each plan's share of the combined shortage, so recorded
    -- purchases can be attributed to the plans that needed them.
    local function Buy(reagent, qty, planID)
        if qty <= 0 then return end
        if not buys[reagent.itemID] then
            buys[reagent.itemID] = { itemID = reagent.itemID, name = reagent.name, quantity = 0, plans = {} }
            buyOrder[#buyOrder + 1] = buys[reagent.itemID]
        end
        local buy = buys[reagent.itemID]
        buy.quantity = buy.quantity + qty
        if planID ~= nil then buy.plans[planID] = (buy.plans[planID] or 0) + qty end
    end
    for _, plan in ipairs(plans or {}) do
        local taskMap, visiting = {}, {}
        local remainingCrafts = {}
        local function Produce(key, crafts, final)
            if visiting[key] then error(L("WF_CIRCULAR_SAVED_PLAN", "Circular saved craft plan")) end
            local node = assert(plan.nodes[key], L("WF_MISSING_SAVED_RECIPE", "Missing saved craft recipe"))
            visiting[key] = true
            for _, reagent in ipairs(node.reagents) do
                local shortage = Consume(reagent.itemID, reagent.quantity * crafts)
                if shortage > 0 then
                    local producer = reagent.producer and plan.nodes[reagent.producer]
                    if producer and producer.baseYield > 0 then
                        local batches = Ceil(shortage / producer.baseYield)
                        if producer.craftLimit ~= nil then
                            if remainingCrafts[reagent.producer] == nil then
                                local completed = math.max(0, ((plan.history or {})[reagent.producer] or 0)
                                    - (producer.craftLimitHistory or 0))
                                remainingCrafts[reagent.producer] = math.max(0, producer.craftLimit - completed)
                            end
                            batches = math.min(batches, remainingCrafts[reagent.producer])
                            remainingCrafts[reagent.producer] = remainingCrafts[reagent.producer] - batches
                        end
                        if batches > 0 then Produce(reagent.producer, batches, false) end
                        local output = batches * producer.baseYield
                        ledger[reagent.itemID] = Owned(reagent.itemID) + math.max(0, output - shortage)
                        Buy(reagent, math.max(0, shortage - output), plan.id)
                    else
                        Buy(reagent, shortage, plan.id)
                    end
                end
            end
            visiting[key] = nil
            if not taskMap[key] then
                taskMap[key] = { plan = plan, node = node, crafts = 0, final = final }
                tasks[#tasks + 1] = taskMap[key]
            end
            taskMap[key].crafts = taskMap[key].crafts + crafts
        end
        local remaining = math.max(0, plan.target - plan.completed)
        if remaining > 0 then Produce(plan.root, remaining, true) end
    end
    -- Reserve real inventory in dependency order. Projected producer output is
    -- useful for shopping but never qualifies as inventory ready to craft.
    for _, task in ipairs(tasks) do
        local totals = {}
        for _, reagent in ipairs(task.node.reagents) do
            totals[reagent.itemID] = (totals[reagent.itemID] or 0) + reagent.quantity
        end
        local ready = task.crafts
        for id, qty in pairs(totals) do
            Owned(id)
            ready = math.min(ready, math.floor(actual[id] / qty))
        end
        task.ready = math.max(0, ready)
        for id, qty in pairs(totals) do
            local take = math.min(actual[id], qty * task.crafts)
            reserved[id] = (reserved[id] or 0) + take
            actual[id] = actual[id] - take
        end
    end
    return { tasks = tasks, buys = buyOrder, reserved = reserved }
end

function Model.ConfirmCraft(plan, node, final, castGUID)
    plan.confirmedCasts = plan.confirmedCasts or {}
    if not castGUID or plan.confirmedCasts[castGUID] then return false end
    plan.confirmedCasts[castGUID] = true
    if final then plan.completed = math.min(plan.target, plan.completed + 1) end
    plan.history = plan.history or {}
    plan.history[node.key] = (plan.history[node.key] or 0) + 1
    return true
end

function Model.RecordOutput(plan, node, itemID, quantity, final)
    local allowed = false
    for _, id in ipairs(node.outputs) do if id == itemID then allowed = true; break end end
    if not allowed or not quantity or quantity <= 0 then return end
    if final then
        plan.outputs[itemID] = (plan.outputs[itemID] or 0) + quantity
    else
        plan.intermediateOutputs = plan.intermediateOutputs or {}
        plan.intermediateOutputs[itemID] = (plan.intermediateOutputs[itemID] or 0) + quantity
    end
end
