-- Regression: VI execution planning consumes owned intermediates before
-- expanding the remaining demand into raw-material producer inputs.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {}
local TestLoader = assert(loadfile("../tests/TestLoader.lua"))()

function wipe(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end
tinsert = table.insert
time = os.time

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

LoadGlobal("Data/WorkbookGenerated.lua")
LoadGlobal("Data/CommodityManifest.lua")
LoadGlobal("Data/ProfessionCrafts.lua")
LoadGlobal("Data/ProfessionCraftsPatch12_1.lua")
LoadModule("Constants.lua")
LoadModule("CommodityCatalog.lua")
LoadModule("StrategyModel.lua")
LoadModule("PricingDerivation.lua")
LoadModule("PricingContract.lua")
TestLoader.LoadModuleWithFixture(
    "PricingFormula.lua",
    "../tests/fixtures/PricingFormulaSmoke.lua",
    ADDON_NAME,
    GAM)
LoadModule("ReagentMixOptimizer.lua")
LoadModule("PricingEngine.lua")
LoadModule("PricingPriceSource.lua")
LoadModule("PricingRecipe.lua")
LoadModule("PricingVerticalIntegration.lua")

GAM.db = {
    options = {
        rankPolicy = "highest",
        pigmentCostSource = "mill",
        ingotCostSource = "ah",
        boltCostSource = "ah",
        v2PricingMode = "fixed_crafts",
        ahCut = 0.05,
        shallowFillQty = 50,
        inscMillingRes = 30.1,
        inscInkMulti = 29.7,
        inscInkRes = 16.1,
    },
    patch = {},
    userStrats = {},
}
function GAM:GetDB() return self.db end
function GAM:GetOptions() return self.db.options end
function GAM:GetRealmCache() return {} end
function GAM:GetPatchDB(patchTag)
    patchTag = patchTag or self.C.DEFAULT_PATCH
    self.db.patch[patchTag] = self.db.patch[patchTag] or {
        startingAmounts = {}, favorites = {}, rankGroups = {}, priceOverrides = {},
        inputQtyOverrides = {}, craftsOverrides = {}, gearModes = {},
    }
    return self.db.patch[patchTag]
end
GAM.Log = { Info = function() end, Warn = function() end, Debug = function() end }

local reagentQualities = {
    [236761] = 1, [236767] = 2,
    [236770] = 1, [236771] = 2,
    [236778] = 1, [236779] = 2,
    [245807] = 1, [245808] = 2,
    [245865] = 1, [245864] = 2,
    [245867] = 1, [245866] = 2,
    [245801] = 1, [245802] = 2,
}
local craftedQualities = {}
C_TradeSkillUI = {
    GetItemReagentQualityByItemInfo = function(itemInfo)
        local structured = type(itemInfo) == "table"
        local itemID = structured and itemInfo.itemID or itemInfo
        -- Blizzard reports 0 when a ranked crafted output is passed to the
        -- reagent-quality API. This must not be interpreted as output rank 1.
        if craftedQualities[itemID] then return 0 end
        -- Model the live ItemInfo contract: a bare numeric reagent lookup can
        -- be classified as unranked even though the structured lookup is ranked.
        if not structured and reagentQualities[itemID] then return 0 end
        return reagentQualities[itemID]
    end,
    GetItemCraftedQualityByItemInfo = function(itemID)
        -- The legacy crafted-quality lookup can be ambiguous for these output
        -- IDs; recipe output resolution must not rely on it.
        if craftedQualities[itemID] then return 1 end
        return reagentQualities[itemID]
    end,
    GetRecipeQualityItemIDs = function(recipeID)
        -- Blizzard returns crafted output item IDs in one-based rank order.
        if recipeID == 1227926 then return { 239198, 239200 } end
        return nil
    end,
    GetQualitiesForRecipe = function(recipeID)
        -- These are opaque quality-record IDs, not values accepted by
        -- GetRecipeOutputItemData's overrideQualityID argument.
        if recipeID == 1227926 then return { 9101, 9102 } end
        return nil
    end,
    GetRecipeOutputItemData = function(recipeID, reagents, allocationItemGUID, overrideQualityID)
        if recipeID ~= 1227926 then return nil end
        assert(type(reagents) == "table", "output-quality lookup omitted the reagent table")
        if overrideQualityID == 1 then return { itemID = 239198 } end
        if overrideQualityID == 2 then return { itemID = 239200 } end
        return nil
    end,
}
C_Item = nil
GetItemInfo = function() return nil end

TestLoader.LoadModuleWithFixture(
    "Pricing.lua",
    "../tests/fixtures/PricingSmoke.lua",
    ADDON_NAME,
    GAM)
LoadModule("Importer.lua")
LoadGlobal("Data/RecipesGenerated.lua")
LoadGlobal("Data/Recipes/Patch12_1.lua")
GAM.Importer.Init()

local originalGetEffectivePrice = GAM.Pricing.GetEffectivePrice
local originalGetUnitPrice = GAM.Pricing.GetUnitPrice
GAM.Pricing.GetEffectivePrice = function() return 100, false end
GAM.Pricing.GetUnitPrice = function() return 100, false end

local owned = {
    [245808] = 36, -- Powder Pigment R2
    [245864] = 3,  -- Sanguithorn Pigment R2
    [245866] = 20, -- Mana Lily Pigment R2
    [245802] = 45, -- Existing output must not satisfy newly requested crafts
    [236767] = 7,  -- Tranquility Bloom R2
    [236779] = 1,  -- Mana Lily R2
}
GetItemCount = function(itemID)
    return owned[itemID] or 0
end

local strat = assert(GAM.Importer.GetStratByID("inscription__munsell_ink__midnight_1"))
GAM:GetPatchDB(GAM.C.DEFAULT_PATCH).craftsOverrides[strat.id] = 10
local metrics = assert(GAM.Pricing.CalculateStratMetricsV2(strat, GAM.C.DEFAULT_PATCH, 10))
assert(metrics.crafts == 10, "per-strategy craft override was not applied")

local patchDB = GAM:GetPatchDB(GAM.C.DEFAULT_PATCH)
patchDB.craftsOverrides[strat.id] = nil
local globalBatchMetrics = assert(GAM.Pricing.CalculateStratMetricsV2(
    strat, GAM.C.DEFAULT_PATCH, 1, nil, 37))
assert(globalBatchMetrics.crafts == 37,
    "global starting crafts did not replace the strategy workbook batch")
patchDB.craftsOverrides[strat.id] = 12
local overriddenGlobalMetrics = assert(GAM.Pricing.CalculateStratMetricsV2(
    strat, GAM.C.DEFAULT_PATCH, 1, nil, 37))
assert(overriddenGlobalMetrics.crafts == 12,
    "per-strategy craft override did not take priority over the global default")
patchDB.craftsOverrides[strat.id] = 10

local byID = {}
for _, row in ipairs(metrics.reagents or {}) do
    byID[row.itemID] = row
end

assert(byID[236767] and byID[236767].needToBuy < byID[236767].required,
    "owned Tranquility Bloom was not removed from the shopping quantity")
assert(byID[236779] and byID[236779].needToBuy < byID[236779].required,
    "owned Mana Lily was not removed from the shopping quantity")
assert((byID[236767].required or 0) < 140,
    "owned Powder Pigment was expanded into the original full herb requirement: "
        .. tostring(byID[236767].required))
assert((byID[236779].required or 0) < 40,
    "owned Mana Lily Pigment was expanded into the original full herb requirement: "
        .. tostring(byID[236779].required))

local breakdown = assert(GAM.Pricing.GetVIBreakdownData(strat, GAM.C.DEFAULT_PATCH, metrics))
local craftByName = {}
for _, entry in ipairs(breakdown.entries or {}) do
    if entry.kind == "craft" then craftByName[entry.name] = entry end
end
assert(craftByName["Powder Pigment"] and craftByName["Powder Pigment"].requiredRaw < 200,
    "VI craft step ignored owned Powder Pigment")
assert(craftByName["Mana Lily Pigment"] and craftByName["Mana Lily Pigment"].requiredRaw < 50,
    "VI craft step ignored owned Mana Lily Pigment")

-- When Blizzard reports that all-high reagents still cannot reach the selected
-- max output without Concentration, revenue must use the reachable output rank
-- instead of silently retaining the unreachable max-rank sale price.
reagentQualities[237017], reagentQualities[237018] = 1, 2
reagentQualities[239702], reagentQualities[239703] = 1, 2
craftedQualities[239198], craftedQualities[239200] = 1, 2
C_TradeSkillUI.GetRecipeSchematic = function(recipeID, isRecraft)
    if recipeID ~= 1227926 or isRecraft ~= false then return nil end
    return {
        reagentSlotSchematics = {
            {
                quantityRequired = 4,
                dataSlotIndex = 1,
                reagents = { { itemID = 236951 } },
            },
            {
                quantityRequired = 5,
                dataSlotIndex = 2,
                reagents = { { itemID = 237017 }, { itemID = 237018 } },
            },
            {
                quantityRequired = 6,
                dataSlotIndex = 3,
                reagents = { { itemID = 239702 }, { itemID = 239703 } },
            },
        },
    }
end
C_TradeSkillUI.GetCraftingOperationInfo = function(recipeID, allocation, allocationItemGUID, applyConcentration)
    assert(recipeID == 1227926 and allocationItemGUID == nil and applyConcentration == false)
    local bonusSkill = 0
    for _, reagent in ipairs(allocation or {}) do
        local itemID = reagent.reagent and reagent.reagent.itemID
        if itemID == 237018 or itemID == 239703 then
            bonusSkill = bonusSkill + (tonumber(reagent.quantity) or 0) * 5
        end
    end
    return {
        baseSkill = 205,
        bonusSkill = bonusSkill,
        baseDifficulty = 515,
        bonusDifficulty = 0,
        concentrationCost = 391,
        quality = 1,
    }
end

local rankPrices = {
    [236951] = 110,
    [237017] = 3140, [237018] = 2497,
    [239702] = 266, [239703] = 345,
    [239198] = 8600, [239200] = 9900,
}
GAM.Pricing.GetEffectivePrice = function(itemID)
    return rankPrices[itemID] or 100, false
end
GAM.Pricing.GetUnitPrice = GAM.Pricing.GetEffectivePrice
GAM.db.options.rankPolicy = "optimal"
local arcanoweave = assert(GAM.Importer.GetStratByID("tailoring__arcanoweave_bolt__midnight_1"))
local originalOutputIDs = arcanoweave.outputs[1].itemIDs
arcanoweave.outputs[1].itemIDs = { 239200, 239198 } -- deliberately not quality-ordered
local unreachableMetrics = assert(GAM.Pricing.CalculateStratMetricsV2(
    arcanoweave, GAM.C.DEFAULT_PATCH, 10))
arcanoweave.outputs[1].itemIDs = originalOutputIDs
assert(unreachableMetrics.rankMixReason == "target-quality-unreachable",
    "unreachable max rank was not surfaced by canonical pricing")
assert(unreachableMetrics.rankMixStatus == "reachable" and unreachableMetrics.rankMixPlan,
    "unreachable max rank did not retain its verified reachable-rank plan")
assert(unreachableMetrics.rankMixTargetQuality == 2
        and unreachableMetrics.rankMixOutputQuality == 1,
    "canonical pricing lost the target/reachable quality boundary")
assert(unreachableMetrics.rankMixHighSkill == 260
        and unreachableMetrics.rankMixRequiredSkill == 515
        and unreachableMetrics.rankMixSkillDeficit == 255
        and unreachableMetrics.rankMixConcentrationCost == 391,
    "reachable-rank plan lost its Blizzard skill/difficulty diagnostics")
assert(unreachableMetrics.output.itemID == 239198
        and unreachableMetrics.output.unitPrice == 8600,
    string.format("unreachable max rank retained the wrong output price: item=%s price=%s",
        tostring(unreachableMetrics.output.itemID), tostring(unreachableMetrics.output.unitPrice)))
local reachableRows = unreachableMetrics.rankMixPlan.rows
assert(reachableRows[1].lowCount == 0 and reachableRows[1].highCount == 5
        and reachableRows[1].highItemID == 237018,
    "reachable-rank fallback did not use the cheaper R2 Arcanoweave")
assert(reachableRows[2].lowCount == 6 and reachableRows[2].highCount == 0
        and reachableRows[2].lowItemID == 239702,
    "reachable-rank fallback retained unnecessary R2 Imbued Bright Linen Bolts")
local arcanoweaveBreakdown = assert(GAM.Pricing.GetVIBreakdownData(
    arcanoweave, GAM.C.DEFAULT_PATCH, unreachableMetrics))
local arcanoweaveRootIDs = {}
for _, rootIndex in ipairs(arcanoweaveBreakdown.rootIndices or {}) do
    local entry = arcanoweaveBreakdown.entries[rootIndex]
    if entry and entry.itemID then arcanoweaveRootIDs[entry.itemID] = true end
end
assert(arcanoweaveRootIDs[237018] and not arcanoweaveRootIDs[237017],
    "VI breakdown root lost the optimized R2 Arcanoweave selection")
assert(arcanoweaveRootIDs[239702] and not arcanoweaveRootIDs[239703],
    "VI breakdown root reverted to unnecessary R2 Imbued Bright Linen Bolts")

-- If Blizzard's live operation API is unavailable, Best Mix must not retain an
-- unverified highest-rank sale price. Keep the expensive input view, but pin
-- revenue to the lowest known output rank until the recipe can be refreshed.
local savedOperationInfo = C_TradeSkillUI.GetCraftingOperationInfo
C_TradeSkillUI.GetCraftingOperationInfo = nil
GAM.ReagentMixOptimizer.ClearCache()
local fallbackMetrics = assert(GAM.Pricing.CalculateStratMetricsV2(
    arcanoweave, GAM.C.DEFAULT_PATCH, 10))
assert(fallbackMetrics.rankMixStatus == "fallback"
        and fallbackMetrics.output.itemID == 239198,
    "unverified Best Mix did not fall back to conservative output-rank pricing")
C_TradeSkillUI.GetCraftingOperationInfo = savedOperationInfo
GAM.ReagentMixOptimizer.ClearCache()

-- A parent Best Mix may request the lower-rank output of another ranked recipe.
-- VI must preserve that exact item ID and optimize the producer for rank 1; it
-- must not re-resolve the producer through global `optimal` and reject it or
-- consume unnecessary rank-2 raw materials.
do
    local savedGetProducerCandidates = GAM.Importer.GetProducerCandidates
    local savedGetStratByID = GAM.Importer.GetStratByID
    local savedGetEffectivePrice = GAM.Pricing.GetEffectivePrice
    local savedGetUnitPrice = GAM.Pricing.GetUnitPrice
    local savedGetRecipeQualityItemIDs = C_TradeSkillUI.GetRecipeQualityItemIDs
    local savedGetRecipeSchematic = C_TradeSkillUI.GetRecipeSchematic
    local savedGetReagentQuality = C_TradeSkillUI.GetItemReagentQualityByItemInfo
    local savedGetCraftedQuality = C_TradeSkillUI.GetItemCraftedQualityByItemInfo
    local savedGetOperationInfo = C_TradeSkillUI.GetCraftingOperationInfo

    local producer = {
        id = "ranked_vi_producer",
        stratName = "Ranked VI Producer",
        profession = "Tailoring",
        patchTag = GAM.C.DEFAULT_PATCH,
        recipeID = 777777,
        calcMode = "fixed",
        qualityPolicy = "normal",
        outputQualityMode = "rank_policy",
        defaultStartingAmount = 1,
        defaultCrafts = 1,
        reagents = {
            { name = "Ranked Raw", itemIDs = { 7001, 7002 }, qtyPerCraft = 2 },
        },
        outputs = {
            { name = "Ranked Intermediate", itemIDs = { 7101, 7102 }, baseYieldPerCraft = 1 },
        },
    }
    local root = {
        id = "ranked_vi_root",
        stratName = "Ranked VI Root",
        profession = "Tailoring",
        patchTag = GAM.C.DEFAULT_PATCH,
        recipeID = 888888,
        calcMode = "fixed",
        qualityPolicy = "force_q1_inputs",
        defaultStartingAmount = 1,
        defaultCrafts = 1,
        reagents = {
            { name = "Ranked Intermediate", itemIDs = { 7101 }, qtyPerCraft = 1 },
        },
        outputs = {
            { name = "Finished Item", itemIDs = { 7201 }, baseYieldPerCraft = 1 },
        },
    }
    local nestedPrices = {
        [7001] = 10, [7002] = 100,
        [7101] = 1000, [7102] = 1200,
        [7201] = 2000,
    }

    GAM.Importer.GetProducerCandidates = function(itemID)
        return itemID == 7101 and { { stratID = producer.id } } or {}
    end
    GAM.Importer.GetStratByID = function(stratID)
        if stratID == producer.id then return producer end
        return savedGetStratByID(stratID)
    end
    GAM.Pricing.GetEffectivePrice = function(itemID)
        return nestedPrices[itemID], false
    end
    GAM.Pricing.GetUnitPrice = GAM.Pricing.GetEffectivePrice
    C_TradeSkillUI.GetRecipeQualityItemIDs = function(recipeID)
        if recipeID == producer.recipeID then return { 7101, 7102 } end
        return savedGetRecipeQualityItemIDs(recipeID)
    end
    C_TradeSkillUI.GetRecipeSchematic = function(recipeID, isRecraft)
        if recipeID == producer.recipeID and isRecraft == false then
            return {
                reagentSlotSchematics = {
                    {
                        quantityRequired = 2,
                        dataSlotIndex = 1,
                        reagents = { { itemID = 7001 }, { itemID = 7002 } },
                    },
                },
            }
        end
        return savedGetRecipeSchematic(recipeID, isRecraft)
    end
    C_TradeSkillUI.GetItemReagentQualityByItemInfo = function(itemInfo)
        local itemID = type(itemInfo) == "table" and itemInfo.itemID or itemInfo
        if itemID == 7001 then return 1 end
        if itemID == 7002 then return 2 end
        if itemID == 7101 or itemID == 7102 then return 0 end
        return savedGetReagentQuality(itemID)
    end
    C_TradeSkillUI.GetItemCraftedQualityByItemInfo = function(itemID)
        if itemID == 7101 or itemID == 7102 then return 1 end
        return savedGetCraftedQuality(itemID)
    end
    C_TradeSkillUI.GetCraftingOperationInfo = function(recipeID, allocation, allocationItemGUID, applyConcentration)
        if recipeID ~= producer.recipeID then
            return savedGetOperationInfo(recipeID, allocation, allocationItemGUID, applyConcentration)
        end
        assert(allocationItemGUID == nil and applyConcentration == false)
        local highCount = 0
        for _, reagent in ipairs(allocation or {}) do
            if reagent.reagent and reagent.reagent.itemID == 7002 then
                highCount = highCount + (tonumber(reagent.quantity) or 0)
            end
        end
        return {
            baseSkill = 100,
            bonusSkill = highCount * 10,
            quality = highCount > 0 and 2 or 1,
        }
    end

    GAM.ReagentMixOptimizer.ClearCache()
    local nestedMetrics = assert(GAM.Pricing.CalculateStratMetricsV2(
        root, GAM.C.DEFAULT_PATCH, 1))
    local nestedByID = {}
    for _, row in ipairs(nestedMetrics.reagents or {}) do
        nestedByID[row.itemID] = row
    end
    assert(nestedMetrics.economicChoices
            and nestedMetrics.economicChoices["7101"]
            and nestedMetrics.economicChoices["7101"].source == "producer",
        "lower-rank intermediate was not matched to its ranked VI producer")
    assert(nestedByID[7001] and not nestedByID[7002] and not nestedByID[7101],
        "rank-1 VI producer did not use its cheapest verified rank-1 raw mix")

    -- Ranked producer indexes contain both variants under both output IDs.
    -- When a parent explicitly requests the rank-2 output, VI must select the
    -- producer's highest variant instead of accepting the first (lowest)
    -- candidate that advertises the same output ID pool.
    producer.rankVariants = {
        lowest = {
            reagents = {
                { name = "Ranked Raw", itemIDs = { 7001 }, qtyPerCraft = 2 },
            },
            outputs = {
                { name = "Ranked Intermediate", itemIDs = { 7101, 7102 }, baseYieldPerCraft = 1 },
            },
        },
        highest = {
            reagents = {
                { name = "Ranked Raw", itemIDs = { 7001 }, qtyPerCraft = 1 },
                { name = "Ranked Raw", itemIDs = { 7002 }, qtyPerCraft = 1 },
            },
            outputs = {
                { name = "Ranked Intermediate", itemIDs = { 7101, 7102 }, baseYieldPerCraft = 1 },
            },
        },
    }
    GAM.Importer.GetProducerCandidates = function(itemID)
        if itemID == 7101 then
            return { { stratID = producer.id } }
        end
        if itemID == 7102 then
            return {
                { stratID = producer.id, variantKey = "lowest" },
                { stratID = producer.id, variantKey = "highest" },
            }
        end
        return {}
    end
    local rank2Root = {
        id = "ranked_vi_rank2_root",
        stratName = "Ranked VI Rank 2 Root",
        profession = "Tailoring",
        patchTag = GAM.C.DEFAULT_PATCH,
        recipeID = 888889,
        calcMode = "fixed",
        qualityPolicy = "force_q2_inputs",
        defaultStartingAmount = 1,
        defaultCrafts = 1,
        reagents = {
            { name = "Ranked Intermediate", itemIDs = { 7102 }, qtyPerCraft = 1 },
        },
        outputs = {
            { name = "Finished Item", itemIDs = { 7201 }, baseYieldPerCraft = 1 },
        },
    }
    local rank2Metrics = assert(GAM.Pricing.CalculateStratMetricsV2(
        rank2Root, GAM.C.DEFAULT_PATCH, 1))
    local rank2ByID = {}
    for _, row in ipairs(rank2Metrics.reagents or {}) do rank2ByID[row.itemID] = row end
    assert(rank2ByID[7001] and rank2ByID[7002] and not rank2ByID[7102],
        "rank-2 VI dependency selected the lowest producer variant")

    -- Cooldown/charge capacity is part of executability. With one producer
    -- charge left for two required intermediates, VI must craft one and buy the
    -- other. With zero charges it must buy the intermediate outright.
    local savedCooldownTracker = GAM.CooldownTracker
    GAM.CooldownTracker = {
        GetImmediateCraftCapacity = function(recipeID)
            return recipeID == producer.recipeID and 1 or nil, "charges"
        end,
    }
    local hybridMetrics = assert(GAM.Pricing.CalculateStratMetricsV2(
        root, GAM.C.DEFAULT_PATCH, 2))
    local hybridByID = {}
    for _, row in ipairs(hybridMetrics.reagents or {}) do hybridByID[row.itemID] = row end
    assert(hybridMetrics.economicChoices["7101"].source == "hybrid"
            and hybridByID[7001] and hybridByID[7101],
        "VI did not split a charged intermediate between available crafting and AH purchases")
    assert(hybridByID[7001].required == 2 and hybridByID[7101].required == 1,
        "VI bought producer inputs for crafts beyond the one remaining charge")
    local hybridBreakdown = assert(GAM.Pricing.GetVIBreakdownData(
        root, GAM.C.DEFAULT_PATCH, hybridMetrics))
    local hybridProducerCrafts = 0
    for _, entry in ipairs(hybridBreakdown.entries or {}) do
        if entry.producerStratID == producer.id then
            hybridProducerCrafts = hybridProducerCrafts + (entry.craftsExecution or 0)
        end
    end
    assert(hybridProducerCrafts == 1,
        "VI breakdown exceeded the producer's one remaining charge")

    GAM.CooldownTracker.GetImmediateCraftCapacity = function(recipeID)
        return recipeID == producer.recipeID and 0 or nil, "charges"
    end
    local blockedMetrics = assert(GAM.Pricing.CalculateStratMetricsV2(
        root, GAM.C.DEFAULT_PATCH, 2))
    local blockedByID = {}
    for _, row in ipairs(blockedMetrics.reagents or {}) do blockedByID[row.itemID] = row end
    assert(blockedByID[7101] and not blockedByID[7001] and not blockedByID[7002],
        "VI expanded a producer whose charges were fully depleted")
    local blockedBreakdown = assert(GAM.Pricing.GetVIBreakdownData(
        root, GAM.C.DEFAULT_PATCH, blockedMetrics))
    for _, entry in ipairs(blockedBreakdown.entries or {}) do
        assert(entry.producerStratID ~= producer.id,
            "VI breakdown retained a craft step for a fully depleted producer")
    end

    -- The selected final recipe is also part of an immediately executable VI
    -- plan. Keep the requested four-craft estimate intact, but limit the
    -- breakdown and its shopping projection to the one live charge available.
    GAM.CooldownTracker.GetImmediateCraftCapacity = function(recipeID)
        return recipeID == root.recipeID and 1 or nil, "charges"
    end
    local requestedFinalMetrics = assert(GAM.Pricing.CalculateStratMetricsV2(
        root, GAM.C.DEFAULT_PATCH, 4))
    assert(requestedFinalMetrics.crafts == 4,
        "final-recipe charge fixture did not retain the requested estimate")
    local finalLimitedBreakdown = assert(GAM.Pricing.GetVIBreakdownData(
        root, GAM.C.DEFAULT_PATCH, requestedFinalMetrics))
    assert(finalLimitedBreakdown.capacityLimited
            and finalLimitedBreakdown.finalCraftCapacity == 1
            and finalLimitedBreakdown.requestedFinalCraftsExecution == 4
            and finalLimitedBreakdown.finalCraftsExecution == 1,
        "VI did not cap the selected final recipe to its one remaining charge")
    local limitedRawRequired = 0
    for _, row in ipairs(finalLimitedBreakdown.shoppingReagents or {}) do
        if row.itemID == 7001 or row.itemID == 7002 then
            limitedRawRequired = limitedRawRequired + (row.required or 0)
        end
    end
    assert(limitedRawRequired == 2,
        "VI still bought raw materials for unavailable final crafts: "
            .. tostring(limitedRawRequired))

    GAM.CooldownTracker.GetImmediateCraftCapacity = function(recipeID)
        return recipeID == root.recipeID and 0 or nil, "charges"
    end
    local finalBlockedBreakdown = assert(GAM.Pricing.GetVIBreakdownData(
        root, GAM.C.DEFAULT_PATCH, requestedFinalMetrics))
    assert(finalBlockedBreakdown.capacityLimited
            and finalBlockedBreakdown.finalCraftsExecution == 0,
        "VI retained a final craft when all recipe charges were depleted")
    for _, row in ipairs(finalBlockedBreakdown.shoppingReagents or {}) do
        assert((row.needToBuy or 0) == 0,
            "VI retained a shopping quantity for a fully blocked final recipe")
    end
    GAM.CooldownTracker = savedCooldownTracker

    GAM.Importer.GetProducerCandidates = savedGetProducerCandidates
    GAM.Importer.GetStratByID = savedGetStratByID
    GAM.Pricing.GetEffectivePrice = savedGetEffectivePrice
    GAM.Pricing.GetUnitPrice = savedGetUnitPrice
    C_TradeSkillUI.GetRecipeQualityItemIDs = savedGetRecipeQualityItemIDs
    C_TradeSkillUI.GetRecipeSchematic = savedGetRecipeSchematic
    C_TradeSkillUI.GetItemReagentQualityByItemInfo = savedGetReagentQuality
    C_TradeSkillUI.GetItemCraftedQualityByItemInfo = savedGetCraftedQuality
    C_TradeSkillUI.GetCraftingOperationInfo = savedGetOperationInfo
    GAM.ReagentMixOptimizer.ClearCache()
end
GAM.db.options.rankPolicy = "highest"

GAM.Pricing.GetEffectivePrice = originalGetEffectivePrice
GAM.Pricing.GetUnitPrice = originalGetUnitPrice
local smokeOK, smokeErr = GAM.Pricing.RunSmokeChecks()
assert(smokeOK, smokeErr)

print("PASS: VI execution inventory is consumed before producer expansion")
