-- GoldAdvisorMidnight/ItemInfoCache.lua
-- Memoized Blizzard item/recipe lookups used by pricing. Repricing every
-- strategy asked the client the same questions thousands of times (about
-- 10,000 reagent-quality calls per pass). Answers that cannot change during
-- a session are kept; owned counts are reused only within one frame.
-- Module: GAM.ItemInfoCache

local ADDON_NAME, GAM = ...
local Cache = {}
GAM.ItemInfoCache = Cache

-- Keyed by the API function too, so a replaced function (tests, or a client
-- API swap) never serves answers from the previous one.
local byAPI = setmetatable({}, { __mode = "k" })
local requested = {}

local function Store(api)
    local store = byAPI[api]
    if not store then
        store = {}
        byAPI[api] = store
    end
    return store
end

-- Item-info APIs accept an ItemInfo table or a plain itemID depending on
-- client version; try the table form first, as the pricing code always has.
local function CallItemInfoAPI(api, itemID)
    local ok, value = pcall(api, { itemID = itemID })
    if ok and value ~= nil then return value end
    ok, value = pcall(api, itemID)
    if ok then return value end
    return nil
end

-- Quality tiers are fixed per item. nil means "item data not loaded yet"
-- and is never cached, so a later call can still get the real answer.
function Cache.ItemInfo(api, itemID)
    if type(api) ~= "function" or not itemID then return nil end
    local store = Store(api)
    local cached = store[itemID]
    if cached ~= nil then return cached end
    local value = CallItemInfoAPI(api, itemID)
    if value ~= nil then store[itemID] = value end
    return value
end

function Cache.RequestLoad(itemID)
    if not itemID or itemID == 0 or requested[itemID] then return end
    requested[itemID] = true
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    elseif GetItemInfo then
        GetItemInfo(itemID)
    end
end

-- A recipe's profession identity is fixed; only those fields are kept, so
-- no caller can read a stale skill level from the cache.
function Cache.ProfessionInfoByRecipe(api, recipeID)
    if type(api) ~= "function" or not recipeID then return nil end
    local store = Store(api)
    local cached = store[recipeID]
    if cached ~= nil then return cached or nil end
    local ok, info = pcall(api, recipeID)
    if not ok or type(info) ~= "table" then return nil end
    local identity = {
        profession = info.profession,
        professionID = info.professionID,
        parentProfessionID = info.parentProfessionID,
    }
    -- Keep only a resolved identity; an empty answer may fill in later.
    if (tonumber(info.professionID) or 0) > 0 or (tonumber(info.parentProfessionID) or 0) > 0 then
        store[recipeID] = identity
    end
    return identity
end

-- Owned counts change with bags and banks, so they are shared only within
-- one frame (one repricing pass) and dropped on any bag update.
local countFrame, countGeneration, generation, counts = nil, nil, 0, {}
function Cache.OwnedCount(itemID, read)
    local now = type(GetTime) == "function" and GetTime() or nil
    if not now then return read(itemID) end
    if countFrame ~= now or countGeneration ~= generation then
        counts, countFrame, countGeneration = {}, now, generation
    end
    local cached = counts[itemID]
    if cached == nil then
        cached = read(itemID)
        counts[itemID] = cached
    end
    return cached
end

function Cache.InvalidateCounts()
    generation = generation + 1
end

-- Changes whenever bags or banks change; owned materials affect metrics.
function Cache.GetInventoryGeneration()
    return generation
end

local events = CreateFrame and CreateFrame("Frame")
if events and events.RegisterEvent then
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED",
            "PLAYERREAGENTBANKSLOTS_CHANGED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", Cache.InvalidateCounts)
end
