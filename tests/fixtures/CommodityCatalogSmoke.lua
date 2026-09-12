-- Test-only fixture extracted from CommodityCatalog.lua.
function Catalog.RunSmokeChecks()
    local ok, err = pcall(function()
        assert(type(manifest) == "table", "manifest unavailable")
        assert(type(manifest.itemIDs) == "table", "manifest itemIDs unavailable")
        assert((tonumber(manifest.strategyCount) or 0) > 0, "manifest strategy count unavailable")

        local firstItemID = next(manifest.itemIDs)
        assert(type(firstItemID) == "number", "manifest contains no item IDs")
        assert(Catalog.IsItemID(firstItemID), "known commodity lookup failed")
        assert(not Catalog.IsItemID(-1), "unknown item lookup failed")

        local filtered = Catalog.FilterItemIDs({ -1, firstItemID, 0 })
        assert(#filtered == 1 and filtered[1] == firstItemID, "item filtering failed")

        local eligible = Catalog.IsStrategyEligible({
            outputs = { { itemIDs = { firstItemID } } },
            reagents = {},
        })
        assert(eligible, "eligible strategy rejected")

        local rejected = Catalog.IsStrategyEligible({
            outputs = { { itemIDs = { -1 } } },
            reagents = {},
        })
        assert(not rejected, "noncommodity strategy accepted")
    end)
    return ok, err
end
