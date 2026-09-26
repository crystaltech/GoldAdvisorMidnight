-- GoldAdvisorMidnight/CraftingStatsGear.lua
-- Per-profession saved gear sets, per-strategy gear modes, and legacy presets.
-- Module: GAM.CraftingStatsGear

local ADDON_NAME, GAM = ...
local Gear = {}
GAM.CraftingStatsGear = Gear

local Cache = assert(GAM.CraftingStatsCache, "CraftingStatsCache must load before CraftingStatsGear")
local Specialization = GAM.CraftingStatsSpecialization

function Gear.Profession(recipeID, profileKey)
    local api = C_TradeSkillUI
    local info = recipeID and api and api.GetProfessionInfoByRecipeID and api.GetProfessionInfoByRecipeID(recipeID)
    local def = info and Specialization.ResolveProfessionDefBySkillLine(
        info.parentProfessionID or info.professionID)
    local profileDef = Specialization.ResolveProfessionDef(Specialization.GetProfessionForProfile(profileKey))
    -- Conflicting identities must never attach another profession's equipment
    -- to a recipe profile. Unknown API identities cannot identify live slots.
    if def and profileDef and def.name ~= profileDef.name then return nil end
    if info and not def then return nil end
    def = def or profileDef
    return def and def.name, info
end

-- GUID distinguishes two copies; the item string also detects enchant/quality
-- changes on the same item. Never identify a profession tool by item ID alone.
function Gear.ReadEquipment(recipeID, profileKey)
    local profession, info = Gear.Profession(recipeID, profileKey)
    local api = C_TradeSkillUI
    if not profession or not info or info.profession == nil or not api.GetProfessionSlots
            or not GetInventoryItemLink or not C_Item or not ItemLocation then return nil end
    if (api.IsTradeSkillLinked and api.IsTradeSkillLinked())
            or (api.IsTradeSkillGuild and api.IsTradeSkillGuild()) then return nil end
    local slots = api.GetProfessionSlots(info.profession)
    if type(slots) ~= "table" or #slots == 0 then return nil end
    local equipment, signature = {}, {}
    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink("player", slot)
        local guid
        if link then
            guid = C_Item.GetItemGUID(ItemLocation:CreateFromEquipmentSlot(slot))
            if not guid then return nil end
        elseif GetInventoryItemID and GetInventoryItemID("player", slot) then
            return nil -- item data is still loading, not an empty slot
        end
        local itemString = link and link:match("item:[^|]+") or nil
        if link and not itemString then return nil end
        equipment[#equipment + 1] = { slot = slot, guid = guid, item = itemString, link = link }
        signature[#signature + 1] = tostring(slot) .. ":" .. (guid or "empty") .. ":" .. (itemString or "")
    end
    table.sort(signature)
    return { profession = profession, slots = equipment, signature = table.concat(signature, ";") }
end

function Gear.GetSet(character, recipeID, profileKey, mode)
    local profession = Gear.Profession(recipeID, profileKey)
    local sets = character and character.professionGear and character.professionGear[profession]
    local set = sets and sets[mode]
    return set and set.profession == profession and set.mode == mode and set or nil
end

-- Node rating the specialization catalog adds to one recipe's proc stats.
-- nil means the catalog cannot place this recipe; callers must not guess.
local function NodeRatings(character, recipeID, profileKey)
    if not (Specialization and Specialization.ApplyNodeState and Specialization.IsProfile
            and Specialization.IsProfile(profileKey)) then
        return nil
    end
    local probe = Specialization.ApplyNodeState(
        { supportsMulticraft = true, supportsResourcefulness = true }, profileKey, character, recipeID)
    if type(probe) ~= "table" or not probe.nodeHash then return nil end
    local stats = probe.nodeStats or {}
    return {
        multicraft = tonumber(stats.multicraft and stats.multicraft.rating) or 0,
        resourcefulness = tonumber(stats.resourcefulness and stats.resourcefulness.rating) or 0,
    }
end

-- A set is saved once per profession and stays authoritative until the user
-- saves it again. It stores the equipment identity plus the stats Blizzard
-- reported for the open recipe with ordinary reagents only.
function Gear.CaptureSet(snapshot, mode)
    local character, uid, cache = Cache.Ensure()
    local equipment = Gear.ReadEquipment(snapshot.recipeID, snapshot.profileKey)
    if not character or not equipment then return nil, "profession-equipment-unavailable" end
    if snapshot.gearStatContext ~= "base-reagents"
            or (snapshot.multiPercent == nil and snapshot.resPercent == nil) then
        return nil, "recipe-stats-unavailable"
    end
    local nodes = NodeRatings(character, snapshot.recipeID, snapshot.profileKey)
    local sets = character.professionGear[equipment.profession] or {}
    character.professionGear[equipment.profession] = sets
    local old = sets[mode]
    equipment.uid, equipment.mode = uid, mode
    equipment.revision = (old and old.revision or 0) + 1
    equipment.capturedAt = Cache.GetCurrentTimestamp()
    equipment.recipeID, equipment.profileKey = snapshot.recipeID, snapshot.profileKey
    equipment.stats = {
        multicraft = { percent = snapshot.multiPercent, rating = snapshot.multiRating,
            nodeRating = nodes and nodes.multicraft },
        resourcefulness = { percent = snapshot.resPercent, rating = snapshot.resRating,
            nodeRating = nodes and nodes.resourcefulness },
    }
    sets[mode] = equipment
    Cache.TouchRevision(character, cache)
    return equipment
end

-- Profession ratings convert to a chance linearly, so only the node part of
-- the captured rating is exchanged for the target recipe's node rating.
-- Without both node ratings and a rating, the captured chance is used as-is.
local function DeriveStat(entry, targetNodeRating)
    local percent = type(entry) == "table" and tonumber(entry.percent) or nil
    if percent == nil then return nil, false end
    local rating, captured = tonumber(entry.rating), tonumber(entry.nodeRating)
    if rating and rating > 0 and captured and targetNodeRating then
        return math.max(0, percent * (rating - captured + targetNodeRating) / rating), true
    end
    return percent, false
end

function Gear.RecipeStats(character, set, recipeID, profileKey)
    local nodes = NodeRatings(character, recipeID, profileKey)
    local stats = set.stats or {}
    local multi, multiScaled = DeriveStat(stats.multicraft, nodes and nodes.multicraft)
    local res, resScaled = DeriveStat(stats.resourcefulness, nodes and nodes.resourcefulness)
    local snapshot = {
        recipeID = recipeID, profileKey = profileKey, profession = set.profession,
        multiPercent = multi, resPercent = res, capturedAt = set.capturedAt,
        gearPreset = set.mode, source = "gear-set-" .. tostring(set.mode),
        gearStatScaling = (multiScaled or resScaled) and "node-scaled" or "profession-wide",
    }
    -- Recipe capability comes from this recipe's own capture, never the set's.
    local recipe = type(character.recipes) == "table" and character.recipes[tostring(recipeID)] or nil
    if type(recipe) == "table" then
        snapshot.supportsMulticraft = recipe.supportsMulticraft
        snapshot.supportsResourcefulness = recipe.supportsResourcefulness
    end
    return snapshot
end

function Gear.Requirement(character, recipeID, profileKey, mode)
    local set = Gear.GetSet(character, recipeID, profileKey, mode)
    if not set then return nil end
    return { uid = set.uid, profession = set.profession, mode = mode,
        signature = set.signature, slots = Cache.CopySerializableTable(set.slots) }
end

function Gear.IsEquipped(requirement, recipeID, profileKey)
    local _, uid = Cache.Ensure()
    if not requirement or uid ~= requirement.uid then return false end
    local equipment = Gear.ReadEquipment(recipeID, profileKey)
    return equipment and equipment.profession == requirement.profession
        and equipment.signature == requirement.signature or false
end
local GEAR_MODES = {
    auto = true,
    multicraft = true,
    resourcefulness = true,
}

function Gear.NormalizeMode(mode)
    mode = tostring(mode or "auto"):lower()
    return GEAR_MODES[mode] and mode or "auto"
end

function Gear.GetPreset(character, recipeID, profileKey, mode)
    mode = Gear.NormalizeMode(mode)
    if not Gear.Profession(recipeID, profileKey) then return nil end
    local set = Gear.GetSet(character, recipeID, profileKey, mode)
    if set then
        -- Sets saved before stats were stored must be saved again.
        if type(set.stats) ~= "table" then return nil end
        return Gear.RecipeStats(character, set, recipeID, profileKey)
    end
    if mode == "auto" or not recipeID or type(character) ~= "table"
            or type(character.gearPresets) ~= "table" then
        return nil
    end
    local recipePresets = character.gearPresets[tostring(recipeID)]
    local snapshot = type(recipePresets) == "table" and recipePresets[mode] or nil
    if type(snapshot) == "table"
            and (not snapshot.profileKey or not profileKey or snapshot.profileKey == profileKey) then
        return snapshot
    end
    return nil
end

function Gear.FindPresetCrafter(cache, currentUID, recipeID, profileKey, mode)
    if not recipeID or type(cache) ~= "table" or type(cache.characters) ~= "table" then
        return nil
    end
    local bestCharacter, bestUID, bestSnapshot, bestCapturedAt
    for uid, character in pairs(cache.characters) do
        if uid ~= currentUID and type(character) == "table" then
            local snapshot = Gear.GetPreset(character, recipeID, profileKey, mode)
            local capturedAt = snapshot and (tonumber(snapshot.capturedAt) or 0) or nil
            if snapshot and (not bestSnapshot
                    or capturedAt > bestCapturedAt
                    or (capturedAt == bestCapturedAt and tostring(uid) < tostring(bestUID))) then
                bestCharacter, bestUID, bestSnapshot, bestCapturedAt =
                    character, uid, snapshot, capturedAt
            end
        end
    end
    return bestCharacter, bestUID, bestSnapshot, bestCapturedAt
end

function Gear.GetModeForStrategy(strat, patchTag)
    local stratID = type(strat) == "table" and strat.id or nil
    local defaultPatch = GAM.C and GAM.C.DEFAULT_PATCH
    local patch = stratID and GAM.GetPatchDB and GAM:GetPatchDB(patchTag or defaultPatch) or nil
    return Gear.NormalizeMode(patch and patch.gearModes and patch.gearModes[stratID])
end

function Gear.SetModeForStrategy(strat, mode, patchTag)
    local stratID = type(strat) == "table" and strat.id or nil
    if not stratID then return false, "missing-strategy" end
    local defaultPatch = GAM.C and GAM.C.DEFAULT_PATCH
    local patch = GAM.GetPatchDB and GAM:GetPatchDB(patchTag or defaultPatch) or nil
    if not patch then return false, "no-db" end
    patch.gearModes = patch.gearModes or {}
    mode = Gear.NormalizeMode(mode)
    if patch.gearModes[stratID] ~= mode then
        patch.gearModes[stratID] = mode
        local character, _, cache = Cache.Ensure()
        Cache.TouchRevision(character, cache)
    end
    return true, mode
end
