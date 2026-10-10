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

-- An empty answer may mean "data not loaded yet", so it is not kept for the
-- session, but it is remembered for a short while: an item with no crafted
-- rank, or a recipe without ranked outputs, always answers empty, and asking
-- again on every call made one strategy cost tens of thousands of client
-- calls (about 200 ms in game).
local MISS_SECONDS = 30
local MISS = {}
local function Now() return type(GetTime) == "function" and GetTime() or nil end
local function RecentMiss(store, key)
    local miss = store[MISS] and store[MISS][key]
    local now = Now()
    return miss and now and now < miss or false
end
local function RememberMiss(store, key)
    local now = Now()
    if not now then return end
    store[MISS] = store[MISS] or {}
    store[MISS][key] = now + MISS_SECONDS
end

-- Quality tiers are fixed per item. nil means "no rank" or "item data not
-- loaded yet": remembered briefly, so a later call can still get the answer.
function Cache.ItemInfo(api, itemID)
    if type(api) ~= "function" or not itemID then return nil end
    local store = Store(api)
    local cached = store[itemID]
    if cached ~= nil then return cached end
    if RecentMiss(store, itemID) then return nil end
    local value = CallItemInfoAPI(api, itemID)
    if value ~= nil then store[itemID] = value else RememberMiss(store, itemID) end
    return value
end

-- The item a recipe makes at one crafted rank (GetRecipeOutputItemData) is
-- fixed; an empty answer is remembered briefly like the others.
function Cache.RecipeOutputItem(api, recipeID, quality)
    if type(api) ~= "function" or not recipeID or not quality then return nil end
    local store = Store(api)
    local key = recipeID .. ":" .. quality
    local cached = store[key]
    if cached ~= nil then return cached end
    if RecentMiss(store, key) then return nil end
    local ok, outputInfo = pcall(api, recipeID, {}, nil, quality)
    local itemID = ok and type(outputInfo) == "table" and tonumber(outputInfo.itemID) or nil
    if itemID and itemID > 0 then
        store[key] = itemID
        return itemID
    end
    RememberMiss(store, key)
    return nil
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

-- A recipe's ranked output item list is fixed. An empty answer (recipe data
-- still loading, or no ranked outputs) is remembered only briefly. Callers
-- must not modify the returned list.
function Cache.RecipeList(api, recipeID)
    if type(api) ~= "function" or not recipeID then return nil end
    local store = Store(api)
    local cached = store[recipeID]
    if cached ~= nil then return cached end
    if RecentMiss(store, recipeID) then return nil end
    local ok, list = pcall(api, recipeID)
    if not ok or type(list) ~= "table" or #list == 0 then
        RememberMiss(store, recipeID)
        return nil
    end
    store[recipeID] = list
    return list
end

-- Live answers that hold for one frame (whether a recipe is known, charges
-- ready). Chained strategies ask them once per reagent; one repricing pass
-- runs in one frame, so the first answer is shared. A price change within
-- the frame starts over. Up to three return values.
local liveFrame, liveRevision, live = nil, nil, {}
function Cache.ThisFrame(kind, key, read)
    local now = type(GetTime) == "function" and GetTime() or nil
    if not now or key == nil then return read() end
    local revision = GAM.State and GAM.State.GetPriceRevision and GAM.State.GetPriceRevision() or 0
    if liveFrame ~= now or liveRevision ~= revision then
        live, liveFrame, liveRevision = {}, now, revision
    end
    local bucket = live[kind]
    if not bucket then
        bucket = {}
        live[kind] = bucket
    end
    local entry = bucket[key]
    if not entry then
        local a, b, c = read()
        entry = { a, b, c }
        bucket[key] = entry
    end
    return entry[1], entry[2], entry[3]
end

-- Owned counts change with bags and banks, so they are shared only within
-- one frame (one repricing pass) and dropped on any bag update.
local countFrame, countGeneration, generation, counts = nil, nil, 0, {}
-- Every item pricing has asked about, with the count it saw. A bag update
-- moves the generation only when one of those counts changed, so swapping
-- gear, looting or opening mail no longer reprices every strategy.
local watched, bagsDirty = {}, false
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
        -- A read after a bag update may be the first to see the change (a
        -- detail panel priced before the list checked): move the generation
        -- here too, or the list would keep the old profit.
        local seen = watched[itemID]
        if seen == nil then
            watched[itemID] = { read = read, count = cached }
        elseif seen.count ~= cached then
            seen.count = cached
            generation = generation + 1
            countGeneration = generation
        end
    end
    return cached
end

function Cache.InvalidateCounts()
    -- Read again on the next request; whether anything relevant changed is
    -- decided when the generation is asked for.
    counts, bagsDirty = {}, true
end

-- Changes when the owned count of an item pricing uses changed.
function Cache.GetInventoryGeneration()
    if bagsDirty then
        bagsDirty = false
        local changed = false
        for itemID, entry in pairs(watched) do
            local ok, count = pcall(entry.read, itemID)
            if ok and count ~= entry.count then
                entry.count, changed = count, true
            end
        end
        if changed then generation = generation + 1 end
    end
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
