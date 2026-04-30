-- GoldAdvisorMidnight/Data/SpecializationData/Midnight/Alchemy.lua
-- GAM-owned Midnight Alchemy specialization catalog.
--
-- Static node IDs/max ranks/stat payloads are transformed from CraftSim's
-- MIT-licensed Data/SpecializationData/Midnight/Alchemy.lua.
-- Source: https://github.com/derfloh205/CraftSim
-- CraftSim copyright belongs to its authors; this file is a reduced static
-- catalog for GAM's standalone pricing/stat resolver and has no runtime
-- dependency on CraftSim.
--
-- CraftSim license notice retained for the transformed data:
-- MIT License Copyright (c) 2023 Florian Schneider
-- Permission is granted to use, copy, modify, merge, publish, distribute,
-- sublicense, and/or sell copies of the Software, provided the copyright and
-- permission notices are included in all copies or substantial portions.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

local ADDON_NAME, GAM = ...

GAM_SPECIALIZATION_DATA = GAM_SPECIALIZATION_DATA or {}
GAM_SPECIALIZATION_DATA.MIDNIGHT = GAM_SPECIALIZATION_DATA.MIDNIGHT or {}

local PROFILES = { alchemy = true }

GAM_SPECIALIZATION_DATA.MIDNIGHT.Alchemy = {
    version = 1,
    season = "midnight",
    profession = "Alchemy",
    skillLineID = 171,
    sourceAddon = "CraftSim",
    sourceLicense = "MIT",
    sourcePath = "Data/SpecializationData/Midnight/Alchemy.lua",
    profiles = PROFILES,
    recipeScoped = true,

    uiGroups = {
        {
            label = "Multicraft Extras",
            nodeIDs = { 107101, 107060, 107061, 107063 },
        },
        {
            label = "Multicraft Extras",
            nodeIDs = { 107104, 107077, 107078, 107080 },
        },
        {
            label = "Multicraft Extras",
            nodeIDs = { 107208, 107167, 107168, 107170 },
        },
        {
            label = "Multicraft Extras",
            nodeIDs = { 107211, 107184, 107185, 107187 },
        },
        {
            label = "Multicraft Extras",
            nodeIDs = { 107254, 107232, 107233, 107234, 107235, 107236 },
        },
    },

    recipeMapping = {
        [1230854] = { 107060, 107061, 107063, 107101 },
        [1230855] = { 107232, 107233, 107234, 107235, 107236, 107254 },
        [1230856] = { 107232, 107233, 107234, 107235, 107236, 107254 },
        [1230857] = { 107060, 107061, 107063, 107077, 107078, 107080, 107101, 107104 },
        [1230858] = { 107077, 107078, 107080, 107104 },
        [1230859] = { 107060, 107061, 107063, 107101 },
        [1230860] = { 107060, 107061, 107063, 107101 },
        [1230862] = { 107060, 107061, 107063, 107101 },
        [1230863] = { 107077, 107078, 107080, 107104 },
        [1230864] = { 107060, 107061, 107063, 107101 },
        [1230865] = { 107077, 107078, 107080, 107104 },
        [1230866] = { 107077, 107078, 107080, 107104 },
        [1230867] = { 107060, 107061, 107063, 107101 },
        [1230868] = { 107077, 107078, 107080, 107104 },
        [1230869] = { 107077, 107078, 107080, 107104 },
        [1230870] = { 107167, 107168, 107170, 107208 },
        [1230872] = { 107167, 107168, 107170, 107208 },
        [1230873] = { 107167, 107168, 107170, 107208 },
        [1230874] = { 107167, 107168, 107170, 107184, 107185, 107187, 107208, 107211 },
        [1230875] = { 107184, 107185, 107187, 107211 },
        [1230876] = { 107184, 107185, 107187, 107211 },
        [1230877] = { 107184, 107185, 107187, 107211 },
        [1230878] = { 107184, 107185, 107187, 107211 },
        [1230883] = { 107184, 107185, 107187, 107211 },
        [1230886] = { 107077, 107078, 107080, 107104 },
        [1230887] = { 107232, 107233, 107234, 107235, 107236, 107254 },
        [1230888] = { 107232, 107233, 107234, 107235, 107236, 107254 },
        [1230889] = { 107232, 107233, 107234, 107235, 107236, 107254 },
        [1230890] = { 107232, 107233, 107234, 107235, 107236, 107254 },
        [1230891] = { 107232, 107233, 107234, 107235, 107236, 107254 },
        [1230892] = { 107232, 107233, 107234, 107235, 107236, 107254 },
        [1230893] = { 107232, 107233, 107234, 107235, 107236, 107254 },
        [1234768] = { 107077, 107078, 107080, 107104 },
        [1235057] = { 107184, 107185, 107187, 107211 },
        [1235108] = { 107184, 107185, 107187, 107211 },
        [1235110] = { 107184, 107185, 107187, 107211 },
        [1235111] = { 107184, 107185, 107187, 107211 },
        [1235568] = { 107077, 107078, 107080, 107104 },
        [1236551] = { 107060, 107061, 107063, 107101 },
        [1236590] = { 107077, 107078, 107080, 107104 },
        [1236616] = { 107077, 107078, 107080, 107104 },
        [1236648] = { 107077, 107078, 107080, 107104 },
        [1236652] = { 107077, 107078, 107080, 107104 },
        [1236763] = { 107167, 107168, 107170, 107208 },
        [1236767] = { 107167, 107168, 107170, 107208 },
        [1236994] = { 107060, 107061, 107063, 107101 },
        [1236998] = { 107060, 107061, 107063, 107101 },
        [1237154] = { 107060, 107061, 107063, 107101 },
        [1237157] = { 107060, 107061, 107063, 107101 },
        [1237158] = { 107077, 107078, 107080, 107104 },
        [1237886] = { 107077, 107078, 107080, 107104 },
        [1238443] = { 107077, 107078, 107080, 107104 },
        [1239355] = { 107184, 107185, 107187, 107211 },
        [1239755] = { 107167, 107168, 107170, 107208 },
        [1263074] = { 107077, 107078, 107080, 107104 },
        [1263342] = { 107060, 107061, 107063, 107101 },
        [1284260] = { 107060, 107061, 107063, 107101 },
    },

    nodes = {
        [107101] = {
            nodeID = 107101,
            name = "Multicraft Rating",
            maxRank = 20,
            defaultRank = 0,
            base = true,
            profiles = PROFILES,
            stats = {
                multicraft = 3,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107060] = {
            nodeID = 107060,
            parentNodeID = 107101,
            name = "Multicraft Extra Items +20%",
            maxRank = 1,
            defaultRank = 1,
            profiles = PROFILES,
            stats = {
                additionalitemscraftedwithmulticraft = 20,
            },
        },
        [107061] = {
            nodeID = 107061,
            parentNodeID = 107101,
            name = "Multicraft Rating +30",
            maxRank = 1,
            defaultRank = 0,
            profiles = PROFILES,
            stats = {
                multicraft = 30,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107063] = {
            nodeID = 107063,
            parentNodeID = 107101,
            name = "Multicraft Rating +30",
            maxRank = 1,
            defaultRank = 0,
            profiles = PROFILES,
            stats = {
                multicraft = 30,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107104] = {
            nodeID = 107104,
            name = "Multicraft Rating",
            maxRank = 20,
            defaultRank = 0,
            base = true,
            profiles = PROFILES,
            stats = {
                multicraft = 3,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107077] = {
            nodeID = 107077,
            parentNodeID = 107104,
            name = "Multicraft Extra Items +20%",
            maxRank = 1,
            defaultRank = 1,
            profiles = PROFILES,
            stats = {
                additionalitemscraftedwithmulticraft = 20,
            },
        },
        [107078] = {
            nodeID = 107078,
            parentNodeID = 107104,
            name = "Multicraft Rating +30",
            maxRank = 1,
            defaultRank = 0,
            profiles = PROFILES,
            stats = {
                multicraft = 30,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107080] = {
            nodeID = 107080,
            parentNodeID = 107104,
            name = "Multicraft Rating +30",
            maxRank = 1,
            defaultRank = 0,
            profiles = PROFILES,
            stats = {
                multicraft = 30,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107208] = {
            nodeID = 107208,
            name = "Multicraft Rating",
            maxRank = 20,
            defaultRank = 0,
            base = true,
            profiles = PROFILES,
            stats = {
                multicraft = 3,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107167] = {
            nodeID = 107167,
            parentNodeID = 107208,
            name = "Multicraft Extra Items +20%",
            maxRank = 1,
            defaultRank = 1,
            profiles = PROFILES,
            stats = {
                additionalitemscraftedwithmulticraft = 20,
            },
        },
        [107168] = {
            nodeID = 107168,
            parentNodeID = 107208,
            name = "Multicraft Rating +30",
            maxRank = 1,
            defaultRank = 0,
            profiles = PROFILES,
            stats = {
                multicraft = 30,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107170] = {
            nodeID = 107170,
            parentNodeID = 107208,
            name = "Multicraft Rating +30",
            maxRank = 1,
            defaultRank = 0,
            profiles = PROFILES,
            stats = {
                multicraft = 30,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107211] = {
            nodeID = 107211,
            name = "Multicraft Rating",
            maxRank = 20,
            defaultRank = 0,
            base = true,
            profiles = PROFILES,
            stats = {
                multicraft = 3,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107184] = {
            nodeID = 107184,
            parentNodeID = 107211,
            name = "Multicraft Extra Items +20%",
            maxRank = 1,
            defaultRank = 1,
            profiles = PROFILES,
            stats = {
                additionalitemscraftedwithmulticraft = 20,
            },
        },
        [107185] = {
            nodeID = 107185,
            parentNodeID = 107211,
            name = "Multicraft Rating +30",
            maxRank = 1,
            defaultRank = 0,
            profiles = PROFILES,
            stats = {
                multicraft = 30,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107187] = {
            nodeID = 107187,
            parentNodeID = 107211,
            name = "Multicraft Rating +30",
            maxRank = 1,
            defaultRank = 0,
            profiles = PROFILES,
            stats = {
                multicraft = 30,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107254] = {
            nodeID = 107254,
            name = "Skill Node",
            maxRank = 20,
            defaultRank = 0,
            base = true,
            profiles = PROFILES,
            stats = {
                skill = 1,
            },
        },
        [107232] = {
            nodeID = 107232,
            parentNodeID = 107254,
            name = "Multicraft Extra Items +10%",
            maxRank = 1,
            defaultRank = 1,
            profiles = PROFILES,
            stats = {
                additionalitemscraftedwithmulticraft = 10,
            },
        },
        [107233] = {
            nodeID = 107233,
            parentNodeID = 107254,
            name = "Multicraft Rating +45",
            maxRank = 1,
            defaultRank = 0,
            profiles = PROFILES,
            stats = {
                multicraft = 45,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107234] = {
            nodeID = 107234,
            parentNodeID = 107254,
            name = "Multicraft Rating +45",
            maxRank = 1,
            defaultRank = 0,
            profiles = PROFILES,
            stats = {
                multicraft = 45,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107235] = {
            nodeID = 107235,
            parentNodeID = 107254,
            name = "Multicraft Rating +45",
            maxRank = 1,
            defaultRank = 0,
            profiles = PROFILES,
            stats = {
                multicraft = 45,
            },
            pricingNote = "Rating node; enter final profession-window % in the stat box.",
        },
        [107236] = {
            nodeID = 107236,
            parentNodeID = 107254,
            name = "Multicraft Extra Items +10%",
            maxRank = 1,
            defaultRank = 1,
            profiles = PROFILES,
            stats = {
                additionalitemscraftedwithmulticraft = 10,
            },
        },
    },
}
