-- GoldAdvisorMidnight/Data/ProfessionCraftsPatch12_1.lua
-- Compact maintenance facts for live Retail 12.1 additions.
-- Kept separate from the generated Midnight launch catalog so patch identity
-- and rollback boundaries remain obvious.

local ADDON_NAME, GAM = ...
GAM.ProfessionCrafts = GAM.ProfessionCrafts or {}
GAM.RuntimeProfessionCrafts = GAM.RuntimeProfessionCrafts or {}
local professionCrafts = GAM.ProfessionCrafts
local runtimeProfessionCrafts = GAM.RuntimeProfessionCrafts

local SOURCE = "Retail DB2 12.1.0.69299"
local NOTES = "Verified against live 12.1 spell, reagent, crafting-data, and item tables."

local function Add(profession, craft)
    craft.sourceBlock = SOURCE
    craft.notes = NOTES
    professionCrafts[profession] = professionCrafts[profession] or {}
    table.insert(professionCrafts[profession], craft)
    runtimeProfessionCrafts[#runtimeProfessionCrafts + 1] = {
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
        { itemRef = "Silvermoon Health Potion", itemIDs = { 241305, 241304 }, amount = 25 },
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
        { itemRef = "Sunglass Vial", itemIDs = { 240991, 240990 }, amount = 5 },
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
        { itemRef = "Sunglass Vial", itemIDs = { 240991, 240990 }, amount = 5 },
    },
    outputs = {
        { itemRef = "Alluring Nostrum", itemIDs = { 271889, 271890 }, baseAmount = 5 },
    },
})

Add("Cooking", {
    id = "cooking__feast_of_knowledge__midnight_1",
    name = "Feast of Knowledge",
    patchTag = "midnight-1",
    recipeID = 1295777,
    formulaProfile = "cooking",
    inputs = {
        { itemRef = "Coiled Stargorger", itemIDs = { 274591 }, amount = 10 },
        { itemRef = "Sulfurous Sludgefish", itemIDs = { 274590 }, amount = 20 },
        { itemRef = "Thalassian Fillet", itemIDs = { 253403 }, amount = 50 },
        { itemRef = "Cursebound Globe", itemIDs = { 274781 }, amount = 3 },
        { itemRef = "Petrified Root", itemIDs = { 251285 }, amount = 1 },
    },
    outputs = {
        { itemRef = "Feast of Knowledge", itemIDs = { 275266 }, baseAmount = 2 },
    },
})

-- Cooking salvage: one plant or animal part per craft, any of five single-rank
-- commodities. Yield varies with Cooking skill; 3 is just under observed
-- max-skill averages (about 3.1 per part including Resourcefulness).
Add("Cooking", {
    id = "cooking__plant_protein__midnight_1",
    name = "Plant Protein",
    patchTag = "midnight-1",
    recipeID = 1296450,
    formulaProfile = "cook_salvage",
    inputs = {
        {
            itemRef = "Cheapest Plant Part",
            itemIDs = { 275286 },
            amount = 1,
            cheapestOf = {
                { itemRef = "Malleable Root",         itemIDs = { 275285 } },
                { itemRef = "Leafy Appendage",        itemIDs = { 275286 } },
                { itemRef = "Cellular Slab",          itemIDs = { 275287 } },
                { itemRef = "Photosynthesized Scrap", itemIDs = { 275288 } },
                { itemRef = "Winged Stalk",           itemIDs = { 275289 } },
            },
        },
    },
    outputs = {
        { itemRef = "Plant Protein", itemIDs = { 242640 }, baseAmount = 3 },
    },
})

Add("Cooking", {
    id = "cooking__practically_pork__midnight_1",
    name = "Practically Pork",
    patchTag = "midnight-1",
    recipeID = 1296449,
    formulaProfile = "cook_salvage",
    inputs = {
        {
            itemRef = "Cheapest Animal Part",
            itemIDs = { 275280 },
            amount = 1,
            cheapestOf = {
                { itemRef = "Gamey Flank",      itemIDs = { 275280 } },
                { itemRef = "Folded Wing",      itemIDs = { 275281 } },
                { itemRef = "Smooth Loin",      itemIDs = { 275282 } },
                { itemRef = "Amphibious Scrap", itemIDs = { 275283 } },
                { itemRef = "Slobbery Tongue",  itemIDs = { 275284 } },
            },
        },
    },
    outputs = {
        { itemRef = "Practically Pork", itemIDs = { 242639 }, baseAmount = 3 },
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
        { itemRef = "Vantus Rune: Radiant", itemIDs = { 245879, 245880 }, amount = 1 },
    },
    outputs = {
        { itemRef = "Vantus Rune: Tides", itemIDs = { 272194, 272195 }, baseAmount = 1 },
    },
})

Add("Inscription", {
    id = "inscription__contract_zuljarras_forces__midnight_1",
    name = "Contract: Zul'jarra's Forces",
    patchTag = "midnight-1",
    recipeID = 1303151,
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
