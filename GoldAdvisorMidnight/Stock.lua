-- GoldAdvisorMidnight/Stock.lua
-- Everything the player owns of an item: bags and banks, listed on the
-- Auction House, and returned items waiting in the mailbox. Listed and mail
-- counts are remembered from the last Auction House and mailbox visits, and
-- kept current with posts and cancels recorded since.
-- Module: GAM.Stock

local ADDON_NAME, GAM = ...
local function L(key, fallback, ...)
    local value = (GAM.L and GAM.L[key]) or fallback
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end

local Stock = {}
GAM.Stock = Stock

Stock.WELL_STOCKED_DAYS = 7   -- warn when what you own covers this many days of your sales
Stock.RATE_DAYS = 14          -- your sales rate is measured over this many days
Stock.RECENT_DAYS = 3         -- ...and over the last few days; the lower rate is used

local function Now() return (GetServerTime and GetServerTime()) or (time and time()) or 0 end

local function Saved()
    local store = GAM.CraftHistory and GAM.CraftHistory.Store()
    if not store then return nil end
    -- The mailbox starts empty: cancels from now on count until it is read.
    store.stock = store.stock or { listed = {}, mail = {}, mailAt = Now() - 1 }
    return store.stock
end

-- Auction House visits, to tell how long the player is usually away:
-- { s = first open, e = last seen }; opening again within an hour of the
-- last one continues the same visit.
Stock.VISIT_MERGE_SECONDS = 3600
Stock.VISIT_KEEP_DAYS = 14
function Stock.RecordVisit(t)
    local saved = Saved()
    if not saved then return end
    t = t or Now()
    saved.visits = saved.visits or {}
    local last = saved.visits[#saved.visits]
    if last and t - last.e < Stock.VISIT_MERGE_SECONDS then
        last.e = math.max(last.e, t)
    else
        saved.visits[#saved.visits + 1] = { s = t, e = t }
    end
    local keep, since = {}, t - Stock.VISIT_KEEP_DAYS * 86400
    for _, visit in ipairs(saved.visits) do if visit.e >= since then keep[#keep + 1] = visit end end
    saved.visits = keep
end
function Stock.Visits()
    local saved = Saved()
    return saved and saved.visits or {}
end

-- The auction-length prompt, once opened, stays away for a week.
Stock.HINT_SNOOZE_DAYS = 7
function Stock.SnoozeDurationHint()
    local saved = Saved()
    if saved then saved.durationHintAt = Now() end
end
function Stock.DurationHintSnoozed()
    local saved = Saved()
    return saved and saved.durationHintAt and Now() - saved.durationHintAt < Stock.HINT_SNOOZE_DAYS * 86400 or false
end

-- Tallies are rebuilt only when the history changes: Posting asks for
-- hundreds of items at a time.
local cache = { key = nil, since = {} }
local function LogKey()
    local store = GAM.CraftHistory and GAM.CraftHistory.Store()
    local events = store and store.events or {}
    local last = events[#events]
    return #events .. ":" .. tostring(last and last.id) .. ":" .. tostring(last and last.qty)
end
local function Cached(name, build)
    local key = LogKey()
    if cache.key ~= key then cache = { key = key, since = {} } end
    if cache[name] == nil then cache[name] = build() end
    return cache[name]
end

-- Posts, cancels and sales recorded after a snapshot, per item. Posts come
-- as a list of { qty, at } where at is when the auction expires.
local function Since(t)
    t = t or 0
    local tallies = Cached("since", function() return {} end)
    if not tallies[t] then
        local posted, cancelled, sold = {}, {}, {}
        for _, event in ipairs(GAM.CraftHistory and GAM.CraftHistory.Events({ since = t + 1 }) or {}) do
            if event.kind == "post" then
                posted[event.itemID] = posted[event.itemID] or {}
                table.insert(posted[event.itemID], { qty = event.qty,
                    at = event.duration and (event.t + event.duration * 3600) or nil })
            elseif event.kind == "cancel" then cancelled[event.itemID] = (cancelled[event.itemID] or 0) + event.qty
            elseif event.kind == "sold" then sold[event.itemID] = (sold[event.itemID] or 0) + event.qty end
        end
        tallies[t] = { posted, cancelled, sold }
    end
    return tallies[t][1], tallies[t][2], tallies[t][3]
end

-- Units posted and still without a result, per item (no Auction House visit yet).
local function OpenPosts()
    return Cached("open", function()
        local open = {}
        for _, event in ipairs(GAM.CraftHistory and GAM.CraftHistory.Events() or {}) do
            local sign = event.kind == "post" and 1
                or (event.kind == "sold" or event.kind == "expired" or event.kind == "cancel") and -1 or 0
            if sign ~= 0 then open[event.itemID] = (open[event.itemID] or 0) + sign * event.qty end
        end
        return open
    end)
end

-- A complete read of your auctions (Posting) replaces the listed snapshot:
-- per item, each auction's units and when it expires. soldPending: units
-- already showing as sold then (their mail comes later).
-- soldByAuction: units showing as sold per auction ID in this read.
function Stock.SaveListed(auctions, soldPending, soldByAuction)
    local saved = Saved()
    if not saved then return end
    local listed, auctionsByItem, soonest, now, present = {}, {}, nil, Now(), {}
    for _, auction in ipairs(auctions or {}) do
        listed[auction.itemID] = (listed[auction.itemID] or 0) + (auction.qty or 0)
        local left = tonumber(auction.timeLeft)
        if left and (not soonest or left < soonest) then soonest = left end
        auctionsByItem[auction.itemID] = auctionsByItem[auction.itemID] or {}
        table.insert(auctionsByItem[auction.itemID], { qty = auction.qty or 0, at = left and (now + left) or nil,
            id = auction.auctionID })
        if auction.auctionID then present[auction.auctionID] = true end
    end
    -- Auctions from the last read that are gone and past their expiry
    -- expired: their unsold units are in the mailbox until it is read.
    saved.carried = saved.carried or {}
    for itemID, entries in pairs(saved.auctions or {}) do
        for _, e in ipairs(entries) do
            if e.id and not present[e.id] and e.at and e.at <= now and e.at > (saved.mailAt or 0) then
                local qty = e.qty - ((soldByAuction or {})[e.id] or 0)
                if qty > 0 then saved.carried[itemID] = (saved.carried[itemID] or 0) + qty end
            end
        end
    end
    saved.listed, saved.listedAt = listed, now
    saved.auctions, saved.soldAtRead = auctionsByItem, soldPending or {}
    -- For the login reminder: when this character's next auction expires.
    saved.nextExpire = soonest and (Now() + soonest) or nil
    saved.name = Stock.CharacterName()
    cache.key = nil
end

-- Each inbox read (PostingMail) replaces the mail snapshot. mailExpire:
-- when the first Auction House mail with items or gold runs out.
function Stock.SaveMail(returns, mailExpire)
    local saved = Saved()
    if not saved then return end
    saved.mail, saved.mailAt = returns or {}, Now()
    saved.carried = {}   -- the inbox read shows the returned items itself
    saved.mailExpire, saved.name = mailExpire, Stock.CharacterName()
    cache.key = nil
end

-- Since the last read of your auctions, per item: units still listed, and
-- units whose auctions have expired since the last inbox read (their items
-- are on the way back by mail). Sales collected since then come off first;
-- auctions without a known expiry count as listed.
local function Outstanding(itemID)
    local saved = Saved()
    local now = Now()
    local posted, cancelled, sold = Since(saved.listedAt)
    local entries = {}
    if saved.auctions then
        for _, a in ipairs(saved.auctions[itemID] or {}) do entries[#entries + 1] = a end
    elseif (saved.listed[itemID] or 0) > 0 then
        entries[1] = { qty = saved.listed[itemID] }   -- saved before expiries were kept
    end
    for _, p in ipairs(posted[itemID] or {}) do entries[#entries + 1] = p end
    local gone = (cancelled[itemID] or 0)
        + math.max(0, (sold[itemID] or 0) - ((saved.soldAtRead or {})[itemID] or 0))
    local listed, expired = 0, 0
    -- Soonest-expiring first: those sold or were cancelled first, most likely.
    table.sort(entries, function(a, b) return (a.at or math.huge) < (b.at or math.huge) end)
    for _, e in ipairs(entries) do
        local qty = e.qty
        local take = math.min(gone, qty)
        qty, gone = qty - take, gone - take
        if qty > 0 then
            if e.at and e.at <= now then
                if e.at > (saved.mailAt or 0) then expired = expired + qty end
            else
                listed = listed + qty
            end
        end
    end
    return listed, expired
end

function Stock.Listed(itemID)
    local saved = Saved()
    if not (saved and saved.listedAt) then
        -- No Auction House visit yet: posts that have no result yet.
        return math.max(0, OpenPosts()[itemID] or 0)
    end
    return (Outstanding(itemID))
end

-- Cancelled auctions come back by mail straight away; expired ones when
-- their time runs out.
function Stock.InMail(itemID)
    local saved = Saved()
    if not saved then return 0 end
    local _, cancelled = Since(saved.mailAt or Now())
    local expired = 0
    if saved.listedAt then expired = select(2, Outstanding(itemID)) end
    return (saved.mail[itemID] or 0) + (cancelled[itemID] or 0) + expired + ((saved.carried or {})[itemID] or 0)
end

-- { total, held (bags + banks), listed, mail, listedAt }
function Stock.Owned(itemID)
    local plan = GAM.CraftPlan
    local held = plan and plan.Count and plan.Count(itemID) or 0
    local listed, mail = Stock.Listed(itemID), Stock.InMail(itemID)
    local saved = Saved()
    return { total = held + listed + mail, held = held, listed = listed, mail = mail,
        listedAt = saved and saved.listedAt }
end

-- Units you sold per day, from your own recorded sales, and how many days
-- of sales that rate is based on. When the last few days sold slower than
-- the two weeks (a boom has ended), the slower rate is used: suggestions
-- follow the market down straight away and up only as sales confirm it.
function Stock.SalesPerDay(itemID)
    local now = Now()
    local since, recentSince = now - Stock.RATE_DAYS * 86400, now - Stock.RECENT_DAYS * 86400
    local sold, recent, first = 0, 0, nil
    for _, event in ipairs(GAM.CraftHistory and GAM.CraftHistory.Events({ kind = "sold", itemID = itemID, since = since }) or {}) do
        sold = sold + event.qty
        if event.t >= recentSince then recent = recent + event.qty end
        first = math.min(first or event.t, event.t)
    end
    if sold <= 0 then return nil end
    -- At least a day, so one early sale is not read as a huge rate.
    local days = math.max(1, math.min(Stock.RATE_DAYS, (now - first) / 86400))
    local rate = sold / days
    if days > Stock.RECENT_DAYS then rate = math.min(rate, recent / Stock.RECENT_DAYS) end
    if rate <= 0 then return nil end
    return rate, days
end

-- A note for Add to Queue when the player already owns plenty of what the
-- plan makes: nil when stock is low. Never blocks the add.
function Stock.QueueWarning(itemIDs, expected)
    local owned = { total = 0, held = 0, listed = 0, mail = 0 }
    local rate, name = 0, nil
    for _, id in ipairs(itemIDs or {}) do
        local one = Stock.Owned(id)
        for key in pairs(owned) do owned[key] = owned[key] + one[key] end
        rate = rate + (Stock.SalesPerDay(id) or 0)
        name = name or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
    end
    if owned.total <= 0 then return nil end
    local parts = L("WF_STOCK_PARTS", "%d in bags or banks, %d listed, %d in the mailbox", owned.held, owned.listed, owned.mail)
    if rate > 0 then
        local days = owned.total / rate
        if days < Stock.WELL_STOCKED_DAYS then return nil end
        return L("WF_WELL_STOCKED_DAYS", "You already have %d %s (%s): about %d days of your sales.",
            owned.total, name or "", parts, math.floor(days + 0.5))
    end
    if owned.total < (expected or 0) or (expected or 0) <= 0 then return nil end
    return L("WF_WELL_STOCKED", "You already have %d %s (%s), more than this plan makes.",
        owned.total, name or "", parts)
end

function Stock.CharacterName()
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    return name and (realm and (name .. "-" .. realm) or name) or nil
end

Stock.MAIL_WARN_DAYS = 3

-- Login reminders for every character: auctions that have expired since the
-- last visit (their items wait in the mailbox), and Auction House mail about
-- to run out. Returns a list of lines.
function Stock.Reminders()
    local lines, now = {}, Now()
    local chars = GAM.db and GAM.db.craftHistory and GAM.db.craftHistory.characters or {}
    local names = {}
    for key in pairs(chars) do names[#names + 1] = key end
    table.sort(names)
    for _, key in ipairs(names) do
        local saved = chars[key].stock
        local who = saved and saved.name or L("STOCK_THIS_CHAR", "This character")
        if saved and saved.nextExpire and saved.nextExpire <= now and (saved.mailAt or 0) < saved.nextExpire then
            lines[#lines + 1] = L("STOCK_REMIND_EXPIRED", "%s: auctions have expired; the items are waiting in the mailbox.", who)
        end
        if saved and saved.mailExpire and saved.mailExpire - now < Stock.MAIL_WARN_DAYS * 86400 then
            local days = math.max(0, math.floor((saved.mailExpire - now) / 86400))
            lines[#lines + 1] = saved.mailExpire <= now
                and L("STOCK_REMIND_MAIL_GONE", "%s: some Auction House mail may have run out.", who)
                or L("STOCK_REMIND_MAIL", "%s: Auction House mail runs out in %d days; collect it.", who, days)
        end
    end
    return lines
end
