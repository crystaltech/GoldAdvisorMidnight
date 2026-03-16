-- GoldAdvisorMidnight/Importer.lua
-- Loads StratsGenerated + StratsManual, builds runtime indices.
-- Validates and normalises strat records. No loadstring.
-- Module: GAM.Importer

local ADDON_NAME, GAM = ...
local Importer = {}
GAM.Importer = Importer

-- ===== Runtime indices (rebuilt by Init) =====
local stratsByID         = {}   -- [id] = strat
local stratsByPatch      = {}   -- [patchTag] = { strat, ... }
local stratsByProfession = {}   -- [profession] = { strat, ... }
local allStrats          = {}   -- ordered list

-- ===== ID generator (deterministic, patchTag-aware) =====
local function NormStr(s)
    return (s or ""):lower():gsub("[^a-z0-9]", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
end

local function MakeStratID(profession, stratName, patchTag)
    return NormStr(profession) .. "__" .. NormStr(stratName) .. "__" .. NormStr(patchTag)
end

-- ===== Validation =====
local function ValidateStrat(s, src)
    if type(s) ~= "table" then
        GAM.Log.Warn("Importer: %s — skipping non-table entry", src)
        return false
    end
    if type(s.stratName) ~= "string" or s.stratName == "" then
        GAM.Log.Warn("Importer: %s — missing stratName, skipping", src)
        return false
    end
    if type(s.profession) ~= "string" or s.profession == "" then
        GAM.Log.Warn("Importer: %s '%s' — missing profession, skipping", src, s.stratName)
        return false
    end
    local hasOutput  = type(s.output) == "table"
    local hasOutputs = type(s.outputs) == "table" and #s.outputs > 0
    if not hasOutput and not hasOutputs then
        GAM.Log.Warn("Importer: %s '%s' — missing output/outputs table, skipping", src, s.stratName)
        return false
    end
    if type(s.reagents) ~= "table" then
        GAM.Log.Warn("Importer: %s '%s' — missing reagents table, skipping", src, s.stratName)
        return false
    end
    -- Validate output multipliers (accept baseYieldMultiplier or legacy qtyMultiplier)
    if hasOutput then
        local bym = s.output.baseYieldMultiplier
        local qm  = s.output.qtyMultiplier
        if type(bym) ~= "number" and type(qm) ~= "number" then
            GAM.Log.Warn("Importer: %s '%s' — missing output baseYieldMultiplier", src, s.stratName)
            return false
        end
        if (type(bym) == "number" and bym < 0) or (type(qm) == "number" and qm < 0) then
            GAM.Log.Warn("Importer: %s '%s' — negative output yield multiplier", src, s.stratName)
            return false
        end
        s.output.itemIDs = s.output.itemIDs or {}
    end
    if type(s.outputs) == "table" then
        for i, o in ipairs(s.outputs) do
            local bym = o.baseYieldMultiplier
            local qm  = o.qtyMultiplier
            if type(bym) ~= "number" and type(qm) ~= "number" then
                GAM.Log.Warn("Importer: %s '%s' outputs[%d] — missing baseYieldMultiplier", src, s.stratName, i)
                return false
            end
            o.itemIDs = o.itemIDs or {}
        end
    end
    for i, r in ipairs(s.reagents) do
        if type(r.qtyMultiplier) ~= "number" or r.qtyMultiplier < 0 then
            GAM.Log.Warn("Importer: %s '%s' reagent[%d] — bad qtyMultiplier", src, s.stratName, i)
            return false
        end
        r.itemIDs = r.itemIDs or {}
    end
    return true
end

-- Manual overrides only need profession + stratName. output/reagents are optional
-- (merged into the matching generated strat; reagents only overridden if provided).
local function ValidateManualOverride(s)
    if type(s) ~= "table" then
        GAM.Log.Warn("Importer: Manual — skipping non-table entry")
        return false
    end
    if type(s.stratName) ~= "string" or s.stratName == "" then
        GAM.Log.Warn("Importer: Manual — missing stratName, skipping")
        return false
    end
    if type(s.profession) ~= "string" or s.profession == "" then
        GAM.Log.Warn("Importer: Manual '%s' — missing profession, skipping", s.stratName)
        return false
    end
    -- Normalise optional fields so downstream code doesn't need nil-checks.
    -- NOTE: itemIDs is intentionally NOT defaulted to {} here so that an
    -- explicit itemIDs = {} in the manual entry can clear generated IDs,
    -- while a missing itemIDs field leaves generated IDs unchanged.
    if s.output then
        -- leave s.output.itemIDs as-is (nil means "don't override")
    end
    if type(s.reagents) == "table" then
        for _, r in ipairs(s.reagents) do
            r.itemIDs = r.itemIDs or {}
        end
    end
    return true
end

-- ===== Normalise + assign ID =====
local function NormaliseStrat(s)
    local pt = s.patchTag or GAM.C.DEFAULT_PATCH
    s.patchTag     = pt
    s.defaultStartingAmount = s.defaultStartingAmount or 1
    s.notes        = s.notes or ""
    s.sourceTab    = s.sourceTab or s.profession
    if not s.output and type(s.outputs) == "table" and s.outputs[1] then
        local first = s.outputs[1]
        s.output = {
            name          = first.name,
            itemIDs       = first.itemIDs or {},
            qtyMultiplier = first.qtyMultiplier or 0,
        }
        GAM.Log.Verbose("Importer: synthesized primary output from outputs[1] for '%s'", s.stratName)
    end
    -- Assign deterministic ID
    s.id = MakeStratID(s.profession, s.stratName, pt)
end

-- ===== Merge manual overrides into generated strat =====
-- Manual strats can override itemIDs and defaultStartingAmount for existing IDs,
-- or add entirely new strats.
local function ApplyManualOverride(generated, manual)
    -- Manual entry matches by id if provided, else by profession+stratName+patchTag
    local targetID = manual.id or MakeStratID(
        manual.profession or "", manual.stratName or "", manual.patchTag or GAM.C.DEFAULT_PATCH)

    local existing = stratsByID[targetID]
    if existing then
        -- Merge: output fields, defaultStartingAmount, outputs list
        if manual.output then
            -- nil means "not provided" (preserve generated IDs)
            -- {} means "clear" (explicit empty override)
            if manual.output.itemIDs ~= nil then
                existing.output.itemIDs = manual.output.itemIDs
            end
            if manual.output.name then
                existing.output.name = manual.output.name
            end
            if manual.output.qtyMultiplier ~= nil then
                existing.output.qtyMultiplier = manual.output.qtyMultiplier
            end
        end
        if manual.outputs then
            existing.outputs = manual.outputs
        end
        if manual.defaultStartingAmount then
            existing.defaultStartingAmount = manual.defaultStartingAmount
        end
        -- Reagent itemID overrides by name match.
        -- Empty table means "no reagent override" so generated reagents remain intact.
        if type(manual.reagents) == "table" and #manual.reagents > 0 then
            for _, mr in ipairs(manual.reagents) do
                for _, er in ipairs(existing.reagents) do
                    if er.name == mr.name and mr.itemIDs and #mr.itemIDs > 0 then
                        er.itemIDs = mr.itemIDs
                        break
                    end
                end
            end
        end
        -- Merge notes if provided
        if manual.notes then existing.notes = manual.notes end
        GAM.Log.Verbose("Importer: applied manual override to '%s'", targetID)
        return true  -- merged, don't add as new
    end
    return false  -- new strat, add to indices
end

-- ===== Index a strat =====
local function IndexStrat(s)
    stratsByID[s.id] = s
    allStrats[#allStrats + 1] = s

    local pt = s.patchTag
    stratsByPatch[pt] = stratsByPatch[pt] or {}
    stratsByPatch[pt][#stratsByPatch[pt] + 1] = s

    local pr = s.profession
    stratsByProfession[pr] = stratsByProfession[pr] or {}
    stratsByProfession[pr][#stratsByProfession[pr] + 1] = s
end

-- ===== Init =====
function Importer.Init()
    -- Wipe indices
    wipe(stratsByID)
    wipe(stratsByPatch)
    wipe(stratsByProfession)
    wipe(allStrats)

    local loaded = 0
    local skipped = 0

    -- 1. Process generated strats
    if type(GAM_STRATS_GENERATED) == "table" then
        for _, s in ipairs(GAM_STRATS_GENERATED) do
            if ValidateStrat(s, "Generated") then
                NormaliseStrat(s)
                IndexStrat(s)
                loaded = loaded + 1
            else
                skipped = skipped + 1
            end
        end
    else
        GAM.Log.Warn("Importer: GAM_STRATS_GENERATED not found — run generate_strats.py")
    end

    -- 2. Process manual strats (overrides first, then new additions)
    if type(GAM_STRATS_MANUAL) == "table" then
        for _, s in ipairs(GAM_STRATS_MANUAL) do
            if ValidateManualOverride(s) then
                NormaliseStrat(s)
                -- Try to merge into existing, otherwise add as new
                local merged = ApplyManualOverride(stratsByID, s)
                if not merged then
                    IndexStrat(s)
                    loaded = loaded + 1
                end
            else
                skipped = skipped + 1
            end
        end
    end

    -- 3. Load user-created strats from SavedVariables (same validation as manual strats).
    if GAM.db and type(GAM.db.userStrats) == "table" then
        for _, s in ipairs(GAM.db.userStrats) do
            s._isUser = true   -- mark so StratDetail knows to show Export/Edit buttons
            if ValidateManualOverride(s) then
                NormaliseStrat(s)
                local merged = ApplyManualOverride(stratsByID, s)
                if not merged then
                    IndexStrat(s)
                    loaded = loaded + 1
                end
            else
                skipped = skipped + 1
                GAM.Log.Warn("Importer: user strat skipped (invalid)")
            end
        end
    end

    GAM.Log.Info("Importer: loaded %d strats, skipped %d", loaded, skipped)
end

-- ===== Public queries =====

function Importer.GetAllStrats(patchTag)
    if not patchTag then return allStrats end
    return stratsByPatch[patchTag] or {}
end

function Importer.GetStratByID(id)
    return stratsByID[id]
end

function Importer.GetStratsByProfession(profession, patchTag)
    local byProf = stratsByProfession[profession] or {}
    if not patchTag then return byProf end
    local out = {}
    for _, s in ipairs(byProf) do
        if s.patchTag == patchTag then
            out[#out + 1] = s
        end
    end
    return out
end

function Importer.GetAllPatchTags()
    local tags = {}
    for tag in pairs(stratsByPatch) do
        tags[#tags + 1] = tag
    end
    table.sort(tags)
    return tags
end

function Importer.GetAllProfessions(patchTag)
    local profs = {}
    local seen  = {}
    local src   = patchTag and (stratsByPatch[patchTag] or {}) or allStrats
    for _, s in ipairs(src) do
        if not seen[s.profession] then
            seen[s.profession] = true
            profs[#profs + 1]  = s.profession
        end
    end
    table.sort(profs)
    return profs
end

function Importer.GetStratCount(patchTag)
    if patchTag then
        return #(stratsByPatch[patchTag] or {})
    end
    return #allStrats
end
