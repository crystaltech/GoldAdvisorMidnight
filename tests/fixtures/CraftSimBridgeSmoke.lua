-- Test-only fixture extracted from CraftSimBridge.lua.
function Bridge.RunSmokeChecks()
    local BuildPushOverrideEntries = Bridge._BuildPushOverrideEntries
    local FindPushOverrideEntry = Bridge._FindPushOverrideEntry
    assert(type(BuildPushOverrideEntries) == "function", "CraftSim price override helper unavailable")
    assert(type(FindPushOverrideEntry) == "function", "CraftSim price override lookup unavailable")

    local originalGetPatchDB = GAM.GetPatchDB
    local originalGetOptions = GAM.GetOptions
    local originalAHScan = GAM.AHScan
    local originalGetUnitPrice = GAM.Pricing and GAM.Pricing.GetUnitPrice
    local originalGetActiveRecipeView = GAM.Pricing and GAM.Pricing.GetActiveRecipeView
    local originalVendorPrices = GAM.C.VENDOR_PRICES
    local originalVendorResolver = GAM.VendorPrices
    local fakePDB = {
        rankGroups = {},
        priceOverrides = {},
    }
    local fakeOpts = {
        shallowFillQty = 50,
        priceSource = "craftsim",
    }
    local cachedPrices = {
        [51001] = 111,
        [51002] = 112,
        [52001] = 211,
        [52002] = 212,
        [53001] = 311,
        [53101] = 411,
    }
    local livePrices = {
        [51001] = { [1000] = 4101 },
        [51002] = { [1000] = 4102 },
        [52001] = { [50] = 5201 },
        [52002] = { [50] = 5202 },
        [53001] = { [25] = 6301 },
        [53002] = { [25] = 6302 },
    }

    local function RestoreState()
        GAM.GetPatchDB = originalGetPatchDB
        GAM.GetOptions = originalGetOptions
        GAM.AHScan = originalAHScan
        if GAM.Pricing then
            GAM.Pricing.GetUnitPrice = originalGetUnitPrice
            GAM.Pricing.GetActiveRecipeView = originalGetActiveRecipeView
        end
        GAM.C.VENDOR_PRICES = originalVendorPrices
        GAM.VendorPrices = originalVendorResolver
    end

    local ok, err = pcall(function()
        GAM.GetPatchDB = function() return fakePDB end
        GAM.GetOptions = function() return fakeOpts end
        GAM.AHScan = {
            ComputePriceForQty = function(itemID, qty)
                local byQty = livePrices[itemID]
                return byQty and byQty[qty] or nil
            end,
        }
        GAM.C.VENDOR_PRICES = {}
        if not GAM.Pricing then
            error("Pricing module unavailable")
        end
        GAM.Pricing.GetUnitPrice = function(itemID)
            return cachedPrices[itemID], false
        end
        GAM.Pricing.GetActiveRecipeView = function(strat)
            return strat
        end

        local originalCraftSimForIdentity = CraftSim
        local identityOK, identityErr = pcall(function()
            CraftSim = {
                UTIL = {
                    GetPlayerCrafterData = function()
                        return { name = "Crafter", realm = "Normalized-Realm", class = "MAGE" }
                    end,
                },
            }
            local crafter = GetPlayerCrafterData()
            assert(crafter.name == "Crafter" and crafter.realm == "Normalized-Realm"
                    and crafter.class == "MAGE",
                "CraftSim canonical crafter identity was not used")
        end)
        CraftSim = originalCraftSimForIdentity
        assert(identityOK, identityErr)

        local originalCraftSimForStats = CraftSim
        local statSnapshotOK, statSnapshotErr = pcall(function()
            CraftSim = {
                CONST = {
                    BASE_RESOURCEFULNESS_AVERAGE_SAVE_FACTOR = 0.31,
                    MULTICRAFT_CONSTANTS = {
                        DEFAULT = 2.5,
                        [1] = 2.1,
                    },
                },
                DB = {
                    OPTIONS = {
                        Get = function(_, key)
                            if key == "PROFIT_CALCULATION_RESOURCEFULNESS_CONSTANT" then
                                return 0.32
                            end
                            if key == "PROFIT_CALCULATION_MULTICRAFT_CONSTANTS" then
                                return {
                                    DEFAULT = 2.55,
                                    [2] = 1.83,
                                }
                            end
                            return nil
                        end,
                    },
                },
            }

            local function FakeStat(percent, extra)
                return {
                    value = percent,
                    GetPercent = function()
                        return percent
                    end,
                    GetExtraValue = function()
                        return extra
                    end,
                }
            end

            local originalEnum = Enum
            local professionMatchOK, professionMatchErr = pcall(function()
                local inscriptionDef
                local cookingDef
                for _, professionDef in ipairs(PROFESSION_DEFS) do
                    if professionDef.name == "Inscription" then
                        inscriptionDef = professionDef
                    elseif professionDef.name == "Cooking" then
                        cookingDef = professionDef
                    end
                end
                assert(inscriptionDef, "shared Inscription profession definition missing")
                assert(cookingDef and InferFormulaProfileKey({}, cookingDef) == "cooking",
                    "shared Cooking CraftSim profile missing")
                Enum = {
                    Profession = {
                        Inscription = 9001,
                    },
                }
                assert(RecipeMatchesProfession({
                    professionData = {
                        professionInfo = {
                            profession = 9001,
                            professionID = 999999,
                        },
                    },
                }, inscriptionDef), "CraftSim enum profession match failed")
                assert(RecipeMatchesProfession({
                    professionData = {
                        professionInfo = {
                            professionID = 773,
                        },
                    },
                }, inscriptionDef), "CraftSim skill-line profession fallback failed")
                assert(not RecipeMatchesProfession({
                    professionData = {
                        professionInfo = {
                            profession = 9002,
                            professionID = 999999,
                        },
                    },
                }, inscriptionDef), "CraftSim profession mismatch should not match")
            end)
            Enum = originalEnum
            assert(professionMatchOK, professionMatchErr)

            local originalCraftSimAPI = CraftSimAPI
            local originalGAMDB = GAM.db
            local originalSavedDB = GoldAdvisorMidnightDB
            local openSnapshotOK, openSnapshotErr = pcall(function()
                Enum = {
                    Profession = {
                        Inscription = 9001,
                    },
                }
                GAM.db = {
                    v2StatCache = {
                        profiles = {},
                    },
                }
                GoldAdvisorMidnightDB = GAM.db
                CraftSimAPI = {
                    GetRecipeData = function() end,
                    GetOpenRecipeData = function()
                        return {
                            recipeID = 12345,
                            supportsResourcefulness = true,
                            supportsMulticraft = true,
                            professionData = {
                                professionInfo = {
                                    profession = 9001,
                                    professionID = 2913,
                                },
                            },
                            professionStats = {
                                resourcefulness = FakeStat(15.778, 0.55),
                                multicraft = FakeStat(13.273, 0.25),
                            },
                            specializationData = {
                                professionStats = {
                                    resourcefulness = FakeStat(0, 0.55),
                                    multicraft = FakeStat(0, 0.25),
                                },
                            },
                        }
                    end,
                }
                local snapshots = Bridge.GetOpenProfessionStatSnapshots()
                local insc = snapshots and snapshots.insc
                assert(insc and insc.source == "craftsim-imported", "open CraftSim snapshot source failed")
                assert(insc.recipeID == 12345, "open CraftSim snapshot recipe id failed")
                assert(insc.profileKey == "insc_ink", "open CraftSim snapshot profile failed")
                assert(insc.multiPercent == 13.273, "open CraftSim multicraft snapshot failed")
                assert(insc.resPercent == 15.778, "open CraftSim resourcefulness snapshot failed")
                assert(insc.cachedSource == "craftsim-open", "open CraftSim snapshot cached source failed")
                assert(insc.totalStats
                        and insc.nodeStats
                        and insc.totalStats.resourcefulness.extra == 0.55
                        and insc.nodeStats.multicraft.extra == 0.25,
                    "open CraftSim stat breakdown snapshot failed")
                local cached = Bridge.GetCachedProfileStatSnapshots()
                assert(cached
                        and cached.insc_ink
                        and cached.insc_ink.source == "craftsim-imported"
                        and cached.insc_ink.multiPercent == 13.273,
                    "open CraftSim snapshot profile cache failed")
            end)
            CraftSimAPI = originalCraftSimAPI
            GAM.db = originalGAMDB
            GoldAdvisorMidnightDB = originalSavedDB
            Enum = originalEnum
            assert(openSnapshotOK, openSnapshotErr)

            local snapshot = {}
            ApplyProfessionSnapshot(snapshot, {
                supportsResourcefulness = true,
                supportsMulticraft = true,
                professionStats = {
                    resourcefulness = FakeStat(12.5, 0.99),
                    multicraft = FakeStat(25.0, 0.99),
                },
                specializationData = {
                    professionStats = {
                        resourcefulness = FakeStat(0, 0.35),
                        multicraft = FakeStat(0, 0.25),
                    },
                },
            }, true)

            assert(snapshot.resPercent == 12.5, "resourcefulness percent snapshot failed")
            assert(snapshot.multiPercent == 25.0, "multicraft percent snapshot failed")
            assert(snapshot.rsNode == 0.35 and snapshot.resExtra == 0.99,
                "resourcefulness extra snapshot failed")
            assert(snapshot.mcNode == 0.25 and snapshot.multiExtra == 0.99,
                "multicraft extra snapshot failed")
            assert(snapshot.totalStats
                    and snapshot.nodeStats
                    and snapshot.totalStats.resourcefulness.extra == 0.99
                    and snapshot.nodeStats.resourcefulness.extra == 0.35,
                "CraftSim learned node stat breakdown failed")
            assert(snapshot.resourcefulnessSaveBase == 0.32,
                "CraftSim resourcefulness constant snapshot failed")
            assert(snapshot.multicraftConstants and snapshot.multicraftConstants[2] == 1.83
                and snapshot.multicraftConstants.DEFAULT == 2.55,
                "CraftSim multicraft constants snapshot failed")

            local resourcefulnessOnly = {}
            ApplyProfessionSnapshot(resourcefulnessOnly, {
                supportsResourcefulness = true,
                supportsMulticraft = false,
                professionStats = {
                    resourcefulness = FakeStat(18.0, 0),
                    multicraft = FakeStat(24.5, 0),
                },
            }, true)
            assert(resourcefulnessOnly.supportsResourcefulness == true
                    and resourcefulnessOnly.supportsMulticraft == false,
                "recipe capability flags must override the broad formula profile")
            assert(resourcefulnessOnly.resPercent == 18.0,
                "Resourcefulness-only recipe percent failed")

            local constants = Bridge.GetFormulaConstants()
            assert(constants and constants.resourcefulnessSaveBase == 0.32,
                "CraftSim formula constant reader failed")
            assert(constants.multicraftConstants and constants.multicraftConstants[2] == 1.83,
                "CraftSim formula multicraft constant reader failed")
        end)
        CraftSim = originalCraftSimForStats
        assert(statSnapshotOK, statSnapshotErr)

        local originalCraftSimForCache = CraftSim
        local originalCraftSimAPIForCache = CraftSimAPI
        local cacheAccessorOK, cacheAccessorErr = pcall(function()
            local fakeCraftSim = {
                DB = {
                    CRAFTER = {
                        GetCachedRecipeIDs = function(_, _, profession)
                            if profession == 9001 then
                                return { 71001, 71002 }
                            end
                            return nil
                        end,
                    },
                },
            }
            CraftSim = nil
            CraftSimAPI = {
                GetCraftSim = function()
                    return fakeCraftSim
                end,
            }
            local ids = GetCachedRecipeIDsForProfession(9001)
            assert(ids and ids[1] == 71001 and ids[2] == 71002,
                "CraftSim cached recipe repository accessor failed")
        end)
        CraftSim = originalCraftSimForCache
        CraftSimAPI = originalCraftSimAPIForCache
        assert(cacheAccessorOK, cacheAccessorErr)

        local strat = {
            id = "bridge_smoke",
            reagents = {
                { itemRef = "Original Reagent", itemIDs = { 51001, 51002 } },
            },
            output = { itemRef = "Output", itemIDs = { 52001, 52002 } },
            outputs = {
                { itemRef = "Output", itemIDs = { 52001, 52002 } },
            },
        }
        local metrics = {
            engine = "commodity_expected_value",
            recipeReagents = {
                {
                    name = "Original Reagent",
                    itemID = 51001,
                    sourceItemIDs = { 51001, 51002 },
                    required = 1000,
                },
            },
            reagents = {
                {
                    name = "Expanded Leaf",
                    itemID = 59999,
                    sourceItemIDs = { 59999 },
                    required = 4000,
                },
            },
        }

        local entries = BuildPushOverrideEntries(strat, GAM.C.DEFAULT_PATCH, metrics)
        assert((FindPushOverrideEntry(entries, 51001) or {}).price == 4101,
            "qty-aware reagent push failed")
        assert((FindPushOverrideEntry(entries, 51002) or {}).price == 4102,
            "qty-aware reagent rank coverage failed")
        assert((FindPushOverrideEntry(entries, 52001) or {}).price == 5201,
            "output fill-qty push failed")
        assert((FindPushOverrideEntry(entries, 52002) or {}).price == 5202,
            "output rank coverage failed")
        assert(not FindPushOverrideEntry(entries, 59999),
            "VI leaf rows leaked into CraftSim push")

        fakePDB.priceOverrides[51001] = 9901
        entries = BuildPushOverrideEntries(strat, GAM.C.DEFAULT_PATCH, metrics)
        assert((FindPushOverrideEntry(entries, 51001) or {}).price == 9901,
            "manual override precedence failed")
        fakePDB.priceOverrides[51001] = nil

        GAM.C.VENDOR_PRICES[51001] = 8801
        entries = BuildPushOverrideEntries(strat, GAM.C.DEFAULT_PATCH, metrics)
        assert((FindPushOverrideEntry(entries, 51001) or {}).price == 8801,
            "vendor precedence failed")
        GAM.VendorPrices = {
            GetPrice = function(itemID)
                if itemID == 51001 then
                    return 7701, "live"
                end
                return GAM.C.VENDOR_PRICES[itemID]
            end,
        }
        entries = BuildPushOverrideEntries(strat, GAM.C.DEFAULT_PATCH, metrics)
        assert((FindPushOverrideEntry(entries, 51001) or {}).price == 7701,
            "live vendor precedence failed")
        GAM.VendorPrices = nil
        GAM.C.VENDOR_PRICES[51001] = nil

        local cheapestStrat = {
            id = "bridge_smoke_cheapest",
            reagents = {
                { itemRef = "Cheapest Pool", itemIDs = { 54001, 54002 } },
            },
            output = { itemRef = "Cheapest Output", itemIDs = { 53101 } },
            outputs = {
                { itemRef = "Cheapest Output", itemIDs = { 53101 } },
            },
        }
        local cheapestMetrics = {
            engine = "commodity_expected_value",
            recipeReagents = {
                {
                    name = "Chosen Alternative",
                    itemID = 53001,
                    sourceItemIDs = { 53001, 53002 },
                    required = 25,
                    selectedAlternativeItemID = 53001,
                },
            },
            reagents = {
                {
                    name = "Expanded Cheapest Leaf",
                    itemID = 54999,
                    sourceItemIDs = { 54999 },
                    required = 100,
                },
            },
        }
        entries = BuildPushOverrideEntries(cheapestStrat, GAM.C.DEFAULT_PATCH, cheapestMetrics)
        assert((FindPushOverrideEntry(entries, 53001) or {}).price == 6301,
            "selected cheapest alternative price failed")
        assert((FindPushOverrideEntry(entries, 53002) or {}).price == 6302,
            "selected cheapest alternative rank coverage failed")
        assert(not FindPushOverrideEntry(entries, 54001) and not FindPushOverrideEntry(entries, 54002),
            "unselected cheapest pool entries leaked into push")
        assert(not FindPushOverrideEntry(entries, 54999),
            "expanded cheapest leaf leaked into push")

        local originalCraftSimForPush = CraftSim
        local originalCraftSimAPIForPush = CraftSimAPI
        local originalCraftSimDBForPush = CraftSimDB
        local pushAPIPathOK, pushAPIPathErr = pcall(function()
            local savedOverrides = {}
            local fakeCraftSim = {
                DB = {
                    PRICE_OVERRIDE = {
                        SaveGlobalOverride = function(_, overrideData)
                            savedOverrides[overrideData.itemID] = overrideData
                        end,
                    },
                },
            }
            CraftSimDB = {
                priceOverrideDB = {
                    data = {
                        globalOverrides = {},
                    },
                },
            }
            CraftSim = nil
            CraftSimAPI = {
                GetCraftSim = function()
                    return fakeCraftSim
                end,
            }

            local pushed = Bridge.PushStratPrices(strat, GAM.C.DEFAULT_PATCH, metrics)
            assert(pushed > 0, "CraftSim push API path pushed no overrides")
            assert(savedOverrides[51001] and savedOverrides[51001].price == 4101,
                "CraftSim SaveGlobalOverride API path failed")
            assert(not CraftSimDB.priceOverrideDB.data.globalOverrides[51001],
                "CraftSim SaveGlobalOverride API path should not require direct SavedVariables fallback")
        end)
        CraftSim = originalCraftSimForPush
        CraftSimAPI = originalCraftSimAPIForPush
        CraftSimDB = originalCraftSimDBForPush
        assert(pushAPIPathOK, pushAPIPathErr)
    end)

    RestoreState()
    return ok, err
end
