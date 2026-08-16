-- GoldAdvisorMidnight/StrategyModel.lua
-- Canonical recipe normalization and rank-variant resolution.
-- Module: GAM.StrategyModel

local ADDON_NAME, GAM = ...
local Model = {}
GAM.StrategyModel = Model

Model.SCHEMA_VERSION = 1

local function NormStr(value)
    return (value or ""):lower():gsub("[^a-z0-9]", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
end

local function MakeID(profession, name, patchTag)
    return NormStr(profession) .. "__" .. NormStr(name) .. "__" .. NormStr(patchTag)
end

local function GetItemCatalog()
    return (GAM_WORKBOOK_GENERATED and GAM_WORKBOOK_GENERATED.itemCatalog) or {}
end

local function CopyIDs(ids)
    local out = {}
    if type(ids) == "table" then
        for _, itemID in ipairs(ids) do
            itemID = tonumber(itemID)
            if itemID and itemID > 0 then
                out[#out + 1] = itemID
            end
        end
    end
    return out
end

local function ResolveIDs(itemRef, ids)
    local resolved = CopyIDs(ids)
    if #resolved == 0 and itemRef then
        resolved = CopyIDs(GetItemCatalog()[itemRef])
    end
    return resolved
end

local function ResolveOutputIDs(itemRef, ids)
    local resolved = ResolveIDs(itemRef, ids)
    local catalog = GAM.CommodityCatalog
    if not (catalog and catalog.FilterItemIDs) then
        return {}
    end
    return catalog.FilterItemIDs(resolved)
end

local function PositiveNumber(value, fallback)
    value = tonumber(value)
    if not value or value <= 0 then
        return fallback
    end
    return value
end

local function NormalizeCheapestOf(list)
    if type(list) ~= "table" then
        return nil
    end

    local normalized = {}
    for _, alternative in ipairs(list) do
        if type(alternative) == "table" then
            local itemRef = alternative.itemRef or alternative.name
            local itemIDs = ResolveIDs(itemRef, alternative.itemIDs)
            if itemRef or #itemIDs > 0 then
                normalized[#normalized + 1] = {
                    itemRef = itemRef,
                    name = itemRef, -- Compatibility until display consumers use itemRef.
                    itemIDs = itemIDs,
                }
            end
        end
    end
    return (#normalized > 0) and normalized or nil
end

local function NormalizeOutput(raw, startingAmount, defaultCrafts)
    if type(raw) ~= "table" then
        return nil, "output is not a table"
    end

    local itemRef = raw.itemRef or raw.name
    local itemIDs = ResolveOutputIDs(itemRef, raw.itemIDs)
    if #itemIDs == 0 then
        return nil, "output has no commodity item IDs"
    end

    local baseYieldPerCraft = tonumber(raw.baseYieldPerCraft) or tonumber(raw.baseAmount)
    local legacyBaseYield = tonumber(raw.baseYield)
        or tonumber(raw.baseYieldMultiplier)
        or tonumber(raw.qtyMultiplier)
    if not baseYieldPerCraft and legacyBaseYield then
        baseYieldPerCraft = (legacyBaseYield * startingAmount) / defaultCrafts
    end
    if not legacyBaseYield and baseYieldPerCraft then
        legacyBaseYield = (baseYieldPerCraft * defaultCrafts) / startingAmount
    end
    if not baseYieldPerCraft or baseYieldPerCraft < 0 or not legacyBaseYield or legacyBaseYield < 0 then
        return nil, "output has no valid yield"
    end

    return {
        itemRef = itemRef,
        name = itemRef, -- Compatibility alias.
        itemIDs = itemIDs,
        baseYieldPerCraft = baseYieldPerCraft,
        -- Compatibility aliases retained at the boundary while pricing is consolidated.
        baseYield = legacyBaseYield,
        baseYieldMultiplier = legacyBaseYield,
        qtyMultiplier = legacyBaseYield,
        workbookExpectedQty = tonumber(raw.workbookExpectedQty),
    }
end

local function NormalizeReagent(raw, startingAmount, defaultCrafts)
    if type(raw) ~= "table" then
        return nil, "reagent is not a table"
    end

    local itemRef = raw.itemRef or raw.name
    local itemIDs = ResolveIDs(itemRef, raw.itemIDs)
    local quantityPerCraft = tonumber(raw.quantityPerCraft) or tonumber(raw.qtyPerCraft)
    local quantityPerStart = tonumber(raw.qtyPerStart) or tonumber(raw.qtyMultiplier)
    if not quantityPerCraft and quantityPerStart then
        quantityPerCraft = (quantityPerStart * startingAmount) / defaultCrafts
    end
    if not quantityPerStart and quantityPerCraft then
        quantityPerStart = (quantityPerCraft * defaultCrafts) / startingAmount
    end
    if not quantityPerCraft or quantityPerCraft < 0 or not quantityPerStart or quantityPerStart < 0 then
        return nil, "reagent has no valid quantity"
    end

    return {
        itemRef = itemRef,
        name = itemRef, -- Compatibility alias.
        itemIDs = itemIDs,
        quantityPerCraft = quantityPerCraft,
        qtyPerCraft = quantityPerCraft, -- Compatibility alias.
        qtyPerStart = quantityPerStart,
        qtyMultiplier = quantityPerStart,
        workbookTotalQty = tonumber(raw.workbookTotalQty),
        cheapestOf = NormalizeCheapestOf(raw.cheapestOf),
        excludeFromCost = raw.excludeFromCost and true or false,
        skipDerivation = raw.skipDerivation and true or false,
    }
end

local function NormalizeRecipeBody(raw, fallbackStartingAmount, fallbackCrafts)
    local startingAmount = PositiveNumber(raw.defaultStartingAmount, fallbackStartingAmount or 1000)
    local defaultCrafts = PositiveNumber(raw.defaultCrafts, fallbackCrafts or startingAmount)

    local outputs = {}
    local rawOutputs = raw.outputs
    if type(rawOutputs) ~= "table" or #rawOutputs == 0 then
        rawOutputs = type(raw.output) == "table" and { raw.output } or {}
    end
    for _, rawOutput in ipairs(rawOutputs) do
        local output, err = NormalizeOutput(rawOutput, startingAmount, defaultCrafts)
        if output then
            outputs[#outputs + 1] = output
        elseif #rawOutputs == 1 then
            return nil, err
        end
    end
    if #outputs == 0 then
        return nil, "recipe has no valid commodity outputs"
    end

    if type(raw.reagents) ~= "table" then
        return nil, "recipe has no reagent table"
    end
    local reagents = {}
    for index, rawReagent in ipairs(raw.reagents) do
        local reagent, err = NormalizeReagent(rawReagent, startingAmount, defaultCrafts)
        if not reagent then
            return nil, string.format("reagent[%d]: %s", index, err or "invalid")
        end
        reagents[#reagents + 1] = reagent
    end

    return {
        defaultStartingAmount = startingAmount, -- Compatibility with saved batch sizing.
        defaultCrafts = defaultCrafts,
        outputs = outputs,
        output = outputs[1], -- Compatibility alias.
        reagents = reagents,
    }
end

function Model.Normalize(raw, source, isUser)
    source = source or "Unknown"
    if type(raw) ~= "table" then
        return nil, source .. ": entry is not a table"
    end
    if type(raw.profession) ~= "string" or raw.profession == "" then
        return nil, source .. ": missing profession"
    end
    if type(raw.stratName) ~= "string" or raw.stratName == "" then
        return nil, source .. ": missing strategy name"
    end

    local patchTag = raw.patchTag or (GAM.C and GAM.C.DEFAULT_PATCH) or "midnight-1"
    local body, bodyErr = NormalizeRecipeBody(raw)
    if not body then
        return nil, string.format("%s '%s': %s", source, raw.stratName, bodyErr)
    end

    local variants = nil
    if type(raw.rankVariants) == "table" then
        variants = {}
        for variantKey, rawVariant in pairs(raw.rankVariants) do
            if type(rawVariant) == "table" then
                local variant, variantErr = NormalizeRecipeBody(
                    rawVariant, body.defaultStartingAmount, body.defaultCrafts)
                if variant then
                    variants[variantKey] = variant
                elseif GAM.Log and GAM.Log.Warn then
                    GAM.Log.Warn("StrategyModel: %s '%s' variant '%s': %s",
                        source, raw.stratName, tostring(variantKey), tostring(variantErr))
                end
            end
        end
        if next(variants) == nil then
            variants = nil
        end
    end

    local profileKey = raw.statProfileKey or raw.formulaProfile
    local model = {
        schemaVersion = Model.SCHEMA_VERSION,
        id = raw.id or MakeID(raw.profession, raw.stratName, patchTag),
        patchTag = patchTag,
        profession = raw.profession,
        stratName = raw.stratName,
        sourceTab = raw.sourceTab or raw.profession,
        sourceBlock = raw.sourceBlock,
        recipeID = tonumber(raw.recipeID),
        recipeName = raw.recipeName,
        statProfileKey = profileKey,
        formulaProfile = profileKey, -- Compatibility alias.
        defaultStartingAmount = body.defaultStartingAmount,
        defaultCrafts = body.defaultCrafts,
        qualityPolicy = raw.qualityPolicy
            or ((raw.stratName:lower():find("q2", 1, true) and "force_q2_inputs") or "normal"),
        -- A known stat profile always uses the shared formula engine. This also
        -- retires the last workbook-only fixed strategy at the runtime boundary.
        calcMode = profileKey and "formula" or (raw.calcMode or "fixed"),
        outputQualityMode = raw.outputQualityMode or "rank_policy",
        notes = raw.notes or "",
        outputs = body.outputs,
        output = body.outputs[1], -- Compatibility alias.
        reagents = body.reagents,
        rankVariants = variants,
        _isUser = isUser or raw._isUser or false,
    }
    return model
end

function Model.ResolveRecipeView(strategy, variantKeyOrTable)
    if type(strategy) ~= "table" then
        return nil
    end
    local variant = variantKeyOrTable
    if type(variantKeyOrTable) ~= "table" then
        variant = strategy.rankVariants and strategy.rankVariants[variantKeyOrTable]
    end
    variant = variant or {}
    local outputs = variant.outputs or strategy.outputs or {}
    return {
        defaultStartingAmount = variant.defaultStartingAmount or strategy.defaultStartingAmount,
        defaultCrafts = variant.defaultCrafts or strategy.defaultCrafts or strategy.defaultStartingAmount,
        outputs = outputs,
        output = outputs[1], -- Compatibility alias for consumers not yet migrated.
        reagents = variant.reagents or strategy.reagents or {},
    }
end

function Model.ResolveActiveRecipeView(strategy, rankPolicy)
    if type(strategy) ~= "table" then
        return nil
    end
    local variantKey = (rankPolicy == "highest") and "highest" or "lowest"
    if not (strategy.rankVariants and strategy.rankVariants[variantKey]) then
        variantKey = nil
    end
    return Model.ResolveRecipeView(strategy, variantKey)
end

function Model.GetOrderedVariantKeys(rankVariants)
    local ordered = {}
    if type(rankVariants) ~= "table" then
        return ordered
    end
    if rankVariants.lowest then ordered[#ordered + 1] = "lowest" end
    if rankVariants.highest then ordered[#ordered + 1] = "highest" end
    local extras = {}
    for key in pairs(rankVariants) do
        if key ~= "lowest" and key ~= "highest" then
            extras[#extras + 1] = key
        end
    end
    table.sort(extras, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(extras) do ordered[#ordered + 1] = key end
    return ordered
end

function Model.RunSmokeChecks()
    local ok, err = pcall(function()
        local sample = {
            profession = "Alchemy",
            stratName = "Canonical Sample",
            patchTag = "midnight-1",
            defaultStartingAmount = 10,
            defaultCrafts = 5,
            formulaProfile = "alchemy",
            outputs = {
                { itemIDs = { 241334, 241335 }, baseYieldPerCraft = 2 },
            },
            reagents = {
                { itemIDs = { 236949 }, qtyPerCraft = 2 },
            },
        }
        local strategy, normalizeErr = Model.Normalize(sample, "Smoke", false)
        assert(strategy, normalizeErr)
        assert(strategy.schemaVersion == Model.SCHEMA_VERSION, "schema version missing")
        assert(strategy.statProfileKey == "alchemy", "profile was not canonicalized")
        assert(#strategy.outputs[1].itemIDs == 1 and strategy.outputs[1].itemIDs[1] == 241334,
            "commodity outputs were not filtered")
        assert(strategy.reagents[1].quantityPerCraft == 2, "reagent quantity was not canonicalized")
        assert(Model.ResolveRecipeView(strategy).outputs == strategy.outputs, "recipe view changed outputs")
        assert(Model.ResolveActiveRecipeView(strategy, "lowest").outputs == strategy.outputs,
            "active recipe view changed base outputs")
    end)
    return ok, err
end
