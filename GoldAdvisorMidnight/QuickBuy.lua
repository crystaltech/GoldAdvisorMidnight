-- GoldAdvisorMidnight/QuickBuy.lua
-- Hardware-safe commodity purchasing with an explicit quote state machine.
-- Module: GAM.QuickBuy

local ADDON_NAME, GAM = ...

local QuickBuy = {}
GAM.QuickBuy = QuickBuy

local MAX_PRICE_INCREASE = 0.05

local function L(key, fallback, ...)
    local value = (GAM.L and GAM.L[key]) or fallback or key
    if select("#", ...) > 0 then
        return string.format(value, ...)
    end
    return value
end

local function FirstEntry(list)
    return list and list.entries and list.entries[1] or nil
end

local function RemoveEntry(list, target)
    for index, entry in ipairs((list and list.entries) or {}) do
        if entry == target
            or (target.searchString and entry.searchString == target.searchString)
            or (not target.searchString and entry.itemID == target.itemID) then
            table.remove(list.entries, index)
            return true
        end
    end
    return false
end

function QuickBuy.CreateController(deps)
    deps = deps or {}
    local controller = {
        list = nil,
        deferredList = nil,
        state = {
            active = false,
            phase = "idle",
            pendingEntry = nil,
            pendingItemID = nil,
            pendingQty = nil,
            quoteUnitPrice = nil,
            quoteTotalPrice = nil,
            lastError = nil,
            attemptID = 0,
        },
    }

    local function Changed()
        if deps.onChanged then deps.onChanged(controller) end
    end

    local function ClearPending()
        local state = controller.state
        state.pendingEntry = nil
        state.pendingItemID = nil
        state.pendingQty = nil
        state.quoteUnitPrice = nil
        state.quoteTotalPrice = nil
    end

    local function CancelQuote()
        if deps.cancel then pcall(deps.cancel) end
    end

    local function Fail(message)
        CancelQuote()
        ClearPending()
        controller.state.phase = "idle"
        controller.state.lastError = message
        Changed()
        return false, message
    end

    local function ConfirmPending()
        local state = controller.state
        if not state.pendingItemID or not state.pendingQty then
            return Fail(L("QB_ERR_NO_QUOTE", "No commodity quote is ready."))
        end
        if deps.getQuoteRemaining and (tonumber(deps.getQuoteRemaining()) or 0) <= 0 then
            return Fail(L("QB_ERR_EXPIRED", "The quote expired. Click Buy Next to request a new one."))
        end
        local ok, err = pcall(deps.confirm, state.pendingItemID, state.pendingQty)
        if not ok then
            return Fail(L("QB_ERR_CONFIRM", "The Auction House could not confirm this purchase: %s", tostring(err)))
        end
        state.phase = "purchasing"
        state.lastError = nil
        Changed()
        return true
    end

    function controller:SetList(list)
        local phase = self.state.phase
        if phase == "quoting" or phase == "approval" or phase == "purchasing" then
            self.deferredList = list
        else
            self.list = list
            self.deferredList = nil
        end
        if FirstEntry(list) and self.state.phase == "complete" then
            self.state.phase = "idle"
        end
        Changed()
    end

    function controller:GetList()
        return self.list
    end

    function controller:Reset()
        if self.state.phase ~= "idle" and self.state.phase ~= "complete" then
            CancelQuote()
        end
        self.state.active = false
        self.state.phase = "idle"
        self.state.lastError = nil
        self.state.attemptID = self.state.attemptID + 1
        self.deferredList = nil
        ClearPending()
        Changed()
    end

    function controller:Click()
        local state = self.state
        if state.phase == "approval" then
            return ConfirmPending()
        end
        if state.phase == "quoting" or state.phase == "purchasing" then
            return false, L("QB_ERR_BUSY", "The current purchase is still being processed.")
        end

        local entry = FirstEntry(self.list)
        if not entry then
            state.active = false
            state.phase = "complete"
            state.lastError = nil
            Changed()
            return false, L("QB_ERR_EMPTY", "No items remain in the shopping list.")
        end

        local itemID = tonumber(entry.itemID)
        local quantity = math.floor(tonumber(entry.quantity) or 0)
        if not itemID or itemID <= 0 or quantity <= 0 then
            return Fail(L("QB_ERR_INVALID_ENTRY", "The next shopping-list entry has no valid commodity or quantity."))
        end

        state.active = true
        state.phase = "quoting"
        state.attemptID = state.attemptID + 1
        local attemptID = state.attemptID
        state.pendingEntry = entry
        state.pendingItemID = itemID
        state.pendingQty = quantity
        state.quoteUnitPrice = nil
        state.quoteTotalPrice = nil
        state.lastError = nil
        Changed()

        local ok, err = pcall(deps.start, itemID, quantity)
        if not ok then
            return Fail(L("QB_ERR_START", "The Auction House could not start this purchase: %s", tostring(err)))
        end
        if deps.after then
            deps.after(8, function()
                if state.phase == "quoting" and state.attemptID == attemptID then
                    Fail(L("QB_ERR_TIMEOUT", "The Auction House did not return a quote. Retry when it is ready."))
                end
            end)
        end
        return true
    end

    function controller:OnPriceUpdated(unitPrice, totalPrice)
        local state = self.state
        if state.phase ~= "quoting" or not state.pendingEntry then return false end
        unitPrice = tonumber(unitPrice)
        totalPrice = tonumber(totalPrice)
        if not unitPrice or unitPrice <= 0 or not totalPrice or totalPrice <= 0 then
            return Fail(L("QB_ERR_INVALID_QUOTE", "The Auction House returned an invalid commodity quote."))
        end

        state.quoteUnitPrice = unitPrice
        state.quoteTotalPrice = totalPrice

        local money = deps.getMoney and tonumber(deps.getMoney()) or nil
        if money and totalPrice > money then
            return Fail(L("QB_ERR_NO_GOLD", "You do not have enough gold for this purchase."))
        end

        local expected = tonumber(state.pendingEntry.unitPrice)
        if not expected or expected <= 0 or unitPrice > expected * (1 + MAX_PRICE_INCREASE) then
            state.phase = "approval"
            state.lastError = nil
            Changed()
            return true, "approval"
        end

        return ConfirmPending()
    end

    function controller:OnPriceUnavailable()
        if self.state.phase ~= "quoting" and self.state.phase ~= "approval" then return false end
        return Fail(L("QB_ERR_UNAVAILABLE", "The requested quantity is not currently available. Retry or skip this item."))
    end

    function controller:OnPurchaseFailed()
        if self.state.phase ~= "purchasing" then return false end
        return Fail(L("QB_ERR_PURCHASE_FAILED", "The purchase failed. The item was kept in the list so you can retry or skip it."))
    end

    function controller:OnPurchaseSucceeded()
        local state = self.state
        if state.phase ~= "purchasing" or not state.pendingEntry then return false end
        local purchasedEntry = state.pendingEntry
        local purchasedQty = state.pendingQty
        if deps.onPurchased then
            deps.onPurchased(purchasedEntry, purchasedQty, self.list)
        end
        RemoveEntry(self.list, purchasedEntry)
        if self.deferredList then
            self.list = self.deferredList
            self.deferredList = nil
        end
        ClearPending()
        state.lastError = nil
        if FirstEntry(self.list) then
            state.phase = "idle"
            state.active = true
        else
            state.phase = "complete"
            state.active = false
        end
        Changed()
        return true
    end

    function controller:Skip()
        if self.state.phase == "quoting" or self.state.phase == "approval" or self.state.phase == "purchasing" then
            CancelQuote()
            ClearPending()
        end
        local entries = self.list and self.list.entries
        if not entries or #entries == 0 then return false end
        if #entries > 1 then
            local skipped = table.remove(entries, 1)
            entries[#entries + 1] = skipped
        end
        self.state.phase = "idle"
        self.state.lastError = nil
        Changed()
        return true
    end

    return controller
end

local controller
local window
local refs = {}

local function FormatMoney(value)
    if value and GAM.Pricing and GAM.Pricing.FormatPrice then
        return GAM.Pricing.FormatPrice(value)
    end
    return value and tostring(value) or "—"
end

local function RefreshSignature(list)
    if not list then return end
    local parts = {}
    for _, entry in ipairs(list.entries or {}) do
        if entry.searchString then parts[#parts + 1] = entry.searchString end
    end
    table.sort(parts)
    list.signature = table.concat(parts, "\031")
end

local function RemoveAuctionatorEntry(entry, list)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and entry and entry.searchString and list and list.listName) then return end
    if type(api.DeleteShoppingListItem) == "function" then
        pcall(api.DeleteShoppingListItem, ADDON_NAME, list.listName, entry.searchString)
    end
end

local function CurrentEntry()
    if not controller then return nil end
    return controller.state.pendingEntry or FirstEntry(controller:GetList())
end

local function RefreshWindow()
    if not window then return end
    local state = controller.state
    local list = controller:GetList()
    local entries = (list and list.entries) or {}
    local entry = CurrentEntry()
    refs.progress:SetText(#entries == 1
        and L("QB_PROGRESS_ONE", "%d item remaining", #entries)
        or L("QB_PROGRESS_MANY", "%d items remaining", #entries))
    refs.item:SetText(entry
        and (entry.name or L("QB_ITEM_FALLBACK", "Item %s", tostring(entry.itemID)))
        or L("QB_LIST_COMPLETE", "Shopping list complete"))
    refs.quantity:SetText(entry
        and L("QB_QUANTITY", "Quantity: %d", math.floor(tonumber(entry.quantity) or 0)) or "")
    refs.expected:SetText(entry
        and L("QB_EXPECTED_PRICE", "Expected unit price: %s", FormatMoney(entry.unitPrice)) or "")
    refs.quote:SetText(state.quoteTotalPrice
        and L("QB_LIVE_QUOTE", "Live quote: %s total (%s each)",
            FormatMoney(state.quoteTotalPrice), FormatMoney(state.quoteUnitPrice))
        or "")

    local status
    local buttonText = L("QB_BUY_NEXT", "Buy Next")
    local enabled = true
    if state.phase == "quoting" then
        status = L("QB_STATUS_QUOTING", "Waiting for the live Auction House quote…")
        buttonText = L("QB_CHECKING_PRICE", "Checking Price…")
        enabled = false
    elseif state.phase == "approval" then
        status = L("QB_STATUS_APPROVAL", "The live unit price is more than 5% above the estimate. Review it before buying.")
        buttonText = L("QB_ACCEPT_HIGHER", "Accept Higher Price")
    elseif state.phase == "purchasing" then
        status = L("QB_STATUS_PURCHASING", "Purchase submitted. Waiting for the Auction House…")
        buttonText = L("QB_PURCHASING", "Purchasing…")
        enabled = false
    elseif state.phase == "complete" then
        status = L("QB_STATUS_COMPLETE", "All shopping-list items have been purchased.")
        buttonText = L("QB_COMPLETE", "Complete")
        enabled = false
    elseif state.lastError then
        status = state.lastError
        buttonText = L("QB_RETRY", "Retry")
    else
        status = L("QB_STATUS_IDLE", "Buy one commodity at a time using a current price quote.")
    end
    refs.status:SetText(status)
    refs.buy:SetText(buttonText)
    refs.buy:SetEnabled(enabled and entry ~= nil)
    refs.buy:SetAlpha((enabled and entry ~= nil) and 1 or 0.5)
    refs.skip:SetEnabled(#entries > 0)
    refs.skip:SetAlpha(#entries > 0 and 1 or 0.5)
end

local function BuildWindow()
    if window then return end
    window = CreateFrame("Frame", "GAMQuickBuyWindow", UIParent, "BackdropTemplate")
    window:SetSize(430, 238)
    window:SetPoint("CENTER", UIParent, "CENTER", 180, 40)
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    window:SetBackdropColor(0.035, 0.035, 0.035, 0.98)
    window:SetBackdropBorderColor(1, 0.82, 0, 0.9)
    window:Hide()

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", window, "TOP", 0, -14)
    title:SetText(L("BTN_QUICK_BUY_SHORT", "Quick Buy"))
    title:SetTextColor(1, 0.82, 0)

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        controller:Reset()
        window:Hide()
    end)

    refs.progress = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    refs.progress:SetPoint("TOPLEFT", window, "TOPLEFT", 20, -47)
    refs.progress:SetTextColor(0.7, 0.7, 0.7)

    refs.item = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    refs.item:SetPoint("TOPLEFT", refs.progress, "BOTTOMLEFT", 0, -12)
    refs.item:SetPoint("RIGHT", window, "RIGHT", -20, 0)
    refs.item:SetJustifyH("LEFT")
    refs.item:SetTextColor(1, 0.82, 0)

    refs.quantity = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    refs.quantity:SetPoint("TOPLEFT", refs.item, "BOTTOMLEFT", 0, -9)
    refs.expected = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    refs.expected:SetPoint("TOPLEFT", refs.quantity, "BOTTOMLEFT", 0, -6)
    refs.quote = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    refs.quote:SetPoint("TOPLEFT", refs.expected, "BOTTOMLEFT", 0, -5)

    refs.status = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    refs.status:SetPoint("TOPLEFT", refs.quote, "BOTTOMLEFT", 0, -11)
    refs.status:SetPoint("RIGHT", window, "RIGHT", -20, 0)
    refs.status:SetJustifyH("LEFT")
    refs.status:SetWordWrap(true)
    refs.status:SetTextColor(0.9, 0.9, 0.9)

    refs.buy = CreateFrame("Button", "GAMQuickBuyBtn", window, "UIPanelButtonTemplate")
    refs.buy:SetSize(180, 26)
    refs.buy:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 20, 18)
    refs.buy:SetScript("OnClick", function() controller:Click() end)

    refs.skip = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    refs.skip:SetSize(94, 26)
    refs.skip:SetPoint("LEFT", refs.buy, "RIGHT", 8, 0)
    refs.skip:SetText(L("QB_SKIP", "Skip"))
    refs.skip:SetScript("OnClick", function() controller:Skip() end)

    local stop = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    stop:SetSize(94, 26)
    stop:SetPoint("LEFT", refs.skip, "RIGHT", 8, 0)
    stop:SetText(L("QB_STOP", "Stop"))
    stop:SetScript("OnClick", function() controller:Reset() end)

    RefreshWindow()
end

function QuickBuy.Init()
    if controller then return end
    controller = QuickBuy.CreateController({
        start = function(itemID, quantity)
            if not GAM.ahOpen then error(L("ERR_NO_AH", "Open the Auction House first.")) end
            C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)
        end,
        confirm = function(itemID, quantity)
            C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, quantity)
        end,
        cancel = function()
            if C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
                C_AuctionHouse.CancelCommoditiesPurchase()
            end
        end,
        getQuoteRemaining = function()
            return C_AuctionHouse.GetQuoteDurationRemaining()
        end,
        getMoney = GetMoney,
        after = function(delay, callback)
            C_Timer.After(delay, callback)
        end,
        onPurchased = function(entry, _, list)
            RemoveAuctionatorEntry(entry, list)
        end,
        onChanged = function(activeController)
            GAM.quickBuyState = activeController.state
            GAM.quickBuyList = activeController:GetList()
            RefreshSignature(GAM.quickBuyList)
            RefreshWindow()
        end,
    })
    controller:SetList(GAM.quickBuyList)
    GAM.quickBuyState = controller.state
    BuildWindow()
end

function QuickBuy.SetList(list)
    GAM.quickBuyList = list
    if controller then controller:SetList(list) end
end

function QuickBuy.Show()
    QuickBuy.Init()
    window:Show()
    window:Raise()
    RefreshWindow()
end

function QuickBuy.Toggle()
    QuickBuy.Init()
    if window:IsShown() then
        window:Hide()
    else
        QuickBuy.Show()
    end
end

function QuickBuy.Reset()
    if controller then controller:Reset() end
end

function QuickBuy.OnPriceUpdated(unitPrice, totalPrice)
    if controller then controller:OnPriceUpdated(unitPrice, totalPrice) end
end

function QuickBuy.OnPriceUnavailable()
    if controller then controller:OnPriceUnavailable() end
end

function QuickBuy.OnPurchaseSucceeded()
    if controller then controller:OnPurchaseSucceeded() end
end

function QuickBuy.OnPurchaseFailed()
    if controller then controller:OnPurchaseFailed() end
end

function QuickBuy.GetController()
    return controller
end
