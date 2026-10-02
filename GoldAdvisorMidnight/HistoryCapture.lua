-- GoldAdvisorMidnight/HistoryCapture.lua
-- Records posts, cancels, purchases and collected Auction House mail into
-- the crafting history, whichever addon or window the player uses.
-- Blizzard's own functions are hooked (hooksecurefunc runs after them and
-- cannot change them), so nothing has to be guessed afterwards from auction
-- lists or inbox reads.
-- Module: GAM.HistoryCapture

local ADDON_NAME, GAM = ...
local Capture = {}
GAM.HistoryCapture = Capture

local CONFIRM_SECONDS = 10   -- a post, cancel or purchase not confirmed by then failed
local UNDO_SECONDS = 2       -- an error this soon after a collect or vendor buy means it failed
local REPEAT_SECONDS = 60    -- safety expiry for the double-click guard below
local MAIL_DAYS = 30
local LEGACY_DAYS = 31
local HOURS = { [1] = 12, [2] = 24, [3] = 48 }

local state = { quote = nil, buying = nil, recorded = {}, collected = {} }
Capture.state = state

local function Clock() return GetTime and GetTime() or 0 end
local function Now() return (GetServerTime and GetServerTime()) or (time and time()) or 0 end
local function History() return GAM.CraftHistory end
local function Debug(...)
    if GAM.Log and GAM.Log.Debug then GAM.Log.Debug(...) end
end

-- ===== What is recorded =====

-- Items a GAM strategy makes, queue outputs and anything posted before.
local trackedCache, trackedAt
function Capture.IsOutput(itemID)
    local posting = GAM.Posting
    if not (itemID and posting) then return false end
    if posting.OutputIndex and posting.OutputIndex()[itemID] then return true end
    if not trackedCache or Clock() - trackedAt > 5 then
        trackedCache = posting.TrackedItems and posting.TrackedItems() or {}
        trackedAt = Clock()
    end
    return trackedCache[itemID] ~= nil
end

-- Materials: anything the queue is short of (with each plan's need, so the
-- purchase counts toward those plans) or any strategy reagent.
function Capture.MaterialNeeds(itemID)
    local plan = GAM.CraftPlan
    if itemID and plan and plan.Project then
        local ok, projection = pcall(plan.Project)
        for _, entry in ipairs(ok and type(projection) == "table" and projection.buys or {}) do
            if entry.itemID == itemID then return true, entry.plans end
        end
    end
    local posting = GAM.Posting
    return (itemID and posting and posting.ReagentIndex and posting.ReagentIndex()[itemID]) and true or false, nil
end

-- A record that a following error message can still undo (only what this
-- call added: the line may have merged with an earlier one).
local function Remember(event, added)
    if event then state.recorded[#state.recorded + 1] = { event = event, added = added, at = Clock() } end
    return event
end

-- The oldest waiting entry that is still recent enough to be confirmed.
local function Pop(list)
    local now = Clock()
    while list[1] and now - list[1].at > CONFIRM_SECONDS do table.remove(list, 1) end
    return table.remove(list, 1)
end

-- ===== Posts =====

local function ItemAt(location)
    if not (location and C_Item and C_Item.GetItemID) then return nil end
    local ok, itemID = pcall(C_Item.GetItemID, location)
    return ok and itemID or nil
end

local function Deposit(location, itemID, durationEnum, qty, isItem)
    local api = C_AuctionHouse
    local calculate = api and (isItem and api.CalculateItemDeposit or api.CalculateCommodityDeposit)
    if not calculate then return 0 end
    local ok, value = pcall(calculate, isItem and location or itemID, durationEnum, qty)
    return ok and tonumber(value) or 0
end

-- Posts and cancels wait here (saved: a /reload keeps them) until they are
-- settled. A confirmation settles one when it cannot be mistaken (only one
-- is waiting); otherwise, and when confirmations are lost, late or doubled,
-- the auction list settles them: a new auction matches its waiting post by
-- item, quantity and price, and a waiting cancel is recorded once its
-- auction is gone (unless it sold).
local PAIR_SECONDS = 60        -- a confirmation this late can still settle the only waiting one
local KEEP_SECONDS = 2 * 86400 -- waiting ones are kept until the next visits can settle them
local QUICK_SALE_SECONDS = 900 -- a post never seen in the list after this sold at once

local function Waiting(kind)
    local store = History() and History().Store()
    if not store then return {} end
    store.waiting = store.waiting or {}
    local list, now, kept = store.waiting[kind] or {}, Now(), {}
    for _, entry in ipairs(list) do
        if now - (entry.t or 0) < KEEP_SECONDS and not (entry.skip and now - entry.t > PAIR_SECONDS) then
            kept[#kept + 1] = entry
        end
    end
    store.waiting[kind] = kept
    return kept
end
Capture.Waiting = Waiting

local function Remove(list, entry)
    for index, other in ipairs(list) do if other == entry then table.remove(list, index); return end end
end

-- The only entry waiting recently, or nil when there are none or several.
local function OnlyRecent(list)
    local found, now = nil, Now()
    for _, entry in ipairs(list) do
        if now - entry.t <= PAIR_SECONDS then
            if found then return nil end
            found = entry
        end
    end
    return found
end

local function PostRecorded(auctionID)
    if not auctionID then return false end
    local events = History().Events({ kind = "post", since = Now() - 3 * 86400 })
    for index = #events, 1, -1 do if events[index].auctionID == auctionID then return true end end
    return false
end

local function RecordPost(post, auctionID)
    if auctionID and PostRecorded(auctionID) then return end
    History().Record("post", { itemID = post.itemID, qty = post.qty, copper = post.deposit,
        unitPrice = post.unitPrice, duration = post.duration, othersAtPrice = post.othersAtPrice,
        postedLocal = post.postedLocal, auctionID = auctionID, source = post.source, t = post.t })
end

local function OnPostCall(isItem, location, durationEnum, qty, price, buyout)
    local itemID = ItemAt(location)
    qty = tonumber(qty)
    local unit = tonumber(isItem and buyout or price)
    local list = Waiting("posts")
    -- Untracked posts wait too, so a confirmation is never paired with the wrong one.
    if not (itemID and qty and qty > 0 and unit and Capture.IsOutput(itemID)) then
        list[#list + 1] = { skip = true, t = Now() }
        return
    end
    local posting, model = GAM.Posting, GAM.PostingModel
    local own = posting and posting.session.pending
    local _, _, prices
    if posting and posting.Listing then _, _, prices = posting.Listing(itemID) end
    list[#list + 1] = {
        itemID = itemID, qty = qty, unitPrice = unit, duration = HOURS[durationEnum], t = Now(),
        postedLocal = time and time() or nil,
        deposit = Deposit(location, itemID, durationEnum, qty, isItem),
        othersAtPrice = prices and model and model.OthersAtPrice(prices, unit) or nil,
        source = not (own and own.kind == "post" and own.itemID == itemID) and "other" or nil,
    }
end

function Capture.OnAuctionCreated(auctionID)
    local list = Waiting("posts")
    local post = OnlyRecent(list)
    Debug("History post confirmed: auctionID=%s item=%s", tostring(auctionID), tostring(post and post.itemID))
    if not History() or (auctionID and PostRecorded(auctionID)) then return end
    if post then
        Remove(list, post)
        if not post.skip then RecordPost(post, auctionID) end
    end
    -- Otherwise the next auction-list read settles it.
end

local function FindOwned(auctionID)
    local posting = GAM.Posting
    for _, auction in ipairs(posting and posting.session.auctions or {}) do
        if auction.auctionID == auctionID then return auction.itemID, auction.qty, auction.deposit end
    end
    local api = C_AuctionHouse
    for index = 1, api and api.GetNumOwnedAuctions and api.GetNumOwnedAuctions() or 0 do
        local ok, info = pcall(api.GetOwnedAuctionInfo, index)
        if ok and info and info.auctionID == auctionID and info.status == 0 then
            return info.itemKey and info.itemKey.itemID, info.quantity
        end
    end
end

local function LastPostDuration(itemID)
    local events = History() and History().Events({ kind = "post", itemID = itemID }) or {}
    return events[#events] and events[#events].duration or nil
end

local function OnCancelCall(auctionID)
    local list = Waiting("cancels")
    local itemID, qty, deposit = FindOwned(auctionID)
    if not (itemID and qty and Capture.IsOutput(itemID)) then
        list[#list + 1] = { skip = true, t = Now() }
        return
    end
    local posting = GAM.Posting
    if not deposit and posting and posting.Deposit then
        deposit = posting.Deposit(itemID, qty, LastPostDuration(itemID) or posting.Options().duration)
    end
    local api = C_AuctionHouse
    local ok, cost = false, nil
    if api and api.GetCancelCost then ok, cost = pcall(api.GetCancelCost, auctionID) end
    Debug("History cancel sent: auctionID=%s deposit=%s cancelCost=%s", tostring(auctionID), tostring(deposit),
        tostring(ok and cost or nil))
    list[#list + 1] = { auctionID = auctionID, itemID = itemID, qty = qty, deposit = deposit or 0, t = Now() }
end

function Capture.OnAuctionCancelled()
    local list = Waiting("cancels")
    -- The game also fires this for auctions GAM did not cancel: nothing to do.
    if #list == 0 then return end
    local target = OnlyRecent(list)
    Debug("History cancel confirmed: auctionID=%s", tostring(target and target.auctionID))
    if not target then return end   -- several waiting: the auction list settles them
    Remove(list, target)
    if not target.skip and GAM.Posting and GAM.Posting.RecordCancel then GAM.Posting.RecordCancel(target) end
end

-- Called after every complete read of the player's auctions.
-- active: { {auctionID, itemID, qty, price} } still listed; sold: {[auctionID]=units sold}.
function Capture.Settle(active, sold)
    if not History() then return end
    local listed = {}
    for _, auction in ipairs(active or {}) do listed[auction.auctionID] = auction end
    -- New auctions: match the oldest waiting post of the same item, quantity and price.
    local posts, now = Waiting("posts"), Now()
    for _, auction in ipairs(active or {}) do
        if not PostRecorded(auction.auctionID) then
            for _, post in ipairs(posts) do
                if not post.skip and post.itemID == auction.itemID and post.qty == auction.qty
                        and post.unitPrice == auction.price then
                    RecordPost(post, auction.auctionID)
                    Remove(posts, post)
                    break
                end
            end
        end
    end
    -- Posts never seen in the list: they sold (or were cancelled) at once.
    for index = #posts, 1, -1 do
        local post = posts[index]
        if not post.skip and now - post.t > QUICK_SALE_SECONDS then
            RecordPost(post, nil)
            table.remove(posts, index)
        end
    end
    -- Waiting cancels whose auction is gone were cancelled, less any part of
    -- it that sold first (a commodity auction sells in parts); one whose
    -- auction is still listed a minute later failed.
    local cancels = Waiting("cancels")
    for index = #cancels, 1, -1 do
        local cancel = cancels[index]
        if not cancel.skip and listed[cancel.auctionID] and now - cancel.t > PAIR_SECONDS then
            table.remove(cancels, index)
        elseif not cancel.skip and not listed[cancel.auctionID] and now - cancel.t >= 2 then
            table.remove(cancels, index)
            local left = cancel.qty - (sold and tonumber(sold[cancel.auctionID]) or 0)
            if left > 0 and GAM.Posting and GAM.Posting.RecordCancel then
                if left < cancel.qty then
                    cancel.deposit = math.floor((cancel.deposit or 0) * left / cancel.qty)
                    cancel.qty = left
                end
                GAM.Posting.RecordCancel(cancel)
            end
        end
    end
end

-- ===== Purchases =====

local function OnStartPurchase(itemID, qty)
    state.quote = { itemID = tonumber(itemID), qty = tonumber(qty) }
end

function Capture.OnPriceUpdated(_, totalPrice)
    if state.quote then state.quote.total = tonumber(totalPrice) end
end

local function OnConfirmPurchase(itemID, qty)
    local quote = state.quote
    itemID, qty = tonumber(itemID), tonumber(qty)
    if not (quote and quote.itemID == itemID and quote.total and qty and qty > 0) then return end
    -- Quick Buy notes its own purchases, with the plans it bought for.
    if GAM.quickBuyConfirming then state.buying = nil; return end
    local material, needs = Capture.MaterialNeeds(itemID)
    if not material then state.buying = nil; return end
    local total = quote.qty == qty and quote.total or math.floor(quote.total * qty / math.max(1, quote.qty or qty))
    state.buying = { itemID = itemID, qty = qty, total = total, needs = needs, at = Clock() }
end

function Capture.OnPurchaseResult(succeeded)
    local buying = state.buying
    state.buying, state.quote = nil, nil
    if not (succeeded and buying and History()) or Clock() - buying.at > CONFIRM_SECONDS * 3 then return end
    Capture.ExpectPurchase(buying.itemID, buying.qty, buying.total, buying.needs)
end

-- Auction House purchases are recorded when their "Auction won" mail is
-- collected, at the price on the invoice: the price event does not say
-- which item it is for, and a late one can belong to an earlier quote.
-- Until then the purchase waits here (saved, so a /reload keeps it) with
-- the plans it was bought for.
local PENDING_DAYS = 7
local function PendingBuys()
    local store = History() and History().Store()
    if not store then return {} end
    store.pendingBuys = store.pendingBuys or {}
    local now, kept = Now(), {}
    for _, buy in ipairs(store.pendingBuys) do
        if now - (buy.t or 0) < PENDING_DAYS * 86400 and (buy.left or 0) > 0 then kept[#kept + 1] = buy end
    end
    store.pendingBuys = kept
    return kept
end
Capture.PendingBuys = PendingBuys

function Capture.ExpectPurchase(itemID, qty, total, plans)
    itemID, qty = tonumber(itemID), math.floor(tonumber(qty) or 0)
    if not (itemID and qty > 0) then return end
    local list = PendingBuys()
    local copy
    if type(plans) == "table" then
        copy = {}
        for planID, need in pairs(plans) do copy[planID] = need end
    end
    list[#list + 1] = { itemID = itemID, qty = qty, left = qty, quote = tonumber(total), plans = copy, t = Now() }
end

local function OnBuyMerchant(index, quantity)
    if GAM.quickBuyVendoring or not (GetMerchantItemID and History()) then return end
    local itemID = GetMerchantItemID(index)
    local material, needs = Capture.MaterialNeeds(itemID)
    local offer = material and GAM.VendorPrices and GAM.VendorPrices.GetMerchantOffer(itemID)
    if not (offer and offer.unitPrice > 0) then return end
    local units = tonumber(quantity) or offer.bundle
    Remember(History().RecordPurchase(itemID, units, math.floor(offer.unitPrice * units + 0.5), "vendor", needs))
end

-- ===== Collected mail =====

-- Mail read now, or as it was on the last inbox read if the client has
-- already cleared the part being collected.
local function ReadMail(index)
    local _, _, _, subject, money, _, daysLeft = GetInboxHeaderInfo(index)
    local mail = { subject = subject, money = money or 0, daysLeft = daysLeft, items = {} }
    if GetInboxInvoiceInfo then
        local invoiceType, itemName, _, bid, _, _, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
        mail.invoiceType, mail.itemName, mail.bid, mail.consignment, mail.count =
            invoiceType, itemName, bid, consignment, count
    end
    for attach = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local _, itemID, _, qty = GetInboxItem(index, attach)
        if itemID then mail.items[attach] = { itemID = itemID, qty = qty } end
    end
    local seen = GAM.PostingMail and GAM.PostingMail.inbox and GAM.PostingMail.inbox[index]
    if seen and seen.subject == subject then
        if mail.money <= 0 then mail.money = seen.money or 0 end
        if not mail.invoiceType then
            mail.invoiceType, mail.itemName, mail.bid, mail.consignment, mail.count =
                seen.invoiceType, seen.itemName, seen.bid, seen.consignment, seen.count
        end
        for attach, item in pairs(seen.items or {}) do mail.items[attach] = mail.items[attach] or item end
    end
    return mail
end

local function FirstCollect(key)
    local now = Clock()
    for old, at in pairs(state.collected) do
        if now - at > REPEAT_SECONDS then state.collected[old] = nil end
    end
    if state.collected[key] then return false end
    state.collected[key] = now
    return true
end

-- Guards against a second click before the server answers. It is cleared on
-- every inbox update, so identical mails collected one after another still
-- count separately.
local function CollectKey(index, mail, part)
    return table.concat({ index, tostring(mail.subject), string.format("%.4f", mail.daysLeft or 0), tostring(part) }, "|")
end

-- When the mail arrived; the Auction House sends it at the sale or expiry.
local function Arrival(daysLeft)
    return Now() - math.floor((MAIL_DAYS - (tonumber(daysLeft) or MAIL_DAYS)) * 86400)
end

-- Mail that arrived before this recording existed may already be in the
-- history (older versions recorded it when the inbox was read).
local function AlreadyRecorded(kind, itemID, qty, copper, arrival)
    local store = History() and History().Store()
    local legacy = store and store.mailLegacy
    if not (legacy and store.captureSince) then return false end
    if Now() - store.captureSince > LEGACY_DAYS * 86400 then store.mailLegacy = nil; return false end
    if arrival >= store.captureSince then return false end
    local key = table.concat({ kind, itemID, qty, copper or "" }, ":")
    local count = legacy[key] or 0
    if count <= 0 then return false end
    legacy[key] = count > 1 and count - 1 or nil
    return true
end

local function CollectSale(index)
    local mail = ReadMail(index)
    if mail.invoiceType ~= "seller" or (mail.money or 0) <= 0 or (mail.count or 0) <= 0 then return end
    if not FirstCollect(CollectKey(index, mail, "money")) then return end
    local names = GAM.PostingMail
    local candidates = names.TrackedByName()[names.CleanName(mail.itemName)]
    local itemID = candidates and names.MatchSoldItem(candidates, mail.count, mail.bid)
    Debug("History sale collected: %s x%s item=%s", tostring(mail.itemName), tostring(mail.count), tostring(itemID))
    if not itemID then return end
    local net, arrival = math.max(0, (mail.bid or 0) - (mail.consignment or 0)), Arrival(mail.daysLeft)
    if AlreadyRecorded("sold", itemID, mail.count, net, arrival) then return end
    Remember(History().Record("sold", { itemID = itemID, qty = mail.count, copper = net,
        source = "mail", t = arrival }))
end

local function CollectReturned(index, attach)
    local mail = ReadMail(index)
    local names = GAM.PostingMail
    if not (mail.subject and names.ExpiredName(mail.subject)) then return end
    local item = mail.items[attach]
    if not (item and (item.qty or 0) > 0 and Capture.IsOutput(item.itemID)) then return end
    if not FirstCollect(CollectKey(index, mail, attach)) then return end
    local arrival = Arrival(mail.daysLeft)
    if AlreadyRecorded("expired", item.itemID, item.qty, nil, arrival) then return end
    local posts = History().Events({ kind = "post", itemID = item.itemID })
    Remember(History().Record("expired", { itemID = item.itemID, qty = item.qty, source = "mail", t = arrival,
        copper = math.floor(names.DepositPerUnit(posts) * item.qty) }))
end

-- An "Auction won" mail: the purchase, at the invoice price, for the plans
-- it was bought for (or, with no record of it, what the queue needs now).
local function CollectBought(index, attach)
    local mail = ReadMail(index)
    if mail.invoiceType ~= "buyer" then return end
    local item = mail.items[attach]
    if not (item and (item.qty or 0) > 0) then return end
    if not FirstCollect(CollectKey(index, mail, "buy" .. attach)) then return end
    local count = math.max(item.qty, tonumber(mail.count) or item.qty)
    local copper = math.floor((tonumber(mail.bid) or 0) * item.qty / count + 0.5)
    -- Match the oldest expected purchase of this item.
    local plans, matched
    for _, buy in ipairs(PendingBuys()) do
        if buy.itemID == item.itemID and buy.left > 0 then
            matched = buy
            if buy.plans then
                plans = History().Allocate(math.min(item.qty, buy.left), buy.plans)
                for planID, share in pairs(plans or {}) do
                    buy.plans[planID] = math.max(0, (buy.plans[planID] or 0) - share)
                end
            end
            buy.left = buy.left - item.qty
            break
        end
    end
    if not matched then
        local material, needs = Capture.MaterialNeeds(item.itemID)
        if not material then return end
        plans = History().Allocate(item.qty, needs)
    end
    Debug("History purchase collected: %s x%d for %d (%s)", tostring(mail.itemName), item.qty, copper,
        matched and "matched" or "no record")
    local event, added = History().Record("buy", { itemID = item.itemID, qty = item.qty, copper = copper,
        source = "auction", plans = plans })
    Remember(event, added)
end

local function OnTakeMoney(index) pcall(CollectSale, index) end
local function OnTakeItem(index, attach)
    pcall(CollectReturned, index, attach)
    pcall(CollectBought, index, attach)
end
local function OnAutoLoot(index)
    pcall(CollectSale, index)
    for attach = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        pcall(CollectReturned, index, attach)
        pcall(CollectBought, index, attach)
    end
end

-- ===== Failures =====

-- Collects and vendor buys the game refused: error message -> the kinds of
-- record it can refuse. Only the latest such record is undone; mail collected
-- just before it (auto-open collects quickly) went through.
local FAILURE_KINDS = {}
local function Fails(name, kinds)
    if type(_G[name]) == "string" then FAILURE_KINDS[_G[name]] = kinds end
end
Fails("ERR_INV_FULL", { expired = true, buy = true })
Fails("ERR_BAG_FULL", { expired = true, buy = true })
Fails("ERR_ITEM_MAX_COUNT", { expired = true, buy = true })
Fails("ERR_NOT_ENOUGH_MONEY", { buy = true })
Fails("ERR_TOO_MUCH_GOLD", { sold = true })
Fails("ERR_MAIL_DATABASE_ERROR", { sold = true, expired = true })
Capture.FAILURE_KINDS = FAILURE_KINDS

function Capture.OnError(message)
    local now, recent = Clock(), {}
    for _, entry in ipairs(state.recorded) do
        if now - entry.at <= UNDO_SECONDS then recent[#recent + 1] = entry end
    end
    state.recorded = recent
    local kinds = FAILURE_KINDS[message]
    if not kinds then return end
    for index = #recent, 1, -1 do
        local event = recent[index].event
        if kinds[event.kind] then
            History().Unrecord(event, recent[index].added)
            table.remove(recent, index)
            Debug("History: %s of %s undone after '%s'", event.kind, tostring(event.itemID), tostring(message))
            return
        end
    end
end

-- ===== Setup =====

function Capture.OnEvent(event, ...)
    if event == "AUCTION_HOUSE_AUCTION_CREATED" then Capture.OnAuctionCreated(...)
    elseif event == "AUCTION_HOUSE_POST_WARNING" or event == "AUCTION_HOUSE_POST_ERROR" then
        -- The latest post did not go through (a warning post is sent again on confirm).
        table.remove(Waiting("posts"))
    elseif event == "AUCTION_CANCELED" then Capture.OnAuctionCancelled()
    elseif event == "COMMODITY_PRICE_UPDATED" then Capture.OnPriceUpdated(...)
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then Capture.OnPurchaseResult(true)
    elseif event == "COMMODITY_PURCHASE_FAILED" then Capture.OnPurchaseResult(false)
    elseif event == "UI_ERROR_MESSAGE" then Capture.OnError(select(2, ...))
    elseif event == "MAIL_INBOX_UPDATE" then state.collected = {}
    elseif event == "AUCTION_HOUSE_CLOSED" then
        state.quote, state.buying = nil, nil
    end
end

local function Hook(owner, name, handler)
    if type(owner) == "table" and type(owner[name]) == "function" then
        hooksecurefunc(owner, name, handler)
    elseif owner == nil and type(_G[name]) == "function" then
        hooksecurefunc(name, handler)
    end
end

function Capture.Init()
    if Capture.frame or not (CreateFrame and hooksecurefunc) then return end
    local api = C_AuctionHouse
    Hook(api, "PostCommodity", function(...) OnPostCall(false, ...) end)
    Hook(api, "ConfirmPostCommodity", function(...) OnPostCall(false, ...) end)
    Hook(api, "PostItem", function(...) OnPostCall(true, ...) end)
    Hook(api, "ConfirmPostItem", function(...) OnPostCall(true, ...) end)
    Hook(api, "CancelAuction", OnCancelCall)
    Hook(api, "StartCommoditiesPurchase", OnStartPurchase)
    Hook(api, "ConfirmCommoditiesPurchase", OnConfirmPurchase)
    Hook(nil, "BuyMerchantItem", OnBuyMerchant)
    Hook(nil, "TakeInboxMoney", OnTakeMoney)
    Hook(nil, "TakeInboxItem", OnTakeItem)
    Hook(nil, "AutoLootMailItem", OnAutoLoot)
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_POST_WARNING", "AUCTION_HOUSE_POST_ERROR",
            "AUCTION_CANCELED", "COMMODITY_PRICE_UPDATED", "COMMODITY_PURCHASE_SUCCEEDED",
            "COMMODITY_PURCHASE_FAILED", "UI_ERROR_MESSAGE", "MAIL_INBOX_UPDATE", "AUCTION_HOUSE_CLOSED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        local ok, err = pcall(Capture.OnEvent, event, ...)
        if not ok and GAM.Log and GAM.Log.Warn then GAM.Log.Warn("History capture failed: %s", tostring(err)) end
    end)
    Capture.frame = frame
end
