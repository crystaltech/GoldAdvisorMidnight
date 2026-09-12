-- Test-only fixture extracted from State.lua.
function State.RunSmokeChecks()
    local ok, err = pcall(function()
        local migrated = NormalizeFavoritesTable({
            legacy_shared = true,
            lowest = { lowest_only = true },
            highest = { highest_only = true },
        })

        assert(migrated.legacy_shared == nil, "legacy favorites were not cleaned up")
        assert(migrated.lowest.legacy_shared and migrated.highest.legacy_shared,
            "legacy favorites did not copy into both rank buckets")
        assert(migrated.lowest.lowest_only and not migrated.highest.lowest_only,
            "lowest favorites leaked into highest bucket")
        assert(migrated.highest.highest_only and not migrated.lowest.highest_only,
            "highest favorites leaked into lowest bucket")

        local patch = {
            favorites = {
                shared_before = true,
            },
        }

        assert(GetFavoriteBucketForPatch(patch, "lowest").shared_before, "lowest bucket migration unavailable")
        assert(GetFavoriteBucketForPatch(patch, "highest").shared_before, "highest bucket migration unavailable")

        assert(ToggleFavoriteForPatch(patch, "r1_only", "lowest"), "failed to set lowest-rank favorite")
        assert(GetFavoriteBucketForPatch(patch, "lowest").r1_only, "lowest-rank favorite missing after toggle")
        assert(not GetFavoriteBucketForPatch(patch, "highest").r1_only, "lowest-rank favorite leaked to highest")

        assert(not ToggleFavoriteForPatch(patch, "r1_only", "lowest"), "failed to clear lowest-rank favorite")
        assert(not GetFavoriteBucketForPatch(patch, "lowest").r1_only, "lowest-rank favorite remained after clear")
        assert(GetFavoriteBucketForPatch(patch, "highest").shared_before, "highest bucket changed unexpectedly")
    end)
    return ok, err
end
