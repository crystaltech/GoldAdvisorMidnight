-- Optional, read-only TSM regional sale-rate integration.
local ADDON_NAME, GAM = ...
local SaleRate = {}
GAM.TSMSaleRate = SaleRate
local cache = {}

function SaleRate.IsAvailable()
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return type(isLoaded) == "function" and isLoaded("TradeSkillMaster")
        and type(TSM_API) == "table" and type(TSM_API.GetCustomPriceValue) == "function"
        and true or false
end

function SaleRate.Get(itemID)
    if not SaleRate.IsAvailable() then return nil end
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return nil end
    local now = GetTime and GetTime() or 0
    local cached = cache[itemID]
    if cached and cached.api == TSM_API and now - cached.time < 30 then return cached.value end
    -- Scale before evaluation to preserve fractional rates in API versions that
    -- round custom price results to integer copper.
    local ok, value = pcall(TSM_API.GetCustomPriceValue, "DBRegionSaleRate * 10000", "i:" .. itemID)
    value = ok and tonumber(value) or nil
    if value then value = value / 10000 end
    if not value or value ~= value or value < 0 or value > 1 then value = nil end
    cache[itemID] = { value = value, time = now, api = TSM_API }
    return value
end

-- Average units sold per auction house per day in the region (TSM). It is a
-- regional average, not this player's sales; nil when TSM has no value.
local soldCache = {}
function SaleRate.SoldPerDay(itemID)
    if not SaleRate.IsAvailable() then return nil end
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return nil end
    local now = GetTime and GetTime() or 0
    local cached = soldCache[itemID]
    if cached and cached.api == TSM_API and now - cached.time < 30 then return cached.value end
    local ok, value = pcall(TSM_API.GetCustomPriceValue, "DBRegionSoldPerDay * 1000", "i:" .. itemID)
    value = ok and tonumber(value) or nil
    if value then value = value / 1000 end
    if not value or value ~= value or value < 0 then value = nil end
    soldCache[itemID] = { value = value, time = now, api = TSM_API }
    return value
end

function SaleRate.ForOutputs(outputs)
    local seen, items = {}, {}
    for _, output in ipairs(outputs or {}) do
        local id = tonumber(output.itemID)
        if id and not seen[id] then
            seen[id] = true
            items[#items + 1] = { itemID = id, name = output.name or tostring(id), rate = SaleRate.Get(id) }
        end
    end
    local value = #items == 1 and items[1].rate or nil
    local label = #items > 1 and (GAM.L and GAM.L["UI_MIXED"] or "Mixed") or (value and string.format("%.1f%%", value * 100) or "—")
    return value, label, items
end
