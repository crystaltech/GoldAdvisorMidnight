-- Test-only fixture extracted from StrategyModel.lua.
function Model.RunSmokeChecks()
    local ok, err = pcall(function()
        local sample = {
            profession = "Alchemy",
            stratName = "Canonical Sample",
            patchTag = "midnight-1",
            defaultStartingAmount = 10,
            defaultCrafts = 5,
            formulaProfile = "alchemy",
            outputs = {
                { itemIDs = { 241334, 241335 }, baseYieldPerCraft = 2 },
            },
            reagents = {
                { itemIDs = { 236949 }, qtyPerCraft = 2 },
            },
        }
        local strategy, normalizeErr = Model.Normalize(sample, "Smoke", false)
        assert(strategy, normalizeErr)
        assert(strategy.schemaVersion == Model.SCHEMA_VERSION, "schema version missing")
        assert(strategy.statProfileKey == "alchemy", "profile was not canonicalized")
        assert(#strategy.outputs[1].itemIDs == 1 and strategy.outputs[1].itemIDs[1] == 241334,
            "commodity outputs were not filtered")
        assert(strategy.reagents[1].quantityPerCraft == 2, "reagent quantity was not canonicalized")
        assert(Model.ResolveRecipeView(strategy).outputs == strategy.outputs, "recipe view changed outputs")
        assert(Model.ResolveActiveRecipeView(strategy, "lowest").outputs == strategy.outputs,
            "active recipe view changed base outputs")
    end)
    return ok, err
end
