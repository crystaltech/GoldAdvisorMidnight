-- GoldAdvisorMidnight/ReagentMixOptimizer.lua
-- Finds the least-cost two-tier reagent allocation that Blizzard confirms will
-- craft the requested quality without Concentration.

local ADDON_NAME, GAM = ...
local Optimizer = {}
GAM.ReagentMixOptimizer = Optimizer

local SKILL_SCALE = 1000
local MODEL_TTL_SECONDS = 2
local liveModelCache = {}

local function RoundSkill(value)
    return math.floor((tonumber(value) or 0) * SKILL_SCALE + 0.5)
end

local function OperationSkill(info)
    if type(info) ~= "table" then return nil end
    local base = tonumber(info.baseSkill)
    local bonus = tonumber(info.bonusSkill)
    if base == nil or bonus == nil then return nil end
    return base + bonus
end

local function OperationQuality(info)
    if type(info) ~= "table" then return nil end
    return tonumber(info.quality) or tonumber(info.craftingQuality)
end

local function CallOperationInfo(recipeID, allocation)
    local api = C_TradeSkillUI and C_TradeSkillUI.GetCraftingOperationInfo
    if type(api) ~= "function" then
        return nil, "operation-api-unavailable"
    end
    local ok, info = pcall(api, recipeID, allocation, nil, false)
    if not ok then return nil, "operation-api-error" end
    if type(info) ~= "table" then return nil, "operation-api-returned-nil" end
    return info
end

local function GetReagentQuality(itemID, fallback)
    local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    if type(api) == "function" then
        local ok, quality = pcall(api, itemID)
        quality = ok and tonumber(quality) or nil
        if quality and quality > 0 then
            return quality
        end
        if quality == 0 then
            -- Zero is Blizzard's explicit "not quality-ranked" result. Treat
            -- every item in that selectable pool as the same unranked tier.
            return 1
        end
    end
    return fallback
end

local function BuildAllocation(slots, highCounts)
    local allocation = {}
    for index, slot in ipairs(slots or {}) do
        local high = math.max(0, math.min(slot.quantity, tonumber(highCounts and highCounts[index]) or 0))
        allocation[#allocation + 1] = {
            reagent = { itemID = slot.lowItemID },
            dataSlotIndex = slot.dataSlotIndex,
            quantity = slot.quantity - high,
        }
        allocation[#allocation + 1] = {
            reagent = { itemID = slot.highItemID },
            dataSlotIndex = slot.dataSlotIndex,
            quantity = high,
        }
    end
    return allocation
end

local function PruneStates(states)
    local cheapestBySkill = {}
    for _, state in ipairs(states) do
        local previous = cheapestBySkill[state.skill]
        if not previous or state.cost < previous.cost then
            cheapestBySkill[state.skill] = state
        end
    end

    local ordered = {}
    for _, state in pairs(cheapestBySkill) do
        ordered[#ordered + 1] = state
    end
    table.sort(ordered, function(a, b)
        if a.skill == b.skill then return a.cost < b.cost end
        return a.skill > b.skill
    end)

    local frontier = {}
    local bestCost = math.huge
    for _, state in ipairs(ordered) do
        if state.cost < bestCost then
            frontier[#frontier + 1] = state
            bestCost = state.cost
        end
    end
    return frontier
end

-- Pure bounded optimizer. Each slot supplies a list of possible compositions:
-- { highCount, skill, cost }. Dominated states are discarded after every slot.
function Optimizer.OptimizeTwoTier(slotOptions)
    local states = { { skill = 0, cost = 0, highCounts = {}, selections = {} } }
    for slotIndex, options in ipairs(slotOptions or {}) do
        local expanded = {}
        for _, state in ipairs(states) do
            for _, option in ipairs(options or {}) do
                local counts = {}
                for index, count in ipairs(state.highCounts) do
                    counts[index] = count
                end
                local selections = {}
                for index, selection in ipairs(state.selections) do
                    selections[index] = selection
                end
                counts[slotIndex] = option.highCount
                selections[slotIndex] = option.selection
                expanded[#expanded + 1] = {
                    skill = state.skill + option.skill,
                    cost = state.cost + option.cost,
                    stale = state.stale or option.stale or false,
                    highCounts = counts,
                    selections = selections,
                }
            end
        end
        states = PruneStates(expanded)
    end
    table.sort(states, function(a, b)
        if a.cost == b.cost then return a.skill > b.skill end
        return a.cost < b.cost
    end)
    return states
end

local function ReadQualitySlots(recipeID)
    local api = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic
    if type(api) ~= "function" then
        return nil, "recipe-schematic-api-unavailable"
    end
    local ok, schematic = pcall(api, recipeID, false)
    if not ok or type(schematic) ~= "table" then
        return nil, "recipe-schematic-unavailable"
    end

    local slots = {}
    for _, rawSlot in ipairs(schematic.reagentSlotSchematics or {}) do
        local quantity = tonumber(rawSlot.quantityRequired) or 0
        local reagents = rawSlot.reagents or {}
        if quantity > 0 and rawSlot.required ~= false and #reagents > 1 then
            local ranked = {}
            for reagentIndex, reagent in ipairs(reagents) do
                if reagent.itemID then
                    ranked[#ranked + 1] = {
                        itemID = reagent.itemID,
                        quality = GetReagentQuality(reagent.itemID, reagentIndex),
                    }
                end
            end
            table.sort(ranked, function(a, b)
                if a.quality == b.quality then return a.itemID < b.itemID end
                return a.quality < b.quality
            end)
            local qualityOrder = {}
            local itemsByQuality = {}
            for _, reagent in ipairs(ranked) do
                if not itemsByQuality[reagent.quality] then
                    qualityOrder[#qualityOrder + 1] = reagent.quality
                    itemsByQuality[reagent.quality] = {}
                end
                itemsByQuality[reagent.quality][#itemsByQuality[reagent.quality] + 1] = reagent.itemID
            end
            table.sort(qualityOrder)
            if #qualityOrder > 2 then
                return nil, "only-two-tier-reagents-are-supported"
            end
            if #qualityOrder == 2 then
                local lowQuality = qualityOrder[1]
                local highQuality = qualityOrder[2]
                slots[#slots + 1] = {
                    dataSlotIndex = rawSlot.dataSlotIndex,
                    quantity = quantity,
                    lowItemID = itemsByQuality[lowQuality][1],
                    highItemID = itemsByQuality[highQuality][1],
                    lowItemIDs = itemsByQuality[lowQuality],
                    highItemIDs = itemsByQuality[highQuality],
                    lowQuality = lowQuality,
                    highQuality = highQuality,
                }
            end
        end
    end
    if #slots == 0 then
        return nil, "recipe-has-no-ranked-reagents"
    end
    return slots
end

local function BuildLiveModel(recipeID)
    local slots, slotReason = ReadQualitySlots(recipeID)
    if not slots then return nil, slotReason end

    local lowCounts = {}
    local highCounts = {}
    for index, slot in ipairs(slots) do
        lowCounts[index] = 0
        highCounts[index] = slot.quantity
    end

    local lowInfo, lowReason = CallOperationInfo(recipeID, BuildAllocation(slots, lowCounts))
    local highInfo, highReason = CallOperationInfo(recipeID, BuildAllocation(slots, highCounts))
    local lowSkill = OperationSkill(lowInfo)
    local highSkill = OperationSkill(highInfo)
    if not lowSkill or not highSkill then
        return nil, lowReason or highReason or "operation-info-missing-skill"
    end

    for index, slot in ipairs(slots) do
        local counts = {}
        for other = 1, #slots do counts[other] = 0 end
        counts[index] = slot.quantity
        local info, infoReason = CallOperationInfo(recipeID, BuildAllocation(slots, counts))
        local skill = OperationSkill(info)
        if not skill then
            return nil, infoReason or "slot-operation-info-missing-skill"
        end
        slot.skillPerHigh = (skill - lowSkill) / slot.quantity
        slot.skillPerHighScaled = RoundSkill(slot.skillPerHigh)
    end

    return {
        recipeID = recipeID,
        slots = slots,
        lowQuality = OperationQuality(lowInfo),
        highQuality = OperationQuality(highInfo),
        lowSkill = lowSkill,
        highSkill = highSkill,
    }
end

local function GetLiveModel(recipeID)
    local now = type(GetTime) == "function" and GetTime() or nil
    local cached = liveModelCache[recipeID]
    if cached and now and cached.cachedAt and now - cached.cachedAt <= MODEL_TTL_SECONDS then
        return cached.model
    end
    local model, reason = BuildLiveModel(recipeID)
    if model and now then
        liveModelCache[recipeID] = { model = model, cachedAt = now }
    end
    return model, reason
end

local function GetPrice(priceGetter, itemID, quantity)
    local price, stale = priceGetter(itemID, quantity)
    price = tonumber(price)
    if not price or price < 0 then return nil, stale end
    return price, stale and true or false
end

local function HasItemID(ids, wanted)
    for _, itemID in ipairs(ids or {}) do
        if itemID == wanted then return true end
    end
    return false
end

local function GetQualityPair(ids, slot)
    local lowItemID, highItemID = nil, nil
    for _, itemID in ipairs(ids or {}) do
        if HasItemID(slot.lowItemIDs, itemID) then lowItemID = itemID end
        if HasItemID(slot.highItemIDs, itemID) then highItemID = itemID end
    end
    if lowItemID and highItemID then
        return { lowItemID = lowItemID, highItemID = highItemID }
    end
    return nil
end

local function GetRecipeReagentIDs(reagent)
    local ids = {}
    for _, itemID in ipairs(reagent and reagent.itemIDs or {}) do ids[#ids + 1] = itemID end
    for _, alternative in ipairs(reagent and reagent.cheapestOf or {}) do
        for _, itemID in ipairs(alternative.itemIDs or {}) do ids[#ids + 1] = itemID end
    end
    return ids
end

local function BuildSlotFamilies(slot, recipeView)
    local slotIDs = {}
    for _, itemID in ipairs(slot.lowItemIDs or {}) do slotIDs[itemID] = true end
    for _, itemID in ipairs(slot.highItemIDs or {}) do slotIDs[itemID] = true end

    for _, reagent in ipairs(recipeView and recipeView.reagents or {}) do
        local matches = false
        for _, itemID in ipairs(GetRecipeReagentIDs(reagent)) do
            if slotIDs[itemID] then matches = true break end
        end
        if matches then
            local families = {}
            if reagent.cheapestOf and #reagent.cheapestOf > 0 then
                for _, alternative in ipairs(reagent.cheapestOf) do
                    local pair = GetQualityPair(alternative.itemIDs, slot)
                    if pair then families[#families + 1] = pair end
                end
            else
                local pair = GetQualityPair(reagent.itemIDs, slot)
                if pair then families[#families + 1] = pair end
            end
            if #families > 0 then return families end
        end
    end

    if #(slot.lowItemIDs or {}) == 1 and #(slot.highItemIDs or {}) == 1 then
        return { { lowItemID = slot.lowItemIDs[1], highItemID = slot.highItemIDs[1] } }
    end
    return nil
end

-- Uses the live Blizzard operation API as the final acceptance test. The API is
-- always called with applyConcentration=false (see CallOperationInfo).
function Optimizer.BuildLivePlan(args)
    args = args or {}
    local recipeID = tonumber(args.recipeID)
    local targetQuality = tonumber(args.targetQuality)
    local priceGetter = args.priceGetter
    local crafts = math.max(1, tonumber(args.crafts) or 1)
    if not recipeID or not targetQuality or type(priceGetter) ~= "function" then
        return nil, "invalid-arguments"
    end

    local model, modelReason = GetLiveModel(recipeID)
    if not model then return nil, modelReason end
    if (tonumber(model.highQuality) or 0) < targetQuality then
        return nil, "target-quality-unreachable"
    end

    local slotOptions = {}
    for slotIndex, slot in ipairs(model.slots) do
        local families = BuildSlotFamilies(slot, args.recipeView)
        if not families then
            return nil, "rank-families-do-not-match-recipe"
        end
        local options = {}
        for highCount = 0, slot.quantity do
            local lowCount = slot.quantity - highCount
            local best = nil
            for _, family in ipairs(families) do
                local lowPrice, lowStale = 0, false
                local highPrice, highStale = 0, false
                if lowCount > 0 then
                    lowPrice, lowStale = GetPrice(priceGetter, family.lowItemID, lowCount * crafts)
                end
                if highCount > 0 then
                    highPrice, highStale = GetPrice(priceGetter, family.highItemID, highCount * crafts)
                end
                if lowPrice ~= nil and highPrice ~= nil then
                    local cost = lowCount * lowPrice + highCount * highPrice
                    if not best or cost < best.cost then
                        best = {
                            cost = cost,
                            stale = lowStale or highStale,
                            selection = family,
                        }
                    end
                end
            end
            if not best then
                return nil, "rank-price-unavailable"
            end
            options[#options + 1] = {
                highCount = highCount,
                skill = highCount * slot.skillPerHighScaled,
                cost = best.cost,
                stale = best.stale,
                selection = best.selection,
            }
        end
        slotOptions[slotIndex] = options
    end

    local candidates = Optimizer.OptimizeTwoTier(slotOptions)
    local validationReason = nil
    for _, candidate in ipairs(candidates) do
        local selectedSlots = {}
        for index, slot in ipairs(model.slots) do
            local selection = candidate.selections[index]
            selectedSlots[index] = {
                quantity = slot.quantity,
                dataSlotIndex = slot.dataSlotIndex,
                lowItemID = selection.lowItemID,
                highItemID = selection.highItemID,
            }
        end
        local allocation = BuildAllocation(selectedSlots, candidate.highCounts)
        local info, infoReason = CallOperationInfo(recipeID, allocation)
        validationReason = validationReason or infoReason
        if (OperationQuality(info) or 0) >= targetQuality then
            local rows = {}
            for index, slot in ipairs(model.slots) do
                local highCount = candidate.highCounts[index] or 0
                local selection = candidate.selections[index]
                rows[#rows + 1] = {
                    dataSlotIndex = slot.dataSlotIndex,
                    quantity = slot.quantity,
                    lowItemID = selection.lowItemID,
                    highItemID = selection.highItemID,
                    lowCount = slot.quantity - highCount,
                    highCount = highCount,
                }
            end
            return {
                recipeID = recipeID,
                targetQuality = targetQuality,
                verifiedQuality = OperationQuality(info),
                applyConcentration = false,
                costPerCraft = candidate.cost,
                stale = candidate.stale and true or false,
                rows = rows,
            }
        end
    end
    return nil, validationReason or "no-verified-allocation"
end

local function ItemIDSet(ids)
    local set = {}
    for _, itemID in ipairs(ids or {}) do set[itemID] = true end
    return set
end

local function ReagentItemIDSet(reagent)
    local set = ItemIDSet(reagent and reagent.itemIDs)
    for _, alternative in ipairs(reagent and reagent.cheapestOf or {}) do
        for _, itemID in ipairs(alternative.itemIDs or {}) do set[itemID] = true end
    end
    return set
end

local function CloneReagent(reagent)
    local copy = {}
    for key, value in pairs(reagent or {}) do copy[key] = value end
    return copy
end

function Optimizer.ApplyPlan(recipeView, plan)
    if type(recipeView) ~= "table" or type(plan) ~= "table" then
        return nil, "invalid-plan"
    end
    local rowByItemID = {}
    for _, row in ipairs(plan.rows or {}) do
        rowByItemID[row.lowItemID] = row
        rowByItemID[row.highItemID] = row
    end

    local appliedRows = {}
    local reagents = {}
    for _, reagent in ipairs(recipeView.reagents or {}) do
        local row = nil
        local ids = ReagentItemIDSet(reagent)
        for itemID in pairs(ids) do
            if rowByItemID[itemID] then row = rowByItemID[itemID] break end
        end
        if row and not appliedRows[row] then
            local originalPerCraft = tonumber(reagent.qtyPerCraft or reagent.quantityPerCraft) or row.quantity
            local originalPerStart = tonumber(reagent.qtyPerStart or reagent.qtyMultiplier)
            local function append(itemID, count, rank)
                if count <= 0 then return end
                local copy = CloneReagent(reagent)
                copy.itemIDs = { itemID }
                copy.itemRef = tostring(reagent.itemRef or reagent.name or "Reagent") .. " (R" .. rank .. ")"
                copy.name = copy.itemRef
                copy.quantityPerCraft = count
                copy.qtyPerCraft = count
                if originalPerStart and originalPerCraft > 0 then
                    copy.qtyPerStart = originalPerStart * count / originalPerCraft
                    copy.qtyMultiplier = copy.qtyPerStart
                end
                copy.cheapestOf = nil
                reagents[#reagents + 1] = copy
            end
            append(row.lowItemID, row.lowCount, 1)
            append(row.highItemID, row.highCount, 2)
            appliedRows[row] = true
        elseif not row then
            reagents[#reagents + 1] = reagent
        end
    end

    for _, row in ipairs(plan.rows or {}) do
        if not appliedRows[row] then
            return nil, "plan-does-not-match-recipe-view"
        end
    end

    local view = {}
    for key, value in pairs(recipeView) do view[key] = value end
    view.reagents = reagents
    return view
end

function Optimizer.GetHighestOutputQuality(output)
    local api = C_TradeSkillUI and C_TradeSkillUI.GetItemCraftedQualityByItemInfo
    local best = nil
    for index, itemID in ipairs(output and output.itemIDs or {}) do
        local quality = nil
        if type(api) == "function" then
            local ok, value = pcall(api, itemID)
            if ok then quality = tonumber(value) end
        end
        if not quality or quality <= 0 then
            quality = (output and output.itemIDs and #output.itemIDs > 1) and index or nil
        end
        if quality and (not best or quality > best) then best = quality end
    end
    return best
end

function Optimizer.ClearCache()
    wipe(liveModelCache)
end
