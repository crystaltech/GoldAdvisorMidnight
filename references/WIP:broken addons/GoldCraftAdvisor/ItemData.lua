-- GoldCraft Advisor - ItemData.lua
-- Item ID database and mappings - VERIFIED CORRECT IDs
-- Each TWW material has quality tiers with DIFFERENT item IDs

local _, GCA = ...
GCA.ItemDB = {}

-- ================= Item Categories =================
local CATEGORY = {
    HERB = "Herbs",
    ORE = "Ore",
    METAL = "Metal",
    CLOTH = "Cloth",
    LEATHER = "Leather",
    ENCHANTING = "Enchanting",
    INSCRIPTION = "Inscription",
    JEWELCRAFTING = "Jewelcrafting",
    ALCHEMY = "Alchemy",
    COOKING = "Cooking",
    ENGINEERING = "Engineering",
    MISC = "Miscellaneous",
}

-- ================= Expansion Markers =================
-- Prep for future expansion items
local EXPANSION = {
    TWW = "The War Within",
    MIDNIGHT = "Midnight",
}
GCA.EXPANSION = EXPANSION

-- Current expansion for all items below
local CURRENT_EXPANSION = EXPANSION.TWW

-- ================= Item Database =================
-- Format: [itemID] = { name = "Item Name", category = CATEGORY.X, rank = 1/2/3, expansion = EXPANSION.X }
-- VERIFIED IDs from in-game AH scanning
-- NOTE: All current items are TWW expansion. Expansion field defaults to TWW if not specified.
-- When Midnight items are added, set expansion = EXPANSION.MIDNIGHT explicitly.

GCA.ItemDB = {
    -- ======================
    -- HERBS
    -- ======================
    [210796] = { name = "Mycobloom", category = CATEGORY.HERB, rank = 1 },
    [210797] = { name = "Mycobloom", category = CATEGORY.HERB, rank = 2 },
    [210798] = { name = "Mycobloom", category = CATEGORY.HERB, rank = 3 },

    [210799] = { name = "Luredrop", category = CATEGORY.HERB, rank = 1 },
    [210800] = { name = "Luredrop", category = CATEGORY.HERB, rank = 2 },
    [210801] = { name = "Luredrop", category = CATEGORY.HERB, rank = 3 },

    [210802] = { name = "Orbinid", category = CATEGORY.HERB, rank = 1 },
    [210803] = { name = "Orbinid", category = CATEGORY.HERB, rank = 2 },
    [210804] = { name = "Orbinid", category = CATEGORY.HERB, rank = 3 },

    [210805] = { name = "Blessing Blossom", category = CATEGORY.HERB, rank = 1 },
    [210806] = { name = "Blessing Blossom", category = CATEGORY.HERB, rank = 2 },
    [210807] = { name = "Blessing Blossom", category = CATEGORY.HERB, rank = 3 },

    [210808] = { name = "Arathor's Spear", category = CATEGORY.HERB, rank = 1 },
    [210809] = { name = "Arathor's Spear", category = CATEGORY.HERB, rank = 2 },
    [210810] = { name = "Arathor's Spear", category = CATEGORY.HERB, rank = 3 },

    -- ======================
    -- ORE
    -- ======================
    [210930] = { name = "Bismuth", category = CATEGORY.ORE, rank = 1 },
    [210931] = { name = "Bismuth", category = CATEGORY.ORE, rank = 2 },
    [210932] = { name = "Bismuth", category = CATEGORY.ORE, rank = 3 },

    [210933] = { name = "Aqirite", category = CATEGORY.ORE, rank = 1 },
    [210934] = { name = "Aqirite", category = CATEGORY.ORE, rank = 2 },
    [210935] = { name = "Aqirite", category = CATEGORY.ORE, rank = 3 },

    [210936] = { name = "Ironclaw Ore", category = CATEGORY.ORE, rank = 1 },
    [210937] = { name = "Ironclaw Ore", category = CATEGORY.ORE, rank = 2 },
    [210938] = { name = "Ironclaw Ore", category = CATEGORY.ORE, rank = 3 },

    -- ======================
    -- LEATHER
    -- ======================
    [212664] = { name = "Stormcharged Leather", category = CATEGORY.LEATHER, rank = 1 },
    [212665] = { name = "Stormcharged Leather", category = CATEGORY.LEATHER, rank = 2 },
    [212666] = { name = "Stormcharged Leather", category = CATEGORY.LEATHER, rank = 3 },

    [212667] = { name = "Gloom Chitin", category = CATEGORY.LEATHER, rank = 1 },
    [212668] = { name = "Gloom Chitin", category = CATEGORY.LEATHER, rank = 2 },
    [212669] = { name = "Gloom Chitin", category = CATEGORY.LEATHER, rank = 3 },

    -- ======================
    -- ENCHANTING
    -- ======================
    [219946] = { name = "Storm Dust", category = CATEGORY.ENCHANTING, rank = 1 },
    [219947] = { name = "Storm Dust", category = CATEGORY.ENCHANTING, rank = 2 },
    [219948] = { name = "Storm Dust", category = CATEGORY.ENCHANTING, rank = 3 },

    [219949] = { name = "Gleaming Shard", category = CATEGORY.ENCHANTING, rank = 1 },
    [219950] = { name = "Gleaming Shard", category = CATEGORY.ENCHANTING, rank = 2 },
    [219951] = { name = "Gleaming Shard", category = CATEGORY.ENCHANTING, rank = 3 },

    -- ======================
    -- INSCRIPTION
    -- ======================
    [222555] = { name = "Codified Greenwood", category = CATEGORY.INSCRIPTION, rank = 1 },
    [222556] = { name = "Codified Greenwood", category = CATEGORY.INSCRIPTION, rank = 2 },
    [222557] = { name = "Codified Greenwood", category = CATEGORY.INSCRIPTION, rank = 3 },

    [222558] = { name = "Boundless Cipher", category = CATEGORY.INSCRIPTION, rank = 1 },
    [222559] = { name = "Boundless Cipher", category = CATEGORY.INSCRIPTION, rank = 2 },
    [222560] = { name = "Boundless Cipher", category = CATEGORY.INSCRIPTION, rank = 3 },

    [222609] = { name = "Shadow Ink", category = CATEGORY.INSCRIPTION, rank = 1 },
    [222610] = { name = "Shadow Ink", category = CATEGORY.INSCRIPTION, rank = 2 },
    [222611] = { name = "Shadow Ink", category = CATEGORY.INSCRIPTION, rank = 3 },

    [222612] = { name = "Luredrop Pigment", category = CATEGORY.INSCRIPTION, rank = 1 },
    [222613] = { name = "Luredrop Pigment", category = CATEGORY.INSCRIPTION, rank = 2 },
    [222614] = { name = "Luredrop Pigment", category = CATEGORY.INSCRIPTION, rank = 3 },

    [222615] = { name = "Apricate Ink", category = CATEGORY.INSCRIPTION, rank = 1 },
    [222616] = { name = "Apricate Ink", category = CATEGORY.INSCRIPTION, rank = 2 },
    [222617] = { name = "Apricate Ink", category = CATEGORY.INSCRIPTION, rank = 3 },

    [213612] = { name = "Viridescent Spores", category = CATEGORY.INSCRIPTION, rank = 0 },

    -- ======================
    -- JEWELCRAFTING
    -- ======================
    [213219] = { name = "Crushed Gemstones", category = CATEGORY.JEWELCRAFTING, rank = 1 },
    [213220] = { name = "Crushed Gemstones", category = CATEGORY.JEWELCRAFTING, rank = 2 },
    [213221] = { name = "Crushed Gemstones", category = CATEGORY.JEWELCRAFTING, rank = 3 },

    [212498] = { name = "Ambivalent Amber", category = CATEGORY.JEWELCRAFTING, rank = 0 },
    [212495] = { name = "Radiant Ruby", category = CATEGORY.JEWELCRAFTING, rank = 0 },
    [212505] = { name = "Extravagant Emerald", category = CATEGORY.JEWELCRAFTING, rank = 0 },
    [212508] = { name = "Stunning Sapphire", category = CATEGORY.JEWELCRAFTING, rank = 0 },
    [212511] = { name = "Ostentatious Onyx", category = CATEGORY.JEWELCRAFTING, rank = 0 },
    [212514] = { name = "Blasphemite", category = CATEGORY.JEWELCRAFTING, rank = 0 },
    [213398] = { name = "Handful of Pebbles", category = CATEGORY.JEWELCRAFTING, rank = 0 },
    [213399] = { name = "Glittering Glass", category = CATEGORY.JEWELCRAFTING, rank = 0 },

    -- ======================
    -- ALCHEMY
    -- ======================
    [212260] = { name = "Frontline Potion", category = CATEGORY.ALCHEMY, rank = 1 },
    [212261] = { name = "Frontline Potion", category = CATEGORY.ALCHEMY, rank = 2 },
    [212262] = { name = "Frontline Potion", category = CATEGORY.ALCHEMY, rank = 3 },

    [212263] = { name = "Tempered Potion", category = CATEGORY.ALCHEMY, rank = 1 },
    [212264] = { name = "Tempered Potion", category = CATEGORY.ALCHEMY, rank = 2 },
    [212265] = { name = "Tempered Potion", category = CATEGORY.ALCHEMY, rank = 3 },

    [212269] = { name = "Flask of Tempered Aggression", category = CATEGORY.ALCHEMY, rank = 1 },
    [212270] = { name = "Flask of Tempered Aggression", category = CATEGORY.ALCHEMY, rank = 2 },
    [212271] = { name = "Flask of Tempered Aggression", category = CATEGORY.ALCHEMY, rank = 3 },

    [212272] = { name = "Flask of Tempered Swiftness", category = CATEGORY.ALCHEMY, rank = 1 },
    [212273] = { name = "Flask of Tempered Swiftness", category = CATEGORY.ALCHEMY, rank = 2 },
    [212274] = { name = "Flask of Tempered Swiftness", category = CATEGORY.ALCHEMY, rank = 3 },

    [212275] = { name = "Flask of Tempered Versatility", category = CATEGORY.ALCHEMY, rank = 1 },
    [212276] = { name = "Flask of Tempered Versatility", category = CATEGORY.ALCHEMY, rank = 2 },
    [212277] = { name = "Flask of Tempered Versatility", category = CATEGORY.ALCHEMY, rank = 3 },

    [212278] = { name = "Flask of Tempered Mastery", category = CATEGORY.ALCHEMY, rank = 1 },
    [212279] = { name = "Flask of Tempered Mastery", category = CATEGORY.ALCHEMY, rank = 2 },
    [212280] = { name = "Flask of Tempered Mastery", category = CATEGORY.ALCHEMY, rank = 3 },

    [212281] = { name = "Flask of Alchemical Chaos", category = CATEGORY.ALCHEMY, rank = 1 },
    [212282] = { name = "Flask of Alchemical Chaos", category = CATEGORY.ALCHEMY, rank = 2 },
    [212283] = { name = "Flask of Alchemical Chaos", category = CATEGORY.ALCHEMY, rank = 3 },

    [211806] = { name = "Gilded Vial", category = CATEGORY.ALCHEMY, rank = 1 },
    [211807] = { name = "Gilded Vial", category = CATEGORY.ALCHEMY, rank = 2 },
    [211808] = { name = "Gilded Vial", category = CATEGORY.ALCHEMY, rank = 3 },

    [213197] = { name = "Null Lotus", category = CATEGORY.ALCHEMY, rank = 0 },
    [213611] = { name = "Writhing Sample", category = CATEGORY.ALCHEMY, rank = 0 },
    [213613] = { name = "Leyline Residue", category = CATEGORY.ALCHEMY, rank = 0 },

    [213756] = { name = "Marbled Stone", category = CATEGORY.ALCHEMY, rank = 1 },
    [213757] = { name = "Marbled Stone", category = CATEGORY.ALCHEMY, rank = 2 },
    [213758] = { name = "Marbled Stone", category = CATEGORY.ALCHEMY, rank = 3 },

    -- ======================
    -- ENGINEERING
    -- ======================
    [221853] = { name = "Handful of Bismuth Bolts", category = CATEGORY.ENGINEERING, rank = 1 },
    [221854] = { name = "Handful of Bismuth Bolts", category = CATEGORY.ENGINEERING, rank = 2 },
    [221855] = { name = "Handful of Bismuth Bolts", category = CATEGORY.ENGINEERING, rank = 3 },

    [221859] = { name = "Gyrating Gear", category = CATEGORY.ENGINEERING, rank = 1 },
    [221860] = { name = "Gyrating Gear", category = CATEGORY.ENGINEERING, rank = 2 },
    [221861] = { name = "Gyrating Gear", category = CATEGORY.ENGINEERING, rank = 3 },

    -- ======================
    -- BLACKSMITHING
    -- ======================
    [222417] = { name = "Core Alloy", category = CATEGORY.METAL, rank = 1 },
    [222418] = { name = "Core Alloy", category = CATEGORY.METAL, rank = 2 },
    [222419] = { name = "Core Alloy", category = CATEGORY.METAL, rank = 3 },

    [222420] = { name = "Charged Alloy", category = CATEGORY.METAL, rank = 1 },
    [222421] = { name = "Charged Alloy", category = CATEGORY.METAL, rank = 2 },
    [222422] = { name = "Charged Alloy", category = CATEGORY.METAL, rank = 3 },

    [222426] = { name = "Ironclaw Alloy", category = CATEGORY.METAL, rank = 1 },
    [222427] = { name = "Ironclaw Alloy", category = CATEGORY.METAL, rank = 2 },
    [222428] = { name = "Ironclaw Alloy", category = CATEGORY.METAL, rank = 3 },

    -- ======================
    -- TAILORING
    -- ======================
    [222789] = { name = "Spool of Duskthread", category = CATEGORY.CLOTH, rank = 1 },
    [222790] = { name = "Spool of Duskthread", category = CATEGORY.CLOTH, rank = 2 },
    [222791] = { name = "Spool of Duskthread", category = CATEGORY.CLOTH, rank = 3 },

    [222792] = { name = "Spool of Dawnthread", category = CATEGORY.CLOTH, rank = 1 },
    [222793] = { name = "Spool of Dawnthread", category = CATEGORY.CLOTH, rank = 2 },
    [222794] = { name = "Spool of Dawnthread", category = CATEGORY.CLOTH, rank = 3 },

    [222795] = { name = "Spool of Weaverthread", category = CATEGORY.CLOTH, rank = 1 },
    [222796] = { name = "Spool of Weaverthread", category = CATEGORY.CLOTH, rank = 2 },
    [222797] = { name = "Spool of Weaverthread", category = CATEGORY.CLOTH, rank = 3 },

    [222804] = { name = "Weavercloth Bolt", category = CATEGORY.CLOTH, rank = 1 },
    [222805] = { name = "Weavercloth Bolt", category = CATEGORY.CLOTH, rank = 2 },
    [222806] = { name = "Weavercloth Bolt", category = CATEGORY.CLOTH, rank = 3 },

    -- ======================
    -- THAUMATURGY (Base Cloth)
    -- ======================
    [228231] = { name = "Weavercloth", category = CATEGORY.MISC, rank = 1 },
    [228232] = { name = "Weavercloth", category = CATEGORY.MISC, rank = 2 },

    [228233] = { name = "Duskweave", category = CATEGORY.MISC, rank = 1 },
    [228234] = { name = "Duskweave", category = CATEGORY.MISC, rank = 2 },

    [228235] = { name = "Dawnweave", category = CATEGORY.MISC, rank = 1 },
    [228236] = { name = "Dawnweave", category = CATEGORY.MISC, rank = 2 },
}

-- ================= Helper Functions =================

-- Get item info from database
function GCA:GetItemInfo(itemID)
    return self.ItemDB[itemID]
end

-- Get item name (prefer WoW API for accuracy)
function GCA:GetItemName(itemID)
    if not itemID then return nil end

    -- Use WoW API first (always accurate)
    local wowName = C_Item.GetItemNameByID(itemID)
    if wowName then
        return wowName
    end

    -- Fallback to legacy API
    local name = GetItemInfo(itemID)
    if name then
        return name
    end

    -- Last resort: our database
    local dbInfo = self.ItemDB[itemID]
    if dbInfo and dbInfo.name then
        return dbInfo.name
    end

    return "Item " .. itemID
end

-- Get item category
function GCA:GetItemCategory(itemID)
    local dbInfo = self.ItemDB[itemID]
    if dbInfo and dbInfo.category then
        return dbInfo.category
    end
    return CATEGORY.MISC
end

-- Get item rank from database
function GCA:GetItemRank(itemID)
    local dbInfo = self.ItemDB[itemID]
    if dbInfo and dbInfo.rank then
        return dbInfo.rank
    end
    return 0
end

-- Get item expansion (defaults to TWW if not specified)
function GCA:GetItemExpansion(itemID)
    local dbInfo = self.ItemDB[itemID]
    if dbInfo and dbInfo.expansion then
        return dbInfo.expansion
    end
    -- Default all current items to TWW
    return EXPANSION.TWW
end

-- Get all unique item IDs from the database
function GCA:GetAllItemIDs()
    local result = {}
    for itemID in pairs(self.ItemDB) do
        result[#result + 1] = itemID
    end
    table.sort(result)
    return result
end

-- Export categories constant for external use
GCA.CATEGORY = CATEGORY
