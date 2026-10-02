-- GoldAdvisorMidnight/PostingMail.lua
-- Reads Auction House mail: counts returned items waiting in the mailbox for
-- the Posting tab and keeps a snapshot of the inbox. Sales and expiries are
-- recorded when the mail is collected (HistoryCapture), not when it is read.
-- Module: GAM.PostingMail

local ADDON_NAME, GAM = ...
local Mail = {}
GAM.PostingMail = Mail

Mail.inbox = {}   -- [index] = the last read of each Auction House mail

-- Turns a localized "Auction expired: %s" into a Lua pattern.
function Mail.SubjectPattern(format)
    if type(format) ~= "string" then return nil end
    local escaped = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    return "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end

-- Mail item names may carry color, texture or quality-icon codes.
function Mail.CleanName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|A.-|a", ""):gsub("|T.-|t", "")
    return (name:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function SubjectName(subject, format)
    local pattern = Mail.SubjectPattern(format)
    return pattern and type(subject) == "string" and Mail.CleanName(subject:match(pattern)) or nil
end

function Mail.ExpiredName(subject) return SubjectName(subject, AUCTION_EXPIRED_MAIL_SUBJECT) end
function Mail.CancelledName(subject) return SubjectName(subject, AUCTION_REMOVED_MAIL_SUBJECT) end

local function NameOf(itemID)
    return Mail.CleanName(C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
end

-- Items a sale mail can be for, by name (the mail names the item only):
-- everything the player posted, and every item a GAM strategy makes, so a
-- sale is recorded even when its post was missed.
function Mail.TrackedByName()
    local byName = {}
    local history = GAM.CraftHistory
    if not history then return byName end
    for _, event in ipairs(history.Events({ kind = "post" })) do
        local name = NameOf(event.itemID)
        if name then
            byName[name] = byName[name] or {}
            byName[name][event.itemID] = byName[name][event.itemID] or {}
            table.insert(byName[name][event.itemID], event)
        end
    end
    local outputs = GAM.Posting and GAM.Posting.OutputIndex and GAM.Posting.OutputIndex() or {}
    for itemID in pairs(outputs) do
        local name = NameOf(itemID)
        if name then
            byName[name] = byName[name] or {}
            byName[name][itemID] = byName[name][itemID] or {}
        end
    end
    return byName
end

-- Ranked items share a name: the one posted at the sale's unit price; with
-- no such post, the one whose recent price is closest to it.
function Mail.MatchSoldItem(candidates, count, bid)
    local unit = count and count > 0 and bid and bid / count or nil
    local ids = {}
    for itemID, posts in pairs(candidates or {}) do
        ids[#ids + 1] = itemID
        for _, post in ipairs(posts) do
            if unit and post.unitPrice and math.abs(post.unitPrice - unit) < 1 then return itemID end
        end
    end
    table.sort(ids)
    if #ids <= 1 or not unit then return ids[1] end
    local best, bestGap
    for _, itemID in ipairs(ids) do
        local posts = candidates[itemID]
        local recent = posts[#posts] and posts[#posts].unitPrice
        if not recent and GAM.Pricing and GAM.Pricing.GetUnitPrice then recent = GAM.Pricing.GetUnitPrice(itemID) end
        local gap = recent and math.abs(recent - unit) or math.huge
        if not best or gap < bestGap then best, bestGap = itemID, gap end
    end
    return best
end

function Mail.DepositPerUnit(posts)
    local last = posts and posts[#posts]
    return last and last.qty > 0 and (last.copper or 0) / last.qty or 0
end

function Mail.Scan()
    if not (GetInboxNumItems and GetInboxHeaderInfo) then return end
    local capture = GAM.HistoryCapture
    local inbox, returns, invoices, soonest = {}, {}, 0, nil
    local function Expires(daysLeft)
        daysLeft = tonumber(daysLeft)
        if daysLeft and (not soonest or daysLeft < soonest) then soonest = daysLeft end
    end
    for index = 1, GetInboxNumItems() or 0 do
        local _, _, _, subject, money, _, daysLeft, itemCount = GetInboxHeaderInfo(index)
        local invoiceType, itemName, _, bid, _, _, consignment, _, _, _, count
        if GetInboxInvoiceInfo then
            invoiceType, itemName, _, bid, _, _, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
        end
        local returned = Mail.ExpiredName(subject) or Mail.CancelledName(subject)
        if invoiceType == "buyer" and GetInboxItem then
            local items = {}
            for attach = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
                local _, itemID, _, qty = GetInboxItem(index, attach)
                if itemID and (qty or 0) > 0 then items[attach] = { itemID = itemID, qty = qty } end
            end
            inbox[index] = { subject = subject, money = money or 0, daysLeft = daysLeft, invoiceType = invoiceType,
                itemName = itemName, bid = bid, count = count, items = items }
        elseif invoiceType == "seller" then
            invoices = invoices + 1
            if (money or 0) > 0 then Expires(daysLeft) end
            inbox[index] = { subject = subject, money = money or 0, daysLeft = daysLeft, invoiceType = invoiceType,
                itemName = itemName, bid = bid, consignment = consignment, count = count }
        elseif returned and GetInboxItem and (itemCount == nil or itemCount > 0) then
            local items = {}
            for attach = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
                local _, itemID, _, qty = GetInboxItem(index, attach)
                if itemID and (qty or 0) > 0 then
                    items[attach] = { itemID = itemID, qty = qty }
                    if not capture or capture.IsOutput(itemID) then
                        returns[itemID] = (returns[itemID] or 0) + qty
                    end
                end
            end
            inbox[index] = { subject = subject, money = money or 0, daysLeft = daysLeft, items = items }
            if next(items) then Expires(daysLeft) end
        end
    end
    Mail.inbox = inbox
    -- The inbox updates many times a second while mail is open: log changes only.
    if invoices ~= Mail.lastInvoices and GAM.Log and GAM.Log.Debug then
        GAM.Log.Debug("Posting mail: %d sale invoices waiting", invoices)
    end
    Mail.lastInvoices = invoices
    local now = (GetServerTime and GetServerTime()) or (time and time()) or 0
    if GAM.Stock then GAM.Stock.SaveMail(returns, soonest and math.floor(now + soonest * 86400) or nil) end
    if GAM.Posting then GAM.Posting.Changed() end
end

function Mail.Init()
    if Mail.frame or not CreateFrame then return end
    local frame = CreateFrame("Frame")
    local function Scan()
        local ok, err = pcall(Mail.Scan)
        if not ok and GAM.Log and GAM.Log.Warn then GAM.Log.Warn("Posting mail scan failed: %s", tostring(err)) end
    end
    -- Inbox updates can be missed; opening and closing the mailbox read it
    -- too, and so does a moment after each collect.
    for _, event in ipairs({ "MAIL_INBOX_UPDATE", "MAIL_SHOW", "MAIL_CLOSED" }) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent", Scan)
    local function Soon() if C_Timer and C_Timer.After then C_Timer.After(1, Scan) end end
    for _, name in ipairs({ "TakeInboxMoney", "TakeInboxItem", "AutoLootMailItem" }) do
        if hooksecurefunc and type(_G[name]) == "function" then hooksecurefunc(name, Soon) end
    end
    Mail.frame = frame
end
