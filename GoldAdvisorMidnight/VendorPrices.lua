-- GoldAdvisorMidnight/VendorPrices.lua
-- Character-specific merchant price capture with static catalog fallback.
-- Module: GAM.VendorPrices

local ADDON_NAME, GAM = ...
local VendorPrices = {}
GAM.VendorPrices = VendorPrices

local CACHE_VERSION = 1

local function GetTimestamp()
    if type(time) == "function" then
        return time()
    end
    return 0
end

local function GetCharacterKey()
    local name, realm
    if type(UnitFullName) == "function" then
        name, realm = UnitFullName("player")
    end
    if not name and type(UnitName) == "function" then
        name = UnitName("player")
    end
    if not realm and type(GetRealmName) == "function" then
        realm = GetRealmName()
    end
    return tostring(name or "Unknown") .. "-" .. tostring(realm or "Unknown")
end

local function EnsureCharacterCache()
    local db = GAM.db or GoldAdvisorMidnightDB
    if type(db) ~= "table" then
        return nil
    end

    db.vendorPriceCache = type(db.vendorPriceCache) == "table" and db.vendorPriceCache or {}
    local cache = db.vendorPriceCache
    cache.version = CACHE_VERSION
    cache.characters = type(cache.characters) == "table" and cache.characters or {}

    local characterKey = GetCharacterKey()
    cache.characters[characterKey] = type(cache.characters[characterKey]) == "table"
        and cache.characters[characterKey] or {}
    local character = cache.characters[characterKey]
    character.prices = type(character.prices) == "table" and character.prices or {}
    return character, cache, characterKey
end

local function GetMerchantItemPrice(index)
    if C_MerchantFrame and type(C_MerchantFrame.GetItemInfo) == "function" then
        local info = C_MerchantFrame.GetItemInfo(index)
        if type(info) == "table" then
            return tonumber(info.price), tonumber(info.stackCount), info.hasExtendedCost and true or false
        end
    end

    if type(GetMerchantItemInfo) == "function" then
        local _, _, price, quantity, _, _, _, hasExtendedCost = GetMerchantItemInfo(index)
        return tonumber(price), tonumber(quantity), hasExtendedCost and true or false
    end
    return nil, nil, false
end

local function GetMerchantItemIDSafe(index)
    if type(GetMerchantItemID) == "function" then
        local itemID = tonumber(GetMerchantItemID(index))
        if itemID then
            return itemID
        end
    end
    if type(GetMerchantItemLink) == "function" then
        local link = GetMerchantItemLink(index)
        return tonumber(type(link) == "string" and link:match("item:(%d+)") or nil)
    end
    return nil
end

local function NotifyPriceChange(changedCount)
    if changedCount <= 0 then
        return
    end
    if GAM.Log and GAM.Log.Info then
        GAM.Log.Info("Captured %d updated live vendor price(s)", changedCount)
    end
    local mainWindow = GAM.UI and GAM.UI.MainWindow
    if mainWindow and mainWindow.Refresh then
        mainWindow.Refresh()
    end
end

function VendorPrices.IsVendorItem(itemID)
    return itemID ~= nil
        and GAM.C
        and type(GAM.C.VENDOR_PRICES) == "table"
        and GAM.C.VENDOR_PRICES[itemID] ~= nil
end

function VendorPrices.GetLivePrice(itemID)
    itemID = tonumber(itemID)
    if not itemID then
        return nil
    end
    local character = EnsureCharacterCache()
    local entry = character and character.prices[itemID] or nil
    local price = entry and tonumber(entry.price) or nil
    if price and price > 0 then
        return price, entry
    end
    return nil
end

function VendorPrices.GetPrice(itemID)
    local livePrice, entry = VendorPrices.GetLivePrice(itemID)
    if livePrice then
        return livePrice, "live", entry
    end
    local staticPrice = GAM.C and GAM.C.VENDOR_PRICES and GAM.C.VENDOR_PRICES[itemID] or nil
    if staticPrice ~= nil then
        return staticPrice, "static"
    end
    return nil
end

function VendorPrices.GetResolvedCatalog()
    local resolved = {}
    for itemID, price in pairs((GAM.C and GAM.C.VENDOR_PRICES) or {}) do
        resolved[itemID] = VendorPrices.GetLivePrice(itemID) or price
    end
    return resolved
end

function VendorPrices.CaptureMerchant()
    if type(GetMerchantNumItems) ~= "function" then
        return 0, 0
    end
    local character, cache = EnsureCharacterCache()
    if not character then
        return 0, 0
    end

    local capturedCount, changedCount = 0, 0
    local observedAt = GetTimestamp()
    local itemCount = math.max(0, tonumber(GetMerchantNumItems()) or 0)
    for index = 1, itemCount do
        local itemID = GetMerchantItemIDSafe(index)
        if VendorPrices.IsVendorItem(itemID) then
            local totalPrice, stackCount, hasExtendedCost = GetMerchantItemPrice(index)
            stackCount = math.max(1, tonumber(stackCount) or 1)
            if totalPrice and totalPrice > 0 and not hasExtendedCost then
                local unitPrice = totalPrice / stackCount
                local previous = character.prices[itemID]
                if not previous or tonumber(previous.price) ~= unitPrice then
                    changedCount = changedCount + 1
                end
                character.prices[itemID] = {
                    price = unitPrice,
                    merchantPrice = totalPrice,
                    stackCount = stackCount,
                    observedAt = observedAt,
                }
                capturedCount = capturedCount + 1
            end
        end
    end

    if changedCount > 0 then
        cache.revision = (tonumber(cache.revision) or 0) + 1
    end
    NotifyPriceChange(changedCount)
    return capturedCount, changedCount
end

if GAM.RegisterEvent then
    GAM:RegisterEvent("MERCHANT_SHOW", function()
        VendorPrices.CaptureMerchant()
    end)
    GAM:RegisterEvent("MERCHANT_UPDATE", function()
        VendorPrices.CaptureMerchant()
    end)
end
