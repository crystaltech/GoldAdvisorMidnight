-- Offline regression checks for character-specific live merchant prices.

local ADDON_NAME = "GoldAdvisorMidnight"
local registered = {}
local refreshCount = 0
local characterName = "TailorOne"
local now = 1000

local GAM = {
    C = {
        VENDOR_PRICES = {
            [251691] = 700,
            [243060] = 3000,
        },
    },
    db = {},
    Log = { Info = function() end },
    UI = {
        MainWindow = {
            Refresh = function()
                refreshCount = refreshCount + 1
            end,
        },
    },
}

function GAM:RegisterEvent(event, handler)
    registered[event] = handler
end

UnitFullName = function()
    return characterName, "TestRealm"
end
time = function()
    return now
end

local merchantItems = {
    { itemID = 251691, price = 1750, stackCount = 2 },
    { itemID = 243060, price = 3750, stackCount = 1, hasExtendedCost = true },
    { itemID = 999999, price = 12345, stackCount = 1 },
}

GetMerchantNumItems = function()
    return #merchantItems
end
GetMerchantItemID = function(index)
    return merchantItems[index].itemID
end
C_MerchantFrame = {
    GetItemInfo = function(index)
        local item = merchantItems[index]
        return {
            price = item.price,
            stackCount = item.stackCount,
            hasExtendedCost = item.hasExtendedCost,
        }
    end,
}

local chunk, err = loadfile("VendorPrices.lua")
assert(chunk, err)
chunk(ADDON_NAME, GAM)

local VendorPrices = assert(GAM.VendorPrices, "VendorPrices module unavailable")
assert(type(registered.MERCHANT_SHOW) == "function", "MERCHANT_SHOW not registered")
assert(type(registered.MERCHANT_UPDATE) == "function", "MERCHANT_UPDATE not registered")

local fallbackPrice, fallbackSource = VendorPrices.GetPrice(251691)
assert(fallbackPrice == 700 and fallbackSource == "static", "static vendor fallback failed")

registered.MERCHANT_SHOW()
local observedPrice, observedSource, observedEntry = VendorPrices.GetPrice(251691)
assert(observedPrice == 875 and observedSource == "live", "merchant stack price was not normalized")
assert(observedEntry.merchantPrice == 1750 and observedEntry.stackCount == 2,
    "merchant observation metadata missing")
assert(VendorPrices.GetLivePrice(243060) == nil, "extended-cost merchant item should be ignored")
assert(refreshCount == 1, "new live price should invalidate visible calculations once")

now = 1001
registered.MERCHANT_UPDATE()
assert(refreshCount == 1, "unchanged merchant price should not invalidate calculations")

merchantItems[1].price = 1400
registered.MERCHANT_UPDATE()
assert(VendorPrices.GetLivePrice(251691) == 700, "updated live merchant price missing")
assert(refreshCount == 2, "changed merchant price should invalidate calculations")

characterName = "TailorTwo"
local secondCharacterPrice, secondCharacterSource = VendorPrices.GetPrice(251691)
assert(secondCharacterPrice == 700 and secondCharacterSource == "static",
    "live merchant prices leaked between characters")

characterName = "TailorOne"
local resolved = VendorPrices.GetResolvedCatalog()
assert(resolved[251691] == 700 and resolved[243060] == 3000,
    "resolved vendor catalog did not combine live and fallback prices")

print("PASS: live merchant prices are normalized, character-scoped, and cached")
