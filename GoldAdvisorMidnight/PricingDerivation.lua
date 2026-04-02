-- GoldAdvisorMidnight/PricingDerivation.lua
-- Internal helpers for crafted/milled reagent derivation and shopping-chain expansion.

local ADDON_NAME, GAM = ...
local Derivation = {}
GAM.PricingDerivation = Derivation

local function GetOpts()
    return (GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {}
end

local function GetFormulaProfiles()
    return (GAM_WORKBOOK_GENERATED and GAM_WORKBOOK_GENERATED.formulaProfiles) or {}
end

local function HasRequiredDeps(deps)
    return deps and deps.PickItemID and deps.GetEffectivePrice
end

-- ===== Pigment -> herb mapping for "Mill Own Herbs" cost mode =====
-- Maps each pigment itemID -> { herbIDs, yieldPerHerb, formulaProfile }.
-- yieldPerHerb stores the sheet base yield before workbook stat scaling.
-- Inscription milling uses 13 pigments per 10 herbs => 1.3 base yield/herb,
-- with resourcefulness applied by the insc_milling profile.
local PIGMENT_MILL_MAP = {
    [245807] = { herbIDs = {236761,236767}, yieldPerHerb = 1.300000, formulaProfile = "insc_milling", displayYieldPerCraft = 13.000000, displayHerbQtyPerCraft = 10.000000 }, -- Powder Pigment Q1
    [245808] = { herbIDs = {236761,236767}, yieldPerHerb = 1.300000, formulaProfile = "insc_milling", displayYieldPerCraft = 13.000000, displayHerbQtyPerCraft = 10.000000 }, -- Powder Pigment Q2
    [245803] = { herbIDs = {236776,236777}, yieldPerHerb = 1.300000, formulaProfile = "insc_milling", displayYieldPerCraft = 13.000000, displayHerbQtyPerCraft = 10.000000 }, -- Argentleaf Pigment Q1
    [245804] = { herbIDs = {236776,236777}, yieldPerHerb = 1.300000, formulaProfile = "insc_milling", displayYieldPerCraft = 13.000000, displayHerbQtyPerCraft = 10.000000 }, -- Argentleaf Pigment Q2
    [245867] = { herbIDs = {236778,236779}, yieldPerHerb = 1.300000, formulaProfile = "insc_milling", displayYieldPerCraft = 13.000000, displayHerbQtyPerCraft = 10.000000 }, -- Mana Lily Pigment Q1
    [245866] = { herbIDs = {236778,236779}, yieldPerHerb = 1.300000, formulaProfile = "insc_milling", displayYieldPerCraft = 13.000000, displayHerbQtyPerCraft = 10.000000 }, -- Mana Lily Pigment Q2
    [245865] = { herbIDs = {236770,236771}, yieldPerHerb = 1.300000, formulaProfile = "insc_milling", displayYieldPerCraft = 13.000000, displayHerbQtyPerCraft = 10.000000 }, -- Sanguithorn Pigment Q1
    [245864] = { herbIDs = {236770,236771}, yieldPerHerb = 1.300000, formulaProfile = "insc_milling", displayYieldPerCraft = 13.000000, displayHerbQtyPerCraft = 10.000000 }, -- Sanguithorn Pigment Q2
}

-- Crafted reagent cost derivations for "craft your own" reagent modes.
-- Each entry maps crafted output itemID -> recipe ingredients and expected output
-- per source unit, mirroring the spreadsheet-baked strategy definition.
local CRAFTED_REAGENT_MAP = {
    -- Bright Linen Bolt Q1/Q2
    [239700] = {
        optionKey = "boltCostSource",
        modeValue = "craft",
        ingredients = {
            { itemIDs = { 236963, 236965 }, qty = 1.000000 }, -- Bright Linen
            { itemIDs = { 251665 },         qty = 4.000000 }, -- Silverleaf Thread
        },
        yield = 1.000000,
        displayIngredients = {
            { itemIDs = { 236963, 236965 }, qty = 1.000000 },
            { itemIDs = { 251665 },         qty = 4.000000 },
        },
        displayYieldPerCraft = 1.000000,
        formulaProfile = "tailoring",
    },
    [239701] = {
        optionKey = "boltCostSource",
        modeValue = "craft",
        ingredients = {
            { itemIDs = { 236963, 236965 }, qty = 1.000000 },
            { itemIDs = { 251665 },         qty = 4.000000 },
        },
        yield = 1.000000,
        displayIngredients = {
            { itemIDs = { 236963, 236965 }, qty = 1.000000 },
            { itemIDs = { 251665 },         qty = 4.000000 },
        },
        displayYieldPerCraft = 1.000000,
        formulaProfile = "tailoring",
    },
    -- Refulgent Copper Ingot Q1: 5xR1 ore + 2xflux -> 1 ingot (base)
    -- Normalised to 1 R1 ore unit: flux qty = 2/5 = 0.4, yield = 1/5
    -- formulaProfile = "blacksmithing" so GetEffectiveCraftYield applies MC/RS bonuses,
    -- keeping shopping-list ore qty consistent with the direct Refulgent Copper Ingot view.
    [238197] = {
        optionKey = "ingotCostSource",
        modeValue = "craft",
        ingredients = {
            { itemIDs = { 237359 }, qty = 1.000000 }, -- Refulgent Copper Ore R1
            { itemIDs = { 243060 }, qty = 0.400000 }, -- Luminant Flux
        },
        yield = 0.200000,
        displayIngredients = {
            { itemIDs = { 237359 }, qty = 5.000000 },
            { itemIDs = { 243060 }, qty = 2.000000 },
        },
        displayYieldPerCraft = 1.000000,
        formulaProfile = "blacksmithing",
    },
    -- Refulgent Copper Ingot Q2: 3xR1 ore + 2xR2 ore + 2xflux -> 1 ingot (base)
    -- Normalised to 1 R1 ore unit: R2 qty = 2/3, flux qty = 2/3, yield = 1/3
    [238198] = {
        optionKey = "ingotCostSource",
        modeValue = "craft",
        ingredients = {
            { itemIDs = { 237359 }, qty = 1.000000 }, -- Refulgent Copper Ore R1
            { itemIDs = { 237361 }, qty = 0.666667 }, -- Refulgent Copper Ore R2
            { itemIDs = { 243060 }, qty = 0.666667 }, -- Luminant Flux
        },
        yield = 0.333333,
        displayIngredients = {
            { itemIDs = { 237359 }, qty = 3.000000 },
            { itemIDs = { 237361 }, qty = 2.000000 },
            { itemIDs = { 243060 }, qty = 2.000000 },
        },
        displayYieldPerCraft = 1.000000,
        formulaProfile = "blacksmithing",
    },
    -- Sienna Ink Q1: sheet pricing omits Songwater from the expected-value math.
    -- Costing therefore mirrors the live workbook C29/C31 formulas: pigments only.
    -- Base yield is 2/20 = 0.1 inks per normalized PP unit before insc_ink stats.
    -- Activates automatically when pigmentCostSource == "mill" (no separate "craft own inks" checkbox needed)
    [245805] = {
        optionKey  = "pigmentCostSource",
        modeValue  = "mill",
        ingredients = {
            { itemIDs = { 245807, 245808 }, qty = 1.000000 }, -- Powder Pigment
            { itemIDs = { 245803, 245804 }, qty = 0.500000 }, -- Argentleaf Pigment
            { itemIDs = { 245867, 245866 }, qty = 0.250000 }, -- Mana Lily Pigment
        },
        yield = 0.100000,
        displayIngredients = {
            { itemIDs = { 245807, 245808 }, qty = 20.000000 },
            { itemIDs = { 245803, 245804 }, qty = 10.000000 },
            { itemIDs = { 245867, 245866 }, qty = 5.000000 },
        },
        displayYieldPerCraft = 2.000000,
        formulaProfile = "insc_ink",
    },
    [245806] = { -- Sienna Ink Q2 -- same recipe
        optionKey  = "pigmentCostSource",
        modeValue  = "mill",
        ingredients = {
            { itemIDs = { 245807, 245808 }, qty = 1.000000 },
            { itemIDs = { 245803, 245804 }, qty = 0.500000 },
            { itemIDs = { 245867, 245866 }, qty = 0.250000 },
        },
        yield = 0.100000,
        displayIngredients = {
            { itemIDs = { 245807, 245808 }, qty = 20.000000 },
            { itemIDs = { 245803, 245804 }, qty = 10.000000 },
            { itemIDs = { 245867, 245866 }, qty = 5.000000 },
        },
        displayYieldPerCraft = 2.000000,
        formulaProfile = "insc_ink",
    },
    -- Munsell Ink Q1: sheet pricing omits Songwater from the expected-value math.
    [245801] = {
        optionKey  = "pigmentCostSource",
        modeValue  = "mill",
        ingredients = {
            { itemIDs = { 245807, 245808 }, qty = 1.000000 }, -- Powder Pigment
            { itemIDs = { 245865, 245864 }, qty = 0.500000 }, -- Sanguithorn Pigment
            { itemIDs = { 245867, 245866 }, qty = 0.250000 }, -- Mana Lily Pigment
        },
        yield = 0.100000,
        displayIngredients = {
            { itemIDs = { 245807, 245808 }, qty = 20.000000 },
            { itemIDs = { 245865, 245864 }, qty = 10.000000 },
            { itemIDs = { 245867, 245866 }, qty = 5.000000 },
        },
        displayYieldPerCraft = 2.000000,
        formulaProfile = "insc_ink",
    },
    [245802] = { -- Munsell Ink Q2 -- same recipe
        optionKey  = "pigmentCostSource",
        modeValue  = "mill",
        ingredients = {
            { itemIDs = { 245807, 245808 }, qty = 1.000000 },
            { itemIDs = { 245865, 245864 }, qty = 0.500000 },
            { itemIDs = { 245867, 245866 }, qty = 0.250000 },
        },
        yield = 0.100000,
        displayIngredients = {
            { itemIDs = { 245807, 245808 }, qty = 20.000000 },
            { itemIDs = { 245865, 245864 }, qty = 10.000000 },
            { itemIDs = { 245867, 245866 }, qty = 5.000000 },
        },
        displayYieldPerCraft = 2.000000,
        formulaProfile = "insc_ink",
    },
}

function Derivation.HasMillMapping(itemID)
    return PIGMENT_MILL_MAP[itemID] ~= nil
end

function Derivation.HasCraftedMapping(itemID)
    return CRAFTED_REAGENT_MAP[itemID] ~= nil
end

function Derivation.GetAnyCraftInfo()
    return CRAFTED_REAGENT_MAP[238197] or CRAFTED_REAGENT_MAP[239700]
end

function Derivation.GetEffectiveCraftYield(craftInfo)
    local baseYield = craftInfo and (craftInfo.yield or craftInfo.yieldPerHerb)
    if not baseYield then
        return 0
    end
    if not craftInfo.formulaProfile then
        return baseYield
    end

    local profileDef = GetFormulaProfiles()[craftInfo.formulaProfile]
    if not profileDef then
        return baseYield
    end

    local opts = GetOpts()
    local statMCp = profileDef.multiKey and ((opts[profileDef.multiKey] or 0) / 100) or 0
    local statRp = profileDef.resKey and ((opts[profileDef.resKey] or 0) / 100) or 0
    -- Node influence is temporarily disabled for spreadsheet parity.
    -- sheetMCm/sheetRs are fixed sheet-authoritative effective multipliers.
    local statMCm_tot = profileDef.multiKey and (profileDef.sheetMCm or GAM.C.BASE_MCM) or 0
    local statRs_tot = profileDef.sheetRs or GAM.C.BASE_RS
    local statDenom = 1 - statRp * statRs_tot
    if statDenom <= 0 then
        statDenom = 1
    end
    return baseYield * (1 + statMCp * statMCm_tot) / statDenom
end

function Derivation.GetMillDerivedPigmentCost(itemID, patchTag, pigmentQty, deps)
    if not HasRequiredDeps(deps) then
        return nil, false
    end

    local info = PIGMENT_MILL_MAP[itemID]
    if not info then
        return nil, false
    end

    local effectiveYield = Derivation.GetEffectiveCraftYield(info)
    if effectiveYield <= 0 then
        return nil, false
    end

    local bestPrice, isStale = nil, false
    local hid = deps.PickItemID(info.herbIDs, patchTag)
    if hid then
        bestPrice, isStale = deps.GetEffectivePrice(hid, patchTag, nil)
    end
    if not bestPrice then
        for _, fid in ipairs(info.herbIDs) do
            if fid ~= hid then
                local p, s = deps.GetEffectivePrice(fid, patchTag, nil)
                if p then
                    bestPrice = p
                    isStale = isStale or (s or false)
                    break
                end
            end
        end
    end
    if not bestPrice then
        return nil, false
    end

    return math.floor(bestPrice / effectiveYield + 0.5), isStale
end

function Derivation.GetPreferredIngredientPrice(itemIDs, patchTag, qty, deps)
    if not HasRequiredDeps(deps) or not itemIDs or #itemIDs == 0 then
        return nil, false
    end

    local picked = deps.PickItemID(itemIDs, patchTag)
    if picked then
        if GetOpts().pigmentCostSource == "mill" and PIGMENT_MILL_MAP[picked] then
            local p, s = Derivation.GetMillDerivedPigmentCost(picked, patchTag, qty, deps)
            if p then
                return p, s
            end
        end
        if CRAFTED_REAGENT_MAP[picked] then
            local p, s = Derivation.GetCraftDerivedReagentCost(picked, patchTag, qty, deps)
            if p then
                return p, s
            end
        end
        local price, isStale = deps.GetEffectivePrice(picked, patchTag, qty)
        if price then
            return price, isStale
        end
    end

    for _, itemID in ipairs(itemIDs) do
        if itemID ~= picked then
            local price, isStale = deps.GetEffectivePrice(itemID, patchTag, qty)
            if price then
                return price, isStale
            end
        end
    end

    return nil, false
end

function Derivation.GetCraftDerivedReagentCost(itemID, patchTag, outputQty, deps)
    local info = CRAFTED_REAGENT_MAP[itemID]
    if not info or not HasRequiredDeps(deps) then
        return nil, false
    end
    if (GetOpts()[info.optionKey] or "ah") ~= info.modeValue then
        return nil, false
    end

    local effectiveYield = Derivation.GetEffectiveCraftYield(info)
    if effectiveYield <= 0 then
        return nil, false
    end

    local totalCost, anyStale = 0, false
    for _, ingredient in ipairs(info.ingredients) do
        local unitPrice, isStale = Derivation.GetPreferredIngredientPrice(ingredient.itemIDs, patchTag, nil, deps)
        if not unitPrice then
            return nil, false
        end
        totalCost = totalCost + (unitPrice * ingredient.qty)
        anyStale = anyStale or isStale
    end

    return math.floor(totalCost / effectiveYield + 0.5), anyStale
end

function Derivation.ExpandReagentThroughChain(itemIDs, qty, patchTag, deps, depth)
    depth = depth or 0
    if depth > 5 or not itemIDs or #itemIDs == 0 or not deps or not deps.PickItemID then
        return {{ itemIDs = itemIDs, qty = qty }}
    end

    local picked = deps.PickItemID(itemIDs, patchTag)
    if not picked then
        return {{ itemIDs = itemIDs, qty = qty }}
    end

    local craftInfo = CRAFTED_REAGENT_MAP[picked]
    if craftInfo and (GetOpts()[craftInfo.optionKey] or "ah") == craftInfo.modeValue then
        local effectiveYield = Derivation.GetEffectiveCraftYield(craftInfo)
        if effectiveYield <= 0 then
            return {{ itemIDs = itemIDs, qty = qty }}
        end

        local primaryQty = qty / effectiveYield
        local result = {}
        for _, ing in ipairs(craftInfo.ingredients) do
            local ingQty = primaryQty * ing.qty
            local sub = Derivation.ExpandReagentThroughChain(ing.itemIDs, ingQty, patchTag, deps, depth + 1)
            for _, expanded in ipairs(sub) do
                tinsert(result, expanded)
            end
        end
        return result
    end

    local millInfo = PIGMENT_MILL_MAP[picked]
    if millInfo and GetOpts().pigmentCostSource == "mill" then
        local effectiveYield = Derivation.GetEffectiveCraftYield(millInfo)
        if effectiveYield <= 0 then
            return {{ itemIDs = itemIDs, qty = qty }}
        end
        local herbQty = qty / effectiveYield
        return {{ itemIDs = millInfo.herbIDs, qty = herbQty }}
    end

    return {{ itemIDs = itemIDs, qty = qty }}
end

function Derivation.ExpandReagentForDisplayThroughChain(itemIDs, qty, patchTag, deps, depth)
    depth = depth or 0
    if depth > 5 or not itemIDs or #itemIDs == 0 or not deps or not deps.PickItemID then
        return {{ itemIDs = itemIDs, qty = qty }}
    end

    local picked = deps.PickItemID(itemIDs, patchTag)
    if not picked then
        return {{ itemIDs = itemIDs, qty = qty }}
    end

    local craftInfo = CRAFTED_REAGENT_MAP[picked]
    if craftInfo and (GetOpts()[craftInfo.optionKey] or "ah") == craftInfo.modeValue and craftInfo.displayIngredients and craftInfo.displayYieldPerCraft then
        local displayYieldPerCraft = craftInfo.displayYieldPerCraft or 0
        if displayYieldPerCraft <= 0 then
            return {{ itemIDs = itemIDs, qty = qty }}
        end

        -- Display/shopping chain expansion must buy enough to execute the requested
        -- chain, so it uses the deterministic base craft yield rather than the
        -- expected-value sheet yield that includes MC/RS assumptions.
        local craftsNeeded = math.max(1, math.ceil((qty / displayYieldPerCraft) - 1e-9))
        local result = {}
        for _, ing in ipairs(craftInfo.displayIngredients) do
            local ingQty = craftsNeeded * ing.qty
            local sub = Derivation.ExpandReagentForDisplayThroughChain(ing.itemIDs, ingQty, patchTag, deps, depth + 1)
            for _, expanded in ipairs(sub) do
                tinsert(result, expanded)
            end
        end
        return result
    end

    local millInfo = PIGMENT_MILL_MAP[picked]
    if millInfo and GetOpts().pigmentCostSource == "mill" and millInfo.displayYieldPerCraft and millInfo.displayHerbQtyPerCraft then
        local displayYieldPerCraft = millInfo.displayYieldPerCraft or 0
        if displayYieldPerCraft <= 0 then
            return {{ itemIDs = itemIDs, qty = qty }}
        end

        local craftsNeeded = math.max(1, math.ceil((qty / displayYieldPerCraft) - 1e-9))
        local herbQty = craftsNeeded * millInfo.displayHerbQtyPerCraft
        return {{ itemIDs = millInfo.herbIDs, qty = herbQty }}
    end

    return {{ itemIDs = itemIDs, qty = qty }}
end

function Derivation.ExpandReagentForDisplayOneLevel(itemIDs, qty, patchTag, deps)
    if not itemIDs or #itemIDs == 0 or not deps or not deps.PickItemID then
        return { { itemIDs = itemIDs, qty = qty } }, false
    end

    local picked = deps.PickItemID(itemIDs, patchTag)
    if not picked then
        return { { itemIDs = itemIDs, qty = qty } }, false
    end

    local craftInfo = CRAFTED_REAGENT_MAP[picked]
    if craftInfo and (GetOpts()[craftInfo.optionKey] or "ah") == craftInfo.modeValue and craftInfo.displayIngredients and craftInfo.displayYieldPerCraft then
        local displayYieldPerCraft = craftInfo.displayYieldPerCraft or 0
        if displayYieldPerCraft <= 0 then
            return { { itemIDs = itemIDs, qty = qty } }, false
        end

        local craftsNeeded = math.max(1, math.ceil((qty / displayYieldPerCraft) - 1e-9))
        local result = {}
        for _, ing in ipairs(craftInfo.displayIngredients) do
            result[#result + 1] = {
                itemIDs = ing.itemIDs,
                qty = craftsNeeded * ing.qty,
            }
        end
        return result, true
    end

    local millInfo = PIGMENT_MILL_MAP[picked]
    if millInfo and GetOpts().pigmentCostSource == "mill" and millInfo.displayYieldPerCraft and millInfo.displayHerbQtyPerCraft then
        local displayYieldPerCraft = millInfo.displayYieldPerCraft or 0
        if displayYieldPerCraft <= 0 then
            return { { itemIDs = itemIDs, qty = qty } }, false
        end

        local craftsNeeded = math.max(1, math.ceil((qty / displayYieldPerCraft) - 1e-9))
        return {
            {
                itemIDs = millInfo.herbIDs,
                qty = craftsNeeded * millInfo.displayHerbQtyPerCraft,
            },
        }, true
    end

    return { { itemIDs = itemIDs, qty = qty } }, false
end
