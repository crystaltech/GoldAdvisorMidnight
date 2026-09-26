-- GoldAdvisorMidnight/State.lua
-- Shared SavedVariables/state access helpers.
-- Module: GAM.State

local ADDON_NAME, GAM = ...
local State = {}
GAM.State = State

-- Session counter bumped whenever any price input changes, so cached
-- strategy metrics know to recalculate without repricing on every redraw.
local priceRevision = 0
function State.BumpPriceRevision() priceRevision = priceRevision + 1 end
function State.GetPriceRevision() return priceRevision end

local PATCH_TABLE_KEYS = {
    "startingAmounts",
    "favorites",
    "rankGroups",
    "priceOverrides",
    "inputQtyOverrides",
    "craftsOverrides",
    "gearModes",
}

local function StartingCraftsBounds()
    local constants = GAM.C or {}
    return constants.MIN_STARTING_CRAFTS or 1,
        constants.MAX_STARTING_CRAFTS or 1000000,
        constants.DEFAULT_STARTING_CRAFTS or 50
end

function State.NormalizeStartingCrafts(value)
    local minValue, maxValue = StartingCraftsBounds()
    local text = tostring(value or ""):gsub(",", ""):match("^%s*(.-)%s*$")
    local number = tonumber(text)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil, string.format(
            "Starting crafts must be a whole number from %d to %d.", minValue, maxValue)
    end
    if number ~= math.floor(number) then
        return nil, string.format(
            "Starting crafts must be a whole number from %d to %d.", minValue, maxValue)
    end
    number = math.floor(number)
    if number < minValue or number > maxValue then
        return nil, string.format(
            "Starting crafts must be from %d to %d.", minValue, maxValue)
    end
    return number
end

local function NormalizeFavoritesTable(favorites)
    if type(favorites) ~= "table" then return {} end
    -- Merge old rank-specific sets once, then remove them so unfavoriting
    -- cannot resurrect a saved favorite on the next read or reload.
    for _, policy in ipairs({"lowest", "highest", "optimal"}) do
        local bucket = favorites[policy]
        favorites[policy] = nil
        if type(bucket) == "table" then
            for id, enabled in pairs(bucket) do
                if enabled == true then favorites[id] = true end
            end
        end
    end
    return favorites
end

local function GetFavoritesForPatch(patch)
    if type(patch) ~= "table" then
        return NormalizeFavoritesTable({})
    end
    patch.favorites = NormalizeFavoritesTable(patch.favorites)
    return patch.favorites
end

local function GetFavoriteBucketForPatch(patch, rankPolicy)
    return GetFavoritesForPatch(patch)
end

local function ToggleFavoriteForPatch(patch, stratID, rankPolicy)
    if not stratID then
        return false
    end

    local bucket = GetFavoriteBucketForPatch(patch, rankPolicy)
    if bucket[stratID] then
        bucket[stratID] = nil
        return false
    end

    bucket[stratID] = true
    return true
end

local function EnsureDB()
    local db = GAM.db or _G[ADDON_NAME .. "DB"]
    if not db then
        return nil
    end

    GAM.db = db
    db.options = db.options or {}
    db.patch = db.patch or {}
    db.priceCache = db.priceCache or {}
    db.scanState = db.scanState or {}
    db.itemKeyDB = db.itemKeyDB or {}
    db.vendorPriceCache = db.vendorPriceCache or { version = 1, characters = {} }
    db.userStrats = db.userStrats or {}
    return db
end

function State.GetDB()
    return EnsureDB()
end

function State.GetOptions()
    local db = EnsureDB()
    return (db and db.options) or {}
end

function State.GetOption(key, fallback)
    local value = State.GetOptions()[key]
    if value == nil then
        return fallback
    end
    return value
end

function State.SetOption(key, value)
    local db = EnsureDB()
    if not db then
        return
    end
    db.options[key] = value
end

function State.GetGlobalStartingCrafts()
    local _, _, defaultValue = StartingCraftsBounds()
    local value = State.GetOption("globalStartingCrafts", defaultValue)
    return State.NormalizeStartingCrafts(value) or defaultValue
end

function State.SetGlobalStartingCrafts(value)
    local normalized, err = State.NormalizeStartingCrafts(value)
    if not normalized then
        return nil, err
    end
    State.SetOption("globalStartingCrafts", normalized)
    return normalized
end

function State.GetPatchDB(patchTag)
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local db = EnsureDB()
    if not db then
        return nil
    end

    local patch = db.patch[patchTag]
    if type(patch) ~= "table" then
        patch = {}
        db.patch[patchTag] = patch
    end

    for _, key in ipairs(PATCH_TABLE_KEYS) do
        if type(patch[key]) ~= "table" then
            patch[key] = {}
        end
    end

    patch.favorites = NormalizeFavoritesTable(patch.favorites)

    return patch
end

function State.IsFavorite(stratID, patchTag, rankPolicy)
    if not stratID then
        return false
    end

    local patch = State.GetPatchDB(patchTag)
    if not patch then
        return false
    end

    local bucket = GetFavoriteBucketForPatch(patch, rankPolicy)
    return bucket[stratID] and true or false
end

function State.ToggleFavorite(stratID, patchTag, rankPolicy)
    local patch = State.GetPatchDB(patchTag)
    if not patch then
        return false
    end

    return ToggleFavoriteForPatch(patch, stratID, rankPolicy)
end

function State.GetRealmCache()
    local db = EnsureDB()
    if not db then
        return {}
    end

    local realmKey = (GAM.GetRealmKey and GAM:GetRealmKey()) or "Unknown-Realm"
    db.priceCache[realmKey] = db.priceCache[realmKey] or {}
    return db.priceCache[realmKey]
end

function State.ClearPriceCache()
    local db = EnsureDB()
    if not db then
        return
    end
    wipe(db.priceCache)
    State.BumpPriceRevision()
end

function State.GetItemKeyDB()
    local db = EnsureDB()
    return (db and db.itemKeyDB) or {}
end


function GAM:GetDB()
    return State.GetDB()
end

function GAM:GetOptions()
    return State.GetOptions()
end

function GAM:GetOption(key, fallback)
    return State.GetOption(key, fallback)
end

function GAM:GetPatchDB(patchTag)
    return State.GetPatchDB(patchTag)
end

function GAM:GetRealmCache()
    return State.GetRealmCache()
end
