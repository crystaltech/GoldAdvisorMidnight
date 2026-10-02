-- GoldAdvisorMidnight/CraftHistory.lua
-- Per-character log of purchases, crafts, posts, sales, expiries and cancels.
-- It records what actually happened; estimates never read from it.
-- Module: GAM.CraftHistory

local ADDON_NAME, GAM = ...
local History = {}
GAM.CraftHistory = History

History.KINDS = { buy = true, craft = true, post = true, sold = true, expired = true, cancel = true }
History.DEFAULT_DAYS = 180
History.MAX_EVENTS = 5000

local function Now()
    return (GetServerTime and GetServerTime()) or (time and time()) or 0
end

local function CharacterKey()
    return UnitGUID and UnitGUID("player") or ((UnitName and UnitName("player") or "player")
        .. "-" .. (GetRealmName and GetRealmName() or "realm"))
end

local function Store()
    local db = GAM.db
    if not db then return nil end
    db.craftHistory = db.craftHistory or { version = 1, characters = {} }
    local chars = db.craftHistory.characters
    local key = CharacterKey()
    chars[key] = chars[key] or { events = {}, nextID = 1, pruned = {} }
    chars[key].plans = chars[key].plans or {}
    local store = chars[key]
    -- Sales recorded from the auction list before 2026-09-27 multiplied the
    -- entry total by the quantity again. Drop those unconfirmed estimates;
    -- the auction list or the sale mail records them again correctly.
    if (store.salesFix or 0) < 1 then
        local kept = {}
        for _, event in ipairs(store.events) do
            if not (event.kind == "sold" and event.source == "auction" and not event.mailed) then kept[#kept + 1] = event end
        end
        store.events, store.soldAuctions, store.salesFix = kept, nil, 1
    end
    -- Sale mails were re-recorded after their gold was collected (the key used
    -- the attached gold). Drop mail sales that repeat an earlier one - same
    -- item, count and amount - within an hour; genuine identical sales read
    -- together share one timestamp and are kept.
    if (store.salesFix or 0) < 2 then
        local firstSeen, kept = {}, {}
        for _, event in ipairs(store.events) do
            local drop = false
            if event.kind == "sold" and event.source == "mail" then
                local key = table.concat({ event.itemID, event.qty, event.copper }, ":")
                local first = firstSeen[key]
                if first and event.t ~= first and event.t - first < 3600 then
                    drop = true
                elseif not first then
                    firstSeen[key] = event.t
                end
            end
            if not drop then kept[#kept + 1] = event end
        end
        -- Mails already recorded under the old key must not be recorded again:
        -- each kept mail sale can absorb one matching mail (see PostingMail).
        local legacy, now = {}, Now()
        for _, event in ipairs(kept) do
            if event.kind == "sold" and event.source == "mail" and now - (event.t or 0) < 31 * 86400 then
                local key = table.concat({ "sold", event.itemID, event.qty, event.copper }, ":")
                legacy[key] = (legacy[key] or 0) + 1
            end
        end
        store.events, store.mailLegacy, store.salesFix = kept, legacy, 2
    end
    -- From 2026-09-28 sales and expiries are recorded when their mail is
    -- collected. Estimates from the auction list are dropped (the mail records
    -- them), and mail already recorded from inbox reads is remembered so
    -- collecting it does not record it again (see HistoryCapture).
    if (store.salesFix or 0) < 3 then
        local kept, legacy, now = {}, {}, Now()
        for _, event in ipairs(store.events) do
            if not (event.kind == "sold" and event.source == "auction" and not event.mailed) then
                kept[#kept + 1] = event
                if (event.kind == "sold" or event.kind == "expired") and now - (event.t or 0) < 31 * 86400 then
                    local key = table.concat({ event.kind, event.itemID, event.qty,
                        event.kind == "sold" and event.copper or "" }, ":")
                    legacy[key] = (legacy[key] or 0) + 1
                end
            end
        end
        store.events, store.mailLegacy, store.captureSince = kept, next(legacy) and legacy or nil, now
        store.mailSeen, store.soldAuctions, store.knownAuctions = nil, nil, nil
        store.salesFix = 3
    end
    -- Posts recorded twice for one auction (older versions could record a
    -- GAM post and then the same auction again): keep the first.
    if (store.salesFix or 0) < 4 then
        local seen, kept = {}, {}
        for _, event in ipairs(store.events) do
            local id = event.kind == "post" and event.auctionID
            if not (id and seen[id]) then kept[#kept + 1] = event end
            if id then seen[id] = true end
        end
        store.events, store.salesFix = kept, 4
    end
    return store
end
History.Store = Store

local function RetentionSeconds()
    local days = tonumber(GAM.db and GAM.db.options and GAM.db.options.historyDays) or History.DEFAULT_DAYS
    return math.max(1, days) * 86400
end

-- Old events fold into per-item totals so lifetime numbers survive pruning.
local function Fold(pruned, event)
    local item = pruned[event.itemID] or {}
    pruned[event.itemID] = item
    item[event.kind] = (item[event.kind] or 0) + (event.qty or 0)
    item[event.kind .. "Copper"] = (item[event.kind .. "Copper"] or 0) + (event.copper or 0)
end

function History.Prune(now)
    local store = Store()
    if not store then return 0 end
    now = now or Now()
    local cutoff = now - RetentionSeconds()
    local events, kept, removed = store.events, {}, 0
    local overflow = math.max(0, #events - History.MAX_EVENTS)
    for index, event in ipairs(events) do
        if index <= overflow or (event.t or 0) < cutoff then
            Fold(store.pruned, event)
            removed = removed + 1
        else
            kept[#kept + 1] = event
        end
    end
    store.events = kept
    local plans = {}
    for _, record in ipairs(store.plans or {}) do
        if (record.archivedAt or 0) >= cutoff then plans[#plans + 1] = record end
    end
    while #plans > History.MAX_PLANS do table.remove(plans, 1) end
    store.plans = plans
    return removed
end

History.MAX_PLANS = 500

-- A finished queue plan, kept after it leaves the queue so Posting and
-- History still know its break-even and what the player paid.
-- record: id, name, strategyID, completed, finalOutputs = {[itemID]=qty},
-- outputs = {[itemID]=qty} (final and intermediate), breakEven = {[itemID]=copper}.
function History.ArchivePlan(record)
    local store = Store()
    if not (store and type(record) == "table" and record.id ~= nil) then return nil end
    record.archivedAt = record.archivedAt or Now()
    for index, existing in ipairs(store.plans) do
        if existing.id == record.id then table.remove(store.plans, index); break end
    end
    store.plans[#store.plans + 1] = record
    while #store.plans > History.MAX_PLANS do table.remove(store.plans, 1) end
    return record
end

function History.ArchivedPlans()
    local store = Store()
    return store and store.plans or {}
end

-- copper is always a positive amount; the kind says which way it moved:
-- buy = paid, post = deposit paid, sold = received after the AH cut,
-- expired/cancel = deposit lost, craft = none.
function History.Record(kind, fields)
    if not History.KINDS[kind] or type(fields) ~= "table" then return nil end
    local itemID, qty = tonumber(fields.itemID), math.floor(tonumber(fields.qty) or 0)
    if not itemID or itemID <= 0 or qty <= 0 then return nil end
    local store = Store()
    if not store then return nil end
    local event = {
        id = store.nextID, t = fields.t or Now(), kind = kind, itemID = itemID, qty = qty,
        copper = math.max(0, math.floor(tonumber(fields.copper) or 0)),
        unitPrice = tonumber(fields.unitPrice), duration = tonumber(fields.duration),
        source = fields.source, planID = fields.planID,
        othersAtPrice = tonumber(fields.othersAtPrice), postedLocal = tonumber(fields.postedLocal),
        auctionID = fields.auctionID,
    }
    if type(fields.plans) == "table" and next(fields.plans) then
        event.plans = {}
        for planID, share in pairs(fields.plans) do
            share = tonumber(share)
            if share and share > 0 then event.plans[planID] = share end
        end
    end
    -- Consecutive crafts of one item for one plan are one batch in the log.
    -- The second value is what this call added, so it can be undone.
    local last = store.events[#store.events]
    if kind == "craft" and last and last.kind == "craft" and last.itemID == event.itemID
            and last.planID == event.planID and last.source == event.source and event.t - (last.t or 0) < 600 then
        last.qty, last.t = last.qty + event.qty, event.t
        return last, { qty = event.qty, copper = 0 }
    end
    -- Sales and expiries of one item within 5 minutes are one line (a mass
    -- crafter's sales arrive as many small mails).
    if (kind == "sold" or kind == "expired") and last and last.kind == kind and last.itemID == event.itemID
            and last.source == event.source and math.abs(event.t - (last.t or 0)) <= History.MERGE_SECONDS then
        last.qty, last.copper = last.qty + event.qty, last.copper + event.copper
        return last, { qty = event.qty, copper = event.copper }
    end
    store.nextID = store.nextID + 1
    store.events[#store.events + 1] = event
    if #store.events > History.MAX_EVENTS then History.Prune() end
    return event, { qty = event.qty, copper = event.copper }
end
History.MERGE_SECONDS = 300

-- Takes back what one Record call added (a refused collect or buy); a
-- merged line keeps the rest.
function History.Unrecord(event, added)
    if type(event) ~= "table" then return false end
    added = added or event
    event.qty = event.qty - (added.qty or 0)
    event.copper = math.max(0, (event.copper or 0) - (added.copper or 0))
    if event.qty <= 0 then return History.Remove(event) end
    return true
end

-- Removes a record that turned out not to happen (a refused collect or buy).
function History.Remove(event)
    local store = Store()
    if not (store and type(event) == "table") then return false end
    for index = #store.events, 1, -1 do
        if store.events[index] == event or store.events[index].id == event.id then
            table.remove(store.events, index)
            return true
        end
    end
    return false
end

-- Splits a purchase across the queue plans that needed the item, in
-- proportion to each plan's shortage. Shares are whole units that add up to
-- qty; purchases beyond the plans' combined need stay unattributed.
function History.Allocate(qty, needs)
    if type(needs) ~= "table" then return nil end
    local total, ids = 0, {}
    for planID, need in pairs(needs) do
        need = tonumber(need) or 0
        if need > 0 then total = total + need; ids[#ids + 1] = planID end
    end
    if total <= 0 then return nil end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    local covered = math.min(qty, total)
    local shares, given = {}, 0
    for _, planID in ipairs(ids) do
        local share = math.floor(covered * needs[planID] / total)
        shares[planID], given = share, given + share
    end
    -- Hand out rounding leftovers to the largest needs first.
    table.sort(ids, function(a, b)
        if needs[a] ~= needs[b] then return needs[a] > needs[b] end
        return tostring(a) < tostring(b)
    end)
    local index = 1
    while given < covered do
        local planID = ids[index]
        shares[planID] = shares[planID] + 1
        given = given + 1
        index = index % #ids + 1
    end
    for planID, share in pairs(shares) do if share <= 0 then shares[planID] = nil end end
    return next(shares) and shares or nil
end

function History.RecordPurchase(itemID, qty, copper, source, needs)
    return History.Record("buy", { itemID = itemID, qty = qty, copper = copper,
        source = source, plans = History.Allocate(math.floor(tonumber(qty) or 0), needs) })
end

function History.Events(filter)
    local store = Store()
    local out = {}
    if not store then return out end
    filter = filter or {}
    local since = filter.since or 0
    for _, event in ipairs(store.events) do
        if (event.t or 0) >= since and (not filter.kind or event.kind == filter.kind)
                and (not filter.itemID or event.itemID == filter.itemID) then
            out[#out + 1] = event
        end
    end
    return out
end

-- Recorded purchases per material, overall and per plan, rebuilt only when
-- the log changes: { byItem = {[itemID]={qty,copper}}, byPlan = {[planID]={...}} }.
local paidCache = { key = nil }
function History.PaidIndex()
    local store = Store()
    local events = store and store.events or {}
    local last = events[#events]
    local key = #events .. ":" .. tostring(last and last.id) .. ":" .. tostring(last and last.qty)
    if paidCache.key == key then return paidCache.index end
    local index = { byItem = {}, byPlan = {} }
    for _, event in ipairs(events) do
        if event.kind == "buy" and event.qty > 0 then
            local all = index.byItem[event.itemID] or { qty = 0, copper = 0 }
            index.byItem[event.itemID] = all
            all.qty, all.copper = all.qty + event.qty, all.copper + event.copper
            for planID, share in pairs(event.plans or {}) do
                local plan = index.byPlan[planID] or {}
                index.byPlan[planID] = plan
                local row = plan[event.itemID] or { qty = 0, copper = 0 }
                plan[event.itemID] = row
                row.qty, row.copper = row.qty + share, row.copper + event.copper * share / event.qty
            end
        end
    end
    paidCache = { key = key, index = index }
    return index
end

-- Average price paid per unit: this plan's purchases first, then any
-- recorded purchase of the material. nil when it was never bought.
function History.PaidUnitPrice(itemID, planID)
    local index = History.PaidIndex()
    local own = planID ~= nil and index.byPlan[planID] and index.byPlan[planID][itemID]
    local row = (own and own.qty > 0) and own or index.byItem[itemID]
    if row and row.qty > 0 then return row.copper / row.qty end
    return nil
end

-- What a batch's used materials cost: at the price paid where recorded,
-- else today's market price (marketOf). Returns total copper (nil when a
-- material has no price at all) and the share priced at what was paid.
function History.MaterialCost(consumed, planID, marketOf)
    local total, paidValue, known = 0, 0, true
    for itemID, qty in pairs(consumed or {}) do
        local unit, paid = History.PaidUnitPrice(itemID, planID), true
        if not unit then unit, paid = marketOf and marketOf(itemID), false end
        if unit then
            total = total + unit * qty
            if paid then paidValue = paidValue + unit * qty end
        else
            known = false
        end
    end
    if not known then return nil, 0 end
    return math.floor(total), total > 0 and paidValue / total or 0
end

-- Recorded purchases attributed to one queue plan: { [itemID] = {qty, copper} }.
function History.PlanPurchases(planID)
    local byItem = {}
    for _, event in ipairs(History.Events({ kind = "buy" })) do
        local share = event.plans and event.plans[planID]
        if share and event.qty > 0 then
            local row = byItem[event.itemID] or { qty = 0, copper = 0 }
            byItem[event.itemID] = row
            row.qty = row.qty + share
            row.copper = row.copper + event.copper * share / event.qty
        end
    end
    return byItem
end

function History.Clear()
    local store = Store()
    if not store then return end
    store.events, store.pruned, store.plans = {}, {}, {}
end
