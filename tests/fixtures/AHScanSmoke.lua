-- Test-only fixture extracted from AuctionHouseScan.lua.
function AHScan.RunSmokeChecks()
    local ok, err = pcall(function()
        local avg, minP, maxP, kept = Results.ComputeStatsFromRows({
            { unitPrice = 100, quantity = 3 },
            { unitPrice = 125, quantity = 2 },
            { unitPrice = 150, quantity = 1 },
        }, 4)
        assert(type(avg) == "number" and avg > 0, "avg unavailable")
        assert(type(minP) == "number" and minP > 0, "min unavailable")
        assert(type(maxP) == "number" and maxP > 0, "max unavailable")
        assert(type(kept) == "number" and kept > 0, "kept unavailable")

        local weightedAvg = Results.ComputeStatsFromRows({
            { unitPrice = 100, quantity = 1 },
            { unitPrice = 1000, quantity = 10 },
        }, 11)
        assert(weightedAvg and weightedAvg > 800,
            string.format("stack weighting regressed: got %s expected > 800", tostring(weightedAvg)))
    end)
    return ok, err
end
