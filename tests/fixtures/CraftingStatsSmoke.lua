-- Test-only fixture extracted from CraftingStats.lua.
function Stats.RunSmokeChecks()
    local originalDB = GAM.db
    local originalSavedDB = GoldAdvisorMidnightDB
    local originalOpen = testOpenSnapshot
    local originalProfessionNodes = testOpenProfessionNodes
    local originalPlayerProfessionSet = testPlayerProfessionSet
    local originalProfessionsFrame = ProfessionsFrame
    local originalCProfSpecs = C_ProfSpecs
    local originalCTraits = C_Traits
    local originalCTradeSkillUI = C_TradeSkillUI
    local originalCTimer = C_Timer
    local ok, err = pcall(function()
        GAM.db = {
            options = {},
            v2StatCache = {
                version = Cache.VERSION,
                characters = {},
            },
        }
        GoldAdvisorMidnightDB = GAM.db
        testPlayerProfessionSet = { Alchemy = true, Inscription = true }
        testOpenProfessionNodes = {
            [999001] = {
                rank = 1,
                maxRank = 1,
                name = "Test Specialization Node",
                nameSource = "blizzard",
            },
        }

        local openedSkillLine
        local openedRecipe
        C_TradeSkillUI = {
            OpenTradeSkill = function(skillLineID)
                openedSkillLine = skillLineID
            end,
            OpenRecipe = function(recipeID)
                openedRecipe = recipeID
            end,
        }
        C_Timer = nil
        testOpenSnapshot = {
            source = "native-open",
            recipeID = 1289744,
            recipeName = "Concentrated Silvermoon Health Potion",
            profession = "Alchemy",
            profileKey = "alchemy",
            multiPercent = 20,
            resPercent = 10,
            supportsMulticraft = true,
            supportsResourcefulness = true,
        }
        local refreshedRecipe
        local opened, openReason = Stats.OpenRecipeForStrat({
            profession = "Alchemy",
            formulaProfile = "alchemy",
            recipeID = 1289744,
        }, function(recipeID)
            refreshedRecipe = recipeID
        end)
        assert(opened and openReason == nil
                and openedSkillLine == 171
                and openedRecipe == 1289744
                and refreshedRecipe == 1289744,
            "selected recipe open/refresh failed")

        -- OpenRecipe has no success return. A non-throwing call must not capture
        -- or refresh while Blizzard is still displaying a different recipe.
        testOpenSnapshot = {
            source = "native-open",
            recipeID = 1230049,
            recipeName = "Thalassian Missive of Ingenuity",
            profession = "Inscription",
            profileKey = "insc_ink",
            resPercent = 10,
            supportsResourcefulness = true,
        }
        refreshedRecipe = nil
        local mismatchOpened, mismatchReason = Stats.OpenRecipeForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1230048,
        }, function(recipeID)
            refreshedRecipe = recipeID
        end)
        assert(not mismatchOpened
                and mismatchReason == "open-recipe-mismatch:1230049"
                and refreshedRecipe == nil,
            "mismatched visible recipe was treated as a successful refresh")

        local retries = {}
        local refreshCount = 0
        C_Timer = {
            After = function(delay, callback)
                retries[#retries + 1] = { delay = delay, callback = callback }
            end,
        }
        local retryOpened, retryReason = Stats.OpenRecipeForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1230048,
        }, function(recipeID)
            refreshedRecipe = recipeID
            refreshCount = refreshCount + 1
        end)
        assert(retryOpened and retryReason == nil and #retries == 3
                and refreshedRecipe == nil,
            "recipe mismatch retries were not scheduled")
        testOpenSnapshot.recipeID = 1230048
        testOpenSnapshot.recipeName = "Thalassian Missive of Resourcefulness"
        retries[1].callback()
        retries[2].callback()
        retries[3].callback()
        assert(refreshedRecipe == 1230048 and refreshCount == 1,
            "verified recipe retry did not refresh exactly once")

        -- A newer recipe selection supersedes every delayed retry from the
        -- previous selection, even if callbacks are executed out of order.
        retries = {}
        local callbackRefreshes = {}
        local callbackOpens = {}
        C_TradeSkillUI.OpenRecipe = function(recipeID)
            callbackOpens[#callbackOpens + 1] = recipeID
        end
        testOpenSnapshot.recipeID = 1269575
        testOpenSnapshot.recipeName = "Milling"
        assert(Stats.OpenRecipeForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1230048,
        }, function(recipeID)
            callbackRefreshes[#callbackRefreshes + 1] = recipeID
        end))
        assert(Stats.OpenRecipeForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1230049,
        }, function(recipeID)
            callbackRefreshes[#callbackRefreshes + 1] = recipeID
        end))
        assert(#retries == 6, "competing recipe requests did not queue bounded retries")
        callbackOpens = {}
        testOpenSnapshot.recipeID = 1230048
        testOpenSnapshot.recipeName = "Thalassian Missive of Resourcefulness"
        retries[1].callback()
        assert(#callbackOpens == 0 and #callbackRefreshes == 0,
            "superseded recipe callback reopened or refreshed the old selection")
        testOpenSnapshot.recipeID = 1230049
        testOpenSnapshot.recipeName = "Thalassian Missive of Ingenuity"
        retries[4].callback()
        assert(#callbackOpens == 0
                and #callbackRefreshes == 1 and callbackRefreshes[1] == 1230049,
            "timer must capture the latest recipe without protected selection")
        retries[2].callback()
        retries[3].callback()
        assert(#callbackOpens == 0 and #callbackRefreshes == 1,
            "late superseded callbacks changed recipe state")

        C_TradeSkillUI.OpenRecipe = function(recipeID)
            openedRecipe = recipeID
        end

        -- Multiple hardware clicks while Blizzard is still switching recipes
        -- must share one bounded refresh attempt. On the final retry, the
        -- complete profession recipe list gives a precise unavailable reason.
        testOpenSnapshot.recipeID = 1269575
        testOpenSnapshot.recipeName = "Milling"
        C_TradeSkillUI.GetAllRecipeIDs = function()
            return { 1269575 }
        end
        retries = {}
        local unavailableReason
        local unavailableOpened = Stats.OpenRecipeForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1303144,
        }, nil, function(reason)
            unavailableReason = reason
        end)
        local duplicateOpened, duplicateReason = Stats.OpenRecipeForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1303144,
        })
        assert(unavailableOpened and duplicateOpened
                and duplicateReason == "open-pending"
                and #retries == 3,
            "duplicate recipe refresh queued another retry set")
        retries[1].callback()
        retries[2].callback()
        retries[3].callback()
        assert(unavailableReason == "recipe-not-in-current-profession",
            "missing profession recipe did not return its precise failure reason")
        C_TradeSkillUI.GetAllRecipeIDs = nil
        C_Timer = nil
        testOpenSnapshot = nil
        testOpenProfessionNodes = nil
        local characterAfterOpenTests = Cache.Ensure()
        characterAfterOpenTests.nodeState = nil

        local cooking = Stats.GetProfile("cooking")
        assert(cooking and cooking.profileKey == "cooking",
            "Cooking profile is missing from the shared profession registry")

        local jcRefine = Stats.GetProfile("jc_refine")
        assert(jcRefine
                and jcRefine.supportsResourcefulness
                and not jcRefine.supportsMulticraft
                and jcRefine.multiPercent == 0,
            "Jewelcrafting refinement profile must be Resourcefulness-only")
        assert(InferProfileKey("Refine Crystalline Glass", "Jewelcrafting", false) == "jc_refine"
                and InferProfileKey("Refine Duskshrouded Stone", "Jewelcrafting", false) == "jc_refine",
            "Jewelcrafting refinement recipe capture must use the refinement profile")

        local strat = {
            profession = "Inscription",
            formulaProfile = "insc_ink",
            statProfileKey = "insc_ink",
            recipeID = 1001,
        }
        local base = Stats.ResolveForStrat(strat, {})
        assert(base and base.statSource == "workbook-default", "default profile stat source failed")

        testOpenSnapshot = {
            source = "native-open",
            recipeID = 1001,
            recipeName = "Munsell Ink",
            profession = "Inscription",
            profileKey = "insc_ink",
            multiPercent = 35,
            resPercent = 10,
            supportsMulticraft = true,
            supportsResourcefulness = true,
        }
        local mcPreset, mcPresetErr = Stats.CaptureOpenRecipeAsGearPreset("multicraft")
        assert(mcPreset and not mcPresetErr, "Multicraft gear preset capture failed")
        testOpenSnapshot.multiPercent = 15
        testOpenSnapshot.resPercent = 40
        local resPreset, resPresetErr = Stats.CaptureOpenRecipeAsGearPreset("resourcefulness")
        assert(resPreset and not resPresetErr, "Resourcefulness gear preset capture failed")
        testOpenSnapshot = nil

        local gearAvailable = Stats.GetAvailableGearPresetModes(strat)
        assert(gearAvailable.multicraft and gearAvailable.resourcefulness,
            "exact recipe gear preset availability failed")
        local forcedMC = Stats.ResolveForStrat(strat, { _gamGearModeOverride = "multicraft" })
        local forcedRes = Stats.ResolveForStrat(strat, { _gamGearModeOverride = "resourcefulness" })
        assert(forcedMC.statSource == "gear-preset-multicraft"
                and forcedMC.multiPercent == 35
                and forcedMC.resPercent == 10,
            "Multicraft gear preset resolution failed")
        assert(forcedRes.statSource == "gear-preset-resourcefulness"
                and forcedRes.multiPercent == 15
                and forcedRes.resPercent == 40,
            "Resourcefulness gear preset resolution failed")

        local manualOK = Stats.SetManualProfile("insc_milling", {
            resPercent = 31,
            resExtra = 0.55,
            supportsResourcefulness = true,
        })
        assert(manualOK, "manual profile save failed")
        local manual = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
        }, {})
        assert(manual.statSource == "manual" and manual.resPercent == 31,
            "manual profile resolve failed")

        assert(Stats.SaveSnapshot({
            source = "craftsim-imported",
            recipeID = 1001,
            recipeName = "Munsell Ink",
            profession = "Inscription",
            profileKey = "insc_ink",
            resPercent = 12.5,
            resExtra = 0.35,
            supportsResourcefulness = true,
        }))
        local imported = Stats.ResolveForStrat(strat, {})
        assert(imported.statSource == "craftsim-imported" and imported.resPercent == 12.5,
            "imported recipe snapshot resolve failed")

        local sameProfileDifferentRecipe = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            statProfileKey = "insc_ink",
            recipeID = 1006,
        }, {})
        assert(sameProfileDifferentRecipe.statSource == "workbook-default"
                and sameProfileDifferentRecipe.resPercent ~= 12.5,
            "recipe snapshot leaked into another strategy in the same profile")

        GAM.db.v2StatCache.characters["AltCrafter-TestRealm"] = {
            uid = "AltCrafter-TestRealm",
            name = "AltCrafter",
            realm = "TestRealm",
            recipes = {
                ["1006"] = {
                    source = "native-open",
                    recipeID = 1006,
                    recipeName = "Cross-Character Ink",
                    profession = "Inscription",
                    profileKey = "insc_ink",
                    resPercent = 44,
                    supportsMulticraft = true,
                    supportsResourcefulness = true,
                    capturedAt = GetCurrentTimestamp(),
                },
            },
            recipeValidatedAt = { ["1006"] = GetCurrentTimestamp() },
            profiles = {},
            manualProfiles = {},
            nodeState = {},
        }
        local cachedCrafter = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1006,
        }, {})
        assert(cachedCrafter.crossCharacter
                and cachedCrafter.crafterUID == "AltCrafter-TestRealm"
                and cachedCrafter.crafterName == "AltCrafter"
                and cachedCrafter.resPercent == 44
                and cachedCrafter.fallbackReason == "cached-crafter",
            "exact cross-character crafter cache resolution failed")
        local cachedStatus = Stats.GetRecipeCacheStatus({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1006,
        })
        assert(cachedStatus.hasCachedCrafter
                and cachedStatus.cachedCrafterUID == "AltCrafter-TestRealm",
            "cross-character recipe cache status failed")

        assert(Stats.SetManualProfile("insc_ink", {
            resExtra = 0.9,
            supportsResourcefulness = true,
        }))
        assert(Stats.SaveSnapshot({
            source = "craftsim-imported",
            recipeID = 1004,
            recipeName = "Manual-Filled Ink",
            profession = "Inscription",
            profileKey = "insc_ink",
            resPercent = 10,
            supportsResourcefulness = true,
        }))
        local manualFilled = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_ink",
            recipeID = 1004,
        }, {})
        assert(manualFilled.statSource == "craftsim-imported"
                and manualFilled.resPercent == 10
                and math.abs((manualFilled.resExtra or 0) - 0.9) < 0.0001,
            "manual profile values should fill missing imported snapshot extras")

        testOpenSnapshot = {
            source = "native-open",
            recipeID = 1002,
            recipeName = "Some Milling",
            profession = "Inscription",
            profileKey = "insc_milling",
            resPercent = 55,
            resExtra = 0.55,
            supportsResourcefulness = true,
        }
        local native = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
            recipeID = 1002,
        }, {})
        assert(native.statSource == "native-open" and native.resPercent == 55,
            "native open snapshot resolve failed")

        testOpenSnapshot = nil
        local craftSimUpgradeOK, craftSimUpgradeStatus = Stats.SaveSnapshot({
            source = "craftsim-imported",
            recipeID = 1002,
            recipeName = "Some Milling",
            profession = "Inscription",
            profileKey = "insc_milling",
            resPercent = 5,
            resExtra = 0.55,
            supportsResourcefulness = true,
            nodeHash = "111:2",
            totalStats = {
                resourcefulness = { percent = 5, extra = 0.55 },
            },
            nodeStats = {
                resourcefulness = { percent = 3, extra = 0.55 },
            },
        })
        assert(craftSimUpgradeOK and craftSimUpgradeStatus == nil,
            "exact CraftSim recipe should upgrade an incomplete native snapshot")
        testOpenSnapshot = {
            source = "native-open",
            recipeID = 1002,
            recipeName = "Some Milling",
            profession = "Inscription",
            profileKey = "insc_milling",
            resPercent = 55,
            resExtra = 0.55,
            supportsResourcefulness = true,
        }
        local upgraded = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
            recipeID = 1002,
        }, {})
        assert(upgraded.statSource == "craftsim+native-open"
                and upgraded.resPercent == 55
                and math.abs((upgraded.resExtra or 0) - 0.55) < 0.0001
                and not upgraded.nodeHash,
            "CraftSim recipe should merge visible stats without owning node extras")

        local nativeDowngradeOK, nativeDowngradeStatus = Stats.SaveSnapshot({
            source = "native-open",
            recipeID = 1002,
            recipeName = "Some Milling",
            profession = "Inscription",
            profileKey = "insc_milling",
            resPercent = 55,
            resExtra = 0.55,
            supportsResourcefulness = true,
        })
        assert(nativeDowngradeOK and nativeDowngradeStatus == "preserved-existing",
            "native refresh should preserve an exact CraftSim recipe snapshot")
        testOpenSnapshot = nil
        local afterNativeDowngrade = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
            recipeID = 1002,
        }, {})
        assert(afterNativeDowngrade.statSource == "craftsim-imported"
                and afterNativeDowngrade.resPercent == 5
                and math.abs((afterNativeDowngrade.resExtra or 0) - 0.55) < 0.0001
                and not afterNativeDowngrade.nodeHash,
            "native refresh downgraded an exact CraftSim recipe snapshot")

        -- The explicit Refresh Recipe path must retain CraftSim's richer
        -- snapshot while persisting the newly visible Blizzard stats. Once a
        -- different strategy is selected, the open form can no longer supply
        -- a live overlay, so the recipe cache itself must carry these values.
        testOpenSnapshot = {
            source = "native-open",
            recipeID = 1002,
            recipeName = "Some Milling",
            profession = "Inscription",
            profileKey = "insc_milling",
            resPercent = 55,
            supportsResourcefulness = true,
        }
        local refreshedSnapshot, refreshSnapshotErr = Stats.CaptureOpenRecipe(1002)
        assert(refreshedSnapshot and refreshSnapshotErr == nil,
            "explicit recipe refresh failed")
        testOpenSnapshot = nil
        local rememberedRefresh = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
            recipeID = 1002,
        }, {})
        assert(rememberedRefresh.statSource == "craftsim-imported"
                and rememberedRefresh.resPercent == 55
                and math.abs((rememberedRefresh.resExtra or 0) - 0.55) < 0.0001,
            "explicit recipe refresh did not persist visible stats across selection changes")

        assert(Stats.SaveSnapshot({
            source = "craftsim-imported",
            recipeID = 1005,
            recipeName = "CraftSim Only Milling",
            profession = "Inscription",
            profileKey = "insc_milling",
            resPercent = 5,
            resExtra = 0.55,
            supportsResourcefulness = true,
            nodeHash = "111:2",
            nodeStats = {
                resourcefulness = { percent = 3, extra = 0.55 },
            },
        }))
        local craftSimOnly = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
            recipeID = 1005,
        }, {})
        assert(craftSimOnly.statSource == "craftsim-imported"
                and craftSimOnly.resPercent == 5
                and math.abs((craftSimOnly.resExtra or 0) - 0.55) < 0.0001
                and not craftSimOnly.nodeHash,
            "CraftSim import leaked hidden node state")

        local audit = Stats.GetAudit("insc")
        assert(type(audit) == "table" and type(audit.ready) == "table"
                and type(audit.manual) == "table"
                and type(audit.needsCapture) == "table",
            "stat profile audit shape failed")

        testOpenSnapshot = {
            source = "native-open",
            recipeID = 1003,
            recipeName = "Munsell Ink",
            profession = "Inscription",
            profileKey = "insc_ink",
            resPercent = 90,
            supportsResourcefulness = true,
        }
        local mismatch = Stats.ResolveForStrat({
            profession = "Inscription",
            formulaProfile = "insc_milling",
        }, {})
        assert(mismatch.statSource ~= "native-open" and mismatch.profileKey == "insc_milling",
            "open profile mismatch leaked into another profile")

        -- 12.1 native capture uses the selected expansion skill line and the
        -- public profession-trait APIs; it must not depend on frame internals
        -- or CraftSim's cached specialization model.
        ProfessionsFrame = {
            professionInfo = {
                professionID = 999202,
                parentProfessionID = 202,
                professionName = "Midnight Engineering",
            },
        }
        C_ProfSpecs = {
            GetConfigIDForSkillLine = function(skillLineID)
                return skillLineID == 999202 and 7001 or 0
            end,
            GetDefaultSpecSkillLine = function() return 999202 end,
            GetSpecTabIDsForSkillLine = function(skillLineID)
                return skillLineID == 999202 and { 8001 } or {}
            end,
            GetRootPathForTab = function() return 106720 end,
            GetChildrenForPath = function() return {} end,
            GetSpendEntryForPath = function(nodeID) return nodeID + 1000 end,
            GetDescriptionForPath = function(nodeID)
                return "Live description " .. tostring(nodeID)
            end,
        }
        C_Traits = {
            GetTreeNodes = function(treeID)
                return treeID == 8001 and { 106720, 106727 } or {}
            end,
            GetNodeInfo = function(configID, nodeID)
                assert(configID == 7001, "native node capture used wrong config")
                return {
                    ID = nodeID,
                    currentRank = 1,
                    ranksPurchased = 0,
                    maxRanks = 1,
                }
            end,
            GetEntryInfo = function(configID, entryID)
                assert(configID == 7001, "node name lookup used wrong config")
                return { definitionID = entryID + 1000 }
            end,
            GetDefinitionInfo = function(definitionID)
                return { overrideName = "Live Engineering Path " .. tostring(definitionID - 2000) }
            end,
        }
        local nodeCaptureNotifications = 0
        local notifiedProfession
        local removeNodeCaptureListener = Stats.AddProfessionNodeCaptureListener(function(profession)
            nodeCaptureNotifications = nodeCaptureNotifications + 1
            notifiedProfession = profession
        end)
        local apiCapture = Stats.CaptureOpenProfessionNodes()
        assert(apiCapture
                and apiCapture.meta
                and apiCapture.meta.captureMethod == "traits-api"
                and apiCapture.nodes[106720].rank == 1
                and apiCapture.nodes[106727].rank == 1
                and apiCapture.nodes[106720].name == "Live Engineering Path 106720"
                and apiCapture.nodes[106720].description == "Live description 106720"
                and apiCapture.nodes[106720].nameSource == "blizzard"
                and nodeCaptureNotifications == 1
                and notifiedProfession == "Engineering",
            "12.1 profession trait API capture failed")
        local liveRows = Stats.GetProfessionNodeRows("Engineering")
        local liveSettingsNode = nil
        for _, group in ipairs(liveRows.groups or {}) do
            for _, row in ipairs(group.rows or {}) do
                if row.nodeID == 106720 then liveSettingsNode = row end
            end
        end
        assert(liveSettingsNode
                and liveSettingsNode.name == "Live Engineering Path 106720"
                and liveSettingsNode.nameSource == "blizzard",
            "captured in-game profession node names did not reach settings rows")
        local revisionAfterAPICapture = Stats.GetRevision()
        assert(Stats.CaptureOpenProfessionNodes(), "repeat native node capture failed")
        assert(Stats.GetRevision() == revisionAfterAPICapture
                and nodeCaptureNotifications == 1,
            "unchanged profession frame refresh invalidated pricing revision")
        C_Traits.GetDefinitionInfo = function(definitionID)
            return { overrideName = "Renamed Engineering Path " .. tostring(definitionID - 2000) }
        end
        assert(Stats.CaptureOpenProfessionNodes(), "renamed native node capture failed")
        assert(Stats.GetRevision() == revisionAfterAPICapture
                and nodeCaptureNotifications == 2,
            "same-rank Blizzard node-name update did not notify UI without repricing")
        removeNodeCaptureListener()
        ProfessionsFrame = originalProfessionsFrame
        C_ProfSpecs = originalCProfSpecs
        C_Traits = originalCTraits

        local nodeCapture = Stats.CaptureProfessionNodes("Engineering", {
            [106726] = 1,
            [106724] = 1,
            [106722] = 1,
            [106720] = 1,
            [106733] = 1,
            [106731] = 1,
            [106729] = 1,
            [106727] = 1,
        }, "gam-native-nodes")
        assert(nodeCapture and nodeCapture.nodeHash, "engineering node capture failed")
        local engineering = Stats.ResolveForStrat({
            profession = "Engineering",
            formulaProfile = "engineering_craft",
        }, {})
        assert(engineering.statSource == "gam-native-nodes"
                and math.abs((engineering.resExtra or 0) - 0.45) < 0.0001
                and math.abs((engineering.multiExtra or 0) - 1.0) < 0.0001,
            "engineering captured node extras failed")

        assert(Stats.SetManualNodeRank("Engineering", 106727, 0),
            "engineering manual node rank failed")
        local manualNodes = Stats.ResolveForStrat({
            profession = "Engineering",
            formulaProfile = "engineering_craft",
        }, {})
        assert(manualNodes.statSource == "gam-manual-nodes"
                and math.abs((manualNodes.multiExtra or 0) - 0.75) < 0.0001,
            "engineering manual node override failed")

        assert(Stats.ResetProfessionNodesToDefaults("Engineering"),
            "engineering reset node defaults failed")
        local defaultNodes = Stats.ResolveForStrat({
            profession = "Engineering",
            formulaProfile = "engineering_craft",
        }, {})
        assert(defaultNodes.statSource == "gam-manual-nodes"
                and math.abs((defaultNodes.multiExtra or 0) - 1.0) < 0.0001
                and math.abs((defaultNodes.resExtra or 0) - 0.45) < 0.0001,
            "engineering default node ranks failed")

        local rows = Stats.GetProfessionNodeRows("Engineering")
        local displayedNodeCount = 0
        local displayedRatingNode = false
        for _, group in ipairs((rows and rows.groups) or {}) do
            for _, row in ipairs(group.rows or {}) do
                displayedNodeCount = displayedNodeCount + 1
                local catalogNode = Specialization.GetCatalogNode(
                    Specialization.GetCatalog("Engineering"), row.nodeID)
                if not Specialization.IsPricingModifierNode(catalogNode) then
                    displayedRatingNode = true
                end
            end
        end
        assert(rows and rows.pricingNodeCount == 8
                and rows.capturedNodeCount == 8
                and displayedNodeCount > rows.pricingNodeCount
                and displayedRatingNode,
            "engineering node settings rows did not include rating-only catalog nodes")
        local blacksmithRows = Stats.GetProfessionNodeRows("Blacksmithing")
        local blacksmithDisplayedNodeCount = 0
        for _, group in ipairs((blacksmithRows and blacksmithRows.groups) or {}) do
            blacksmithDisplayedNodeCount = blacksmithDisplayedNodeCount + #(group.rows or {})
        end
        assert(blacksmithRows and blacksmithRows.pricingNodeCount == 0
                and #blacksmithRows.groups == 3
                and blacksmithDisplayedNodeCount == 18,
            "rating-only blacksmithing nodes were missing from settings rows")

        assert(Stats.ResetProfessionNodesToDefaults("Alchemy"),
            "alchemy reset node defaults failed")
        local alchemyCauldron = Stats.ResolveForStrat({
            profession = "Alchemy",
            formulaProfile = "alchemy",
            recipeID = 1230857,
        }, {})
        assert(alchemyCauldron.statSource == "gam-manual-nodes"
                and math.abs((alchemyCauldron.multiExtra or 0) - 0.4) < 0.0001,
            "alchemy recipe-scoped node extras failed")
        local alchemyUnscoped = Stats.ResolveForStrat({
            profession = "Alchemy",
            formulaProfile = "alchemy",
        }, {})
        assert(math.abs((alchemyUnscoped.multiExtra or 0) - 0.2) < 0.0001,
            "alchemy unscoped profile default failed")

        assert(Stats.ResetProfessionNodesToDefaults("Tailoring"),
            "tailoring reset node defaults failed")
        local tailoring = Stats.ResolveForStrat({
            profession = "Tailoring",
            formulaProfile = "tailoring",
            recipeID = 1227926,
        }, {})
        assert(tailoring.statSource == "gam-manual-nodes"
                and math.abs((tailoring.multiExtra or 0) - 0.4) < 0.0001
                and math.abs((tailoring.resExtra or 0) - 0.5) < 0.0001,
            "tailoring node defaults failed")

        assert(Stats.ResetProfessionNodesToDefaults("Blacksmithing"),
            "blacksmithing reset node defaults failed")
        local blacksmithing = Stats.ResolveForStrat({
            profession = "Blacksmithing",
            formulaProfile = "blacksmithing",
            recipeID = 1229427,
        }, {})
        assert(blacksmithing.statSource == "gam-manual-nodes"
                and math.abs((blacksmithing.multiExtra or 0) - 0.12) < 0.0001,
            "blacksmithing rating-only defaults should preserve workbook node multiplier")

        local jcOpts = {
            jcCraftMulti = 30,
            jcCraftRes = 20,
            jcMcNode = 50,
            jcRsNode = 50,
        }
        local jcDefault = Stats.ResolveForStrat({
            profession = "Jewelcrafting",
            formulaProfile = "jc_craft",
            recipeID = 1230476,
        }, jcOpts)
        assert(jcDefault and math.abs((jcDefault.multiExtra or 0) - 0.50) < 0.0001,
            "JC Sunglass Vial workbook hidden MC default failed")

        local jcNodes = Stats.CaptureProfessionNodes("Jewelcrafting", {
            [106991] = 1,
            [106995] = 1,
            [106998] = 1,
            [107000] = 1,
        }, "gam-native-nodes")
        assert(jcNodes and jcNodes.nodeHash, "JC node capture failed")
        local jcCaptured = Stats.ResolveForStrat({
            profession = "Jewelcrafting",
            formulaProfile = "jc_craft",
            recipeID = 1230476,
        }, jcOpts)
        assert(jcCaptured.statSource == "gam-native-nodes"
                and math.abs((jcCaptured.multiExtra or 0) - 0.25) < 0.0001
                and math.abs((jcCaptured.resExtra or 0) - 0.35) < 0.0001,
            "JC recipe-scoped captured hidden nodes failed")
        assert(jcCaptured.nodeBonusDetails
                and jcCaptured.nodeBonusDetails.status == "resolved"
                and jcCaptured.nodeBonusDetails.multicraft
                and #jcCaptured.nodeBonusDetails.multicraft.nodes == 2
                and jcCaptured.nodeBonusDetails.multicraft.nodes[1].nodeID == 106991
                and jcCaptured.nodeBonusDetails.multicraft.nodes[2].nodeID == 106995
                and math.abs((jcCaptured.nodeBonusDetails.multicraft.extra or 0) - 0.25) < 0.0001
                and jcCaptured.nodeBonusDetails.resourcefulness
                and #jcCaptured.nodeBonusDetails.resourcefulness.nodes == 2
                and math.abs((jcCaptured.nodeBonusDetails.resourcefulness.extra or 0) - 0.35) < 0.0001,
            "JC applied-node diagnostic failed")

        assert(Stats.SaveSnapshot({
            source = "native-open",
            recipeID = 1230475,
            recipeName = "Sin'dorei Lens",
            profession = "Jewelcrafting",
            profileKey = "jc_craft",
            multiPercent = 30,
            multiExtra = 0.25,
            supportsMulticraft = true,
            resPercent = 20,
            resExtra = 0.35,
            supportsResourcefulness = true,
            nodeHash = "106991:1|106995:1",
        }))
        local jcUnscoped = Stats.ResolveForStrat({
            profession = "Jewelcrafting",
            formulaProfile = "jc_craft",
        }, jcOpts)
        assert(jcUnscoped.statSource == "gam-cache-profile"
                and jcUnscoped.fallbackReason == "profile-visible-stats-only"
                and math.abs((jcUnscoped.multiPercent or 0) - 30) < 0.0001
                and math.abs((jcUnscoped.multiExtra or 0) - 0.50) < 0.0001
                and not jcUnscoped.nodeHash,
            "JC unscoped profile snapshot leaked hidden node extras")

        assert(Stats.SaveSnapshot({
            source = "craftsim-imported",
            recipeID = 1230476,
            recipeName = "Sunglass Vial",
            profession = "Jewelcrafting",
            profileKey = "jc_craft",
            multiPercent = 30,
            multiExtra = 0.50,
            supportsMulticraft = true,
            resPercent = 20,
            resExtra = 0.50,
            supportsResourcefulness = true,
            nodeHash = "current-craftsim-layout",
        }))
        testOpenSnapshot = {
            source = "native-open",
            recipeID = 1230476,
            recipeName = "Sunglass Vial",
            profession = "Jewelcrafting",
            profileKey = "jc_craft",
            multiPercent = 31,
            resPercent = 21,
            supportsMulticraft = true,
            supportsResourcefulness = true,
        }
        local jcExactMerged = Stats.ResolveForStrat({
            profession = "Jewelcrafting",
            formulaProfile = "jc_craft",
            recipeID = 1230476,
        }, jcOpts)
        assert(jcExactMerged.statSource == "craftsim+native-open"
                and math.abs((jcExactMerged.multiPercent or 0) - 31) < 0.0001
                and math.abs((jcExactMerged.resPercent or 0) - 21) < 0.0001
                and math.abs((jcExactMerged.multiExtra or 0) - 0.25) < 0.0001
                and math.abs((jcExactMerged.resExtra or 0) - 0.35) < 0.0001
                and jcExactMerged.nodeHash,
            "CraftSim snapshot overrode GAM-owned learned node extras")
    end)
    testOpenSnapshot = originalOpen
    testOpenProfessionNodes = originalProfessionNodes
    testPlayerProfessionSet = originalPlayerProfessionSet
    ProfessionsFrame = originalProfessionsFrame
    C_ProfSpecs = originalCProfSpecs
    C_Traits = originalCTraits
    C_TradeSkillUI = originalCTradeSkillUI
    C_Timer = originalCTimer
    GAM.db = originalDB
    GoldAdvisorMidnightDB = originalSavedDB
    return ok, err
end
