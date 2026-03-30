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

    return patch
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
