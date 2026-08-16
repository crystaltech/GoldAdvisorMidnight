-- GoldAdvisorMidnight/RecipeAudit.lua
-- Read-only comparison of retained commodity strategies against live WoW schematics.
-- Module: GAM.RecipeAudit

local ADDON_NAME, GAM = ...
local Audit = {}
GAM.RecipeAudit = Audit

local EPSILON = 0.000001

local function NormalizeName(value)
    local text = tostring(value or ""):lower()
    text = text:gsub("[‘’´`]", "'")
    return text:gsub("[^a-z0-9]", "")
end

local function ContainsValue(values, wanted)
    for _, value in ipairs(values or {}) do
        if tonumber(value) == tonumber(wanted) then
            return true
        end
    end
    return false
end

local function Intersects(left, right)
    for _, value in ipairs(left or {}) do
        if ContainsValue(right, value) then
            return true
        end
    end
    return false
end

local function JoinNumbers(values)
    local result = {}
    for _, value in ipairs(values or {}) do
        result[#result + 1] = tostring(value)
    end
    table.sort(result)
    return table.concat(result, ",")
end

local function GetCatalogReagents(strat)
    local result = {}
    for _, reagent in ipairs(strat and strat.reagents or {}) do
        local itemIDs = {}
        for _, itemID in ipairs(reagent.itemIDs or {}) do
            if tonumber(itemID) then
                itemIDs[#itemIDs + 1] = tonumber(itemID)
            end
        end
        if #itemIDs > 0 then
            result[#result + 1] = {
                name = reagent.itemRef or reagent.name or "Reagent",
                itemIDs = itemIDs,
                quantity = tonumber(reagent.quantityPerCraft or reagent.qtyPerCraft),
            }
        end
    end
    return result
end

local function AddCatalogOutput(result, seen, output)
    if type(output) ~= "table" then return end
    for _, itemID in ipairs(output.itemIDs or {}) do
        itemID = tonumber(itemID)
        if itemID and not seen[itemID] then
            seen[itemID] = true
            result[#result + 1] = itemID
        end
    end
end

local function GetCatalogOutputIDs(strat)
    local result, seen = {}, {}
    for _, output in ipairs(strat and strat.outputs or {}) do
        AddCatalogOutput(result, seen, output)
    end
    AddCatalogOutput(result, seen, strat and strat.output)
    for _, variant in pairs(strat and strat.rankVariants or {}) do
        for _, output in ipairs(variant.outputs or {}) do
            AddCatalogOutput(result, seen, output)
        end
        AddCatalogOutput(result, seen, variant.output)
    end
    table.sort(result)
    return result
end

local function GetCatalogBaseYield(strat)
    local output = strat and ((strat.outputs and strat.outputs[1]) or strat.output)
    return output and tonumber(output.baseYieldPerCraft or output.baseYield) or nil
end

local function IsRegularRequiredSlot(slot, enumTable)
    if type(slot) ~= "table" then return false end
    local crafting = enumTable and enumTable.CraftingReagentType or {}
    local slotData = enumTable and enumTable.TradeskillSlotDataType or {}
    local basic = crafting.Basic
    local modifying = crafting.Modifying
    local reagentData = slotData.Reagent
    local modifiedData = slotData.ModifiedReagent

    if modifying ~= nil and slot.reagentType == modifying then
        return slot.required == true
    end
    if basic ~= nil and slot.reagentType == basic then
        if slot.dataSlotType == nil or (reagentData == nil and modifiedData == nil) then
            return true
        end
        return slot.dataSlotType == reagentData or slot.dataSlotType == modifiedData
    end

    -- Numeric fallback retained by CraftSim for clients where Enum is unavailable.
    return tonumber(slot.reagentType) == 1
end

local function GetLiveRequiredSlots(schematic, enumTable)
    local result = {}
    for _, slot in pairs(schematic and schematic.reagentSlotSchematics or {}) do
        if IsRegularRequiredSlot(slot, enumTable) then
            local itemIDs = {}
            for _, reagent in pairs(slot.reagents or {}) do
                local itemID = tonumber(reagent.itemID)
                if itemID then itemIDs[#itemIDs + 1] = itemID end
            end
            table.sort(itemIDs)
            if #itemIDs > 0 then
                result[#result + 1] = {
                    itemIDs = itemIDs,
                    quantity = tonumber(slot.quantityRequired),
                    dataSlotIndex = slot.dataSlotIndex,
                }
            end
        end
    end
    return result
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil, "api unavailable" end
    local ok, value = pcall(fn, ...)
    if not ok then return nil, tostring(value) end
    return value, nil
end

local function GetDefaultDependencies()
    return {
        enum = Enum,
        getRecipeInfo = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo,
        getRecipeSchematic = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic,
        getChildProfessionInfo = C_TradeSkillUI and C_TradeSkillUI.GetChildProfessionInfo,
        getBaseProfessionInfo = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo,
        resolveStats = GAM.CraftingStatsV2 and GAM.CraftingStatsV2.ResolveForStrat,
        options = (GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {},
    }
end

local function GetProfessionByEnum(professionEnum, enumTable)
    if professionEnum == nil then return nil end
    for _, definition in ipairs((GAM.C and GAM.C.PROFESSION_REGISTRY) or {}) do
        local expected = enumTable
            and enumTable.Profession
            and enumTable.Profession[definition.enumName]
        if expected ~= nil and expected == professionEnum then
            return definition.name
        end
    end
    return nil
end

local function GetProfessionByName(name)
    local normalized = NormalizeName(name)
    if normalized == "" then return nil end
    for _, definition in ipairs((GAM.C and GAM.C.PROFESSION_REGISTRY) or {}) do
        if NormalizeName(definition.name) == normalized then
            return definition.name
        end
    end
    return nil
end

function Audit.GetOpenProfessionName(deps)
    deps = deps or GetDefaultDependencies()
    local child = SafeCall(deps.getChildProfessionInfo)
    local base = SafeCall(deps.getBaseProfessionInfo)
    local info = child or base
    if not info then return nil end
    return GetProfessionByEnum(info.profession, deps.enum)
        or GetProfessionByName(info.professionName or info.name or info.skillLineName)
end

local function AddFinding(row, code, detail)
    row.findings[#row.findings + 1] = {
        code = code,
        detail = detail,
    }
end

local function ResolveStatAudit(strat, deps)
    local resolved = SafeCall(deps.resolveStats, strat, deps.options)
    if type(resolved) ~= "table" then
        return "unavailable", "-", false, false
    end
    local source = tostring(resolved.statSource or resolved.source or "unknown")
    if resolved.fallbackReason then
        source = source .. "(" .. tostring(resolved.fallbackReason) .. ")"
    end
    local exact = tonumber(resolved.recipeID) == tonumber(strat.recipeID)
        and (source:find("craftsim", 1, true) ~= nil or source:find("native", 1, true) ~= nil)
    return exact and "exact" or "fallback",
        source,
        resolved.supportsMulticraft and true or false,
        resolved.supportsResourcefulness and true or false
end

local function AuditOne(strat, deps)
    local row = {
        strategyID = strat.id,
        strategyName = strat.stratName,
        profession = strat.profession,
        recipeID = tonumber(strat.recipeID),
        recipeName = strat.recipeName,
        findings = {},
        status = "PASS",
        learned = nil,
        schematic = false,
        statStatus = "unavailable",
        statSource = "-",
        supportsMulticraft = false,
        supportsResourcefulness = false,
    }

    if not row.recipeID then
        row.status = "UNAVAILABLE"
        AddFinding(row, "missing_recipe_id",
            strat._isUser and "user strategy has no canonical recipe ID"
                or "strategy has no canonical recipe ID")
        return row
    end

    local recipeInfo, infoError = SafeCall(deps.getRecipeInfo, row.recipeID)
    local schematic, schematicError = SafeCall(deps.getRecipeSchematic, row.recipeID, false)
    row.recipeInfo = type(recipeInfo) == "table" and recipeInfo or nil
    row.learned = row.recipeInfo and row.recipeInfo.learned

    if type(schematic) ~= "table" then
        row.status = "UNAVAILABLE"
        AddFinding(row, "schematic_unavailable", schematicError or infoError or "no schematic returned")
        return row
    end
    row.schematic = true

    if row.recipeInfo and row.recipeInfo.name
            and NormalizeName(row.recipeInfo.name) ~= NormalizeName(row.recipeName) then
        AddFinding(row, "recipe_name", string.format("live=%s catalog=%s",
            tostring(row.recipeInfo.name), tostring(row.recipeName)))
    end
    if schematic.recipeID and tonumber(schematic.recipeID) ~= row.recipeID then
        AddFinding(row, "recipe_id", string.format("live=%s catalog=%s",
            tostring(schematic.recipeID), tostring(row.recipeID)))
    end

    local catalogReagents = GetCatalogReagents(strat)
    local isSalvage = row.recipeInfo and row.recipeInfo.isSalvageRecipe == true
    if isSalvage then
        local liveQuantity = tonumber(schematic.quantityMax)
        local catalogQuantity = catalogReagents[1] and catalogReagents[1].quantity or nil
        if liveQuantity and catalogQuantity and math.abs(liveQuantity - catalogQuantity) > EPSILON then
            AddFinding(row, "salvage_quantity", string.format("live=%s catalog=%s",
                tostring(liveQuantity), tostring(catalogQuantity)))
        end
    else
        local liveSlots = GetLiveRequiredSlots(schematic, deps.enum)
        local matchedCatalog = {}
        for _, liveSlot in ipairs(liveSlots) do
            local matchedIndex = nil
            for index, catalog in ipairs(catalogReagents) do
                if Intersects(liveSlot.itemIDs, catalog.itemIDs) then
                    matchedIndex = index
                    matchedCatalog[index] = true
                    if liveSlot.quantity and catalog.quantity
                            and math.abs(liveSlot.quantity - catalog.quantity) > EPSILON then
                        AddFinding(row, "reagent_quantity", string.format(
                            "%s [%s] live=%s catalog=%s",
                            tostring(catalog.name), JoinNumbers(catalog.itemIDs),
                            tostring(liveSlot.quantity), tostring(catalog.quantity)))
                    end
                    break
                end
            end
            if not matchedIndex then
                AddFinding(row, "catalog_missing_reagent", string.format("live items=[%s] x%s",
                    JoinNumbers(liveSlot.itemIDs), tostring(liveSlot.quantity or "?")))
            end
        end
        for index, catalog in ipairs(catalogReagents) do
            if not matchedCatalog[index] then
                AddFinding(row, "live_missing_reagent", string.format("%s [%s] x%s",
                    tostring(catalog.name), JoinNumbers(catalog.itemIDs),
                    tostring(catalog.quantity or "?")))
            end
        end
    end

    local outputIDs = GetCatalogOutputIDs(strat)
    local liveOutputID = tonumber(schematic.outputItemID)
    -- Salvage/processing schematics expose a placeholder or currently selected
    -- result item rather than the probabilistic output distribution. Those IDs
    -- are not comparable to the strategy's commodity output set.
    if not isSalvage and liveOutputID and liveOutputID > 0
            and not ContainsValue(outputIDs, liveOutputID) then
        AddFinding(row, "output_item", string.format("live=%s catalog=[%s]",
            tostring(liveOutputID), JoinNumbers(outputIDs)))
    end

    local catalogYield = GetCatalogBaseYield(strat)
    local minYield = tonumber(schematic.quantityMin)
    local maxYield = tonumber(schematic.quantityMax)
    if not isSalvage and #(strat.outputs or {}) <= 1 and catalogYield and minYield and maxYield then
        local liveYield = (minYield + maxYield) / 2
        if math.abs(liveYield - catalogYield) > EPSILON then
            AddFinding(row, "base_yield", string.format("live=%s-%s avg=%s catalog=%s",
                tostring(minYield), tostring(maxYield), tostring(liveYield), tostring(catalogYield)))
        end
    end

    row.statStatus, row.statSource, row.supportsMulticraft, row.supportsResourcefulness =
        ResolveStatAudit(strat, deps)

    if #row.findings > 0 then
        row.status = "MISMATCH"
    elseif row.learned == false then
        row.status = "UNLEARNED"
    end
    return row
end

function Audit.AuditStrategies(strategies, deps, scope)
    deps = deps or GetDefaultDependencies()
    local result = {
        scope = scope or "custom",
        rows = {},
        counts = { PASS = 0, MISMATCH = 0, UNAVAILABLE = 0, UNLEARNED = 0 },
        exactStats = 0,
        fallbackStats = 0,
        uniqueRecipes = 0,
    }
    local recipeIDs = {}
    for _, strat in ipairs(strategies or {}) do
        local row = AuditOne(strat, deps)
        result.rows[#result.rows + 1] = row
        result.counts[row.status] = (result.counts[row.status] or 0) + 1
        if row.statStatus == "exact" then
            result.exactStats = result.exactStats + 1
        elseif row.statStatus == "fallback" then
            result.fallbackStats = result.fallbackStats + 1
        end
        if row.recipeID then recipeIDs[row.recipeID] = true end
    end
    for _ in pairs(recipeIDs) do result.uniqueRecipes = result.uniqueRecipes + 1 end
    table.sort(result.rows, function(a, b)
        if a.status ~= b.status then return a.status < b.status end
        if a.profession ~= b.profession then return a.profession < b.profession end
        return tostring(a.strategyName) < tostring(b.strategyName)
    end)
    return result
end

local function FindingsText(row)
    local parts = {}
    for _, finding in ipairs(row.findings or {}) do
        parts[#parts + 1] = tostring(finding.code) .. ":" .. tostring(finding.detail)
    end
    return #parts > 0 and table.concat(parts, "; ") or "-"
end

function Audit.BuildReport(result)
    local counts = result.counts or {}
    local lines = {
        "Gold Advisor Midnight Live Recipe Audit",
        "scope=" .. tostring(result.scope),
        string.format("strategies=%d uniqueRecipes=%d pass=%d mismatch=%d unavailable=%d unlearned=%d exactStats=%d fallbackStats=%d",
            #(result.rows or {}),
            tonumber(result.uniqueRecipes) or 0,
            tonumber(counts.PASS) or 0,
            tonumber(counts.MISMATCH) or 0,
            tonumber(counts.UNAVAILABLE) or 0,
            tonumber(counts.UNLEARNED) or 0,
            tonumber(result.exactStats) or 0,
            tonumber(result.fallbackStats) or 0),
        "",
        "status\tprofession\tstrategy\trecipeID\tlearned\tstats\tmc\tres\tdetail",
    }
    for _, row in ipairs(result.rows or {}) do
        lines[#lines + 1] = table.concat({
            tostring(row.status),
            tostring(row.profession or "-"),
            tostring(row.strategyName or row.strategyID or "-"),
            tostring(row.recipeID or "-"),
            row.learned == nil and "?" or tostring(row.learned),
            tostring(row.statStatus) .. ":" .. tostring(row.statSource or "-"),
            row.supportsMulticraft and "yes" or "no",
            row.supportsResourcefulness and "yes" or "no",
            FindingsText(row),
        }, "\t")
    end
    return table.concat(lines, "\n")
end

local function PrintSummary(result)
    local counts = result.counts
    local message = string.format(
        "Recipe audit %s: %d strategies (%d recipes) — %d pass, %d mismatch, %d unavailable, %d unlearned; exact stats %d, fallback %d.",
        tostring(result.scope), #(result.rows or {}), result.uniqueRecipes or 0,
        counts.PASS or 0, counts.MISMATCH or 0, counts.UNAVAILABLE or 0,
        counts.UNLEARNED or 0, result.exactStats or 0, result.fallbackStats or 0)
    print("|cffff8800[GAM]|r " .. message)
    if GAM.Log and GAM.Log.Info then GAM.Log.Info(message) end
    for _, row in ipairs(result.rows or {}) do
        if row.status == "MISMATCH" or row.status == "UNAVAILABLE" then
            if GAM.Log and GAM.Log.Warn then
                GAM.Log.Warn("RecipeAudit: %s recipeID=%s status=%s %s",
                    tostring(row.strategyName), tostring(row.recipeID),
                    tostring(row.status), FindingsText(row))
            end
        end
    end
end

function Audit.Run(args)
    if not (GAM.Importer and GAM.Importer.GetAllStrats) then
        print("|cffff8800[GAM]|r Recipe audit unavailable: importer not ready.")
        return nil, "importer not ready"
    end

    local deps = GetDefaultDependencies()
    local choice = tostring(args or ""):lower():match("^%s*(%S*)") or ""
    local scope = "all"
    local strategies = GAM.Importer.GetAllStrats()
    if choice ~= "all" then
        local profession = Audit.GetOpenProfessionName(deps)
        if not profession then
            print("|cffff8800[GAM]|r Open a supported profession before running the live recipe audit harness.")
            return nil, "no supported profession open"
        end
        scope = profession
        strategies = GAM.Importer.GetStratsByProfession(profession)
    end

    local result = Audit.AuditStrategies(strategies, deps, scope)
    Audit.lastResult = result
    Audit.lastReport = Audit.BuildReport(result)
    PrintSummary(result)

    if GAM.UI and GAM.UI.DebugLog and GAM.UI.DebugLog.ShowTextExport then
        GAM.UI.DebugLog.ShowTextExport("Recipe Audit - " .. scope, Audit.lastReport)
    elseif GAM.UI and GAM.UI.DebugLog and GAM.UI.DebugLog.Show then
        GAM.UI.DebugLog.Show()
    end
    return result
end

function Audit.GetLastReport()
    return Audit.lastReport
end
