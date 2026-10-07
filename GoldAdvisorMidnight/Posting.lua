-- GoldAdvisorMidnight/Posting.lua
-- Game side of the Posting tab: rows from Craft Queue outputs, price
-- refresh, the player's own auctions, and the one-click post/cancel button.
-- Rules live in PostingModel; this file only gathers data and calls the API.
-- Module: GAM.Posting

local ADDON_NAME, GAM = ...
local function L(key, fallback, ...)
    local value = (GAM.L and GAM.L[key]) or fallback
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end

local Posting = {}
GAM.Posting = Posting
local Model = assert(GAM.PostingModel, "PostingModel must load before Posting")

local DURATION_ENUM = { [12] = 1, [24] = 2, [48] = 3 }
local REFRESH_TIMEOUT = 60
local STALE_SECONDS = 120   -- your auctions are re-checked when their scan is older
local READ_RETRIES = 5      -- an incomplete auction list is read again this many times
local READ_RETRY_SECONDS = 1
local session = {
    edits = {},          -- [itemID] = { price, qty, on }
    cancelEdits = {},    -- [auctionID] = on
    refreshing = {},     -- [itemID] = GetTime() the refresh was queued
    auctions = {},       -- own active commodity auctions
    pending = nil,       -- the post/cancel submitted and not yet confirmed
    warning = nil,       -- a post waiting for the player to confirm Blizzard's price warning
    message = nil,
}
Posting.session = session

local function Now() return GetTime and GetTime() or 0 end

-- The auction length to suggest in Settings, from how long the player is
-- usually away and how often auctions expired in the last 14 days; nil
-- when the current length suits, or the prompt was opened this week.
function Posting.DurationHint()
    local stock, history = GAM.Stock, GAM.CraftHistory
    if not (stock and history and stock.Visits) or stock.DurationHintSnoozed() then return nil end
    local now = (GetServerTime and GetServerTime()) or (time and time()) or 0
    local expires = Model.RecentExpires(history.Events({ kind = "expired" }), now)
    local suggest, usual = Model.SuggestDuration(stock.Visits(), expires, Posting.Options().duration)
    if suggest then return suggest, usual, expires end
end

function Posting.Options()
    local opts = GAM.db and GAM.db.options or {}
    local merged = Model.Options(opts.posting)
    merged.ahCut = tonumber(opts.ahCut) or merged.ahCut
    return merged
end

local listeners = {}
function Posting.OnChange(callback) listeners[#listeners + 1] = callback end
-- A scan stores prices item by item, each a change: the windows redraw at
-- most every CHANGE_INTERVAL seconds, with one more after the last change.
local CHANGE_INTERVAL = 0.5
local lastChange, changeQueued = nil, false
local function Changed()
    local now = Now()
    if lastChange and now - lastChange < CHANGE_INTERVAL and C_Timer and C_Timer.After then
        if not changeQueued then
            changeQueued = true
            C_Timer.After(CHANGE_INTERVAL - (now - lastChange), function()
                changeQueued = false
                lastChange = Now()
                for _, callback in ipairs(listeners) do pcall(callback) end
            end)
        end
        return
    end
    lastChange = now
    for _, callback in ipairs(listeners) do pcall(callback) end
end
Posting.Changed = Changed

local function Notify(message)
    session.message = message
    Changed()
end

-- ===== Data =====

-- Returned items waiting in the mailbox (Stock remembers the last inbox read).
local function InMail(itemID)
    return GAM.Stock and GAM.Stock.InMail(itemID) or 0
end

local function BagCount(itemID)
    return C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID, false, false, false) or 0
end

-- Last known listing for the item: this session's scan when available,
-- otherwise the saved lowest price with an unknown quantity.
function Posting.Listing(itemID)
    local snapshot = GAM.AHScan and GAM.AHScan.GetRawScanSnapshot and GAM.AHScan.GetRawScanSnapshot(itemID)
    if snapshot and snapshot.source == "commodity" and #snapshot.prices > 0 then
        return Model.Tiers(snapshot.prices), snapshot.ts, snapshot.prices
    end
    local cache = GAM.GetRealmCache and GAM:GetRealmCache()
    local saved = cache and cache[itemID]
    if saved and tonumber(saved.minPrice) then
        return { { price = tonumber(saved.minPrice), qty = 0, unknown = true } }, saved.ts, nil
    end
    return {}, nil, nil
end

-- History grouped by item, oldest first. Rebuilt only when events are
-- added or pruned: the auction checks read it for every auction.
local eventsCache = { key = nil }
local function EventsByItem()
    local history = GAM.CraftHistory
    local store = history and history.Store and history.Store()
    local events = store and store.events
    local first, last = events and events[1], events and events[#events]
    local key = events and (#events .. ":" .. tostring(first and first.id) .. ":" .. tostring(last and last.id))
    if key and eventsCache.key == key then return eventsCache.byItem end
    local byItem = {}
    for _, event in ipairs(history and history.Events() or {}) do
        local id = event.itemID
        if id ~= nil then
            local list = byItem[id]
            if not list then list = {}; byItem[id] = list end
            list[#list + 1] = event
        end
    end
    eventsCache = { key = key, byItem = byItem }
    return byItem
end
Posting.EventsByItem = EventsByItem

local function MarketPrice(itemID)
    return GAM.Pricing and GAM.Pricing.GetUnitPrice and GAM.Pricing.GetUnitPrice(itemID) or nil
end
Posting.MarketPrice = MarketPrice

-- What the player actually paid per item, for final outputs of queue plans.
-- Plans whose batches counted the materials they used cost those materials
-- at the price paid; older plans use the market-valued break-even minus the
-- savings on recorded purchases. Returns cost per item, and the share of it
-- backed by recorded purchase prices (0-1).
function Posting.YourCost(itemID, breakEven, opts, memo)
    local history, plan = GAM.CraftHistory, GAM.CraftPlan
    if not (history and plan) then return nil end
    memo = memo or {}
    memo.purchases = memo.purchases or {}
    local sources = {}
    for _, saved in ipairs(plan.GetData().plans) do
        sources[#sources + 1] = { id = saved.id, outputs = saved.outputs,
            consumed = plan.UsedMaterials and plan.UsedMaterials(saved) }
    end
    for _, record in ipairs(history.ArchivedPlans and history.ArchivedPlans() or {}) do
        sources[#sources + 1] = { id = record.id, outputs = record.finalOutputs, consumed = record.consumed }
    end
    local produced, costSum, backed = 0, 0, 0
    for _, source in ipairs(sources) do
        local made = source.outputs and source.outputs[itemID] or 0
        if made > 0 then
            local total = 0
            for _, qty in pairs(source.outputs) do total = total + qty end
            local used, share = nil, 0
            if source.consumed then used, share = history.MaterialCost(source.consumed, source.id, MarketPrice) end
            if used then
                -- Split the batch's material cost over everything it made.
                local cost = used * made / total
                produced, costSum, backed = produced + made, costSum + cost, backed + cost * share
            elseif breakEven then
                local purchases = memo.purchases[source.id]
                if not purchases then purchases = history.PlanPurchases(source.id); memo.purchases[source.id] = purchases end
                local market, paid = 0, 0
                for reagentID, bought in pairs(purchases) do
                    local unit = MarketPrice(reagentID)
                    if unit then market, paid = market + unit * bought.qty, paid + bought.copper end
                end
                if market > 0 then
                    local materialValue = breakEven * (1 - opts.ahCut) * made
                    local cost = math.max(0, materialValue - (market - paid))
                    produced, costSum = produced + made, costSum + cost
                    backed = backed + cost * math.min(1, market / materialValue)
                end
            end
        end
    end
    if produced <= 0 then return nil, 0 end
    return math.floor(costSum / produced), costSum > 0 and math.min(1, backed / costSum) or 0
end

-- Every item a GAM strategy makes -> the strategies that make it, and every
-- material a strategy uses -> true. Rank variants are included.
local outputIndex, reagentIndex
local function BuildIndexes()
    local importer = GAM.Importer
    local strats = importer and importer.GetAllStrats and importer.GetAllStrats() or {}
    if #strats == 0 then return {}, {} end
    local outputs, reagents = {}, {}
    local function AddOutput(output, strat)
        for _, id in ipairs(output and output.itemIDs or {}) do
            outputs[id] = outputs[id] or {}
            local list = outputs[id]
            if list[#list] ~= strat then list[#list + 1] = strat end
        end
    end
    local function AddReagents(list)
        for _, reagent in ipairs(list or {}) do
            for _, id in ipairs(reagent.itemIDs or {}) do reagents[id] = true end
        end
    end
    for _, strat in ipairs(strats) do
        AddOutput(strat.output, strat)
        for _, output in ipairs(strat.outputs or {}) do AddOutput(output, strat) end
        AddReagents(strat.reagents)
        for _, variant in pairs(strat.rankVariants or {}) do
            AddOutput(variant.output, strat)
            for _, output in ipairs(variant.outputs or {}) do AddOutput(output, strat) end
            AddReagents(variant.reagents)
        end
    end
    outputIndex, reagentIndex = outputs, reagents
    return outputs, reagents
end

local function OutputIndex()
    if outputIndex then return outputIndex end
    return (BuildIndexes())
end
Posting.OutputIndex = OutputIndex

function Posting.ReagentIndex()
    if reagentIndex then return reagentIndex end
    local _, reagents = BuildIndexes()
    return reagents
end

-- Strategy data can be reloaded (Settings > Tools); rebuild the indexes then.
local breakEvenCache = { revision = nil, values = {} }
function Posting.InvalidateOutputIndex()
    outputIndex, reagentIndex = nil, nil
    breakEvenCache = { revision = nil, values = {} }
end

-- Break-even for an item made outside the queue: the current estimate of
-- the strategies that make it. The highest one is used, the safer floor.
-- A scan changes prices one item at a time: a sale item that no strategy
-- uses as a material only affects the strategies that make it, so only
-- their outputs are worked out again. Any other change clears everything.
local function DropAffected(changed)
    local outputs, reagents = OutputIndex(), Posting.ReagentIndex()
    local values = breakEvenCache.values
    for _, id in ipairs(changed) do
        if reagents[id] or not outputs[id] then return false end
        for _, strat in ipairs(outputs[id]) do
            local function Drop(output) for _, out in ipairs(output and output.itemIDs or {}) do values[out] = nil end end
            Drop(strat.output)
            for _, output in ipairs(strat.outputs or {}) do Drop(output) end
            for _, variant in pairs(strat.rankVariants or {}) do
                Drop(variant.output)
                for _, output in ipairs(variant.outputs or {}) do Drop(output) end
            end
        end
    end
    return true
end
function Posting.StrategyBreakEven(itemID)
    local state = GAM.State
    local revision = state and state.GetPriceRevision and state.GetPriceRevision()
    if breakEvenCache.revision ~= revision then
        local changed = state and state.PriceChangesSince and state.PriceChangesSince(breakEvenCache.revision)
        if changed and DropAffected(changed) then
            breakEvenCache.revision = revision
        else
            breakEvenCache = { revision = revision, values = {} }
        end
    end
    local cached = breakEvenCache.values[itemID]
    if cached ~= nil then return cached or nil end
    local best
    local facade = GAM.PricingFacade
    for _, strat in ipairs(facade and facade.CalculateCurrent and OutputIndex()[itemID] or {}) do
        local ok, result = pcall(facade.CalculateCurrent, strat, strat.patchTag)
        local value = ok and type(result) == "table" and tonumber(result.breakEvenSell)
        if value and value > 0 and (not best or value > best) then best = math.ceil(value) end
    end
    breakEvenCache.values[itemID] = best or false
    return best
end

function Posting.Rows()
    local plan = GAM.CraftPlan
    if not (plan and plan.Project and plan.OutputSummary) then return {} end
    local ok, projection = pcall(plan.Project)
    if not ok then return {} end
    local opts, now, rows = Posting.Options(), Now(), {}
    local summaries, fromQueue = plan.OutputSummary(projection), {}
    for _, summary in ipairs(summaries) do fromQueue[summary.itemID] = true end
    -- Items from finished plans that moved to History keep the plan's break-even.
    local archived = GAM.CraftHistory and GAM.CraftHistory.ArchivedPlans and GAM.CraftHistory.ArchivedPlans() or {}
    for index = #archived, 1, -1 do
        local record = archived[index]
        for itemID in pairs(record.outputs or {}) do
            if not fromQueue[itemID] and plan.Count then
                fromQueue[itemID] = true
                local free = math.max(0, plan.Count(itemID) - ((projection.reserved or {})[itemID] or 0))
                if free > 0 or InMail(itemID) > 0 then
                    summaries[#summaries + 1] = { itemID = itemID, free = free, breakEven = record.breakEven and record.breakEven[itemID] }
                end
            end
        end
    end
    -- Other strategy outputs in bags or bank, made before tracking or outside the queue.
    if opts.includeOther and plan.Count then
        local others = {}
        -- Only items with some in bags: bank stockpiles of materials would flood the list.
        for itemID in pairs(OutputIndex()) do
            if not fromQueue[itemID] and (BagCount(itemID) > 0 or InMail(itemID) > 0) then
                local free = math.max(0, plan.Count(itemID) - ((projection.reserved or {})[itemID] or 0))
                if free > 0 or InMail(itemID) > 0 then
                    others[#others + 1] = { itemID = itemID, free = free, other = true }
                end
            end
        end
        table.sort(others, function(a, b) return a.itemID < b.itemID end)
        local history = GAM.CraftHistory
        for _, other in ipairs(others) do
            other.breakEven = Posting.StrategyBreakEven(other.itemID)
            -- Bought rather than crafted (work orders, shopping lists): what
            -- you paid sets the floor, so it is never shown as profit to sell
            -- under your purchase price.
            local paid = history and history.PaidUnitPrice and history.PaidUnitPrice(other.itemID)
            if paid and paid > 0 then
                other.paid = paid
                local floor = math.ceil(paid / (1 - opts.ahCut))
                if not other.breakEven or floor > other.breakEven then other.breakEven, other.fromPaid = floor, true end
            end
            summaries[#summaries + 1] = other
        end
    end
    local byItem, memo = EventsByItem(), {}
    for _, summary in ipairs(summaries) do
        local id = summary.itemID
        local free = math.max(0, summary.free or 0)
        local bags = math.min(BagCount(id), free)
        local mail = InMail(id)
        if free > 0 or mail > 0 then
            local tiers, ts, prices = Posting.Listing(id)
            local rate = GAM.TSMSaleRate
            local row = Model.BuildRow({
                itemID = id, bags = bags, bank = math.max(0, free - bags), mail = mail,
                breakEven = summary.breakEven and math.ceil(summary.breakEven) or nil,
                market = GAM.Pricing and GAM.Pricing.GetUnitPrice and GAM.Pricing.GetUnitPrice(id, true),
                tiers = tiers, soldPerDay = rate and rate.SoldPerDay and rate.SoldPerDay(id),
                listed = GAM.Stock and GAM.Stock.Listed and GAM.Stock.Listed(id) or 0,
                streak = Model.ExpiryStreak(byItem[id]),
                recentExpires = Model.RecentExpires(byItem[id], (GetServerTime and GetServerTime()) or (time and time()) or 0),
            }, opts)
            row.ts, row.prices, row.produced, row.other = ts, prices, summary.produced, summary.other
            row.paid, row.fromPaid = summary.paid, summary.fromPaid
            -- The lowest listing is far above the item's normal price in a very
            -- thin market (a lone troll post): suggest the normal price, unticked.
            local normal, unreliable
            if GAM.Pricing.UnreliableSale then normal, unreliable = GAM.Pricing.UnreliableSale(id) end
            if unreliable then
                row.unreliable, row.normal, row.on = true, normal, false
                if normal then row.price = Posting.RoundPrice and Posting.RoundPrice(normal) or normal end
            end
            -- Items not from the queue may be the player's own materials: start unticked.
            if row.other then row.on = false end
            local queued = session.refreshing[id]
            row.refreshing = queued and now - queued < REFRESH_TIMEOUT or false
            if not row.other then row.cost, row.costShare = Posting.YourCost(id, row.breakEven, opts, memo) end
            local edit = session.edits[id]
            -- Unticked after posting: more in bags since then (returned or newly
            -- crafted items) means there is something new to post.
            if edit and edit.postedLeft and row.bags > edit.postedLeft then
                session.edits[id], edit = nil, nil
            end
            if edit then
                if edit.price then row.price = edit.price end
                if edit.qty then row.qty = math.max(1, math.min(edit.qty, row.bags)) end
                if edit.on ~= nil then row.on = edit.on and row.bags > 0 end
            end
            if row.bags <= 0 then row.on = false; row.qty = 0 end
            row.status = Model.Status(row, opts)
            row.flags = Model.Flags(row, opts)
            rows[#rows + 1] = row
        end
    end
    return rows
end

function Posting.SetEdit(itemID, field, value)
    session.edits[itemID] = session.edits[itemID] or {}
    session.edits[itemID][field] = value
    Changed()
end

function Posting.SetCancel(auctionID, on)
    session.cancelEdits[auctionID] = on and true or false
    Changed()
end

-- Silver is the smallest Auction House price step.
function Posting.RoundPrice(copper)
    copper = math.floor(tonumber(copper) or 0)
    return math.max(100, copper - copper % 100)
end

function Posting.Deposit(itemID, qty, duration)
    local api = C_AuctionHouse
    if not (api and api.CalculateCommodityDeposit) or not qty or qty <= 0 then return nil end
    local ok, value = pcall(api.CalculateCommodityDeposit, itemID, DURATION_ENUM[duration] or 1, qty)
    return ok and tonumber(value) or nil
end

-- ===== Price refresh =====

-- Price checks GAM starts on its own (Auction House opened, auction list
-- read): only with the setting on and a GAM window open. Recheck and the
-- Scan buttons always work.
function Posting.AutoScanAllowed()
    if not Posting.Options().autoScan then return false end
    local window = GAM.UI and GAM.UI.MainWindow
    return window and window.IsShown and window.IsShown() and true or false
end

function Posting.RefreshPrices(itemIDs, force)
    local scan = GAM.AHScan
    local queue = scan and (scan.QueueFreshItemScan or scan.QueueItemScan)
    if not (GAM.ahOpen and queue) then return end
    local now, queued = Now(), false
    for _, id in ipairs(itemIDs or {}) do
        local last = session.refreshing[id]
        if force or not last or now - last >= REFRESH_TIMEOUT then
            session.refreshing[id] = now
            queue(id, function()
                session.refreshing[id] = nil
                Changed()
            end, "posting")
            queued = true
        end
    end
    if queued and scan.StartScan and not (scan.IsScanning and scan.IsScanning()) then scan.StartScan() end
    -- A failed refresh never calls back; redraw once the timeout has passed.
    if queued and C_Timer and C_Timer.After then C_Timer.After(REFRESH_TIMEOUT + 1, Changed) end
    Changed()
end

-- The Recheck button: re-read your auctions and re-check every item's price.
function Posting.Recheck()
    if not GAM.ahOpen then Notify(L("PT_OPEN_AH", "Open the Auction House to post.")); return end
    local ids, seen = {}, {}
    for _, row in ipairs(Posting.Rows()) do
        if not seen[row.itemID] then seen[row.itemID] = true; ids[#ids + 1] = row.itemID end
    end
    for _, auction in ipairs(session.auctions) do
        if not seen[auction.itemID] then seen[auction.itemID] = true; ids[#ids + 1] = auction.itemID end
    end
    Posting.QueryOwned()
    Posting.RefreshPrices(ids, true)
    Notify(L("PT_RECHECKING", "Rechecking %d items...", #ids))
end

-- ===== Own auctions =====

-- Blizzard's Auctions tab keeps the list current itself; a query of GAM's
-- own while it is open would reset that tab's list.
local function AuctionsTabOpen()
    local frame = AuctionHouseFrame and AuctionHouseFrame.AuctionsFrame
    return frame and frame.IsShown and frame:IsShown() or false
end

local function QueryOwned()
    local api = C_AuctionHouse
    if not (GAM.ahOpen and api and api.QueryOwnedAuctions) then return end
    if AuctionsTabOpen() then
        session.queryWanted = "tab"
        Posting.OnOwnedUpdated()
        return
    end
    -- A query sent while the Auction House is throttled is dropped: send it
    -- when the Auction House is ready again.
    if api.IsThrottledMessageSystemReady and not api.IsThrottledMessageSystemReady() then
        session.queryWanted = "throttle"
        return
    end
    session.queryWanted = nil
    pcall(api.QueryOwnedAuctions, {})
end
Posting.QueryOwned = QueryOwned

-- Called when Blizzard's Auctions tab closes or the Auction House is ready.
function Posting.RunWantedQuery()
    if session.queryWanted and not AuctionsTabOpen() then QueryOwned() end
end

local function TrackedItems()
    local tracked = {}
    local plan = GAM.CraftPlan
    if plan and plan.OutputSummary and plan.Project then
        local ok, projection = pcall(plan.Project)
        if ok then
            for _, summary in ipairs(plan.OutputSummary(projection)) do
                tracked[summary.itemID] = summary.breakEven and math.ceil(summary.breakEven) or false
            end
        end
    end
    if GAM.CraftHistory then
        for _, record in ipairs(GAM.CraftHistory.ArchivedPlans and GAM.CraftHistory.ArchivedPlans() or {}) do
            for itemID in pairs(record.outputs or {}) do
                if tracked[itemID] == nil then tracked[itemID] = record.breakEven and record.breakEven[itemID] or false end
            end
        end
        for _, event in ipairs(GAM.CraftHistory.Events({ kind = "post" })) do
            if tracked[event.itemID] == nil then tracked[event.itemID] = false end
        end
    end
    return tracked
end
Posting.TrackedItems = TrackedItems

-- The latest post of this item at this price: its baseline of other sellers
-- and when it was posted (local clock, same as scan timestamps).
local function PostAt(itemID, price)
    local events = EventsByItem()[itemID] or {}
    for index = #events, 1, -1 do
        local event = events[index]
        if event.kind == "post" and event.unitPrice == price then return event end
    end
end

local function Evaluate(auction, opts)
    local tiers, ts, prices = Posting.Listing(auction.itemID)
    local post = PostAt(auction.itemID, auction.price)
    -- A scan older than the post cannot contain it: treat the price as unknown.
    local stale = post and post.postedLocal and ts and ts < post.postedLocal
    auction.lowest = not stale and tiers[1] and not tiers[1].unknown and tiers[1].price or nil
    -- A fresh scan with no other seller: you are the only one.
    auction.alone = not stale and prices ~= nil and tiers[1] == nil or false
    -- Blizzard's cancel cost, and whether the player can pay it.
    local api = C_AuctionHouse
    if auction.cancelCost == nil then
        local ok, cost = false, nil
        if api and api.GetCancelCost then ok, cost = pcall(api.GetCancelCost, auction.auctionID) end
        auction.cancelCost = ok and tonumber(cost) or false
    end
    auction.cantAfford = GetMoney and (auction.cancelCost or 0) > (GetMoney() or 0) or false
    local baseline = post and post.othersAtPrice
    auction.postedAfter = not stale and Model.PostedAfter(prices, auction.price, baseline) or false
    auction.ahead, auction.aheadExact = nil, nil
    if prices and not stale then auction.ahead, auction.aheadExact = Model.UnitsAhead(prices, auction.price, baseline) end
    auction.stale = stale
    -- When this item was last cancelled (re-cancel guard).
    auction.now = (GetServerTime and GetServerTime()) or (time and time()) or 0
    auction.lastCancel, auction.cancelTimes = nil, {}
    local since = auction.now - 24 * 3600
    for _, event in ipairs(EventsByItem()[auction.itemID] or {}) do
        if event.kind == "cancel" and (event.t or 0) >= since then
            auction.cancelTimes[#auction.cancelTimes + 1] = event.t or 0
            if not auction.lastCancel or (event.t or 0) > auction.lastCancel then auction.lastCancel = event.t end
        end
    end
    auction.state = Model.AuctionState(auction, opts)
end

local function LastPostDuration(itemID)
    local events = EventsByItem()[itemID] or {}
    for index = #events, 1, -1 do
        if events[index].kind == "post" then return events[index].duration end
    end
end

-- Reads again shortly: Blizzard sends the list in parts, and rows can arrive
-- before their item data.
local function RetryRead()
    session.readRetries = (session.readRetries or 0) + 1
    if session.readRetries > READ_RETRIES then
        -- Give up until the next update; the last complete list stays shown.
        session.auctionsReading = nil
        if GAM.Log and GAM.Log.Debug then GAM.Log.Debug("Posting: auction list still incomplete, kept the last one") end
        return
    end
    if session.retryQueued or not (C_Timer and C_Timer.After) then return end
    session.retryQueued = true
    C_Timer.After(READ_RETRY_SECONDS, function()
        session.retryQueued = nil
        if GAM.ahOpen then Posting.OnOwnedUpdated() end
    end)
end

-- Returns true when the whole list was read. An incomplete list never
-- replaces the last complete one.
function Posting.ReadOwned()
    local api = C_AuctionHouse
    if not (api and api.GetNumOwnedAuctions and api.GetOwnedAuctionInfo) then return false end
    if api.HasFullOwnedAuctionResults and not api.HasFullOwnedAuctionResults() then
        session.auctionsReading = true
        RetryRead()
        Changed()
        return false
    end
    local tracked, opts, list, soldPending = TrackedItems(), Posting.Options(), {}, {}
    local soldIDs = {}
    for index = 1, api.GetNumOwnedAuctions() or 0 do
        local ok, info = pcall(api.GetOwnedAuctionInfo, index)
        if not (ok and info and info.itemKey and info.itemKey.itemID) then
            session.auctionsReading = true
            RetryRead()
            Changed()
            return false
        end
        local itemID = info.itemKey.itemID
        -- Any item a GAM strategy makes is watched too, not only queue outputs.
        if itemID and tracked[itemID] == nil and OutputIndex()[itemID] then
            tracked[itemID] = Posting.StrategyBreakEven(itemID) or false
        end
        -- Sold entries stay in the list until the sale mail arrives (about an
        -- hour). The sale is recorded when that mail is collected.
        -- Units sold per auction (a commodity auction can sell in parts).
        if itemID and info.status == 1 then soldIDs[info.auctionID] = (soldIDs[info.auctionID] or 0) + (info.quantity or 0) end
        if itemID and info.status == 1 and tracked[itemID] ~= nil then
            soldPending[itemID] = (soldPending[itemID] or 0) + (info.quantity or 0)
        end
        if itemID and info.status == 0 and tracked[itemID] ~= nil and info.buyoutAmount then
            local auction = {
                auctionID = info.auctionID, itemID = itemID, qty = info.quantity or 0,
                price = info.buyoutAmount, timeLeft = info.timeLeftSeconds,
                breakEven = tracked[itemID] or nil,
            }
            Evaluate(auction, opts)
            auction.deposit = Posting.Deposit(itemID, auction.qty, LastPostDuration(itemID) or opts.duration) or 0
            local edit = session.cancelEdits[auction.auctionID]
            auction.on = Model.Cancellable(auction)
                and (edit == nil and Model.CancelDefault(auction, opts) or edit == true)
            list[#list + 1] = auction
        end
    end
    table.sort(list, function(a, b) return a.auctionID < b.auctionID end)
    -- Undercuts happen after posting: re-check listed items whose scan is
    -- missing or old (they may not be on the post list any more).
    local stale, seen, clock = {}, {}, time and time() or 0
    for _, auction in ipairs(list) do
        if not seen[auction.itemID] then
            seen[auction.itemID] = true
            local _, ts, prices = Posting.Listing(auction.itemID)
            if auction.stale or not auction.lowest or not prices or not ts or clock - ts > STALE_SECONDS then
                stale[#stale + 1] = auction.itemID
            end
        end
    end
    if #stale > 0 and Posting.AutoScanAllowed() then Posting.RefreshPrices(stale) end
    session.auctions = list
    session.soldPending = soldPending
    if GAM.HistoryCapture and GAM.HistoryCapture.Settle then
        local ok, err = pcall(GAM.HistoryCapture.Settle, list, soldIDs)
        if not ok and GAM.Log and GAM.Log.Warn then GAM.Log.Warn("History settle failed: %s", tostring(err)) end
    end
    if GAM.Stock then GAM.Stock.SaveListed(list, soldPending, soldIDs) end
    session.auctionsLoaded, session.auctionsReading, session.readRetries = true, nil, 0
    Changed()
    return true
end

-- A complete read also lets finished plans move to History.
function Posting.OnOwnedUpdated()
    if Posting.ReadOwned() and GAM.CraftPlan and GAM.CraftPlan.ArchiveFinished then
        pcall(GAM.CraftPlan.ArchiveFinished)
    end
end

function Posting.Auctions()
    -- Re-evaluate against the latest prices and settings each time.
    local opts = Posting.Options()
    for _, auction in ipairs(session.auctions) do
        Evaluate(auction, opts)
        local edit = session.cancelEdits[auction.auctionID]
        auction.on = Model.Cancellable(auction)
            and (edit == nil and Model.CancelDefault(auction, opts) or edit == true)
    end
    return session.auctions, session.auctionsLoaded
end

-- ===== The one button =====

local function FindBagLocation(itemID)
    if not (C_Container and ItemLocation) then return nil end
    -- Crafted reagents land in the reagent bag (after the regular bags).
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID and not info.isLocked then
                return ItemLocation:CreateFromBagAndSlot(bag, slot)
            end
        end
    end
end

local function Timeout(pending)
    if C_Timer and C_Timer.After then
        C_Timer.After(10, function()
            if session.pending == pending then
                session.pending = nil
                Notify(L("PT_NO_RESPONSE", "The Auction House did not respond. Press the button again."))
            end
        end)
    end
end

-- What the button will do next, for its label: "cancel"/"post"/"confirm", target.
function Posting.NextAction(rows, auctions)
    if session.warning then return "confirm", session.warning end
    return Model.NextAction(auctions or Posting.Auctions(), rows or Posting.Rows())
end

function Posting.IsBusy() return session.pending ~= nil end

-- Called from the button's OnClick: each post and cancel needs a click.
function Posting.DoNext()
    if session.pending then return false end
    if not GAM.ahOpen then Notify(L("PT_OPEN_AH", "Open the Auction House to post.")); return false end
    if InCombatLockdown and InCombatLockdown() then Notify(L("WF_LEAVE_COMBAT", "Leave combat before crafting.")); return false end
    local api = C_AuctionHouse
    local kind, target = Posting.NextAction()
    if kind == "confirm" then
        session.warning = nil
        session.pending = target
        local ok = pcall(api.ConfirmPostCommodity, target.location, target.durationEnum, target.qty, target.price)
        if not ok then session.pending = nil; Notify(L("PT_POST_FAILED", "The post failed. Check the item and try again.")) end
        Timeout(target)
        Changed()
        return ok
    elseif kind == "cancel" then
        local pending = { kind = "cancel", auctionID = target.auctionID, itemID = target.itemID,
            qty = target.qty, deposit = target.deposit }
        session.pending = pending
        local ok = pcall(api.CancelAuction, target.auctionID)
        if not ok then session.pending = nil; Notify(L("PT_CANCEL_FAILED", "The cancel failed. Try again.")); return false end
        Timeout(pending)
        Changed()
        return true
    elseif kind == "post" then
        local opts = Posting.Options()
        local location = FindBagLocation(target.itemID)
        if not location then Notify(L("PT_NOT_IN_BAGS", "The item is not in your bags (or is locked).")); return false end
        local qty = target.qty
        if api.GetAvailablePostCount then
            local ok, available = pcall(api.GetAvailablePostCount, location)
            if ok and tonumber(available) then qty = math.min(qty, available) end
        end
        if qty <= 0 then Notify(L("PT_NOT_IN_BAGS", "The item is not in your bags (or is locked).")); return false end
        local price = Posting.RoundPrice(target.price)
        local pending = { kind = "post", itemID = target.itemID, qty = qty, price = price,
            duration = opts.duration, durationEnum = DURATION_ENUM[opts.duration], location = location,
            deposit = Posting.Deposit(target.itemID, qty, opts.duration) or 0 }
        session.pending = pending
        local ok = pcall(api.PostCommodity, location, pending.durationEnum, qty, price)
        if not ok then session.pending = nil; Notify(L("PT_POST_FAILED", "The post failed. Check the item and try again.")); return false end
        Timeout(pending)
        Changed()
        return true
    end
    return false
end

-- ===== Events =====

local function OnPosted(auctionID)
    local pending = session.pending
    if GAM.Log and GAM.Log.Debug then
        GAM.Log.Debug("Posting post confirmed: auctionID=%s pending=%s", tostring(auctionID),
            tostring(pending and pending.kind == "post" and (pending.itemID .. " x" .. pending.qty) or "none"))
    end
    if not pending or pending.kind ~= "post" then return end
    -- HistoryCapture records the post (from any addon); this only updates the tab.
    session.pending = nil
    -- Untick after posting; the rest stays for next time.
    -- What stayed in bags; more than this later is new stock to post.
    session.edits[pending.itemID] = { on = false, postedLeft = BagCount(pending.itemID) }
    session.message = L("PT_POSTED", "Posted %d.", pending.qty)
    QueryOwned()
    Changed()
end

-- Records one cancelled auction (once) and releases its tick; Stock counts
-- the items coming back by mail from the record. HistoryCapture calls it for every cancel of a
-- tracked auction, whichever addon made it.
local function RecordCancel(target)
    local store = GAM.CraftHistory and GAM.CraftHistory.Store()
    store = store or {}
    store.cancelledAuctions = store.cancelledAuctions or {}
    if store.cancelledAuctions[target.auctionID] then return end
    store.cancelledAuctions[target.auctionID] = true
    if GAM.CraftHistory then
        GAM.CraftHistory.Record("cancel", { itemID = target.itemID, qty = target.qty, copper = target.deposit or 0,
            auctionID = target.auctionID })
    end
    session.cancelEdits[target.auctionID] = nil
    for index, auction in ipairs(session.auctions) do
        if auction.auctionID == target.auctionID then table.remove(session.auctions, index); break end
    end
    session.message = L("PT_CANCELLED", "Cancelled. The items come back by mail.")
    return true
end
Posting.RecordCancel = RecordCancel

-- The cancel is recorded by HistoryCapture; this releases the button.
local function OnCancelled()
    local pending = session.pending
    if pending and pending.kind == "cancel" then session.pending = nil end
    QueryOwned()
    Changed()
end

function Posting.OnEvent(event, ...)
    if event == "AUCTION_HOUSE_SHOW" then
        -- A new visit starts from the rules: edits from the last visit used
        -- prices that are out of date, and unticks hid items since returned.
        session.pending, session.warning, session.edits, session.cancelEdits = nil, nil, {}, {}
        if GAM.Stock then GAM.Stock.RecordVisit() end
        -- Blizzard's Auctions tab: query once it closes.
        local tab = AuctionHouseFrame and AuctionHouseFrame.AuctionsFrame
        if tab and tab.HookScript and not Posting.tabHooked then
            Posting.tabHooked = true
            tab:HookScript("OnHide", function() Posting.RunWantedQuery() end)
        end
        QueryOwned()
        -- After the window has had its chance to open with the Auction House.
        local function Refresh()
            if not (GAM.ahOpen and Posting.AutoScanAllowed()) then return end
            local ids = {}
            for _, row in ipairs(Posting.Rows()) do ids[#ids + 1] = row.itemID end
            Posting.RefreshPrices(ids)
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.5, Refresh) else Refresh() end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if GAM.Stock then GAM.Stock.RecordVisit() end
        session.pending, session.warning, session.refreshing = nil, nil, {}
        session.queryWanted, session.auctionsReading, session.readRetries = nil, nil, 0
        Changed()
    elseif event == "OWNED_AUCTIONS_UPDATED" then
        session.readRetries = 0
        Posting.OnOwnedUpdated()
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        Posting.RunWantedQuery()
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
        OnPosted(...)
    elseif event == "AUCTION_HOUSE_POST_WARNING" then
        local pending = session.pending
        if pending and pending.kind == "post" then
            session.pending, session.warning = nil, pending
            Notify(L("PT_PRICE_WARNING", "Blizzard warns this price is unusual. Press the button again to confirm."))
        end
    elseif event == "AUCTION_HOUSE_POST_ERROR" then
        if session.pending and session.pending.kind == "post" then
            session.pending = nil
            Notify(L("PT_POST_FAILED", "The post failed. Check the item and try again."))
        end
    elseif event == "AUCTION_CANCELED" then
        OnCancelled(...)
    elseif event == "BAG_UPDATE_DELAYED" then
        Changed()
    end
end

function Posting.Init()
    if Posting.frame or not CreateFrame then return end
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "OWNED_AUCTIONS_UPDATED",
            "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_POST_WARNING", "AUCTION_HOUSE_POST_ERROR",
            "AUCTION_CANCELED", "BAG_UPDATE_DELAYED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, ...) Posting.OnEvent(event, ...) end)
    Posting.frame = frame
end
