-- Test-only fixture extracted from Pricing.lua.
function Pricing.RunSmokeChecks()
    local ok, err = pcall(function()
        local profiles = GetFormulaProfiles()
        assert(type(profiles) == "table", "formula profiles unavailable")

        local formulaV2 = Pricing.GetFormulaV2()
        assert(formulaV2 and type(formulaV2.RunSmokeChecks) == "function", "PricingFormula unavailable")
        local formulaV2OK, formulaV2Err = formulaV2.RunSmokeChecks()
        assert(formulaV2OK, formulaV2Err)

        local craftInfo = Derivation.GetAnyCraftInfo()
        assert(craftInfo and craftInfo.yield, "crafted reagent map unavailable")

        local effectiveYield = Derivation.GetEffectiveCraftYield(craftInfo)
        assert(type(effectiveYield) == "number" and effectiveYield > 0, "effective craft yield invalid")

        local largeSample = Pricing.FormatPrice(245000 * 10000)
        assert(largeSample:find("245,000g", 1, true), "FormatPrice missing gold comma separators")

        local mixedSample = Pricing.FormatPrice((245000 * 10000) + (56 * 100) + 78)
        assert(mixedSample:find("245,000g", 1, true), "FormatPrice failed for mixed gold value")
        assert(mixedSample:find("56s", 1, true), "FormatPrice failed for silver value")
        assert(mixedSample:find("78c", 1, true), "FormatPrice failed for copper value")

        local negativeSample = Pricing.FormatPrice(-245000 * 10000)
        assert(negativeSample:sub(1, 1) == "-", "FormatPrice failed for negative value")
        assert(negativeSample:find("245,000g", 1, true), "FormatPrice failed for negative gold value")

        assert(Pricing.FormatPrice(0) == "0g", "FormatPrice failed for zero value")

        local originalGetUnitPrice = Pricing.GetUnitPrice
        local originalAHScan = GAM.AHScan
        local qtyPricingOK, qtyPricingErr = pcall(function()
            Pricing.GetUnitPrice = function(itemID)
                if itemID == 424242 then
                    return 12345, false
                end
                return nil, false
            end
            GAM.AHScan = {
                ComputePriceForQty = function(itemID, qty)
                    if itemID == 424242 and qty == 5000 then
                        return 67890
                    end
                    return nil
                end,
            }

            local price = Pricing.GetEffectivePrice(424242, GAM.C.DEFAULT_PATCH, 5000)
            assert(price == 67890, string.format(
                "qty-aware repricing failed: got %s expected 67890",
                tostring(price)))
        end)
        Pricing.GetUnitPrice = originalGetUnitPrice
        GAM.AHScan = originalAHScan
        assert(qtyPricingOK, qtyPricingErr)

        local originalGetRealmCache = GAM.GetRealmCache
        local cachedMinimumOK, cachedMinimumErr = pcall(function()
            local fakeCache = {}
            GAM.GetRealmCache = function()
                return fakeCache
            end
            Pricing.StorePrice(434343, 349716980, 25000000)
            local average = Pricing.GetUnitPrice(434343)
            local minimum = Pricing.GetUnitPrice(434343, true)
            assert(average == 349716980, "cached acquisition average failed")
            assert(minimum == 25000000, "cached sell-side minimum failed")
        end)
        GAM.GetRealmCache = originalGetRealmCache
        assert(cachedMinimumOK, cachedMinimumErr)

        assert((GAM.C.VENDOR_PRICES and GAM.C.VENDOR_PRICES[243060]) == 3000,
            "Luminant Flux vendor-price baseline missing")
        assert((GAM.C.VENDOR_PRICES and GAM.C.VENDOR_PRICES[251665]) == 700,
            "Silverleaf Thread vendor-price baseline missing")
        assert((GAM.C.VENDOR_PRICES and GAM.C.VENDOR_PRICES[251691]) == 700,
            "Embroidery Floss vendor-price baseline missing")
        assert((GAM.C.VENDOR_PRICES and GAM.C.VENDOR_PRICES[240990]) == nil
                and GAM.C.VENDOR_PRICES[240991] == 27500,
            "Sunglass Vial vendor pricing must apply only to R1")
        assert((GAM.C.VENDOR_PRICES and GAM.C.VENDOR_PRICES[253302]) == 2105
                and GAM.C.VENDOR_PRICES[253303] == 2105,
            "Engineering vendor-price baselines missing")

        local originalVendorGetUnitPrice = Pricing.GetUnitPrice
        local originalVendorAHScan = GAM.AHScan
        local originalVendorResolver = GAM.VendorPrices
        local vendorPrecedenceOK, vendorPrecedenceErr = pcall(function()
            Pricing.GetUnitPrice = function(itemID)
                if itemID == 251691 then
                    return 800, false
                end
                if itemID == 240990 then
                    return 123456, false
                end
                return originalVendorGetUnitPrice(itemID)
            end
            GAM.AHScan = {
                ComputePriceForQty = function(itemID)
                    if itemID == 251691 then
                        return 800
                    end
                    if itemID == 240990 then
                        return 123456
                    end
                    return nil
                end,
            }
            GAM.VendorPrices = {
                GetPrice = function(itemID)
                    if itemID == 251691 then
                        return 875, "live"
                    end
                    return nil
                end,
            }

            local price = Pricing.GetEffectivePrice(251691, GAM.C.DEFAULT_PATCH, 50)
            assert(price == 875, string.format(
                "Embroidery Floss ignored live vendor price: got %s expected 875",
                tostring(price)))

            local r1VialPrice = Pricing.GetEffectivePrice(240991, GAM.C.DEFAULT_PATCH, 50)
            assert(r1VialPrice == 27500, string.format(
                "R1 Sunglass Vial ignored static vendor price: got %s expected 27500",
                tostring(r1VialPrice)))
            local r2VialPrice = Pricing.GetEffectivePrice(240990, GAM.C.DEFAULT_PATCH, 50)
            assert(r2VialPrice == 123456, string.format(
                "R2 Sunglass Vial incorrectly used the R1 vendor price: got %s expected 123456",
                tostring(r2VialPrice)))
        end)
        Pricing.GetUnitPrice = originalVendorGetUnitPrice
        GAM.AHScan = originalVendorAHScan
        GAM.VendorPrices = originalVendorResolver
        assert(vendorPrecedenceOK, vendorPrecedenceErr)

        local originalGetEffectivePriceForItem = Pricing.GetEffectivePriceForItem
        local cheapestOK, cheapestErr = pcall(function()
            Pricing.GetEffectivePriceForItem = function(item)
                local exactID = item and item.itemIDs and item.itemIDs[1] or nil
                local prices = {
                    [1001] = 400,
                    [1002] = 450,
                    [1003] = 410,
                    [1004] = 399,
                }
                return prices[exactID], false
            end

            local opts = GetOpts()
            local savedPolicy = opts.rankPolicy
            opts.rankPolicy = "highest"
            local resolved = ResolveCheapestAlternative({
                cheapestOf = {
                    { itemRef = "Amani Lapis", itemIDs = { 1001, 1002 } },
                    { itemRef = "Flawless Amani Lapis", itemIDs = { 1003, 1004 } },
                },
            }, {
                patchTag = GAM.C.DEFAULT_PATCH,
                pdb = { rankGroups = {} },
            }, 15)
            opts.rankPolicy = savedPolicy
            assert(resolved and resolved.itemID == 1004, "cheapestOf rank-policy selection regressed")
        end)
        Pricing.GetEffectivePriceForItem = originalGetEffectivePriceForItem
        assert(cheapestOK, cheapestErr)

        local originalCraftUI = C_TradeSkillUI
        local originalGetItemInfo = GetItemInfo
        local originalGetEffectivePrice = Pricing.GetEffectivePrice
        local dazzlingRankOK, dazzlingRankErr = pcall(function()
            C_TradeSkillUI = {
                GetItemReagentQualityByItemInfo = function(itemID)
                    return ({
                        [242786] = 2,
                        [242787] = 1,
                        [245864] = 1,
                        [245865] = 2,
                        [245866] = 1,
                        [245867] = 2,
                    })[itemID]
                end,
                -- Multi-output processing recipes do not necessarily resolve
                -- their byproducts through the crafted-output quality APIs.
                GetItemCraftedQualityInfo = function()
                    return nil
                end,
                GetItemCraftedQualityByItemInfo = function()
                    return 0
                end,
                -- A shared multi-output recipe mapping must not override the
                -- more specific live reagent ranks of its individual outputs.
                GetRecipeQualityItemIDs = function(recipeID)
                    if recipeID == 1231127 then
                        return { 242786, 242787 }
                    end
                    return nil
                end,
            }
            GetItemInfo = function(itemID)
                return itemID and ("Item-" .. tostring(itemID)) or nil
            end
            Pricing.GetEffectivePrice = function(itemID)
                return ({
                    [242786] = 3605500,
                    [242787] = 20500,
                })[itemID], false
            end

            for _, strategyID in ipairs({
                "jewelcrafting__refulgent_copper_ore_prospecting__midnight_1",
                "jewelcrafting__brilliant_silver_ore_prospecting__midnight_1",
                "jewelcrafting__umbral_tin_ore_prospecting__midnight_1",
                "jewelcrafting__dazzling_thorium_prospecting__midnight_1",
            }) do
                local strategy = GAM.Importer and GAM.Importer.GetStratByID
                    and GAM.Importer.GetStratByID(strategyID) or nil
                local glass = strategy and strategy.outputs and strategy.outputs[7] or nil
                assert(glass and #(glass.itemIDs or {}) >= 2,
                    strategyID .. ": ranked Crystalline Glass output unavailable")
                local r1ID = priceSource.GetOutputItemIDForDisplay(
                    glass, GAM.C.DEFAULT_PATCH, 1, strategy.recipeID)
                local r2ID = priceSource.GetOutputItemIDForDisplay(
                    glass, GAM.C.DEFAULT_PATCH, 2, strategy.recipeID)
                assert(r1ID == 242787 and r2ID == 242786, string.format(
                    "%s: Crystalline Glass ranks resolved to R1=%s R2=%s",
                    strategyID, tostring(r1ID), tostring(r2ID)))
                local price = GetOutputPriceForItem(
                    glass, GAM.C.DEFAULT_PATCH, 1, 800, strategy.recipeID)
                assert(price == 20500, string.format(
                    "%s: R1 Crystalline Glass price got %s expected 20500",
                    strategyID, tostring(price)))
            end

            for _, case in ipairs({
                { "inscription__sanguithorn_milling__midnight_1", 245864 },
                { "inscription__mana_lily_milling__midnight_1", 245866 },
            }) do
                local strategy = GAM.Importer and GAM.Importer.GetStratByID
                    and GAM.Importer.GetStratByID(case[1]) or nil
                local output = strategy and strategy.outputs and strategy.outputs[1] or nil
                assert(output, case[1] .. ": ranked pigment output unavailable")
                local r1ID = priceSource.GetOutputItemIDForDisplay(
                    output, GAM.C.DEFAULT_PATCH, 1, strategy.recipeID)
                assert(r1ID == case[2], string.format(
                    "%s: R1 pigment resolved to %s expected %s",
                    case[1], tostring(r1ID), tostring(case[2])))
            end
        end)
        C_TradeSkillUI = originalCraftUI
        GetItemInfo = originalGetItemInfo
        Pricing.GetEffectivePrice = originalGetEffectivePrice
        assert(dazzlingRankOK, dazzlingRankErr)

        local originalGetOptions = GAM.GetOptions
        local oilRankOK, oilRankErr = pcall(function()
            C_TradeSkillUI = {
                GetItemReagentQualityByItemInfo = function(itemID)
                    return nil
                end,
            }
            GetItemInfo = function(itemID)
                return itemID and ("Item-" .. tostring(itemID)) or nil
            end
            GAM.GetOptions = function()
                return { rankPolicy = "highest" }
            end
            Pricing.GetEffectivePrice = function(itemID)
                return ({
                    [243735] = 17500,
                    [243736] = 0,
                })[itemID], false
            end

            local function assertRankedIDs(ids, q1ID, q2ID, label)
                ids = ids or {}
                assert(#ids == 2 and ids[1] == q1ID and ids[2] == q2ID,
                    string.format("%s must keep Q1/Q2 IDs %s,%s: got %s",
                        label, tostring(q1ID), tostring(q2ID), table.concat(ids, ",")))
                local r2ID = PickItemID(ids, GAM.C.DEFAULT_PATCH, "highest")
                assert(r2ID == q2ID,
                    string.format("%s R2 must resolve to Q2 ID %s: got %s",
                        label, tostring(q2ID), tostring(r2ID)))
            end

            local oil = GAM.Importer and GAM.Importer.GetStratByID
                and GAM.Importer.GetStratByID("enchanting__oil_of_dawn__midnight_1") or nil
            assert(oil and oil.outputs and oil.outputs[1], "oil of dawn strat unavailable")
            assert(oil.reagents and oil.reagents[3] and oil.reagents[4], "oil of dawn ranked reagents unavailable")
            assertRankedIDs(oil.outputs[1].itemIDs, 243735, 243736, "Oil of Dawn output")
            assertRankedIDs(oil.reagents[3].itemIDs, 243599, 243600, "Oil of Dawn Eversinging Dust")
            assertRankedIDs(oil.reagents[4].itemIDs, 240990, 240991, "Oil of Dawn Sunglass Vial")

            local priceByPolicy = GetOutputPriceForItem(oil.outputs[1], GAM.C.DEFAULT_PATCH, nil, 8295)
            assert(priceByPolicy == 0, string.format(
                "Oil of Dawn rank-policy resolution failed: got %s expected 0",
                tostring(priceByPolicy)))

            local priceByPreferredQuality = GetOutputPriceForItem(oil.outputs[1], GAM.C.DEFAULT_PATCH, 2, 8295)
            assert(priceByPreferredQuality == 0, string.format(
                "Oil of Dawn R2 rank resolution failed: got %s expected 0",
                tostring(priceByPreferredQuality)))

            -- A missing selected-rank quote must not silently borrow another
            -- rank's market price. Keep the resolved identity with the quote so
            -- downstream revenue and display fields stay atomic.
            Pricing.GetEffectivePrice = function(itemID)
                return ({ [243735] = 17500 })[itemID], false
            end
            local missingR2Price, missingR2Stale, missingR2ID = GetOutputPriceForItem(
                oil.outputs[1], GAM.C.DEFAULT_PATCH, 2, 8295)
            assert(missingR2Price == nil and missingR2Stale == false and missingR2ID == 243736,
                "missing R2 output quote crossed ranks or lost its R2 identity")
            local r1Price, _, pricedR1ID = GetOutputPriceForItem(
                oil.outputs[1], GAM.C.DEFAULT_PATCH, 1, 8295)
            assert(r1Price == 17500 and pricedR1ID == 243735,
                "available R1 output quote did not retain its R1 identity")

            local phoenix = GAM.Importer and GAM.Importer.GetStratByID
                and GAM.Importer.GetStratByID("enchanting__thalassian_phoenix_oil__midnight_1") or nil
            assert(phoenix and phoenix.reagents and phoenix.reagents[2] and phoenix.reagents[3],
                "thalassian phoenix oil ranked reagents unavailable")
            assertRankedIDs(phoenix.reagents[2].itemIDs, 243599, 243600, "Thalassian Phoenix Oil Eversinging Dust")
            assertRankedIDs(phoenix.reagents[3].itemIDs, 240990, 240991, "Thalassian Phoenix Oil Sunglass Vial")

            local smuggler = GAM.Importer and GAM.Importer.GetStratByID
                and GAM.Importer.GetStratByID("enchanting__smuggler_s_enchanted_edge__midnight_1") or nil
            assert(smuggler and smuggler.outputs and smuggler.outputs[1]
                and smuggler.reagents and smuggler.reagents[3] and smuggler.reagents[4],
                "smuggler's enchanted edge ranked items unavailable")
            assertRankedIDs(smuggler.outputs[1].itemIDs, 243737, 243738, "Smuggler's Enchanted Edge output")
            assertRankedIDs(smuggler.reagents[3].itemIDs, 243599, 243600, "Smuggler's Enchanted Edge Eversinging Dust")
            assertRankedIDs(smuggler.reagents[4].itemIDs, 240990, 240991, "Smuggler's Enchanted Edge Sunglass Vial")
        end)
        C_TradeSkillUI = originalCraftUI
        GetItemInfo = originalGetItemInfo
        GAM.GetOptions = originalGetOptions
        Pricing.GetEffectivePrice = originalGetEffectivePrice
        assert(oilRankOK, oilRankErr)

        local originalGetOptions = GAM.GetOptions
        local originalCraftUIForDrums = C_TradeSkillUI
        local originalGetEffectivePriceForDrums = Pricing.GetEffectivePrice
        local drumsRankOK, drumsRankErr = pcall(function()
            C_TradeSkillUI = {
                GetItemReagentQualityByItemInfo = function(itemID)
                    return ({
                        [238511] = 1,
                        [238512] = 2,
                        [238513] = 1,
                        [238514] = 2,
                    })[itemID]
                end,
            }
            GAM.GetOptions = function()
                return {
                    rankPolicy = "highest",
                    lwMulti = 32.0,
                    lwRes = 14.9,
                }
            end
            Pricing.GetEffectivePrice = function(itemID)
                return ({
                    [236952] = 8100,
                    [238525] = 5280357,
                    [238522] = 1319835,
                    [238511] = 49400,
                    [238512] = 620000,
                    [238513] = 167500,
                    [238514] = 480000,
                })[itemID], false
            end

            local drums = GAM.Importer and GAM.Importer.GetStratByID
                and GAM.Importer.GetStratByID("leatherworking__void_touched_drums__midnight_1") or nil
            assert(drums and drums.qualityPolicy == "force_q1_inputs", "void-touched drums strat unavailable")

            local ctx = BuildCalcContext(
                drums, GetActiveRecipeView(drums), GAM.C.DEFAULT_PATCH, 1, GAM.GetOptions(),
                GetPatchDB(GAM.C.DEFAULT_PATCH), GAM.C.AH_CUT)
            local reagents = BuildReagentMetrics(ctx)
            assert((reagents.reagentResults[4] and reagents.reagentResults[4].itemID) == 238511,
                "Void-Touched Drums must force Q1 Void-Tempered Leather")
            assert((reagents.reagentResults[5] and reagents.reagentResults[5].itemID) == 238513,
                "Void-Touched Drums must force Q1 Void-Tempered Scales")
        end)
        GAM.GetOptions = originalGetOptions
        C_TradeSkillUI = originalCraftUIForDrums
        Pricing.GetEffectivePrice = originalGetEffectivePriceForDrums
        assert(drumsRankOK, drumsRankErr)

        if GAM.Importer and GAM.Importer.GetStratByID then
            local crushing = GAM.Importer.GetStratByID("jewelcrafting__crushing__midnight_1")
            assert(crushing and crushing.reagents and crushing.reagents[1], "crushing strat unavailable")
            assert(type(crushing.reagents[1].cheapestOf) == "table" and #crushing.reagents[1].cheapestOf > 0,
                "normalized cheapestOf pool unavailable")
        end

        local canonicalV2OK, canonicalV2Err = pcall(function()
            local originalGetPatchDB = GAM.GetPatchDB
            local originalGetOptions = GAM.GetOptions
            local originalGetItemCount = GetItemCount
            local originalGetEffectivePrice = Pricing.GetEffectivePrice
            local originalProducerCandidates = GAM.Importer and GAM.Importer.GetProducerCandidates
            local originalGetStratByID = GAM.Importer and GAM.Importer.GetStratByID
            local originalCraftingStats = GAM.CraftingStats
            local originalProfile = profiles.__canonical_v2_smoke
            local ok, err = pcall(function()
                profiles.__canonical_v2_smoke = {
                    multiKey = nil,
                    resKey = "v2Res",
                    mcNodeKey = nil,
                    rsNodeKey = "v2RsNode",
                    defaultMulti = nil,
                    defaultRes = 50,
                    defaultMcNode = 0,
                    defaultRsNode = 50,
                    sheetMCm = 0,
                    sheetRs = 0.45,
                }
                local fakePDB = {
                    rankGroups = {},
                    priceOverrides = {},
                }
                local fakeOpts = {
                    rankPolicy = "lowest",
                    shallowFillQty = 50,
                    v2PricingMode = "fixed_crafts",
                    v2Res = 50,
                    v2RsNode = 50,
                }
                local prices = {
                    [80001] = 100,
                    [80002] = 300,
                    [81001] = 250,
                    [81002] = 100,
                    [81003] = 900,
                    [236761] = 100,
                    [245807] = 250,
                }
                GAM.GetPatchDB = function()
                    return fakePDB
                end
                GAM.GetOptions = function()
                    return fakeOpts
                end
                GetItemCount = function()
                    return 0
                end
                Pricing.GetEffectivePrice = function(itemID)
                    return prices[itemID], false
                end

                local directStrat = {
                    id = "canonical_v2_direct",
                    stratName = "Canonical V2 Direct",
                    calcMode = "formula",
                    formulaProfile = "__canonical_v2_smoke",
                    defaultCrafts = 10,
                    defaultStartingAmount = 10,
                    reagents = {
                        { name = "V2 Reagent", itemIDs = { 80001 }, qtyPerCraft = 2 },
                    },
                    outputs = {
                        { name = "V2 Output", itemIDs = { 80002 }, baseYieldPerCraft = 1 },
                    },
                }

                local canonicalMetrics = Pricing.CalculateStratMetricsV2(
                    directStrat, GAM.C.DEFAULT_PATCH, 1)
                assert(canonicalMetrics and canonicalMetrics.reagents and canonicalMetrics.reagents[1]
                        and canonicalMetrics.reagents[1].required == 20,
                    "Canonical V2 visible reagent quantity failed")
                assert(canonicalMetrics.reagents[1].needToBuy == 20,
                    "Canonical V2 visible need-to-buy quantity failed")
                assert(canonicalMetrics and canonicalMetrics.requiredCostFull == 2000,
                    "Canonical V2 required cost failed")
                assert(math.abs((canonicalMetrics.expectedConsumedCostFull or 0) - 1550) < 0.001,
                    string.format("Canonical V2 expected consumed cost failed: got %.6f",
                        canonicalMetrics.expectedConsumedCostFull or 0))
                assert(canonicalMetrics.requiredCostFull > canonicalMetrics.expectedConsumedCostFull,
                    "V2 resourcefulness expected cost reduction missing")

                fakeOpts.v2PricingMode = "exhaust_materials"
                local exhaustMetrics = Pricing.CalculateStratMetricsV2(
                    directStrat, GAM.C.DEFAULT_PATCH, 1)
                assert(exhaustMetrics and exhaustMetrics.formula
                        and exhaustMetrics.formula.pricingMode == "exhaust_materials"
                        and exhaustMetrics.formula.model == "exhaustMaterials",
                    "V2 Exhaust Materials mode selection failed")
                assert(math.abs((exhaustMetrics.expectedConsumedCostFull or 0) - 2000) < 0.001,
                    string.format("V2 Exhaust Materials should keep full input budget as cost: got %.6f",
                        exhaustMetrics.expectedConsumedCostFull or 0))
                assert(((exhaustMetrics.output and exhaustMetrics.output.expectedQtyRaw) or 0)
                        > ((canonicalMetrics.output and canonicalMetrics.output.expectedQtyRaw) or 0),
                    "V2 Exhaust Materials Resourcefulness should increase expected output")
                fakeOpts.v2PricingMode = "fixed_crafts"

                fakeOpts.pigmentCostSource = "mill"
                local producer = {
                    id = "canonical_v2_producer",
                    stratName = "Canonical V2 Producer",
                    profession = "Inscription",
                    calcMode = "formula",
                    formulaProfile = "__canonical_v2_smoke",
                    defaultCrafts = 10,
                    defaultStartingAmount = 10,
                    reagents = {
                        { name = "V2 Raw", itemIDs = { 81002 }, qtyPerCraft = 2 },
                    },
                    outputs = {
                        { name = "V2 Intermediate", itemIDs = { 81001 }, baseYieldPerCraft = 1 },
                    },
                }
                local root = {
                    id = "canonical_v2_root",
                    stratName = "Canonical V2 Root",
                    profession = "Inscription",
                    calcMode = "fixed",
                    defaultCrafts = 1,
                    defaultStartingAmount = 1,
                    reagents = {
                        { name = "V2 Intermediate", itemIDs = { 81001 }, qtyPerCraft = 10 },
                    },
                    outputs = {
                        { name = "V2 Finished", itemIDs = { 81003 }, baseYieldPerCraft = 1 },
                    },
                }

                GAM.Importer.GetProducerCandidates = function(itemID)
                    if itemID == 81001 then
                        return {
                            { stratID = "canonical_v2_producer" },
                        }
                    end
                    return {}
                end
                GAM.Importer.GetStratByID = function(id)
                    if id == "canonical_v2_producer" then
                        return producer
                    end
                    if originalGetStratByID then
                        return originalGetStratByID(id)
                    end
                    return nil
                end

                local rootMetrics = Pricing.CalculateStratMetricsV2(root, GAM.C.DEFAULT_PATCH, 1)
                assert(rootMetrics and math.abs((rootMetrics.requiredCostFull or 0) - 2000) < 0.001,
                    "V2 VI required cost failed")
                assert(math.abs((rootMetrics.expectedConsumedCostFull or 0) - 1550) < 0.001,
                    string.format("V2 VI expected consumed cost failed: got %.6f",
                        rootMetrics.expectedConsumedCostFull or 0))

                -- Powder Pigment is intentionally a real legacy derivation ID.
                -- With VI active, GetEffectivePriceForItem derives it from
                -- Tranquility Bloom.  V2 must nevertheless compare its actual
                -- direct AH price against the canonical milling producer.
                local mappedProducer = {
                    id = "canonical_v2_mapped_producer",
                    stratName = "Canonical V2 Mapped Producer",
                    profession = "Inscription",
                    calcMode = "formula",
                    formulaProfile = "__canonical_v2_smoke",
                    defaultCrafts = 10,
                    defaultStartingAmount = 10,
                    reagents = {
                        { name = "V2 Raw", itemIDs = { 81002 }, qtyPerCraft = 2 },
                    },
                    outputs = {
                        { name = "Powder Pigment", itemIDs = { 245807 }, baseYieldPerCraft = 1 },
                    },
                }
                local mappedRoot = {
                    id = "canonical_v2_mapped_root",
                    stratName = "Canonical V2 Mapped Root",
                    profession = "Inscription",
                    calcMode = "fixed",
                    defaultCrafts = 1,
                    defaultStartingAmount = 1,
                    reagents = {
                        { name = "Powder Pigment", itemIDs = { 245807 }, qtyPerCraft = 10 },
                    },
                    outputs = {
                        { name = "V2 Finished", itemIDs = { 81003 }, baseYieldPerCraft = 1 },
                    },
                }
                GAM.Importer.GetProducerCandidates = function(itemID)
                    if itemID == 245807 then
                        return { { stratID = "canonical_v2_mapped_producer" } }
                    end
                    if itemID == 81001 then
                        return { { stratID = "canonical_v2_producer" } }
                    end
                    return {}
                end
                GAM.Importer.GetStratByID = function(id)
                    if id == "canonical_v2_mapped_producer" then
                        return mappedProducer
                    end
                    if id == "canonical_v2_producer" then
                        return producer
                    end
                    if originalGetStratByID then
                        return originalGetStratByID(id)
                    end
                    return nil
                end

                local mappedCraftMetrics = Pricing.CalculateStratMetricsV2(
                    mappedRoot, GAM.C.DEFAULT_PATCH, 1)
                assert(mappedCraftMetrics
                        and mappedCraftMetrics.economicChoices
                        and mappedCraftMetrics.economicChoices["245807"]
                        and mappedCraftMetrics.economicChoices["245807"].source == "producer",
                    "V2 VI compared the producer against a derived pseudo-direct price")
                assert(mappedCraftMetrics.reagents and mappedCraftMetrics.reagents[1]
                        and mappedCraftMetrics.reagents[1].itemID == 81002
                        and mappedCraftMetrics.reagents[1].unitPrice == 100,
                    "V2 VI producer choice did not expand to truthfully priced raw materials")
                local mappedCraftBreakdown = Pricing.GetVIBreakdownData(
                    mappedRoot, GAM.C.DEFAULT_PATCH, mappedCraftMetrics)
                assert(mappedCraftBreakdown and mappedCraftBreakdown.entries
                        and mappedCraftBreakdown.entries[1]
                        and mappedCraftBreakdown.entries[1].kind == "craft"
                        and mappedCraftBreakdown.entries[2]
                        and mappedCraftBreakdown.entries[2].itemID == 81002,
                    "V2 VI breakdown did not follow the selected producer path")

                -- A VI chain may intentionally use different saved tools at
                -- each stage: Resourcefulness for milling and Multicraft for
                -- the consuming/final craft. Producer gear choices must not be
                -- replaced by the root strategy's choice.
                local resolvedGearByStrat = {}
                GAM.CraftingStats = {
                    GetGearModeForStrat = function(strategy)
                        if strategy and strategy.id == "canonical_v2_mapped_producer" then
                            return "resourcefulness"
                        end
                        if strategy and strategy.id == "canonical_v2_mapped_root" then
                            return "multicraft"
                        end
                        return "auto"
                    end,
                    GetAvailableGearPresetModes = function()
                        return { multicraft = true, resourcefulness = true }
                    end,
                    ResolveForStrat = function(strategy, statOpts)
                        resolvedGearByStrat[strategy.id] = statOpts and statOpts._gamGearModeOverride
                        return {
                            profileKey = strategy.formulaProfile,
                            statSource = "gear-preset-" .. tostring(statOpts and statOpts._gamGearModeOverride),
                            multiPercent = 30,
                            multiExtra = 1,
                            resPercent = 30,
                            resExtra = 0.55,
                            supportsMulticraft = true,
                            supportsResourcefulness = true,
                        }
                    end,
                }
                local mixedGearMetrics = Pricing.CalculateStratMetricsV2(
                    mappedRoot, GAM.C.DEFAULT_PATCH, 1)
                assert(mixedGearMetrics
                        and resolvedGearByStrat["canonical_v2_mapped_root"] == "multicraft"
                        and resolvedGearByStrat["canonical_v2_mapped_producer"] == "resourcefulness",
                    "V2 VI did not resolve root and producer gear plans independently")
                local mixedGearBreakdown = Pricing.GetVIBreakdownData(
                    mappedRoot, GAM.C.DEFAULT_PATCH, mixedGearMetrics)
                assert(mixedGearBreakdown
                        and mixedGearBreakdown.entries
                        and mixedGearBreakdown.entries[1]
                        and mixedGearBreakdown.entries[1].gearModeResolved == "resourcefulness"
                        and mixedGearBreakdown.finalGearModeResolved == "multicraft",
                    "V2 VI breakdown lost per-stage gear choices")
                GAM.CraftingStats = originalCraftingStats

                prices[81002] = 1000
                local mappedDirectMetrics = Pricing.CalculateStratMetricsV2(
                    mappedRoot, GAM.C.DEFAULT_PATCH, 1)
                assert(mappedDirectMetrics
                        and mappedDirectMetrics.economicChoices
                        and mappedDirectMetrics.economicChoices["245807"]
                        and mappedDirectMetrics.economicChoices["245807"].source == "direct",
                    "V2 VI did not retain the cheaper actual intermediate purchase")
                assert(mappedDirectMetrics.reagents and mappedDirectMetrics.reagents[1]
                        and mappedDirectMetrics.reagents[1].itemID == 245807
                        and mappedDirectMetrics.reagents[1].unitPrice == 250,
                    "V2 VI direct shopping row reused a derived producer price")
                local mappedDirectBreakdown = Pricing.GetVIBreakdownData(
                    mappedRoot, GAM.C.DEFAULT_PATCH, mappedDirectMetrics)
                assert(mappedDirectBreakdown and mappedDirectBreakdown.entries
                        and #mappedDirectBreakdown.entries == 1
                        and mappedDirectBreakdown.entries[1].kind == "leaf"
                        and mappedDirectBreakdown.entries[1].itemID == 245807
                        and mappedDirectBreakdown.entries[1].effectiveUnitPrice == 250,
                    "V2 VI breakdown disagreed with the selected direct purchase")
                prices[81002] = 100

                producer.profession = "Jewelcrafting"
                local crossProfessionMetrics = Pricing.CalculateStratMetricsV2(
                    root, GAM.C.DEFAULT_PATCH, 1)
                assert(crossProfessionMetrics
                        and math.abs((crossProfessionMetrics.requiredCostFull or 0) - 2500) < 0.001,
                    "V2 VI must buy an intermediate produced by another profession")
                producer.profession = "Inscription"

                prices[81005] = 50
                local directCheapProducer = {
                    id = "canonical_v2_direct_cheap_producer",
                    stratName = "Canonical V2 Direct Cheap Producer",
                    profession = "Inscription",
                    calcMode = "formula",
                    formulaProfile = "__canonical_v2_smoke",
                    defaultCrafts = 10,
                    defaultStartingAmount = 10,
                    reagents = {
                        { name = "V2 Raw", itemIDs = { 81002 }, qtyPerCraft = 2 },
                    },
                    outputs = {
                        { name = "V2 Direct Cheap Intermediate", itemIDs = { 81005 }, baseYieldPerCraft = 1 },
                    },
                }
                local directCheapRoot = {
                    id = "canonical_v2_direct_cheap_root",
                    stratName = "Canonical V2 Direct Cheap Root",
                    profession = "Inscription",
                    calcMode = "fixed",
                    defaultCrafts = 1,
                    defaultStartingAmount = 1,
                    reagents = {
                        { name = "V2 Direct Cheap Intermediate", itemIDs = { 81005 }, qtyPerCraft = 10 },
                    },
                    outputs = {
                        { name = "V2 Finished", itemIDs = { 81003 }, baseYieldPerCraft = 1 },
                    },
                }
                GAM.Importer.GetProducerCandidates = function(itemID)
                    if itemID == 81001 then
                        return {
                            { stratID = "canonical_v2_producer" },
                        }
                    end
                    if itemID == 81005 then
                        return {
                            { stratID = "canonical_v2_direct_cheap_producer" },
                        }
                    end
                    return {}
                end
                GAM.Importer.GetStratByID = function(id)
                    if id == "canonical_v2_direct_cheap_producer" then
                        return directCheapProducer
                    end
                    if id == "canonical_v2_producer" then
                        return producer
                    end
                    if originalGetStratByID then
                        return originalGetStratByID(id)
                    end
                    return nil
                end
                local directCheapMetrics = Pricing.CalculateStratMetricsV2(directCheapRoot, GAM.C.DEFAULT_PATCH, 1)
                assert(directCheapMetrics and math.abs((directCheapMetrics.requiredCostFull or 0) - 500) < 0.001,
                    "V2 VI should keep direct buy cost when direct is cheaper")
                assert(math.abs((directCheapMetrics.expectedConsumedCostFull or 0) - 500) < 0.001,
                    string.format("V2 VI direct-cheaper expected consumed cost failed: got %.6f",
                        directCheapMetrics.expectedConsumedCostFull or 0))
                assert(directCheapMetrics.reagents and directCheapMetrics.reagents[1]
                        and directCheapMetrics.reagents[1].sourceNote == nil,
                    "V2 VI direct-cheaper display should not annotate crafted source")

                local largeProducer = {
                    id = "canonical_v2_large_producer",
                    stratName = "Canonical V2 Large Producer",
                    profession = "Inscription",
                    calcMode = "formula",
                    formulaProfile = "__canonical_v2_smoke",
                    defaultCrafts = 1,
                    defaultStartingAmount = 10,
                    reagents = {
                        { name = "V2 Raw", itemIDs = { 81002 }, qtyPerCraft = 10 },
                    },
                    outputs = {
                        { name = "V2 Large Intermediate", itemIDs = { 81004 }, baseYieldPerCraft = 13 },
                    },
                }
                local largeRoot = {
                    id = "canonical_v2_large_root",
                    stratName = "Canonical V2 Large Root",
                    profession = "Inscription",
                    calcMode = "fixed",
                    defaultCrafts = 1,
                    defaultStartingAmount = 1,
                    reagents = {
                        { name = "V2 Large Intermediate", itemIDs = { 81004 }, qtyPerCraft = 4000 },
                    },
                    outputs = {
                        { name = "V2 Finished", itemIDs = { 81003 }, baseYieldPerCraft = 1 },
                    },
                }
                GAM.Importer.GetProducerCandidates = function(itemID)
                    if itemID == 81001 then
                        return {
                            { stratID = "canonical_v2_producer" },
                        }
                    end
                    if itemID == 81004 then
                        return {
                            { stratID = "canonical_v2_large_producer" },
                        }
                    end
                    return {}
                end
                GAM.Importer.GetStratByID = function(id)
                    if id == "canonical_v2_large_producer" then
                        return largeProducer
                    end
                    if id == "canonical_v2_producer" then
                        return producer
                    end
                    if originalGetStratByID then
                        return originalGetStratByID(id)
                    end
                    return nil
                end
                local largeMetrics = Pricing.CalculateStratMetricsV2(largeRoot, GAM.C.DEFAULT_PATCH, 1)
                assert(largeMetrics
                        and largeMetrics.reagents
                        and largeMetrics.reagents[1]
                        and largeMetrics.reagents[1].itemID == 81002
                        and largeMetrics.reagents[1].required == 3080,
                    string.format("V2 VI execution display should expand the producer inputs: got %s",
                        tostring(largeMetrics and largeMetrics.reagents and largeMetrics.reagents[1]
                            and largeMetrics.reagents[1].required)))

                GAM.CraftingStats = {
                    ResolveForStrat = function(strat)
                        return {
                            profileKey = strat and (strat.statProfileKey or strat.formulaProfile),
                            statSource = "craftsim-imported",
                            resPercent = 12.5,
                            resExtra = 0.35,
                            supportsResourcefulness = true,
                        }
                    end,
                }
                local snapshotStrat = {
                    id = "canonical_v2_imported_snapshot",
                    stratName = "Canonical V2 Imported Snapshot",
                    profession = "Inscription",
                    calcMode = "formula",
                    formulaProfile = "__canonical_v2_smoke",
                    defaultCrafts = 10,
                    defaultStartingAmount = 10,
                    reagents = {
                        { name = "V2 Reagent", itemIDs = { 80001 }, qtyPerCraft = 2 },
                    },
                    outputs = {
                        { name = "V2 Output", itemIDs = { 80002 }, baseYieldPerCraft = 1 },
                    },
                }
                local snapshotMetrics = Pricing.CalculateStratMetricsV2(snapshotStrat, GAM.C.DEFAULT_PATCH, 1)
                assert(snapshotMetrics and snapshotMetrics.formula and snapshotMetrics.formula.statSource == "craftsim-imported",
                    "Canonical V2 should use imported stat snapshots from the GAM resolver")
                assert(math.abs((snapshotMetrics.expectedConsumedCostFull or 0) - 1898.75) < 0.001,
                    string.format("V2 imported snapshot resourcefulness failed: got %.6f",
                        snapshotMetrics.expectedConsumedCostFull or 0))

                GAM.CraftingStats = {
                    ResolveForStrat = function(strat)
                        return {
                            statSource = "gam-cache-profile",
                            profileKey = strat and (strat.statProfileKey or strat.formulaProfile),
                            resPercent = 12.5,
                            resExtra = 0.35,
                            supportsResourcefulness = true,
                        }
                    end,
                }
                local cachedProfileMetrics = Pricing.CalculateStratMetricsV2(
                    snapshotStrat, GAM.C.DEFAULT_PATCH, 1)
                assert(cachedProfileMetrics
                        and cachedProfileMetrics.formula
                        and cachedProfileMetrics.formula.statSource == "gam-cache-profile",
                    "Canonical V2 should accept exact profile stat cache from the GAM resolver")
                assert(math.abs((cachedProfileMetrics.expectedConsumedCostFull or 0) - 1898.75) < 0.001,
                    string.format("V2 exact profile cache resourcefulness failed: got %.6f",
                        cachedProfileMetrics.expectedConsumedCostFull or 0))
            end)
            GAM.GetPatchDB = originalGetPatchDB
            GAM.GetOptions = originalGetOptions
            GetItemCount = originalGetItemCount
            Pricing.GetEffectivePrice = originalGetEffectivePrice
            GAM.CraftingStats = originalCraftingStats
            if GAM.Importer then
                GAM.Importer.GetProducerCandidates = originalProducerCandidates
                GAM.Importer.GetStratByID = originalGetStratByID
            end
            profiles.__canonical_v2_smoke = originalProfile
            assert(ok, err)
        end)
        assert(canonicalV2OK, canonicalV2Err)

        -- ── Spreadsheet-parity checks ─────────────────────────────────────────
        -- Verify formula profiles reproduce workbookExpectedQty at default stats.
        local profiles = GetFormulaProfiles()

        -- insc_ink: live sheet Inscription!A18=29.7 (multi) and A16=16.1 (res)
        local inkProfile = profiles["insc_ink"]
        assert(inkProfile, "insc_ink profile missing")
        assert(math.abs((inkProfile.defaultMulti or 0) - 29.7) < 0.01,
            string.format("insc_ink defaultMulti parity fail: got %.3f expected 29.7", inkProfile.defaultMulti or 0))
        local missiveProfile = profiles["insc_missive_estimated"]
        assert(missiveProfile, "insc_missive_estimated profile missing")
        assert((missiveProfile.multiKey or "") == (inkProfile.multiKey or ""),
            "insc_missive_estimated multiKey must mirror insc_ink")
        assert((missiveProfile.resKey or "") == (inkProfile.resKey or ""),
            "insc_missive_estimated resKey must mirror insc_ink")
        local codifiedProfile = profiles["insc_codified"]
        assert(codifiedProfile, "insc_codified profile missing")

        -- leatherworking: live sheet Leatherworking!A18=32.0
        local lwProfile = profiles["leatherworking"]
        assert(lwProfile, "leatherworking profile missing")
        assert(math.abs((lwProfile.defaultMulti or 0) - 32.0) < 0.01,
            string.format("leatherworking defaultMulti parity fail: got %.3f expected 32.0", lwProfile.defaultMulti or 0))
        local bsProfile = profiles["blacksmithing"]
        assert(bsProfile, "blacksmithing profile missing")
        assert(math.abs((bsProfile.defaultMulti or 0) - 33.0) < 0.01,
            string.format("blacksmithing defaultMulti parity fail: got %.3f expected 33.0", bsProfile.defaultMulti or 0))
        assert(math.abs((bsProfile.sheetMCm or 0) - 1.4) < 0.01,
            string.format("blacksmithing sheetMCm parity fail: got %.3f expected 1.4", bsProfile.sheetMCm or 0))

        -- Engineering profiles must be split
        assert(profiles["engineering_recycling"], "engineering_recycling profile missing")
        assert(profiles["engineering_craft"], "engineering_craft profile missing")
        assert(not profiles["engineering"], "stale unified engineering profile still present")

        if GAM.Importer and GAM.Importer.GetStratByID then
            local function assertNear(actual, expected, label)
                assert(math.abs(actual - expected) <= math.max(0.0001, math.abs(expected) * 0.001),
                    string.format("%s: got %.6f expected %.6f", label, actual, expected))
            end

            local originalGetOptions = GAM.GetOptions
            local derivedParityOK, derivedParityErr = pcall(function()
                local parityOpts = {
                    pigmentCostSource = "mill",
                    boltCostSource = "craft",
                    ingotCostSource = "craft",
                    inscMillingRes = 30.1,
                    inscInkMulti = 29.7,
                    inscInkRes = 16.1,
                }
                GAM.GetOptions = function()
                    return parityOpts
                end

                local priceMap = {
                    [236761] = 30798,  -- Tranquility Bloom
                    [236776] = 239300, -- Argentleaf
                    [236778] = 120000, -- Mana Lily
                    [236770] = 10400,  -- Sanguithorn
                    [245882] = 3595,   -- Thalassian Songwater
                }
                local deps = {
                    PickItemID = function(ids)
                        return ids and ids[1] or nil
                    end,
                    GetEffectivePrice = function(itemID)
                        return priceMap[itemID], false
                    end,
                }

                local pigmentYield = 1.3 / (1 - 0.301 * 0.465)
                local inkYield = 0.1 * (1 + 0.297 * 2.5) / (1 - 0.161 * 0.465)

                local powderCost = Derivation.GetMillDerivedPigmentCost(245807, GAM.C.DEFAULT_PATCH, 1512, deps)
                local argentleafCost = Derivation.GetMillDerivedPigmentCost(245803, GAM.C.DEFAULT_PATCH, 756, deps)
                local manaCost = Derivation.GetMillDerivedPigmentCost(245867, GAM.C.DEFAULT_PATCH, 378, deps)
                local sanguithornCost = Derivation.GetMillDerivedPigmentCost(245865, GAM.C.DEFAULT_PATCH, 756, deps)

                assertNear(powderCost or 0, math.floor(priceMap[236761] / pigmentYield + 0.5),
                    "inscription powder pigment derived cost")
                assertNear(argentleafCost or 0, math.floor(priceMap[236776] / pigmentYield + 0.5),
                    "inscription argentleaf pigment derived cost")
                assertNear(manaCost or 0, math.floor(priceMap[236778] / pigmentYield + 0.5),
                    "inscription mana pigment derived cost")
                assertNear(sanguithornCost or 0, math.floor(priceMap[236770] / pigmentYield + 0.5),
                    "inscription sanguithorn pigment derived cost")

                local expectedSienna = math.floor((
                    (powderCost * 1.0)
                    + (argentleafCost * 0.5)
                    + (manaCost * 0.25)
                ) / inkYield + 0.5)
                local expectedMunsell = math.floor((
                    (powderCost * 1.0)
                    + (sanguithornCost * 0.5)
                    + (manaCost * 0.25)
                ) / inkYield + 0.5)

                local siennaCost = Derivation.GetCraftDerivedReagentCost(245805, GAM.C.DEFAULT_PATCH, 285, deps)
                local munsellCost = Derivation.GetCraftDerivedReagentCost(245801, GAM.C.DEFAULT_PATCH, 285, deps)
                assertNear(siennaCost or 0, expectedSienna, "inscription sienna derived cost")
                assertNear(munsellCost or 0, expectedMunsell, "inscription munsell derived cost")

                local sienna = GAM.Importer.GetStratByID("inscription__sienna_ink__midnight_1")
                assert(sienna, "sienna strat unavailable")
                local active = GetActiveRecipeView(sienna)
                local ctx = BuildCalcContext(
                    sienna, active, GAM.C.DEFAULT_PATCH, 1, parityOpts,
                    GetPatchDB(GAM.C.DEFAULT_PATCH), GAM.C.AH_CUT)
                local mergedOrder, mergedMap = BuildMergedReagentMap(ctx)
                assert(#mergedOrder == 4, string.format(
                    "sienna reagent list regressed to raw-chain expansion: got %d entries expected 4",
                    #mergedOrder))
                assert(mergedMap[245807] and mergedMap[245803] and mergedMap[245867] and mergedMap[245882],
                    "sienna reagent list must stay at powder/pigment/songwater sheet level")
                assert(mergedMap[245882].excludeFromCost,
                    "sienna songwater must stay visible but excluded from sheet cost math")

                local originalGetUnitPrice = Pricing.GetUnitPrice
                local originalGetItemCount = GetItemCount
                local recyclingParityOK, recyclingParityErr = pcall(function()
                    Pricing.GetUnitPrice = function(itemID)
                        local recyclingPrices = {
                            [236761] = 27000, -- cheaper herb-derived pigment would regress engineering recycling
                            [245807] = 24800, -- Powder Pigment Q1 direct sheet price
                            [243581] = 68900, -- Evercore Q1
                        }
                        return recyclingPrices[itemID], false
                    end
                    GetItemCount = function()
                        return 0
                    end

                    local recycling = GAM.Importer.GetStratByID("engineering__recycling_powder_pigment__midnight_1")
                    assert(recycling, "engineering recycling powder pigment strat unavailable")
                    assert(recycling.reagents and recycling.reagents[1] and recycling.reagents[1].skipDerivation,
                        "engineering recycling reagent must preserve skipDerivation")
                    local recyclingActive = GetActiveRecipeView(recycling)
                    local recyclingCtx = BuildCalcContext(
                        recycling, recyclingActive, GAM.C.DEFAULT_PATCH, 1, {
                            pigmentCostSource = "mill",
                            engRecycleRes = 36.0,
                            rankPolicy = "lowest",
                        }, GetPatchDB(GAM.C.DEFAULT_PATCH), GAM.C.AH_CUT)
                    local recyclingReagents = BuildReagentMetrics(recyclingCtx)
                    assertNear((recyclingReagents.reagentResults[1] and recyclingReagents.reagentResults[1].unitPrice) or 0,
                        24800, "engineering recycling powder pigment direct reagent price")
                    local recyclingOutputPrice = GetOutputPriceForItem(
                        recyclingActive.outputs[1], GAM.C.DEFAULT_PATCH, 1, 1, recycling.recipeID)
                    assertNear(recyclingOutputPrice or 0, 68900,
                        "engineering recycling powder pigment output price")
                end)
                Pricing.GetUnitPrice = originalGetUnitPrice
                GetItemCount = originalGetItemCount
                assert(recyclingParityOK, recyclingParityErr)

                local displayParityOK, displayParityErr = pcall(function()
                    local originalGetUnitPrice = Pricing.GetUnitPrice
                    local originalGetItemCount = GetItemCount
                    Pricing.GetUnitPrice = function(itemID)
                        local displayPrices = {
                            [236761] = 27000,  -- Tranquility Bloom Q1
                            [236776] = 239300, -- Argentleaf Q1
                            [236778] = 120000, -- Mana Lily Q1
                            [236770] = 10400,  -- Sanguithorn Q1
                            [236963] = 81400,  -- Bright Linen Q1
                            [251665] = 5000,   -- Silverleaf Thread
                            [237359] = 31500,  -- Refulgent Copper Ore Q1
                            [243060] = 5000,   -- Luminant Flux
                            [245807] = 24800,  -- Powder Pigment Q1
                            [243581] = 68900,  -- Evercore Q1
                        }
                        return displayPrices[itemID], false
                    end
                    GetItemCount = function()
                        return 0
                    end

                    local function collectSeenIDs(metricRows)
                        local seen = {}
                        for _, row in ipairs(metricRows or {}) do
                            if row.itemID then
                                seen[row.itemID] = true
                            end
                        end
                        return seen
                    end

                    local soulCipher = GAM.Importer.GetStratByID("inscription__soul_cipher__midnight_1")
                    assert(soulCipher, "soul cipher strat unavailable")
                    local soulMetrics = Pricing.CalculateStratMetricsV2(soulCipher, GAM.C.DEFAULT_PATCH, 1)
                    local soulSeen = collectSeenIDs(soulMetrics and soulMetrics.reagents)
                    assert(soulSeen[236761] or soulSeen[236767],
                        "soul cipher VI detail rows must expand ink inputs to herb leaves")
                    assert(not soulSeen[245805] and not soulSeen[245806]
                            and not soulSeen[245801] and not soulSeen[245802],
                        "soul cipher VI detail rows retained crafted ink intermediates")

                    -- Execution planning must consume owned intermediates before
                    -- recursively turning their full demand into raw materials.
                    -- Existing final output is deliberately irrelevant: the user
                    -- asked to craft additional units, not fill an inventory target.
                    local munsell = GAM.Importer.GetStratByID("inscription__munsell_ink__midnight_1")
                    assert(munsell, "munsell ink strat unavailable")
                    GetItemCount = function(itemID)
                        return ({
                            [245807] = 100000, -- Powder Pigment Q1
                            [245865] = 100000, -- Sanguithorn Pigment Q1
                            [245867] = 100000, -- Mana Lily Pigment Q1
                            [245801] = 100000, -- Existing Munsell Ink must not satisfy new crafts
                        })[itemID] or 0
                    end
                    local ownedMunsellMetrics = Pricing.CalculateStratMetricsV2(
                        munsell, GAM.C.DEFAULT_PATCH, 1)
                    local ownedMunsellSeen = collectSeenIDs(ownedMunsellMetrics and ownedMunsellMetrics.reagents)
                    assert(not ownedMunsellSeen[236761]
                            and not ownedMunsellSeen[236770]
                            and not ownedMunsellSeen[236778],
                        "owned pigments were expanded into unnecessary herb purchases")
                    local ownedMunsellBreakdown = Pricing.GetVIBreakdownData(
                        munsell, GAM.C.DEFAULT_PATCH, ownedMunsellMetrics)
                    for _, entry in ipairs(ownedMunsellBreakdown and ownedMunsellBreakdown.entries or {}) do
                        assert(not entry.producerStratID,
                            "owned pigments still created an intermediate milling step")
                    end
                    GetItemCount = function()
                        return 0
                    end

                    local codified = GAM.Importer.GetStratByID("inscription__codified_azeroot__midnight_1")
                    assert(codified, "codified azeroot strat unavailable")
                    local codifiedMetrics = Pricing.CalculateStratMetricsV2(codified, GAM.C.DEFAULT_PATCH, 1)
                    local codifiedSeen = collectSeenIDs(codifiedMetrics and codifiedMetrics.reagents)
                    local codifiedUsesExpandedSoul = codifiedSeen[236761] or codifiedSeen[236767]
                    local codifiedUsesDirectSoul = codifiedSeen[245766] or codifiedSeen[245767]
                    assert(not not codifiedUsesExpandedSoul ~= not not codifiedUsesDirectSoul,
                        "codified azeroot VI detail rows must show exactly one selected soul cipher path")

                    local peerless = GAM.Importer.GetStratByID("inscription__peerless_missive__midnight_1")
                    assert(peerless, "peerless missive strat unavailable")
                    local peerlessMetrics = Pricing.CalculateStratMetricsV2(peerless, GAM.C.DEFAULT_PATCH, 10)
                    local expectedMissiveQty = GAM.PricingFormula.CalculateExhaustMaterials({
                        crafts = 10,
                        baseYield = 1,
                        mcPercent = parityOpts.inscInkMulti / 100,
                        resPercent = parityOpts.inscInkRes / 100,
                        mcExtra = 1.00,
                        resExtra = 0.55,
                        supportsMulticraft = true,
                        supportsResourcefulness = true,
                    }).expectedOutput
                    assertNear((peerlessMetrics and peerlessMetrics.output and peerlessMetrics.output.expectedQtyRaw) or 0,
                        expectedMissiveQty,
                        "peerless missive estimated formula output")
                    local displayQtyByID = {}
                    for _, row in ipairs(peerlessMetrics and peerlessMetrics.reagents or {}) do
                        if row.itemID then
                            displayQtyByID[row.itemID] = row.required
                        end
                    end
                    assert(displayQtyByID[236761] or displayQtyByID[236776]
                            or displayQtyByID[236770] or displayQtyByID[236778],
                        "peerless missive VI detail rows must expand inks to herb leaves")
                    assert(not displayQtyByID[245801] and not displayQtyByID[245802]
                            and not displayQtyByID[245805] and not displayQtyByID[245806],
                        "peerless missive VI detail rows retained crafted ink intermediates")

                    local imbuedBolt = GAM.Importer.GetStratByID("tailoring__imbued_bright_linen_bolt__midnight_1")
                    assert(imbuedBolt, "imbued bright linen bolt strat unavailable")
                    local boltMetrics = Pricing.CalculateStratMetricsV2(imbuedBolt, GAM.C.DEFAULT_PATCH, 1)
                    local boltSeen = collectSeenIDs(boltMetrics and boltMetrics.reagents)
                    assert((boltSeen[236963] or boltSeen[236965]) and boltSeen[251665],
                        "imbued bright linen bolt VI rows must expand bolts to linen + thread")
                    assert(not boltSeen[239700] and not boltSeen[239701],
                        "imbued bright linen bolt VI rows retained crafted bolt intermediates")

                    local refulgentIngot = GAM.Importer.GetStratByID("blacksmithing__refulgent_copper_ingot__midnight_1")
                    assert(refulgentIngot, "refulgent copper ingot strat unavailable")
                    local ingotMetrics = Pricing.CalculateStratMetricsV2(refulgentIngot, GAM.C.DEFAULT_PATCH, 1)
                    local ingotSeen = collectSeenIDs(ingotMetrics and ingotMetrics.reagents)
                    assert(ingotSeen[237359] and ingotSeen[243060], "refulgent copper ingot VI must expand to ore + flux")
                    assert(not ingotSeen[238197] and not ingotSeen[238198],
                        "refulgent copper ingot VI must not display ingot rows")

                    local recycling = GAM.Importer.GetStratByID("engineering__recycling_powder_pigment__midnight_1")
                    assert(recycling, "engineering recycling powder pigment strat unavailable")
                    local recyclingMetrics = Pricing.CalculateStratMetricsV2(recycling, GAM.C.DEFAULT_PATCH, 1)
                    local recyclingSeen = collectSeenIDs(recyclingMetrics and recyclingMetrics.reagents)
                    assert(recyclingSeen[245807] and not recyclingSeen[236761] and not recyclingSeen[236767],
                        "engineering recycling VI display must remain direct")

                    local crushing = GAM.Importer.GetStratByID("jewelcrafting__crushing__midnight_1")
                    assert(crushing, "crushing strat unavailable")
                    local analyzer = Pricing.GetCrushingAnalyzerData(crushing, GAM.C.DEFAULT_PATCH)
                    assert(analyzer and analyzer.entries and #analyzer.entries > 0, "crushing analyzer data unavailable")
                    local scaledCrushingMetrics = Pricing.CalculateStratMetricsV2(crushing, GAM.C.DEFAULT_PATCH, 2)
                    local scaledAnalyzer = Pricing.GetCrushingAnalyzerData(crushing, GAM.C.DEFAULT_PATCH, scaledCrushingMetrics)
                    assert(scaledAnalyzer and scaledAnalyzer.crafts == scaledCrushingMetrics.crafts,
                        "crushing analyzer must inherit current craft quantity")
                    local selectedAnalyzerProfit = nil
                    for _, entry in ipairs(scaledAnalyzer.entries or {}) do
                        if entry.isSelected then
                            selectedAnalyzerProfit = entry.profit
                            break
                        end
                    end
                    assertNear(selectedAnalyzerProfit or 0, scaledCrushingMetrics.profit or 0,
                        "crushing analyzer selected profit must follow current craft quantity")
                end)
                Pricing.GetUnitPrice = originalGetUnitPrice
                GetItemCount = originalGetItemCount
                assert(displayParityOK, displayParityErr)
            end)
            GAM.GetOptions = originalGetOptions
            assert(derivedParityOK, derivedParityErr)

            local function checkWorkbookParity(stratID, outputIdx, expectedQty, label)
                local strat = GAM.Importer.GetStratByID(stratID)
                if not strat then return end
                local profileDef = profiles[strat.formulaProfile]
                if not profileDef then return end
                -- Build a default-opts snapshot for this profile so we evaluate at
                -- spreadsheet baseline stats (independent of the user's saved values).
                local defaultOpts = {}
                if profileDef.multiKey then
                    defaultOpts[profileDef.multiKey] = profileDef.defaultMulti or 0
                end
                if profileDef.resKey then
                    defaultOpts[profileDef.resKey] = profileDef.defaultRes or 0
                end
                local ctx = BuildProfileContext(strat, defaultOpts)
                local outputDef = strat.outputs and strat.outputs[outputIdx]
                if not outputDef then return end
                local sa = strat.defaultStartingAmount or 1
                local cr = strat.defaultCrafts or sa
                local qty = ComputeOutputQuantity(outputDef, strat, ctx.profileDef, ctx.statDenom, ctx.statMCp, ctx.statMCm_tot, sa, cr)
                assertNear(qty, expectedQty, "Parity " .. label)
            end

            local function checkVariantWorkbookParity(stratID, variantKey, outputIdx, expectedQty, label)
                local strat = GAM.Importer.GetStratByID(stratID)
                if not strat or not strat.rankVariants or not strat.rankVariants[variantKey] then
                    return
                end
                local variant = strat.rankVariants[variantKey]
                local profileDef = profiles[strat.formulaProfile]
                if not profileDef then return end
                local defaultOpts = {}
                if profileDef.multiKey then
                    defaultOpts[profileDef.multiKey] = profileDef.defaultMulti or 0
                end
                if profileDef.resKey then
                    defaultOpts[profileDef.resKey] = profileDef.defaultRes or 0
                end
                local ctx = BuildProfileContext(strat, defaultOpts)
                local outputDef = variant.outputs and variant.outputs[outputIdx]
                if not outputDef then return end
                local sa = variant.defaultStartingAmount or strat.defaultStartingAmount or 1
                local cr = variant.defaultCrafts or strat.defaultCrafts or sa
                assertNear(outputDef.workbookExpectedQty or 0, expectedQty, label .. " workbookExpectedQty")
                local qty = ComputeOutputQuantity(outputDef, strat, ctx.profileDef, ctx.statDenom, ctx.statMCp, ctx.statMCm_tot, sa, cr)
                assertNear(qty, expectedQty, "Parity " .. label)
            end

            local engineeringRecyclingIDs = {
                "engineering__recycling_argentleaf_pigment__midnight_1",
                "engineering__recycling_bright_linen_bolt__midnight_1",
                "engineering__recycling_codified_azeroot__midnight_1",
                "engineering__recycling_imbued_bright_linen_bolt__midnight_1",
                "engineering__recycling_powder_pigment__midnight_1",
            }
            for _, stratID in ipairs(engineeringRecyclingIDs) do
                local strat = GAM.Importer.GetStratByID(stratID)
                if strat then
                    assertNear(strat.defaultStartingAmount or 0, 5000, stratID .. " defaultStartingAmount")
                    assertNear(strat.defaultCrafts or 0, 1000, stratID .. " defaultCrafts")
                    assertNear((strat.outputs and strat.outputs[1] and strat.outputs[1].baseYieldPerCraft) or 0, 2.776595,
                        stratID .. " baseYieldPerCraft")
                    assertNear((strat.reagents and strat.reagents[1] and strat.reagents[1].qtyPerCraft) or 0, 5.0,
                        stratID .. " reagent qtyPerCraft")
                    assertNear((strat.reagents and strat.reagents[1] and strat.reagents[1].qtyPerStart) or 0, 1.0,
                        stratID .. " reagent qtyPerStart")
                end
                checkWorkbookParity(stratID, 1, 3292.144942, stratID .. " Engineering recycling")
            end

            local refulgent = GAM.Importer.GetStratByID("blacksmithing__refulgent_copper_ingot__midnight_1")
            if refulgent then
                assertNear(refulgent.defaultStartingAmount or 0, 5000.0, "Refulgent Copper Ingot defaultStartingAmount")
                assertNear(refulgent.defaultCrafts or 0, 1000.0, "Refulgent Copper Ingot defaultCrafts")
                assertNear((refulgent.rankVariants and refulgent.rankVariants.lowest
                    and refulgent.rankVariants.lowest.defaultStartingAmount) or 0,
                    5000.0, "Refulgent Copper Ingot lowest defaultStartingAmount")
                assertNear((refulgent.rankVariants and refulgent.rankVariants.lowest
                    and refulgent.rankVariants.lowest.defaultCrafts) or 0,
                    1000.0, "Refulgent Copper Ingot lowest defaultCrafts")
                assertNear((refulgent.rankVariants and refulgent.rankVariants.highest
                    and refulgent.rankVariants.highest.defaultStartingAmount) or 0,
                    5000.0, "Refulgent Copper Ingot highest defaultStartingAmount")
                assertNear((refulgent.rankVariants and refulgent.rankVariants.highest
                    and refulgent.rankVariants.highest.defaultCrafts) or 0,
                    1000.0, "Refulgent Copper Ingot highest defaultCrafts")
            end
            checkVariantWorkbookParity("blacksmithing__refulgent_copper_ingot__midnight_1", "lowest", 1, 1548.892891,
                "Blacksmithing Refulgent Copper Ingot Q1")
            checkVariantWorkbookParity("blacksmithing__refulgent_copper_ingot__midnight_1", "highest", 1, 1548.892891,
                "Blacksmithing Refulgent Copper Ingot Q2")

            local gloaming = GAM.Importer.GetStratByID("blacksmithing__gloaming_alloy__midnight_1")
            if gloaming then
                assertNear((gloaming.defaultStartingAmount or 0), 600.0, "Gloaming Alloy defaultStartingAmount")
                assertNear((gloaming.defaultCrafts or 0), 100.0, "Gloaming Alloy defaultCrafts")
                assertNear((gloaming.rankVariants and gloaming.rankVariants.lowest
                    and gloaming.rankVariants.lowest.defaultStartingAmount) or 0,
                    600.0, "Gloaming Alloy lowest defaultStartingAmount")
                assertNear((gloaming.rankVariants and gloaming.rankVariants.lowest
                    and gloaming.rankVariants.lowest.defaultCrafts) or 0,
                    100.0, "Gloaming Alloy lowest defaultCrafts")
                assertNear((gloaming.rankVariants and gloaming.rankVariants.highest
                    and gloaming.rankVariants.highest.defaultStartingAmount) or 0,
                    600.0, "Gloaming Alloy highest defaultStartingAmount")
                assertNear((gloaming.rankVariants and gloaming.rankVariants.highest
                    and gloaming.rankVariants.highest.defaultCrafts) or 0,
                    100.0, "Gloaming Alloy highest defaultCrafts")
            end
            checkVariantWorkbookParity("blacksmithing__gloaming_alloy__midnight_1", "lowest", 1, 154.8892891,
                "Blacksmithing Gloaming Alloy Q1")
            checkVariantWorkbookParity("blacksmithing__gloaming_alloy__midnight_1", "highest", 1, 154.8892891,
                "Blacksmithing Gloaming Alloy Q2")

            local sterling = GAM.Importer.GetStratByID("blacksmithing__sterling_alloy__midnight_1")
            if sterling then
                assertNear((sterling.defaultStartingAmount or 0), 6000.0, "Sterling Alloy defaultStartingAmount")
                assertNear((sterling.defaultCrafts or 0), 1000.0, "Sterling Alloy defaultCrafts")
                assertNear((sterling.rankVariants and sterling.rankVariants.lowest
                    and sterling.rankVariants.lowest.defaultStartingAmount) or 0,
                    6000.0, "Sterling Alloy lowest defaultStartingAmount")
                assertNear((sterling.rankVariants and sterling.rankVariants.lowest
                    and sterling.rankVariants.lowest.defaultCrafts) or 0,
                    1000.0, "Sterling Alloy lowest defaultCrafts")
                assertNear((sterling.rankVariants and sterling.rankVariants.highest
                    and sterling.rankVariants.highest.defaultStartingAmount) or 0,
                    1590.0, "Sterling Alloy highest defaultStartingAmount")
                assertNear((sterling.rankVariants and sterling.rankVariants.highest
                    and sterling.rankVariants.highest.defaultCrafts) or 0,
                    265.0, "Sterling Alloy highest defaultCrafts")
            end
            checkVariantWorkbookParity("blacksmithing__sterling_alloy__midnight_1", "lowest", 1, 1548.892891,
                "Blacksmithing Sterling Alloy Q1")
            checkVariantWorkbookParity("blacksmithing__sterling_alloy__midnight_1", "highest", 1, 410.456616,
                "Blacksmithing Sterling Alloy Q2")

            local dawn = GAM.Importer.GetStratByID("enchanting__dawn_shatter_q2__midnight_1")
            if dawn then
                assertNear((dawn.outputs and dawn.outputs[1] and dawn.outputs[1].workbookExpectedQty) or 0, 3086.673801,
                    "dawn_shatter_q2 top-level workbookExpectedQty")
                assertNear((dawn.rankVariants and dawn.rankVariants.lowest and dawn.rankVariants.lowest.outputs
                    and dawn.rankVariants.lowest.outputs[1] and dawn.rankVariants.lowest.outputs[1].workbookExpectedQty) or 0,
                    3086.673801, "dawn_shatter_q2 lowest workbookExpectedQty")
            end
            checkVariantWorkbookParity("enchanting__dawn_shatter_q2__midnight_1", "highest", 1, 2262.531896,
                "Dawn Shatter highest output 1")
            checkVariantWorkbookParity("enchanting__dawn_shatter_q2__midnight_1", "highest", 2, 824.141905,
                "Dawn Shatter highest output 2")

            local radiant = GAM.Importer.GetStratByID("enchanting__radiant_shatter_q2__midnight_1")
            if radiant then
                assertNear((radiant.outputs and radiant.outputs[1] and radiant.outputs[1].workbookExpectedQty) or 0, 3086.673801,
                    "radiant_shatter_q2 top-level workbookExpectedQty")
                assertNear((radiant.rankVariants and radiant.rankVariants.lowest and radiant.rankVariants.lowest.outputs
                    and radiant.rankVariants.lowest.outputs[1] and radiant.rankVariants.lowest.outputs[1].workbookExpectedQty) or 0,
                    3086.673801, "radiant_shatter_q2 lowest workbookExpectedQty")
            end
            checkVariantWorkbookParity("enchanting__radiant_shatter_q2__midnight_1", "highest", 1, 2262.531896,
                "Radiant Shatter highest output 1")
            checkVariantWorkbookParity("enchanting__radiant_shatter_q2__midnight_1", "highest", 2, 824.141905,
                "Radiant Shatter highest output 2")

            local crushing = GAM.Importer.GetStratByID("jewelcrafting__crushing__midnight_1")
            if crushing then
                assertNear(crushing.defaultStartingAmount or 0, 426.0, "jc_crush defaultStartingAmount")
                assertNear(crushing.defaultCrafts or 0, 142.0, "jc_crush defaultCrafts")
                assertNear((crushing.outputs and crushing.outputs[1] and crushing.outputs[1].baseYieldPerCraft) or 0, 2.09,
                    "jc_crush baseYieldPerCraft")
                assertNear((crushing.reagents and crushing.reagents[1] and crushing.reagents[1].qtyPerCraft) or 0, 3.0,
                    "jc_crush cheapest gem qtyPerCraft")
            end
            checkWorkbookParity("jewelcrafting__crushing__midnight_1", 1, 348.5378743,
                "Jewelcrafting crushing G23")

            local lens = GAM.Importer.GetStratByID("jewelcrafting__sin_dorei_lens_crafting__midnight_1")
            if lens and Pricing.CalculateStratMetricsV2 then
                local originalGetOptions = GAM.GetOptions
                local originalGetPatchDB = GAM.GetPatchDB
                local originalCraftingStats = GAM.CraftingStats
                local fixedCraftOpts = {
                    v2PricingMode = "fixed_crafts",
                    rankPolicy = "lowest",
                    pigmentCostSource = "ah",
                    ingotCostSource = "ah",
                    boltCostSource = "ah",
                    jcCraftMulti = 7.9,
                    jcCraftRes = 28.8,
                    jcMcNode = 65,
                    jcRsNode = 50,
                }
                GAM.GetOptions = function()
                    return fixedCraftOpts
                end
                GAM.GetPatchDB = function()
                    return {
                        rankGroups = {},
                        priceOverrides = {},
                        inputQtyOverrides = {},
                        craftsOverrides = {},
                    }
                end
                -- This is an options-baseline formula check. Live recipe
                -- snapshots are tested separately and must not replace the
                -- fixture's explicit Multicraft/Resourcefulness values.
                GAM.CraftingStats = nil
                local ok, metrics = pcall(Pricing.CalculateStratMetricsV2, lens, GAM.C.DEFAULT_PATCH, 0.1)
                GAM.GetOptions = originalGetOptions
                GAM.GetPatchDB = originalGetPatchDB
                GAM.CraftingStats = originalCraftingStats
                assert(ok, metrics)
                local qty = metrics and metrics.output and metrics.output.expectedQtyRaw
                assert(qty and qty > 115 and qty < 119,
                    string.format("Lens fixed-crafts output should be about 117 for 100 crafts, got %.6f",
                        qty or 0))
            end

            local jcRefulgent = GAM.Importer.GetStratByID("jewelcrafting__refulgent_copper_ore_prospecting__midnight_1")
            if jcRefulgent then
                assertNear(jcRefulgent.defaultStartingAmount or 0, 2000.0,
                    "jc prospect refulgent defaultStartingAmount")
                assertNear(jcRefulgent.defaultCrafts or 0, 400.0,
                    "jc prospect refulgent defaultCrafts")
                assertNear((jcRefulgent.outputs and jcRefulgent.outputs[1] and jcRefulgent.outputs[1].baseYieldPerCraft) or 0,
                    0.106449, "jc prospect refulgent baseYieldPerCraft")
                assertNear((jcRefulgent.reagents and jcRefulgent.reagents[1] and jcRefulgent.reagents[1].qtyPerStart) or 0,
                    1.0, "jc prospect refulgent qtyPerStart")
            end
            checkWorkbookParity("jewelcrafting__refulgent_copper_ore_prospecting__midnight_1", 1, 50.005435,
                "Jewelcrafting refulgent output 1")
            checkWorkbookParity("jewelcrafting__refulgent_copper_ore_prospecting__midnight_1", 5, 10.870747,
                "Jewelcrafting refulgent diamond")
            checkWorkbookParity("jewelcrafting__refulgent_copper_ore_prospecting__midnight_1", 6, 434.829873,
                "Jewelcrafting refulgent stone")
            checkWorkbookParity("jewelcrafting__refulgent_copper_ore_prospecting__midnight_1", 7, 304.380911,
                "Jewelcrafting refulgent glass")

            local jcBrilliant = GAM.Importer.GetStratByID("jewelcrafting__brilliant_silver_ore_prospecting__midnight_1")
            if jcBrilliant then
                assertNear(jcBrilliant.defaultStartingAmount or 0, 15000.0,
                    "jc prospect brilliant defaultStartingAmount")
                assertNear(jcBrilliant.defaultCrafts or 0, 3000.0,
                    "jc prospect brilliant defaultCrafts")
                assertNear((jcBrilliant.outputs and jcBrilliant.outputs[1] and jcBrilliant.outputs[1].baseYieldPerCraft) or 0,
                    0.157359, "jc prospect brilliant baseYieldPerCraft")
                assertNear((jcBrilliant.reagents and jcBrilliant.reagents[1] and jcBrilliant.reagents[1].qtyPerStart) or 0,
                    1.0, "jc prospect brilliant qtyPerStart")
            end
            checkWorkbookParity("jewelcrafting__brilliant_silver_ore_prospecting__midnight_1", 1, 554.408088,
                "Jewelcrafting brilliant output 1")
            checkWorkbookParity("jewelcrafting__brilliant_silver_ore_prospecting__midnight_1", 3, 512.012175,
                "Jewelcrafting brilliant flawless output")
            checkWorkbookParity("jewelcrafting__brilliant_silver_ore_prospecting__midnight_1", 5, 140.232634,
                "Jewelcrafting brilliant diamond")
            checkWorkbookParity("jewelcrafting__brilliant_silver_ore_prospecting__midnight_1", 6, 3098.162844,
                "Jewelcrafting brilliant stone")
            checkWorkbookParity("jewelcrafting__brilliant_silver_ore_prospecting__midnight_1", 7, 2485.052723,
                "Jewelcrafting brilliant glass")

            local jcUmbral = GAM.Importer.GetStratByID("jewelcrafting__umbral_tin_ore_prospecting__midnight_1")
            if jcUmbral then
                assertNear(jcUmbral.defaultStartingAmount or 0, 15000.0,
                    "jc prospect umbral defaultStartingAmount")
                assertNear(jcUmbral.defaultCrafts or 0, 3000.0,
                    "jc prospect umbral defaultCrafts")
                assertNear((jcUmbral.outputs and jcUmbral.outputs[1] and jcUmbral.outputs[1].baseYieldPerCraft) or 0,
                    0.157359, "jc prospect umbral baseYieldPerCraft")
                assertNear((jcUmbral.reagents and jcUmbral.reagents[1] and jcUmbral.reagents[1].qtyPerStart) or 0,
                    1.0, "jc prospect umbral qtyPerStart")
            end
            checkWorkbookParity("jewelcrafting__umbral_tin_ore_prospecting__midnight_1", 1, 554.408088,
                "Jewelcrafting umbral output 1")
            checkWorkbookParity("jewelcrafting__umbral_tin_ore_prospecting__midnight_1", 3, 512.012175,
                "Jewelcrafting umbral flawless output")
            checkWorkbookParity("jewelcrafting__umbral_tin_ore_prospecting__midnight_1", 5, 140.232634,
                "Jewelcrafting umbral diamond")
            checkWorkbookParity("jewelcrafting__umbral_tin_ore_prospecting__midnight_1", 6, 3098.162844,
                "Jewelcrafting umbral stone")
            checkWorkbookParity("jewelcrafting__umbral_tin_ore_prospecting__midnight_1", 7, 2485.052723,
                "Jewelcrafting umbral glass")

            checkWorkbookParity("jewelcrafting__sin_dorei_lens_crafting__midnight_1", 1, 1823.987082,
                "Jewelcrafting lens crafting")
            local jcSunglass = GAM.Importer.GetStratByID("jewelcrafting__sunglass_vial_crafting__midnight_1")
            if jcSunglass then
                assertNear((jcSunglass.reagents and jcSunglass.reagents[1] and jcSunglass.reagents[1].qtyPerCraft) or 0, 5.0,
                    "Jewelcrafting sunglass glass qtyPerCraft")
                assertNear((jcSunglass.reagents and jcSunglass.reagents[2] and jcSunglass.reagents[2].qtyPerCraft) or 0, 1.0,
                    "Jewelcrafting sunglass stone qtyPerCraft")
                assertNear((jcSunglass.reagents and jcSunglass.reagents[2] and jcSunglass.reagents[2].qtyPerStart) or 0, 0.2,
                    "Jewelcrafting sunglass stone qtyPerStart")
            end
            checkWorkbookParity("jewelcrafting__sunglass_vial_crafting__midnight_1", 1, 455.9967705,
                "Jewelcrafting sunglass vial crafting")
            local amani = GAM.Importer.GetStratByID("alchemy__amani_extract__midnight_1")
            if amani then
                assertNear(amani.defaultStartingAmount or 0, 5000.0, "Amani Extract defaultStartingAmount")
                assertNear(amani.defaultCrafts or 0, 1000.0, "Amani Extract defaultCrafts")
                assertNear((amani.reagents and amani.reagents[1] and amani.reagents[1].qtyPerCraft) or 0, 5.0,
                    "Amani Extract sunglass vial qtyPerCraft")
            end
            checkWorkbookParity("alchemy__amani_extract__midnight_1", 1, 7591.623037,
                "Alchemy Amani Extract C57")
            checkWorkbookParity("inscription__codified_azeroot__midnight_1", 1, 10706.565200,
                "Inscription codified azeroot O31")

            local jcCrushProfile = profiles["jc_crush"]
            assert(jcCrushProfile, "jc_crush profile missing")
            assertNear(jcCrushProfile.defaultRes or 0, 33.0, "jc_crush defaultRes")
            assertNear(jcCrushProfile.defaultRsNode or 0, 50.0, "jc_crush defaultRsNode")
            assertNear(jcCrushProfile.sheetRs or 0, 0.45, "jc_crush sheetRs")
            assertNear(codifiedProfile.sheetRs or 0, 0.495, "insc_codified sheetRs")

            -- Engineering!C56 craft parity
            checkWorkbookParity("engineering__soul_sprocket__midnight_1", 1, 1950.595878,
                "Engineering craft C56")
            -- Engineering!O37 craft parity (500-craft baseline)
            checkWorkbookParity("engineering__emergency_soul_link__midnight_1", 1, 975.297939,
                "Engineering craft O37")
        end
    end)
    return ok, err
end
