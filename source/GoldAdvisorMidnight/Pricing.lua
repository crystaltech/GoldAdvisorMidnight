-- GoldAdvisorMidnight/Pricing.lua
-- Pricing engine: price lookup, effective price, strat metrics.
-- Module: GAM.Pricing

local ADDON_NAME, GAM = ...
local Pricing = {}
GAM.Pricing = Pricing

-- ===== Internal helpers =====

local function GetDB() return GAM.db end
local function GetOpts() return GAM.db and GAM.db.options or {} end
local function GetPatchDB(pt) return GAM:GetPatchDB(pt) end

-- ===== Pigment → herb mapping for "Mill Own Herbs" cost mode =====
-- Maps each pigment itemID → { herbIDs, yieldPerHerb }
-- yieldPerHerb = output.qtyMultiplier (1.53) / reagent.qtyMultiplier (1.0)
local PIGMENT_MILL_MAP = {
    [245807] = { herbIDs = {236761,236767}, yieldPerHerb = 1.530000 }, -- Powder Pigment Q1
    [245808] = { herbIDs = {236761,236767}, yieldPerHerb = 1.530000 }, -- Powder Pigment Q2
    [245803] = { herbIDs = {236776,236777}, yieldPerHerb = 1.530000 }, -- Argentleaf Pigment Q1
    [245804] = { herbIDs = {236776,236777}, yieldPerHerb = 1.530000 }, -- Argentleaf Pigment Q2
    [245867] = { herbIDs = {236778,236779}, yieldPerHerb = 1.530000 }, -- Mana Lily Pigment Q1
    [245866] = { herbIDs = {236778,236779}, yieldPerHerb = 1.530000 }, -- Mana Lily Pigment Q2
    [245865] = { herbIDs = {236770,236771}, yieldPerHerb = 1.530000 }, -- Sanguithorn Pigment Q1
    [245864] = { herbIDs = {236770,236771}, yieldPerHerb = 1.530000 }, -- Sanguithorn Pigment Q2
}

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

-- GetEffectivePrice(itemID, patchTag) → price in copper, or nil
-- Priority: override > AH cache > CraftSim bridge
function Pricing.GetEffectivePrice(itemID, patchTag)
    if not itemID then return nil end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local opts = GetOpts()

    -- 1. Manual override (use ~= nil so an explicit 0 override is honoured)
    local pdb = GetPatchDB(patchTag)
    if pdb.priceOverrides and pdb.priceOverrides[itemID] ~= nil then
        return pdb.priceOverrides[itemID], false
    end

    -- 2. CraftSim (if selected as source)
    if opts.priceSource == "craftsim" and GAM.CraftSimBridge then
        local csPrice = GAM.CraftSimBridge.GetPrice(itemID)
        if csPrice and csPrice > 0 then
            return csPrice, false
        end
    end

    -- 3. AH cache
    return Pricing.GetUnitPrice(itemID)
end

-- GetMillDerivedPigmentCost(itemID, patchTag) → cost per pigment (copper), isStale
-- Derives pigment cost from herb AH price ÷ milling yield.
-- Returns nil if the item is not a known pigment or herb prices are unavailable
-- (caller falls through to AH pigment price).
local function GetMillDerivedPigmentCost(itemID, patchTag)
    local info = PIGMENT_MILL_MAP[itemID]
    if not info then return nil, false end
    local bestPrice, isStale = nil, false
    for _, hid in ipairs(info.herbIDs) do
        local p, s = Pricing.GetEffectivePrice(hid, patchTag)
        if p and (not bestPrice or p < bestPrice) then
            bestPrice = p
            isStale   = isStale or s
        end
    end
    if not bestPrice then return nil, false end
    return math.floor(bestPrice / info.yieldPerHerb + 0.5), isStale
end

-- GetEffectivePriceForItem(item, patchTag) → price, isStale
-- item = { name, itemIDs = {}, ... }
-- Used for REAGENT pricing: tries the rank-policy preferred itemID first, then
-- falls back through remaining variants (you'd buy the cheapest available rank).
function Pricing.GetEffectivePriceForItem(item, patchTag)
    if not item then return nil, false end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GetPatchDB(patchTag)

    -- Resolve itemIDs: use rankGroups if item.itemIDs is empty
    local ids = item.itemIDs
    if (not ids or #ids == 0) and item.name then
        ids = pdb.rankGroups[item.name] or {}
    end

    if not ids or #ids == 0 then return nil, false end

    -- "Mill Own Herbs" mode: for known pigment items, derive cost from herb prices.
    -- Respects manual price overrides — skip mill path if one is set.
    if GetOpts().pigmentCostSource == "mill" then
        local pdb2 = GetPatchDB(patchTag)
        for _, id in ipairs(ids) do
            if PIGMENT_MILL_MAP[id] then
                if not (pdb2.priceOverrides and pdb2.priceOverrides[id] ~= nil) then
                    local millCost, millStale = GetMillDerivedPigmentCost(id, patchTag)
                    if millCost then return millCost, millStale end
                end
                break  -- herb prices missing or override set → fall through to AH price
            end
        end
    end

    local picked = PickItemID(ids, patchTag)
    if not picked then return nil, false end

    -- Try preferred itemID first
    local price, isStale = Pricing.GetEffectivePrice(picked, patchTag)
    if price then return price, isStale end

    -- Fallback: check remaining quality variants in array order
    for _, id in ipairs(ids) do
        if id ~= picked then
            local p, s = Pricing.GetEffectivePrice(id, patchTag)
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

local function GetOutputPriceForItem(item, patchTag, preferredQuality)
    if not item then return nil, false end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GetPatchDB(patchTag)

    local ids = item.itemIDs
    if (not ids or #ids == 0) and item.name then
        ids = pdb.rankGroups[item.name] or {}
    end
    if not ids or #ids == 0 then return nil, false end

    -- Single rank: no rank-matching needed
    if #ids == 1 then
        return Pricing.GetEffectivePrice(ids[1], patchTag)
    end

    -- Preferred quality: find the output itemID whose crafting quality matches
    -- the input reagent's quality (e.g. R2 herb → R2 pigment price).
    if preferredQuality then
        local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
        if api then
            for _, id in ipairs(ids) do
                if api(id) == preferredQuality then
                    local p, s = Pricing.GetEffectivePrice(id, patchTag)
                    if p then return p, s end
                    break  -- found the right quality rank but no price — fall through
                end
            end
        end
    end

    -- Multiple ranks: collect all prices that have AH data
    local prices, anyStale = {}, false
    for _, id in ipairs(ids) do
        local p, s = Pricing.GetEffectivePrice(id, patchTag)
        if p then
            prices[#prices + 1] = p
            if s then anyStale = true end
        end
    end

    if #prices == 0 then return nil, false end
    if #prices == 1 then return prices[1], anyStale end

    -- Cross-rank trim: exclude extreme outliers > RANK_TRIM × min.
    local minPrice = prices[1]
    for _, p in ipairs(prices) do
        if p < minPrice then minPrice = p end
    end
    local threshold = minPrice * RANK_TRIM

    local floorPrice = nil
    for _, p in ipairs(prices) do
        if p <= threshold then
            if not floorPrice or p < floorPrice then floorPrice = p end
        end
    end

    return math.floor(floorPrice or minPrice), anyStale
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
    if g > 0 then parts[#parts+1] = string.format("|cffffd700%dg|r", g) end
    if s > 0 then parts[#parts+1] = string.format("|cffc0c0c0%ds|r", s) end
    if c > 0 or #parts == 0 then parts[#parts+1] = string.format("|cffae8f0a%dc|r", c) end
    local result = table.concat(parts, " ")
    return neg and ("-" .. result) or result
end

-- ===== Stat scaling (Master Equation) =====

-- Stat profiles: baseline values baked into spreadsheet qtyMultipliers.
--   bakedMulti / bakedRes  — the tester's gear stats (0–1) when the multipliers were measured.
--   mcm / rs               — MCm/Rs formula constants baked into the spreadsheet (per-profession).
--   multiKey / resKey      — DB option keys for the user's current gear stats (integer %).
--   mcNodeKey / rsNodeKey  — DB option keys for the user's spec node bonuses (integer %).
--                            Default values (baked into DB_DEFAULTS) match what the spreadsheet
--                            assumed → scale = 1.0 for users who haven't changed them.
-- Starred (*) profiles had bakedMulti=0 (tester had no multicraft gear for that tool set).
local STAT_PROFILES = {
    insc_milling   = { bakedMulti=0,    bakedRes=0.32, resKey="inscMillingRes",                              mcm=0,     rs=0.465, rsNodeKey="inscRsNode"                           },  -- no MC stat
    insc_ink       = { bakedMulti=0.26, bakedRes=0.17, multiKey="inscInkMulti", resKey="inscInkRes",         mcm=2.5,   rs=0.465, mcNodeKey="inscMcNode", rsNodeKey="inscRsNode"   },
    jc_prospect    = { bakedMulti=0,    bakedRes=0.33, resKey="jcProspectRes",                               mcm=0,     rs=0.45,  rsNodeKey="jcRsNode"                             },  -- no MC stat
    jc_crush       = { bakedMulti=0,    bakedRes=0.35, resKey="jcCrushRes",                                  mcm=0,     rs=0.45,  rsNodeKey="jcRsNode"                             },  -- no MC stat
    ench_shatter   = { bakedMulti=0,    bakedRes=0.30, resKey="enchShatterRes",                              mcm=0,     rs=0.36,  rsNodeKey="enchRsNode"                           },  -- no MC stat
    ench_craft     = { bakedMulti=0.25, bakedRes=0.16, multiKey="enchCraftMulti", resKey="enchCraftRes",     mcm=2.5,   rs=0.36,  mcNodeKey="enchMcNode", rsNodeKey="enchRsNode"   },
    alchemy        = { bakedMulti=0.30, bakedRes=0.15, multiKey="alchMulti",      resKey="alchRes",          mcm=1.5,   rs=0.30,  mcNodeKey="alchMcNode", rsNodeKey="alchRsNode"  },
    tailoring      = { bakedMulti=0.25, bakedRes=0.15, multiKey="tailMulti",      resKey="tailRes",          mcm=1.75,  rs=0.45,  mcNodeKey="tailMcNode", rsNodeKey="tailRsNode"  },
    blacksmithing  = { bakedMulti=0.28, bakedRes=0.19, multiKey="bsMulti",        resKey="bsRes",            mcm=1.25,  rs=0.30,  mcNodeKey="bsMcNode",   rsNodeKey="bsRsNode"    },
    leatherworking = { bakedMulti=0.29, bakedRes=0.17, multiKey="lwMulti",        resKey="lwRes",            mcm=1.875, rs=0.45,  mcNodeKey="lwMcNode",   rsNodeKey="lwRsNode"    },
    engineering    = { bakedMulti=0,    bakedRes=0.38, multiKey="engMulti",        resKey="engRes",           mcm=1.875, rs=0.45,  mcNodeKey="engMcNode",  rsNodeKey="engRsNode"   }, -- *
}

-- Maps every strat ID to its stat profile key.
-- Strat IDs not listed here (custom strats, unregistered strats) → outputStatScale = 1.0.
local STRAT_STAT_PROFILE = {
    -- Inscription milling
    ["inscription__tranquility_bloom_milling__midnight_1"] = "insc_milling",
    ["inscription__argentleaf_milling__midnight_1"]        = "insc_milling",
    ["inscription__mana_lily_milling__midnight_1"]         = "insc_milling",
    ["inscription__sanguithorn_milling__midnight_1"]       = "insc_milling",
    -- Inscription ink / soul cipher
    ["inscription__sienna_ink__midnight_1"]                = "insc_ink",
    ["inscription__munsell_ink__midnight_1"]               = "insc_ink",
    ["inscription__soul_cipher__midnight_1"]               = "insc_ink",
    -- JC prospecting
    ["jewelcrafting__dazzling_thorium_prospecting__midnight_1"]     = "jc_prospect",
    ["jewelcrafting__refulgent_copper_ore_prospecting__midnight_1"] = "jc_prospect",
    -- Enchanting shattering
    ["enchanting__dawn_shatter_q2__midnight_1"]                     = "ench_shatter",
    ["enchanting__radiant_shatter_q1__midnight_1"]                  = "ench_shatter",
    ["enchanting__radiant_shatter_q2__midnight_1"]                  = "ench_shatter",
    -- Enchanting crafting
    ["enchanting__oil_of_dawn__midnight_1"]                         = "ench_craft",
    ["enchanting__thalassian_phoenix_oil__midnight_1"]              = "ench_craft",
    ["enchanting__smuggler_s_enchanted_edge__midnight_1"]           = "ench_craft",
    -- Alchemy
    ["alchemy__amani_extract__midnight_1"]                          = "alchemy",
    ["alchemy__composite_flora__midnight_1"]                        = "alchemy",
    ["alchemy__draught_of_rampant_abandon__midnight_1"]             = "alchemy",
    ["alchemy__flask_of_the_blood_knights__midnight_1"]             = "alchemy",
    ["alchemy__flask_of_the_shattered_sun__midnight_1"]             = "alchemy",
    ["alchemy__haranir_phial_of_finesse__midnight_1"]               = "alchemy",
    ["alchemy__haranir_phial_of_perception__midnight_1"]            = "alchemy",
    ["alchemy__light_s_potential__midnight_1"]                      = "alchemy",
    ["alchemy__lightfused_mana_potion__midnight_1"]                 = "alchemy",
    ["alchemy__potion_of_recklessness__midnight_1"]                 = "alchemy",
    ["alchemy__potion_of_zealotry__midnight_1"]                     = "alchemy",
    ["alchemy__silvermoon_health_potion__midnight_1"]               = "alchemy",
    ["alchemy__vicious_thalassian_flask_of_honor__midnight_1"]      = "alchemy",
    ["alchemy__void_shrouded_tincture__midnight_1"]                 = "alchemy",
    -- Tailoring
    ["tailoring__bright_linen_bolt__midnight_1"]                    = "tailoring",
    -- Blacksmithing
    ["blacksmithing__gloaming_alloy_q1__midnight_1"]                = "blacksmithing",
    ["blacksmithing__gloaming_alloy_q2__midnight_1"]                = "blacksmithing",
    ["blacksmithing__refulgent_copper_ingot_q1__midnight_1"]        = "blacksmithing",
    ["blacksmithing__refulgent_copper_ingot_q2__midnight_1"]        = "blacksmithing",
    ["blacksmithing__sterling_alloy_q1__midnight_1"]                = "blacksmithing",
    ["blacksmithing__sterling_alloy_q2__midnight_1"]                = "blacksmithing",
    -- Leatherworking
    ["leatherworking__silvermoon_weapon_wrap__midnight_1"]          = "leatherworking",
    ["leatherworking__sin_dorei_armor_banding__midnight_1"]         = "leatherworking",
    -- Engineering
    ["engineering__recycling_arcanoweave__midnight_1"]              = "engineering",
    ["engineering__recycling_arcanoweave_lining__midnight_1"]       = "engineering",
    ["engineering__recycling_argentleaf_pigment__midnight_1"]       = "engineering",
    ["engineering__recycling_bright_linen_bolt__midnight_1"]        = "engineering",
    ["engineering__recycling_codified_azeroot__midnight_1"]         = "engineering",
    ["engineering__recycling_devouring_banding__midnight_1"]        = "engineering",
    ["engineering__recycling_gloaming_alloy__midnight_1"]           = "engineering",
    ["engineering__recycling_imbued_bright_linen_bolt__midnight_1"] = "engineering",
    ["engineering__recycling_infused_scalewoven_hide__midnight_1"]  = "engineering",
    ["engineering__recycling_munsell_ink__midnight_1"]              = "engineering",
    ["engineering__recycling_powder_pigment__midnight_1"]           = "engineering",
    ["engineering__recycling_refulgent_copper_ingot__midnight_1"]   = "engineering",
    ["engineering__recycling_song_gear__midnight_1"]                = "engineering",
    ["engineering__recycling_soul_sprocket__midnight_1"]            = "engineering",
    ["engineering__recycling_sunfire_silk_bolt__midnight_1"]        = "engineering",
    ["engineering__soul_sprocket__midnight_1"]                      = "engineering",
    ["engineering__song_gear__midnight_1"]                          = "engineering",
    ["engineering__farstrider_hawkeye__midnight_1"]                 = "engineering",
    ["engineering__emergency_soul_link__midnight_1"]                = "engineering",
    ["engineering__smuggler_s_lynxeye__midnight_1"]                 = "engineering",
    ["engineering__laced_zoomshots__midnight_1"]                    = "engineering",
    ["engineering__weighted_boomshots__midnight_1"]                 = "engineering",
}

-- ===== Core calculation =====

-- CalculateStratMetrics(strat, patchTag, craftQty) → metrics table or nil
-- strat = one entry from GAM_STRATS_GENERATED
-- craftQty = how many "batches" (multiplied by defaultStartingAmount)
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

    -- Master Equation stat scaling: adjust output quantities from baked baseline to player's gear.
    -- scale = [(1 + u_multi × eff_mcm) / (1 + b_multi × b_mcm)]
    --       × [(1 - b_res × b_rs) / (1 - u_res × eff_rs)]
    -- where eff_mcm/eff_rs = BASE × (1 + user_node_bonus).
    -- Returns 1.0 for strats not in STRAT_STAT_PROFILE (custom strats → unchanged).
    local outputStatScale = 1.0
    local profileKey = STRAT_STAT_PROFILE[strat.id]
    if profileKey then
        local prof    = STAT_PROFILES[profileKey]
        local u_multi = prof.multiKey and ((opts[prof.multiKey] or 0) / 100) or 0
        local u_res   = (opts[prof.resKey]   or 0) / 100
        local b_multi = prof.bakedMulti
        local b_res   = prof.bakedRes
        local b_mcm   = prof.mcm  -- MCm baked into spreadsheet formula
        local b_rs    = prof.rs   -- Rs  baked into spreadsheet formula

        -- User's effective MCm/Rs from spec node bonus (integer % in DB → decimal)
        local u_mc_node = prof.mcNodeKey and ((opts[prof.mcNodeKey] or 0) / 100)
                          or (GAM.C.BASE_MCM > 0 and (b_mcm / GAM.C.BASE_MCM - 1) or 0)
        local u_rs_node = prof.rsNodeKey and ((opts[prof.rsNodeKey] or 0) / 100)
                          or (GAM.C.BASE_RS  > 0 and (b_rs  / GAM.C.BASE_RS  - 1) or 0)
        local eff_mcm   = GAM.C.BASE_MCM * (1 + u_mc_node)
        local eff_rs    = GAM.C.BASE_RS  * (1 + u_rs_node)

        local multi_denom = 1 + b_multi * b_mcm
        local res_denom   = 1 - u_res   * eff_rs
        local res_baked   = 1 - b_res   * b_rs
        if multi_denom > 0 and res_denom > 0 and res_baked > 0 then
            outputStatScale = ((1 + u_multi * eff_mcm) / multi_denom)
                            * (res_baked / res_denom)
        end
    end

    local startingAmt = (strat.defaultStartingAmount or 1) * craftQty

    -- If the user has set a desired input (primary reagent) qty, use it directly.
    if pdb.inputQtyOverrides and pdb.inputQtyOverrides[strat.id] then
        startingAmt = pdb.inputQtyOverrides[strat.id]
    end

    local totalCostToBuy = 0
    local missingPrices  = {}
    local hasStale       = false
    local reagentResults = {}

    -- ── Reagents ──
    for _, r in ipairs(strat.reagents or {}) do
        -- Use nearest-integer rounding to avoid float precision issues
        -- (e.g. 1.53 * 5000 = 7649.999... in binary; +0.5 floors to 7650)
        local required = math.floor(r.qtyMultiplier * startingAmt + 0.5)

        -- Resolve how many the player currently has (bags + bank)
        local userHave = 0
        local rIds = r.itemIDs
        if (not rIds or #rIds == 0) and r.name then
            rIds = pdb.rankGroups[r.name] or {}
        end
        if rIds and #rIds > 0 then
            for _, rid in ipairs(rIds) do
                userHave = userHave + (GetItemCount(rid, true) or 0)
            end
        end

        local needToBuy = math.max(0, required - userHave)

        -- Price: only required if there is something left to buy.
        -- If the player already owns all copies (needToBuy == 0), cost is 0
        -- and a missing AH price should NOT block profit/ROI display.
        local price, stale = Pricing.GetEffectivePriceForItem(r, patchTag)
        if stale then hasStale = true end

        local totalCost    = (needToBuy == 0) and 0 or (price and (needToBuy * price) or nil)
        local missingPrice = (needToBuy > 0) and not price

        if missingPrice then
            missingPrices[#missingPrices + 1] = r.name
        else
            totalCostToBuy = totalCostToBuy + totalCost
        end

        -- Resolve itemID for display
        local ids    = r.itemIDs
        if (not ids or #ids == 0) and r.name then
            ids = pdb.rankGroups[r.name] or {}
        end
        local itemID = PickItemID(ids, patchTag)

        reagentResults[#reagentResults + 1] = {
            name         = r.name,
            itemID       = itemID,
            unitPrice    = price,
            required     = required,
            have         = userHave,
            needToBuy    = needToBuy,
            totalCost    = totalCost,
            isStale      = stale,
            missingPrice = missingPrice,
        }
    end

    -- ── Output(s) ──
    -- Primary output (always strat.output, used for display + single-output calcs)
    local primaryOut      = strat.output or {}
    -- Raw float used for revenue calculation (expected value over many crafts).
    -- Nearest-integer rounding only for the display qty field.
    local outputQtyRaw    = (primaryOut.qtyMultiplier or 0) * startingAmt * outputStatScale
    local outputQty       = math.floor(outputQtyRaw + 0.5)

    -- Determine the crafting quality of the primary reagent so output pricing can
    -- match the same rank (R1 herb → R1 pigment, R2 herb → R2 pigment).
    local primaryQuality = nil
    if strat.reagents and #strat.reagents > 0 then
        local r0   = strat.reagents[1]
        local rIds = r0.itemIDs
        if (not rIds or #rIds == 0) and r0.name then
            rIds = pdb.rankGroups[r0.name] or {}
        end
        if rIds and #rIds > 0 then
            local pickedId = PickItemID(rIds, patchTag)
            local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
            if api and pickedId then
                local q = api(pickedId)
                if q and q > 0 then primaryQuality = q end
            end
        end
    end

    local outPrice, outStale = GetOutputPriceForItem(primaryOut, patchTag, primaryQuality)
    if outStale then hasStale = true end
    local outMissingPrice = not outPrice

    local netRevenue  = nil
    local outResults  = nil  -- non-nil only for JC multi-output strats

    if strat.outputs and #strat.outputs > 0 then
        -- JC prospecting / Enchanting shatter: sum revenues from all output items.
        -- Each output item gets its own netRevenue field so the display row can show
        -- the correct net value without recomputing the AH cut separately.
        local totalRev      = 0
        local allHavePrices = true
        outResults = {}
        for _, o in ipairs(strat.outputs) do
            local oQtyRaw = (o.qtyMultiplier or 0) * startingAmt * outputStatScale    -- float for revenue
            local oQty    = math.floor(oQtyRaw + 0.5)                               -- integer for display
            local oPrice, oStale2 = GetOutputPriceForItem(o, patchTag, primaryQuality)
            if oStale2 then hasStale = true end
            local oIds = o.itemIDs
            if (not oIds or #oIds == 0) and o.name then
                oIds = pdb.rankGroups[o.name] or {}
            end
            local oNetRev = oPrice and math.floor(oQtyRaw * oPrice * (1 - ahCut)) or nil
            if not oPrice then
                allHavePrices = false
                missingPrices[#missingPrices + 1] = o.name or "Output"
            else
                totalRev = totalRev + oNetRev
            end
            outResults[#outResults + 1] = {
                name         = o.name,
                itemID       = PickItemID(oIds, patchTag),
                unitPrice    = oPrice,
                expectedQty  = oQty,
                netRevenue   = oNetRev,
                isStale      = oStale2,
                missingPrice = not oPrice,
            }
        end
        if allHavePrices then netRevenue = totalRev end
    else
        -- Standard single output
        if outMissingPrice then
            missingPrices[#missingPrices + 1] = primaryOut.name or "Output"
        elseif outPrice and outputQtyRaw > 0 then
            netRevenue = math.floor(outputQtyRaw * outPrice * (1 - ahCut))
        end
    end

    local outIds = primaryOut.itemIDs
    if (not outIds or #outIds == 0) and primaryOut.name then
        outIds = pdb.rankGroups[primaryOut.name] or {}
    end
    local outItemID = PickItemID(outIds, patchTag)

    -- ── Final metrics ──
    local profit    = nil
    local roi       = nil
    local breakEven = nil

    if netRevenue and #missingPrices == 0 then
        profit = netRevenue - totalCostToBuy
        if totalCostToBuy > 0 then
            roi = (profit / totalCostToBuy) * 100
        end
    end

    -- Break-even is only meaningful for single-output strats: it is the minimum
    -- sell price per output unit needed to cover all input costs.  For multi-output
    -- strats (JC prospecting, Enchanting shatters) there is no single output unit
    -- to price, so we leave breakEven nil and the UI shows "—".
    if totalCostToBuy > 0 and outputQtyRaw > 0 and not strat.outputs then
        breakEven = totalCostToBuy / (outputQtyRaw * (1 - ahCut))
    end

    return {
        startingAmount = startingAmt,
        reagents       = reagentResults,
        output = {
            name         = primaryOut.name,
            itemID       = outItemID,
            unitPrice    = outPrice,
            expectedQty  = outputQty,
            netRevenue   = (not strat.outputs) and netRevenue or nil,
            isStale      = outStale,
            missingPrice = outMissingPrice,
        },
        outputs        = outResults,   -- list; non-nil for multi-output (JC) strats
        totalCostToBuy = totalCostToBuy,
        netRevenue     = netRevenue,
        profit         = profit,
        roi            = roi,
        breakEvenSell  = breakEven,
        missingPrices  = missingPrices,
        hasStale       = hasStale,
    }
end

-- GetBestStrategy(patchTag, profFilter) — returns (strat, profit, roi) for the top
-- scoring strategy that clears both minimum thresholds. Returns nil,nil,nil if none qualify.
-- Score = profit × √ROI; capital tie-break on totalCostToBuy.
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
                local p, r, cost = m.profit, m.roi, m.totalCostToBuy
                if p and p >= minProfit and r and r >= minROI then
                    -- Composite score: profit × √ROI (balances magnitude vs capital efficiency)
                    local score = p * math.sqrt(r)
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
    local existing = cache[itemID]
    cache[itemID] = {
        price = price,
        ts    = time(),
        raw   = existing and existing.raw or nil,  -- preserve raw if already stored
    }
    GAM.Log.Debug("Stored price: itemID=%d price=%d", itemID, price)
end

-- StoreRaw(itemID, sortedRaw) — persist raw AH listings alongside the avg price
-- so ComputePriceForQty can give qty-aware prices between sessions.
function Pricing.StoreRaw(itemID, sortedRaw)
    if not itemID or not sortedRaw then return end
    local cache = GAM:GetRealmCache()
    local entry = cache[itemID]
    if entry then
        entry.raw = sortedRaw
    end
end

-- GetRawCache(itemID) — return persisted raw listings, or nil.
function Pricing.GetRawCache(itemID)
    if not itemID then return nil end
    local cache = GAM:GetRealmCache()
    local entry = cache[itemID]
    return entry and entry.raw or nil
end

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
