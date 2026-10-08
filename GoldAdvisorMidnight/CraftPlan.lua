-- Persistent character craft plans and a hardware-initiated native craft adapter.
local ADDON_NAME, GAM = ...
local function L(key, fallback, ...)
    local value = (GAM.L and GAM.L[key]) or fallback
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end
local Plan = {}
GAM.CraftPlan = Plan
local pending, events
local outsideResults   -- craft results already recorded outside the queue
local function GetStopRepeat()
    return (C_TradeSkillUI and C_TradeSkillUI.StopRecipeRepeat) or StopTradeSkillRepeat
end
Plan.message = L("WF_PLAN_INTRO", "Add strategies from Details. Minimum final crafts are preserved.")
Plan.messageKind = "summary"

local function CharacterKey()
    return UnitGUID and UnitGUID("player") or ((UnitName and UnitName("player") or "player") .. "-" .. (GetRealmName and GetRealmName() or "realm"))
end
local function Data()
    GAM.db.craftPlans = GAM.db.craftPlans or { version = 1, characters = {} }
    local chars = GAM.db.craftPlans.characters
    local key = CharacterKey()
    chars[key] = chars[key] or { plans = {}, nextID = 1, incoming = {} }
    return chars[key]
end
-- Crafting can consume reagents from the bank, reagent bank and Warband bank,
-- so the queue counts the same owned inventory that pricing does.
local function Count(id)
    return C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id, true, false, true, true) or 0
end
local function Notify(message, kind)
    if message then Plan.message, Plan.messageKind = message, kind end
    local ui = GAM.UI and GAM.UI.CraftPlanWindow
    if ui and ui.Refresh then ui.Refresh() end
end
Plan.Notify = Notify
Plan.GetData = Data
Plan.Count = Count
function Plan.IsBusy() return pending ~= nil end
function Plan.Project()
    local data = Data()
    local active, extras = {}, {}
    for _, plan in ipairs(data.plans) do
        if not plan.paused then
            local group = plan.optionalExtra and extras or active
            group[#group + 1] = plan
        end
    end
    local function count(id)
        return Count(id) + ((data.incoming[id] and data.incoming[id].quantity) or 0)
    end
    local projection = GAM.CraftPlanModel.Project(active, count, Count)
    local uncertain = false
    for _, plan in ipairs(active) do if plan.needsReview then uncertain = true end end
    for _, plan in ipairs(extras) do
        local capacity = uncertain and 0 or math.max(0, plan.target - plan.completed)
        local totals = {}
        for _, reagent in ipairs(plan.nodes[plan.root].reagents) do
            totals[reagent.itemID] = (totals[reagent.itemID] or 0) + reagent.quantity
        end
        if next(totals) == nil then capacity = 0 end
        for id, quantity in pairs(totals) do
            capacity = math.min(capacity, math.floor(math.max(0, Count(id) - (projection.reserved[id] or 0)) / quantity))
        end
        if capacity > 0 then
            local view = {}
            for key, value in pairs(plan) do view[key] = value end
            view.target = view.completed + capacity
            active[#active + 1] = view
            projection = GAM.CraftPlanModel.Project(active, count, Count)
            -- Keep task identity bound to the persistent plan, not its capped view.
            view.originalPlan = plan
        end
    end
    for _, task in ipairs(projection.tasks) do task.plan = task.plan.originalPlan or task.plan end
    return projection
end

-- target: optional craft count (History's Queue button); the notes below
-- then describe that count.
function Plan.Add(strat, patchTag, target)
    Plan.Init()
    if pending then return false, L("WF_ADD_BUSY", "Finish or stop the current batch before adding a plan.") end
    local result, err = GAM.PricingFacade.CalculateCurrent(strat, patchTag)
    if not result then return false, err end
    local ok, snapshot = pcall(GAM.Pricing.BuildCraftPlanSnapshot, strat, patchTag, result)
    if not ok then return false, tostring(snapshot) end
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        for _, node in pairs(snapshot.nodes) do
            local info = C_TradeSkillUI.GetRecipeInfo(node.recipeID)
            if Plan.PrepareRecipeType then
                local supported, reason = Plan.PrepareRecipeType(node)
                if not supported then return false, reason end
            elseif info and (info.isSalvageRecipe or info.isEnchantingRecipe or info.isRecraft) then
                return false, L("WF_NATIVE_ONLY", "%s needs native crafting controls and cannot be queued. Craft it in your profession window.", node.name)
            end
        end
    end
    local data = Data()
    snapshot.id = data.nextID
    data.nextID = data.nextID + 1
    snapshot.crafter = UnitName("player")
    snapshot.createdAt = GetServerTime and GetServerTime() or nil
    target = tonumber(target)
    if target and target >= 1 and target <= 100000 and target % 1 == 0 and target ~= snapshot.target then
        snapshot.target = target
        Plan.RecalculateBreakEven(snapshot)
    end
    data.plans[#data.plans + 1] = snapshot
    local notes = {}
    notes[#notes + 1] = Plan.StockWarning(snapshot)
    notes[#notes + 1] = Plan.ProfitWarning(result)
    notes[#notes + 1] = Plan.AvailabilityWarning(snapshot)
    notes[#notes + 1] = Plan.HistoryWarning(snapshot)
    notes[#notes + 1] = Plan.CooldownWarning(snapshot)
    local okGold, goldNote = pcall(Plan.GoldWarning)
    notes[#notes + 1] = okGold and goldNote or nil
    local warning = #notes > 0 and table.concat(notes, " ") or nil
    if warning then
        -- Shown in the queue's status line (and chat); the plan is still added.
        Notify(L("WF_ADDED_PLAN", "Added %s. Quantities use base yields, without bonus procs.", snapshot.name) .. " " .. warning)
    else
        Notify(L("WF_ADDED_PLAN", "Added %s. Quantities use base yields, without bonus procs.", snapshot.name), "summary")
    end
    return true, snapshot
end
-- Optional minimum profit per craft (Settings; 0 = off): a note, never a block.
function Plan.MinProfit()
    local value = tonumber(GAM.db and GAM.db.options and GAM.db.options.minProfitPerCraft) or 0
    return value > 0 and value or nil
end
function Plan.ProfitWarning(result)
    local minimum, perCraft = Plan.MinProfit(), result and tonumber(result.profitPerCraft)
    -- A loss at today's prices is always worth a note (a Queue button or an
    -- old habit can add a strategy whose market has since dropped).
    if perCraft and perCraft < 0 then
        return L("WF_CURRENT_LOSS", "At current prices each craft loses %s.", GAM.Pricing.FormatPrice(math.floor(-perCraft)))
    end
    if not (minimum and perCraft) or perCraft >= minimum then return nil end
    return L("WF_BELOW_MIN_PROFIT", "Profit per craft %s is below your minimum %s.",
        GAM.Pricing.FormatPrice(math.floor(perCraft)), GAM.Pricing.FormatPrice(minimum))
end
-- A note when the Auction House did not have enough of a material at the
-- last scan: the plan may stall at Quick Buy. The whole queue's need is
-- compared (two plans can share a material), for the materials this plan
-- uses. Vendor materials are skipped.
-- none: an item known to be unavailable right now (a purchase just failed),
-- whatever the last scan said: only what you own of it counts.
function Plan.AvailabilityWarning(plan, none)
    local scan = GAM.AHScan
    if not (scan and scan.GetRawScanSnapshot and GAM.CraftPlanModel) then return nil end
    local plans, included = {}, false
    for _, saved in ipairs(Data().plans) do
        plans[#plans + 1] = saved
        if saved == plan then included = true end
    end
    if not included then plans[#plans + 1] = plan end
    local ok, own = pcall(GAM.CraftPlanModel.Project, { plan }, Count)
    local okAll, projection = pcall(GAM.CraftPlanModel.Project, plans, Count)
    if not (ok and okAll and type(own) == "table" and type(projection) == "table") then return nil end
    local uses = {}
    for _, buy in ipairs(own.buys or {}) do uses[buy.itemID] = true end
    local short = {}
    for _, buy in ipairs(projection.buys or {}) do
        if not uses[buy.itemID] then buy = nil end
        if buy then
        local vendor = GAM.VendorPrices and GAM.VendorPrices.IsVendorItem and GAM.VendorPrices.IsVendorItem(buy.itemID)
        local snapshot = not vendor and scan.GetRawScanSnapshot(buy.itemID)
        if buy.itemID == none then snapshot = { prices = {} } end
        if snapshot and snapshot.prices then
            local listed = 0
            for _, row in ipairs(snapshot.prices) do
                listed = listed + math.max(0, (row.quantity or 0) - (row.mine and (tonumber(row.numMine) or 0) or 0))
            end
            -- A scan that stopped at the depth it needed (full == false) only
            -- shows a lower bound: never call that short.
            if listed < buy.quantity and snapshot.full ~= false then
                short[#short + 1] = L("WF_SHORT_ITEM", "%d of %d %s", listed, buy.quantity,
                    buy.name or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(buy.itemID)) or "?")
            end
        end
        end
    end
    if #short == 0 then return nil end
    return L("WF_SHORT_ON_AH", "Only %s listed at your last scan; buying may stall. Lower the craft count or wait.",
        table.concat(short, ", ", 1, math.min(#short, 2)))
end
-- The largest craft count (at least the crafts done) whose materials the
-- last scan showed on the Auction House, with the rest of the queue.
-- none: the item a purchase just failed on (see AvailabilityWarning).
function Plan.FitCrafts(plan, none)
    local original = plan.target
    local low, high = plan.completed or 0, original
    plan.target = high
    if not Plan.AvailabilityWarning(plan, none) then return high end
    while low < high do
        local mid = math.floor((low + high + 1) / 2)
        plan.target = mid
        if Plan.AvailabilityWarning(plan, none) then high = mid - 1 else low = mid end
    end
    plan.target = original
    return low
end

-- The purchase of itemID just failed. When the last scan showed less than
-- was needed, it is believable and the fit uses it; when it showed enough
-- (or there is no scan), it is out of date, so only owned units count.
function Plan.MarkShort(plan, itemID, requested)
    plan.marketShort = { itemID = itemID, at = GetServerTime and GetServerTime() or 0 }
    local snapshot = GAM.AHScan and GAM.AHScan.GetRawScanSnapshot and GAM.AHScan.GetRawScanSnapshot(itemID)
    local listed = 0
    for _, row in ipairs(snapshot and snapshot.prices or {}) do
        listed = listed + math.max(0, (row.quantity or 0) - (row.mine and (tonumber(row.numMine) or 0) or 0))
    end
    local scanWrong = not snapshot or listed >= (requested or math.huge)
    plan.marketShort.fit = math.min(plan.target, Plan.FitCrafts(plan, scanWrong and itemID or nil))
end

-- Lower a short plan to what the Auction House can supply.
function Plan.FitToMarket(plan)
    local fit = plan.marketShort and plan.marketShort.fit or Plan.FitCrafts(plan)
    -- Nothing more to buy: a plan with crafts done finishes at those.
    if fit < (plan.completed or 0) or (fit < 1 and (plan.completed or 0) > 0) then fit = plan.completed end
    if fit < math.max(1, plan.completed or 0) then return false, L("WF_SHORT_NOTHING", "The Auction House cannot supply even one more craft; remove the plan or retry later.") end
    local ok, err = Plan.SetTarget(plan, fit)
    if ok then plan.marketShort = nil end
    return ok, err
end

function Plan.RetryShort(plan)
    plan.marketShort = nil
    Notify(L("WF_SHORT_RETRY", "%s will buy again; scan first so the prices and amounts are current.", plan.name))
    return true
end

-- Realized profit of this strategy's batches in the last `days` days, from
-- History (finished plans; profit counts sold items at what they cost).
-- Returns total copper and the number of batches, or nil when none.
function Plan.RecentResult(strategyID, days)
    local history, analysis = GAM.CraftHistory, GAM.CraftHistoryAnalysis
    if not (strategyID and history and analysis and analysis.Batches and history.ArchivedPlans) then return nil end
    local since = (GetServerTime and GetServerTime() or 0) - (days or 30) * 86400
    local records = {}
    for _, record in ipairs(history.ArchivedPlans()) do
        if record.strategyID == strategyID and (record.archivedAt or 0) >= since then records[#records + 1] = record end
    end
    if #records == 0 then return nil end
    local market = GAM.Posting and GAM.Posting.MarketPrice
    local ahCut = GAM.Posting and GAM.Posting.Options().ahCut or 0.05
    local total, counted = 0, 0
    for _, batch in ipairs(analysis.Batches(records, history.Events(), history.PlanPurchases, market, ahCut,
            function(record) return (history.MaterialCost(record.consumed, record.id, market)) end)) do
        if batch.realized and batch.sold > 0 then total, counted = total + batch.realized, counted + 1 end
    end
    if counted == 0 then return nil end
    return total, counted
end

-- A note when this strategy's recent batches lost gold: the estimate can
-- look good while your own results say otherwise.
function Plan.HistoryWarning(plan)
    local total, count = Plan.RecentResult(plan and plan.strategyID, 30)
    if not total or total >= 0 then return nil end
    return L("WF_RECENT_LOSS", "Your last %d batches of this lost %s after costs (History).", count,
        GAM.Pricing.FormatPrice(-total))
end

-- A note when a cooldown recipe has fewer charges ready than the plan's
-- crafts: the rest wait for charges (and their materials wait in bags).
function Plan.CooldownWarning(plan)
    local tracker = GAM.CooldownTracker
    local node = plan and plan.nodes and plan.nodes[plan.root]
    if not (tracker and tracker.GetImmediateCraftCapacity and node) then return nil end
    local ok, ready = pcall(tracker.GetImmediateCraftCapacity, node.recipeID)
    local left = (plan.target or 0) - (plan.completed or 0)
    if not ok or type(ready) ~= "number" or ready >= left then return nil end
    return L("WF_COOLDOWN_SHORT", "Only %d of these %d crafts are ready now (cooldown); the rest wait for charges.", ready, left)
end

-- A note when the player already owns plenty of what the plan makes.
function Plan.StockWarning(plan)
    local stock = GAM.Stock
    local node = plan and plan.nodes and plan.nodes[plan.root]
    if not (stock and node) then return nil end
    local ids = node.outputItemID and { node.outputItemID } or node.outputs or {}
    return stock.QueueWarning(ids, (plan.target or 0) * (node.baseYield or 0))
end
-- Up-front gold for this strategy alone: the exact materials Add to Queue
-- would put on the shopping list (base yields, no procs, owned items used
-- first). Returns nil when any price is missing rather than understating.
function Plan.EstimatePurchaseCost(strat, patchTag, result)
    if not (strat and result and GAM.Pricing and GAM.Pricing.BuildCraftPlanSnapshot) then return nil end
    local ok, snapshot = pcall(GAM.Pricing.BuildCraftPlanSnapshot, strat, patchTag, result)
    if not ok or type(snapshot) ~= "table" then return nil end
    for _, node in pairs(snapshot.nodes) do
        if Plan.PrepareRecipeType then pcall(Plan.PrepareRecipeType, node) end
    end
    local projected, projection = pcall(GAM.CraftPlanModel.Project, { snapshot }, Count)
    if not projected then return nil end
    local total = 0
    for _, buy in ipairs(projection.buys) do
        -- Real Auction House spend: manual input prices do not apply here.
        local price = GAM.Pricing.GetMarketPrice(buy.itemID, patchTag, buy.quantity)
        if not price then return nil end
        total = total + price * buy.quantity
    end
    return total
end

-- Materials the plan's batches used, less the intermediate items the plan
-- crafted itself (their materials are already counted; bought ones are not).
-- nil for plans from before tracking.
function Plan.UsedMaterials(plan)
    if not plan.consumed then return nil end
    local crafted, used = plan.intermediateOutputs or {}, {}
    for itemID, qty in pairs(plan.consumed) do
        local bought = qty - (crafted[itemID] or 0)
        if bought > 0 then used[itemID] = bought end
    end
    return next(used) and used or nil
end

-- A plan's results as History keeps them: what it made and its break-even.
function Plan.BatchRecord(plan)
    local record = { id = plan.id, name = plan.name, strategyID = plan.strategyID, patchTag = plan.patchTag,
        createdAt = plan.createdAt, completed = plan.completed, consumed = Plan.UsedMaterials(plan),
        extra = plan.optionalExtra or nil, ownUse = plan.ownUse or nil,
        target = plan.target, finalOutputs = {}, outputs = {}, breakEven = {} }
    local finalEstimate = plan.breakEven or (Plan.OutputBreakEven and Plan.OutputBreakEven(plan, plan.root))
    for id, qty in pairs(plan.outputs or {}) do
        record.finalOutputs[id], record.outputs[id] = qty, qty
        record.breakEven[id] = finalEstimate and math.ceil(finalEstimate) or nil
    end
    for key, node in pairs(plan.nodes or {}) do
        if key ~= plan.root then
            for _, id in ipairs(node.outputs or {}) do
                local qty = (plan.intermediateOutputs or {})[id] or 0
                if qty > 0 then
                    record.outputs[id] = (record.outputs[id] or 0) + qty
                    local estimate = Plan.OutputBreakEven and Plan.OutputBreakEven(plan, key)
                    record.breakEven[id] = record.breakEven[id] or (estimate and math.ceil(estimate)) or nil
                end
            end
        end
    end
    return record
end

-- Adds a strategy again with a set number of crafts (History's Craft more).
function Plan.QueueMore(strategyID, patchTag, crafts)
    local importer = GAM.Importer
    local strat = importer and importer.GetStratByID and importer.GetStratByID(strategyID)
    if not strat then return false, L("WF_STRAT_MISSING", "That strategy is no longer available.") end
    local ok, plan = Plan.Add(strat, patchTag or strat.patchTag, math.max(1, math.floor(crafts)))
    if not ok then return ok, plan end
    -- History's count follows your sales; the Auction House may not have the
    -- materials for all of it. Queue what the last scan can supply, so a
    -- half-bought plan does not tie up gold.
    if Plan.AvailabilityWarning(plan) then
        local asked, fit = plan.target, Plan.FitCrafts(plan)
        if fit < 1 then
            Plan.Remove(plan)
            return false, L("WF_QUEUE_NO_MATS", "Not queued: your last scan did not show the materials for even one craft.")
        end
        Plan.SetTarget(plan, fit)
        Notify(L("WF_QUEUE_FITTED", "Queued %d of %d crafts: your last scan showed materials for %d.", fit, asked, fit))
    end
    return true, plan
end

-- Saves a finished plan's results to History, then removes it from the queue.
function Plan.Archive(plan, automatic)
    if pending then return false end
    local history = GAM.CraftHistory
    if history then history.ArchivePlan(Plan.BatchRecord(plan)) end
    for i, saved in ipairs(Data().plans) do
        if saved == plan then table.remove(Data().plans, i); break end
    end
    Notify(automatic and L("WF_PLAN_ARCHIVED_AUTO", "%s is finished and its items are gone; it moved to History.", plan.name)
        or L("WF_PLAN_ARCHIVED", "%s cleared. Its results stay in History.", plan.name), "summary")
    if GAM.Posting and GAM.Posting.Changed then GAM.Posting.Changed() end
    return true
end

function Plan.IsFinished(plan)
    return plan.completed >= plan.target and not plan.needsReview
end

-- True when nothing the plan made is left: not in bags or banks, not
-- waiting in the mailbox, and not still listed as far as GAM knows.
function Plan.OutputsGone(plan)
    local stock = GAM.Stock
    local ids = {}
    for id in pairs(plan.outputs or {}) do ids[id] = true end
    for id in pairs(plan.intermediateOutputs or {}) do ids[id] = true end
    for id in pairs(ids) do
        if Count(id) > 0 then return false end
        if stock and (stock.Listed(id) > 0 or stock.InMail(id) > 0) then return false end
    end
    return true
end

function Plan.ArchiveFinished()
    if pending then return end
    local plans = Data().plans
    for index = #plans, 1, -1 do
        local plan = plans[index]
        if Plan.IsFinished(plan) and Plan.OutputsGone(plan) then Plan.Archive(plan, true) end
    end
end

function Plan.Remove(plan)
    if pending then return false end
    -- Crafts already made keep their batch (items, materials used, cost) in
    -- History; only an untouched plan is simply dropped.
    if (plan.completed or 0) > 0 or next(plan.consumed or {}) then return Plan.Archive(plan) end
    for i, saved in ipairs(Data().plans) do
        if saved == plan then table.remove(Data().plans, i); Notify(L("WF_REMOVED_PLAN", "Plan removed; reservations released."), "summary"); return true end
    end
end
-- Keep the queue's break-even on the same basis as Details (expected yields,
-- including bonus procs) for the plan's remaining crafts. When it cannot be
-- priced, the queue falls back to its base-yield replacement estimate.
function Plan.RecalculateBreakEven(plan)
    plan.breakEven = nil
    local strat = GAM.Importer and GAM.Importer.GetStratByID and GAM.Importer.GetStratByID(plan.strategyID)
    local facade = GAM.PricingFacade
    if not (strat and facade and facade.CalculateForCrafts) or plan.optionalExtra then return end
    local ok, result = pcall(facade.CalculateForCrafts, strat, plan.patchTag,
        math.max(1, plan.target - plan.completed))
    if ok and type(result) == "table" then plan.breakEven = result.breakEvenSell end
end
function Plan.SetTarget(plan, target)
    target = tonumber(target)
    if pending or plan.needsReview or not target or target % 1 ~= 0 or target < math.max(1, plan.completed) or target > 100000 then
        return false, L("WF_TARGET_INVALID", "Enter a whole craft count between completed crafts and 100,000.")
    end
    if target == plan.target then return true end
    plan.target = target
    Plan.RecalculateBreakEven(plan)
    plan.estimateInvalid = true
    plan.revision = (plan.revision or 0) + 1
    plan.marketShort = nil
    local short = Plan.AvailabilityWarning(plan) or Plan.CooldownWarning(plan)
    Notify(L("WF_TARGET_UPDATED", "Final craft count updated; remaining materials recalculated.") .. (short and (" " .. short) or ""))
    return true
end
function Plan.ReviewProgress(plan, completed)
    completed = tonumber(completed)
    if pending or not completed or completed % 1 ~= 0 or completed < 0 or completed > plan.target then return false end
    plan.completed = completed
    plan.needsReview = nil
    Notify(L("WF_PROGRESS_CONFIRMED", "Recorded progress confirmed. Inventory will be checked before crafting."))
    return true
end

-- Resolve the frozen rank mix into the current client schematic. Reject omitted
-- required reagents and changed quantities rather than using Blizzard defaults.
function Plan.BeginProgressReview(plan)
    if pending then return false end
    plan.needsReview = true
    Notify(L("WF_REVIEW_TOTAL", "Confirm this plan's total completed final crafts, including any crafted outside GAM."))
    return true
end

function Plan.BuildAllocation(node, schematic)
    local allocation, used = {}, {}
    for _, reagent in ipairs(node.reagents) do
        if type(reagent.itemID) ~= "number" or reagent.itemID <= 0
                or type(reagent.quantity) ~= "number" or reagent.quantity <= 0
                or reagent.quantity % 1 ~= 0 then
            return nil, L("WF_WHOLE_REAGENT_REQUIRED", "Recipe needs a verified whole-craft reagent quantity: %s", node.name or "?")
        end
    end
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local total = 0
        for i, reagent in ipairs(node.reagents) do
            local matches = false
            for _, allowed in ipairs(slot.reagents or {}) do
                if allowed.itemID == reagent.itemID then matches = true; break end
            end
            if matches and not used[i] then
                total = total + reagent.quantity
                -- Native CreateCraftingReagentInfoTbl sends only ModifiedReagent
                -- slots. Fixed Reagent slots are consumed automatically; their
                -- indices belong to a separate namespace and can invalidate the
                -- operation query if passed as selectable allocations.
                local modified = Enum and Enum.TradeskillSlotDataType and Enum.TradeskillSlotDataType.ModifiedReagent or 2
                if reagent.itemID ~= node.targetItemID and (slot.dataSlotType == modified or slot.dataSlotType == nil) then
                    allocation[#allocation + 1] = { reagent = { itemID = reagent.itemID },
                        dataSlotIndex = slot.dataSlotIndex, quantity = reagent.quantity }
                end
                used[i] = true
            end
        end
        if (slot.required or total > 0) and total ~= slot.quantityRequired then
            return nil, L("WF_MATERIALS_CHANGED", "Recipe materials changed or a required reagent is missing. Remove and re-add this plan after Refresh Recipe.")
        end
    end
    for i in ipairs(node.reagents) do
        if not used[i] and node.reagents[i].itemID ~= node.targetItemID then return nil, L("WF_MATERIAL_RANK_MISMATCH", "A saved material rank does not match this recipe.") end
    end
    return allocation
end

local function LiveStatsMatch(node, allocation, target)
    if not node.plannedStats then return true end
    if not (GAM.CraftingStats and GAM.CraftingStats.ReadPlannedOperation) then return false end
    local live = GAM.CraftingStats.ReadPlannedOperation(node.recipeID, allocation,
        target and C_Item.GetItemGUID(target) or nil)
    if not live or node.gearStatValidity == "unobserved" then return false end
    -- A saved profession set is authoritative until the user saves it again;
    -- Preflight already verifies its exact equipment. Buffs or node-scaled
    -- estimates can differ slightly from live chances without changing gear.
    local fields = node.gearRequirement and { "multiExtra", "resExtra" }
        or { "multiPercent", "resPercent", "multiExtra", "resExtra" }
    for _, field in ipairs(fields) do
        local expected = node.plannedStats[field]
        -- A temporary crafting buff (Shattered Essence) only raises the
        -- chances; crafting with more than planned is fine.
        local boosted = live.temporaryBuff and (field == "multiPercent" or field == "resPercent")
            and expected ~= nil and (live[field] or 0) >= expected - 0.01
        if expected ~= nil and not boosted and ((live[field] == nil and expected ~= 0)
                or math.abs((live[field] or 0) - expected) >= 0.01) then return false end
    end
    return not node.plannedStats.nodeHash or live.nodeHash == node.plannedStats.nodeHash
end

function Plan.Preflight(task)
    local api = C_TradeSkillUI
    if not api then return nil, L("WF_OPEN_PROFESSION", "Open your profession first.") end
    if task.plan.paused then return nil, L("WF_STRATEGY_PAUSED", "This strategy is paused.") end
    if task.plan.needsReview then return nil, L("WF_INTERRUPTED_REVIEW", "Confirm recorded progress after the interrupted session.") end
    if task.ready <= 0 then return nil, L("WF_MISSING_RESERVED", "Materials are missing or reserved for an earlier step. Buy or collect the missing items.") end
    if InCombatLockdown and InCombatLockdown() then return nil, L("WF_LEAVE_COMBAT", "Leave combat before crafting.") end
    if UnitCastingInfo and UnitCastingInfo("player") then return nil, L("WF_WAIT_CAST", "Wait for your current cast to finish.") end
    if api.IsTradeSkillLinked and api.IsTradeSkillLinked() then return nil, L("WF_OWN_PROFESSION", "Open your own profession.") end
    if api.IsTradeSkillGuild and api.IsTradeSkillGuild() then return nil, L("WF_OWN_PROFESSION", "Open your own profession.") end
    -- Operation data must come from the queued recipe's loaded form, not the
    -- recipe left selected after the previous batch (or a manual selection).
    local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
    if form and form.GetRecipeInfo then
        local selected = form:GetRecipeInfo()
        if not selected or selected.recipeID ~= task.node.recipeID then
            return nil, L("WF_OPEN_CHECK_RANK", "Open %s to check this step's output rank.", task.node.name), "open-recipe"
        end
    end
    local info = api.GetRecipeInfo(task.node.recipeID)
    if not info or not info.learned then return nil, L("WF_RECIPE_UNKNOWN", "Open this recipe on a character who knows it.") end
    local gear = GAM.CraftingStatsGear
    if task.node.gearRequirement and (not gear or not gear.IsEquipped(
            task.node.gearRequirement, task.node.recipeID, task.node.statProfileKey)) then
        return nil, L("WF_GEAR_REQUIRED", "Equip the saved %s set on %s, then retry.",
            task.node.gearMode == "multicraft" and L("GEAR_MODE_MC", "Multicraft") or L("GEAR_MODE_RES", "Resourcefulness"),
            task.node.gearRequirement.uid), "gear-required"
    end
    if info.disabled or info.craftable == false then return nil, info.disabledReason or L("WF_RECIPE_UNAVAILABLE", "Recipe is unavailable here.") end
    if info.isRecraft then
        return nil, L("WF_MANUAL_RECIPE", "This saved recipe needs native controls. Craft it there, then confirm total completed crafts here."), "manual"
    end
    if (info.isSalvageRecipe and task.node.craftType ~= "salvage")
        or (info.isEnchantingRecipe and task.node.craftType ~= "enchant") then
        return nil, L("WF_TARGET_REQUIRED", "This job needs a saved input target. Use current setup before buying materials."), "setup-mismatch"
    end
    for _, requirement in ipairs(api.GetRecipeRequirements(task.node.recipeID) or {}) do
        if not requirement.met then return nil, requirement.name or L("WF_REQUIREMENT_UNMET", "A recipe requirement is not met.") end
    end
    local schematic = api.GetRecipeSchematic(task.node.recipeID, false)
    if not schematic then return nil, L("WF_LOAD_MATERIALS", "Open the recipe to load its materials.") end
    local minYield = not info.isSalvageRecipe and tonumber(schematic.quantityMin)
    if not task.final and minYield and minYield < task.node.baseYield then
        return nil, L("WF_YIELD_CHANGED", "Base recipe yield changed. Use the current setup to update remaining materials without losing progress."), "setup-mismatch"
    end
    local allocation, err = Plan.BuildAllocation(task.node, schematic)
    if not allocation then return nil, err, "setup-mismatch" end
    if task.node.gearMode and task.node.gearMode ~= "current" and not task.node.gearRequirement then
        return nil, L("WF_GEAR_UNVERIFIED", "Save this profession's equipment set, then use current setup."), "setup-mismatch"
    end
    local target, targetCapacity
    if task.node.craftType then
        if not Plan.FindCraftTarget then return nil, L("WF_TARGET_UNAVAILABLE", "Selected-item crafting is unavailable.") end
        target, targetCapacity = Plan.FindCraftTarget(task.node)
        if not target then return nil, L("WF_TARGET_LOCKED", "The saved input item needs an unlocked stack in your bags.") end
        if info.isSalvageRecipe then
            local valid = false
            for _, id in ipairs(api.GetSalvagableItemIDs(task.node.recipeID) or {}) do
                if id == task.node.targetItemID then valid = true end
            end
            if not valid or schematic.quantityMax ~= task.node.targetQuantity then
                return nil, L("WF_SALVAGE_CHANGED", "The saved salvage input changed. Use current setup."), "setup-mismatch"
            end
        end
    end
    if not LiveStatsMatch(task.node, allocation, target) then
        return nil, L("WF_GEAR_STATS_CHANGED", "Live recipe stats differ from this estimate. Use current setup before crafting."), "setup-mismatch"
    end
    if info.supportsQualities then
        if not task.node.targetQuality then
            return nil, L("WF_SAVED_RANK_UNKNOWN", "Saved output rank is unknown. Refresh Recipe in Details, then use the current setup here."), "setup-mismatch"
        end
        local operation = api.GetCraftingOperationInfo(task.node.recipeID, allocation,
            target and C_Item.GetItemGUID(target) or nil, false)
        local quality = operation and (tonumber(operation.craftingQuality) or tonumber(operation.quality))
        local target = tonumber(task.node.targetQuality)
        if not quality or quality <= 0 then
            return nil, L("WF_NO_OUTPUT_RANK", "Blizzard has not returned an output rank. Reopen this recipe to retry verification."), "open-recipe"
        end
        -- A higher final rank also changes the item whose sale price was used.
        if not quality or not target or quality ~= target then
            return nil, string.format(L("WF_RANK_MISMATCH", "Saved rank: %s. Current output without Concentration: %s. %s"),
                tostring(target or L("WF_UNKNOWN", "unknown")), tostring(quality or L("WF_UNKNOWN", "unknown")),
                task.final and L("WF_EQUIP_OR_READD", "Equip the intended gear or re-add the plan with current recipe stats.")
                    or L("WF_EXACT_RANK_REQUIRED", "The next step requires the exact saved material rank.")), "rank-mismatch"
        end
    end
    local capacity = GAM.CooldownTracker and GAM.CooldownTracker.GetImmediateCraftCapacity(task.node.recipeID)
    local amount = math.min(task.crafts, task.ready, capacity or task.ready, targetCapacity or task.ready)
    if amount < 1 then return nil, L("WF_ON_COOLDOWN", "This recipe is on cooldown."), "cooldown" end
    if not GetStopRepeat() then return nil, L("WF_STOP_UNAVAILABLE", "The client crafting stop control is unavailable.") end
    return allocation, math.floor(amount), nil, target
end

function Plan.Craft(task)
    if pending then return false end
    -- Button closures may predate an inventory event; locate the fresh task.
    local fresh
    for _, candidate in ipairs(Plan.Project().tasks) do
        if candidate.plan == task.plan and candidate.node.key == task.node.key then fresh = candidate; break end
    end
    if not fresh then Notify(L("WF_STEP_SATISFIED", "This step is already satisfied.")); return false end
    local ok, allocation, amount, _, target = pcall(Plan.Preflight, fresh)
    if not ok or not allocation then Notify(ok and amount or tostring(allocation)); return false end
    pending = { task = fresh, requested = amount, confirmed = 0, results = {}, lastActivity = GetTime(), target = target,
        startCounts = {} }
    -- Materials on hand now; what is missing at the end of the batch was used
    -- (resourcefulness savings stay in bags and are not counted).
    for _, reagent in ipairs(fresh.node.reagents or {}) do pending.startCounts[reagent.itemID] = Count(reagent.itemID) end
    if fresh.node.targetItemID then pending.startCounts[fresh.node.targetItemID] = Count(fresh.node.targetItemID) end
    -- Saved: after a /reload or disconnect mid-batch the start counts still
    -- tell what the batch used.
    Data().inFlight = { planID = fresh.plan.id, nodeKey = fresh.node.key, startCounts = pending.startCounts }
    Notify(L("WF_CRAFTING_NOTICE", "Crafting %s. Each new recipe requires a click.", fresh.node.name))
    -- Retain the user's hardware event through the actual submission.
    local submitted, failure = pcall(function()
        if fresh.node.craftType == "salvage" then
            C_TradeSkillUI.CraftSalvage(fresh.node.recipeID, amount, target, allocation, false)
        elseif fresh.node.craftType == "enchant" then
            C_TradeSkillUI.CraftEnchant(fresh.node.recipeID, amount, allocation, target, false)
        else
            C_TradeSkillUI.CraftRecipe(fresh.node.recipeID, amount, allocation, nil, nil, false)
        end
    end)
    if not submitted then pending = nil; Data().inFlight = nil; Notify(tostring(failure)); return false end
    return true
end
function Plan.OpenRecipe(task)
    if pending then return end
    if not (C_TradeSkillUI and C_TradeSkillUI.OpenRecipe) then Notify(L("WF_OPEN_PROFESSION", "Open your profession first.")); return end
    local ok, err = pcall(C_TradeSkillUI.OpenRecipe, task.node.recipeID)
    Notify(ok and L("WF_RECIPE_OPENED", "Recipe opened. Verify gear, then click Craft.") or tostring(err))
end
function Plan.EquipGear(task)
    if pending then return end
    local node = task.node
    local gear = GAM.CraftingStatsGear
    if not (gear and gear.Equip) then return end
    local ok, done, message = pcall(gear.Equip, node.gearRequirement, node.recipeID, node.statProfileKey)
    Notify(ok and message or tostring(done))
end
function Plan.Stop()
    if not pending then return end
    pending.stopping = true
    local stop = GetStopRepeat()
    if stop then stop() end
    Notify(L("WF_STOPPING_NOTICE", "Stopping after the current craft; confirmed progress will be kept."))
end

-- Adds what the batch used to its plan (plan.consumed = {[itemID] = qty}).
local function RecordUse(batch)
    if not (batch and batch.confirmed > 0 and batch.startCounts) then return end
    local plan, outputs = batch.task.plan, {}
    for _, id in ipairs(batch.task.node.outputs or {}) do outputs[id] = true end
    plan.consumed = plan.consumed or {}
    for itemID, before in pairs(batch.startCounts) do
        local used = before - Count(itemID)
        if used > 0 and not outputs[itemID] then plan.consumed[itemID] = (plan.consumed[itemID] or 0) + used end
    end
end
Plan.RecordUse = RecordUse

local function EndBatch()
    if not pending then return end
    pcall(RecordUse, pending)
    pending = nil
    Data().inFlight = nil
    Notify(L("WF_BATCH_FINISHED", "Batch finished. Remaining requirements now use your current bags and banks."))
end
function Plan.OnEvent(event, ...)
    local data = Data()
    if event == "BAG_UPDATE_DELAYED" then
        if not pending then pcall(Plan.ArchiveFinished) end
        if pending and not pending.task.final and pending.confirmed > 0 and not pending.stopping then
            local needed = false
            for _, task in ipairs(Plan.Project().tasks) do
                if task.plan == pending.task.plan and task.node.key == pending.task.node.key then needed = true; break end
            end
            if not needed then Plan.Stop() end
        end
        Notify()
    elseif not pending and event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, recipeID = ...
        if unit == "player" then
            for _, plan in ipairs(data.plans) do
                if plan.completed < plan.target and plan.nodes[plan.root].recipeID == recipeID then
                    plan.needsReview = true
                    Notify(L("WF_OUTSIDE_CRAFT", "Crafted outside GAM. Confirm total completed crafts for the matching queued plan before continuing."))
                end
            end
        end
    elseif pending and event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, guid, spellID = ...
        if unit == "player" and spellID == pending.task.node.recipeID then
            local task = pending.task
            if GAM.CraftPlanModel.ConfirmCraft(task.plan, task.node, task.final, guid) then
                pending.confirmed = pending.confirmed + 1
                pending.lastActivity = GetTime()
            end
            Notify()
        end
    elseif not pending and event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
        -- Crafted outside the queue: still part of the history when a GAM
        -- strategy makes the item.
        local result = ...
        local capture = GAM.HistoryCapture
        if result and not result.firstCraftReward and (result.quantity or 0) > 0 and GAM.CraftHistory
                and capture and capture.IsOutput(result.itemID) then
            local key = tostring(result.operationID) .. ":" .. tostring(result.itemID) .. ":" .. tostring(result.itemGUID)
            outsideResults = outsideResults or {}
            if not (tonumber(result.operationID) and outsideResults[key]) then
                if tonumber(result.operationID) then outsideResults[key] = true end
                GAM.CraftHistory.Record("craft", { itemID = result.itemID, qty = result.quantity, source = "outside" })
            end
        end
    elseif pending and event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
        local result = ...
        if result and not result.firstCraftReward then
            -- Some recipe results omit a distinct operation ID. Scope those
            -- receipts to the confirmed cast instead of collapsing a batch's
            -- repeated output into one item stack.
            local operation = tonumber(result.operationID)
            local identity = operation and operation > 0 and operation or ("cast:" .. pending.confirmed)
            local key = tostring(identity) .. ":" .. tostring(result.itemID) .. ":" .. tostring(result.itemGUID)
            if not pending.results[key] then
                pending.results[key] = true
                local task = pending.task
                GAM.CraftPlanModel.RecordOutput(task.plan, task.node, result.itemID, result.quantity, task.final)
                if GAM.CraftHistory and result.quantity and result.quantity > 0 then
                    GAM.CraftHistory.Record("craft", { itemID = result.itemID, qty = result.quantity,
                        planID = task.plan.id, source = task.final and "final" or "intermediate" })
                end
                if not task.final and task.node.outputItemID and result.itemID ~= task.node.outputItemID then
                    for _, id in ipairs(task.node.outputs) do
                        if result.itemID == id then
                            Plan.Stop()
                            Notify(L("WF_INTERMEDIATE_RANK_CHANGED", "Intermediate output rank changed. Review the remaining chain before continuing."))
                            break
                        end
                    end
                end
            end
        end
    elseif pending and (event == "UPDATE_TRADESKILL_CAST_STOPPED" or event == "TRADE_SKILL_CLOSE") then
        Plan.Stop()
        pending.ended = true
    elseif pending and (event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED") then
        local unit, _, recipeID = ...
        if unit == "player" and recipeID == pending.task.node.recipeID then Plan.Stop(); pending.ended = true end
    elseif pending and (event == "PLAYER_EQUIPMENT_CHANGED" or event == "TRAIT_CONFIG_UPDATED"
            or event == "SKILL_LINES_CHANGED" or (event == "UNIT_AURA" and (...) == "player")) then
        -- Recheck the actual recipe rather than stopping for every armor swap.
        local node = pending.task.node
        if node.targetQuality or node.gearRequirement or node.plannedStats then
            local ok, valid = pcall(function()
                if node.gearRequirement and not GAM.CraftingStatsGear.IsEquipped(
                        node.gearRequirement, node.recipeID, node.statProfileKey) then return false end
                local schematic = C_TradeSkillUI.GetRecipeSchematic(node.recipeID, false)
                local allocation = schematic and Plan.BuildAllocation(node, schematic)
                if not allocation or not LiveStatsMatch(node, allocation, pending.target) then return false end
                if not node.targetQuality then return true end
                local op = C_TradeSkillUI.GetCraftingOperationInfo(node.recipeID, allocation,
                    pending.target and C_Item.GetItemGUID(pending.target) or nil, false)
                local rank = op and (tonumber(op.craftingQuality) or tonumber(op.quality))
                return rank == node.targetQuality
            end)
            if not ok or not valid then Plan.Stop() end
        end
    elseif event == "PLAYER_LOGOUT" then
        local stop = GetStopRepeat()
        if pending and stop then stop() end
    else
        Notify()
    end
end

-- Materials still to buy, leaving out plans waiting on a short material
-- (they buy nothing until lowered or retried): { itemID, name, quantity, plans }.
function Plan.OpenBuys(projection)
    projection = projection or Plan.Project()
    local held = {}
    for _, plan in ipairs(Data().plans) do if plan.marketShort then held[plan.id] = true end end
    if not next(held) then return projection.buys end
    local open = {}
    for _, entry in ipairs(projection.buys) do
        local quantity, plans = entry.quantity, {}
        for planID, need in pairs(entry.plans or {}) do
            if held[planID] then quantity = quantity - need else plans[planID] = need end
        end
        if quantity > 0 then
            open[#open + 1] = { itemID = entry.itemID, name = entry.name, quantity = quantity, plans = plans }
        end
    end
    return open
end

-- What the queue's materials still to buy cost, at the prices Quick Buy
-- expects (vendor or Auction House).
function Plan.OpenBuysCost()
    local resolve = GAM.VendorPrices and GAM.VendorPrices.ResolvePurchase
    local total = 0
    for _, entry in ipairs(Plan.OpenBuys()) do
        local unit
        if resolve then unit = select(2, resolve(entry.itemID, entry.quantity)) end
        unit = tonumber(unit) or (GAM.Pricing and GAM.Pricing.GetUnitPrice and GAM.Pricing.GetUnitPrice(entry.itemID)) or 0
        total = total + unit * entry.quantity
    end
    return math.floor(total)
end

-- A note when the queue's materials cost more than the gold on hand: Quick
-- Buy would spend it all on part of each plan and none could be crafted.
function Plan.GoldWarning()
    local money = GetMoney and tonumber(GetMoney())
    if not money then return nil end
    local cost = Plan.OpenBuysCost()
    if cost <= money then return nil end
    return L("WF_QUEUE_OVER_GOLD", "The queue's materials cost %s and you have %s; lower a plan so each can be finished.",
        GAM.Pricing.FormatPrice(cost), GAM.Pricing.FormatPrice(money))
end

function Plan.CreateShoppingList(itemID)
    local list = { entries = {}, vendorEntries = {}, craftPlan = true }
    for _, entry in ipairs(Plan.OpenBuys()) do
        local quantity, plans = entry.quantity, entry.plans
        if not itemID or entry.itemID == itemID then
            local source, price = GAM.VendorPrices.ResolvePurchase(entry.itemID, quantity)
            local copy = { itemID = entry.itemID, name = entry.name, quantity = quantity, unitPrice = price,
                plans = plans }
            local target = source == "vendor" and list.vendorEntries or list.entries
            target[#target + 1] = copy
        end
    end
    list.validatePurchase = function(entry, quantity)
        if not pending and entry then
            for _, plan in ipairs(Data().plans) do
                if plan.needsReview then
                    for _, node in pairs(plan.nodes) do
                        for _, reagent in ipairs(node.reagents) do
                            if reagent.itemID == entry.itemID then
                                return false, L("WF_REVIEW_BEFORE_BUY", "Confirm completed crafts in Craft Queue before buying more of this plan's materials.")
                            end
                        end
                    end
                end
            end
            for _, missing in ipairs(Plan.Project().buys) do
                if missing.itemID == entry.itemID and quantity and quantity <= missing.quantity then return true end
            end
        end
        return false, L("WF_SHORTAGE_CHANGED", "Requirements changed. Select the material in Shopping again to review the current shortage.")
    end
    -- The Auction House does not have enough of this material: stop buying
    -- for the plans that need it (their other materials would sit unused),
    -- keep buying for the rest. Returns a message, or nil for no plans.
    list.onUnavailable = function(entry)
        if not (entry and entry.plans and next(entry.plans)) then return nil end
        local stuck, names = {}, {}
        for _, plan in ipairs(Data().plans) do
            if entry.plans[plan.id] then
                stuck[plan.id] = true
                names[#names + 1] = plan.name
                Plan.MarkShort(plan, entry.itemID, entry.quantity)
            end
        end
        for _, source in ipairs({ list.entries, list.vendorEntries }) do
            for index = #source, 1, -1 do
                local other = source[index]
                if other == entry or other.itemID == entry.itemID then
                    table.remove(source, index)
                elseif other.plans then
                    for planID in pairs(stuck) do
                        local share = other.plans[planID]
                        if share then other.quantity = other.quantity - share; other.plans[planID] = nil end
                    end
                    if other.quantity <= 0 then table.remove(source, index) end
                end
            end
        end
        Notify()
        return L("QB_SHORT_STOPPED", "Not enough %s on the Auction House: stopped buying for %s. Lower it in the Craft Queue, or retry later.",
            entry.name or (C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.itemID)) or "?", table.concat(names, ", "))
    end
    list.onPurchased = function(entry, quantity, fromVendor)
        if fromVendor then return end
        local incoming = Data().incoming
        incoming[entry.itemID] = incoming[entry.itemID] or { quantity = 0, before = Count(entry.itemID) }
        incoming[entry.itemID].quantity = incoming[entry.itemID].quantity + quantity
        Notify(L("WF_PURCHASE_RECORDED", "Auction purchase recorded. Collect it from the mailbox before crafting."))
    end
    return list
end
function Plan.Buy(itemID)
    if pending then return end
    local qb = GAM.QuickBuy.GetController()
    if qb and qb.state.phase ~= "idle" and qb.state.phase ~= "complete" then
        Notify(L("WF_FINISH_PURCHASE", "Finish the current Quick Buy purchase first.")); GAM.QuickBuy.Show(); return
    end
    local list = Plan.CreateShoppingList(itemID)
    if #list.entries + #list.vendorEntries == 0 then Notify(L("WF_NO_MISSING_MATERIALS", "No missing materials to buy.")); return end
    GAM.QuickBuy.SetList(list)
    GAM.QuickBuy.Buy()
end
-- Extra-crafts plans made before 2026-09-29 copied the finished plan's
-- material use. Take the parent's use back out, once: the parent is the plan
-- of the same name made earlier whose use is contained in the extra's (the
-- largest such).
function Plan.RepairExtraUse(extras, sources)
    local suffix = L("WF_EXTRA_NAME", "%s · extra crafts", ""):gsub("^%s+", " ")
    local fixed = 0
    for _, extra in ipairs(extras) do
        local name = extra.name or ""
        local isExtra = extra.optionalExtra or extra.extra
            or (#name > #suffix and name:sub(-#suffix) == suffix)
        if isExtra and not extra.ownUse and extra.consumed then
            local base = name:sub(1, #name - #suffix)
            local parent, parentTotal
            local extraTotal = 0
            for _, qty in pairs(extra.consumed) do extraTotal = extraTotal + qty end
            for _, source in ipairs(sources) do
                if source ~= extra and source.consumed and (source.id or 0) < (extra.id or 0) and source.name == base then
                    local contained, total = true, 0
                    for itemID, qty in pairs(source.consumed) do
                        total = total + qty
                        if (extra.consumed[itemID] or 0) < qty then contained = false end
                    end
                    if contained and total > 0 and (not parentTotal or total > parentTotal) then parent, parentTotal = source, total end
                end
            end
            -- A copied parent is most of what the extra shows; a small plan
            -- that merely fits inside the extra's own use is not its parent.
            if parent and parentTotal * 2 >= extraTotal then
                for itemID, qty in pairs(parent.consumed) do
                    local left = extra.consumed[itemID] - qty
                    extra.consumed[itemID] = left > 0 and left or nil
                end
                if not next(extra.consumed) then extra.consumed = nil end
                fixed = fixed + 1
            end
            extra.ownUse = true   -- checked: never taken out again
        end
    end
    return fixed
end

function Plan.Init()
    if events then return end
    local data = Data()
    local history = GAM.CraftHistory
    local store = history and history.Store and history.Store()
    if not data.extraUseFix and store then
        local sources = {}
        for _, plan in ipairs(data.plans) do sources[#sources + 1] = plan end
        for _, record in ipairs(store.plans or {}) do sources[#sources + 1] = record end
        Plan.RepairExtraUse(sources, sources)
        data.extraUseFix = true
    end
    for _, plan in ipairs(data.plans) do
        for _, node in pairs(plan.nodes or {}) do
            -- Old queue entries never stored the gear used by pricing. Keep
            -- progress and materials, but require explicit setup reconciliation.
            if node.gearMode == nil then node.gearMode = "legacy" end
        end
    end
    -- The queue has no pause/skip state. Restore previously paused entries once
    -- so removing those controls cannot strand an existing saved strategy.
    if data.queueUIVersion ~= 1 then
        for _, plan in ipairs(data.plans) do
            if plan.paused then
                plan.paused = nil
                plan.revision = (plan.revision or 0) + 1
            end
        end
        data.queueUIVersion = 1
    end
    if Plan.InitMail then Plan.InitMail() end
    if data.inFlight then
        for _, plan in ipairs(data.plans) do
            if plan.id == data.inFlight.planID then
                plan.needsReview = true
                -- The interrupted batch's materials: what is missing since it started.
                local node = plan.nodes and plan.nodes[data.inFlight.nodeKey]
                if node and data.inFlight.startCounts then
                    pcall(RecordUse, { confirmed = 1, task = { plan = plan, node = node },
                        startCounts = data.inFlight.startCounts })
                end
            end
        end
        data.inFlight = nil
    end
    events = CreateFrame("Frame")
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "UNIT_SPELLCAST_SUCCEEDED", "TRADE_SKILL_ITEM_CRAFTED_RESULT",
        "UPDATE_TRADESKILL_CAST_STOPPED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "TRADE_SKILL_CLOSE",
        "TRADE_SKILL_SHOW", "CRAFTING_DETAILS_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_LIST_UPDATE", "PLAYER_LOGOUT", "MERCHANT_SHOW", "MERCHANT_CLOSED", "PLAYER_EQUIPMENT_CHANGED",
        "UNIT_AURA", "TRAIT_CONFIG_UPDATED", "SKILL_LINES_CHANGED" }) do events:RegisterEvent(event) end
    events:SetScript("OnEvent", function(_, event, ...) Plan.OnEvent(event, ...) end)
    local elapsed = 0
    events:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        if pending then
            local idle = GetTime() - pending.lastActivity
            local casting = UnitCastingInfo and UnitCastingInfo("player")
            if not casting and idle > 1 and (pending.ended or pending.stopping or pending.confirmed >= pending.requested) then
                EndBatch()
            elseif not casting and idle > 10 then
                Plan.Stop()
                pending.task.plan.needsReview = true
                EndBatch()
                Notify(L("WF_NO_CRAFT_CONFIRMATION", "No craft confirmation received. Review recorded progress before retrying."))
            end
        end
    end)
end
