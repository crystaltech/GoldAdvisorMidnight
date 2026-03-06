-- GoldCraft Advisor - Strategies.lua
-- All crafting strategies with conversion rates from spreadsheet
-- CORRECTED ITEM IDs based on ARP SavedVariables

local _, GCA = ...
GCA.Strategies = {}

-- ================= Strategy Structure =================
-- Each strategy contains:
--   category: Profession category
--   name: Display name
--   guide: Setup recommendations
--   inputs: Array of { itemID, rank (optional), quantity, label }
--   outputs: Array of { itemID, rank (optional), avgPer, label }
--   resourcefulness: Bonus multiplier (0.21 = 21%)
--   multicraft: Bonus multiplier (0.22 = 22%)

-- ================= ITEM ID REFERENCE =================
-- Herbs: Mycobloom (210796/210797/210798), Luredrop (210799/210800/210801)
--        Orbinid (210802/210803/210804), Blessing Blossom (210805/210806/210807)
--        Arathor's Spear (210808/210809/210810)
-- Ore:   Bismuth (210930/210931/210932), Aqirite (210933/210934/210935)
--        Ironclaw Ore (210936/210937/210938)
-- Leather: Stormcharged Leather (212664/212665/212666), Gloom Chitin (212667/212668/212669)
-- Cloth: Weavercloth (228231/228232/228233) -- Thaumaturgy cloth output
-- Enchanting: Storm Dust (219946/219947/219948), Gleaming Shard (219949/219950/219951)
-- Gems: Radiant Ruby (212495), Blasphemite (212514), Handful of Pebbles (213398), Glittering Glass (213399)

-- ================= THAUMATURGY =================

GCA.Strategies["Thaumaturgy:Gloom Chitin"] = {
    category = "Thaumaturgy",
    name = "Gloom Chitin Thaumaturgy",
    guide = "21.1% resourcefulness, 75% crafting speed",
    inputs = {
        { itemID = 212668, rank = 2, quantity = 5000, label = "Gloom Chitin" },
    },
    outputs = {
        { itemID = 210800, rank = 2, avgPer = 0.17, label = "Luredrop" },
        { itemID = 228232, rank = 2, avgPer = 0.01, label = "Weavercloth" },
        { itemID = 210937, rank = 2, avgPer = 0.18, label = "Aqirite" },
        { itemID = 210934, rank = 2, avgPer = 0.03, label = "Ironclaw Ore" },
        { itemID = 210803, rank = 2, avgPer = 0.18, label = "Orbinid" },
        { itemID = 210806, rank = 2, avgPer = 0.02, label = "Blessing Blossom" },
        { itemID = 210931, rank = 2, avgPer = 0.01, label = "Bismuth" },
        { itemID = 212514, rank = 0, avgPer = 0.00, label = "Blasphemite" },
        { itemID = 219947, rank = 2, avgPer = 0.01, label = "Storm Dust" },
        { itemID = 210809, rank = 2, avgPer = 0.02, label = "Arathor's Spear" },
        { itemID = 210797, rank = 2, avgPer = 0.01, label = "Mycobloom" },
        { itemID = 212495, rank = 0, avgPer = 0.00, label = "Radiant Ruby" },
    },
    resourcefulness = 0.211,
    multicraft = 0,
}

GCA.Strategies["Thaumaturgy:Stormcharge Leather"] = {
    category = "Thaumaturgy",
    name = "Stormcharge Leather Thaumaturgy",
    guide = "21.1% resourcefulness, 75% crafting speed",
    inputs = {
        { itemID = 212665, rank = 2, quantity = 5000, label = "Stormcharged Leather" },
    },
    outputs = {
        { itemID = 210800, rank = 2, avgPer = 0.0114, label = "Luredrop" },
        { itemID = 228232, rank = 2, avgPer = 0.0204, label = "Weavercloth" },
        { itemID = 210937, rank = 2, avgPer = 0.0100, label = "Aqirite" },
        { itemID = 210934, rank = 2, avgPer = 0.1768, label = "Ironclaw Ore" },
        { itemID = 210803, rank = 2, avgPer = 0.0107, label = "Orbinid" },
        { itemID = 210806, rank = 2, avgPer = 0.1737, label = "Blessing Blossom" },
        { itemID = 210931, rank = 2, avgPer = 0.0187, label = "Bismuth" },
        { itemID = 212514, rank = 0, avgPer = 0.0017, label = "Blasphemite" },
        { itemID = 219947, rank = 2, avgPer = 0.0173, label = "Storm Dust" },
        { itemID = 210809, rank = 2, avgPer = 0.1701, label = "Arathor's Spear" },
        { itemID = 210797, rank = 2, avgPer = 0.0209, label = "Mycobloom" },
        { itemID = 212495, rank = 0, avgPer = 0.0012, label = "Radiant Ruby" },
    },
    resourcefulness = 0.211,
    multicraft = 0,
}

GCA.Strategies["Thaumaturgy:Blessing Blossom"] = {
    category = "Thaumaturgy",
    name = "Blessing Blossom Thaumaturgy",
    guide = "26.1% resourcefulness, 75% crafting speed",
    inputs = {
        { itemID = 210806, rank = 2, quantity = 5000, label = "Blessing Blossom" },
    },
    outputs = {
        { itemID = 210800, rank = 2, avgPer = 0.01, label = "Luredrop" },
        { itemID = 228232, rank = 2, avgPer = 0.02, label = "Weavercloth" },
        { itemID = 210937, rank = 2, avgPer = 0.01, label = "Aqirite" },
        { itemID = 210934, rank = 2, avgPer = 0.17, label = "Ironclaw Ore" },
        { itemID = 210803, rank = 2, avgPer = 0.01, label = "Orbinid" },
        { itemID = 212668, rank = 2, avgPer = 0.00, label = "Gloom Chitin" },
        { itemID = 210931, rank = 2, avgPer = 0.02, label = "Bismuth" },
        { itemID = 212514, rank = 0, avgPer = 0.00, label = "Blasphemite" },
        { itemID = 219947, rank = 2, avgPer = 0.02, label = "Storm Dust" },
        { itemID = 210809, rank = 2, avgPer = 0.18, label = "Arathor's Spear" },
        { itemID = 210797, rank = 2, avgPer = 0.02, label = "Mycobloom" },
        { itemID = 212665, rank = 2, avgPer = 0.17, label = "Stormcharged Leather" },
        { itemID = 212495, rank = 0, avgPer = 0.00, label = "Radiant Ruby" },
    },
    resourcefulness = 0.261,
    multicraft = 0,
}

GCA.Strategies["Thaumaturgy:Mycobloom"] = {
    category = "Thaumaturgy",
    name = "Mycobloom Thaumaturgy",
    guide = "21.1% resourcefulness, 75% crafting speed",
    inputs = {
        { itemID = 210797, rank = 2, quantity = 5000, label = "Mycobloom" },
    },
    outputs = {
        { itemID = 210800, rank = 2, avgPer = 0.02, label = "Luredrop" },
        { itemID = 228232, rank = 2, avgPer = 0.17, label = "Weavercloth" },
        { itemID = 210937, rank = 2, avgPer = 0.02, label = "Aqirite" },
        { itemID = 210934, rank = 2, avgPer = 0.01, label = "Ironclaw Ore" },
        { itemID = 210803, rank = 2, avgPer = 0.02, label = "Orbinid" },
        { itemID = 210806, rank = 2, avgPer = 0.01, label = "Blessing Blossom" },
        { itemID = 210931, rank = 2, avgPer = 0.18, label = "Bismuth" },
        { itemID = 212514, rank = 0, avgPer = 0.00, label = "Blasphemite" },
        { itemID = 219947, rank = 2, avgPer = 0.18, label = "Storm Dust" },
        { itemID = 210809, rank = 2, avgPer = 0.01, label = "Arathor's Spear" },
        { itemID = 212495, rank = 0, avgPer = 0.00, label = "Radiant Ruby" },
    },
    resourcefulness = 0.211,
    multicraft = 0,
}

-- ================= ENCHANTING =================
-- Storm Dust: 219946 (Q1), 219947 (Q2), 219948 (Q3)
-- Gleaming Shard: 219949 (Q1), 219950 (Q2), 219951 (Q3)

GCA.Strategies["Enchanting:Gleaming Shard Q1 Shuffle"] = {
    category = "Enchanting",
    name = "Gleaming Shard Q1 Shuffle",
    guide = "Blood Elf 37% resourcefulness",
    inputs = {
        { itemID = 219949, rank = 1, quantity = 2000, label = "Gleaming Shard Q1" },
    },
    outputs = {
        { itemID = 219947, rank = 2, avgPer = 3.57, label = "Storm Dust" },
    },
    resourcefulness = 0.37,
    multicraft = 0,
}

GCA.Strategies["Enchanting:Gleaming Shard Q2 Shuffle"] = {
    category = "Enchanting",
    name = "Gleaming Shard Q2 Shuffle",
    guide = "Blood Elf 37% resourcefulness",
    inputs = {
        { itemID = 219950, rank = 2, quantity = 2000, label = "Gleaming Shard Q2" },
    },
    outputs = {
        { itemID = 219946, rank = 1, avgPer = 2.24, label = "Storm Dust Q1" },
        { itemID = 219947, rank = 2, avgPer = 1.30, label = "Storm Dust Q2" },
    },
    resourcefulness = 0.37,
    multicraft = 0,
}

GCA.Strategies["Enchanting:Gleaming Shard Q3 Shuffle"] = {
    category = "Enchanting",
    name = "Gleaming Shard Q3 Shuffle",
    guide = "Blood Elf 37% resourcefulness",
    inputs = {
        { itemID = 219951, rank = 3, quantity = 2000, label = "Gleaming Shard Q3" },
    },
    outputs = {
        { itemID = 219946, rank = 1, avgPer = 1.41, label = "Storm Dust Q1" },
        { itemID = 219947, rank = 2, avgPer = 1.48, label = "Storm Dust Q2" },
        { itemID = 219948, rank = 3, avgPer = 0.70, label = "Storm Dust Q3" },
    },
    resourcefulness = 0.37,
    multicraft = 0,
}

GCA.Strategies["Enchanting:Mana Oil"] = {
    category = "Enchanting",
    name = "Algari Mana Oil",
    guide = "Blood Elf setup",
    inputs = {
        { itemID = 213757, rank = 2, quantity = 10000, label = "Leyline Residue" },
        { itemID = 219947, rank = 2, quantity = 5000, label = "Storm Dust" },
    },
    outputs = {
        { itemID = 224106, rank = 2, avgPer = 0.74375, label = "Algari Mana Oil" },
    },
    resourcefulness = 0.37,
    multicraft = 0,
}

-- ================= INSCRIPTION =================
-- Viridescent Spores: 222555 (Q1), 222556 (Q2), 222557 (Q3)
-- Apricate Ink: 222609 (Q1), 222610 (Q2), 222611 (Q3)
-- Shadow Ink: 222612 (Q1), 222613 (Q2), 222614 (Q3)

GCA.Strategies["Inscription:Luredrop Milling"] = {
    category = "Inscription",
    name = "Luredrop Milling",
    guide = "32.2% resourcefulness",
    inputs = {
        { itemID = 210800, rank = 2, quantity = 5000, label = "Luredrop" },
    },
    outputs = {
        { itemID = 222556, rank = 2, avgPer = 1.50, label = "Pigment" },
    },
    resourcefulness = 0.322,
    multicraft = 0,
}

GCA.Strategies["Inscription:Mycobloom Milling"] = {
    category = "Inscription",
    name = "Mycobloom Milling",
    guide = "32.2% resourcefulness",
    inputs = {
        { itemID = 210797, rank = 2, quantity = 10000, label = "Mycobloom" },
    },
    outputs = {
        { itemID = 222556, rank = 2, avgPer = 1.50, label = "Pigment" },
    },
    resourcefulness = 0.322,
    multicraft = 0,
}

GCA.Strategies["Inscription:Apricate Ink"] = {
    category = "Inscription",
    name = "Apricate Ink",
    guide = "20% resourcefulness, 22.7% multicraft",
    inputs = {
        { itemID = 210800, rank = 2, quantity = 5000, label = "Luredrop" },
        { itemID = 210797, rank = 2, quantity = 10000, label = "Mycobloom" },
    },
    outputs = {
        { itemID = 222610, rank = 2, avgPer = 0.53, label = "Apricate Ink" },
    },
    resourcefulness = 0.20,
    multicraft = 0.227,
}

GCA.Strategies["Inscription:Shadow Ink"] = {
    category = "Inscription",
    name = "Shadow Ink",
    guide = "20% resourcefulness, 22.7% multicraft",
    inputs = {
        { itemID = 210803, rank = 2, quantity = 6850, label = "Orbinid" },
        { itemID = 210806, rank = 2, quantity = 6850, label = "Blessing Blossom" },
    },
    outputs = {
        { itemID = 222613, rank = 2, avgPer = 0.55, label = "Shadow Ink" },
    },
    resourcefulness = 0.20,
    multicraft = 0.227,
}

GCA.Strategies["Inscription:Boundless Cipher"] = {
    category = "Inscription",
    name = "Boundless Cipher",
    guide = "20% resourcefulness, 22.7% multicraft",
    inputs = {
        { itemID = 222610, rank = 2, quantity = 2647, label = "Apricate Ink" },
        { itemID = 210809, rank = 2, quantity = 6627, label = "Arathor's Spear" },
    },
    outputs = {
        { itemID = 222559, rank = 2, avgPer = 0.88, label = "Boundless Cipher" },
    },
    resourcefulness = 0.20,
    multicraft = 0.227,
}

GCA.Strategies["Inscription:Codified Greenwood"] = {
    category = "Inscription",
    name = "Codified Greenwood",
    guide = "20% resourcefulness, 22.7% multicraft",
    inputs = {
        { itemID = 222613, rank = 2, quantity = 3740, label = "Shadow Ink" },
        { itemID = 210809, rank = 2, quantity = 9364, label = "Arathor's Spear" },
    },
    outputs = {
        { itemID = 222616, rank = 2, avgPer = 0.88, label = "Codified Greenwood" },
    },
    resourcefulness = 0.20,
    multicraft = 0.227,
}

-- ================= BLACKSMITHING =================
-- Bismuth: 210930 (Q1), 210931 (Q2), 210932 (Q3)
-- Ironclaw Ore: 210933 (Q1), 210934 (Q2), 210935 (Q3)
-- Aqirite: 210936 (Q1), 210937 (Q2), 210938 (Q3)

GCA.Strategies["Blacksmithing:Core Alloy"] = {
    category = "Blacksmithing",
    name = "Core Alloy",
    guide = "20.1% resourcefulness, 22.1% multicraft",
    inputs = {
        { itemID = 210931, rank = 2, quantity = 10000, label = "Bismuth" },
    },
    outputs = {
        { itemID = 222418, rank = 2, avgPer = 0.13885, label = "Core Alloy" },
    },
    resourcefulness = 0.201,
    multicraft = 0.221,
}

GCA.Strategies["Blacksmithing:Ironclaw Alloy"] = {
    category = "Blacksmithing",
    name = "Ironclaw Alloy",
    guide = "20.1% resourcefulness, 22.1% multicraft",
    inputs = {
        { itemID = 210931, rank = 2, quantity = 2000, label = "Bismuth" },
        { itemID = 210934, rank = 2, quantity = 682, label = "Ironclaw Ore" },
    },
    outputs = {
        { itemID = 222421, rank = 2, avgPer = 0.0965, label = "Ironclaw Alloy" },
    },
    resourcefulness = 0.201,
    multicraft = 0.221,
}

GCA.Strategies["Blacksmithing:Charged Alloy"] = {
    category = "Blacksmithing",
    name = "Charged Alloy",
    guide = "20.1% resourcefulness, 22.1% multicraft",
    inputs = {
        { itemID = 210931, rank = 2, quantity = 2000, label = "Bismuth" },
        { itemID = 210937, rank = 2, quantity = 693, label = "Aqirite" },
    },
    outputs = {
        { itemID = 222427, rank = 2, avgPer = 0.0975, label = "Charged Alloy" },
    },
    resourcefulness = 0.201,
    multicraft = 0.221,
}

GCA.Strategies["Blacksmithing:Proficient Hammer"] = {
    category = "Blacksmithing",
    name = "Proficient Blacksmith's Hammer",
    guide = "20.1% resourcefulness, full disenchanting spec",
    inputs = {
        { itemID = 210931, rank = 2, quantity = 15000, label = "Bismuth" },
    },
    outputs = {
        { itemID = 219946, rank = 1, avgPer = 0.123, label = "Storm Dust Q1" },
        { itemID = 219947, rank = 2, avgPer = 0.199, label = "Storm Dust Q2" },
        { itemID = 219948, rank = 3, avgPer = 0.115, label = "Storm Dust Q3" },
    },
    resourcefulness = 0.201,
    multicraft = 0.221,
}

-- ================= TAILORING =================
-- Stormcharged Leather: 212664 (Q1), 212665 (Q2), 212666 (Q3)
-- Weavercloth: 228231 (Q1), 228232 (Q2), 228233 (Q3)

GCA.Strategies["Tailoring:Duskweave Unravelling"] = {
    category = "Tailoring",
    name = "Duskweave Cloth Unravelling",
    guide = "24.3% resourcefulness",
    inputs = {
        { itemID = 228234, rank = 2, quantity = 1, label = "Duskweave" },
    },
    outputs = {
        { itemID = 222792, rank = 2, avgPer = 0.98, label = "Spool of Duskthread" },
    },
    resourcefulness = 0.243,
    multicraft = 0,
}

GCA.Strategies["Tailoring:Weavercloth Unravelling"] = {
    category = "Tailoring",
    name = "Weavercloth Unravelling",
    guide = "24.3% resourcefulness",
    inputs = {
        { itemID = 228232, rank = 2, quantity = 1, label = "Weavercloth" },
    },
    outputs = {
        { itemID = 222789, rank = 2, avgPer = 3.37, label = "Spool of Weaverthread" },
    },
    resourcefulness = 0.243,
    multicraft = 0,
}

GCA.Strategies["Tailoring:Weavercloth Bolt"] = {
    category = "Tailoring",
    name = "Weavercloth Bolt Crafting",
    guide = "18.8% resourcefulness, 19.5% multicraft",
    inputs = {
        { itemID = 228232, rank = 2, quantity = 2000, label = "Weavercloth" },
    },
    outputs = {
        { itemID = 222795, rank = 2, avgPer = 0.57, label = "Weavercloth Bolt" },
    },
    resourcefulness = 0.188,
    multicraft = 0.195,
}

GCA.Strategies["Tailoring:Exquisite Bolt"] = {
    category = "Tailoring",
    name = "Exquisite Bolt Crafting",
    guide = "18.8% resourcefulness, 19.5% multicraft",
    inputs = {
        { itemID = 228232, rank = 2, quantity = 2000, label = "Weavercloth" },
    },
    outputs = {
        { itemID = 222804, rank = 2, avgPer = 0.47, label = "Exquisite Weavercloth Bolt" },
        { itemID = 219947, rank = 2, avgPer = 0.28, label = "Storm Dust" },
    },
    resourcefulness = 0.188,
    multicraft = 0.195,
}

GCA.Strategies["Tailoring:Pioneer's Cloth Cuffs"] = {
    category = "Tailoring",
    name = "Pioneer's Cloth Cuffs",
    guide = "Disenchant shuffle",
    inputs = {
        { itemID = 228232, rank = 2, quantity = 2000, label = "Weavercloth" },
    },
    outputs = {
        { itemID = 219949, rank = 1, avgPer = 0.110, label = "Gleaming Shard Q1" },
        { itemID = 219950, rank = 2, avgPer = 0.205, label = "Gleaming Shard Q2" },
        { itemID = 219951, rank = 3, avgPer = 0.102, label = "Gleaming Shard Q3" },
    },
    resourcefulness = 0.188,
    multicraft = 0.195,
}

-- ================= JEWELCRAFTING =================

GCA.Strategies["Jewelcrafting:Crushing"] = {
    category = "Jewelcrafting",
    name = "Bismuth Crushing",
    guide = "20.5% resourcefulness",
    inputs = {
        { itemID = 210931, rank = 2, quantity = 2000, label = "Bismuth" },
    },
    outputs = {
        { itemID = 212495, rank = 2, avgPer = 0.96, label = "Crushed Gemstones" },
        { itemID = 212495, rank = 0, avgPer = 0.25, label = "Radiant Ruby" },
    },
    resourcefulness = 0.205,
    multicraft = 0,
}

GCA.Strategies["Jewelcrafting:Ironclaw Prospecting"] = {
    category = "Jewelcrafting",
    name = "Ironclaw Prospecting Q2",
    guide = "20.5% resourcefulness",
    inputs = {
        { itemID = 210934, rank = 2, quantity = 30000, label = "Ironclaw Ore" },
    },
    outputs = {
        { itemID = 212495, rank = 2, avgPer = 0.02, label = "Crushed Gemstones" },
        { itemID = 212498, rank = 2, avgPer = 0.23, label = "Handful of Pebbles" },
        { itemID = 212505, rank = 2, avgPer = 0.08, label = "Glittering Glass" },
        { itemID = 212508, rank = 2, avgPer = 0.02, label = "Ambivalent Amber" },
        { itemID = 212495, rank = 0, avgPer = 0.03, label = "Radiant Ruby" },
        { itemID = 212511, rank = 2, avgPer = 0.03, label = "Ostentatious Onyx" },
        { itemID = 212514, rank = 2, avgPer = 0.03, label = "Extravagant Emerald" },
        { itemID = 213220, rank = 2, avgPer = 0.03, label = "Stunning Sapphire" },
    },
    resourcefulness = 0.205,
    multicraft = 0,
}

GCA.Strategies["Jewelcrafting:Aqirite Prospecting"] = {
    category = "Jewelcrafting",
    name = "Aqirite Prospecting Q2",
    guide = "20.5% resourcefulness",
    inputs = {
        { itemID = 210937, rank = 2, quantity = 30000, label = "Aqirite" },
    },
    outputs = {
        { itemID = 212495, rank = 2, avgPer = 0.02, label = "Crushed Gemstones" },
        { itemID = 212498, rank = 2, avgPer = 0.23, label = "Handful of Pebbles" },
        { itemID = 212505, rank = 2, avgPer = 0.08, label = "Glittering Glass" },
        { itemID = 212508, rank = 2, avgPer = 0.02, label = "Ambivalent Amber" },
        { itemID = 212495, rank = 0, avgPer = 0.03, label = "Radiant Ruby" },
        { itemID = 212511, rank = 2, avgPer = 0.03, label = "Ostentatious Onyx" },
        { itemID = 212514, rank = 2, avgPer = 0.03, label = "Extravagant Emerald" },
        { itemID = 213220, rank = 2, avgPer = 0.03, label = "Stunning Sapphire" },
    },
    resourcefulness = 0.205,
    multicraft = 0,
}

GCA.Strategies["Jewelcrafting:Null Stone"] = {
    category = "Jewelcrafting",
    name = "Null Stone Processing",
    guide = "20.5% resourcefulness",
    inputs = {
        { itemID = 213613, rank = 2, quantity = 2000, label = "Null Lotus" },
    },
    outputs = {
        { itemID = 212498, rank = 2, avgPer = 0.22, label = "Handful of Pebbles" },
        { itemID = 212505, rank = 2, avgPer = 0.08, label = "Glittering Glass" },
        { itemID = 212508, rank = 2, avgPer = 0.02, label = "Ambivalent Amber" },
        { itemID = 212495, rank = 0, avgPer = 0.16, label = "Radiant Ruby" },
        { itemID = 212511, rank = 2, avgPer = 0.16, label = "Ostentatious Onyx" },
        { itemID = 212514, rank = 2, avgPer = 0.16, label = "Extravagant Emerald" },
        { itemID = 213220, rank = 2, avgPer = 0.16, label = "Stunning Sapphire" },
    },
    resourcefulness = 0.205,
    multicraft = 0,
}

GCA.Strategies["Jewelcrafting:Marbled Stone"] = {
    category = "Jewelcrafting",
    name = "Marbled Stone",
    guide = "20% multicraft, 16% resourcefulness",
    inputs = {
        { itemID = 210931, rank = 2, quantity = 150000, label = "Bismuth" },
    },
    outputs = {
        { itemID = 228231, rank = 2, avgPer = 1.44, label = "Marbled Stone" },
    },
    resourcefulness = 0.16,
    multicraft = 0.20,
}

-- ================= ENGINEERING =================

GCA.Strategies["Engineering:Bismuth Bolts"] = {
    category = "Engineering",
    name = "Handful of Bismuth Bolts",
    guide = "20.4% resourcefulness, 19.5% multicraft",
    inputs = {
        { itemID = 210931, rank = 2, quantity = 2000, label = "Bismuth" },
    },
    outputs = {
        { itemID = 221854, rank = 2, avgPer = 0.50, label = "Handful of Bismuth Bolts" },
    },
    resourcefulness = 0.204,
    multicraft = 0.195,
}

GCA.Strategies["Engineering:Gyrating Gear"] = {
    category = "Engineering",
    name = "Gyrating Gear",
    guide = "20.4% resourcefulness, 19.5% multicraft",
    inputs = {
        { itemID = 210931, rank = 2, quantity = 2000, label = "Bismuth" },
        { itemID = 210937, rank = 2, quantity = 667, label = "Aqirite" },
    },
    outputs = {
        { itemID = 221860, rank = 2, avgPer = 0.70, label = "Gyrating Gear" },
    },
    resourcefulness = 0.204,
    multicraft = 0.195,
}

-- ================= COOKING =================

GCA.Strategies["Cooking:Portioned Steak"] = {
    category = "Cooking",
    name = "Portioned Steak",
    guide = "9.3% resourcefulness",
    inputs = {
        { itemID = 223512, rank = 2, quantity = 2000, label = "Basically Beef" },
    },
    outputs = {
        { itemID = 222728, rank = 2, avgPer = 1.33, label = "Portioned Steak" },
    },
    resourcefulness = 0.093,
    multicraft = 0,
}

GCA.Strategies["Cooking:Beledar's Bounty (No Finisher)"] = {
    category = "Cooking",
    name = "Beledar's Bounty (No Finisher)",
    guide = "9.3% resourcefulness",
    inputs = {
        { itemID = 222728, rank = 2, quantity = 13300, label = "Portioned Steak" },
    },
    outputs = {
        { itemID = 225911, rank = 2, avgPer = 0.21, label = "Beledar's Bounty" },
    },
    resourcefulness = 0.093,
    multicraft = 0.04,
}

GCA.Strategies["Cooking:Beledar's Bounty (Hot Honeycomb)"] = {
    category = "Cooking",
    name = "Beledar's Bounty (Hot Honeycomb)",
    guide = "9.3% resourcefulness, 37% multicraft, Phial of Quick Hands Q3",
    inputs = {
        { itemID = 222728, rank = 2, quantity = 21796, label = "Portioned Steak" },
        { itemID = 222738, rank = 2, quantity = 1495, label = "Hot Honeycomb" },
    },
    outputs = {
        { itemID = 225911, rank = 2, avgPer = 0.30, label = "Beledar's Bounty" },
    },
    resourcefulness = 0.093,
    multicraft = 0.37,
}

GCA.Strategies["Cooking:Cinderbee Belly"] = {
    category = "Cooking",
    name = "Cinderbee Belly Processing",
    guide = "Processing cinderbee materials",
    inputs = {
        { itemID = 223512, rank = 2, quantity = 2000, label = "Cinderbee Belly" },
    },
    outputs = {
        { itemID = 222738, rank = 2, avgPer = 0.10, label = "Hot Honeycomb" },
        { itemID = 222728, rank = 2, avgPer = 0.62, label = "Portioned Steak" },
    },
    resourcefulness = 0.093,
    multicraft = 0,
}

GCA.Strategies["Cooking:Chopped Mycobloom"] = {
    category = "Cooking",
    name = "Chopped Mycobloom",
    guide = "Processing Q3 mycobloom",
    inputs = {
        { itemID = 210804, rank = 3, quantity = 10000, label = "Mycobloom Q3" },
    },
    outputs = {
        { itemID = 222737, rank = 2, avgPer = 1.62, label = "Chopped Mycobloom" },
    },
    resourcefulness = 0.093,
    multicraft = 0,
}

-- ================= REFINING (Q2 to Q3 upgrades) =================

GCA.Strategies["Refining:Luredrop Q2 to Q3"] = {
    category = "Refining",
    name = "Luredrop Refining Q2 > Q3",
    guide = "5x Q2 = 1x Q3",
    inputs = {
        { itemID = 210800, rank = 2, quantity = 5, label = "Luredrop Q2" },
    },
    outputs = {
        { itemID = 210801, rank = 3, avgPer = 1.0, label = "Luredrop Q3" },
    },
    resourcefulness = 0,
    multicraft = 0,
}

GCA.Strategies["Refining:Blessing Blossom Q2 to Q3"] = {
    category = "Refining",
    name = "Blessing Blossom Refining Q2 > Q3",
    guide = "5x Q2 = 1x Q3",
    inputs = {
        { itemID = 210806, rank = 2, quantity = 5, label = "Blessing Blossom Q2" },
    },
    outputs = {
        { itemID = 210807, rank = 3, avgPer = 1.0, label = "Blessing Blossom Q3" },
    },
    resourcefulness = 0,
    multicraft = 0,
}

GCA.Strategies["Refining:Bismuth Q2 to Q3"] = {
    category = "Refining",
    name = "Bismuth Refining Q2 > Q3",
    guide = "5x Q2 = 1x Q3",
    inputs = {
        { itemID = 210931, rank = 2, quantity = 5, label = "Bismuth Q2" },
    },
    outputs = {
        { itemID = 210932, rank = 3, avgPer = 1.0, label = "Bismuth Q3" },
    },
    resourcefulness = 0,
    multicraft = 0,
}

GCA.Strategies["Refining:Orbinid Q2 to Q3"] = {
    category = "Refining",
    name = "Orbinid Refining Q2 > Q3",
    guide = "5x Q2 = 1x Q3",
    inputs = {
        { itemID = 210803, rank = 2, quantity = 5, label = "Orbinid Q2" },
    },
    outputs = {
        { itemID = 210804, rank = 3, avgPer = 1.0, label = "Orbinid Q3" },
    },
    resourcefulness = 0,
    multicraft = 0,
}

GCA.Strategies["Refining:Arathor's Spear Q2 to Q3"] = {
    category = "Refining",
    name = "Arathor's Spear Refining Q2 > Q3",
    guide = "5x Q2 = 1x Q3",
    inputs = {
        { itemID = 210809, rank = 2, quantity = 5, label = "Arathor's Spear Q2" },
    },
    outputs = {
        { itemID = 210810, rank = 3, avgPer = 1.0, label = "Arathor's Spear Q3" },
    },
    resourcefulness = 0,
    multicraft = 0,
}

-- ================= Helper Functions =================

-- Get all strategy names
function GCA:GetAllStrategyNames()
    local names = {}
    for name in pairs(self.Strategies) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

-- Get strategies by category
function GCA:GetStrategiesByCategory(category)
    local strategies = {}
    for name, strategy in pairs(self.Strategies) do
        if strategy.category == category then
            strategies[#strategies + 1] = {
                id = name,
                strategy = strategy,
            }
        end
    end
    return strategies
end

-- Get all categories
function GCA:GetAllCategories()
    local categories = {}
    local seen = {}
    for _, strategy in pairs(self.Strategies) do
        if not seen[strategy.category] then
            seen[strategy.category] = true
            categories[#categories + 1] = strategy.category
        end
    end
    table.sort(categories)
    return categories
end

-- Get all required item IDs for a strategy
function GCA:GetStrategyItemIDs(strategyName)
    local strategy = self.Strategies[strategyName]
    if not strategy then return {} end

    local items = {}
    for _, input in ipairs(strategy.inputs) do
        items[input.itemID] = true
    end
    for _, output in ipairs(strategy.outputs) do
        items[output.itemID] = true
    end

    local result = {}
    for itemID in pairs(items) do
        result[#result + 1] = itemID
    end
    return result
end

-- Get all unique item IDs across all strategies
function GCA:GetAllStrategyItemIDs()
    local items = {}
    for _, strategy in pairs(self.Strategies) do
        for _, input in ipairs(strategy.inputs) do
            items[input.itemID] = true
        end
        for _, output in ipairs(strategy.outputs) do
            items[output.itemID] = true
        end
    end

    local result = {}
    for itemID in pairs(items) do
        result[#result + 1] = itemID
    end
    table.sort(result)
    return result
end
