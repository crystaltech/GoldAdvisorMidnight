-- GoldAdvisorMidnight/CraftHistoryAnalysis.lua
-- Turns recorded history into per-item results, verdicts and a few plain
-- suggestions. Pure: callers pass events and a cost lookup.
-- Module: GAM.CraftHistoryAnalysis

local ADDON_NAME, GAM = ...
local Analysis = {}
GAM.CraftHistoryAnalysis = Analysis

Analysis.MIN_POSTED = 10
Analysis.SLOW_EXPIRE_RATE = 0.30
Analysis.GOOD_SELL_THROUGH = 0.80
Analysis.MAX_SUGGESTIONS = 3

-- unitCost(itemID) -> copper per item the player paid (nil when unknown).
-- stockOf(itemID) -> units still owned or listed.
-- listedOf(itemID) -> units still on the Auction House; they have not sold or
-- expired yet, so they do not count against sell-through.
-- saleCost(event) -> units of a sale matched to a batch and what those units
-- cost (see Batches); sold units no batch covers use unitCost.
function Analysis.ItemStats(events, unitCost, stockOf, listedOf, saleCost)
    local byItem, order = {}, {}
    for _, event in ipairs(events or {}) do
        local id = event.itemID
        if id and event.kind ~= "buy" then
            local s = byItem[id]
            if not s then
                s = { itemID = id, crafted = 0, posted = 0, sold = 0, expired = 0, cancelled = 0,
                    revenue = 0, lost = 0 }
                byItem[id] = s
                order[#order + 1] = s
            end
            if event.kind == "craft" then
                s.crafted = s.crafted + event.qty
                -- Crafts outside the queue may be materials too: treated like intermediates.
                if event.source ~= "intermediate" and event.source ~= "outside" then
                    s.finalCrafted = (s.finalCrafted or 0) + event.qty
                end
            elseif event.kind == "post" then s.posted = s.posted + event.qty
            elseif event.kind == "sold" then
                s.sold = s.sold + event.qty; s.revenue = s.revenue + (event.copper or 0)
                local matched = saleCost and saleCost(event)
                if matched and matched.qty > 0 then
                    s.matchedSold = (s.matchedSold or 0) + matched.qty
                    s.matchedCost = (s.matchedCost or 0) + matched.copper
                end
            elseif event.kind == "expired" then s.expired = s.expired + event.qty; s.lost = s.lost + (event.copper or 0)
            elseif event.kind == "cancel" then s.cancelled = s.cancelled + event.qty; s.lost = s.lost + (event.copper or 0)
            end
        end
    end
    -- Intermediates meant to be used up are not items for sale: keep them only
    -- when they were posted or sold.
    local kept = {}
    for _, s in ipairs(order) do
        if (s.finalCrafted or 0) > 0 or s.posted > 0 or s.sold > 0 or s.crafted == 0 then kept[#kept + 1] = s end
    end
    order = kept
    for _, s in ipairs(order) do
        s.cost = unitCost and unitCost(s.itemID) or nil
        s.stock = stockOf and stockOf(s.itemID) or 0
        s.listed = listedOf and listedOf(s.itemID) or 0
        -- Only sold and expired are outcomes. Units still listed, or sold with
        -- no record yet, are pending and never count as unsold.
        s.resolved = s.sold + s.expired
        s.pending = math.max(0, s.posted - s.cancelled - s.resolved)
        s.sellThrough = s.resolved > 0 and math.min(1, s.sold / s.resolved) or nil
        s.expireRate = s.resolved > 0 and math.min(1, s.expired / s.resolved) or nil
        -- Sold units cost what their own batch cost; the rest the item's cost.
        local matchedSold, matchedCost = s.matchedSold or 0, s.matchedCost or 0
        local soldCost
        if matchedSold >= s.sold then soldCost = matchedCost
        elseif s.cost then soldCost = matchedCost + s.cost * (s.sold - matchedSold) end
        if soldCost then
            s.realized = math.floor(s.revenue - soldCost - s.lost)
            local unit = s.sold > 0 and soldCost / s.sold or s.cost
            s.margin = s.sold > 0 and unit and unit > 0 and (s.revenue / s.sold - unit) / unit or nil
        end
        if s.cost then
            s.stockValue = s.stock * s.cost
        elseif s.sold == 0 then
            -- Nothing sold: only the lost deposits are certain.
            s.realized = -s.lost
        end
    end
    return order
end

-- "stuck" | "few" | "loss" | "slow" | "more" | "keep"
function Analysis.Verdict(s, marginWarn)
    if s.posted == 0 and s.stock > 0 then return "stuck" end
    if (s.resolved or s.posted) < Analysis.MIN_POSTED then return "few" end
    -- Losing gold needs sales to judge: with none sold yet, the only loss is
    -- deposits and the items are still yours (expiries make it "slow").
    if s.realized and s.realized < 0 and s.sold > 0 then return "loss" end
    if (s.expireRate or 0) >= Analysis.SLOW_EXPIRE_RATE then return "slow" end
    if (s.sellThrough or 0) >= Analysis.GOOD_SELL_THROUGH and s.margin and s.margin >= (marginWarn or 0.2) then
        return "more"
    end
    return "keep"
end

-- Suggestions, largest gold at stake first: up to `limit` (three when not
-- given; math.huge for all of them).
function Analysis.Suggestions(stats, marginWarn, limit)
    local out = {}
    for _, s in ipairs(stats or {}) do
        local verdict = Analysis.Verdict(s, marginWarn)
        local weight
        if verdict == "more" then weight = s.realized or 0
        elseif verdict == "loss" then weight = -(s.realized or 0) + (s.stockValue or 0)
        elseif verdict == "stuck" then weight = s.stockValue or 0
        elseif verdict == "slow" then weight = (s.lost or 0) * 50
        end
        if weight then out[#out + 1] = { verdict = verdict, stats = s, weight = weight } end
    end
    table.sort(out, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a.stats.itemID < b.stats.itemID
    end)
    for index = #out, (limit or Analysis.MAX_SUGGESTIONS) + 1, -1 do out[index] = nil end
    return out
end

function Analysis.Totals(events, stats)
    -- spent: purchases for Craft Queue plans; other: the rest (work orders,
    -- other addons' shopping not for a queued plan).
    local totals = { spent = 0, other = 0, sold = 0, lost = 0, realized = 0, stock = 0 }
    for _, event in ipairs(events or {}) do
        if event.kind == "buy" then
            if event.plans and next(event.plans) then totals.spent = totals.spent + (event.copper or 0)
            else totals.other = totals.other + (event.copper or 0) end
        end
    end
    for _, s in ipairs(stats or {}) do
        totals.sold = totals.sold + s.revenue
        totals.lost = totals.lost + s.lost
        totals.realized = totals.realized + (s.realized or 0)
        totals.stock = totals.stock + (s.stockValue or 0)
    end
    return totals
end

-- ===== Batches: one queue plan from purchase to sale =====

-- batches: plan records (Plan.BatchRecord / archived): id, name, createdAt,
--   completed, finalOutputs = {[itemID]=qty}, breakEven = {[itemID]=copper}.
-- events: the whole history (sales are matched to batches oldest first).
-- purchases(planID) -> {[itemID] = {qty, copper}} recorded for that plan.
-- unitPrice(itemID) -> today's market price, to value recorded purchases.
-- materialCost(record) -> copper for the materials the batch really used
--   (record.consumed, priced at what was paid), or nil.
-- Returns one result per batch that made something:
--   { record, start, made, sold, revenue, paid, cost, costSource, realized, left }
-- cost is what the batch's items cost you: the materials it used when those
-- were counted ("used"), otherwise its break-even materials less what
-- recorded purchases saved against the market ("estimate"; nil when unknown).
function Analysis.Batches(batches, events, purchases, unitPrice, ahCut, materialCost)
    ahCut = ahCut or 0.05
    local firstCraft = {}
    for _, event in ipairs(events or {}) do
        if event.kind == "craft" and event.planID ~= nil then
            local t = firstCraft[event.planID]
            if not t or (event.t or 0) < t then firstCraft[event.planID] = event.t or 0 end
        end
    end
    local results, slots, saleCosts = {}, {}, {}
    for _, record in ipairs(batches or {}) do
        local made = 0
        for _, qty in pairs(record.finalOutputs or {}) do made = made + qty end
        if made > 0 then
            local r = { record = record, start = firstCraft[record.id] or record.createdAt or record.archivedAt or 0,
                made = made, sold = 0, revenue = 0, paid = 0 }
            -- Material cost: break-even value, less the savings on recorded purchases.
            local materialValue, known = 0, true
            for itemID, qty in pairs(record.finalOutputs) do
                local be = record.breakEven and record.breakEven[itemID]
                if be then materialValue = materialValue + be * (1 - ahCut) * qty else known = false end
                slots[itemID] = slots[itemID] or {}
                table.insert(slots[itemID], { result = r, left = qty })
            end
            local market, paid = 0, 0
            for reagentID, bought in pairs(purchases and purchases(record.id) or {}) do
                paid = paid + bought.copper
                local unit = unitPrice and unitPrice(reagentID)
                if unit then market = market + unit * bought.qty else market = market + bought.copper end
            end
            r.paid = math.floor(paid)
            local used = record.consumed and materialCost and materialCost(record)
            if used then
                r.cost, r.costSource = used, "used"
            else
                r.cost = known and math.max(0, math.floor(materialValue - (market - paid))) or nil
                r.costSource = r.cost and "estimate" or nil
            end
            -- A finished batch keeps the cost it was first given: today's prices
            -- (used to value unrecorded materials and purchase savings) must not
            -- move a past result. The record is saved, so this lasts.
            if record.archivedAt then
                if record.frozenCost then
                    r.cost, r.costSource = record.frozenCost, record.frozenSource or r.costSource
                elseif r.cost then
                    record.frozenCost, record.frozenSource = r.cost, r.costSource
                end
            end
            results[#results + 1] = r
        end
    end
    for _, list in pairs(slots) do table.sort(list, function(a, b) return a.result.start < b.result.start end) end
    -- Sales go to the oldest batch that had made the item before the sale.
    local sales = {}
    for _, event in ipairs(events or {}) do
        if event.kind == "sold" and slots[event.itemID] then sales[#sales + 1] = event end
    end
    table.sort(sales, function(a, b) return (a.t or 0) < (b.t or 0) end)
    for _, sale in ipairs(sales) do
        local remaining = sale.qty
        for _, slot in ipairs(slots[sale.itemID]) do
            if remaining <= 0 then break end
            if slot.left > 0 and slot.result.start <= (sale.t or 0) then
                local take = math.min(slot.left, remaining)
                slot.left, remaining = slot.left - take, remaining - take
                slot.result.sold = slot.result.sold + take
                slot.result.revenue = slot.result.revenue + (sale.copper or 0) * take / sale.qty
                -- What these units cost: their batch's cost per item made.
                if slot.result.cost then
                    local key = sale.id or sale
                    local c = saleCosts[key] or { qty = 0, copper = 0 }
                    saleCosts[key] = c
                    c.qty, c.copper = c.qty + take, c.copper + slot.result.cost * take / slot.result.made
                end
            end
        end
    end
    for _, r in ipairs(results) do
        r.revenue = math.floor(r.revenue)
        r.left = r.made - r.sold
        r.realized = r.cost and math.floor(r.revenue - r.cost * r.sold / r.made) or nil
    end
    table.sort(results, function(a, b) return a.start > b.start end)
    -- Second value: per sale (by event id), the units matched to a batch and
    -- what they cost.
    return results, saleCosts
end

-- Crafts to queue so that stock covers `days` of your own sales:
-- ceil((salesPerDay x days - owned) / yieldPerCraft), or 0 when stocked.
function Analysis.RestockCrafts(salesPerDay, owned, yieldPerCraft, days)
    if not (salesPerDay and salesPerDay > 0 and yieldPerCraft and yieldPerCraft > 0) then return 0 end
    local short = salesPerDay * (days or 7) - (owned or 0)
    if short <= 0 then return 0 end
    return math.ceil(short / yieldPerCraft)
end
