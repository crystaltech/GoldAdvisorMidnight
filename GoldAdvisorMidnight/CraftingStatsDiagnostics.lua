-- GoldAdvisorMidnight/CraftingStatsDiagnostics.lua
-- Developer-facing profile reports kept separate from capture and pricing state.
-- Module: augments GAM.CraftingStats

local ADDON_NAME, GAM = ...
local Stats = GAM.CraftingStats
if not Stats then return end

local READY_SOURCES = {
    ["native-open"] = true,
    ["native-open-profile"] = true,
    ["gam-cache-recipe"] = true,
    ["gam-cache-profile"] = true,
    ["gam-native-nodes"] = true,
    ["gam-manual-nodes"] = true,
    ["craftsim-imported"] = true,
}

function Stats.DumpProfiles(query)
    query = tostring(query or ""):lower()
    local profiles = Stats.GetAllProfiles()
    local keys = {}
    for key in pairs(profiles) do
        if query == "" or tostring(key):lower():find(query, 1, true) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)

    GAM.Log.Info("=== GAM V2 Stat Profiles ===")
    if #keys == 0 then GAM.Log.Info("no profile matched '%s'", query) end
    for _, key in ipairs(keys) do
        local p = profiles[key] or {}
        GAM.Log.Info("%s source=%s recipeID=%s nodeHash=%s mc=%s mcExtra=%s res=%s resExtra=%s captured=%s",
            tostring(key), tostring(p.statSource or p.source or "-"),
            tostring(p.recipeID or "-"), tostring(p.nodeHash or "-"),
            tostring(p.multiPercent or "-"), tostring(p.multiExtra or "-"),
            tostring(p.resPercent or "-"), tostring(p.resExtra or "-"),
            tostring(p.capturedAt or "-"))
    end
    GAM.Log.Info("=== End V2 Stat Profiles ===")
end

local function BuildProfileUsage()
    local usage, missing, total = {}, {}, 0
    if not (GAM.Importer and type(GAM.Importer.GetAllStrats) == "function") then
        return usage, missing, total
    end
    local ok, strats = pcall(GAM.Importer.GetAllStrats)
    if not ok or type(strats) ~= "table" then return usage, missing, total end
    for _, strat in ipairs(strats) do
        local isFormula = type(strat) == "table"
            and (strat.calcMode == "formula" or strat.formulaProfile ~= nil)
        if isFormula then
            total = total + 1
            local profileKey = strat.statProfileKey or strat.formulaProfile
            if profileKey then
                usage[profileKey] = (usage[profileKey] or 0) + 1
            else
                missing[#missing + 1] = strat
            end
        end
    end
    return usage, missing, total
end

local function GetAuditBucket(profile)
    local source = tostring((profile and (profile.statSource or profile.source)) or "workbook-default")
    if source == "manual" then return "manual" end
    return READY_SOURCES[source] and "ready" or "needsCapture"
end

function Stats.GetAudit(query)
    query = tostring(query or ""):lower()
    local usage, missingStrats, formulaCount = BuildProfileUsage()
    local audit = {
        query = query,
        formulaCount = formulaCount,
        missingStrategyProfiles = missingStrats,
        ready = {}, manual = {}, needsCapture = {},
    }
    for profileKey, profile in pairs(Stats.GetAllProfiles()) do
        if query == "" or tostring(profileKey):lower():find(query, 1, true) then
            local entry = {
                profileKey = profileKey,
                profile = profile,
                source = tostring(profile.statSource or profile.source or "workbook-default"),
                usageCount = usage[profileKey] or 0,
            }
            local bucket = GetAuditBucket(profile)
            audit[bucket][#audit[bucket] + 1] = entry
        end
    end
    local function SortEntries(a, b)
        if (a.usageCount or 0) ~= (b.usageCount or 0) then
            return (a.usageCount or 0) > (b.usageCount or 0)
        end
        return tostring(a.profileKey) < tostring(b.profileKey)
    end
    table.sort(audit.ready, SortEntries)
    table.sort(audit.manual, SortEntries)
    table.sort(audit.needsCapture, SortEntries)
    return audit
end

local function DumpAuditBucket(label, entries, emptyText, limit)
    GAM.Log.Info("%s (%d)", label, #entries)
    if #entries == 0 then GAM.Log.Info("  %s", emptyText) return end
    for i, entry in ipairs(entries) do
        if limit and i > limit then
            GAM.Log.Info("  ... %d more", #entries - limit)
            break
        end
        local p = entry.profile or {}
        GAM.Log.Info("  %s source=%s strats=%d recipeID=%s captured=%s nodeHash=%s mc=%s/%s res=%s/%s",
            tostring(entry.profileKey), tostring(entry.source), tonumber(entry.usageCount) or 0,
            tostring(p.recipeID or "-"), tostring(p.capturedAt or "-"),
            tostring(p.nodeHash or "-"), tostring(p.multiPercent or "-"),
            tostring(p.multiExtra or "-"), tostring(p.resPercent or "-"),
            tostring(p.resExtra or "-"))
    end
end

function Stats.DumpAudit(query)
    local audit = Stats.GetAudit(query)
    GAM.Log.Info("=== GAM V2 Stat Audit ===")
    if audit.query ~= "" then GAM.Log.Info("filter=%s", audit.query) end
    GAM.Log.Info("formulaStrategies=%d readyProfiles=%d manualProfiles=%d needsCapture=%d missingStrategyProfiles=%d",
        audit.formulaCount or 0, #audit.ready, #audit.manual, #audit.needsCapture,
        #(audit.missingStrategyProfiles or {}))
    DumpAuditBucket("Ready", audit.ready, "No captured/imported profiles matched.", 20)
    DumpAuditBucket("Manual", audit.manual, "No manual profiles matched.", 20)
    DumpAuditBucket("Needs capture", audit.needsCapture, "No workbook-default profiles matched.", 20)
    for i, strat in ipairs(audit.missingStrategyProfiles or {}) do
        if i > 12 then
            GAM.Log.Info("  ... %d more", #audit.missingStrategyProfiles - 12)
            break
        end
        GAM.Log.Info("  %s [%s]", tostring(strat.stratName or "?"), tostring(strat.id or "-"))
    end
    GAM.Log.Info("=== End V2 Stat Audit ===")
end

return Stats
