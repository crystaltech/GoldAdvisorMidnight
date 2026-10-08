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

-- ===== Developer dumps (/gam dev ...) =====
-- Both dumps read the open profession window and return copyable text. They
-- record what the client reports so static catalogs can be checked by hand.

local function OneLine(value)
    local text = tostring(value == nil and "" or value)
    return (text:gsub("[\r\n\t]+", " | "))
end

local function Percent(value)
    local n = tonumber(value)
    return n and string.format("%.2f", n) or "-"
end

local function SupportFlag(value)
    if value == nil then return "?" end
    return value and "Y" or "N"
end

local function GetOpenProfessionName()
    local context = Stats.GetOpenProfessionTraitContext and Stats.GetOpenProfessionTraitContext()
    if context and context.profession then return context.profession.name end
    local snapshot = Stats.GetOpenNativeRecipeSnapshot and Stats.GetOpenNativeRecipeSnapshot()
    return snapshot and snapshot.profession or nil
end

local function GetRecipeName(recipeID)
    local api = C_TradeSkillUI
    if api and type(api.GetRecipeInfo) == "function" then
        local ok, info = pcall(api.GetRecipeInfo, recipeID)
        if ok and type(info) == "table" then return info.name, info.learned end
    end
    return nil, nil
end

-- /gam dev stats [all]: every GAM strategy recipe of the open profession
-- (or every recipe the client lists, with "all"), read without selecting it.
-- "readable" lists every recipe too but drops non-strategy rows Blizzard
-- could not read (old expansions, recipe-like entries such as Knowledge).
function Stats.DevDumpRecipeStats(argument)
    argument = tostring(argument or ""):lower()
    local readableOnly = argument:find("readable", 1, true) ~= nil
    local profession = GetOpenProfessionName()
    if not profession then return nil, "Open a profession window first." end

    local recipes, order = {}, {}
    local function AddRecipe(recipeID, stratName, profileKey)
        recipeID = tonumber(recipeID)
        if not recipeID then return end
        local row = recipes[recipeID]
        if not row then
            row = { recipeID = recipeID, strats = {}, profileKey = profileKey }
            recipes[recipeID] = row
            order[#order + 1] = recipeID
        end
        if stratName then row.strats[#row.strats + 1] = stratName end
    end
    if GAM.Importer and GAM.Importer.GetStratsByProfession then
        for _, strat in ipairs(GAM.Importer.GetStratsByProfession(profession) or {}) do
            AddRecipe(strat.recipeID, strat.stratName, strat.statProfileKey or strat.formulaProfile)
        end
    end
    if (readableOnly or argument:find("all", 1, true))
            and C_TradeSkillUI and type(C_TradeSkillUI.GetAllRecipeIDs) == "function" then
        local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
        for _, recipeID in ipairs(ok and ids or {}) do AddRecipe(recipeID) end
    end

    local open = Stats.GetOpenNativeRecipeSnapshot and Stats.GetOpenNativeRecipeSnapshot()
    local lines = {
        string.format("GAM recipe stat dump: %s, %d recipes, selected recipe %s",
            profession, #order, tostring(open and open.recipeID or "-")),
        table.concat({ "recipeID", "name", "learned", "read", "mc", "mcPct", "mcRating",
            "res", "resPct", "resRating", "profile", "strats", "rawStats", "skill", "difficulty" }, "\t"),
    }
    local readCount, failed, counts = 0, 0, {}
    for _, recipeID in ipairs(order) do
        local row = recipes[recipeID]
        local name, learned = GetRecipeName(recipeID)
        local snapshot, operation = Stats.ReadRecipeBaseStats(recipeID)
        local skipped = readableOnly and not operation and #row.strats == 0
        local raw = {}
        for _, stat in ipairs(operation and operation.bonusStats or {}) do
            raw[#raw + 1] = string.format("%s=%s/%s", OneLine(stat.bonusStatName or stat.name),
                tostring(stat.bonusStatValue or "-"), Percent(stat.ratingPct or stat.bonusStatPercent))
        end
        local cap = "unread"
        if skipped then
            cap = "skipped"
        elseif snapshot then
            readCount = readCount + 1
            cap = (snapshot.supportsMulticraft and "MC" or "")
                .. (snapshot.supportsResourcefulness and "Res" or "")
            if cap == "" then cap = "none" end
        else
            failed = failed + 1
        end
        counts[cap] = (counts[cap] or 0) + 1
        snapshot = snapshot or {}
        local op = operation or {}
        if not skipped then lines[#lines + 1] = table.concat({
            tostring(recipeID), OneLine(name or "?"), learned == nil and "?" or (learned and "Y" or "N"),
            operation and "Y" or "N",
            SupportFlag(snapshot.supportsMulticraft), Percent(snapshot.multiPercent),
            tostring(snapshot.multiRating or "-"),
            SupportFlag(snapshot.supportsResourcefulness), Percent(snapshot.resPercent),
            tostring(snapshot.resRating or "-"),
            tostring(row.profileKey or "-"), OneLine(table.concat(row.strats, "; ")),
            table.concat(raw, ", "),
            tostring(op.baseSkill and (op.baseSkill + (op.bonusSkill or 0)) or "-"),
            tostring(op.baseDifficulty and (op.baseDifficulty + (op.bonusDifficulty or 0)) or "-"),
        }, "\t") end
    end
    local summary = {}
    for cap, n in pairs(counts) do summary[#summary + 1] = cap .. "=" .. n end
    table.sort(summary)
    lines[#lines + 1] = string.format("read=%d unread=%d %s", readCount, failed, table.concat(summary, " "))
    return table.concat(lines, "\n"), nil
end

local function DescribeCatalogNode(node)
    if type(node) ~= "table" then return "NOT-IN-CATALOG" end
    local stats = {}
    for key, value in pairs(node.stats or {}) do stats[#stats + 1] = key .. "=" .. tostring(value) end
    table.sort(stats)
    return string.format("catalog:%s max=%s parent=%s %s", OneLine(node.name),
        tostring(node.maxRank or "-"), tostring(node.parentNodeID or "-"), table.concat(stats, ","))
end

-- /gam dev nodes: the full live specialization tree of the open profession,
-- with perks, ranks and descriptions, compared against GAM's catalog.
function Stats.DevDumpProfessionNodes()
    local context = Stats.GetOpenProfessionTraitContext and Stats.GetOpenProfessionTraitContext()
    if not context then return nil, "Open a profession window with specializations first." end
    local profSpecs, traits = C_ProfSpecs, C_Traits
    local configID = context.configID
    local Specialization = GAM.CraftingStatsSpecialization
    local catalog = Specialization and Specialization.GetCatalog
        and Specialization.GetCatalog(context.profession.name) or nil
    local catalogNodes = catalog and catalog.nodes or {}
    local Display = GAM.ProfessionNodeDisplay

    local function Call(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, a, b = pcall(fn, ...)
        if ok then return a, b end
        return nil
    end

    local lines = {
        string.format("GAM node dump: %s skillLine=%s config=%s", context.profession.name,
            tostring(context.skillLineID), tostring(configID)),
        table.concat({ "kind", "depth", "nodeID", "parentID", "rank", "max", "name",
            "catalog", "description" }, "\t"),
    }
    local seen = {}
    local function NodeRow(kind, depth, nodeID, parentID, extra)
        seen[nodeID] = true
        local info = Call(traits and traits.GetNodeInfo, configID, nodeID)
        local display = Display and Display.ResolveLiveNodeInfo
            and Call(Display.ResolveLiveNodeInfo, configID, nodeID, info) or nil
        local description = display and display.description
        if kind == "perk" then
            description = Call(profSpecs.GetDescriptionForPerk, nodeID) or description
        end
        lines[#lines + 1] = table.concat({
            kind, tostring(depth), tostring(nodeID), tostring(parentID or "-"),
            tostring(info and (info.currentRank or info.activeRank or info.ranksPurchased) or "-"),
            tostring(info and (info.maxRanks or info.totalMaxRanks) or "-"),
            OneLine(display and display.name or "?") .. (extra or ""),
            DescribeCatalogNode(catalogNodes[nodeID]),
            OneLine(description or ""),
        }, "\t")
    end

    local function Walk(pathID, parentID, depth)
        pathID = tonumber(pathID)
        if not pathID or seen[pathID] or depth > 12 then return end
        NodeRow("path", depth, pathID, parentID)
        for _, perk in ipairs(Call(profSpecs.GetPerksForPath, pathID) or {}) do
            local perkID = tonumber(type(perk) == "table" and perk.perkID or perk)
            if perkID and not seen[perkID] then
                local unlock = Call(profSpecs.GetUnlockRankForPerk, perkID)
                local state = Call(profSpecs.GetStateForPerk, perkID, configID)
                NodeRow("perk", depth + 1, perkID, pathID, string.format(" [unlock@%s state=%s%s]",
                    tostring(unlock or "-"), tostring(state or "-"),
                    (type(perk) == "table" and perk.isMajorPerk) and " major" or ""))
            end
        end
        for _, childID in ipairs(Call(profSpecs.GetChildrenForPath, pathID) or {}) do
            Walk(childID, pathID, depth + 1)
        end
    end

    local tabIDs = Call(profSpecs.GetSpecTabIDsForSkillLine, context.skillLineID) or {}
    for _, tabID in ipairs(tabIDs) do
        local tabInfo = Call(profSpecs.GetTabInfo, tabID)
        local rootID = Call(profSpecs.GetRootPathForTab, tabID) or (tabInfo and tabInfo.rootNodeID)
        lines[#lines + 1] = string.format("tab\t-\t%s\t-\t-\t-\t%s\troot=%s\t", tostring(tabID),
            OneLine(tabInfo and tabInfo.name or "?"), tostring(rootID or "-"))
        Walk(rootID, nil, 0)
    end

    -- Anything the tree API lists that the path walk did not reach.
    for _, tabID in ipairs(tabIDs) do
        for _, nodeID in ipairs(Call(traits and traits.GetTreeNodes, tabID) or {}) do
            nodeID = tonumber(nodeID)
            if nodeID and not seen[nodeID] then NodeRow("tree-only", "-", nodeID, nil) end
        end
    end

    -- What GAM's normal capture sees, so walk/capture differences stand out.
    local captured = {}
    for _, nodeID in ipairs(Stats.CollectProfessionTraitNodeIDs(context) or {}) do captured[nodeID] = true end
    local catalogOnly, notCaptured = {}, {}
    for nodeID in pairs(catalogNodes) do
        if not seen[nodeID] then catalogOnly[#catalogOnly + 1] = tostring(nodeID) end
        if not captured[nodeID] then notCaptured[#notCaptured + 1] = tostring(nodeID) end
    end
    table.sort(catalogOnly)
    table.sort(notCaptured)
    lines[#lines + 1] = "catalog nodes not found live: " .. (#catalogOnly > 0 and table.concat(catalogOnly, ",") or "none")
    lines[#lines + 1] = "catalog nodes missed by GAM capture: " .. (#notCaptured > 0 and table.concat(notCaptured, ",") or "none")
    return table.concat(lines, "\n"), nil
end

-- The equipped profession items and which saved GAM gear set they match.
-- Returns the text and a label for the save: the matching set's mode, or
-- "unsaved-gear".
function Stats.DevDumpGear(strats)
    local Gear, Cache = GAM.CraftingStatsGear, GAM.CraftingStatsCache
    local probe = strats and strats[1]
    if not (Gear and Cache and probe) then return "gear: unavailable", "unknown-gear" end
    local profileKey = probe.statProfileKey or probe.formulaProfile
    local character = Cache.Ensure()
    local equipment = Gear.ReadEquipment(probe.recipeID, profileKey)
    local lines = { "slot\titem" }
    for _, slot in ipairs(equipment and equipment.slots or {}) do
        lines[#lines + 1] = tostring(slot.slot) .. "\t" .. OneLine(slot.link or "empty")
    end
    if not equipment then lines[#lines + 1] = "-\tequipment unreadable (items still loading?)" end
    local matches = {}
    for _, mode in ipairs({ "multicraft", "resourcefulness" }) do
        local set = character and Gear.GetSet(character, probe.recipeID, profileKey, mode)
        local state = "not saved"
        if set then
            state = (equipment and set.signature == equipment.signature) and "EQUIPPED" or "saved, not equipped"
            if state == "EQUIPPED" then matches[#matches + 1] = mode end
            local stats = set.stats or {}
            state = string.format("%s (saved on recipe %s: mc %s, res %s)", state, tostring(set.recipeID),
                Percent(stats.multicraft and stats.multicraft.percent),
                Percent(stats.resourcefulness and stats.resourcefulness.percent))
        end
        lines[#lines + 1] = "set " .. mode .. "\t" .. state
    end
    local label = #matches > 0 and table.concat(matches, "+") or "unsaved-gear"
    return table.concat(lines, "\n"), label
end

local function OutputBaseYield(strat)
    local output = (strat.outputs and strat.outputs[1]) or strat.output or {}
    return tonumber(output.baseYieldPerCraft or output.baseYield) or 1
end

-- What GAM prices each strategy with: the recipe capture (Auto) and each
-- saved gear set, with the expected output of 100 starting crafts.
function Stats.DevDumpResolvedStats(strats)
    local options = (GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {}
    local Formula = GAM.PricingFormula
    local lines = { table.concat({ "recipeID", "strat", "mode", "source", "fallback", "validity",
        "mc", "mcPct", "mcExtra", "res", "resPct", "resExtra", "nodeHash", "outPer100" }, "\t") }
    for _, strat in ipairs(strats or {}) do
        local modes = { "auto" }
        local available = Stats.GetAvailableGearPresetModes and Stats.GetAvailableGearPresetModes(strat) or {}
        for _, mode in ipairs({ "multicraft", "resourcefulness" }) do
            if available[mode] then modes[#modes + 1] = mode end
        end
        for _, mode in ipairs(modes) do
            local opts = options
            if mode ~= "auto" then
                opts = {}
                for key, value in pairs(options) do opts[key] = value end
                opts._gamGearModeOverride = mode
            end
            local ok, s = pcall(Stats.ResolveForStrat, strat, opts)
            s = ok and type(s) == "table" and s or {}
            local out = "-"
            if Formula and ok then
                local result = Formula.CalculateExhaustMaterials({
                    crafts = 100, baseYield = OutputBaseYield(strat),
                    mcPercent = (tonumber(s.multiPercent) or 0) / 100,
                    resPercent = (tonumber(s.resPercent) or 0) / 100,
                    mcExtra = s.multiExtra, resExtra = s.resExtra,
                    supportsMulticraft = s.supportsMulticraft,
                    supportsResourcefulness = s.supportsResourcefulness,
                })
                out = string.format("%.2f", result.expectedOutput or 0)
            end
            lines[#lines + 1] = table.concat({
                tostring(strat.recipeID), OneLine(strat.stratName or "?"), mode,
                tostring(ok and (s.statSource or "-") or ("error: " .. OneLine(s))),
                tostring(s.fallbackReason or "-"), tostring(s.gearStatValidity or "-"),
                SupportFlag(s.supportsMulticraft), Percent(s.multiPercent), Percent(s.multiExtra),
                SupportFlag(s.supportsResourcefulness), Percent(s.resPercent), Percent(s.resExtra),
                tostring(s.nodeHash or "-"), out,
            }, "\t")
        end
    end
    return table.concat(lines, "\n")
end

-- Dumps are kept in the saved DB (GoldAdvisorMidnightDB.devDumps), filed by
-- profession and gear label, one line per array entry, so a /reload writes
-- them to the SavedVariables file. tools/export_dev_dumps.lua splits them.
local function SplitLines(text)
    local lines = {}
    for line in (tostring(text) .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
    return lines
end

local function SaveDevDump(profession, label, sections)
    if type(GAM.db) ~= "table" then return nil end
    GAM.db.devDumps = type(GAM.db.devDumps) == "table" and GAM.db.devDumps or {}
    local byProfession = GAM.db.devDumps[profession] or {}
    GAM.db.devDumps[profession] = byProfession
    local entry = {
        capturedAt = time and time() or nil,
        build = GetBuildInfo and select(2, GetBuildInfo()) or nil,
        character = UnitName and UnitName("player") or nil,
    }
    local total = 0
    for kind, text in pairs(sections) do
        entry[kind] = SplitLines(text)
        total = total + #entry[kind]
    end
    byProfession[label] = entry
    return total
end

-- /gam dev save [label]: everything for the open profession and the gear
-- worn now, in one command.
function Stats.DevSaveAll(label)
    local profession = GetOpenProfessionName()
    if not profession then return nil, "Open a profession window first." end
    local strats = GAM.Importer and GAM.Importer.GetStratsByProfession
        and GAM.Importer.GetStratsByProfession(profession) or {}
    local gearText, gearLabel = Stats.DevDumpGear(strats)
    label = (label and label ~= "") and label:lower() or gearLabel
    local sections = { gear = gearText, gam = Stats.DevDumpResolvedStats(strats) }
    sections.stats = Stats.DevDumpRecipeStats("readable") or "stats: unavailable"
    local nodes, nodesErr = Stats.DevDumpProfessionNodes()
    sections.nodes = nodes or ("nodes: " .. tostring(nodesErr))
    local total = SaveDevDump(profession, label, sections)
    if not total then return nil, "Saved settings are not loaded yet." end
    return string.format("Saved %s / %s: %d strategies, %d lines. Next profession or gear set, then"
        .. " /reload to write the file.", profession, label, #strats, total), nil
end

local DEV_DUMPS = {
    stats = { title = "Recipe stats", run = function() return Stats.DevDumpRecipeStats("") end },
    statsall = { title = "Recipe stats (all)", run = function() return Stats.DevDumpRecipeStats("all") end },
    nodes = { title = "Profession nodes", run = function() return Stats.DevDumpProfessionNodes() end },
}

function Stats.RunDevCommand(argument)
    local sub, rest = tostring(argument or ""):match("^%s*(%S*)%s*(.-)%s*$")
    sub = tostring(sub or ""):lower()
    if sub == "stats" and tostring(rest):lower() == "all" then sub = "statsall" end
    if sub == "clear" then
        if type(GAM.db) == "table" then GAM.db.devDumps = nil end
        print("|cffff8800[GAM]|r Saved dev dumps cleared.")
        return
    end
    if sub == "save" then
        local message, err = Stats.DevSaveAll(rest)
        print("|cffff8800[GAM]|r " .. tostring(message or err))
        return
    end
    local dump = DEV_DUMPS[sub]
    if not dump then
        print("|cffff8800[GAM]|r Dev commands (profession window open): /gam dev save [label] (everything,"
            .. " to SavedVariables), /gam dev stats [all], /gam dev nodes, /gam dev clear.")
        return
    end
    local text, err = dump.run()
    if not text then
        print("|cffff8800[GAM]|r " .. tostring(err))
        return
    end
    if GAM.UI and GAM.UI.DebugLog and GAM.UI.DebugLog.ShowTextExport then
        GAM.UI.DebugLog.ShowTextExport(dump.title, text)
    else
        print(text)
    end
end

return Stats
