-- GoldAdvisorMidnight/CraftingStatsCache.lua
-- Persistent crafting-stat cache ownership, migration, copying, and revisions.
-- Module: GAM.CraftingStatsCache

local ADDON_NAME, GAM = ...
local Cache = {}
GAM.CraftingStatsCache = Cache

Cache.VERSION = 2

function Cache.CopyNumericTable(source)
    if type(source) ~= "table" then return nil end
    local out = {}
    for key, value in pairs(source) do
        local n = tonumber(value)
        if n ~= nil then
            out[key] = n
        end
    end
    return next(out) and out or nil
end

function Cache.CopySerializableTable(source, depth)
    if type(source) ~= "table" then return nil end
    if (depth or 0) > 6 then return nil end

    local out = {}
    for key, value in pairs(source) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" then
            local valueType = type(value)
            if valueType == "table" then
                out[key] = Cache.CopySerializableTable(value, (depth or 0) + 1)
            elseif valueType == "string" or valueType == "number" or valueType == "boolean" then
                out[key] = value
            end
        end
    end
    return next(out) and out or nil
end

function Cache.CopyShallowTable(source)
    if type(source) ~= "table" then return nil end
    local out = {}
    for key, value in pairs(source) do
        out[key] = value
    end
    return out
end

function Cache.GetCurrentTimestamp()
    if type(time) == "function" then
        return time()
    end
    if os and type(os.time) == "function" then
        return os.time()
    end
    return 0
end

local function GetCrafterIdentity()
    local name = type(UnitName) == "function" and UnitName("player") or nil
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil
    name = name or "Unknown"
    realm = realm or "Unknown"
    return name .. "-" .. realm, name, realm
end

local function EnsureCharacterShape(character, uid, name, realm)
    if type(character) ~= "table" then return nil end
    character.recipes = character.recipes or {}
    character.recipeValidatedAt = character.recipeValidatedAt or {}
    character.profiles = character.profiles or {}
    character.manualProfiles = character.manualProfiles or {}
    character.nodeState = character.nodeState or {}
    character.gearPresets = character.gearPresets or {}
    if uid then character.uid = uid end
    if name then character.name = name end
    if realm then character.realm = realm end
    return character
end

function Cache.Ensure()
    local db = GAM.db or GoldAdvisorMidnightDB
    if type(db) ~= "table" then
        return nil
    end

    db.v2StatCache = db.v2StatCache or {}
    local cache = db.v2StatCache
    cache.version = Cache.VERSION
    cache.revision = tonumber(cache.revision) or 0
    cache.characters = cache.characters or {}

    -- Lazily migrate the first test-branch profile cache shape:
    -- v2StatCache.profiles[crafterUID][profileKey] = snapshot
    if type(cache.profiles) == "table" and not cache._migratedProfileCacheV1 then
        for uid, profiles in pairs(cache.profiles) do
            if type(profiles) == "table" then
                cache.characters[uid] = cache.characters[uid] or {}
                cache.characters[uid].profiles = cache.characters[uid].profiles or {}
                for profileKey, snapshot in pairs(profiles) do
                    if type(snapshot) == "table" and cache.characters[uid].profiles[profileKey] == nil then
                        cache.characters[uid].profiles[profileKey] = snapshot
                    end
                end
            end
        end
        cache._migratedProfileCacheV1 = true
    end

    local uid, name, realm = GetCrafterIdentity()
    cache.characters[uid] = cache.characters[uid] or {}
    local character = EnsureCharacterShape(cache.characters[uid], uid, name, realm)
    return character, uid, cache
end

local runtimeRevision = 0

function Cache.TouchRevision(character, cache)
    runtimeRevision = runtimeRevision + 1
    if type(cache) ~= "table" then
        cache = select(3, Cache.Ensure())
    end
    if type(cache) == "table" then
        cache.revision = (tonumber(cache.revision) or 0) + 1
    end
    if type(character) == "table" then
        character.revision = (tonumber(character.revision) or 0) + 1
    end
end

function Cache.GetRevision()
    local _, _, cache = Cache.Ensure()
    if type(cache) == "table" then
        return tonumber(cache.revision) or 0
    end
    return runtimeRevision
end

local MATERIAL_SNAPSHOT_FIELDS = {
    "source",
    "cachedSource",
    "profileKey",
    "recipeID",
    "recipeName",
    "profession",
    "statQuality",
    "multiPercent",
    "resPercent",
    "multiExtra",
    "resExtra",
    "supportsMulticraft",
    "supportsResourcefulness",
    "mcConstant",
    "resourcefulnessSaveBase",
    "nodeHash",
}

local function ScalarEqual(a, b)
    local na = tonumber(a)
    local nb = tonumber(b)
    if na ~= nil or nb ~= nil then
        return na ~= nil and nb ~= nil and math.abs(na - nb) < 0.000001
    end
    return a == b
end

local function NumericTableEqual(a, b)
    if a == nil and b == nil then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    for key, value in pairs(a) do
        if not ScalarEqual(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

function Cache.SnapshotMateriallyEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    for _, field in ipairs(MATERIAL_SNAPSHOT_FIELDS) do
        if not ScalarEqual(a[field], b[field]) then
            return false
        end
    end
    return NumericTableEqual(a.multicraftConstants, b.multicraftConstants)
end
