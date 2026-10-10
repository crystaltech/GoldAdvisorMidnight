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

-- Seconds to wait for a purchase confirmation before moving on.
local PURCHASE_TIMEOUT = 30

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

local function ApplyPurchasedQuantity(list, itemID, quantity)
    -- Refreshed search strings can include a different quantity. Match the
    -- exact item ID and subtract the receipt once, across both source lists.
    for _, entries in ipairs({ list.entries or {}, list.vendorEntries or {} }) do
        local index = 1
        while index <= #entries and quantity > 0 do
            local entry = entries[index]
            if entry.itemID == itemID then
                local used = math.min(quantity, math.max(0, tonumber(entry.quantity) or 0))
                entry.quantity = entry.quantity - used
                quantity = quantity - used
                if entry.quantity <= 0 then table.remove(entries, index) else index = index + 1 end
            else
                index = index + 1
            end
        end
    end
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

    local function RouteVendor(entry, quotedTotal)
        if not (entry and GAM.VendorPrices and GAM.VendorPrices.ResolvePurchase) then return false end
        local source, price, basis = GAM.VendorPrices.ResolvePurchase(entry.itemID, entry.quantity, quotedTotal)
        if source ~= "vendor" then return false end
        CancelQuote()
        local list = controller.list
        list.vendorEntries = list.vendorEntries or {}
        entry.unitPrice, entry.vendorPriceBasis = price, basis
        list.vendorEntries[#list.vendorEntries + 1] = entry
        RemoveEntry(list, entry)
        if deps.onVendor then deps.onVendor(entry, list) end
        ClearPending()
        controller.state.phase = "idle"
        controller.state.lastError = nil
        Changed()
        return true
    end

    local function ConfirmPending()
        local state = controller.state
        if controller.list and controller.list.validatePurchase then
            local valid, reason = controller.list.validatePurchase(state.pendingEntry, state.pendingQty)
            if not valid then return Fail(reason) end
        end
        if RouteVendor(state.pendingEntry, state.quoteTotalPrice) then return false, "vendor" end
        if not state.pendingItemID or not state.pendingQty then
            return Fail(L("QB_ERR_NO_QUOTE", "No commodity quote is ready."))
        end
        if deps.getQuoteRemaining and (tonumber(deps.getQuoteRemaining()) or 0) <= 0 then
            return Fail(L("WF_QUOTE_EXPIRED", "The quote expired. Click Buy to request a new one."))
        end
        local ok, err = pcall(deps.confirm, state.pendingItemID, state.pendingQty)
        if not ok then
            return Fail(L("QB_ERR_CONFIRM", "The Auction House could not confirm this purchase: %s", tostring(err)))
        end
        state.phase = "purchasing"
        state.lastError = nil
        -- The confirmation can be lost: after a while move on instead of
        -- waiting forever. The entry leaves the list (it probably went
        -- through; its mail records it), and the player checks the mailbox
        -- before buying it again.
        local attempt, entry = state.attemptID, state.pendingEntry
        if deps.after then
            deps.after(PURCHASE_TIMEOUT, function()
                if state.phase ~= "purchasing" or state.attemptID ~= attempt or state.pendingEntry ~= entry then return end
                RemoveEntry(controller.list, entry)
                ClearPending()
                state.phase = FirstEntry(controller.list) and "idle" or "complete"
                state.lastError = L("QB_NO_CONFIRMATION", "No confirmation for %s from the Auction House. Check your mailbox before buying it again.",
                    entry.name or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.itemID)) or "?")
                Changed()
            end)
        end
        Changed()
        return true
    end

    function controller:GetVendorEntry()
        if not deps.merchantOffer then return nil end
        for _, entries in ipairs({ (self.list and self.list.vendorEntries) or {},
                (self.list and self.list.entries) or {} }) do
            for _, entry in ipairs(entries) do
                local offer = deps.merchantOffer(entry.itemID)
                local policy = GAM.VendorPrices and GAM.VendorPrices.ShouldBuyAtMerchant
                if (tonumber(entry.quantity) or 0) > 0 and offer
                        and (not policy or policy(entry.itemID, entry.quantity, offer)) then
                    return entry, offer, entries
                end
            end
        end
    end

    local function FinishVendor(message)
        local state = controller.state
        state.vendorPending = nil
        local list = controller.list or {}
        state.phase = not FirstEntry(list) and #(list.vendorEntries or {}) == 0 and "complete" or "idle"
        state.active = false
        state.lastError = message
        -- A sync generated during delivery can contain pre-delivery quantities.
        controller.deferredList = nil
        Changed()
    end

    local function SubmitVendorBatch(pending)
        if controller.list and controller.list.validatePurchase then
            local valid, reason = controller.list.validatePurchase(pending.entry, pending.entry.quantity)
            if not valid then FinishVendor(reason); return false end
        end
        local offer = deps.merchantOffer(pending.entry.itemID)
        if not offer then
            FinishVendor(L("WF_VENDOR_UNAVAILABLE", "This vendor no longer has the item available."))
            return false
        end
        local policy = GAM.VendorPrices and GAM.VendorPrices.ShouldBuyAtMerchant
        if policy and not policy(pending.entry.itemID, pending.entry.quantity, offer) then
            FinishVendor(L("WF_AH_CHEAPER", "The Auction House is cheaper. Buy this material there."))
            return false
        end
        local quantity = math.ceil(pending.entry.quantity / offer.bundle) * offer.bundle
        quantity = math.min(quantity, offer.maxStack)
        if offer.available >= 0 then quantity = math.min(quantity, offer.available) end
        if offer.unitPrice > 0 then
            quantity = math.min(quantity, math.floor((deps.getMoney() or 0) / offer.unitPrice))
        end
        quantity = math.floor(quantity / offer.bundle) * offer.bundle
        if quantity <= 0 then
            FinishVendor(L("WF_VENDOR_LIMIT", "Not enough gold or vendor stock for another bundle. Remaining items stay on the list."))
            return false
        end
        pending.before = deps.getItemCount(pending.entry.itemID)
        pending.quantity = quantity
        pending.unitPrice = offer.unitPrice
        controller.state.attemptID = controller.state.attemptID + 1
        local attempt = controller.state.attemptID
        local ok, err = pcall(deps.buyMerchant, offer.index, quantity)
        if not ok then FinishVendor(tostring(err)); return false end
        if deps.after then
            deps.after(8, function()
                if controller.state.vendorPending == pending and controller.state.attemptID == attempt then
                    controller:OnVendorBagUpdate()
                    if controller.state.vendorPending == pending and controller.state.attemptID == attempt then
                        FinishVendor(L("WF_VENDOR_NOT_RECEIVED", "Vendor purchase was not fully received. Check bag space and try again."))
                    end
                end
            end)
        end
        Changed()
        return true
    end

    function controller:ClickVendor()
        if self.state.phase ~= "idle" and self.state.phase ~= "complete" then return false end
        local entry, _, entries = self:GetVendorEntry()
        if not entry then return false end
        self.state.phase = "vendorPurchasing"
        self.state.active = true
        self.state.lastError = nil
        local pending = { entry = entry, entries = entries }
        self.state.vendorPending = pending
        return SubmitVendorBatch(pending)
    end

    function controller:OnVendorBagUpdate()
        local pending = self.state.vendorPending
        if not pending then return false end
        local received = math.min(pending.quantity,
            math.max(0, deps.getItemCount(pending.entry.itemID) - pending.before))
        if received <= 0 then return false end
        pending.entry.quantity = math.max(0, pending.entry.quantity - received)
        pending.before = pending.before + received
        if deps.onReceipt then
            deps.onReceipt(pending.entry, received, received * (pending.unitPrice or 0), "vendor", self.list)
        end
        pending.quantity = pending.quantity - received
        if pending.entry.quantity <= 0 then
            if deps.onPurchased then deps.onPurchased(pending.entry, received, self.list) end
            for i, entry in ipairs(pending.entries) do
                if entry == pending.entry then table.remove(pending.entries, i); break end
            end
            FinishVendor()
        elseif pending.quantity == 0 and not self.state.active then
            FinishVendor()
        elseif pending.quantity == 0 then
            -- Each stack is confirmed before requesting the next one.
            SubmitVendorBatch(pending)
        else
            Changed()
        end
        return true
    end

    function controller:SetList(list)
        local phase = self.state.phase
        if phase == "quoting" or phase == "approval" or phase == "purchasing" or phase == "vendorPurchasing" then
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
        -- Hiding the UI cannot revoke a purchase already submitted to the AH.
        -- Keep its identity until success/failure so reopening cannot buy it twice.
        if self.state.phase == "purchasing" or self.state.phase == "vendorPurchasing" then
            self.state.active = false
            Changed()
            return
        end
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
        if state.phase == "quoting" or state.phase == "purchasing" or state.phase == "vendorPurchasing" then
            return false, L("QB_ERR_BUSY", "The current purchase is still being processed.")
        end

        local entry = FirstEntry(self.list)
        while entry and RouteVendor(entry) do
            entry = FirstEntry(self.list)
        end
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
        if RouteVendor(state.pendingEntry, totalPrice) then return false, "vendor" end

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

    -- The Auction House does not have this much right now. The first time,
    -- the material moves behind the rest so the others can still be bought;
    -- if it comes round again and is still short, the list stops on it.
    function controller:OnPriceUnavailable()
        if self.state.phase ~= "quoting" and self.state.phase ~= "approval" then return false end
        local entry, list = self.state.pendingEntry, self.list
        -- Craft Queue lists: stop buying for the plans that need it.
        local message = entry and list and list.onUnavailable and list.onUnavailable(entry)
        if message then
            CancelQuote()
            ClearPending()
            self.state.phase = FirstEntry(list) and "idle" or "complete"
            self.state.lastError = message
            Changed()
            return true
        end
        if entry and list and list.entries and not entry.unavailable and #list.entries > 1 then
            entry.unavailable = true
            RemoveEntry(list, entry)
            list.entries[#list.entries + 1] = entry
            CancelQuote()
            ClearPending()
            self.state.phase = "idle"
            self.state.lastError = L("QB_UNAVAILABLE_LATER", "Not enough %s on the Auction House right now; buying the rest first.",
                entry.name or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.itemID)) or "?")
            Changed()
            return true
        end
        return Fail(L("WF_QUANTITY_UNAVAILABLE", "This quantity is unavailable. Select another material in Shopping, or retry Buy."))
    end

    function controller:OnPurchaseFailed()
        if self.state.phase ~= "purchasing" then return false end
        return Fail(L("WF_PURCHASE_FAILED", "The purchase failed. Retry Buy or select another material in Shopping."))
    end

    function controller:OnPurchaseSucceeded()
        local state = self.state
        if state.phase ~= "purchasing" or not state.pendingEntry then return false end
        local purchasedEntry = state.pendingEntry
        local purchasedQty = state.pendingQty
        local deferred = self.deferredList
        self.deferredList = nil
        if deferred and deferred ~= self.list then
            ApplyPurchasedQuantity(deferred, purchasedEntry.itemID, purchasedQty)
        end
        if deps.onReceipt then
            deps.onReceipt(purchasedEntry, purchasedQty, state.quoteTotalPrice, "auction", self.list)
        end
        if deps.onPurchased then
            deps.onPurchased(purchasedEntry, purchasedQty, self.list)
        end
        RemoveEntry(self.list, purchasedEntry)
        -- A list rebuilt by the receipt callback already includes the purchase.
        self.list = self.deferredList or deferred or self.list
        self.deferredList = nil
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
        if state.phase == "complete" and deps.onComplete then
            deps.onComplete(controller)
        end
        return true
    end

    function controller:Skip()
        if self.state.phase == "purchasing" or self.state.phase == "vendorPurchasing" then
            return false, L("QB_ERR_BUSY", "The current purchase is still being processed.")
        end
        if self.state.phase == "quoting" or self.state.phase == "approval" then
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
local vendorOpen, auctionOpen, dismissedContext
local RefreshContext

function QuickBuy.GetContext()
    local merchant = vendorOpen
    if merchant == nil then merchant = MerchantFrame and MerchantFrame:IsShown() end
    if merchant then return "vendor" end
    local auction = auctionOpen
    if auction == nil then auction = GAM.ahOpen end
    if auction then return "auction" end
end

local function DismissWindow()
    dismissedContext = QuickBuy.GetContext()
    if controller then controller:Reset() end
    if window and window:IsShown() then
        window._gamDismissInProgress = true
        window:Hide()
        window._gamDismissInProgress = nil
    end
end

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

function QuickBuy.GetPresentation()
    if not controller then return nil end
    local state, list = controller.state, controller:GetList() or {}
    local context = QuickBuy.GetContext()
    local vendorEntry, offer = controller:GetVendorEntry()
    local entry = state.pendingEntry or (state.vendorPending and state.vendorPending.entry)
        or (context == "vendor" and vendorEntry) or (context ~= "vendor" and FirstEntry(list))
    local title = context == "vendor" and L("WF_QUICK_BUY_VENDOR", "Quick Buy: Craft Queue - Vendor") or L("WF_QUICK_BUY_AH", "Quick Buy: Craft Queue - Auction House")
    local progress = L("WF_BUY_REMAINING", "%d remaining", #(list.entries or {}) + #(list.vendorEntries or {}))
    local listEmpty = #(list.entries or {}) == 0 and #(list.vendorEntries or {}) == 0
    local itemText = entry and (entry.name or tostring(entry.itemID))
        or (listEmpty and L("WF_QUICK_BUY_EMPTY_TITLE", "Your shopping list is empty"))
        or L("WF_NO_MATERIALS_HERE", "No materials needed here")
    local quantity = entry and math.max(0, tonumber(entry.quantity) or 0) or 0
    local total = state.quoteTotalPrice or (entry and entry.unitPrice and quantity * entry.unitPrice)
    if context == "vendor" and offer and entry then
        quantity = math.ceil(quantity / offer.bundle) * offer.bundle
        total = quantity * offer.unitPrice
    end
    local quantityFormat = state.quoteTotalPrice
        and (GAM.L and GAM.L["WF_BUY_TOTAL"] or "Quantity: %d · Total: %s")
        or (GAM.L and GAM.L["WF_BUY_ESTIMATE"] or "Quantity: %d · Est. total: %s")
    local quantityText = entry and string.format(quantityFormat, quantity, FormatMoney(total)) or ""
    local label, message = (GAM.L and GAM.L["WF_BUY"] or "Buy"), state.lastError
    local enabled = entry ~= nil and context ~= nil
    if state.phase == "quoting" then
        label, message, enabled = (GAM.L and GAM.L["WF_CHECKING"] or "Checking price…"), (GAM.L and GAM.L["WF_WAIT_QUOTE"] or "Waiting for the Auction House quote."), false
    elseif state.phase == "purchasing" or state.phase == "vendorPurchasing" then
        label, message, enabled = (GAM.L and GAM.L["WF_PURCHASING"] or "Purchasing…"), (GAM.L and GAM.L["WF_WAIT_PURCHASE"] or "Waiting for purchase confirmation."), false
    elseif state.phase == "approval" then
        label, message = (GAM.L and GAM.L["WF_ACCEPT_PRICE"] or "Accept price"), (GAM.L and GAM.L["WF_REVIEW_PRICE"] or "Review the live total before buying.")
    elseif not entry and listEmpty then
        -- Quick Buy buys the Craft Queue's materials; with nothing queued,
        -- say so instead of opening an empty window.
        enabled = false
        message = L("WF_QUICK_BUY_EMPTY", "Add strategies to the Craft Queue (Add to Queue in Details), then use Quick Buy at the Auction House or a vendor.")
    elseif not context then
        message = L("WF_VISIT_PURCHASE", "Visit a vendor or the Auction House.")
    elseif not entry then
        label, message, enabled = (GAM.L and GAM.L["WF_COMPLETE"] or "Complete"), L("WF_LOCATION_COMPLETE", "No materials needed at this location."), false
    elseif not message then
        message = context == "vendor" and L("WF_BUY_BUNDLES", "Buy the required bundles from this vendor.")
            or L("WF_LIVE_PRICE_POLICY", "Buy at the live price. Increases over 5% require confirmation.")
    end
    return {title=title, progress=progress, item=itemText, quantity=quantityText,
        message=message or "", label=label, enabled=enabled, phase=state.phase, entry=entry}
end

local function InlineVisible()
    local ui = GAM.UI and GAM.UI.CraftPlanWindow
    return ui and ui.IsShoppingVisible and ui.IsShoppingVisible()
end

local function RefreshWindow()
    if not window then return end
    local view = QuickBuy.GetPresentation()
    refs.title:SetText(view.title); refs.progress:SetText(view.progress)
    refs.item:SetText(view.item); refs.quantity:SetText(view.quantity)
    refs.status:SetText(view.message)
    refs.buy:SetText(view.label); refs.buy:SetEnabled(view.enabled); refs.buy:SetAlpha(view.enabled and 1 or 0.5)
end

RefreshContext = function(syncList)
    if not controller or not window then return end
    local context = QuickBuy.GetContext()
    local idle = controller.state.phase == "idle" or controller.state.phase == "complete"
    local plan = GAM.CraftPlan
    -- Rebuild from the queue while it has plans, and also when the last plan
    -- was removed so a previous queue list cannot resurface. Lists from other
    -- sources (strategy shopping sync) are left alone when the queue is empty.
    local current = controller:GetList()
    if context and syncList and idle and plan and plan.CreateShoppingList and not plan.IsBusy()
            and (#plan.GetData().plans > 0 or (current and current.craftPlan)) then
        plan.Init()
        controller:SetList(plan.CreateShoppingList())
    end
    local list = controller:GetList() or {}
    local relevant = context == "vendor" and controller:GetVendorEntry()
        or context == "auction" and FirstEntry(list)
    if not InlineVisible() and context and (relevant or not idle) and dismissedContext ~= context then
        if not window:IsShown() then
            local owner = context == "vendor" and MerchantFrame or AuctionHouseFrame
            window:ClearAllPoints()
            if owner and owner:IsShown() then
                window:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, 0)
            else
                window:SetPoint("CENTER", UIParent, "CENTER", 180, 0)
            end
            window:Show()
        end
    elseif window:IsShown() and (InlineVisible()
            or ((not context or idle) and not window._gamUserOpened)) then
        window._gamDismissInProgress = true
        window:Hide()
        window._gamDismissInProgress = nil
    end
    RefreshWindow()
end

local function BuildWindow()
    if window then return end
    window = CreateFrame("Frame", GAM.RuntimeName("GAMQuickBuyWindow"), UIParent, "BackdropTemplate")
    window._gamOpaqueBackground = true
    window:SetSize(390, 174)
    window:SetScale((GAM.GetOption and GAM:GetOption("uiScale", 1.0)) or 1.0)
    window:SetClampedToScreen(true)
    window:SetPoint("CENTER", UIParent, "CENTER", 180, 40)
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true); window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    window:SetBackdropColor(0.055, 0.055, 0.062, 0.99)
    window:SetBackdropBorderColor(0.48, 0.40, 0.16, 0.9)
    -- Initial hide precedes any callback that accesses the controls below.
    window:Hide()
    window:SetScript("OnHide", function(self)
        self._gamUserOpened = nil
        if not self._gamDismissInProgress and not self._gamConfirmedComplete then
            dismissedContext = QuickBuy.GetContext()
            controller:Reset()
        end
        self._gamConfirmedComplete = nil
    end)
    local manager = GAM.UI and GAM.UI.WindowManager
    if manager and manager.Register then manager.Register(window, "dialog") end
    if UISpecialFrames then table.insert(UISpecialFrames, window:GetName()) end
    local function Field(font, y)
        local text = window:CreateFontString(nil, "OVERLAY", font)
        text:SetPoint("TOPLEFT", 12, y); text:SetPoint("RIGHT", window, "RIGHT", -12, 0)
        text:SetJustifyH("LEFT")
        return text
    end
    refs.title = Field("GameFontNormal", -10)
    refs.title:ClearAllPoints(); refs.title:SetPoint("TOPLEFT", 12, -10)
    refs.title:SetTextColor(0.96, 0.82, 0.36, 1)
    window._gamTitle = refs.title
    refs.progress = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    refs.progress:SetPoint("TOPRIGHT", -36, -11)
    local rule = window:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1); rule:SetPoint("TOPLEFT", 0, -32); rule:SetPoint("TOPRIGHT", 0, -32)
    rule:SetColorTexture(0.38, 0.32, 0.14, 0.65)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2); close:SetScript("OnClick", DismissWindow)
    refs.item = Field("GameFontNormal", -43)
    refs.item:SetWordWrap(false)
    refs.quantity = Field("GameFontHighlightSmall", -64)
    refs.status = Field("GameFontHighlightSmall", -87)
    refs.status:SetHeight(36); refs.status:SetWordWrap(true)
    refs.buy = CreateFrame("Button", GAM.RuntimeName("GAMQuickBuyBtn"), window, "UIPanelButtonTemplate")
    refs.buy:SetSize(154, 26); refs.buy:SetPoint("BOTTOMRIGHT", -12, 10)
    refs.buy:SetScript("OnClick", function()
        if QuickBuy.GetContext() == "vendor" then controller:ClickVendor() else controller:Click() end
    end)
    local common = GAM.UI and GAM.UI.MainWindowCommon
    if common and common.StyleComfortableButton then common.StyleComfortableButton(refs.buy, true) end
    if common and common.StyleSecondaryWindow then common.StyleSecondaryWindow(window) end
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
            -- Quick Buy records its own purchases; HistoryCapture skips them.
            GAM.quickBuyConfirming = true
            local ok, err = pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, itemID, quantity)
            GAM.quickBuyConfirming = nil
            if not ok then error(err, 0) end
        end,
        cancel = function()
            if C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
                C_AuctionHouse.CancelCommoditiesPurchase()
            end
        end,
        getQuoteRemaining = function()
            return C_AuctionHouse.GetQuoteDurationRemaining()
        end,
        merchantOffer = function(itemID)
            return GAM.VendorPrices and GAM.VendorPrices.GetMerchantOffer(itemID)
        end,
        buyMerchant = function(index, quantity)
            GAM.quickBuyVendoring = true
            local ok, err = pcall(BuyMerchantItem, index, quantity)
            GAM.quickBuyVendoring = nil
            if not ok then error(err, 0) end
        end,
        getItemCount = function(itemID) return C_Item.GetItemCount(itemID, false, false, false) end,
        getMoney = GetMoney,
        after = function(delay, callback)
            C_Timer.After(delay, callback)
        end,
        onPurchased = function(entry, quantity, list)
            if list and list.onPurchased then
                list.onPurchased(entry, quantity, controller.state.phase == "vendorPurchasing")
            end
            RemoveAuctionatorEntry(entry, list)
        end,
        onReceipt = function(entry, quantity, copper, source)
            if not (GAM.CraftHistory and entry) then return end
            -- Auction House purchases are recorded from their mail, at the
            -- invoice price (HistoryCapture); vendor purchases right away.
            if source == "auction" and GAM.HistoryCapture and GAM.HistoryCapture.ExpectPurchase then
                GAM.HistoryCapture.ExpectPurchase(entry.itemID, quantity, copper, entry.plans)
            else
                GAM.CraftHistory.RecordPurchase(entry.itemID, quantity, copper, source, entry.plans)
            end
        end,
        onVendor = RemoveAuctionatorEntry,
        onComplete = function()
            local list = controller:GetList()
            if list and list.vendorEntries and #list.vendorEntries > 0 then return end
            if window and window:IsShown() then
                window._gamConfirmedComplete = true
                window:Hide()
            end
        end,
        onChanged = function(activeController)
            GAM.quickBuyState = activeController.state
            GAM.quickBuyList = activeController:GetList()
            RefreshSignature(GAM.quickBuyList)
            RefreshContext(false)
            if GAM.CraftPlan then GAM.CraftPlan.Notify() end
        end,
    })
    controller:SetList(GAM.quickBuyList)
    GAM.quickBuyState = controller.state
    BuildWindow()
    -- Core's event registry has one handler per event. Use a separate listener
    -- so vendor price capture and existing inventory handlers remain installed.
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "MERCHANT_SHOW", "MERCHANT_UPDATE",
            "MERCHANT_CLOSED", "PLAYER_MONEY", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_SHOW" then vendorOpen = true; dismissedContext = nil end
        if event == "AUCTION_HOUSE_SHOW" then auctionOpen = true; dismissedContext = nil end
        if event == "MERCHANT_CLOSED" then vendorOpen = false; controller:Reset(); window._gamUserOpened = nil end
        if event == "AUCTION_HOUSE_CLOSED" then auctionOpen = false; controller:Reset(); window._gamUserOpened = nil end
        if event == "BAG_UPDATE_DELAYED" then controller:OnVendorBagUpdate() end
        local function refresh()
            RefreshContext(true)
            if GAM.CraftPlan then GAM.CraftPlan.Notify() end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, refresh) else refresh() end
    end)
end

function QuickBuy.SetList(list)
    GAM.quickBuyList = list
    if controller then controller:SetList(list) end
end

-- Opened by the player: stays open (an empty list explains how to fill it)
-- until closed or the vendor / Auction House closes. It used to hide again
-- in the same click when nothing was left to buy here.
function QuickBuy.Show()
    QuickBuy.Init()
    dismissedContext = nil
    if not InlineVisible() then
        window._gamUserOpened = true
        window:Show(); window:Raise()
    end
    -- Rebuild from the Craft Queue so the list is current.
    if QuickBuy.GetContext() then RefreshContext(true) else RefreshWindow() end
end

function QuickBuy.Toggle()
    QuickBuy.Init()
    if window:IsShown() then
        DismissWindow()
    else
        QuickBuy.Show()
    end
end

-- Shopping's Buy action is itself the user's purchase click.
function QuickBuy.Buy()
    QuickBuy.Show()
    if QuickBuy.GetContext() == "vendor" then return controller:ClickVendor() end
    if QuickBuy.GetContext() == "auction" then return controller:Click() end
end

function QuickBuy.Reset()
    if controller then controller:Reset() end
end

function QuickBuy.Hide()
    DismissWindow()
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

function QuickBuy.RefreshPresentation()
    RefreshContext(true)
end
