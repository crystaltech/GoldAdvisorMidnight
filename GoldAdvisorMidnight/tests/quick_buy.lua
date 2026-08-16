-- Offline regression checks for the Quick Buy commodity quote state machine.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {}

local chunk, err = loadfile("QuickBuy.lua")
assert(chunk, err)
chunk(ADDON_NAME, GAM)

local QuickBuy = assert(GAM.QuickBuy, "QuickBuy module unavailable")

local starts, confirms, cancels, purchased, timers = {}, {}, 0, {}, {}
local quoteRemaining = 30
local money = 1000000
local controller = QuickBuy.CreateController({
    start = function(itemID, quantity)
        starts[#starts + 1] = { itemID, quantity }
    end,
    confirm = function(itemID, quantity)
        confirms[#confirms + 1] = { itemID, quantity }
    end,
    cancel = function()
        cancels = cancels + 1
    end,
    getQuoteRemaining = function()
        return quoteRemaining
    end,
    getMoney = function()
        return money
    end,
    after = function(_, callback)
        timers[#timers + 1] = callback
    end,
    onPurchased = function(entry, quantity)
        purchased[#purchased + 1] = { entry.itemID, quantity }
    end,
})

local list = {
    entries = {
        { itemID = 101, name = "Stable", quantity = 10, unitPrice = 100, searchString = "stable" },
        { itemID = 202, name = "Higher", quantity = 5, unitPrice = 100, searchString = "higher" },
    },
}
controller:SetList(list)

assert(controller:Click(), "first purchase did not start")
assert(controller.state.phase == "quoting", "first purchase did not wait for a quote")
assert(starts[1][1] == 101 and starts[1][2] == 10, "first purchase used the wrong item or quantity")
controller:OnPriceUpdated(105, 1050)
assert(controller.state.phase == "purchasing", "a quote at the 5% guard did not auto-confirm")
assert(#confirms == 1 and confirms[1][1] == 101, "safe quote was not confirmed once")
controller:OnPurchaseSucceeded()
assert(#list.entries == 1 and list.entries[1].itemID == 202, "successful purchase was not removed")
assert(controller.state.phase == "idle", "controller did not return to idle after success")

controller:Click()
controller:OnPriceUpdated(106, 530)
assert(controller.state.phase == "approval", "higher quote bypassed manual approval")
assert(#confirms == 1, "higher quote was confirmed before approval")
controller:Click()
assert(controller.state.phase == "purchasing" and #confirms == 2,
    "approved higher quote was not confirmed")
controller:OnPurchaseFailed()
assert(controller.state.phase == "idle" and #list.entries == 1,
    "failed purchase was removed instead of retained")

controller:Click()
controller:OnPriceUnavailable()
assert(controller.state.phase == "idle" and #list.entries == 1 and cancels >= 1,
    "unavailable quote did not return to a retryable state")

local retryList = {
    entries = {
        { itemID = 303, name = "No Estimate", quantity = 2, searchString = "unknown" },
        { itemID = 404, name = "Skip Target", quantity = 3, unitPrice = 50, searchString = "skip" },
    },
}
controller:SetList(retryList)
controller:Click()
controller:OnPriceUpdated(25, 50)
assert(controller.state.phase == "approval", "missing estimate did not require quote approval")
controller:Reset()
controller:SetList(retryList)
controller:Skip()
assert(retryList.entries[1].itemID == 404 and retryList.entries[2].itemID == 303,
    "skip did not rotate the blocked item")

money = 10
controller:Click()
controller:OnPriceUpdated(50, 150)
assert(controller.state.phase == "idle" and controller.state.lastError,
    "insufficient funds did not produce a retryable error")

quoteRemaining = 0
money = 1000000
controller:Click()
controller:OnPriceUpdated(60, 180)
assert(controller.state.phase == "approval", "expired-quote fixture did not reach approval")
local confirmed, message = controller:Click()
assert(not confirmed and message and controller.state.phase == "idle",
    "expired quote was confirmed instead of rejected")

quoteRemaining = 30
controller:Click()
local timeout = timers[#timers]
assert(timeout, "quote timeout was not scheduled")
timeout()
assert(controller.state.phase == "idle" and controller.state.lastError,
    "missing quote left Quick Buy stuck")

assert(#purchased == 1 and purchased[1][1] == 101 and purchased[1][2] == 10,
    "purchase callback did not receive the completed item")

print("PASS: Quick Buy quote, guard, retry, skip, and completion states")
