-- GoldAdvisorMidnight/Importer.lua
-- Loads generated workbook recipes and normalizes them into a runtime shape.
-- Module: GAM.Importer

local ADDON_NAME, GAM = ...
local Importer = {}
GAM.Importer = Importer

local stratsByID = {}
local stratsByPatch = {}
local stratsByProfession = {}
local allStrats = {}

local function NormStr(s)
    return (s or ""):lower():gsub("[^a-z0-9]", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
end

local function MakeStratID(profession, stratName, patchTag)
    return NormStr(profession) .. "__" .. NormStr(stratName) .. "__" .. NormStr(patchTag)
end

local function GetItemCatalog()
    return (GAM_WORKBOOK_GENERATED and GAM_WORKBOOK_GENERATED.itemCatalog) or {}
end

local function CatalogIDsFor(itemRef)
    local catalog = GetItemCatalog()
    local ids = catalog[itemRef]
    if ids and #ids > 0 then
        return ids
    end
    return {}
end

local function CopyIDs(ids)
    local out = {}
    if type(ids) == "table" then
        for i, id in ipairs(ids) do
            out[i] = id
        end
    end
    return out
end

local function NormalizeOutput(output, startingAmt, defaultCrafts)
    if type(output) ~= "table" then
        return nil
    end

    local itemRef = output.itemRef or output.name
    local crafts = tonumber(defaultCrafts) or tonumber(startingAmt) or 1
    if crafts <= 0 then crafts = 1 end
    local start = tonumber(startingAmt) or crafts
    if start <= 0 then start = crafts end

    local baseYieldPerCraft = tonumber(output.baseYieldPerCraft)
    local baseYield = tonumber(output.baseYield)
    if type(baseYield) ~= "number" then
        baseYield = tonumber(output.baseYieldMultiplier) or tonumber(output.qtyMultiplier)
    end
    if type(baseYieldPerCraft) ~= "number" and type(baseYield) == "number" then
        baseYieldPerCraft = (baseYield * start) / crafts
    end
    if type(baseYield) ~= "number" and type(baseYieldPerCraft) == "number" then
        baseYield = (baseYieldPerCraft * crafts) / start
    end
    if type(baseYieldPerCraft) ~= "number" or baseYieldPerCraft < 0 or type(baseYield) ~= "number" or baseYield < 0 then
        return nil
    end

    local itemIDs = CopyIDs(output.itemIDs)
    if #itemIDs == 0 and itemRef then
        itemIDs = CopyIDs(CatalogIDsFor(itemRef))
    end

    return {
        itemRef = itemRef,
        name = itemRef,
        itemIDs = itemIDs,
        baseYieldPerCraft = baseYieldPerCraft,
        baseYield = baseYield,
        baseYieldMultiplier = baseYield,
        qtyMultiplier = baseYield,
        workbookExpectedQty = tonumber(output.workbookExpectedQty),
    }
end

local function NormalizeReagent(reagent, startingAmt, defaultCrafts)
    if type(reagent) ~= "table" then
        return nil
    end

    local itemRef = reagent.itemRef or reagent.name
    local crafts = tonumber(defaultCrafts) or tonumber(startingAmt) or 1
    if crafts <= 0 then crafts = 1 end
    local start = tonumber(startingAmt) or crafts
    if start <= 0 then start = crafts end

    local qtyPerCraft = tonumber(reagent.qtyPerCraft)
    local qtyPerStart = tonumber(reagent.qtyPerStart)
    if type(qtyPerStart) ~= "number" then
        qtyPerStart = tonumber(reagent.qtyMultiplier)
    end
    if type(qtyPerCraft) ~= "number" and type(qtyPerStart) == "number" then
        qtyPerCraft = (qtyPerStart * start) / crafts
    end
    if type(qtyPerStart) ~= "number" and type(qtyPerCraft) == "number" then
        qtyPerStart = (qtyPerCraft * crafts) / start
    end
    if type(qtyPerCraft) ~= "number" or qtyPerCraft < 0 or type(qtyPerStart) ~= "number" or qtyPerStart < 0 then
        return nil
    end

    local itemIDs = CopyIDs(reagent.itemIDs)
    if #itemIDs == 0 and itemRef then
        itemIDs = CopyIDs(CatalogIDsFor(itemRef))
    end

    return {
        itemRef = itemRef,
        name = itemRef,
        itemIDs = itemIDs,
        qtyPerCraft = qtyPerCraft,
        qtyPerStart = qtyPerStart,
        qtyMultiplier = qtyPerStart,
        workbookTotalQty = tonumber(reagent.workbookTotalQty),
    }
end

local function NormalizeVariant(rawVariant, src, profession, stratName, patchTag, fallbackStartingAmt, fallbackCrafts)
    if type(rawVariant) ~= "table" then
        return nil
    end
    local startingAmt = tonumber(rawVariant.defaultStartingAmount) or tonumber(fallbackStartingAmt) or 1000
    if startingAmt <= 0 then
        startingAmt = tonumber(fallbackStartingAmt) or 1000
    end
    local defaultCrafts = tonumber(rawVariant.defaultCrafts) or tonumber(fallbackCrafts) or startingAmt
    if defaultCrafts <= 0 then
        defaultCrafts = startingAmt
    end

    local outputs = {}
    for _, output in ipairs(rawVariant.outputs or {}) do
        local normalized = NormalizeOutput(output, startingAmt, defaultCrafts)
        if normalized then
            outputs[#outputs + 1] = normalized
        end
    end
    if #outputs == 0 and type(rawVariant.output) == "table" then
        local normalized = NormalizeOutput(rawVariant.output, startingAmt, defaultCrafts)
        if normalized then outputs[1] = normalized end
    end
    if #outputs == 0 then
        GAM.Log.Warn("Importer: %s '%s' — invalid rank variant outputs", src, stratName)
        return nil
    end

    local reagents = {}
    for i, reagent in ipairs(rawVariant.reagents or {}) do
        local normalized = NormalizeReagent(reagent, startingAmt, defaultCrafts)
        if not normalized then
            GAM.Log.Warn("Importer: %s '%s' — invalid rank variant reagent[%d]", src, stratName, i)
            return nil
        end
        reagents[#reagents + 1] = normalized
    end
    if #reagents == 0 then
        GAM.Log.Warn("Importer: %s '%s' — invalid rank variant reagents", src, stratName)
        return nil
    end

    return {
        defaultStartingAmount = startingAmt,
        defaultCrafts = defaultCrafts,
        outputs = outputs,
        output = outputs[1],
        reagents = reagents,
    }
end

local function NormalizeStrat(raw, src, isUser)
    if type(raw) ~= "table" then
        GAM.Log.Warn("Importer: %s — skipping non-table entry", src)
        return nil
    end

    local profession = raw.profession
    local stratName = raw.stratName
    if type(profession) ~= "string" or profession == "" then
        GAM.Log.Warn("Importer: %s — missing profession", src)
        return nil
    end
    if type(stratName) ~= "string" or stratName == "" then
        GAM.Log.Warn("Importer: %s — missing stratName", src)
        return nil
    end

    local patchTag = raw.patchTag or GAM.C.DEFAULT_PATCH
    local startingAmt = tonumber(raw.defaultStartingAmount) or 1000
    if startingAmt <= 0 then
        startingAmt = 1000
    end
    local defaultCrafts = tonumber(raw.defaultCrafts) or startingAmt
    if defaultCrafts <= 0 then
        defaultCrafts = startingAmt
    end

    local outputs = {}
    if type(raw.outputs) == "table" and #raw.outputs > 0 then
        for _, output in ipairs(raw.outputs) do
            local normalized = NormalizeOutput(output, startingAmt, defaultCrafts)
            if normalized then
                outputs[#outputs + 1] = normalized
            end
        end
    elseif type(raw.output) == "table" then
        local normalized = NormalizeOutput(raw.output, startingAmt, defaultCrafts)
        if normalized then
            outputs[1] = normalized
        end
    end

    if #outputs == 0 then
        GAM.Log.Warn("Importer: %s '%s' — missing valid outputs", src, stratName)
        return nil
    end

    local reagents = {}
    if type(raw.reagents) ~= "table" then
        GAM.Log.Warn("Importer: %s '%s' — missing reagents table", src, stratName)
        return nil
    end
    for i, reagent in ipairs(raw.reagents) do
        local normalized = NormalizeReagent(reagent, startingAmt, defaultCrafts)
        if not normalized then
            GAM.Log.Warn("Importer: %s '%s' — invalid reagent[%d]", src, stratName, i)
            return nil
        end
        reagents[#reagents + 1] = normalized
    end

    local rankVariants = nil
    if type(raw.rankVariants) == "table" then
        rankVariants = {}
        for variantKey, variantRaw in pairs(raw.rankVariants) do
            local normalized = NormalizeVariant(variantRaw, src, profession, stratName, patchTag, startingAmt, defaultCrafts)
            if normalized then
                rankVariants[variantKey] = normalized
            end
        end
        if next(rankVariants) == nil then
            rankVariants = nil
        end
    end

    local strat = {
        id = raw.id or MakeStratID(profession, stratName, patchTag),
        patchTag = patchTag,
        profession = profession,
        stratName = stratName,
        sourceTab = raw.sourceTab or profession,
        sourceBlock = raw.sourceBlock,
        defaultStartingAmount = startingAmt,
        defaultCrafts = defaultCrafts,
        qualityPolicy = raw.qualityPolicy or ((stratName:lower():find("q2", 1, true) and "force_q2_inputs") or "normal"),
        formulaProfile = raw.formulaProfile,
        calcMode = raw.calcMode or (raw.formulaProfile and "formula") or "fixed",
        outputQualityMode = raw.outputQualityMode or "rank_policy",
        notes = raw.notes or "",
        outputs = outputs,
        output = outputs[1],
        reagents = reagents,
        rankVariants = rankVariants,
        _isUser = isUser or raw._isUser or false,
    }

    return strat
end

local function IndexStrat(s)
    local existing = stratsByID[s.id]
    if existing then
        for k in pairs(existing) do
            existing[k] = nil
        end
        for k, v in pairs(s) do
            existing[k] = v
        end
        return
    end

    stratsByID[s.id] = s
    allStrats[#allStrats + 1] = s

    local pt = s.patchTag
    stratsByPatch[pt] = stratsByPatch[pt] or {}
    stratsByPatch[pt][#stratsByPatch[pt] + 1] = s

    local pr = s.profession
    stratsByProfession[pr] = stratsByProfession[pr] or {}
    stratsByProfession[pr][#stratsByProfession[pr] + 1] = s
end

local function LoadRecipeList(list, src, isUser)
    local loaded = 0
    local skipped = 0
    if type(list) ~= "table" then
        return loaded, skipped
    end

    for _, raw in ipairs(list) do
        local strat = NormalizeStrat(raw, src, isUser)
        if strat then
            IndexStrat(strat)
            loaded = loaded + 1
        else
            skipped = skipped + 1
        end
    end
    return loaded, skipped
end

function Importer.Init()
    wipe(stratsByID)
    wipe(stratsByPatch)
    wipe(stratsByProfession)
    wipe(allStrats)

    local loaded = 0
    local skipped = 0

    if type(GAM_RECIPES_GENERATED) == "table" then
        local l, s = LoadRecipeList(GAM_RECIPES_GENERATED, "Generated", false)
        loaded = loaded + l
        skipped = skipped + s
    elseif type(GAM_STRATS_GENERATED) == "table" then
        local l, s = LoadRecipeList(GAM_STRATS_GENERATED, "GeneratedLegacy", false)
        loaded = loaded + l
        skipped = skipped + s
        GAM.Log.Warn("Importer: using legacy generated strats fallback")
    else
        GAM.Log.Warn("Importer: no generated recipe table found")
    end

    if GAM.db and type(GAM.db.userStrats) == "table" then
        local migrated = {}
        for _, raw in ipairs(GAM.db.userStrats) do
            local strat = NormalizeStrat(raw, "User", true)
            if strat then
                migrated[#migrated + 1] = strat
                IndexStrat(strat)
                loaded = loaded + 1
            else
                skipped = skipped + 1
            end
        end
        GAM.db.userStrats = migrated
    end

    GAM.Log.Info("Importer: loaded %d strats, skipped %d", loaded, skipped)
end

function Importer.GetAllStrats(patchTag)
    if not patchTag then return allStrats end
    return stratsByPatch[patchTag] or {}
end

function Importer.GetStratByID(id)
    return stratsByID[id]
end

function Importer.GetStratsByProfession(profession, patchTag)
    local byProf = stratsByProfession[profession] or {}
    if not patchTag then return byProf end
    local out = {}
    for _, s in ipairs(byProf) do
        if s.patchTag == patchTag then
            out[#out + 1] = s
        end
    end
    return out
end

function Importer.GetAllPatchTags()
    local tags = {}
    for tag in pairs(stratsByPatch) do
        tags[#tags + 1] = tag
    end
    table.sort(tags)
    return tags
end

function Importer.GetAllProfessions(patchTag)
    local profs = {}
    local seen = {}
    local src = patchTag and (stratsByPatch[patchTag] or {}) or allStrats
    for _, s in ipairs(src) do
        if not seen[s.profession] then
            seen[s.profession] = true
            profs[#profs + 1] = s.profession
        end
    end
    table.sort(profs)
    return profs
end

function Importer.GetStratCount(patchTag)
    if patchTag then
        return #(stratsByPatch[patchTag] or {})
    end
    return #allStrats
end
