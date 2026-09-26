-- Incoming purchases are reduced only after an observed buyer-mail collection
-- succeeds and its attachment reaches bags. Generic bag gains are not receipts.
local ADDON_NAME, GAM = ...
local function L(key, fallback, ...)
    local value = (GAM.L and GAM.L[key]) or fallback
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end
local Plan = GAM.CraftPlan
local receipts, installed = {}, false
local mailbox, observed, arrivals = false, nil, {}

function Plan.ConfirmDelivery(itemID, quantity)
    local incoming = Plan.GetData().incoming[itemID]
    quantity = tonumber(quantity)
    if not incoming or not quantity or quantity <= 0 or quantity % 1 ~= 0
        or quantity > incoming.quantity then return false end
    -- Explicit confirmation supersedes any pending observation for this item.
    -- Otherwise a delayed success can credit this delivery against a later buy.
    receipts[itemID] = nil
    arrivals[itemID] = nil
    incoming.quantity = incoming.quantity - quantity
    if incoming.quantity == 0 then Plan.GetData().incoming[itemID] = nil end
    Plan.Notify(L("WF_DELIVERY_CONFIRMED", "Delivery confirmed. Remaining materials now use your bags and banks."))
    return true
end

-- Compare buyer attachments across inbox updates. This also handles bulk mail
-- addons and success events without an item ID, without relying on post-hooks
-- still being able to read an attachment that has already disappeared.
local function ObserveInbox()
    if not mailbox or not (GetInboxNumItems and GetInboxInvoiceInfo and GetInboxItem) then return end
    local totals = {}
    for index = 1, GetInboxNumItems() do
        if GetInboxInvoiceInfo(index) == "buyer" then
            for slot = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
                local _, id, _, count = GetInboxItem(index, slot)
                if id and count and count > 0 and Plan.GetData().incoming[id] then
                    totals[id] = (totals[id] or 0) + count
                    arrivals[id] = arrivals[id] or {before = Plan.Count(id), removed = 0}
                end
            end
        end
    end
    for id, previous in pairs(observed or {}) do
        local receipt = arrivals[id]
        if receipt then receipt.removed = receipt.removed + math.max(0, previous - (totals[id] or 0)) end
    end
    observed = totals
end

local function ReconcileInbox()
    for id, receipt in pairs(arrivals) do
        local incoming = Plan.GetData().incoming[id]
        local count = incoming and math.min(incoming.quantity, receipt.removed,
            math.max(0, Plan.Count(id) - receipt.before)) or 0
        if count > 0 then
            local before, remaining = receipt.before + count, receipt.removed - count
            Plan.ConfirmDelivery(id, count)
            if Plan.GetData().incoming[id] then
                arrivals[id] = {before = before, removed = remaining}
            end
        end
    end
end

local function Collect(mailIndex, attachment)
    if observed then return end
    if not (GetInboxInvoiceInfo and GetInboxItem) or GetInboxInvoiceInfo(mailIndex) ~= "buyer" then return end
    for slot = attachment or 1, attachment or (ATTACHMENTS_MAX_RECEIVE or 16) do
        local _, itemID, _, quantity = GetInboxItem(mailIndex, slot)
        if itemID and quantity and quantity > 0 and Plan.GetData().incoming[itemID] then
            -- Only one ambiguous/in-flight attachment per item is tracked. A
            -- bulk collector can fall back to explicit confirmation in Shopping.
            if not receipts[itemID] then
                receipts[itemID] = {quantity = quantity, before = Plan.Count(itemID)}
            else
                receipts[itemID].ambiguous = true
            end
        end
    end
end

function Plan.OnMailEvent(event, itemID)
    if event == "MAIL_SHOW" then mailbox = true; observed = nil; arrivals = {}; ObserveInbox() end
    if event == "MAIL_INBOX_UPDATE" then ObserveInbox() end
    if event == "MAIL_INBOX_UPDATE" or event == "BAG_UPDATE_DELAYED" then ReconcileInbox() end
    if event == "MAIL_CLOSED" then mailbox = false; observed = nil; receipts = {}; return end
    if event == "MAIL_SUCCESS" and receipts[itemID] then receipts[itemID].success = true end
    if event == "MAIL_FAILED" then
        if itemID then receipts[itemID] = nil else receipts = {} end
    end
    for id, receipt in pairs(receipts) do
        if receipt.success and not receipt.ambiguous and Plan.Count(id) - receipt.before >= receipt.quantity then
            receipts[id] = nil
            local incoming = Plan.GetData().incoming[id]
            if incoming then Plan.ConfirmDelivery(id, math.min(incoming.quantity, receipt.quantity)) end
        end
    end
end

function Plan.InitMail()
    if installed then return end
    installed = true
    local frame = CreateFrame("Frame")
    for _, event in ipairs({"MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_SUCCESS", "MAIL_FAILED", "MAIL_CLOSED", "BAG_UPDATE_DELAYED"}) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent", function(_, event, itemID) Plan.OnMailEvent(event, itemID) end)
    if hooksecurefunc then
        if TakeInboxItem then hooksecurefunc("TakeInboxItem", Collect) end
        if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", function(index) Collect(index) end) end
    end
end

-- Track buyer mail from login, not from the first time the queue UI is built.
-- Otherwise purchases collected before opening GAM are never subtracted from
-- incoming and the queue counts them twice (bags + incoming).
if type(CreateFrame) == "function" then
    local login = CreateFrame("Frame")
    if login and login.RegisterEvent and login.SetScript then
        login:RegisterEvent("PLAYER_LOGIN")
        login:SetScript("OnEvent", function()
            if GAM.db then Plan.InitMail() end
        end)
    end
end
