-- GoldAdvisorMidnight/State.lua
-- Shared SavedVariables/state access helpers.
-- Module: GAM.State

local ADDON_NAME, GAM = ...
local State = {}
GAM.State = State

local PATCH_TABLE_KEYS = {
    "startingAmounts",
    "favorites",
    "rankGroups",
    "priceOverrides",
    "inputQtyOverrides",
    "craftsOverrides",
}

local FAVORITE_POLICIES = {
    lowest = true,
    highest = true,
}

local function NormalizeRankPolicy(rankPolicy)
    return (rankPolicy == "highest") and "highest" or "lowest"
end

local function NormalizeFavoritesTable(favorites)
    if type(favorites) ~= "table" then
        favorites = {}
    end

    local lowest = type(favorites.lowest) == "table" and favorites.lowest or {}
    local highest = type(favorites.highest) == "table" and favorites.highest or {}
    local legacyKeys = nil

    for key, value in pairs(favorites) do
        if not FAVORITE_POLICIES[key] then
            if value then
                lowest[key] = true
                highest[key] = true
            end
            legacyKeys = legacyKeys or {}
            legacyKeys[#legacyKeys + 1] = key
        end
    end

    if legacyKeys then
        for _, key in ipairs(legacyKeys) do
            favorites[key] = nil
        end
    end

    favorites.lowest = lowest
    favorites.highest = highest
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
    local favorites = GetFavoritesForPatch(patch)
    return favorites[NormalizeRankPolicy(rankPolicy)]
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
    local db = GAM.db or GoldAdvisorMidnightDB
    if not db then
        return nil
    end

    GAM.db = db
    db.options = db.options or {}
    db.patch = db.patch or {}
    db.priceCache = db.priceCache or {}
    db.scanState = db.scanState or {}
    db.itemKeyDB = db.itemKeyDB or {}
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
end

function State.GetItemKeyDB()
    local db = EnsureDB()
    return (db and db.itemKeyDB) or {}
end

function State.GetUserStrats()
    local db = EnsureDB()
    return (db and db.userStrats) or {}
end

function State.AddUserStrat(strat)
    local db = EnsureDB()
    if not db or not strat then
        return nil
    end
    db.userStrats[#db.userStrats + 1] = strat
    return #db.userStrats
end

function State.ReplaceUserStrat(index, strat)
    local db = EnsureDB()
    if not db or not index or not strat then
        return false
    end
    db.userStrats[index] = strat
    return true
end

function State.DeleteUserStratAt(index)
    local db = EnsureDB()
    if not db or not index or not db.userStrats[index] then
        return nil
    end
    return table.remove(db.userStrats, index)
end

function State.FindUserStratIndex(strat)
    if not strat then
        return nil
    end

    for i, existing in ipairs(State.GetUserStrats()) do
        if existing == strat or
            (existing.stratName == strat.stratName and existing.profession == strat.profession) then
            return i
        end
    end

    return nil
end

function State.DeleteUserStrat(strat)
    local index = State.FindUserStratIndex(strat)
    if not index then
        return nil
    end
    return State.DeleteUserStratAt(index)
end

function State.RunSmokeChecks()
    local ok, err = pcall(function()
        local migrated = NormalizeFavoritesTable({
            legacy_shared = true,
            lowest = { lowest_only = true },
            highest = { highest_only = true },
        })

        assert(migrated.legacy_shared == nil, "legacy favorites were not cleaned up")
        assert(migrated.lowest.legacy_shared and migrated.highest.legacy_shared,
            "legacy favorites did not copy into both rank buckets")
        assert(migrated.lowest.lowest_only and not migrated.highest.lowest_only,
            "lowest favorites leaked into highest bucket")
        assert(migrated.highest.highest_only and not migrated.lowest.highest_only,
            "highest favorites leaked into lowest bucket")

        local patch = {
            favorites = {
                shared_before = true,
            },
        }

        assert(GetFavoriteBucketForPatch(patch, "lowest").shared_before, "lowest bucket migration unavailable")
        assert(GetFavoriteBucketForPatch(patch, "highest").shared_before, "highest bucket migration unavailable")

        assert(ToggleFavoriteForPatch(patch, "r1_only", "lowest"), "failed to set lowest-rank favorite")
        assert(GetFavoriteBucketForPatch(patch, "lowest").r1_only, "lowest-rank favorite missing after toggle")
        assert(not GetFavoriteBucketForPatch(patch, "highest").r1_only, "lowest-rank favorite leaked to highest")

        assert(not ToggleFavoriteForPatch(patch, "r1_only", "lowest"), "failed to clear lowest-rank favorite")
        assert(not GetFavoriteBucketForPatch(patch, "lowest").r1_only, "lowest-rank favorite remained after clear")
        assert(GetFavoriteBucketForPatch(patch, "highest").shared_before, "highest bucket changed unexpectedly")
    end)
    return ok, err
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
