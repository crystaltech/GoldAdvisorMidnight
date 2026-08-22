-- GoldAdvisorMidnight/Data/Recipes/Patch12_1.lua
-- Runtime adapter for the single-source facts in ProfessionCraftsPatch12_1.lua.

assert(GAM_APPEND_RUNTIME_PROFESSION_CRAFTS,
    "ProfessionCrafts.lua must load before patch runtime strategies")
GAM_APPEND_RUNTIME_PROFESSION_CRAFTS()
