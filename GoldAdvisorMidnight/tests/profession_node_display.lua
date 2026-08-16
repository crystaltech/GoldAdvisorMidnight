-- Offline checks for localized Blizzard profession-node display metadata.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {}

local chunk, err = loadfile("ProfessionNodeDisplay.lua")
assert(chunk, err)
chunk(ADDON_NAME, GAM)

local display = GAM.ProfessionNodeDisplay
assert(display.GetFallbackName(106752) == "Resourcefulness",
    "hardcoded profession-node fallback is unavailable")
assert(display.GetFallbackName(999999) == nil, "unknown fallback node unexpectedly resolved")
local apis = {
    profSpecs = {
        GetSpendEntryForPath = function(nodeID) return nodeID + 100 end,
        GetDescriptionForPath = function(nodeID)
            return "Localized path description " .. tostring(nodeID)
        end,
    },
    traits = {
        GetEntryInfo = function(configID, entryID)
            assert(configID == 77 and entryID == 142, "unexpected trait lookup")
            return { definitionID = 242 }
        end,
        GetDefinitionInfo = function(definitionID)
            assert(definitionID == 242, "unexpected definition lookup")
            return { overrideName = "Resourceful Production" }
        end,
    },
}

local info = display.ResolveLiveNodeInfo(77, 42, { currentRank = 1 }, apis)
assert(info and info.name == "Resourceful Production", "localized node name was not resolved")
assert(info.description == "Localized path description 42", "localized description was not resolved")
assert(info.source == "blizzard" and info.entryID == 142 and info.definitionID == 242,
    "resolved node metadata is incomplete")

local spellInfo = display.ResolveLiveNodeInfo(77, 42, { entryIDs = { 142 } }, {
    traits = {
        GetEntryInfo = function() return { definitionID = 242 } end,
        GetDefinitionInfo = function() return { spellID = 9001 } end,
    },
    spells = {
        GetSpellInfo = function(spellID)
            assert(spellID == 9001, "unexpected spell lookup")
            return { name = "Batch Production" }
        end,
    },
})
assert(spellInfo and spellInfo.name == "Batch Production", "spell-name fallback failed")

local impact = display.BuildImpactText({
    stats = {
        additionalitemscraftedwithmulticraft = 20,
        resourcefulness = 30,
    },
})
assert(impact == "Multicraft extra items +20% per rank; Resourcefulness rating +30 per rank.",
    "node impact summary is incorrect")

print("PASS: profession node display metadata")
