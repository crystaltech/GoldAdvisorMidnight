-- GoldAdvisorMidnight/Pricing.lua
-- Pricing engine: price lookup, effective price, strat metrics.
-- Module: GAM.Pricing

local ADDON_NAME, GAM = ...
local Pricing = {}
GAM.Pricing = Pricing
local Derivation = GAM.PricingDerivation or {}

-- ===== Internal helpers =====

local function GetDB()
    return (GAM.GetDB and GAM:GetDB()) or GAM.db
end

local function GetOpts()
    return (GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {}
end
local function GetPatchDB(pt) return GAM:GetPatchDB(pt) end
local function GetFormulaProfiles()
    return (GAM_WORKBOOK_GENERATED and GAM_WORKBOOK_GENERATED.formulaProfiles) or {}
end
local function GetItemLabel(item)
    if not item then return nil end
    return item.name or item.itemRef
end
local function SafeWholeText(n, useCommas)
    if n == nil then return "0" end
    if n == math.huge then return "inf" end
    if n == -math.huge then return "-inf" end
    local whole = math.floor(tonumber(n) or 0)
    local text = tostring(whole)
    if not useCommas then
        return text
    end
    local sign, digits = text:match("^([%-]?)(%d+)$")
    if not digits then
        return text
    end
    return sign .. digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function RequestItemData(itemID)
    if not itemID or itemID == 0 then return end
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    else
        GetItemInfo(itemID)
    end
end

local function GetActiveRecipeView(strat)
    if not strat then return nil end
    local policy = GetOpts().rankPolicy or "lowest"
    if strat.rankVariants and strat.rankVariants[policy] then
        local variant = strat.rankVariants[policy]
        return {
            defaultStartingAmount = variant.defaultStartingAmount or strat.defaultStartingAmount,
            defaultCrafts = variant.defaultCrafts or strat.defaultCrafts or strat.defaultStartingAmount,
            outputs = variant.outputs or strat.outputs,
            output = (variant.outputs and variant.outputs[1]) or variant.output or strat.output,
            reagents = variant.reagents or strat.reagents,
        }
    end
    return {
        defaultStartingAmount = strat.defaultStartingAmount,
        defaultCrafts = strat.defaultCrafts or strat.defaultStartingAmount,
        outputs = strat.outputs,
        output = strat.output or (strat.outputs and strat.outputs[1]),
        reagents = strat.reagents,
    }
end

-- Public helper so non-pricing helpers (scan buttons, exports, CraftSim push)
-- can use the same rank-policy-resolved reagent/output set as pricing.
function Pricing.GetActiveRecipeView(strat)
    return GetActiveRecipeView(strat)
end

-- Shared helper for non-pricing actions that should mirror the currently displayed
-- strategy view. Outputs always come from the active rank-policy recipe view; reagents
-- may come from the expanded metrics list when a caller passes one in.
function Pricing.GetDisplayedItemSet(strat, patchTag, metrics)
    local active = GetActiveRecipeView(strat)
    if not active then return nil end
    local reagentItems = {}
    if metrics and metrics.reagents and #metrics.reagents > 0 then
        for _, r in ipairs(metrics.reagents) do
            reagentItems[#reagentItems + 1] = {
                itemIDs = r.itemID and { r.itemID } or {},
                name = r.name,
            }
        end
    else
        for _, reagent in ipairs(active.reagents or {}) do
            reagentItems[#reagentItems + 1] = {
                itemIDs = reagent.itemIDs or {},
                name = GetItemLabel(reagent),
            }
        end
    end
    local output = active.output and {
        itemIDs = active.output.itemIDs or {},
        name = GetItemLabel(active.output),
    } or nil
    local outputs = {}
    for _, out in ipairs(active.outputs or {}) do
        outputs[#outputs + 1] = {
            itemIDs = out.itemIDs or {},
            name = GetItemLabel(out),
        }
    end
    return {
        output = output,
        outputs = outputs,
        reagents = reagentItems,
    }
end

-- Extra scan targets that are not part of the visible displayed reagent list.
-- Used for flexible reagent groups like `cheapestOf`, where pricing needs every
-- eligible alternative scanned even though only one row is shown in the UI.
function Pricing.GetExtraScanItems(strat, patchTag)
    local active = GetActiveRecipeView(strat)
    if not active then return {} end

    local extras = {}
    for _, reagent in ipairs(active.reagents or {}) do
        if reagent.cheapestOf then
            for _, alt in ipairs(reagent.cheapestOf) do
                local altIDs = alt.itemIDs
                if (not altIDs or #altIDs == 0) and alt.itemRef then
                    local pdb = GetPatchDB(patchTag)
                    altIDs = pdb.rankGroups[alt.itemRef] or {}
                end
                extras[#extras + 1] = {
                    itemIDs = altIDs or {},
                    name = alt.itemRef,
                }
            end
        end
    end
    return extras
end

local function GetStrategyScoreFromMetrics(metrics)
    if not metrics then return nil, nil end
    local p, r, cost = metrics.profit, metrics.roi, metrics.totalCostFull
    if not p or not r then return nil, cost end
    return p * math.sqrt(r), cost
end

function Pricing.GetStrategyScore(metrics)
    return GetStrategyScoreFromMetrics(metrics)
end

local function GetResolvedItemIDs(item, patchTag)
    if not item then return {} end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GetPatchDB(patchTag)
    local ids = item.itemIDs
    local label = GetItemLabel(item)
    if (not ids or #ids == 0) and label then
        ids = pdb.rankGroups[label] or {}
    end
    return ids or {}
end

local function GetItemQualityRank(itemID)
    if not itemID or itemID == 0 then return nil end
    RequestItemData(itemID)
    local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    local q = api and api(itemID) or nil
    if q and q > 0 then return q end
    if q == 0 then return 1 end
    if GetItemInfo(itemID) ~= nil then
        return 1
    end
    return nil
end

local function GetItemName(itemID)
    return select(1, GetItemInfo(itemID))
end

local function FindItemIDByQuality(itemIDs, desiredQuality)
    if not desiredQuality or not itemIDs then return nil end
    for _, id in ipairs(itemIDs) do
        if GetItemQualityRank(id) == desiredQuality then
            return id
        end
    end
    return nil
end

local function GetRankPolicyDesiredQuality(itemIDs, patchTag)
    if not itemIDs or #itemIDs <= 1 then return nil end
    local policy = GetOpts().rankPolicy or "lowest"
    local bestQ = nil
    for _, id in ipairs(itemIDs) do
        local q = GetItemQualityRank(id)
        if q then
            if not bestQ then
                bestQ = q
            elseif policy == "highest" and q > bestQ then
                bestQ = q
            elseif policy ~= "highest" and q < bestQ then
                bestQ = q
            end
        end
    end
    return bestQ
end

-- Dependency container for derivation functions (GetEffectivePrice, PickItemID).
-- Populated lazily by GetDerivationDeps() on first use.
local DERIVATION_DEPS = {}
local ResolveCheapestAlternative

-- Pick best itemID from a list according to rankPolicy.
-- Uses C_TradeSkillUI.GetItemReagentQualityByItemInfo to sort by actual crafting
-- quality rather than array position (array order is not guaranteed to be Q1-first).
local function PickItemID(itemIDs, patchTag)
    if not itemIDs or #itemIDs == 0 then return nil end
    if #itemIDs == 1 then return itemIDs[1] end
    local policy = GetOpts().rankPolicy or "lowest"

    -- Build quality-aware sorted list
    local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    local sorted = {}
    local anyKnown = false
    for _, id in ipairs(itemIDs) do
        local q = api and api(id)
        if q and q > 0 then
            anyKnown = true
            tinsert(sorted, { id = id, q = q })
        elseif q == 0 then
            -- Non-tiered item loaded → treat as rank 1
            anyKnown = true
            tinsert(sorted, { id = id, q = 1 })
        else
            -- Uncached: push to end so known ranks are preferred
            tinsert(sorted, { id = id, q = 999 })
        end
    end

    if anyKnown then
        table.sort(sorted, function(a, b) return a.q < b.q end)
        return (policy == "highest") and sorted[#sorted].id or sorted[1].id
    end

    -- All uncached: fall back to array position
    return (policy == "highest") and itemIDs[#itemIDs] or itemIDs[1]
end

function Pricing.PreloadStratItemData(strat, patchTag)
    if not strat then return end
    local seen = {}
    local active = GetActiveRecipeView(strat)
    local function touch(item)
        for _, id in ipairs(GetResolvedItemIDs(item, patchTag)) do
            if not seen[id] then
                seen[id] = true
                RequestItemData(id)
            end
        end
    end
    touch(active.output)
    for _, o in ipairs(active.outputs or {}) do touch(o) end
    for _, r in ipairs(active.reagents or {}) do touch(r) end
end

local function GetDerivationDeps()
    DERIVATION_DEPS.PickItemID = PickItemID
    DERIVATION_DEPS.GetEffectivePrice = Pricing.GetEffectivePrice
    return DERIVATION_DEPS
end

function Pricing.GetItemDisplayData(itemID, fallbackName)
    if itemID and itemID > 0 then
        RequestItemData(itemID)
        local name, link = GetItemInfo(itemID)
        if link then
            return {
                itemID = itemID,
                displayText = link,
                itemLink = link,
                hasSafeLink = true,
                fallbackName = fallbackName or name or "?",
            }
        end
        return {
            itemID = itemID,
            displayText = fallbackName or name or ("item:" .. tostring(itemID)),
            itemLink = nil,
            hasSafeLink = false,
            fallbackName = fallbackName or name or "?",
        }
    end
    return {
        itemID = itemID,
        displayText = fallbackName or "?",
        itemLink = nil,
        hasSafeLink = false,
        fallbackName = fallbackName or "?",
    }
end

-- Resolve localized item text for Auctionator shopping exports without changing
-- the addon's canonical English item keys used for workbook/catalog lookups.
function Pricing.GetShoppingSearchData(itemID, fallbackName)
    local resolvedName = fallbackName
    local resolvedLink = nil

    if itemID and itemID > 0 then
        RequestItemData(itemID)
        local localizedName, localizedLink = GetItemInfo(itemID)
        resolvedName = localizedName or resolvedName
        resolvedLink = localizedLink
    end

    return {
        itemID = itemID,
        displayName = resolvedName or fallbackName or "?",
        searchName = resolvedName,
        searchString = resolvedLink or resolvedName or fallbackName,
        itemLink = resolvedLink,
    }
end

-- ===== Public API =====

-- GetUnitPrice(itemID) → price in copper, or nil
-- Reads from realm-scoped price cache.
function Pricing.GetUnitPrice(itemID)
    if not itemID then return nil end
    local cache = GAM:GetRealmCache()
    local entry = cache[itemID]
    if not entry then return nil end
    -- Stale check
    local staleThresh = GAM.C.PRICE_STALE_SECONDS
    if (time() - (entry.ts or 0)) > staleThresh then
        return entry.price, true  -- price, isStale
    end
    return entry.price, false
end

-- GetEffectivePrice(itemID, patchTag, qty) → price in copper, or nil
-- Priority: override > vendor price > CraftSim > qty-aware AH fill > AH cache avg
-- qty (optional): when provided, uses ComputePriceForQty for the actual fill
--                 cost at that volume rather than the shallowFillQty cached avg.
function Pricing.GetEffectivePrice(itemID, patchTag, qty)
    if not itemID then return nil end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local opts = GetOpts()

    -- 1. Manual override (use ~= nil so an explicit 0 override is honoured)
    local pdb = GetPatchDB(patchTag)
    if pdb.priceOverrides and pdb.priceOverrides[itemID] ~= nil then
        return pdb.priceOverrides[itemID], false
    end

    -- 2. Vendor price (static — no scan needed)
    if GAM.C.VENDOR_PRICES and GAM.C.VENDOR_PRICES[itemID] then
        return GAM.C.VENDOR_PRICES[itemID], false
    end

    -- 3. CraftSim (if selected as source)
    if opts.priceSource == "craftsim" and GAM.CraftSimBridge then
        local csPrice = GAM.CraftSimBridge.GetPrice(itemID)
        if csPrice and csPrice > 0 then
            return csPrice, false
        end
    end

    -- 3. AH cache — use qty-aware fill when qty is supplied and raw data exists.
    -- Always derive stale status from the cached timestamp (ComputePriceForQty
    -- does not check age, so we get correctness from GetUnitPrice's ts check).
    local cachedPrice, stale = Pricing.GetUnitPrice(itemID)
    if qty and qty > 0 and GAM.AHScan and GAM.AHScan.ComputePriceForQty then
        local qp = GAM.AHScan.ComputePriceForQty(itemID, qty)
        if qp then return qp, stale end
    end
    return cachedPrice, stale
end

-- GetPreferredIngredientPrice(itemIDs, patchTag, qty) → price, isStale
-- Checks mill/craft derivation chains before falling back to AH price.
-- This ensures the full chain works: e.g. inks inside a recipe pick up
-- herb-derived pigment cost, and ingots inside alloy recipes pick up ore cost.
-- The derivation chain itself lives in PricingDerivation.lua.
local function GetPreferredIngredientPrice(itemIDs, patchTag, qty)
    return Derivation.GetPreferredIngredientPrice(itemIDs, patchTag, qty, GetDerivationDeps())
end

-- GetEffectivePriceForItem(item, patchTag, qty) → price, isStale
-- item = { name, itemIDs = {}, ... }
-- qty (optional): actual units to buy; threads through to qty-aware AH fill.
-- Used for REAGENT pricing: selects the rank-policy preferred itemID via
-- PickItemID BEFORE checking mill/craft derivation, so R2 Mats correctly
-- uses R2 ingot/pigment recipes rather than defaulting to the first array entry.
function Pricing.GetEffectivePriceForItem(item, patchTag, qty)
    if not item then return nil, false end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GetPatchDB(patchTag)

    -- Resolve itemIDs: use rankGroups if item.itemIDs is empty
    local ids = item.itemIDs
    local label = GetItemLabel(item)
    if (not ids or #ids == 0) and label then
        ids = pdb.rankGroups[label] or {}
    end
    if not ids or #ids == 0 then return nil, false end

    -- Manual price overrides win over all derivation. Check every ID.
    for _, id in ipairs(ids) do
        if pdb.priceOverrides and pdb.priceOverrides[id] ~= nil then
            return pdb.priceOverrides[id], false
        end
    end

    -- Pick rank-policy ID FIRST so mill/craft derivation honours R1/R2 selection.
    -- (Previously the loop checked ids in array order and could pick R1 even when
    -- R2 Mats was selected because R1's entry appeared first in the array.)
    local picked = PickItemID(ids, patchTag)
    if not picked then return nil, false end

    if GetOpts().pigmentCostSource == "mill" and Derivation.HasMillMapping(picked) then
        local millCost, millStale = Derivation.GetMillDerivedPigmentCost(picked, patchTag, qty, GetDerivationDeps())
        if millCost then return millCost, millStale end
    end
    if Derivation.HasCraftedMapping(picked) then
        local craftCost, craftStale = Derivation.GetCraftDerivedReagentCost(picked, patchTag, qty, GetDerivationDeps())
        if craftCost then return craftCost, craftStale end
    end

    -- AH price: preferred rank first, then remaining variants as fallback
    local price, isStale = Pricing.GetEffectivePrice(picked, patchTag, qty)
    if price then return price, isStale end
    for _, id in ipairs(ids) do
        if id ~= picked then
            local p, s = Pricing.GetEffectivePrice(id, patchTag, qty)
            if p then return p, s end
        end
    end
    return nil, false
end

-- GetOutputPriceForItem(item, patchTag, preferredQuality) → price, isStale
-- Used for OUTPUT pricing. When preferredQuality is provided (1/2/3 crafting
-- quality tier), finds the output itemID with that quality and prices it — used
-- so milling/processing output rank matches the input reagent rank (R1 input →
-- R1 output, R2 input → R2 output). Falls back to cheapest-rank logic when the
-- preferred quality has no matching ID or no price data.
-- A cross-rank trim (RANK_TRIM) excludes extreme outlier ranks before the
-- fallback minimum is chosen.
local RANK_TRIM = 3.0

local function GetDesiredOutputQuality(item, patchTag, preferredQuality)
    if preferredQuality then
        return preferredQuality
    end
    local ids = GetResolvedItemIDs(item, patchTag)
    return GetRankPolicyDesiredQuality(ids, patchTag)
end

local function GetOutputPriceForItem(item, patchTag, preferredQuality, qty)
    if not item then return nil, false end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local ids = GetResolvedItemIDs(item, patchTag)
    if not ids or #ids == 0 then return nil, false end

    local desiredQuality = GetDesiredOutputQuality(item, patchTag, preferredQuality)
    local exactID = FindItemIDByQuality(ids, desiredQuality)
    if exactID then
        local p, s = Pricing.GetEffectivePrice(exactID, patchTag, qty)
        if p then return p, s end
    end

    local policyID = PickItemID(ids, patchTag)
    if policyID then
        local p, s = Pricing.GetEffectivePrice(policyID, patchTag, qty)
        if p then return p, s end
    end

    for _, id in ipairs(ids) do
        if id ~= exactID and id ~= policyID then
            local p, s = Pricing.GetEffectivePrice(id, patchTag, qty)
            if p then return p, s end
        end
    end

    return nil, false
end

local function GetOutputItemIDForDisplay(item, patchTag, preferredQuality)
    if not item then return nil end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local ids = GetResolvedItemIDs(item, patchTag)
    if not ids or #ids == 0 then return nil end
    local desiredQuality = GetDesiredOutputQuality(item, patchTag, preferredQuality)
    local exactID = FindItemIDByQuality(ids, desiredQuality)
    if exactID then
        return exactID
    end
    return PickItemID(ids, patchTag)
end

-- FormatPrice(copper) → "1,234g 56s 78c" string (handles negatives)
function Pricing.FormatPrice(copper)
    if not copper or copper == 0 then return "0g" end
    local neg = copper < 0
    copper = math.floor(math.abs(copper))
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts+1] = "|cffffd700" .. SafeWholeText(g, true) .. "g|r" end
    if s > 0 then parts[#parts+1] = "|cffc0c0c0" .. SafeWholeText(s) .. "s|r" end
    if c > 0 or #parts == 0 then parts[#parts+1] = "|cffae8f0a" .. SafeWholeText(c) .. "c|r" end
    local result = table.concat(parts, " ")
    return neg and ("-" .. result) or result
end

function Pricing.RunSmokeChecks()
    local ok, err = pcall(function()
        local profiles = GetFormulaProfiles()
        assert(type(profiles) == "table", "formula profiles unavailable")

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

        if GAM.Importer and GAM.Importer.GetStratByID then
            local crushing = GAM.Importer.GetStratByID("jewelcrafting__crushing__midnight_1")
            assert(crushing and crushing.reagents and crushing.reagents[1], "crushing strat unavailable")
            assert(type(crushing.reagents[1].cheapestOf) == "table" and #crushing.reagents[1].cheapestOf > 0,
                "normalized cheapestOf pool unavailable")
        end

        local score = Pricing.GetStrategyScore({ profit = 2500, roi = 9, totalCostFull = 1000 })
        assert(type(score) == "number", "strategy score unavailable")
    end)
    return ok, err
end

-- ===== Stat scaling (Workbook-driven formula profiles) =====

-- ===== Chain expansion for shopping list =====

-- ===== Core calculation =====

local function GetFormulaFactor(strat, profileDef, statDenom, statMCp, statMCm_tot)
    if strat.calcMode == "formula" and profileDef and statDenom then
        return (1 + statMCp * statMCm_tot) / statDenom
    end
    return 1
end

local function ComputeOutputQuantity(outputDef, strat, profileDef, statDenom, statMCp, statMCm_tot, startingAmt, crafts)
    if not outputDef then
        return 0, 0
    end

    local baseYield = outputDef.baseYield
    if baseYield == nil then
        baseYield = outputDef.baseYieldMultiplier
    end
    if baseYield == nil then
        baseYield = outputDef.qtyMultiplier
    end
    if outputDef.baseYieldPerCraft ~= nil then
        baseYield = outputDef.baseYieldPerCraft
    end

    local factor = GetFormulaFactor(strat, profileDef, statDenom, statMCp, statMCm_tot)
    local qtyRaw
    if outputDef.baseYieldPerCraft ~= nil then
        qtyRaw = crafts * (baseYield or 0) * factor
    else
        qtyRaw = startingAmt * (baseYield or 0) * factor
    end

    return qtyRaw, math.floor(qtyRaw + 0.5)
end

local function BuildProfileContext(strat, opts)
    local profileKey = strat.formulaProfile
    local profileDef = profileKey and GetFormulaProfiles()[profileKey] or nil
    local statMCp, statRp, statMCm_tot, statRs_tot, statDenom

    if strat.calcMode == "formula" and profileDef then
        statMCp = profileDef.multiKey and ((opts[profileDef.multiKey] or 0) / 100) or 0
        statRp = profileDef.resKey and ((opts[profileDef.resKey] or 0) / 100) or 0
        statMCm_tot = profileDef.multiKey
            and (GAM.C.BASE_MCM * (1 + ((profileDef.mcNodeKey and (opts[profileDef.mcNodeKey] or 0) or 0) / 100)))
            or 0
        statRs_tot = GAM.C.BASE_RS * (1 + ((profileDef.rsNodeKey and (opts[profileDef.rsNodeKey] or 0) or 0) / 100))
        statDenom = 1 - statRp * statRs_tot
        if statDenom <= 0 then
            statDenom = 1
        end
    end

    return {
        profileDef = profileDef,
        statMCp = statMCp,
        statRp = statRp,
        statMCm_tot = statMCm_tot,
        statRs_tot = statRs_tot,
        statDenom = statDenom,
    }
end

local function ResolveStartingAmountAndCrafts(strat, active, pdb, craftQty)
    local startingAmt = (active.defaultStartingAmount or strat.defaultStartingAmount or 1) * craftQty

    if pdb.inputQtyOverrides and pdb.inputQtyOverrides[strat.id] then
        startingAmt = pdb.inputQtyOverrides[strat.id]
    end

    local defaultCrafts = active.defaultCrafts or strat.defaultCrafts
        or active.defaultStartingAmount or strat.defaultStartingAmount or 1
    if defaultCrafts <= 0 then
        defaultCrafts = 1
    end

    local crafts = defaultCrafts
    local baseStartingAmount = active.defaultStartingAmount or strat.defaultStartingAmount or 0
    if baseStartingAmount > 0 then
        crafts = defaultCrafts * (startingAmt / baseStartingAmount)
    end

    if pdb.craftsOverrides and pdb.craftsOverrides[strat.id] then
        crafts = pdb.craftsOverrides[strat.id]
        local dsa = active.defaultStartingAmount or strat.defaultStartingAmount or 0
        local dc = active.defaultCrafts or strat.defaultCrafts or dsa or 1
        if dsa > 0 and dc > 0 then
            startingAmt = crafts * dsa / dc
        else
            startingAmt = crafts
        end
    end

    return startingAmt, crafts
end

local function BuildCalcContext(strat, active, patchTag, craftQty, opts, pdb, ahCut)
    local profile = BuildProfileContext(strat, opts)
    local startingAmt, crafts = ResolveStartingAmountAndCrafts(strat, active, pdb, craftQty)

    return {
        strat = strat,
        active = active,
        patchTag = patchTag,
        opts = opts,
        pdb = pdb,
        ahCut = ahCut,
        fillQty = opts.shallowFillQty or GAM.C.DEFAULT_FILL_QTY,
        -- chainActive: any mill/craft derivation path enabled; triggers expanded reagent chain pricing
        chainActive = (opts.pigmentCostSource == "mill")
            or (opts.ingotCostSource == "craft")
            or (opts.boltCostSource == "craft"),
        startingAmt = startingAmt,
        crafts = crafts,
        profileDef = profile.profileDef,
        statMCp = profile.statMCp,
        statRp = profile.statRp,
        statMCm_tot = profile.statMCm_tot,
        statRs_tot = profile.statRs_tot,
        statDenom = profile.statDenom,
    }
end

local function GetResolvedReagentItemIDs(reagent, pdb)
    local reagentIDs = reagent.itemIDs
    local label = GetItemLabel(reagent)
    if (not reagentIDs or #reagentIDs == 0) and label then
        reagentIDs = pdb.rankGroups[label] or {}
    end
    return reagentIDs
end

local function GetRequiredReagentAmount(reagent, startingAmt, crafts)
    local qtyPerCraft = reagent.qtyPerCraft
    local requiredRaw
    if qtyPerCraft ~= nil then
        requiredRaw = qtyPerCraft * crafts
    else
        local qtyPerStart = reagent.qtyPerStart or reagent.qtyMultiplier or 0
        requiredRaw = qtyPerStart * startingAmt
    end
    return math.floor(requiredRaw + 0.5)
end

local function AddMergedReagentEntry(mergedMap, mergedOrder, key, itemIDs, qty, name, cheapestOf)
    if mergedMap[key] then
        mergedMap[key].qty = mergedMap[key].qty + qty
        return
    end
    mergedMap[key] = { itemIDs = itemIDs, qty = qty, name = name, cheapestOf = cheapestOf }
    tinsert(mergedOrder, key)
end

local function BuildMergedReagentMap(ctx)
    local mergedMap = {}
    local mergedOrder = {}

    for _, reagent in ipairs(ctx.active.reagents or {}) do
        local required = GetRequiredReagentAmount(reagent, ctx.startingAmt, ctx.crafts)
        local reagentIDs = GetResolvedReagentItemIDs(reagent, ctx.pdb)

        if ctx.chainActive then
            local expanded = Derivation.ExpandReagentThroughChain(reagentIDs, required, ctx.patchTag, GetDerivationDeps())
            for _, exp in ipairs(expanded) do
                local key = exp.itemIDs[1]
                local entryName = GetItemLabel(reagent)
                if exp.itemIDs ~= reagentIDs then
                    local expID = PickItemID(exp.itemIDs, ctx.patchTag)
                    entryName = expID and GetItemName(expID) or tostring(key)
                end
                AddMergedReagentEntry(mergedMap, mergedOrder, key, exp.itemIDs, exp.qty, entryName)
            end
        else
            local reagentName = GetItemLabel(reagent)
            local key = PickItemID(reagentIDs, ctx.patchTag) or (reagentIDs and reagentIDs[1]) or reagentName
            AddMergedReagentEntry(mergedMap, mergedOrder, key, reagentIDs, required, reagentName, reagent.cheapestOf)
        end
    end

    return mergedOrder, mergedMap
end

ResolveCheapestAlternative = function(entry, ctx, required)
    if not (entry and entry.cheapestOf) then
        return nil
    end

    local best = nil
    for _, alt in ipairs(entry.cheapestOf) do
        local altIDs = alt.itemIDs
        if (not altIDs or #altIDs == 0) and alt.itemRef then
            altIDs = ctx.pdb.rankGroups[alt.itemRef] or {}
        end

        if altIDs and #altIDs > 0 then
            -- Compare alternatives within the active rank policy so an R2 pool
            -- chooses the cheapest R2 reagent, not the cheapest reagent of any rank.
            local pickedAltID = PickItemID(altIDs, ctx.patchTag)
            local altPrice, altStale = Pricing.GetEffectivePriceForItem({
                itemIDs = pickedAltID and { pickedAltID } or altIDs,
                name = alt.itemRef,
            }, ctx.patchTag, required)
            if altPrice and pickedAltID and (not best or altPrice < best.price) then
                best = {
                    itemID = pickedAltID,
                    itemIDs = altIDs,
                    name = alt.itemRef,
                    price = altPrice,
                    stale = altStale or false,
                }
            end
        else
            local altProxy = { itemIDs = altIDs or {}, name = alt.itemRef }
            local altPrice, altStale = Pricing.GetEffectivePriceForItem(altProxy, ctx.patchTag, required)
            if altPrice and (not best or altPrice < best.price) then
                best = {
                    itemID = PickItemID(altIDs, ctx.patchTag),
                    itemIDs = altIDs,
                    name = alt.itemRef,
                    price = altPrice,
                    stale = altStale or false,
                }
            end
        end
    end

    return best
end

local function CountOwnedReagentItems(itemID, entryIDs)
    local userHave = 0
    if itemID then
        return GetItemCount(itemID, true) or 0
    end
    if entryIDs and #entryIDs > 0 then
        for _, reagentID in ipairs(entryIDs) do
            userHave = userHave + (GetItemCount(reagentID, true) or 0)
        end
    end
    return userHave
end

local function GetCheapestAlternativeScanIDs(entry, ctx)
    if not (entry and entry.cheapestOf) then
        return nil
    end
    local seen = {}
    local scanIDs = {}
    for _, alt in ipairs(entry.cheapestOf) do
        local altIDs = alt.itemIDs
        if (not altIDs or #altIDs == 0) and alt.itemRef then
            altIDs = ctx.pdb.rankGroups[alt.itemRef] or {}
        end
        for _, altID in ipairs(altIDs or {}) do
            if not seen[altID] then
                seen[altID] = true
                scanIDs[#scanIDs + 1] = altID
            end
        end
    end
    return (#scanIDs > 0) and scanIDs or nil
end

local function BuildReagentMetrics(ctx, missingPrices)
    local mergedOrder, mergedMap = BuildMergedReagentMap(ctx)
    local reagentResults = {}
    local totalCostToBuy = 0
    local totalCostRequired = 0
    local hasStale = false
    local selectionNotes = {}

    for _, key in ipairs(mergedOrder) do
        local entry = mergedMap[key]
        local entryIDs = entry.itemIDs
        local required = math.floor(entry.qty + 0.5)
        local itemID, price, stale, displayName

        if entry.cheapestOf then
            local resolved = ResolveCheapestAlternative(entry, ctx, required)
            if resolved then
                entryIDs = resolved.itemIDs
                itemID = resolved.itemID
                displayName = resolved.name
                price = resolved.price
                stale = resolved.stale
            else
                entryIDs = entry.itemIDs
                itemID = PickItemID(entryIDs, ctx.patchTag)
                displayName = entry.name
                price = nil
                stale = false
            end
        else
            itemID      = PickItemID(entryIDs, ctx.patchTag)
            displayName = entry.name
            local itemProxy = { itemIDs = entryIDs, name = entry.name }
            price, stale = Pricing.GetEffectivePriceForItem(itemProxy, ctx.patchTag, required)
        end

        local userHave = CountOwnedReagentItems(itemID, entryIDs)
        local needToBuy = math.max(0, required - userHave)
        if stale then
            hasStale = true
        end

        local totalCost = (needToBuy == 0) and 0 or (price and (needToBuy * price) or nil)
        local totalCostFull = price and (required * price) or nil
        local missingPrice = (needToBuy > 0) and not price

        if missingPrice then
            missingPrices[#missingPrices + 1] = displayName
        else
            totalCostToBuy = totalCostToBuy + (totalCost or 0)
            totalCostRequired = totalCostRequired + (totalCostFull or 0)
        end

        reagentResults[#reagentResults + 1] = {
            name = displayName,
            itemID = itemID,
            scanItemIDs = GetCheapestAlternativeScanIDs(entry, ctx),
            unitPrice = price,
            required = required,
            have = userHave,
            needToBuy = needToBuy,
            totalCost = totalCost,
            totalCostFull = totalCostFull,
            isStale = stale,
            missingPrice = missingPrice,
            selectedAlternativeName = entry.cheapestOf and displayName or nil,
            selectedAlternativeItemID = entry.cheapestOf and itemID or nil,
            selectionMode = entry.cheapestOf and "cheapest_pool" or nil,
        }

        if entry.cheapestOf and displayName then
            selectionNotes[#selectionNotes + 1] = displayName
        end
    end

    return {
        reagentResults = reagentResults,
        totalCostToBuy = totalCostToBuy,
        totalCostRequired = totalCostRequired,
        hasStale = hasStale,
        selectionNotes = selectionNotes,
    }
end

local function GetPrimaryOutput(ctx)
    return (ctx.active.outputs and ctx.active.outputs[1]) or ctx.active.output or {}
end

local function GetPrimaryInputQuality(ctx)
    if ctx.strat.qualityPolicy == "force_q1_inputs" then
        return 1
    end
    if ctx.strat.qualityPolicy == "force_q2_inputs" then
        return 2
    end
    if not (ctx.active.reagents and #ctx.active.reagents > 0) then
        return nil
    end

    local firstReagent = ctx.active.reagents[1]
    local pickedID = nil
    if firstReagent.cheapestOf then
        local required = GetRequiredReagentAmount(firstReagent, ctx.startingAmt, ctx.crafts)
        local resolved = ResolveCheapestAlternative(firstReagent, ctx, required)
        pickedID = resolved and resolved.itemID or nil
    else
        local reagentIDs = GetResolvedReagentItemIDs(firstReagent, ctx.pdb)
        if not (reagentIDs and #reagentIDs > 0) then
            return nil
        end
        pickedID = PickItemID(reagentIDs, ctx.patchTag)
    end
    local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    if api and pickedID then
        local quality = api(pickedID)
        if quality and quality > 0 then
            return quality
        end
    end
    return nil
end

local function BuildSingleOutputMetrics(ctx, primaryOut, outputQtyRaw, outPrice, outMissingPrice, missingPrices)
    local netRevenue = nil
    if outMissingPrice then
        missingPrices[#missingPrices + 1] = GetItemLabel(primaryOut) or "Output"
    elseif outPrice and outputQtyRaw > 0 then
        netRevenue = math.floor(outputQtyRaw * outPrice * (1 - ctx.ahCut))
    end
    return nil, netRevenue
end

local function GetOutputSaleQty(outputQtyRaw, outputQtyRounded)
    if outputQtyRounded and outputQtyRounded > 0 then
        return outputQtyRounded
    end
    if outputQtyRaw and outputQtyRaw > 0 then
        return math.max(1, math.floor(outputQtyRaw + 0.5))
    end
    return 1
end

local function BuildMultiOutputMetrics(ctx, outputPreferredQuality, missingPrices)
    local totalRevenue = 0
    local allHavePrices = true
    local outResults = {}
    local hasStale = false

    for _, outputDef in ipairs(ctx.active.outputs) do
        local outputQtyRaw, outputQty = ComputeOutputQuantity(
            outputDef, ctx.strat, ctx.profileDef, ctx.statDenom, ctx.statMCp, ctx.statMCm_tot, ctx.startingAmt, ctx.crafts)
        local saleQty = GetOutputSaleQty(outputQtyRaw, outputQty)
        local price, stale = GetOutputPriceForItem(outputDef, ctx.patchTag, outputPreferredQuality, saleQty)
        if stale then
            hasStale = true
        end
        local netRevenue = price and math.floor(outputQtyRaw * price * (1 - ctx.ahCut)) or nil
        if not price then
            allHavePrices = false
            missingPrices[#missingPrices + 1] = GetItemLabel(outputDef) or "Output"
        else
            totalRevenue = totalRevenue + netRevenue
        end
        outResults[#outResults + 1] = {
            name = GetItemLabel(outputDef),
            itemID = GetOutputItemIDForDisplay(outputDef, ctx.patchTag, outputPreferredQuality),
            unitPrice = price,
            expectedQty = outputQty,
            netRevenue = netRevenue,
            isStale = stale,
            missingPrice = not price,
        }
    end

    return outResults, allHavePrices and totalRevenue or nil, hasStale
end

local function BuildOutputMetrics(ctx, missingPrices)
    local primaryOut = GetPrimaryOutput(ctx)
    if not primaryOut.name and not primaryOut.itemRef and not primaryOut.itemIDs then
        if GAM.Log and GAM.Log.Warn then
            GAM.Log.Warn("Pricing: strat '%s' missing active output", tostring(ctx.strat.stratName or ctx.strat.id or "?"))
        end
        return nil
    end

    local outputQtyRaw, outputQty = ComputeOutputQuantity(
        primaryOut, ctx.strat, ctx.profileDef, ctx.statDenom, ctx.statMCp, ctx.statMCm_tot, ctx.startingAmt, ctx.crafts)
    local primaryQuality = GetPrimaryInputQuality(ctx)
    local outputPreferredQuality = (ctx.strat.outputQualityMode == "match_input") and primaryQuality or nil
    local saleQty = GetOutputSaleQty(outputQtyRaw, outputQty)
    local outPrice, outStale = GetOutputPriceForItem(primaryOut, ctx.patchTag, outputPreferredQuality, saleQty)
    local outMissingPrice = not outPrice
    local isMultiOutput = ctx.active.outputs and #ctx.active.outputs > 1
    local outputs, netRevenue, extraStale

    if isMultiOutput then
        outputs, netRevenue, extraStale = BuildMultiOutputMetrics(ctx, outputPreferredQuality, missingPrices)
    else
        outputs, netRevenue = BuildSingleOutputMetrics(ctx, primaryOut, outputQtyRaw, outPrice, outMissingPrice, missingPrices)
        extraStale = false
    end

    local outItemID = GetOutputItemIDForDisplay(primaryOut, ctx.patchTag, outputPreferredQuality)

    return {
        primaryOut = primaryOut,
        outputQtyRaw = outputQtyRaw,
        output = {
            name = GetItemLabel(primaryOut),
            itemID = outItemID,
            unitPrice = outPrice,
            expectedQty = outputQty,
            netRevenue = (not isMultiOutput) and netRevenue or nil,
            isStale = outStale,
            missingPrice = outMissingPrice,
        },
        outputs = outputs,
        netRevenue = netRevenue,
        hasStale = outStale or extraStale,
        isMultiOutput = isMultiOutput,
    }
end

local function BuildFinalMetrics(ctx, reagentData, outputData, missingPrices)
    local profit = nil
    local roi = nil
    local breakEven = nil

    if outputData.netRevenue and #missingPrices == 0 then
        profit = outputData.netRevenue - reagentData.totalCostRequired
        if reagentData.totalCostRequired > 0 then
            roi = (profit / reagentData.totalCostRequired) * 100
        end
    end

    if reagentData.totalCostRequired > 0 and outputData.outputQtyRaw > 0 and not outputData.isMultiOutput then
        breakEven = reagentData.totalCostRequired / (outputData.outputQtyRaw * (1 - ctx.ahCut))
    end

    return {
        startingAmount = ctx.startingAmt,
        crafts = ctx.crafts,
        reagents = reagentData.reagentResults,
        output = outputData.output,
        outputs = outputData.outputs,
        totalCostToBuy = reagentData.totalCostToBuy,
        totalCostFull = reagentData.totalCostRequired,
        netRevenue = outputData.netRevenue,
        profit = profit,
        roi = roi,
        breakEvenSell = breakEven,
        missingPrices = missingPrices,
        hasStale = reagentData.hasStale or outputData.hasStale,
        selectionNotes = reagentData.selectionNotes,
    }
end

-- CalculateStratMetrics(strat, patchTag, craftQty) → metrics table or nil
-- strat = one entry from GAM_RECIPES_GENERATED / importer-normalized data
-- craftQty = scalar applied to the recipe's workbook baseline starting amount
-- Runtime uses defaultStartingAmount -> defaultCrafts scaling so workbook
-- "Start Amount" and "Crafts" stay distinct.
-- Returns:
--   {
--     startingAmount,   -- defaultStartingAmount * craftQty
--     reagents = {      -- per-reagent results
--       { name, itemID, unitPrice, required, have, needToBuy, totalCost, isStale, missingPrice }
--     },
--     output = { name, itemID, unitPrice, expectedQty, netRevenue, isStale, missingPrice },
--     totalCostToBuy,
--     netRevenue,
--     profit,
--     roi,              -- nil if no cost
--     breakEvenSell,    -- nil if no output qty
--     missingPrices,    -- list of item names without prices
--     hasStale,
--   }
function Pricing.CalculateStratMetrics(strat, patchTag, craftQty)
    if not strat then return nil end
    patchTag  = patchTag  or GAM.C.DEFAULT_PATCH
    craftQty  = craftQty  or 1

    local opts   = GetOpts()
    local ahCut  = opts.ahCut or GAM.C.AH_CUT
    local pdb    = GetPatchDB(patchTag)
    local active = GetActiveRecipeView(strat)
    if not active or type(active.reagents) ~= "table" or #active.reagents == 0 then
        if GAM.Log and GAM.Log.Warn then
            GAM.Log.Warn("Pricing: strat '%s' missing active reagents", tostring(strat.stratName or strat.id or "?"))
        end
        return nil
    end

    local ctx = BuildCalcContext(strat, active, patchTag, craftQty, opts, pdb, ahCut)
    local missingPrices = {}
    local reagentData = BuildReagentMetrics(ctx, missingPrices)
    local outputData = BuildOutputMetrics(ctx, missingPrices)
    if not outputData then
        return nil
    end

    return BuildFinalMetrics(ctx, reagentData, outputData, missingPrices)
end

-- GetBestStrategy(patchTag, profFilter) — returns (strat, profit, roi) for the top
-- scoring strategy that clears both minimum thresholds. Returns nil,nil,nil if none qualify.
-- Score = profit × √ROI; capital tie-break on full craft cost.
-- Called only on: scan complete, filter change, window open — never per-frame.
function Pricing.GetBestStrategy(patchTag, profFilter)
    patchTag   = patchTag  or GAM.C.DEFAULT_PATCH
    profFilter = profFilter or "All"
    local minProfit = GAM.C.BEST_STRAT_MIN_PROFIT
    local minROI    = GAM.C.BEST_STRAT_MIN_ROI
    local all = GAM.Importer.GetAllStrats(patchTag)
    if not all or #all == 0 then return nil, nil, nil end

    local bestStrat, bestScore, bestProfit, bestROI, bestCost =
        nil, -math.huge, nil, nil, nil

    for _, strat in ipairs(all) do
        if profFilter == "All" or strat.profession == profFilter then
            local m = Pricing.CalculateStratMetrics(strat, patchTag)
            if m then
                local p, r = m.profit, m.roi
                if p and p >= minProfit and r and r >= minROI then
                    local score, cost = GetStrategyScoreFromMetrics(m)
                    local better = not bestStrat
                        or score > bestScore
                        or (score == bestScore
                            and (cost or math.huge) < (bestCost or math.huge))
                    if better then
                        bestStrat, bestScore   = strat, score
                        bestProfit, bestROI, bestCost = p, r, cost
                    end
                end
            end
        end
    end
    return bestStrat, bestProfit, bestROI
end

-- StorePrice(itemID, price) — called by AHScan after scan
function Pricing.StorePrice(itemID, price)
    if not itemID or not price then return end
    local cache = GAM:GetRealmCache()
    -- Store only price + timestamp; raw order-book arrays are no longer persisted
    -- to SavedVariables (they caused progressive lag after multiple scans).
    cache[itemID] = {
        price = price,
        ts    = time(),
    }
    GAM.Log.Debug("Stored price: itemID=%s price=%s", tostring(itemID), tostring(price))
end

-- StoreRaw / GetRawCache — no-ops. Raw AH listings are kept in session-only
-- commodityCache/itemCache in AHScan.lua; they are no longer written to the
-- persistent DB to prevent SavedVariables bloat across scans.
function Pricing.StoreRaw(itemID, sortedRaw)   end
function Pricing.GetRawCache(itemID) return nil end

-- SetPriceOverride(itemID, price, patchTag)
function Pricing.SetPriceOverride(itemID, price, patchTag)
    if not itemID then return end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GAM:GetPatchDB(patchTag)
    pdb.priceOverrides            = pdb.priceOverrides or {}
    pdb.priceOverrides[itemID]    = price
end

-- ClearPriceOverride(itemID, patchTag)
function Pricing.ClearPriceOverride(itemID, patchTag)
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GAM:GetPatchDB(patchTag)
    if pdb.priceOverrides then
        pdb.priceOverrides[itemID] = nil
    end
end
