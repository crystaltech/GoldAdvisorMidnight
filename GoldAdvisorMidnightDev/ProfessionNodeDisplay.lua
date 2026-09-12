-- GoldAdvisorMidnight/ProfessionNodeDisplay.lua
-- Resolves localized Blizzard profession-path metadata without owning rank math.
-- Module: GAM.ProfessionNodeDisplay

local ADDON_NAME, GAM = ...

local Display = {}
GAM.ProfessionNodeDisplay = Display

-- Stable English fallbacks for catalog IDs that are also public profession
-- trait IDs. Blizzard's localized name always wins once the profession opens.
local FALLBACK_NAMES = {
    [104289] = "Prolific Worker",
    [104290] = "Resourceful Smith",
    [104292] = "The Old Ways",
    [104386] = "Textile Utilization",
    [104389] = "Creative Efficiency",
    [106277] = "Dextrous Diligence",
    [106278] = "Keen Eye",
    [106280] = "Calm Hands",
    [106752] = "Resourcefulness",
    [106753] = "Multicraft",
    [107013] = "Outrageous Output",
    [107014] = "Skilled Savings",
    [107101] = "Prolific Potioneer - Void",
    [107104] = "Prolific Potioneer - Light",
    [107208] = "Phial Abundance",
    [107211] = "Flask Abundance",
    [107254] = "Metamorphic Mastery",
    [107614] = "Multicrafting Meticulously",
    [107616] = "Responsible Resources",
    [107918] = "Mastering Multicraft",
    [107920] = "Waning Waste",
}

function Display.GetFallbackName(nodeID)
    return FALLBACK_NAMES[tonumber(nodeID)]
end

local function NonEmptyText(value)
    if type(value) ~= "string" then
        return nil
    end
    local trimmed = value:match("^%s*(.-)%s*$")
    return trimmed ~= "" and trimmed or nil
end

local function AddUniqueID(target, seen, value)
    local id = tonumber(value)
    if id and not seen[id] then
        seen[id] = true
        target[#target + 1] = id
    end
end

local function GetSpellName(spellAPI, spellID)
    if not (spellAPI and spellID) then
        return nil
    end
    if type(spellAPI.GetSpellInfo) == "function" then
        local ok, info = pcall(spellAPI.GetSpellInfo, spellID)
        if ok then
            if type(info) == "table" then
                return NonEmptyText(info.name)
            end
            return NonEmptyText(info)
        end
    end
    if type(spellAPI.GetSpellName) == "function" then
        local ok, name = pcall(spellAPI.GetSpellName, spellID)
        if ok then
            return NonEmptyText(name)
        end
    end
    return nil
end

function Display.ResolveLiveNodeInfo(configID, nodeID, nodeInfo, apis)
    apis = apis or {}
    local profSpecs = apis.profSpecs or C_ProfSpecs
    local traits = apis.traits or C_Traits
    local spells = apis.spells or C_Spell
    if not (traits and type(traits.GetEntryInfo) == "function"
            and type(traits.GetDefinitionInfo) == "function") then
        return nil
    end

    local entryIDs, seen = {}, {}
    if profSpecs and type(profSpecs.GetSpendEntryForPath) == "function" then
        local ok, entryID = pcall(profSpecs.GetSpendEntryForPath, nodeID)
        if ok then AddUniqueID(entryIDs, seen, entryID) end
    end
    AddUniqueID(entryIDs, seen, nodeInfo and nodeInfo.activeEntry and nodeInfo.activeEntry.entryID)
    AddUniqueID(entryIDs, seen, nodeInfo and nodeInfo.nextEntry and nodeInfo.nextEntry.entryID)
    for _, entryID in ipairs((nodeInfo and nodeInfo.entryIDs) or {}) do
        AddUniqueID(entryIDs, seen, entryID)
    end
    if profSpecs and type(profSpecs.GetUnlockEntryForPath) == "function" then
        local ok, entryID = pcall(profSpecs.GetUnlockEntryForPath, nodeID)
        if ok then AddUniqueID(entryIDs, seen, entryID) end
    end

    local resolved = {
        nodeID = tonumber(nodeID) or nodeID,
        source = "blizzard",
    }
    for _, entryID in ipairs(entryIDs) do
        local okEntry, entryInfo = pcall(traits.GetEntryInfo, configID, entryID)
        if okEntry and type(entryInfo) == "table" and entryInfo.definitionID then
            local okDefinition, definitionInfo = pcall(traits.GetDefinitionInfo, entryInfo.definitionID)
            if okDefinition and type(definitionInfo) == "table" then
                local name = NonEmptyText(definitionInfo.overrideName)
                    or GetSpellName(spells, definitionInfo.overriddenSpellID or definitionInfo.spellID)
                if name then
                    resolved.name = name
                    resolved.entryID = entryID
                    resolved.definitionID = entryInfo.definitionID
                    resolved.description = NonEmptyText(definitionInfo.overrideDescription)
                    break
                end
            end
        end
    end

    if profSpecs and type(profSpecs.GetDescriptionForPath) == "function" then
        local ok, description = pcall(profSpecs.GetDescriptionForPath, nodeID)
        if ok then
            resolved.description = NonEmptyText(description) or resolved.description
        end
    end

    if not resolved.name and not resolved.description then
        return nil
    end
    return resolved
end

function Display.BuildImpactText(row)
    local stats = row and row.stats or {}
    local parts = {}
    local function Add(label, value, suffix)
        local number = tonumber(value)
        if number then
            parts[#parts + 1] = string.format("%s +%g%s per rank", label, number, suffix or "")
        end
    end
    Add("Multicraft extra items", stats.additionalitemscraftedwithmulticraft, "%")
    Add("Resourcefulness savings", stats.reagentssavedfromresourcefulness, "%")
    Add("Multicraft rating", stats.multicraft)
    Add("Resourcefulness rating", stats.resourcefulness)
    Add("Profession skill", stats.skill)
    if #parts == 0 then
        return "Used by this profession's pricing profile."
    end
    return table.concat(parts, "; ") .. "."
end

return Display
