-- GoldAdvisorMidnight/Diagnostics.lua
-- Read-only troubleshooting reports written to the debug log. The Debug Log
-- window offers each one as a button; nothing here changes saved data.
-- Module: GAM.Diagnostics

local ADDON_NAME, GAM = ...
local Diagnostics = {}
GAM.Diagnostics = Diagnostics

-- ===== Item ID dump =====
-- Iterates every itemID in all loaded strats, resolves names via
-- GetItemInfo, and logs a Lua-table block to the debug log.
-- Items not yet in the client cache show "???" — visit their crafting
-- window or AH first so WoW loads them.
local function DumpItemIDs()
    if not (GAM.Importer and GAM.Importer.GetAllStrats) then
        GAM.Log.Warn("DumpItemIDs: Importer not ready")
        return
    end

    -- Collect: expectedName → { [itemID]=true, ... }
    local nameMap = {}
    local function addID(name, id)
        if type(id) == "number" and id > 0 then
            nameMap[name] = nameMap[name] or {}
            nameMap[name][id] = true
        end
    end

    for _, strat in ipairs(GAM.Importer.GetAllStrats()) do
        local out = strat.output
        if out and out.name then
            for _, id in ipairs(out.itemIDs or {}) do addID(out.name, id) end
        end
        -- outputs[]: multi-output strats (JC prospecting, etc.)
        -- Skip IDs already in strat.output to avoid internal Q1/Q2 label duplicates
        local mainIDs = {}
        for _, id in ipairs((out and out.itemIDs) or {}) do mainIDs[id] = true end
        for _, o2 in ipairs(strat.outputs or {}) do
            if o2.name then
                for _, id in ipairs(o2.itemIDs or {}) do
                    if not mainIDs[id] then addID(o2.name, id) end
                end
            end
        end
        for _, r in ipairs(strat.reagents or {}) do
            if r.name then
                for _, id in ipairs(r.itemIDs or {}) do addID(r.name, id) end
            end
        end
    end

    -- Sort names alphabetically
    local names = {}
    for name in pairs(nameMap) do names[#names+1] = name end
    table.sort(names)

    GAM.Log.Info("=== GAM Item ID Dump ===")
    GAM.Log.Info("-- Copy to a reference file; ??? = not in client cache yet")

    local totalIDs, mismatches, uncached = 0, 0, 0

    local function NormalizeDumpName(name)
        if type(name) ~= "string" then return "" end
        local normalized = name:lower()
        normalized = normalized:gsub("[‘’´`]", "'")
        normalized = normalized:gsub("%s*%([qr]%d+%)", "")
        normalized = normalized:gsub("%s+", " ")
        return normalized
    end

    for _, expectedName in ipairs(names) do
        local ids = {}
        for id in pairs(nameMap[expectedName]) do ids[#ids+1] = id end
        table.sort(ids)

        local idParts   = {}
        local nameParts = {}
        local anyBad    = false

        for _, id in ipairs(ids) do
            totalIDs = totalIDs + 1
            local actual = GetItemInfo(id)
            idParts[#idParts+1] = tostring(id)
            if actual == nil then
                nameParts[#nameParts+1] = "???"
                uncached = uncached + 1
                anyBad = true
            elseif NormalizeDumpName(actual) ~= NormalizeDumpName(expectedName) then
                nameParts[#nameParts+1] = "MISMATCH:" .. actual
                mismatches = mismatches + 1
                anyBad = true
            else
                nameParts[#nameParts+1] = "\"" .. actual .. "\""
            end
        end

        local flag = anyBad and "  -- !! CHECK !!" or ""
        GAM.Log.Info('  ["%s"] = {%s},  -- %s%s',
            expectedName,
            table.concat(idParts, ", "),
            table.concat(nameParts, ", "),
            flag)
    end

    GAM.Log.Info("=== Done: %d names, %d IDs | %d mismatches | %d uncached ===",
        #names, totalIDs, mismatches, uncached)
end

-- ===== ARP Export =====
-- Produces a CSV-style block matching the AverageReagentPrice addon export format.
-- Format: ItemName, Rank 1, X.XX, Rank 2, X.XX, Rank 3, X.XX
-- Price = copper / 10000, exported to 4 decimal places so the sheet receives
-- exact copper precision and can reproduce addon Profit/ROI without rounding drift.
-- No AH cut applied.
local function GenerateARPExport()
    if not (GAM.Importer and GAM.Importer.GetAllStrats) then
        return "-- Importer not ready"
    end

    local patchTag = GAM.C.DEFAULT_PATCH

    -- Collect unique items by name → itemIDs array, including rank-variant-only IDs.
    local nameToIDs = {}
    local nameOrder = {}
    local nameToIDSet = {}

    local function addItem(name, itemIDs)
        if type(name) ~= "string" or name == "" then return end
        if not itemIDs or #itemIDs == 0 then return end
        if not nameToIDs[name] then
            nameToIDs[name] = {}
            nameToIDSet[name] = {}
            nameOrder[#nameOrder + 1] = name
        end
        for _, id in ipairs(itemIDs) do
            if id and not nameToIDSet[name][id] then
                nameToIDSet[name][id] = true
                nameToIDs[name][#nameToIDs[name] + 1] = id
            end
        end
    end

    for _, strat in ipairs(GAM.Importer.GetAllStrats()) do
        local active = (GAM.Pricing and GAM.Pricing.GetActiveRecipeView and GAM.Pricing.GetActiveRecipeView(strat)) or strat
        local out = active.output
        if out and out.name and out.itemIDs then addItem(out.name, out.itemIDs) end
        for _, o2 in ipairs(active.outputs or {}) do
            if o2.name and o2.itemIDs then addItem(o2.name, o2.itemIDs) end
        end
        for _, r in ipairs(active.reagents or {}) do
            if r.name and r.itemIDs then addItem(r.name, r.itemIDs) end
        end
        for _, variant in pairs(strat.rankVariants or {}) do
            local vOut = variant.output
            if vOut and vOut.name and vOut.itemIDs then addItem(vOut.name, vOut.itemIDs) end
            for _, o2 in ipairs(variant.outputs or {}) do
                if o2.name and o2.itemIDs then addItem(o2.name, o2.itemIDs) end
            end
            for _, r in ipairs(variant.reagents or {}) do
                if r.name and r.itemIDs then addItem(r.name, r.itemIDs) end
            end
        end
    end

    table.sort(nameOrder)

    local lines = {}
    for _, name in ipairs(nameOrder) do
        local ids = nameToIDs[name]
        -- Build quality-tier → itemID map using WoW API.
        -- GetItemReagentQualityByItemInfo: nil = uncached OR non-tiered; 0 = non-tiered; 1/2/3 = tiered.
        -- When nil, use GetItemInfo to distinguish: name returned = item is loaded (non-tiered → Rank 1);
        -- nil returned = truly uncached → skip the whole item.
        local rankMap = {}
        local skip = false
        for _, id in ipairs(ids) do
            local q = C_TradeSkillUI.GetItemReagentQualityByItemInfo(id)
            if q == nil then
                if GetItemInfo(id) ~= nil then
                    -- Item loaded but not a tiered reagent → Rank 1
                    rankMap[1] = id
                else
                    -- Truly uncached → skip whole item
                    skip = true
                    break
                end
            elseif q > 0 then
                -- If the item name already encodes the quality tier (e.g. "Eversinging Dust Q2",
                -- "Radiant Shard Q1"), the rank column is redundant — put at Rank 1 so VLOOKUP
                -- with column 3 always finds it. Items without a Q-suffix (e.g. "Oil of Dawn")
                -- keep quality-based placement so Q2-mode VLOOKUP (column 5) works correctly.
                rankMap[name:match(" Q%d$") and 1 or q] = id
            else
                -- q == 0: non-tiered item → Rank 1
                rankMap[1] = id
            end
        end
        if not skip then
            local parts = { name }
            for rankIdx = 1, 3 do
                local itemID = rankMap[rankIdx]
                local price = itemID and GAM.Pricing.GetEffectivePrice(itemID, patchTag)
                parts[#parts + 1] = "Rank " .. rankIdx
                parts[#parts + 1] = (price and price > 0) and string.format("%.4f", price / 10000) or "0.0000"
            end
            lines[#lines + 1] = table.concat(parts, ", ")
        end
    end

    return #lines > 0 and table.concat(lines, "\n") or "-- No items found"
end


local function GetQualityTag(itemID)
    if not itemID or itemID == 0 then return nil end
    local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    local q = api and api(itemID) or nil
    if q and q > 0 then
        return "Q" .. tostring(q)
    end
    return nil
end

local function FormatPriceSafe(copper)
    if copper == nil then
        return "n/a"
    end
    if GAM.Pricing and GAM.Pricing.FormatPrice then
        return GAM.Pricing.FormatPrice(copper)
    end
    return tostring(copper)
end

local function FormatNumberSafe(value, decimals)
    local number = tonumber(value)
    if number == nil then return "-" end
    return string.format("%." .. tostring(decimals or 3) .. "f", number)
end

local function FormatPercentSafe(value)
    local number = tonumber(value)
    if number == nil then return "-" end
    return string.format("%.2f%%", number * 100)
end

local function GetCurrentDetailContext()
    local mw = GAM.UI and GAM.UI.MainWindow
    if not (mw and mw.GetCurrentDetailContext) then
        return nil, nil, nil
    end
    return mw.GetCurrentDetailContext()
end

local function DumpSelectedStrategyScans()
    local strat, patchTag, metrics = GetCurrentDetailContext()
    if not strat then
        GAM.Log.Warn("DumpSelectedStrategyScans: no selected strategy in the main window")
        return
    end

    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    metrics = metrics or (GAM.PricingFacade
        and GAM.PricingFacade.CalculateCurrent
        and GAM.PricingFacade.CalculateCurrent(strat, patchTag))
    if not metrics then
        GAM.Log.Warn("DumpSelectedStrategyScans: metrics unavailable for '%s'", tostring(strat.stratName or strat.id or "?"))
        return
    end

    local opts = (GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {}
    local fillQty = GAM.C.MARKET_SAMPLE_UNITS or 50
    local rankPolicy = opts.rankPolicy or "lowest"
    local output = (metrics.outputs and metrics.outputs[1]) or metrics.output or {}
    local outputQtyRaw = tonumber(output.expectedQtyRaw) or 0
    local outputQtyRounded = tonumber(output.expectedQty) or math.max(1, math.floor(outputQtyRaw + 0.5))
    -- Output revenue uses the current lowest sell listing. Fill quantity still
    -- applies to reagent acquisition and is logged separately below.
    local pricingQty = 1

    local outputAllIDs = {}
    local seenOutputIDs = {}
    local displayed = GAM.Pricing and GAM.Pricing.GetDisplayedItemSet
        and GAM.Pricing.GetDisplayedItemSet(strat, patchTag, metrics)
        or nil
    for _, id in ipairs((displayed and displayed.output and displayed.output.itemIDs) or {}) do
        if id and not seenOutputIDs[id] then
            seenOutputIDs[id] = true
            outputAllIDs[#outputAllIDs + 1] = id
        end
    end
    if output.itemID and not seenOutputIDs[output.itemID] then
        outputAllIDs[#outputAllIDs + 1] = output.itemID
    end

    local function DumpItem(section, name, itemID, qtyHint)
        local qTag = GetQualityTag(itemID)
        local itemLabel = name or ("item:" .. tostring(itemID or 0))
        local storedPrice, storedMinimum, storedStale = nil, nil, false
        if GAM.Pricing and GAM.Pricing.GetUnitPrice then
            storedPrice, storedStale = GAM.Pricing.GetUnitPrice(itemID)
            storedMinimum = GAM.Pricing.GetUnitPrice(itemID, true)
        end
        local raw = GAM.AHScan and GAM.AHScan.GetRawScanSnapshot and GAM.AHScan.GetRawScanSnapshot(itemID) or nil

        GAM.Log.Info("[%s] %s [item:%s%s]",
            section,
            itemLabel,
            tostring(itemID or 0),
            qTag and (" " .. qTag) or "")
        GAM.Log.Info("  qty=%s storedAvg=%s storedMin=%s%s",
            tostring(qtyHint or "-"),
            FormatPriceSafe(storedPrice),
            FormatPriceSafe(storedMinimum),
            storedStale and " (stale)" or "")

        if raw and raw.prices and #raw.prices > 0 then
            local hintQty = math.max(1, math.floor((qtyHint or 1) + 0.5))
            local avgHint, _, _, _, _, depth
            if qtyHint and GAM.AHScan and GAM.AHScan.ComputePriceForQty then
                avgHint, _, _, _, _, depth = GAM.AHScan.ComputePriceForQty(itemID, hintQty)
            end
            local avgFill = GAM.AHScan and GAM.AHScan.ComputePriceForQty
                and GAM.AHScan.ComputePriceForQty(itemID, fillQty)
                or nil
            GAM.Log.Info("  source=%s rows=%d avg@qty=%s avg@sample(%d)=%s",
                tostring(raw.source),
                #raw.prices,
                FormatPriceSafe(avgHint),
                fillQty,
                FormatPriceSafe(avgFill))
            if depth then
                -- Why this price: bait skipped, and units priced at the top
                -- listing because the market does not list them.
                GAM.Log.Info("  bait skipped=%d (below %s) listed=%d of %d%s",
                    depth.baitUnits or 0, FormatPriceSafe(depth.lowerFence),
                    depth.filled or 0, depth.requested or hintQty,
                    depth.incomplete and " (thin market: missing units at highest listed price)" or "")
            end

            local maxRows = 12
            for i, row in ipairs(raw.prices) do
                if i > maxRows then
                    GAM.Log.Info("  ... %d more row(s)", #raw.prices - maxRows)
                    break
                end
                GAM.Log.Info("  row %02d: %s x %d",
                    i,
                    FormatPriceSafe(row.unitPrice),
                    row.quantity or 0)
            end
        else
            local vendorPrice, vendorSource
            if GAM.VendorPrices and GAM.VendorPrices.GetPrice then
                vendorPrice, vendorSource = GAM.VendorPrices.GetPrice(itemID)
            else
                vendorPrice = GAM.C and GAM.C.VENDOR_PRICES and GAM.C.VENDOR_PRICES[itemID] or nil
                vendorSource = vendorPrice and "static" or nil
            end
            if vendorPrice then
                GAM.Log.Info("  source=vendor-%s unit=%s", tostring(vendorSource or "static"), FormatPriceSafe(vendorPrice))
            else
                GAM.Log.Info("  source=no live scan rows cached")
            end
        end
    end

    GAM.Log.Info("=== GAM Scan Dump: %s ===", tostring(strat.stratName or strat.id or "?"))
    GAM.Log.Info("patch=%s rankPolicy=%s crafts=%s expectedRaw=%.3f rounded=%d pricingQty=%d fillQty=%d",
        tostring(patchTag),
        tostring(rankPolicy),
        tostring(metrics.crafts or "?"),
        outputQtyRaw,
        outputQtyRounded,
        pricingQty,
        fillQty)

    local diagnostics = metrics.diagnostics or {}
    local formula = diagnostics.formula or {}
    GAM.Log.Info("economics: mode=%s revenue=%s requiredCost=%s consumedCost=%s saved=%s profit=%s roi=%s breakEven=%s",
        tostring(metrics.pricingMode or formula.pricingMode or "-"),
        FormatPriceSafe(metrics.netRevenue),
        FormatPriceSafe(metrics.requiredCostFull),
        FormatPriceSafe(metrics.expectedConsumedCostFull),
        FormatPriceSafe(metrics.averageSavedCost),
        FormatPriceSafe(metrics.profit),
        FormatNumberSafe(metrics.roi, 2),
        FormatPriceSafe(metrics.breakEvenSell))
    GAM.Log.Info("formula: profile=%s stats=%s nodeHash=%s baseYield=%s mc=%s mcExtra=%s mcConst=%s res=%s resExtra=%s saveFraction=%s crafts=%s effectiveCrafts=%s actualYield=%s budgetYield=%s expectedOutput=%s",
        tostring(formula.profileKey or strat.formulaProfile or "-"),
        tostring(formula.statSource or "options"),
        tostring(formula.nodeHash or "-"),
        FormatNumberSafe(formula.baseYield, 6),
        FormatPercentSafe(formula.mcPercent),
        FormatPercentSafe(formula.mcExtra),
        FormatNumberSafe(formula.mcConstant, 3),
        FormatPercentSafe(formula.resPercent),
        FormatPercentSafe(formula.resExtra),
        FormatPercentSafe(formula.resourceSaveFraction),
        FormatNumberSafe(formula.crafts, 3),
        FormatNumberSafe(formula.effectiveCrafts, 3),
        FormatNumberSafe(formula.expectedYieldPerActualCraft, 6),
        FormatNumberSafe(formula.expectedYieldPerCraft, 6),
        FormatNumberSafe(formula.expectedOutput, 3))

    if diagnostics.statUsages and #diagnostics.statUsages > 1 then
        GAM.Log.Info("stat graph:")
        for _, usage in ipairs(diagnostics.statUsages) do
            GAM.Log.Info("  %s profile=%s stats=%s nodeHash=%s strat=%s yieldPerCraft=%s",
                tostring(usage.role or "-"),
                tostring(usage.profileKey or "-"),
                tostring(usage.statSource or "options"),
                tostring(usage.nodeHash or "-"),
                tostring(usage.stratName or usage.stratID or "-"),
                FormatNumberSafe(usage.expectedYieldPerCraft, 6))
        end
    end

    if #outputAllIDs == 0 and output.itemID then
        outputAllIDs[1] = output.itemID
    end
    for _, itemID in ipairs(outputAllIDs) do
        DumpItem(itemID == output.itemID and "output" or "output-alt", output.name, itemID, pricingQty)
    end
    for _, row in ipairs(metrics.shoppingReagents or metrics.reagents or {}) do
        DumpItem("input", row.name, row.itemID, row.required)
    end
    local queueSnapshot = GAM.AHScan and GAM.AHScan.GetQueueSnapshot and GAM.AHScan.GetQueueSnapshot() or {}
    if #queueSnapshot > 0 then
        GAM.Log.Info("[queued scan items]")
        for i, entry in ipairs(queueSnapshot) do
            if i > 30 then
                GAM.Log.Info("  ... %d more queued item(s)", #queueSnapshot - 30)
                break
            end
            GAM.Log.Info("  %s item:%s name=%s reason=%s strategies=%s",
                entry.isNameScan and "name" or "price",
                tostring(entry.itemID or 0),
                tostring(entry.name or "-"),
                table.concat(entry.reasons or {}, ", "),
                table.concat(entry.strategyKeys or {}, ", "))
        end
    end
    GAM.Log.Info("=== End Scan Dump ===")
end


-- ===== Auction House scan diagnostics =====
-- Per-item outcomes of the most recent scan: how long each query took, how
-- many attempts it needed, and the event trail for anything that failed.
-- Complete or legitimately empty; anything else also prints its event trail.
local SCAN_OK_OUTCOMES = {
    commodity = true, item = true, confirmed_empty = true,
    name_discovery = true, browse_discovery = true,
}

local function DumpScanDiagnostics()
    local diagnostics = GAM.AHScan and GAM.AHScan.GetDiagnostics and GAM.AHScan.GetDiagnostics() or {}
    GAM.Log.Info("=== GAM Scan Diagnostics ===")
    if #diagnostics == 0 then
        GAM.Log.Info("No scan results recorded this session. Scan at the Auction House, then run this again.")
    end
    local outcomes = {}
    for _, diagnostic in ipairs(diagnostics) do
        local outcome = tostring(diagnostic.outcome or "unknown")
        outcomes[outcome] = (outcomes[outcome] or 0) + 1
        local failed = not SCAN_OK_OUTCOMES[outcome]
        GAM.Log.Info("  %s item:%s %s attempts=%s more=%s time=%.1fs",
            outcome, tostring(diagnostic.itemID or "-"), tostring(diagnostic.name or "-"),
            tostring(diagnostic.queryAttempts or 0), tostring(diagnostic.moreRequests or 0),
            tonumber(diagnostic.duration) or 0)
        if failed then
            for _, event in ipairs(diagnostic.events or {}) do
                GAM.Log.Info("      %.1f %s %s", tonumber(event.at) or 0,
                    tostring(event.event), tostring(event.detail or ""))
            end
        end
    end
    local parts = {}
    for outcome, n in pairs(outcomes) do parts[#parts + 1] = outcome .. "=" .. n end
    table.sort(parts)
    GAM.Log.Info("=== Done: %d items | %s ===", #diagnostics, table.concat(parts, " "))
end

-- ===== Saved profession gear sets =====
local function DumpGearSets()
    local Cache = GAM.CraftingStatsCache
    local character = Cache and Cache.Ensure and Cache.Ensure()
    GAM.Log.Info("=== GAM Gear Sets ===")
    local professions = {}
    for profession in pairs(character and character.professionGear or {}) do
        professions[#professions + 1] = profession
    end
    table.sort(professions)
    if #professions == 0 then
        GAM.Log.Info("No gear sets saved on this character. Use Save MC / Save Res in Profession gear.")
    end
    local now = type(time) == "function" and time() or 0
    for _, profession in ipairs(professions) do
        for _, mode in ipairs({ "multicraft", "resourcefulness" }) do
            local set = character.professionGear[profession][mode]
            if set then
                local stats = set.stats or {}
                local mc, res = stats.multicraft or {}, stats.resourcefulness or {}
                GAM.Log.Info("%s %s: revision=%s saved=%dh ago recipe=%s mc=%s%% res=%s%%%s",
                    profession, mode, tostring(set.revision or 1),
                    math.floor(math.max(0, now - (tonumber(set.capturedAt) or now)) / 3600),
                    tostring(set.recipeID or "-"), tostring(mc.percent or "-"), tostring(res.percent or "-"),
                    type(set.stats) == "table" and "" or " (no stats: save again)")
                for _, slot in ipairs(set.slots or {}) do
                    GAM.Log.Info("    slot %s: %s", tostring(slot.slot), tostring(slot.link or "empty"))
                end
            end
        end
    end
    GAM.Log.Info("=== End Gear Sets ===")
end

-- ===== Support summary =====
-- The facts a bug report needs, in one block that can be copied.
local function DumpSupportSummary()
    local version, build = "?", "?"
    if type(GetBuildInfo) == "function" then version, build = GetBuildInfo() end
    local function Loaded(name)
        local api = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
        return api and api(name) and "yes" or "no"
    end
    local strategies = GAM.Importer and GAM.Importer.GetAllStrats and #GAM.Importer.GetAllStrats() or 0
    GAM.Log.Info("=== GAM Support Summary ===")
    GAM.Log.Info("addon=%s client=%s build=%s locale=%s translations=%s",
        tostring(GAM.C.ADDON_VERSION), tostring(version), tostring(build),
        tostring(GetLocale and GetLocale() or "?"), GAM.C.TRANSLATIONS_ENABLED and "on" or "off")
    GAM.Log.Info("character=%s-%s strategies=%d logLevel=%d",
        tostring(UnitName and UnitName("player") or "?"), tostring(GetRealmName and GetRealmName() or "?"),
        strategies, GAM.Log.GetLevel())
    GAM.Log.Info("TradeSkillMaster=%s CraftSim=%s Auctionator=%s",
        Loaded("TradeSkillMaster"), Loaded("CraftSim"), Loaded("Auctionator"))
    local summary = GAM.Log.GetSummary()
    GAM.Log.Info("log: errors=%d warnings=%d", summary.levels.ERROR or 0, summary.levels.WARN or 0)
    GAM.Log.Info("=== End Support Summary ===")
end

-- ===== Public API =====
-- A report the player asked for is always written, even with the capture
-- level set to Off; the previous level is restored afterwards.
function Diagnostics.Run(fn, ...)
    local previous = GAM.Log.GetLevel()
    if previous < 1 then GAM.Log.SetLevel(1) end
    local ok, err = pcall(fn, ...)
    GAM.Log.SetLevel(previous)
    if not ok then GAM.Log.Error("Diagnostics: %s", tostring(err)) end
    return ok
end

Diagnostics.DumpItemIDs = DumpItemIDs
Diagnostics.DumpSelectedStrategyScans = DumpSelectedStrategyScans
Diagnostics.DumpScanDiagnostics = DumpScanDiagnostics
Diagnostics.DumpGearSets = DumpGearSets
Diagnostics.DumpSupportSummary = DumpSupportSummary
Diagnostics.GenerateARPExport = GenerateARPExport
