-- GoldAdvisorMidnight/Data/Recipes/Patch12_1.lua
-- Runtime adapter for the single-source facts in ProfessionCraftsPatch12_1.lua.

local ADDON_NAME, GAM = ...
assert(GAM.AppendRuntimeProfessionCrafts,
    "ProfessionCrafts.lua must load before patch runtime strategies")
GAM.AppendRuntimeProfessionCrafts()
