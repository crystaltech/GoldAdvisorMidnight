-- GoldAdvisorMidnight/CraftStats.lua
-- Observed Multicraft and Resourcefulness results per recipe, kept next to
-- what GAM's formula expected for the same crafts. Account-wide totals:
-- the ratio measures the game's mechanics, not one character's stats.
-- Estimates do not read from it yet; it is shown for comparison.
-- Module: GAM.CraftStats

local ADDON_NAME, GAM = ...
local CraftStats = {}
GAM.CraftStats = CraftStats

local function L(key, fallback, ...)
    local value = (GAM.L and GAM.L[key]) or fallback
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end

CraftStats.MIN_CRAFTS_TO_JUDGE = 100
local MAX_TRACKED_OPS = 500

local function Now()
    return (GetServerTime and GetServerTime()) or (time and time()) or 0
end

local function CharacterKey()
    return UnitGUID and UnitGUID("player") or ((UnitName and UnitName("player") or "player")
        .. "-" .. (GetRealmName and GetRealmName() or "realm"))
end

-- Major.minor game version ("12.0"): a new patch may change the mechanics.
local function Build()
    local version = GetBuildInfo and GetBuildInfo() or ""
    return tostring(version):match("^(%d+%.%d+)") or tostring(version)
end

local function Store()
    local db = GAM.db
    if not db then return nil end
    db.craftStats = db.craftStats or { version = 1, recipes = {} }
    return db.craftStats
end
CraftStats.Store = Store

-- ===== Recipe lookup =====
-- Only recipes behind a GAM strategy with a single output are tracked.
local trackedRecipes
local function TrackedRecipe(recipeID)
    recipeID = tonumber(recipeID)
    if not recipeID then return nil end
    if not trackedRecipes then
        trackedRecipes = {}
        local strats = GAM.Importer and GAM.Importer.GetAllStrats and GAM.Importer.GetAllStrats() or {}
        for _, strat in ipairs(strats) do
            local id = tonumber(strat.recipeID)
            if id and #(strat.outputs or {}) == 1 and not trackedRecipes[id] then
                local outputs = {}
                for _, itemID in ipairs(strat.outputs[1].itemIDs or {}) do outputs[itemID] = true end
                trackedRecipes[id] = { name = strat.stratName, outputs = outputs }
            end
        end
    end
    return trackedRecipes[recipeID]
end
function CraftStats.ResetRecipeIndex() trackedRecipes = nil end

-- ===== Live stats for the expectation =====
-- Read once per recipe and reused until gear, talents, buffs or the recipe
-- change. Nil when the open profession window cannot provide them.
local liveCache = {}

local function ReadLive(recipeID)
    local api = C_TradeSkillUI
    if not (api and api.GetRecipeSchematic) then return nil end
    local info = api.GetRecipeInfo and api.GetRecipeInfo(recipeID)
    if info and info.isSalvageRecipe then return nil end
    local schematic = api.GetRecipeSchematic(recipeID, false)
    if not schematic then return nil end
    -- Every required basic reagent can be refunded; only ranked (modified)
    -- slots go into the allocation, fixed slots are consumed automatically.
    local modified = Enum and Enum.TradeskillSlotDataType and Enum.TradeskillSlotDataType.ModifiedReagent or 2
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1
    local allocation, slots = {}, {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        if slot.required and slot.reagents and slot.reagents[1]
                and (slot.reagentType == nil or slot.reagentType == basic) then
            if slot.dataSlotType == modified or slot.dataSlotType == nil then
                allocation[#allocation + 1] = { reagent = slot.reagents[1],
                    dataSlotIndex = slot.dataSlotIndex, quantity = slot.quantityRequired }
            end
            -- Any rank of the reagent refunds into the same slot.
            local key = slot.reagents[1].itemID
            for _, reagent in ipairs(slot.reagents) do
                if reagent.itemID then slots[reagent.itemID] = { key = key, perCraft = tonumber(slot.quantityRequired) or 0 } end
            end
        end
    end
    local stats = GAM.CraftingStats and GAM.CraftingStats.ReadPlannedOperation
        and GAM.CraftingStats.ReadPlannedOperation(recipeID, allocation, nil)
    if not stats then return nil end
    local constants = GAM.CraftSimBridge and GAM.CraftSimBridge.GetFormulaConstants
        and GAM.CraftSimBridge.GetFormulaConstants() or {}
    local formula = GAM.PricingFormula
    local baseYield = math.max(0, tonumber(schematic.quantityMin) or 0)
    local saveBase = tonumber(constants.resourcefulnessSaveBase)
        or (formula and formula.DEFAULT_RESOURCEFULNESS_SAVE_BASE) or 0.30
    return {
        baseYield = baseYield,
        mcChance = stats.supportsMulticraft ~= false and (tonumber(stats.multiPercent) or 0) / 100 or nil,
        mcExtra = tonumber(stats.multiExtra) or 0,
        mcConstant = formula and formula.GetMulticraftConstant(baseYield, constants.multicraftConstants) or 2.5,
        resChance = stats.supportsResourcefulness ~= false and (tonumber(stats.resPercent) or 0) / 100 or nil,
        saveFraction = math.min(1, math.max(0, saveBase * (1 + (tonumber(stats.resExtra) or 0)))),
        resExtra = tonumber(stats.resExtra) or 0,
        nodeHash = stats.nodeHash,
        slots = slots,
    }
end

local function Live(recipeID)
    if liveCache[recipeID] == nil then
        local ok, live = pcall(ReadLive, recipeID)
        liveCache[recipeID] = ok and live or false
    end
    return liveCache[recipeID] or nil
end
function CraftStats.InvalidateLive() liveCache = {} end

-- ===== Recording =====
local function RecipeRecord(store, recipeID, name)
    local build = Build()
    local rec = store.recipes[recipeID]
    if not rec or rec.build ~= build then
        rec = { build = build, crafts = 0, unrated = 0, concentration = 0,
            items = 0, expItems = 0, res = {}, setups = {} }
        store.recipes[recipeID] = rec
    end
    rec.name = name or rec.name
    return rec
end

-- The setup the expectation came from; a change restarts its craft count so
-- later calibration can require a stable setup.
local function TrackSetup(rec, live)
    local key = table.concat({ tostring(live.nodeHash or "-"),
        string.format("%.1f", (live.mcChance or 0) * 100), string.format("%.1f", (live.resChance or 0) * 100),
        string.format("%.2f", live.mcExtra), string.format("%.2f", live.resExtra) }, "|")
    local character = CharacterKey()
    local setup = rec.setups[character]
    if not setup or setup.key ~= key then
        setup = { key = key, since = Now(), crafts = 0 }
        rec.setups[character] = setup
    end
    setup.crafts = setup.crafts + 1
end

-- One craft's expectation, added once per operation.
local function AddExpected(rec, live)
    rec.crafts = rec.crafts + 1
    local expExtra = 0
    if live.mcChance then
        local p = live.mcChance
        local perProc = (1 + live.mcConstant * live.baseYield * (1 + live.mcExtra)) / 2
        rec.mc = rec.mc or { procs = 0, extra = 0, expProcs = 0, expProcVar = 0, expExtra = 0 }
        rec.mc.expProcs = rec.mc.expProcs + p
        rec.mc.expProcVar = rec.mc.expProcVar + p * (1 - p)
        expExtra = p * perProc
        rec.mc.expExtra = rec.mc.expExtra + expExtra
    end
    rec.expItems = rec.expItems + live.baseYield + expExtra
    if live.resChance then
        local p, seen = live.resChance, {}
        for _, slot in pairs(live.slots) do
            if not seen[slot.key] then
                seen[slot.key] = true
                local entry = rec.res[slot.key] or { perCraft = slot.perCraft, procs = 0, returned = 0,
                    expProcs = 0, expReturned = 0, expReturnedVar = 0 }
                rec.res[slot.key] = entry
                entry.perCraft = slot.perCraft
                local saved = live.saveFraction * slot.perCraft
                entry.expProcs = entry.expProcs + p
                entry.expReturned = entry.expReturned + p * saved
                entry.expReturnedVar = entry.expReturnedVar + saved * saved * p * (1 - p)
            end
        end
    end
    TrackSetup(rec, live)
end

local currentRecipe, castSerial = nil, 0
local ops, opCount = {}, 0

local function Operation(result)
    local id = tonumber(result.operationID)
    local key = (id and id > 0) and ("op:" .. id) or ("cast:" .. castSerial)
    local op = ops[key]
    if op then return op, false end
    if opCount >= MAX_TRACKED_OPS then ops, opCount = {}, 0 end
    op = { stacks = {}, resSlots = {} }
    ops[key], opCount = op, opCount + 1
    return op, true
end

function CraftStats.OnCraftResult(result, recipeID)
    recipeID = tonumber(recipeID or currentRecipe)
    if type(result) ~= "table" or not recipeID or result.firstCraftReward then return end
    local recipe = TrackedRecipe(recipeID)
    if not (recipe and result.itemID and recipe.outputs[result.itemID]) then return end
    local store = Store()
    if not store then return end
    local op, fresh = Operation(result)
    if fresh then
        op.recipeID = recipeID
        local rec = RecipeRecord(store, recipeID, recipe.name)
        local live = Live(recipeID)
        if (tonumber(result.concentrationSpent) or 0) > 0 then
            rec.concentration = rec.concentration + 1
        elseif not live then
            rec.unrated = rec.unrated + 1
        else
            op.rated, op.live = true, live
            AddExpected(rec, live)
        end
        rec.updated = Now()
    end
    if not op.rated or op.recipeID ~= recipeID then return end
    local rec = store.recipes[recipeID]
    if not rec then return end
    local stackKey = tostring(result.itemID) .. ":" .. tostring(result.itemGUID)
    if not op.stacks[stackKey] then
        op.stacks[stackKey] = true
        rec.items = rec.items + (tonumber(result.quantity) or 0)
        local extra = tonumber(result.multicraft) or 0
        if extra > 0 and rec.mc then
            rec.mc.extra = rec.mc.extra + extra
            if not op.multicraft then op.multicraft = true; rec.mc.procs = rec.mc.procs + 1 end
        end
    end
    -- Refunds can repeat on every result of one operation: count them once.
    if not op.refunded and type(result.resourcesReturned) == "table" and #result.resourcesReturned > 0 then
        op.refunded = true
        for _, returned in ipairs(result.resourcesReturned) do
            local itemID = returned.reagent and returned.reagent.itemID or returned.itemID
            local slot = itemID and op.live.slots[itemID]
            local entry = slot and rec.res[slot.key]
            if entry then
                entry.returned = entry.returned + (tonumber(returned.quantity) or 0)
                if not op.resSlots[slot.key] then op.resSlots[slot.key] = true; entry.procs = entry.procs + 1 end
            end
        end
    end
end

function CraftStats.OnEvent(event, ...)
    if event == "TRADE_SKILL_CRAFT_BEGIN" then
        local recipeID = tonumber((...))
        if recipeID ~= currentRecipe then liveCache[recipeID or 0] = nil end
        currentRecipe = recipeID
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" and spellID and spellID == currentRecipe then castSerial = castSerial + 1 end
    elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
        local ok, err = pcall(CraftStats.OnCraftResult, (...))
        if not ok and GAM.Log then GAM.Log.Debug("CraftStats: %s", tostring(err)) end
    elseif event == "UNIT_AURA" then
        if (...) == "player" then CraftStats.InvalidateLive() end
    else
        CraftStats.InvalidateLive()
    end
end

if CreateFrame then
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "TRADE_SKILL_CRAFT_BEGIN", "UNIT_SPELLCAST_SUCCEEDED", "TRADE_SKILL_ITEM_CRAFTED_RESULT",
        "PLAYER_EQUIPMENT_CHANGED", "TRAIT_CONFIG_UPDATED", "SKILL_LINES_CHANGED", "UNIT_AURA", "TRADE_SKILL_SHOW" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, ...) CraftStats.OnEvent(event, ...) end)
end

-- ===== Reading =====
local function Count(value)
    local text = tostring(math.floor((tonumber(value) or 0) + 0.5))
    return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function Percent(part, whole)
    if not whole or whole <= 0 then return "-" end
    return string.format("%.1f%%", part / whole * 100)
end

-- "as expected" within two standard deviations; nil before enough crafts.
local function Verdict(rec, observed, expected, variance)
    if rec.crafts < CraftStats.MIN_CRAFTS_TO_JUDGE or expected <= 0 then return nil end
    local sd = math.sqrt(math.max(variance or 0, 1e-9))
    local z = (observed - expected) / sd
    if z <= -2 then return L("CS_BELOW", "below expected") end
    if z >= 2 then return L("CS_ABOVE", "above expected") end
    return L("CS_NORMAL", "as expected")
end

local function ItemName(itemID)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    return name or ("item " .. tostring(itemID))
end

function CraftStats.Get(recipeID)
    local store = Store()
    local rec = store and store.recipes[tonumber(recipeID) or 0]
    if not rec or rec.build ~= Build() then return nil end
    return rec
end

-- Lines describing one recipe's observed results against GAM's expectation.
function CraftStats.DescribeRecipe(recipeID, name)
    local rec = CraftStats.Get(recipeID)
    if not rec or rec.crafts <= 0 then return nil end
    local lines = { L("CS_HEADER", "%s: %s crafts recorded", name or rec.name or tostring(recipeID), Count(rec.crafts)) }
    local function Add(label, observed, expected, verdict)
        local ratio = expected > 0 and string.format(" (%d%%)", math.floor(observed / expected * 100 + 0.5)) or ""
        lines[#lines + 1] = "  " .. L("CS_LINE", "%s: %s, expected %s%s", label, Count(observed), Count(expected), ratio)
            .. (verdict and (" - " .. verdict) or "")
    end
    if rec.mc then
        Add(L("CS_MC_PROCS", "Multicraft procs"), rec.mc.procs, rec.mc.expProcs,
            Verdict(rec, rec.mc.procs, rec.mc.expProcs, rec.mc.expProcVar))
        Add(L("CS_MC_EXTRA", "Extra items"), rec.mc.extra, rec.mc.expExtra, nil)
    end
    Add(L("CS_ITEMS", "Items made"), rec.items, rec.expItems, nil)
    local keys = {}
    for key in pairs(rec.res) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local entry = rec.res[key]
        Add(L("CS_REFUNDED", "%s refunded (%d per craft)", ItemName(key), entry.perCraft),
            entry.returned, entry.expReturned, Verdict(rec, entry.returned, entry.expReturned, entry.expReturnedVar))
    end
    if rec.crafts < CraftStats.MIN_CRAFTS_TO_JUDGE then
        lines[#lines + 1] = "  " .. L("CS_TOO_FEW", "Too few crafts to judge yet; results vary a lot below %d.",
            CraftStats.MIN_CRAFTS_TO_JUDGE)
    end
    local skipped = rec.unrated + rec.concentration
    if skipped > 0 then
        lines[#lines + 1] = "  " .. L("CS_SKIPPED", "%s crafts not compared (Concentration or stats unavailable).", Count(skipped))
    end
    return table.concat(lines, "\n")
end

-- The Craft Stats tooltip: GAM's estimate text followed by the player's own
-- results for the strategy and the intermediates it crafts.
function CraftStats.AppendTooltip(base, stratIDs)
    local parts, seen = {}, {}
    for _, stratID in ipairs(stratIDs or {}) do
        local strat = GAM.Importer and GAM.Importer.GetStratByID and GAM.Importer.GetStratByID(stratID)
        local recipeID = strat and tonumber(strat.recipeID)
        if recipeID and not seen[recipeID] then
            seen[recipeID] = true
            local text = CraftStats.DescribeRecipe(recipeID, strat.stratName)
            if text then parts[#parts + 1] = text end
        end
    end
    if #parts == 0 then return base end
    local observed = L("CS_TOOLTIP_TITLE", "Your crafting results (compared with these stats):") .. "\n" .. table.concat(parts, "\n")
    return base and (base .. "\n\n" .. observed) or observed
end

-- Debug log report: every recorded recipe.
function CraftStats.DumpReport()
    local store = Store()
    local ids = {}
    for recipeID, rec in pairs(store and store.recipes or {}) do
        if rec.build == Build() then ids[#ids + 1] = recipeID end
    end
    table.sort(ids, function(a, b)
        return tostring(store.recipes[a].name or a) < tostring(store.recipes[b].name or b)
    end)
    GAM.Log.Info("=== GAM Craft Results (build %s) ===", Build())
    if #ids == 0 then
        GAM.Log.Info("No craft results recorded yet. Craft a GAM strategy with its recipe open, then run this again.")
    end
    for _, recipeID in ipairs(ids) do
        local text = CraftStats.DescribeRecipe(recipeID)
        if text then
            for line in text:gmatch("[^\n]+") do GAM.Log.Info("%s", line) end
        end
        local rec = store.recipes[recipeID]
        local setup = rec.setups[CharacterKey()]
        if setup then
            GAM.Log.Info("  recipe=%d setup crafts=%d since=%s", recipeID, setup.crafts,
                date and date("%Y-%m-%d %H:%M", setup.since) or tostring(setup.since))
        end
    end
    GAM.Log.Info("=== End Craft Results ===")
end
