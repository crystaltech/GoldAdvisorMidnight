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

function Plan.Add(strat, patchTag)
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
    data.plans[#data.plans + 1] = snapshot
    Notify(L("WF_ADDED_PLAN", "Added %s. Quantities use base yields, without bonus procs.", snapshot.name), "summary")
    return true, snapshot
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
        local price = GAM.Pricing.GetEffectivePrice(buy.itemID, patchTag, buy.quantity)
        if not price then return nil end
        total = total + price * buy.quantity
    end
    return total
end

function Plan.Remove(plan)
    if pending then return false end
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
    Notify(L("WF_TARGET_UPDATED", "Final craft count updated; remaining materials recalculated."))
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
        if expected ~= nil and ((live[field] == nil and expected ~= 0)
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
    if amount < 1 then return nil, L("WF_ON_COOLDOWN", "This recipe is on cooldown.") end
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
    pending = { task = fresh, requested = amount, confirmed = 0, results = {}, lastActivity = GetTime(), target = target }
    Data().inFlight = { planID = fresh.plan.id, nodeKey = fresh.node.key }
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
function Plan.Stop()
    if not pending then return end
    pending.stopping = true
    local stop = GetStopRepeat()
    if stop then stop() end
    Notify(L("WF_STOPPING_NOTICE", "Stopping after the current craft; confirmed progress will be kept."))
end

local function EndBatch()
    if not pending then return end
    pending = nil
    Data().inFlight = nil
    Notify(L("WF_BATCH_FINISHED", "Batch finished. Remaining requirements now use your current bags and banks."))
end
function Plan.OnEvent(event, ...)
    local data = Data()
    if event == "BAG_UPDATE_DELAYED" then
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

function Plan.CreateShoppingList(itemID)
    local list = { entries = {}, vendorEntries = {}, craftPlan = true }
    for _, entry in ipairs(Plan.Project().buys) do
        if not itemID or entry.itemID == itemID then
            local source, price = GAM.VendorPrices.ResolvePurchase(entry.itemID, entry.quantity)
            local copy = { itemID = entry.itemID, name = entry.name, quantity = entry.quantity, unitPrice = price }
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
function Plan.Init()
    if events then return end
    local data = Data()
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
        for _, plan in ipairs(data.plans) do if plan.id == data.inFlight.planID then plan.needsReview = true end end
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
