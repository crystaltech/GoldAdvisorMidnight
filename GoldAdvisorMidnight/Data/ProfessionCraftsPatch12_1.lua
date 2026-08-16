-- GoldAdvisorMidnight/Data/ProfessionCraftsPatch12_1.lua
-- Compact maintenance facts for live Retail 12.1 additions.
-- Kept separate from the generated Midnight launch catalog so patch identity
-- and rollback boundaries remain obvious.

GAM_PROFESSION_CRAFTS = GAM_PROFESSION_CRAFTS or {}

local function Add(profession, craft)
    GAM_PROFESSION_CRAFTS[profession] = GAM_PROFESSION_CRAFTS[profession] or {}
    table.insert(GAM_PROFESSION_CRAFTS[profession], craft)
end

Add("Alchemy", {
    id = "alchemy__concentrated_silvermoon_health_potion__midnight_1",
    name = "Concentrated Silvermoon Health Potion",
    patchTag = "midnight-1",
    recipeID = 1289744,
    formulaProfile = "alchemy",
    inputs = {
        { itemRef = "Cursebound Globe", itemIDs = { 274781 }, amount = 2 },
    },
    outputs = {
        { itemRef = "Concentrated Silvermoon Health Potion", itemIDs = { 271883, 271884 }, baseAmount = 5 },
    },
})

Add("Alchemy", {
    id = "alchemy__liquid_luster__midnight_1",
    name = "Liquid Luster",
    patchTag = "midnight-1",
    recipeID = 1289745,
    formulaProfile = "alchemy",
    inputs = {
        { itemRef = "Neutralized Venom Clot", itemIDs = { 274777 }, amount = 1 },
        { itemRef = "Cursebound Globe", itemIDs = { 274781 }, amount = 1 },
    },
    outputs = {
        { itemRef = "Liquid Luster", itemIDs = { 271886, 271887 }, baseAmount = 5 },
    },
})

Add("Alchemy", {
    id = "alchemy__alluring_nostrum__midnight_1",
    name = "Alluring Nostrum",
    patchTag = "midnight-1",
    recipeID = 1289746,
    formulaProfile = "alchemy",
    inputs = {
        { itemRef = "Neutralized Venom Clot", itemIDs = { 274777 }, amount = 1 },
        { itemRef = "Cursebound Globe", itemIDs = { 274781 }, amount = 1 },
    },
    outputs = {
        { itemRef = "Alluring Nostrum", itemIDs = { 271889, 271890 }, baseAmount = 5 },
    },
})

Add("Enchanting", {
    id = "enchanting__rite_of_the_hashey__midnight_1",
    name = "Enchant Weapon - Rite of the Hash'ey",
    patchTag = "midnight-1",
    recipeID = 1291694,
    formulaProfile = "ench_craft",
    inputs = {
        { itemRef = "Cursebound Globe", itemIDs = { 274781 }, amount = 5 },
        { itemRef = "Petrified Root", itemIDs = { 251285 }, amount = 4 },
    },
    outputs = {
        { itemRef = "Enchant Weapon - Rite of the Hash'ey", itemIDs = { 273071, 273072 }, baseAmount = 1 },
    },
})

Add("Engineering", {
    id = "engineering__r0cky_to_go__midnight_1",
    name = "R0CKY-To-Go",
    patchTag = "midnight-1",
    recipeID = 1305148,
    formulaProfile = "engineering_craft",
    inputs = {
        { itemRef = "Pile of Junk", itemIDs = { 253303 }, amount = 10 },
        { itemRef = "Neutralized Venom Clot", itemIDs = { 274777 }, amount = 10 },
    },
    outputs = {
        { itemRef = "R0CKY-To-Go", itemIDs = { 275676 }, baseAmount = 3 },
    },
})

Add("Inscription", {
    id = "inscription__vantus_rune_tides__midnight_1",
    name = "Vantus Rune: Tides",
    patchTag = "midnight-1",
    recipeID = 1290561,
    formulaProfile = "insc_ink",
    inputs = {
        { itemRef = "Thalassian Songwater", itemIDs = { 245882 }, amount = 1 },
        { itemRef = "Lexicologist's Vellum", itemIDs = { 245881 }, amount = 1 },
        { itemRef = "Petrified Root", itemIDs = { 251285 }, amount = 2 },
        { itemRef = "Cursebound Globe", itemIDs = { 274781 }, amount = 2 },
    },
    outputs = {
        { itemRef = "Vantus Rune: Tides", itemIDs = { 272194, 272195 }, baseAmount = 1 },
    },
})

Add("Inscription", {
    id = "inscription__contract_zuljarras_forces__midnight_1",
    name = "Contract: Zul'jarra's Forces",
    patchTag = "midnight-1",
    recipeID = 1303144,
    formulaProfile = "insc_ink",
    inputs = {
        { itemRef = "Lexicologist's Vellum", itemIDs = { 245881 }, amount = 1 },
        { itemRef = "Neutralized Venom Clot", itemIDs = { 274777 }, amount = 3 },
    },
    outputs = {
        { itemRef = "Contract: Zul'jarra's Forces", itemIDs = { 277968, 277969 }, baseAmount = 1 },
    },
})

Add("Jewelcrafting", {
    id = "jewelcrafting__refine_crystalline_glass__midnight_1",
    name = "Refine Crystalline Glass",
    patchTag = "midnight-1",
    recipeID = 1307462,
    formulaProfile = "jc_craft",
    inputs = {
        { itemRef = "Crystalline Glass", itemIDs = { 242787 }, amount = 10 },
    },
    outputs = {
        { itemRef = "Crystalline Glass", itemIDs = { 242786 }, baseAmount = 1 },
    },
})

Add("Jewelcrafting", {
    id = "jewelcrafting__refine_dusk_shrouded_stone__midnight_1",
    name = "Refine Dusk-Shrouded Stone",
    patchTag = "midnight-1",
    recipeID = 1307466,
    formulaProfile = "jc_craft",
    inputs = {
        { itemRef = "Dusk-Shrouded Stone", itemIDs = { 242788 }, amount = 18 },
    },
    outputs = {
        { itemRef = "Dusk-Shrouded Stone", itemIDs = { 242789 }, baseAmount = 1 },
    },
})
