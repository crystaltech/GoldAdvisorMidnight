-- Compare GAM's reduced pricing-node catalog with a local CraftSim checkout.
-- Usage: lua tools/audit_specialization_catalog.lua [CraftSim root]

local craftSimRoot = arg[1] or "tmp/CraftSim-audit"
local professions = {
    "Alchemy",
    "Blacksmithing",
    "Enchanting",
    "Engineering",
    "Inscription",
    "Jewelcrafting",
    "Leatherworking",
    "Tailoring",
}
local hiddenStats = {
    additionalitemscraftedwithmulticraft = true,
    reagentssavedfromresourcefulness = true,
}

local function Load(path, addonTable)
    local chunk = assert(loadfile(path))
    return chunk("Audit", addonTable)
end

local GAM = { C = { PROFESSION_REGISTRY = {} } }
for _, profession in ipairs(professions) do
    Load("GoldAdvisorMidnightDev/Data/SpecializationData/Midnight/" .. profession .. ".lua", GAM)
end

local CraftSim = { SPECIALIZATION_DATA = { MIDNIGHT = {} } }
for _, profession in ipairs(professions) do
    Load(craftSimRoot .. "/Data/SpecializationData/Midnight/" .. profession .. ".lua", CraftSim)
end

local function HasHiddenStat(node)
    for key in pairs((node and node.stats) or {}) do
        if hiddenStats[key] then return true end
    end
    return false
end

local function SetFromList(list, nodeData, hiddenOnly)
    local out = {}
    for _, nodeID in ipairs(list or {}) do
        if not hiddenOnly or HasHiddenStat(nodeData and nodeData[nodeID]) then
            out[tonumber(nodeID) or nodeID] = true
        end
    end
    return out
end

local function SameSet(a, b)
    for key in pairs(a) do if not b[key] then return false end end
    for key in pairs(b) do if not a[key] then return false end end
    return true
end

local errors = {}
for _, profession in ipairs(professions) do
    local upstream = CraftSim.SPECIALIZATION_DATA.MIDNIGHT[profession:upper() .. "_DATA"]
    local catalog = GAM.SpecializationData.MIDNIGHT[profession]
    assert(upstream and catalog, profession .. ": specialization data missing")

    local upstreamAll, upstreamHidden, localAll, localHidden = 0, 0, 0, 0
    local omittedStatKinds = {}
    for nodeID, node in pairs(upstream.nodeData or {}) do
        upstreamAll = upstreamAll + 1
        if HasHiddenStat(node) then
            upstreamHidden = upstreamHidden + 1
            local localNode = catalog.nodes and catalog.nodes[nodeID]
            if not localNode then
                errors[#errors + 1] = profession .. ": missing pricing-hidden node " .. tostring(nodeID)
            else
                for statKey, value in pairs(node.stats or {}) do
                    if hiddenStats[statKey] and tonumber(localNode.stats and localNode.stats[statKey]) ~= tonumber(value) then
                        errors[#errors + 1] = profession .. ": hidden stat mismatch for node " .. tostring(nodeID)
                    end
                end
            end
        elseif not (catalog.nodes and catalog.nodes[nodeID]) then
            for statKey in pairs(node.stats or {}) do omittedStatKinds[statKey] = true end
        end
    end
    for _, node in pairs(catalog.nodes or {}) do
        localAll = localAll + 1
        if HasHiddenStat(node) then localHidden = localHidden + 1 end
    end

    for recipeID, localMapping in pairs(catalog.recipeMapping or {}) do
        local upstreamMapping = upstream.recipeMapping and upstream.recipeMapping[recipeID]
        if upstreamMapping then
            local expected = SetFromList(upstreamMapping, upstream.nodeData, true)
            local actual = SetFromList(localMapping, catalog.nodes, true)
            if not SameSet(expected, actual) then
                errors[#errors + 1] = profession .. ": hidden-node recipe mapping mismatch " .. tostring(recipeID)
            end
        end
    end

    local omitted = {}
    for statKey in pairs(omittedStatKinds) do omitted[#omitted + 1] = statKey end
    table.sort(omitted)
    print(string.format(
        "%s: upstream=%d local=%d hidden=%d/%d omitted-stat-kinds=%s",
        profession,
        upstreamAll,
        localAll,
        localHidden,
        upstreamHidden,
        (#omitted > 0 and table.concat(omitted, ",") or "none")))
end

if #errors > 0 then
    for _, message in ipairs(errors) do print("ERROR: " .. message) end
    error(string.format("specialization audit failed with %d error(s)", #errors))
end

print("PASS: every CraftSim pricing-hidden node and recipe mapping is represented")
