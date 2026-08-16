-- Repeatable offline audit for the retained commodity recipe catalog.
-- Run from the addon directory: lua tools/audit_recipe_catalog.lua

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {}

function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
    return tbl
end

local function LoadGlobal(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk(ADDON_NAME, GAM)
end

local function LoadModule(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk(ADDON_NAME, GAM)
end

local professionNames = {
    "Alchemy",
    "Blacksmithing",
    "Cooking",
    "Enchanting",
    "Engineering",
    "Inscription",
    "Jewelcrafting",
    "Leatherworking",
    "Tailoring",
}

LoadGlobal("Data/WorkbookGenerated.lua")
LoadGlobal("Data/CommodityManifest.lua")
LoadGlobal("Data/ProfessionCrafts.lua")
for _, profession in ipairs(professionNames) do
    LoadGlobal("Data/Professions/" .. profession .. ".lua")
end
LoadGlobal("Data/ProfessionCraftsPatch12_1.lua")
for _, profession in ipairs(professionNames) do
    local path = "Data/SpecializationData/Midnight/" .. profession .. ".lua"
    local file = io.open(path, "r")
    if file then
        file:close()
        LoadGlobal(path)
    end
end

LoadModule("Constants.lua")
LoadModule("CommodityCatalog.lua")
LoadModule("StrategyModel.lua")

GAM.Log = {
    Info = function() end,
    Warn = function() end,
    Debug = function() end,
}
GAM.db = { userStrats = {} }

LoadGlobal("Data/StratsGenerated.lua")
LoadGlobal("Data/Strategies/Patch12_1.lua")
LoadModule("Importer.lua")
GAM.Importer.Init()

local function NormalizeName(value)
    return tostring(value or ""):lower():gsub("[^a-z0-9]", "")
end

local function SortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local compactByID = {}
for profession, crafts in pairs(GAM_PROFESSION_CRAFTS or {}) do
    for _, craft in ipairs(crafts or {}) do
        compactByID[craft.id] = compactByID[craft.id] or {}
        compactByID[craft.id][#compactByID[craft.id] + 1] = {
            profession = profession,
            craft = craft,
        }
    end
end

local issues = {}
local counts = {}
local function AddIssue(severity, code, strat, detail)
    counts[code] = (counts[code] or 0) + 1
    issues[#issues + 1] = {
        severity = severity,
        code = code,
        profession = strat and strat.profession or "-",
        id = strat and strat.id or "-",
        name = strat and strat.stratName or "-",
        detail = detail or "",
    }
end

local function IndexFacts(rows, quantityField)
    local result = {}
    for _, row in ipairs(rows or {}) do
        local key = NormalizeName(row.itemRef or row.name)
        if key ~= "" then
            result[key] = {
                name = row.itemRef or row.name,
                quantity = tonumber(row[quantityField]),
            }
        end
    end
    return result
end

local formulaProfiles = (GAM_WORKBOOK_GENERATED and GAM_WORKBOOK_GENERATED.formulaProfiles) or {}
local retained = GAM.Importer.GetAllStrats()

if arg and arg[1] == "--catalog-tsv" then
    local function JoinIDs(ids)
        local values = {}
        for _, itemID in ipairs(ids or {}) do
            values[#values + 1] = tostring(itemID)
        end
        return table.concat(values, ",")
    end
    local function Clean(value)
        return tostring(value or ""):gsub("[\t\r\n]", " ")
    end
    local function PrintRow(recordType, common, itemName, itemIDs, quantity)
        print(table.concat({
            recordType,
            common[1],
            common[2],
            common[3],
            common[4],
            common[5],
            common[6],
            itemName or "",
            itemIDs or "",
            quantity or "",
        }, "\t"))
    end

    print("record_type\tstrategy_id\tprofession\tstrategy_name\trecipe_id\trecipe_name\tprofile\titem_name\titem_ids\tquantity")
    for _, strat in ipairs(retained) do
        local common = {
            Clean(strat.id),
            Clean(strat.profession),
            Clean(strat.stratName),
            Clean(strat.recipeID),
            Clean(strat.recipeName),
            Clean(strat.statProfileKey),
        }
        PrintRow("strategy", common)
        for _, reagent in ipairs(strat.reagents or {}) do
            PrintRow(
                "reagent",
                common,
                Clean(reagent.itemRef or reagent.name),
                JoinIDs(reagent.itemIDs),
                Clean(reagent.quantityPerCraft))
        end
        for _, output in ipairs(strat.outputs or {}) do
            PrintRow(
                "output",
                common,
                Clean(output.itemRef or output.name),
                JoinIDs(output.itemIDs),
                Clean(output.baseYieldPerCraft))
        end
    end
    os.exit(0)
end

for _, strat in ipairs(retained) do
    if not strat.recipeID then
        AddIssue("error", "missing_recipe_id", strat, "No canonical recipe/spell ID")
    end
    if not strat.recipeName then
        AddIssue("warning", "missing_recipe_name", strat, "No canonical in-game recipe name")
    end
    if not strat.statProfileKey or not formulaProfiles[strat.statProfileKey] then
        AddIssue("error", "missing_stat_profile", strat,
            "Unknown profile " .. tostring(strat.statProfileKey or "nil"))
    end

    local compactRows = compactByID[strat.id]
    if not compactRows or #compactRows == 0 then
        AddIssue("warning", "missing_compact_fact", strat, "No matching profession craft fact")
    elseif #compactRows > 1 then
        AddIssue("error", "duplicate_compact_fact", strat,
            tostring(#compactRows) .. " profession craft facts share this ID")
    else
        local compact = compactRows[1].craft
        if tonumber(compact.recipeID) ~= tonumber(strat.recipeID) then
            AddIssue("error", "recipe_id_crossfile_mismatch", strat,
                string.format("profession=%s runtime=%s",
                    tostring(compact.recipeID), tostring(strat.recipeID)))
        end
        if compact.formulaProfile ~= strat.statProfileKey then
            AddIssue("error", "profile_crossfile_mismatch", strat,
                string.format("profession=%s runtime=%s",
                    tostring(compact.formulaProfile), tostring(strat.statProfileKey)))
        end

        local compactInputs = IndexFacts(compact.inputs, "amount")
        local runtimeInputs = IndexFacts(strat.reagents, "quantityPerCraft")
        for key, fact in pairs(compactInputs) do
            local runtime = runtimeInputs[key]
            if not runtime then
                AddIssue("error", "reagent_crossfile_missing", strat,
                    tostring(fact.name) .. " missing from runtime strategy")
            elseif fact.quantity ~= runtime.quantity then
                AddIssue("error", "reagent_quantity_crossfile_mismatch", strat,
                    string.format("%s profession=%s runtime=%s",
                        tostring(fact.name), tostring(fact.quantity), tostring(runtime.quantity)))
            end
        end
        for key, fact in pairs(runtimeInputs) do
            if not compactInputs[key] then
                AddIssue("error", "reagent_compact_missing", strat,
                    tostring(fact.name) .. " missing from profession facts")
            end
        end

        local compactOutputs = IndexFacts(compact.outputs, "baseAmount")
        local runtimeOutputs = IndexFacts(strat.outputs, "baseYieldPerCraft")
        for key, fact in pairs(compactOutputs) do
            local runtime = runtimeOutputs[key]
            if not runtime then
                AddIssue("error", "output_crossfile_missing", strat,
                    tostring(fact.name) .. " missing from runtime strategy")
            elseif fact.quantity ~= runtime.quantity then
                AddIssue("error", "output_yield_crossfile_mismatch", strat,
                    string.format("%s profession=%s runtime=%s",
                        tostring(fact.name), tostring(fact.quantity), tostring(runtime.quantity)))
            end
        end
    end

    local specialization = GAM_SPECIALIZATION_DATA
        and GAM_SPECIALIZATION_DATA.MIDNIGHT
        and GAM_SPECIALIZATION_DATA.MIDNIGHT[strat.profession]
    if strat.recipeID and specialization and specialization.recipeScoped then
        local mapping = specialization.recipeMapping or {}
        if not mapping[strat.recipeID] and not mapping[tostring(strat.recipeID)] then
            AddIssue("warning", "missing_specialization_mapping", strat,
                "Recipe ID is absent from the CraftSim-derived specialization map")
        end
    end
end

table.sort(issues, function(a, b)
    if a.severity ~= b.severity then return a.severity < b.severity end
    if a.profession ~= b.profession then return a.profession < b.profession end
    if a.code ~= b.code then return a.code < b.code end
    return a.id < b.id
end)

print("Gold Advisor Midnight retained recipe audit")
print(string.format("retained=%d issues=%d", #retained, #issues))
print("")
print("Issue counts:")
for _, code in ipairs(SortedKeys(counts)) do
    print(string.format("  %-38s %d", code, counts[code]))
end
print("")
print("severity\tcode\tprofession\tstrategy_id\tstrategy_name\tdetail")
for _, issue in ipairs(issues) do
    print(table.concat({
        issue.severity,
        issue.code,
        issue.profession,
        issue.id,
        issue.name,
        (issue.detail:gsub("[\t\r\n]", " ")),
    }, "\t"))
end

if #issues > 0 then
    os.exit(1)
end
