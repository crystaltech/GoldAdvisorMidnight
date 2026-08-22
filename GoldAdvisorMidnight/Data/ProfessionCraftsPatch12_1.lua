-- GoldAdvisorMidnight/Data/ProfessionCraftsPatch12_1.lua
-- Compact maintenance facts for live Retail 12.1 additions.
-- Kept separate from the generated Midnight launch catalog so patch identity
-- and rollback boundaries remain obvious.

GAM_PROFESSION_CRAFTS = GAM_PROFESSION_CRAFTS or {}
GAM_RUNTIME_PROFESSION_CRAFTS = GAM_RUNTIME_PROFESSION_CRAFTS or {}

local SOURCE = "Retail DB2 12.1.0.69299"
local NOTES = "Verified against live 12.1 spell, reagent, crafting-data, and item tables."

local function Add(profession, craft)
    craft.sourceBlock = SOURCE
    craft.notes = NOTES
    GAM_PROFESSION_CRAFTS[profession] = GAM_PROFESSION_CRAFTS[profession] or {}
    table.insert(GAM_PROFESSION_CRAFTS[profession], craft)
    GAM_RUNTIME_PROFESSION_CRAFTS[#GAM_RUNTIME_PROFESSION_CRAFTS + 1] = {
        profession = profession,
        craft = craft,
    }
end

Add("Alchemy", {
    id = "alchemy__concentrated_silvermoon_health_potion__midnight_1",
    name = "Concentrated Silvermoon Health Potion",
    patchTag = "midnight-1",
    recipeID = 1289744,
    formulaProfile = "alchemy",
    inputs = {
        { itemRef = "Cursebound Globe", itemIDs = { 274781 }, amount = 2 },
        { itemRef = "Silvermoon Health Potion", itemIDs = { 241304, 241305 }, amount = 25 },
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
        { itemRef = "Tranquility Bloom", itemIDs = { 236761, 236767 }, amount = 8 },
        { itemRef = "Sanguithorn", itemIDs = { 236770, 236771 }, amount = 6 },
        { itemRef = "Sunglass Vial", itemIDs = { 240990, 240991 }, amount = 5 },
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
        { itemRef = "Tranquility Bloom", itemIDs = { 236761, 236767 }, amount = 8 },
        { itemRef = "Sanguithorn", itemIDs = { 236770, 236771 }, amount = 3 },
        { itemRef = "Mana Lily", itemIDs = { 236778, 236779 }, amount = 3 },
        { itemRef = "Sunglass Vial", itemIDs = { 240990, 240991 }, amount = 5 },
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
        { itemRef = "Flawless Amani Lapis", itemIDs = { 242612, 242727 }, amount = 1 },
        { itemRef = "Eversinging Dust", itemIDs = { 243599, 243600 }, amount = 20 },
        { itemRef = "Radiant Shard", itemIDs = { 243602, 243603 }, amount = 10 },
        { itemRef = "Dawn Crystal", itemIDs = { 243605, 243606 }, amount = 2 },
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
        { itemRef = "Evercore", itemIDs = { 243581, 243582 }, amount = 20 },
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
        { itemRef = "Soul Cipher", itemIDs = { 245766, 245767 }, amount = 1 },
        { itemRef = "Vantus Rune: Radiant", itemIDs = { 245879 }, amount = 1 },
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
        { itemRef = "Munsell Ink", itemIDs = { 245801, 245802 }, amount = 1 },
        { itemRef = "Sienna Ink", itemIDs = { 245805, 245806 }, amount = 1 },
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
    formulaProfile = "jc_refine",
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
    recipeName = "Refine Duskshrouded Stone",
    formulaProfile = "jc_refine",
    inputs = {
        { itemRef = "Dusk-Shrouded Stone", itemIDs = { 242788 }, amount = 18 },
    },
    outputs = {
        { itemRef = "Dusk-Shrouded Stone", itemIDs = { 242789 }, baseAmount = 1 },
    },
})
