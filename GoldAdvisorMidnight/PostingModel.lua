-- GoldAdvisorMidnight/PostingModel.lua
-- Pure rules for the Posting tab: starting price and quantity, row status,
-- and what to do with the player's own auctions. No game API calls here.
-- Module: GAM.PostingModel

local ADDON_NAME, GAM = ...
local Model = {}
GAM.PostingModel = Model

Model.DEFAULTS = {
    duration = 12,          -- hours: 12, 24 or 48
    startQty = "rec",       -- "rec" (TSM sold/day x duration) or "all"
    skipBelow = true,       -- rows below break-even start unticked
    marginWarn = 0.20,      -- amber warning under break-even + 20%
    thinPct = 0.10,         -- a top price tier under 10% of the post is "small"
    streakLimit = 3,        -- expires in a row before a row starts unticked; 0 = off
    checkAuctions = true,   -- read the player's own auctions when the AH opens
    autoScan = false,       -- re-check prices on their own (only while a GAM window is open); off since 2.3.2
    includeOther = true,    -- also list other strategy outputs found in bags/bank
    cancelUndercut = true,  -- pre-tick undercut auctions for cancel and repost
    matchedIsUndercut = true, -- a same-price listing posted after mine counts
    cancelDepositPct = 0.05,  -- skip the pre-tick when the lost deposit is larger
    maxExpires = 0,         -- expiries within 14 days before a row starts unticked; 0 = off
    repostHigher = true,    -- pre-tick a cancel when the next seller is well above you
    repostHigherPct = 0.20, -- "well above": 20% over your price
    ahCut = 0.05,
}

-- Other sellers' listings this close to expiring are ignored: they are
-- likely to come back unsold rather than sell first.
Model.IGNORE_EXPIRING_SECONDS = 1800

function Model.Options(saved)
    local out = {}
    for key, value in pairs(Model.DEFAULTS) do out[key] = value end
    for key, value in pairs(type(saved) == "table" and saved or {}) do
        if out[key] ~= nil and type(value) == type(out[key]) then out[key] = value end
    end
    if out.duration ~= 12 and out.duration ~= 24 and out.duration ~= 48 then out.duration = 12 end
    return out
end

-- Units of other sellers in a row (a commodity row combines every seller at
-- one price; numMine is the player's share of it).
local function OthersIn(row)
    if not row.mine then return row.quantity or 0 end
    return math.max(0, (row.quantity or 0) - (tonumber(row.numMine) or 0))
end

-- Other sellers' listings grouped into ascending price tiers. The player's
-- own units are left out (you never compete with yourself), and so are
-- listings about to expire.
function Model.Tiers(prices)
    local byPrice, tiers = {}, {}
    for _, row in ipairs(prices or {}) do
        local price, qty = tonumber(row.unitPrice), OthersIn(row)
        local expiring = tonumber(row.timeLeft) and tonumber(row.timeLeft) < Model.IGNORE_EXPIRING_SECONDS
        if price and price > 0 and qty > 0 and not expiring then
            if not byPrice[price] then
                byPrice[price] = { price = price, qty = 0 }
                tiers[#tiers + 1] = byPrice[price]
            end
            byPrice[price].qty = byPrice[price].qty + qty
        end
    end
    table.sort(tiers, function(a, b) return a.price < b.price end)
    return tiers
end

-- Match the lowest listing; never undercut. With no competition, the higher
-- of the last known market price and break-even plus the warning margin.
function Model.StartPrice(tiers, breakEven, market, opts)
    if tiers and tiers[1] then return tiers[1].price end
    local floor = breakEven and math.ceil(breakEven * (1 + opts.marginWarn)) or 0
    local price = math.max(tonumber(market) or 0, floor)
    return price > 0 and price or nil
end

-- About one auction's worth of regional sales, capped at what is in bags.
-- Units you already have listed count toward it (as TSM's post cap does):
-- only the rest is suggested. Returns the quantity and whether your current
-- listings already cover it.
function Model.StartQty(bags, soldPerDay, opts, listed)
    bags = math.max(0, math.floor(tonumber(bags) or 0))
    if opts.startQty ~= "rec" or not soldPerDay or soldPerDay <= 0 then return bags, false end
    local target = math.max(1, math.ceil(soldPerDay * opts.duration / 24))
    local rest = target - math.max(0, math.floor(tonumber(listed) or 0))
    -- Covered: the row still shows a full post, unticked, if you want more up.
    if rest <= 0 then return math.min(bags, target), true end
    return math.min(bags, rest), false
end

-- Consecutive expiries since the item last sold (events oldest first).
function Model.ExpiryStreak(events)
    local streak = 0
    for _, event in ipairs(events or {}) do
        if event.kind == "sold" then streak = 0
        elseif event.kind == "expired" then streak = streak + 1 end
    end
    return streak
end

-- Expiries of the item in the last `days` days (events oldest first).
Model.EXPIRE_WINDOW_DAYS = 14
function Model.RecentExpires(events, now, days)
    local since, count = (now or 0) - (days or Model.EXPIRE_WINDOW_DAYS) * 86400, 0
    for _, event in ipairs(events or {}) do
        if event.kind == "expired" and (event.t or 0) >= since then count = count + 1 end
    end
    return count
end

-- A longer auction length to suggest when auctions keep expiring while the
-- player is away: their usual time between Auction House visits is longer
-- than the auctions last. visits: { s, e } oldest first; expires: expiries
-- in the last 14 days. Returns the hours to suggest (24 or 48) and the
-- usual gap in hours, or nil.
Model.SUGGEST_MIN_EXPIRES = 3
Model.SUGGEST_MIN_GAPS = 3
function Model.SuggestDuration(visits, expires, current)
    current = current or 12
    if (expires or 0) < Model.SUGGEST_MIN_EXPIRES or current >= 48 then return nil end
    local gaps = {}
    for i = 2, #(visits or {}) do
        local gap = (visits[i].s or 0) - (visits[i - 1].e or 0)
        if gap > 0 then gaps[#gaps + 1] = gap / 3600 end
    end
    if #gaps < Model.SUGGEST_MIN_GAPS then return nil end
    table.sort(gaps)
    local usual = gaps[math.ceil(#gaps / 2)]
    if usual <= current then return nil end
    local suggest = usual <= 24 and 24 or 48
    if suggest <= current then return nil end
    return suggest, usual
end

function Model.Profit(price, breakEven, qty, opts)
    if not price or not breakEven then return nil end
    return math.floor((price - breakEven) * (1 - opts.ahCut) * (qty or 0))
end

-- input: itemID, bags, bank, mail, breakEven, market, tiers, soldPerDay, streak.
-- Returns the row the tab shows, before the player edits price or quantity.
function Model.BuildRow(input, opts)
    local row = {
        itemID = input.itemID, bags = input.bags or 0, bank = input.bank or 0, mail = input.mail or 0,
        breakEven = input.breakEven, tiers = input.tiers or {}, soldPerDay = input.soldPerDay,
        streak = input.streak or 0, recentExpires = input.recentExpires or 0,
    }
    row.price = Model.StartPrice(row.tiers, row.breakEven, input.market, opts)
    row.listed = input.listed or 0
    row.qty, row.covered = Model.StartQty(row.bags, row.soldPerDay, opts, row.listed)
    row.recQty = row.qty
    row.on = Model.DefaultTick(row, opts)
    return row
end

-- Expiring too often: too many in a row, or (optional) too many in 14 days.
function Model.Streaky(row, opts)
    return (opts.streakLimit > 0 and (row.streak or 0) >= opts.streakLimit)
        or (opts.maxExpires > 0 and (row.recentExpires or 0) >= opts.maxExpires)
end

function Model.DefaultTick(row, opts)
    if row.bags <= 0 or not row.price then return false end
    if opts.skipBelow and row.breakEven and row.price < row.breakEven then return false end
    if row.covered then return false end
    return not Model.Streaky(row, opts)
end

-- The flags behind the status dot and its tooltip.
function Model.Flags(row, opts)
    local flags = {}
    local tiers = row.tiers or {}
    flags.noCompetition = tiers[1] == nil
    flags.below = row.breakEven ~= nil and row.price ~= nil and row.price < row.breakEven
    flags.lowMargin = not flags.below and row.breakEven ~= nil and row.price ~= nil
        and row.price < row.breakEven * (1 + opts.marginWarn)
    flags.thin = tiers[2] ~= nil and row.price == tiers[1].price
        and tiers[1].qty < (row.qty or 0) * opts.thinPct
    flags.streak = Model.Streaky(row, opts)
    flags.covered = row.covered or false
    flags.unreliable = row.unreliable or false
    flags.noPrice = row.price == nil
    return flags
end

-- "mail" | "bank" | "noprice" | "bad" | "warn" | "ok"
function Model.Status(row, opts)
    if row.bags <= 0 then
        if (row.mail or 0) > 0 then return "mail" end
        return "bank"
    end
    local flags = Model.Flags(row, opts)
    if flags.noPrice then return "noprice" end
    if flags.below then return "bad" end
    if flags.streak or flags.thin or flags.lowMargin or flags.noCompetition or flags.covered or flags.unreliable then return "warn" end
    return "ok"
end

-- Other sellers' units at exactly `price`.
function Model.OthersAtPrice(prices, price)
    local others = 0
    for _, row in ipairs(prices or {}) do
        if row.unitPrice == price then others = others + OthersIn(row) end
    end
    return others
end

-- Blizzard combines every seller at one price into one row and does not say
-- who posted first; the newest listing sells first. `baseline` is how many
-- other units sat at this price when the player posted: those are behind the
-- player, so only units beyond it count as posted after. Without a baseline
-- (posted outside GAM), every other seller at the price is treated as ahead.
function Model.PostedAfter(prices, price, baseline)
    local mineAtPrice = false
    for _, row in ipairs(prices or {}) do
        if row.unitPrice == price and row.mine then mineAtPrice = true end
    end
    return mineAtPrice and Model.OthersAtPrice(prices, price) > (baseline or 0)
end

-- Units that sell before the player's listing: everything cheaper, plus
-- other sellers who joined the player's price after them (see PostedAfter).
function Model.UnitsAhead(prices, price, baseline)
    local ahead, reached = 0, false
    for _, row in ipairs(prices or {}) do
        if row.unitPrice then
            if row.unitPrice > price or (row.unitPrice == price and row.mine) then reached = true end
            if row.unitPrice < price then ahead = ahead + OthersIn(row) end
        end
    end
    ahead = ahead + math.max(0, Model.OthersAtPrice(prices, price) - (baseline or 0))
    -- The scan may stop before reaching the player's listing (deep markets):
    -- then the count is a minimum.
    return ahead, reached
end

-- Own auctions. auction: price, qty, lowest (other sellers' lowest price),
-- alone (a fresh scan found no other seller), postedAfter (a same-price
-- listing newer than mine), breakEven, deposit (paid), cancelCost (Blizzard's).
-- "unknown" | "top" | "higher" | "matched" | "under" | "leave"
function Model.AuctionState(auction, opts)
    local lowest = auction.lowest
    -- Without a current lowest price nothing can be said: never claim first in line.
    if not lowest then return auction.alone and "top" or "unknown" end
    local undercut = lowest < auction.price
    local matched = not undercut and lowest == auction.price and auction.postedAfter and opts.matchedIsUndercut
    if not undercut and not matched then
        -- First in line, but the next seller is well above: room to repost higher.
        if lowest > auction.price * (1 + opts.repostHigherPct) then return "higher" end
        return "top"
    end
    if auction.breakEven and lowest < auction.breakEven then return "leave" end
    return undercut and "under" or "matched"
end

-- What cancelling costs: the deposit that is not refunded, or Blizzard's
-- cancel cost when that is higher.
function Model.CancelCost(auction)
    return math.max(auction.deposit or 0, auction.cancelCost or 0)
end

function Model.CancelWorthIt(auction, opts)
    if Model.AuctionState(auction, opts) == "higher" then
        -- The extra gold from the higher price must beat the lost deposit
        -- plus the new one.
        local gain = (auction.qty or 0) * ((auction.lowest or 0) - auction.price) * (1 - opts.ahCut)
        return gain > Model.CancelCost(auction) + (auction.deposit or 0)
    end
    local value = (auction.qty or 0) * (auction.lowest or 0) * (1 - opts.ahCut)
    return Model.CancelCost(auction) <= opts.cancelDepositPct * value
end

-- Auctions the player can act on; never one they cannot afford to cancel.
function Model.Cancellable(auction)
    local state = auction.state
    return (state == "under" or state == "matched" or state == "higher") and not auction.cantAfford
end

-- A newer listing at your price is worth a cancel only when it holds at
-- least as many units as your auction; a few units ahead sell quickly, and
-- cancelling for them loses a deposit and a click (the simulation showed
-- busy markets cancelling several times what they sold).
function Model.MatchedWorthIt(auction)
    return auction.ahead == nil or auction.ahead >= (auction.qty or 0)
end

-- Cancelled within the last hour: a new seller at your price does not
-- pre-tick the cancel again (others keep matching, and each round loses a
-- deposit). An undercut still does. The simulation found re-cancels an hour
-- or more apart pay for themselves in faster sales.
Model.RECANCEL_HOURS = 1
Model.RECANCEL_LIMIT = 1
function Model.RecentlyCancelled(auction, now)
    local since, count = (now or 0) - Model.RECANCEL_HOURS * 3600, 0
    for _, t in ipairs(auction.cancelTimes or {}) do if t >= since then count = count + 1 end end
    return count >= Model.RECANCEL_LIMIT
end

function Model.CancelDefault(auction, opts)
    local state = Model.AuctionState(auction, opts)
    if auction.cantAfford then return false end
    if state == "matched" and not Model.MatchedWorthIt(auction) then return false end
    if state == "matched" and Model.RecentlyCancelled(auction, auction.now) then return false end
    if state == "higher" then return opts.repostHigher and Model.CancelWorthIt(auction, opts) or false end
    return opts.cancelUndercut and (state == "under" or state == "matched")
        and Model.CancelWorthIt(auction, opts) or false
end

-- The single button's next action: ticked cancels first, then ticked posts.
function Model.NextAction(auctions, rows)
    for _, auction in ipairs(auctions or {}) do
        if auction.on then return "cancel", auction end
    end
    for _, row in ipairs(rows or {}) do
        if row.on and row.bags > 0 and (row.qty or 0) > 0 and row.price then return "post", row end
    end
    return nil
end
