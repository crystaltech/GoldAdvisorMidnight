-- Offline regression checks for the committed commodity catalog and importer.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {}
local TestLoader = assert(loadfile("../tests/TestLoader.lua"))()

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

local function LoadModuleWithFixture(path, fixture)
    return TestLoader.LoadModuleWithFixture(
        path, "../tests/fixtures/" .. fixture, ADDON_NAME, GAM)
end

local function AssertEqual(actual, expected, label)
    assert(actual == expected,
        string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

LoadGlobal("Data/WorkbookGenerated.lua")
LoadGlobal("Data/CommodityManifest.lua")
LoadGlobal("Data/ProfessionCrafts.lua")
LoadGlobal("Data/ProfessionCraftsPatch12_1.lua")
LoadModule("Constants.lua")
LoadModuleWithFixture("CommodityCatalog.lua", "CommodityCatalogSmoke.lua")
LoadModuleWithFixture("StrategyModel.lua", "StrategyModelSmoke.lua")

GAM.Log = {
    Info = function() end,
    Warn = function() end,
    Debug = function() end,
}
GAM.db = { userStrats = {} }

LoadGlobal("Data/RecipesGenerated.lua")
LoadGlobal("Data/Recipes/Patch12_1.lua")
LoadModule("Importer.lua")

AssertEqual(#GAM.RecipesGenerated, 607, "raw strategy count")
AssertEqual(#GAM.RuntimeProfessionCrafts, 10, "single-source patch craft count")
AssertEqual(GAM.CommodityManifest.disabledStrategyCount, 25, "disabled strategy count")
AssertEqual(GAM.CommodityManifest.strategyCount, 283, "manifest strategy count")
AssertEqual(GAM.CommodityManifest.itemCount, 514, "manifest item count")
assert(GAM.CommodityManifest.source.tsm.us.updatedAt ~= "", "TSM source timestamp missing")
AssertEqual(GAM.CommodityManifest.source.wago.build, "12.1.0.69587", "Wago source build")
AssertEqual(#GAM.C.PROFESSION_REGISTRY, 9, "shared profession registry count")
AssertEqual(GAM.C.PROFESSION_SKILL_LINES.Cooking, 185, "Cooking skill line registration")
local cookingRegistered = false
for _, profession in ipairs(GAM.C.PROFESSION_REGISTRY) do
    if profession.name == "Cooking" then
        cookingRegistered = profession.profKey == "cook"
            and profession.profiles[1] == "cooking"
    end
end
assert(cookingRegistered, "Cooking is missing from the shared stat/CraftSim registry")

local catalogOK, catalogErr = GAM.CommodityCatalog.RunSmokeChecks()
assert(catalogOK, catalogErr)
local modelOK, modelErr = GAM.StrategyModel.RunSmokeChecks()
assert(modelOK, modelErr)

GAM.Importer.Init()
AssertEqual(GAM.Importer.GetStratCount(), 283, "runtime built-in strategy count")

local initStats = GAM.Importer.GetInitStats()
AssertEqual(initStats.builtInLoaded, 283, "loaded built-in count")
AssertEqual(initStats.userLoaded, 0, "loaded user count")
AssertEqual(initStats.skipped, 324, "total skipped count")
AssertEqual(initStats.commoditySkipped, 299, "noncommodity skipped count")
AssertEqual(initStats.disabledSkipped, 25, "disabled skipped count")
AssertEqual(initStats.manifestCount, 283, "importer manifest count")

local patch12Recipes = {
    ["alchemy__concentrated_silvermoon_health_potion__midnight_1"] = 1289744,
    ["alchemy__liquid_luster__midnight_1"] = 1289745,
    ["alchemy__alluring_nostrum__midnight_1"] = 1289746,
    ["cooking__feast_of_knowledge__midnight_1"] = 1295777,
    ["enchanting__rite_of_the_hashey__midnight_1"] = 1291694,
    ["engineering__r0cky_to_go__midnight_1"] = 1305148,
    ["inscription__vantus_rune_tides__midnight_1"] = 1290561,
    ["inscription__contract_zuljarras_forces__midnight_1"] = 1303151,
    ["jewelcrafting__refine_crystalline_glass__midnight_1"] = 1307462,
    ["jewelcrafting__refine_dusk_shrouded_stone__midnight_1"] = 1307466,
}
for strategyID, recipeID in pairs(patch12Recipes) do
    local strategy = GAM.Importer.GetStratByID(strategyID)
    assert(strategy, strategyID .. ": live 12.1 strategy was not retained")
    AssertEqual(strategy.recipeID, recipeID, strategyID .. ": recipe ID")
end

local feastOfKnowledge = GAM.Importer.GetStratByID(
    "cooking__feast_of_knowledge__midnight_1")
AssertEqual(feastOfKnowledge.outputs[1].itemIDs[1], 275266,
    "Feast of Knowledge output item")
AssertEqual(feastOfKnowledge.outputs[1].baseYieldPerCraft, 2,
    "Feast of Knowledge base yield")
AssertEqual(feastOfKnowledge.reagents[1].quantityPerCraft, 10,
    "Feast of Knowledge Coiled Stargorger input")
AssertEqual(feastOfKnowledge.reagents[2].quantityPerCraft, 20,
    "Feast of Knowledge Sulfurous Sludgefish input")

assert(GAM.CommodityCatalog.IsItemID(271889)
        and GAM.CommodityCatalog.IsItemID(271890),
    "reviewed Alluring Nostrum commodity outputs were not retained")

local radiantVantus = GAM.Importer.GetStratByID(
    "inscription__vantus_rune_radiant__midnight_1")
AssertEqual(radiantVantus.outputs[1].itemIDs[1], 245879,
    "Vantus Rune: Radiant R1 output item")
AssertEqual(radiantVantus.outputs[1].itemIDs[2], 245880,
    "Vantus Rune: Radiant R2 output item")
assert(GAM.CommodityCatalog.IsItemID(245879)
        and GAM.CommodityCatalog.IsItemID(245880),
    "Vantus Rune: Radiant quality outputs were not retained")

local restoredR2Outputs = {
    ["enchanting__gleeful_glamour_blood_elf__midnight_1"] = 243797,
    ["enchanting__gleeful_glamour_dark_iron_dwarf__midnight_1"] = 243798,
    ["enchanting__gleeful_glamour_draenei__midnight_1"] = 243799,
    ["enchanting__gleeful_glamour_dwarf__midnight_1"] = 243800,
    ["enchanting__gleeful_glamour_earthen__midnight_1"] = 243801,
    ["enchanting__gleeful_glamour_gnome__midnight_1"] = 243802,
    ["enchanting__gleeful_glamour_goblin__midnight_1"] = 243803,
    ["enchanting__gleeful_glamour_haranir__midnight_1"] = 244057,
    ["enchanting__gleeful_glamour_highmountain_tauren__midnight_1"] = 243804,
    ["enchanting__gleeful_glamour_human__midnight_1"] = 243805,
    ["enchanting__gleeful_glamour_kul_tiran__midnight_1"] = 243806,
    ["enchanting__gleeful_glamour_lightforged_draenei__midnight_1"] = 243807,
    ["enchanting__gleeful_glamour_maghar_orc__midnight_1"] = 243808,
    ["enchanting__gleeful_glamour_mechagnome__midnight_1"] = 243809,
    ["enchanting__gleeful_glamour_night_elf__midnight_1"] = 243810,
    ["enchanting__gleeful_glamour_nightborne__midnight_1"] = 243811,
    ["enchanting__gleeful_glamour_orc__midnight_1"] = 243812,
    ["enchanting__gleeful_glamour_pandaren__midnight_1"] = 243813,
    ["enchanting__gleeful_glamour_tauren__midnight_1"] = 243814,
    ["enchanting__gleeful_glamour_troll__midnight_1"] = 243815,
    ["enchanting__gleeful_glamour_undead__midnight_1"] = 243816,
    ["enchanting__gleeful_glamour_void_elf__midnight_1"] = 243817,
    ["enchanting__gleeful_glamour_vulpera__midnight_1"] = 243818,
    ["enchanting__gleeful_glamour_worgen__midnight_1"] = 243819,
    ["enchanting__gleeful_glamour_zandalari_troll__midnight_1"] = 243820,
    ["inscription__contract_the_amani_tribe__midnight_1"] = 245798,
    ["inscription__contract_the_harati__midnight_1"] = 245796,
    ["inscription__contract_the_silvermoon_court__midnight_1"] = 245800,
    ["leatherworking__blood_knights_armor_kit__midnight_1"] = 244643,
    ["leatherworking__forest_hunters_armor_kit__midnight_1"] = 244641,
    ["leatherworking__thalassian_scout_armor_kit__midnight_1"] = 244645,
    ["tailoring__arcanoweave_spellthread__midnight_1"] = 240155,
    ["tailoring__bright_linen_bandage__midnight_1"] = 239713,
    ["tailoring__bright_linen_spellthread__midnight_1"] = 240157,
    ["tailoring__sunfire_silk_spellthread__midnight_1"] = 240133,
}
for strategyID, r2ItemID in pairs(restoredR2Outputs) do
    local strategy = GAM.Importer.GetStratByID(strategyID)
    assert(strategy, strategyID .. ": ranked strategy is missing")
    AssertEqual(strategy.outputs[1].itemIDs[2], r2ItemID,
        strategyID .. ": R2 output item")
    assert(GAM.CommodityCatalog.IsItemID(r2ItemID),
        strategyID .. ": R2 output is not a retained commodity")
end

local correctedAlchemyMotes = {
    ["alchemy__draught_of_rampant_abandon__midnight_1"] = "Mote of Primal Energy",
    ["alchemy__lights_preservation__midnight_1"] = "Mote of Light",
    ["alchemy__potion_of_recklessness__midnight_1"] = "Mote of Primal Energy",
}
for strategyID, reagentName in pairs(correctedAlchemyMotes) do
    local strategy = GAM.Importer.GetStratByID(strategyID)
    local matched
    for _, reagent in ipairs(strategy and strategy.reagents or {}) do
        if reagent.itemRef == reagentName then matched = reagent break end
    end
    assert(matched, strategyID .. ": corrected mote reagent is missing")
    AssertEqual(matched.quantityPerCraft, 1, strategyID .. ": mote quantity")
end

local tidesVantus = GAM.Importer.GetStratByID(
    "inscription__vantus_rune_tides__midnight_1")
local radiantReagent
for _, reagent in ipairs(tidesVantus.reagents or {}) do
    if reagent.itemRef == "Vantus Rune: Radiant" then
        radiantReagent = reagent
        break
    end
end
assert(radiantReagent, "Vantus Rune: Tides Radiant reagent is missing")
AssertEqual(radiantReagent.itemIDs[1], 245879,
    "Vantus Rune: Tides Radiant R1 reagent item")
AssertEqual(radiantReagent.itemIDs[2], 245880,
    "Vantus Rune: Tides Radiant R2 reagent item")
local refineStone = GAM.Importer.GetStratByID(
    "jewelcrafting__refine_dusk_shrouded_stone__midnight_1")
AssertEqual(refineStone.reagents[1].quantityPerCraft, 18,
    "live 12.1 Dusk-Shrouded Stone refinement input")
AssertEqual(refineStone.recipeName, "Refine Duskshrouded Stone",
    "single-source live recipe name")
AssertEqual(refineStone.defaultStartingAmount, 18000,
    "single-source derived starting amount")
AssertEqual(refineStone.statProfileKey, "jc_refine",
    "single-source refinement stat profile")

for profession, expected in pairs(GAM.CommodityManifest.professionCounts) do
    AssertEqual(#GAM.Importer.GetStratsByProfession(profession), expected,
        profession .. " strategy count")
end

for _, strategy in ipairs(GAM.Importer.GetAllStrats()) do
    assert(not strategy.disabledReason, strategy.id .. ": disabled strategy was loaded")
    assert(type(strategy.recipeID) == "number" and strategy.recipeID > 0,
        strategy.id .. ": retained strategy has no canonical recipe ID")
    assert(type(strategy.recipeName) == "string" and strategy.recipeName ~= "",
        strategy.id .. ": retained strategy has no canonical recipe name")
    AssertEqual(strategy.schemaVersion, GAM.StrategyModel.SCHEMA_VERSION,
        strategy.id .. ": canonical schema version")
    if strategy.calcMode == "formula" then
        assert(strategy.statProfileKey,
            strategy.id .. ": formula strategy has no canonical stat profile")
    end
    for _, output in ipairs(strategy.outputs or {}) do
        assert(#(output.itemIDs or {}) > 0, strategy.id .. ": output has no item IDs")
        for _, itemID in ipairs(output.itemIDs or {}) do
            assert(GAM.CommodityCatalog.IsItemID(itemID),
                string.format("%s: output %d is not a commodity", strategy.id, itemID))
        end
    end
    for index, reagent in ipairs(strategy.reagents or {}) do
        assert(type(reagent.quantityPerCraft) == "number",
            string.format("%s: reagent %d has no canonical quantity", strategy.id, index))
    end
    for variantKey, variant in pairs(strategy.rankVariants or {}) do
        for _, output in ipairs(variant.outputs or {}) do
            assert(#(output.itemIDs or {}) > 0,
                string.format("%s variant %s: output has no item IDs", strategy.id, variantKey))
            for _, itemID in ipairs(output.itemIDs or {}) do
                assert(GAM.CommodityCatalog.IsItemID(itemID),
                    string.format("%s variant %s: output %d is not a commodity",
                        strategy.id, variantKey, itemID))
            end
        end
    end
end

local dazzling = GAM.Importer.GetStratByID(
    "jewelcrafting__dazzling_thorium_prospecting__midnight_1")
assert(dazzling, "Dazzling Thorium Prospecting was not retained")
AssertEqual(dazzling.calcMode, "formula", "Dazzling Thorium formula conversion")
AssertEqual(dazzling.statProfileKey, "jc_prospect", "Dazzling Thorium stat profile")

local radiantShatter = GAM.Importer.GetStratByID(
    "enchanting__radiant_shatter_q2__midnight_1")
assert(radiantShatter, "Radiant Shatter was not retained")
AssertEqual(radiantShatter.recipeID, 1280394,
    "Radiant Shatter recipe-scoped stat identity")

local dawnShatter = GAM.Importer.GetStratByID(
    "enchanting__dawn_shatter_q2__midnight_1")
assert(dawnShatter, "Dawn Shatter was not retained")
AssertEqual(dawnShatter.recipeID, 1280401,
    "Dawn Shatter recipe-scoped stat identity")

local phoenixOil = GAM.Importer.GetStratByID(
    "enchanting__thalassian_phoenix_oil__midnight_1")
assert(phoenixOil, "Thalassian Phoenix Oil was not retained")
AssertEqual(phoenixOil.recipeID, 1236491,
    "Thalassian Phoenix Oil recipe-scoped stat identity")

local auroraMissive = GAM.Importer.GetStratByID(
    "inscription__aurora_missive__midnight_1")
assert(auroraMissive, "Thalassian Missive of the Aurora was not retained")
AssertEqual(auroraMissive.recipeID, 1230042,
    "Thalassian Missive of the Aurora recipe-scoped stat identity")
local auroraMoteQty = nil
for _, reagent in ipairs(auroraMissive.reagents or {}) do
    if reagent.itemIDs and reagent.itemIDs[1] == 236950 then
        auroraMoteQty = reagent.quantityPerCraft
    end
end
AssertEqual(auroraMoteQty, 1,
    "Thalassian Missive of the Aurora Mote quantity")

local haranirFinesse = GAM.Importer.GetStratByID(
    "alchemy__haranir_phial_of_finesse__midnight_1")
assert(haranirFinesse, "Haranir Phial of Finesse was not retained")
local finesseReagents = {}
for _, reagent in ipairs(haranirFinesse.reagents or {}) do
    finesseReagents[reagent.itemRef or reagent.name] = reagent.quantityPerCraft
end
AssertEqual(finesseReagents["Azeroot"], 3,
    "Haranir Phial of Finesse Azeroot quantity")
AssertEqual(finesseReagents["Mana Lily"], 6,
    "Haranir Phial of Finesse Mana Lily quantity")
assert(finesseReagents["Argentleaf"] == nil,
    "Haranir Phial of Finesse retained stale Argentleaf reagent")

for _, strategyID in ipairs({
    "inscription__feverflare_missive__midnight_1",
    "inscription__fireflash_missive__midnight_1",
}) do
    local missive = GAM.Importer.GetStratByID(strategyID)
    assert(missive, strategyID .. ": missive was not retained")
    local moteQty = nil
    for _, reagent in ipairs(missive.reagents or {}) do
        if reagent.itemIDs and reagent.itemIDs[1] == 236950 then
            moteQty = reagent.quantityPerCraft
        end
    end
    AssertEqual(moteQty, 1, strategyID .. ": Mote of Primal Energy quantity")
end

local variantChecked = false
for _, strategy in ipairs(GAM.Importer.GetAllStrats()) do
    if strategy.rankVariants and strategy.rankVariants.lowest then
        local active = GAM.StrategyModel.ResolveActiveRecipeView(strategy, "lowest")
        assert(active and active.outputs == strategy.rankVariants.lowest.outputs,
            strategy.id .. ": active rank variant was not resolved by StrategyModel")
        if strategy.rankVariants.highest then
            local optimal = GAM.StrategyModel.ResolveActiveRecipeView(strategy, "optimal")
            assert(optimal and optimal.outputs == strategy.rankVariants.highest.outputs,
                strategy.id .. ": optimal rank mix did not target the highest output variant")
        end
        variantChecked = true
        break
    end
end
assert(variantChecked, "no retained rank variant was available for resolution testing")

local flask = GAM.Importer.GetStratByID(
    "alchemy__vicious_thalassian_flask_of_honor__midnight_1")
assert(flask, "Vicious Thalassian Flask strategy was not retained")
AssertEqual(#flask.outputs[1].itemIDs, 1, "stale flask output filtering")
AssertEqual(flask.outputs[1].itemIDs[1], 241334, "retained flask output ID")
assert(not GAM.CommodityCatalog.IsItemID(241335), "stale flask item ID is still eligible")
assert(not GAM.Importer.GetStratByID(
    "blacksmithing__thalassian_blacksmith_s_hammer__midnight_1"),
    "noncommodity profession tool was loaded")

local excludedUserStrategy = {
    id = "custom__excluded_equipment__midnight_1",
    profession = "Blacksmithing",
    stratName = "Excluded Equipment",
    patchTag = "midnight-1",
    defaultStartingAmount = 1,
    defaultCrafts = 1,
    outputs = {
        { name = "Thalassian Blacksmith's Hammer", itemIDs = { 238013 },
            baseYieldPerCraft = 1, baseYield = 1 },
    },
    reagents = {
        { name = "Test Reagent", itemIDs = { 236949 }, qtyPerCraft = 1, qtyPerStart = 1 },
    },
}
GAM.db.userStrats = { excludedUserStrategy }
GAM.Importer.Init()
AssertEqual(GAM.Importer.GetStratCount(), 283, "excluded custom strategy activation")
AssertEqual(#GAM.db.userStrats, 1, "excluded custom strategy preservation")
assert(GAM.db.userStrats[1] == excludedUserStrategy,
    "excluded custom strategy was rewritten or discarded")

local eligibleUserStrategy = {
    id = "custom__commodity_flask__midnight_1",
    profession = "Alchemy",
    stratName = "Commodity Flask Test",
    patchTag = "midnight-1",
    defaultStartingAmount = 10,
    defaultCrafts = 10,
    formulaProfile = "alchemy",
    calcMode = "formula",
    outputs = {
        { name = "Vicious Thalassian Flask of Honor", itemIDs = { 241334, 241335 },
            baseYieldPerCraft = 1, baseYield = 1 },
    },
    reagents = {
        { name = "Test Reagent", itemIDs = { 236949 }, qtyPerCraft = 1, qtyPerStart = 1 },
    },
}
GAM.db.userStrats = { excludedUserStrategy, eligibleUserStrategy }
GAM.Importer.Init()
AssertEqual(GAM.Importer.GetStratCount(), 284, "eligible custom strategy activation")
AssertEqual(#GAM.db.userStrats, 2, "custom strategy preservation")
local loadedUser = GAM.Importer.GetStratByID(eligibleUserStrategy.id)
assert(loadedUser and loadedUser._isUser, "eligible custom strategy was not loaded")
assert(GAM.db.userStrats[2] == eligibleUserStrategy,
    "eligible custom strategy was rewritten instead of modeled at runtime")
AssertEqual(#loadedUser.outputs[1].itemIDs, 1, "custom output commodity filtering")
AssertEqual(loadedUser.outputs[1].itemIDs[1], 241334, "custom retained output ID")
AssertEqual(loadedUser.schemaVersion, GAM.StrategyModel.SCHEMA_VERSION,
    "runtime strategy schema version")
AssertEqual(loadedUser.reagents[1].quantityPerCraft, 1,
    "canonical reagent quantity")

local shadowedUserStrategy = {
    id = "inscription__aurora_missive__midnight_1",
    profession = "Inscription",
    stratName = "Thalassian Missive of the Aurora",
    patchTag = "midnight-1",
    defaultStartingAmount = 1,
    defaultCrafts = 1,
    formulaProfile = "obsolete_profile",
    outputs = {
        { name = "Thalassian Missive of the Aurora", itemIDs = { 245781 },
            baseYieldPerCraft = 1, baseYield = 1 },
    },
    reagents = {
        { name = "Lexicologist's Vellum", itemIDs = { 245881 },
            qtyPerCraft = 1, qtyPerStart = 1 },
    },
}
local legacyShadowedUserStrategy = {
    id = "user__legacy_aurora_copy",
    legacyID = "inscription__aurora_missive__midnight_1",
    profession = "Inscription",
    stratName = "Thalassian Missive of the Aurora",
    patchTag = "midnight-1",
    defaultStartingAmount = 1,
    defaultCrafts = 1,
    outputs = {
        { name = "Thalassian Missive of the Aurora", itemIDs = { 245781 },
            baseYieldPerCraft = 1, baseYield = 1 },
    },
    reagents = {
        { name = "Lexicologist's Vellum", itemIDs = { 245881 },
            qtyPerCraft = 1, qtyPerStart = 1 },
    },
}
GAM.db.userStrats = { shadowedUserStrategy, legacyShadowedUserStrategy }
GAM.Importer.Init()
local canonicalAurora = GAM.Importer.GetStratByID(shadowedUserStrategy.id)
assert(canonicalAurora and not canonicalAurora._isUser,
    "stale user duplicate replaced the canonical Aurora strategy")
AssertEqual(canonicalAurora.recipeID, 1230042,
    "canonical Aurora recipe ID after user duplicate")
AssertEqual(canonicalAurora.statProfileKey, "insc_ink",
    "canonical Aurora stat profile after user duplicate")
assert(not GAM.Importer.GetStratByID(legacyShadowedUserStrategy.id),
    "legacy-ID user duplicate remained active")
AssertEqual(#GAM.db.userStrats, 2, "shadowed user strategy preservation")
assert(GAM.db.userStrats[1] == shadowedUserStrategy,
    "shadowed user strategy was rewritten or discarded")
assert(GAM.db.userStrats[2] == legacyShadowedUserStrategy,
    "legacy-ID shadowed user strategy was rewritten or discarded")
local shadowStats = GAM.Importer.GetInitStats()
AssertEqual(shadowStats.shadowedUserSkipped, 2,
    "shadowed user strategy accounting")

print("PASS: commodity catalog and importer regression checks")

-- Live Tailoring audit: both Eversinging Dust ranks are accepted by recipe 1228976.
local spellthread
for _, strat in ipairs(GAM.Importer.GetAllStrats()) do
    if strat.recipeID == 1228976 then spellthread = strat end
end
assert(spellthread, "Bright Linen Spellthread missing from retained catalog")
local dust
for _, reagent in ipairs(spellthread.reagents) do
    if reagent.itemRef == "Eversinging Dust" then dust = reagent end
end
assert(dust and #dust.itemIDs == 2 and dust.itemIDs[1] == 243599 and dust.itemIDs[2] == 243600,
    "Bright Linen Spellthread must retain both live dust ranks")
assert(dust.quantityPerCraft == 2, "dust requirement must remain two per craft")
