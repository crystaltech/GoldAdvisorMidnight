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
local producerIndexByPatch = {}
local lastInitStats = {}

local function GetSupportedProfessionSeed()
    return (GAM.C and GAM.C.SUPPORTED_PROFESSIONS) or {}
end

local function NormalizeStrat(raw, src, isUser)
    local model = GAM.StrategyModel
    if not (model and model.Normalize) then
        GAM.Log.Warn("Importer: StrategyModel is unavailable")
        return nil
    end
    local strategy, err = model.Normalize(raw, src, isUser)
    if not strategy then
        GAM.Log.Warn("Importer: %s", tostring(err or "normalization failed"))
    end
    return strategy
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

local function BuildRecipeView(strat, variant)
    local model = GAM.StrategyModel
    return model and model.ResolveRecipeView and model.ResolveRecipeView(strat, variant) or nil
end

local function IsEligibleProducerView(view)
    if not view or type(view.outputs) ~= "table" or #view.outputs ~= 1 then
        return false
    end
    for _, reagent in ipairs(view.reagents or {}) do
        if reagent.skipDerivation then
            return false
        end
    end
    return true
end

local function AddProducerCandidate(patchTag, itemID, stratID, variantKey)
    if not patchTag or not itemID or itemID == 0 or not stratID then
        return
    end
    producerIndexByPatch[patchTag] = producerIndexByPatch[patchTag] or {}
    producerIndexByPatch[patchTag][itemID] = producerIndexByPatch[patchTag][itemID] or {}
    producerIndexByPatch[patchTag][itemID][#producerIndexByPatch[patchTag][itemID] + 1] = {
        stratID = stratID,
        variantKey = variantKey,
    }
end

local function IndexProducerView(strat, view, variantKey)
    if not IsEligibleProducerView(view) then
        return
    end
    local output = (view.outputs and view.outputs[1]) or view.output
    for _, itemID in ipairs((output and output.itemIDs) or {}) do
        AddProducerCandidate(strat.patchTag, itemID, strat.id, variantKey)
    end
end

local function GetOrderedVariantKeys(rankVariants)
    local model = GAM.StrategyModel
    return model and model.GetOrderedVariantKeys and model.GetOrderedVariantKeys(rankVariants) or {}
end

local function RebuildProducerIndex()
    wipe(producerIndexByPatch)

    for _, strat in ipairs(allStrats) do
        if strat.rankVariants then
            for _, variantKey in ipairs(GetOrderedVariantKeys(strat.rankVariants)) do
                IndexProducerView(strat, BuildRecipeView(strat, strat.rankVariants[variantKey]), variantKey)
            end
        else
            IndexProducerView(strat, BuildRecipeView(strat), nil)
        end
    end
end

local function LoadRecipeList(list, src, isUser)
    local loaded = 0
    local skipped = 0
    local commoditySkipped = 0
    local disabledSkipped = 0
    if type(list) ~= "table" then
        return loaded, skipped, commoditySkipped, disabledSkipped
    end

    for _, raw in ipairs(list) do
        local strat = nil
        local commodityRejected = false
        if type(raw) == "table" and raw.disabledReason then
            skipped = skipped + 1
            disabledSkipped = disabledSkipped + 1
        else
            local catalog = GAM.CommodityCatalog
            local eligible = catalog and catalog.IsStrategyEligible
                and catalog.IsStrategyEligible(raw)
            if eligible then
                strat = NormalizeStrat(raw, src, isUser)
            else
                skipped = skipped + 1
                commoditySkipped = commoditySkipped + 1
                commodityRejected = true
            end
        end
        if strat then
            IndexStrat(strat)
            loaded = loaded + 1
        elseif not commodityRejected and not (type(raw) == "table" and raw.disabledReason) then
            skipped = skipped + 1
        end
    end
    return loaded, skipped, commoditySkipped, disabledSkipped
end

function Importer.Init()
    wipe(stratsByID)
    wipe(stratsByPatch)
    wipe(stratsByProfession)
    wipe(allStrats)
    wipe(producerIndexByPatch)

    local loaded = 0
    local skipped = 0
    local builtInLoaded = 0
    local userLoaded = 0
    local shadowedUserSkipped = 0
    local commoditySkipped = 0
    local disabledSkipped = 0

    if type(GAM_RECIPES_GENERATED) == "table" then
        local l, s, c, d = LoadRecipeList(GAM_RECIPES_GENERATED, "Generated", false)
        loaded = loaded + l
        skipped = skipped + s
        builtInLoaded = builtInLoaded + l
        commoditySkipped = commoditySkipped + c
        disabledSkipped = disabledSkipped + d
    elseif type(GAM_STRATS_GENERATED) == "table" then
        local l, s, c, d = LoadRecipeList(GAM_STRATS_GENERATED, "GeneratedLegacy", false)
        loaded = loaded + l
        skipped = skipped + s
        builtInLoaded = builtInLoaded + l
        commoditySkipped = commoditySkipped + c
        disabledSkipped = disabledSkipped + d
        GAM.Log.Warn("Importer: using legacy generated strats fallback")
    else
        GAM.Log.Warn("Importer: no generated recipe table found")
    end

    if GAM.db and type(GAM.db.userStrats) == "table" then
        for _, raw in ipairs(GAM.db.userStrats) do
            local catalog = GAM.CommodityCatalog
            local eligible = catalog and catalog.IsStrategyEligible
                and catalog.IsStrategyEligible(raw)
            if eligible then
                local strat = NormalizeStrat(raw, "User", true)
                if strat then
                    local legacyID = type(raw) == "table" and raw.legacyID or nil
                    local existing = stratsByID[strat.id]
                    if not existing and legacyID then
                        existing = stratsByID[legacyID]
                    end
                    if existing and not existing._isUser then
                        -- Preserve the SavedVariables entry, but do not let a
                        -- stale custom copy erase canonical recipe IDs,
                        -- profiles, or rank data added to the shipped catalog.
                        -- Migrated user entries may retain a generated strategy
                        -- identity in legacyID while using a new user__ ID.
                        skipped = skipped + 1
                        shadowedUserSkipped = shadowedUserSkipped + 1
                        GAM.Log.Warn(
                            "Importer: preserved inactive user strategy '%s'; built-in '%s' is authoritative",
                            tostring(strat.id), tostring(existing.id))
                    else
                        IndexStrat(strat)
                        loaded = loaded + 1
                        userLoaded = userLoaded + 1
                    end
                else
                    skipped = skipped + 1
                end
            else
                -- Commodity-only 2.0 does not activate unverified custom
                -- strategies, but SavedVariables remain intact for migration,
                -- export, or a future commodity recipe editor.
                skipped = skipped + 1
                commoditySkipped = commoditySkipped + 1
            end
        end
    end

    RebuildProducerIndex()
    local manifestCount = GAM.CommodityCatalog and GAM.CommodityCatalog.GetStrategyCount
        and GAM.CommodityCatalog.GetStrategyCount() or 0
    if manifestCount > 0 and builtInLoaded ~= manifestCount then
        GAM.Log.Warn("Importer: commodity manifest expected %d built-ins, loaded %d",
            manifestCount, builtInLoaded)
    end
    lastInitStats = {
        loaded = loaded,
        skipped = skipped,
        builtInLoaded = builtInLoaded,
        userLoaded = userLoaded,
        commoditySkipped = commoditySkipped,
        disabledSkipped = disabledSkipped,
        shadowedUserSkipped = shadowedUserSkipped,
        manifestCount = manifestCount,
    }
    GAM.Log.Info(
        "Importer: loaded %d strats (%d built-in, %d user), skipped %d (%d noncommodity, %d disabled, %d shadowed)",
        loaded, builtInLoaded, userLoaded, skipped, commoditySkipped, disabledSkipped,
        shadowedUserSkipped)
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
    for _, profession in ipairs(GetSupportedProfessionSeed()) do
        if type(profession) == "string" and profession ~= "" and not seen[profession] then
            seen[profession] = true
            profs[#profs + 1] = profession
        end
    end
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

function Importer.GetInitStats()
    local copy = {}
    for key, value in pairs(lastInitStats) do
        copy[key] = value
    end
    return copy
end

function Importer.GetProducerCandidates(itemID, patchTag)
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local byPatch = producerIndexByPatch[patchTag]
    if not byPatch then
        return {}
    end
    return byPatch[itemID] or {}
end
