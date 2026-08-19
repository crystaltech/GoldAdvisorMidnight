-- GoldAdvisorMidnight/Data/Strategies/Patch12_1.lua
-- Reviewed live-patch additions that are not part of the pinned workbook.
-- Source: WoW Retail 12.1.0.69299 DB2 tables, verified 2026-08-15.

GAM_RECIPES_GENERATED = GAM_RECIPES_GENERATED or {}

local SOURCE = "Retail DB2 12.1.0.69299"

local function Add(strategy)
    strategy.patchTag = "midnight-1"
    strategy.sourceTab = strategy.profession
    strategy.sourceBlock = SOURCE
    strategy.calcMode = "formula"
    strategy.qualityPolicy = "normal"
    strategy.outputQualityMode = "rank_policy"
    strategy.notes = "Verified against live 12.1 spell, reagent, crafting-data, and item tables."
    GAM_RECIPES_GENERATED[#GAM_RECIPES_GENERATED + 1] = strategy
end

Add({
    id = "alchemy__concentrated_silvermoon_health_potion__midnight_1",
    profession = "Alchemy",
    stratName = "Concentrated Silvermoon Health Potion",
    recipeID = 1289744,
    recipeName = "Concentrated Silvermoon Health Potion",
    defaultStartingAmount = 2000,
    defaultCrafts = 1000,
    formulaProfile = "alchemy",
    outputs = {
        { itemRef = "Concentrated Silvermoon Health Potion", itemIDs = { 271883, 271884 }, baseYieldPerCraft = 5 },
    },
    reagents = {
        { itemRef = "Cursebound Globe", itemIDs = { 274781 }, qtyPerCraft = 2 },
        { itemRef = "Silvermoon Health Potion", itemIDs = { 241304, 241305 }, qtyPerCraft = 25 },
    },
})

Add({
    id = "alchemy__liquid_luster__midnight_1",
    profession = "Alchemy",
    stratName = "Liquid Luster",
    recipeID = 1289745,
    recipeName = "Liquid Luster",
    defaultStartingAmount = 1000,
    defaultCrafts = 1000,
    formulaProfile = "alchemy",
    outputs = {
        { itemRef = "Liquid Luster", itemIDs = { 271886, 271887 }, baseYieldPerCraft = 5 },
    },
    reagents = {
        { itemRef = "Neutralized Venom Clot", itemIDs = { 274777 }, qtyPerCraft = 1 },
        { itemRef = "Cursebound Globe", itemIDs = { 274781 }, qtyPerCraft = 1 },
        { itemRef = "Tranquility Bloom", itemIDs = { 236761, 236767 }, qtyPerCraft = 8 },
        { itemRef = "Sanguithorn", itemIDs = { 236770, 236771 }, qtyPerCraft = 6 },
        { itemRef = "Sunglass Vial", itemIDs = { 240990, 240991 }, qtyPerCraft = 5 },
    },
})

Add({
    id = "alchemy__alluring_nostrum__midnight_1",
    profession = "Alchemy",
    stratName = "Alluring Nostrum",
    recipeID = 1289746,
    recipeName = "Alluring Nostrum",
    defaultStartingAmount = 1000,
    defaultCrafts = 1000,
    formulaProfile = "alchemy",
    outputs = {
        { itemRef = "Alluring Nostrum", itemIDs = { 271889, 271890 }, baseYieldPerCraft = 5 },
    },
    reagents = {
        { itemRef = "Neutralized Venom Clot", itemIDs = { 274777 }, qtyPerCraft = 1 },
        { itemRef = "Cursebound Globe", itemIDs = { 274781 }, qtyPerCraft = 1 },
        { itemRef = "Tranquility Bloom", itemIDs = { 236761, 236767 }, qtyPerCraft = 8 },
        { itemRef = "Sanguithorn", itemIDs = { 236770, 236771 }, qtyPerCraft = 3 },
        { itemRef = "Mana Lily", itemIDs = { 236778, 236779 }, qtyPerCraft = 3 },
        { itemRef = "Sunglass Vial", itemIDs = { 240990, 240991 }, qtyPerCraft = 5 },
    },
})

Add({
    id = "enchanting__rite_of_the_hashey__midnight_1",
    profession = "Enchanting",
    stratName = "Enchant Weapon - Rite of the Hash'ey",
    recipeID = 1291694,
    recipeName = "Enchant Weapon - Rite of the Hash'ey",
    defaultStartingAmount = 5000,
    defaultCrafts = 1000,
    formulaProfile = "ench_craft",
    outputs = {
        { itemRef = "Enchant Weapon - Rite of the Hash'ey", itemIDs = { 273071, 273072 }, baseYieldPerCraft = 1 },
    },
    reagents = {
        { itemRef = "Cursebound Globe", itemIDs = { 274781 }, qtyPerCraft = 5 },
        { itemRef = "Petrified Root", itemIDs = { 251285 }, qtyPerCraft = 4 },
        { itemRef = "Flawless Amani Lapis", itemIDs = { 242612, 242727 }, qtyPerCraft = 1 },
        { itemRef = "Eversinging Dust", itemIDs = { 251285 }, qtyPerCraft = 20 },
        { itemRef = "Radiant Shard", itemIDs = { 251285 }, qtyPerCraft = 10 },
        { itemRef = "Dawn Crystal", itemIDs = { 251285 }, qtyPerCraft = 2 },
    },
})

Add({
    id = "engineering__r0cky_to_go__midnight_1",
    profession = "Engineering",
    stratName = "R0CKY-To-Go",
    recipeID = 1305148,
    recipeName = "R0CKY-To-Go",
    defaultStartingAmount = 10000,
    defaultCrafts = 1000,
    formulaProfile = "engineering_craft",
    outputs = {
        { itemRef = "R0CKY-To-Go", itemIDs = { 275676 }, baseYieldPerCraft = 3 },
    },
    reagents = {
        { itemRef = "Pile of Junk", itemIDs = { 253303 }, qtyPerCraft = 10 },
        { itemRef = "Neutralized Venom Clot", itemIDs = { 274777 }, qtyPerCraft = 10 },
        { itemRef = "Evercore", itemIDs = { 243581, 243582 }, qtyPerCraft = 20 },
    },
})

Add({
    id = "inscription__vantus_rune_tides__midnight_1",
    profession = "Inscription",
    stratName = "Vantus Rune: Tides",
    recipeID = 1290561,
    recipeName = "Vantus Rune: Tides",
    defaultStartingAmount = 1000,
    defaultCrafts = 1000,
    formulaProfile = "insc_ink",
    outputs = {
        { itemRef = "Vantus Rune: Tides", itemIDs = { 272194, 272195 }, baseYieldPerCraft = 1 },
    },
    reagents = {
        { itemRef = "Thalassian Songwater", itemIDs = { 245882 }, qtyPerCraft = 1 },
        { itemRef = "Lexicologist's Vellum", itemIDs = { 245881 }, qtyPerCraft = 1 },
        { itemRef = "Petrified Root", itemIDs = { 251285 }, qtyPerCraft = 2 },
        { itemRef = "Cursebound Globe", itemIDs = { 274781 }, qtyPerCraft = 2 },
        { itemRef = "Soul Cipher", itemIDs = { 245766, 245767 }, qtyPerCraft = 1 },
        { itemRef = "Vantus Rune: Radiant", itemIDs = { 245879 }, qtyPerCraft = 1 },
    },
})

Add({
    id = "inscription__contract_zuljarras_forces__midnight_1",
    profession = "Inscription",
    stratName = "Contract: Zul'jarra's Forces",
    recipeID = 1303144,
    recipeName = "Contract: Zul'jarra's Forces",
    defaultStartingAmount = 1000,
    defaultCrafts = 1000,
    formulaProfile = "insc_ink",
    outputs = {
        { itemRef = "Contract: Zul'jarra's Forces", itemIDs = { 277968, 277969 }, baseYieldPerCraft = 1 },
    },
    reagents = {
        { itemRef = "Lexicologist's Vellum", itemIDs = { 245881 }, qtyPerCraft = 1 },
        { itemRef = "Neutralized Venom Clot", itemIDs = { 274777 }, qtyPerCraft = 3 },
        { itemRef = "Munsell Ink", itemIDs = { 245801, 245802 }, qtyPerCraft = 1 },
        { itemRef = "Sienna Ink", itemIDs = { 245805, 245806 }, qtyPerCraft = 1 },
    },
})

Add({
    id = "jewelcrafting__refine_crystalline_glass__midnight_1",
    profession = "Jewelcrafting",
    stratName = "Refine Crystalline Glass",
    recipeID = 1307462,
    recipeName = "Refine Crystalline Glass",
    defaultStartingAmount = 10000,
    defaultCrafts = 1000,
    formulaProfile = "jc_craft",
    outputs = {
        { itemRef = "Crystalline Glass", itemIDs = { 242786 }, baseYieldPerCraft = 1 },
    },
    reagents = {
        { itemRef = "Crystalline Glass", itemIDs = { 242787 }, qtyPerCraft = 10 },
    },
})

Add({
    id = "jewelcrafting__refine_dusk_shrouded_stone__midnight_1",
    profession = "Jewelcrafting",
    stratName = "Refine Dusk-Shrouded Stone",
    recipeID = 1307466,
    recipeName = "Refine Duskshrouded Stone",
    defaultStartingAmount = 18000,
    defaultCrafts = 1000,
    formulaProfile = "jc_craft",
    outputs = {
        { itemRef = "Dusk-Shrouded Stone", itemIDs = { 242789 }, baseYieldPerCraft = 1 },
    },
    reagents = {
        { itemRef = "Dusk-Shrouded Stone", itemIDs = { 242788 }, qtyPerCraft = 18 },
    },
})
