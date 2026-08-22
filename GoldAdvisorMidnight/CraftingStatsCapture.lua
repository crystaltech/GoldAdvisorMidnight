-- GoldAdvisorMidnight/CraftingStatsCapture.lua
-- Blizzard profession UI and trait API capture adapter.
-- Module: GAM.CraftingStatsCapture

local ADDON_NAME, GAM = ...
local Capture = {}
GAM.CraftingStatsCapture = Capture

local NodeDisplay = GAM.ProfessionNodeDisplay
local Specialization = assert(
    GAM.CraftingStatsSpecialization,
    "CraftingStatsSpecialization must load before CraftingStatsCapture")
local PROFESSION_DEFS = Specialization.GetProfessionDefs()
local ResolveProfessionDef = Specialization.ResolveProfessionDef
local ResolveProfessionDefBySkillLine = Specialization.ResolveProfessionDefBySkillLine

local function NormalizeRecipeID(recipeID)
    local n = tonumber(recipeID)
    if n and n > 0 then
        return math.floor(n)
    end
    return nil
end

function Capture.Create(deps)
    assert(type(deps) == "table", "CraftingStatsCapture dependencies are required")
    assert(type(deps.InferProfileKey) == "function", "InferProfileKey dependency is required")

local function ReadPercentFromBonusStat(statInfo)
    if type(statInfo) ~= "table" then
        return nil
    end
    local value = tonumber(statInfo.ratingPct)
    if value ~= nil then
        return value
    end
    value = tonumber(statInfo.bonusStatPercent)
    if value ~= nil then
        return value
    end
    value = tonumber(statInfo.percent)
    if value ~= nil then
        return value
    end
    return nil
end

local function ApplyOperationBonusStats(snapshot, operationInfo)
    local bonusStats = operationInfo and operationInfo.bonusStats
    if type(bonusStats) ~= "table" then
        return
    end

    for _, statInfo in ipairs(bonusStats) do
        local name = tostring(statInfo.bonusStatName or statInfo.name or ""):lower()
        if name:find("multicraft", 1, true) then
            snapshot.multiPercent = ReadPercentFromBonusStat(statInfo)
            snapshot.supportsMulticraft = snapshot.multiPercent ~= nil
        elseif name:find("resourcefulness", 1, true) then
            snapshot.resPercent = ReadPercentFromBonusStat(statInfo)
            snapshot.supportsResourcefulness = snapshot.resPercent ~= nil
        end
    end
end

local function AddNodeCandidate(out, nodeID, rank, maxRank, name, description, nameSource)
    local id = tonumber(nodeID)
    if not id then return end
    local n = tonumber(rank)
    if n == nil then return end
    local existing = out[id]
    if existing and (tonumber(existing.rank) or 0) >= n then
        existing.name = name or existing.name
        existing.description = description or existing.description
        existing.nameSource = nameSource or existing.nameSource
        return
    end
    out[id] = {
        nodeID = id,
        rank = n,
        maxRank = tonumber(maxRank) or (existing and existing.maxRank) or nil,
        name = name or (existing and existing.name) or nil,
        description = description or (existing and existing.description) or nil,
        nameSource = nameSource or (existing and existing.nameSource) or nil,
    }
end

local function ResolveProfessionDefFromOpenName(name)
    local text = tostring(name or ""):lower()
    if text == "" then return nil end
    for _, def in ipairs(PROFESSION_DEFS) do
        for _, alias in ipairs(def.aliases or {}) do
            if text:find(alias, 1, true) then
                return def
            end
        end
    end
    return nil
end

local function ResolveProfessionDefFromInfo(info)
    if type(info) ~= "table" then return nil end

    -- professionID is the selected expansion skill line (Midnight, in this
    -- case); parentProfessionID is the stable base profession ID in our shared
    -- registry. Prefer the parent so this keeps working across expansions.
    local stableSkillLineID = tonumber(info.parentProfessionID
        or info.baseProfessionID
        or info.skillLineID
        or info.professionID)
    local bySkillLine = stableSkillLineID and ResolveProfessionDefBySkillLine(stableSkillLineID) or nil
    if bySkillLine then return bySkillLine end

    return ResolveProfessionDefFromOpenName(
        info.professionName or info.parentProfessionName or info.name)
end

local function GetOpenProfessionContext()
    local candidates = {}
    if type(ProfessionsFrame) == "table" then
        candidates[#candidates + 1] = ProfessionsFrame.professionInfo
        if type(ProfessionsFrame.GetProfessionInfo) == "function" then
            local ok, info = pcall(ProfessionsFrame.GetProfessionInfo, ProfessionsFrame)
            if ok then candidates[#candidates + 1] = info end
        end
    end

    if C_TradeSkillUI and type(C_TradeSkillUI.GetBaseProfessionInfo) == "function" then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok then candidates[#candidates + 1] = info end
    end

    for _, info in ipairs(candidates) do
        local def = ResolveProfessionDefFromInfo(info)
        if def then
            return def, tonumber(info.professionID or info.skillLineID), info
        end
    end

    local openRecipe = GetOpenNativeRecipeSnapshot()
    if type(openRecipe) == "table" then
        local bySkillLine = ResolveProfessionDefBySkillLine(openRecipe.parentSkillLineID)
            or ResolveProfessionDefBySkillLine(openRecipe.skillLineID)
        if bySkillLine then
            return bySkillLine, tonumber(openRecipe.skillLineID), openRecipe
        end
        local byName = ResolveProfessionDefFromOpenName(openRecipe.profession)
        if byName then
            return byName, tonumber(openRecipe.skillLineID), openRecipe
        end
    end

    return nil
end

local function GetOpenProfessionDef()
    return GetOpenProfessionContext()
end

local function OpenProfessionMatches(profession)
    local def = ResolveProfessionDef(profession)
    if not def then
        return false
    end
    local openDef = GetOpenProfessionDef()
    if openDef then
        return openDef.name == def.name
    end
    return nil
end

local function ExtractNodeRanksFromTable(source, out, seen, depth)
    if type(source) ~= "table" or depth > 5 then
        return
    end
    if seen[source] then return end
    seen[source] = true

    local nodeID = source.nodeID or source.ID or source.id or source.traitNodeID
    local rank = source.rank
        or source.currentRank
        or source.activeRank
        or source.ranksPurchased
        or source.purchasedRanks
        or source.numRanksPurchased
    local maxRank = source.maxRank or source.maxRanks or source.maxVisibleRank
    local name = source.name or source.nodeName or source.displayName
    local description = source.description or source.nodeDescription
    AddNodeCandidate(out, nodeID, rank, maxRank, name, description, name and "blizzard-ui" or nil)

    for key, value in pairs(source) do
        if type(value) == "table" then
            local keyText = tostring(key):lower()
            if keyText:find("node", 1, true)
                    or keyText:find("rank", 1, true)
                    or keyText:find("trait", 1, true)
                    or keyText == "data"
                    or keyText == "nodes"
                    or tonumber(key) ~= nil then
                ExtractNodeRanksFromTable(value, out, seen, depth + 1)
            end
        end
    end
end

local function AddUniqueNumber(out, seen, value)
    local n = tonumber(value)
    if n and n > 0 and not seen[n] then
        seen[n] = true
        out[#out + 1] = n
    end
end

local function GetProfessionTraitContext(profession)
    if not (C_ProfSpecs and C_Traits
            and type(C_ProfSpecs.GetConfigIDForSkillLine) == "function") then
        return nil
    end

    local def = ResolveProfessionDef(profession)
    local openDef, openSkillLineID = GetOpenProfessionContext()
    if not def then def = openDef end
    if not def or (openDef and openDef.name ~= def.name) then
        return nil
    end

    -- Blizzard specializes the selected expansion skill line, not the stable
    -- base profession ID. GetDefaultSpecSkillLine is a useful fallback during
    -- the first frames of profession-window initialization.
    local skillLineCandidates, seenSkillLines = {}, {}
    AddUniqueNumber(skillLineCandidates, seenSkillLines, openSkillLineID)
    if type(C_ProfSpecs.GetDefaultSpecSkillLine) == "function" then
        local ok, skillLineID = pcall(C_ProfSpecs.GetDefaultSpecSkillLine)
        if ok then AddUniqueNumber(skillLineCandidates, seenSkillLines, skillLineID) end
    end
    AddUniqueNumber(skillLineCandidates, seenSkillLines, def.skillLineID)

    for _, skillLineID in ipairs(skillLineCandidates) do
        local ok, configID = pcall(C_ProfSpecs.GetConfigIDForSkillLine, skillLineID)
        configID = ok and tonumber(configID) or nil
        if configID and configID > 0 then
            return {
                profession = def,
                skillLineID = skillLineID,
                configID = configID,
            }
        end
    end
    return nil
end

local function CollectProfessionTraitNodeIDs(context)
    local nodeIDs, seenNodeIDs = {}, {}
    local tabIDs = {}
    if type(C_ProfSpecs.GetSpecTabIDsForSkillLine) == "function" then
        local ok, result = pcall(C_ProfSpecs.GetSpecTabIDsForSkillLine, context.skillLineID)
        if ok and type(result) == "table" then tabIDs = result end
    end

    local function addNodeID(nodeID)
        AddUniqueNumber(nodeIDs, seenNodeIDs, nodeID)
    end

    -- GetTreeNodes is the direct public trait API and avoids depending on any
    -- profession-frame widget layout.
    if type(C_Traits.GetTreeNodes) == "function" then
        for _, treeID in ipairs(tabIDs) do
            local ok, result = pcall(C_Traits.GetTreeNodes, treeID)
            if ok and type(result) == "table" then
                for _, nodeID in ipairs(result) do addNodeID(nodeID) end
            end
        end
    end

    -- Some client builds do not expose profession paths through GetTreeNodes.
    -- Walk the same root/child graph Blizzard's 12.1 profession UI uses.
    local function walkPath(pathID)
        local id = tonumber(pathID)
        if not id or seenNodeIDs[id] then return end
        addNodeID(id)
        if type(C_ProfSpecs.GetChildrenForPath) == "function" then
            local ok, children = pcall(C_ProfSpecs.GetChildrenForPath, id)
            if ok and type(children) == "table" then
                for _, childID in ipairs(children) do walkPath(childID) end
            end
        end
    end

    for _, treeID in ipairs(tabIDs) do
        local rootPathID = nil
        if type(C_ProfSpecs.GetRootPathForTab) == "function" then
            local ok, result = pcall(C_ProfSpecs.GetRootPathForTab, treeID)
            if ok then rootPathID = result end
        end
        if not rootPathID and type(C_ProfSpecs.GetTabInfo) == "function" then
            local ok, tabInfo = pcall(C_ProfSpecs.GetTabInfo, treeID)
            if ok and type(tabInfo) == "table" then
                rootPathID = tabInfo.rootNodeID
            end
        end
        walkPath(rootPathID)
    end

    return nodeIDs, #tabIDs
end

local function GetProfessionNodeRanksFromTraits(profession)
    local context = GetProfessionTraitContext(profession)
    if not context or type(C_Traits.GetNodeInfo) ~= "function" then
        return nil
    end

    local nodeIDs, treeCount = CollectProfessionTraitNodeIDs(context)
    local out = {}
    for _, nodeID in ipairs(nodeIDs) do
        local ok, nodeInfo = pcall(C_Traits.GetNodeInfo, context.configID, nodeID)
        if ok and type(nodeInfo) == "table" then
            local displayInfo = NodeDisplay and NodeDisplay.ResolveLiveNodeInfo
                and NodeDisplay.ResolveLiveNodeInfo(context.configID, nodeID, nodeInfo)
            -- currentRank includes granted ranks, which ranksPurchased omits.
            -- On ordinary profession-frame opening there are no staged edits,
            -- so it represents the learned rank the formula must use.
            AddNodeCandidate(out,
                nodeInfo.ID or nodeID,
                nodeInfo.currentRank or nodeInfo.activeRank or nodeInfo.ranksPurchased,
                nodeInfo.maxRanks or nodeInfo.totalMaxRanks,
                displayInfo and displayInfo.name,
                displayInfo and displayInfo.description,
                displayInfo and displayInfo.source)
        end
    end

    if not next(out) then return nil end
    return out, {
        source = "Blizzard_C_ProfSpecs+C_Traits",
        captureMethod = "traits-api",
        skillLineID = context.skillLineID,
        configID = context.configID,
        treeCount = treeCount,
        nodeCount = #nodeIDs,
    }
end

local function GetOpenNativeProfessionNodeRanks(profession)
    local testNodes = deps.GetTestOpenProfessionNodes
        and deps.GetTestOpenProfessionNodes()
        or nil
    if testNodes ~= nil then
        return testNodes, { captureMethod = "test" }
    end
    if not ResolveProfessionDef(profession) then
        return nil
    end
    if OpenProfessionMatches(profession) == false then
        return nil
    end

    local apiNodes, apiMeta = GetProfessionNodeRanksFromTraits(profession)
    if apiNodes then
        return apiNodes, apiMeta
    end

    local out = {}
    local roots = {
        ProfessionsFrame and ProfessionsFrame.SpecPage,
        ProfessionsFrame and ProfessionsFrame.CraftingPage,
        ProfessionsFrame and ProfessionsFrame.OrdersPage,
    }
    for _, root in ipairs(roots) do
        if type(root) == "table" then
            pcall(ExtractNodeRanksFromTable, root, out, {}, 0)
        end
    end

    return next(out) and out or nil, {
        source = "Blizzard_Professions",
        captureMethod = "frame-fallback",
    }
end

local function GetOpenNativeRecipeSnapshot()
    local testSnapshot = deps.GetTestOpenSnapshot and deps.GetTestOpenSnapshot() or nil
    if testSnapshot ~= nil then
        return testSnapshot
    end

    local form = ProfessionsFrame
        and ProfessionsFrame.CraftingPage
        and ProfessionsFrame.CraftingPage.SchematicForm
    if not form then
        return nil
    end

    local okRecipe, recipeInfo = pcall(function()
        if type(form.GetRecipeInfo) == "function" then
            return form:GetRecipeInfo()
        end
        return nil
    end)
    if not okRecipe or not recipeInfo or not recipeInfo.recipeID then
        return nil
    end

    local snapshot = {
        source = "native-open",
        recipeID = NormalizeRecipeID(recipeInfo.recipeID),
        recipeName = recipeInfo.name,
    }

    local okOp, operationInfo = pcall(function()
        if type(form.GetRecipeOperationInfo) == "function" then
            return form:GetRecipeOperationInfo()
        end
        return nil
    end)
    if okOp then
        ApplyOperationBonusStats(snapshot, operationInfo)
    end

    if C_TradeSkillUI and type(C_TradeSkillUI.GetTradeSkillLineForRecipe) == "function" then
        local okSkill, skillLineID, skillLineName, parentSkillLineID = pcall(function()
            return C_TradeSkillUI.GetTradeSkillLineForRecipe(snapshot.recipeID)
        end)
        if okSkill then
            snapshot.profession = skillLineName
            snapshot.skillLineID = skillLineID
            snapshot.parentSkillLineID = parentSkillLineID
        end
    end

    snapshot.profileKey = deps.InferProfileKey(
        snapshot.recipeName,
        snapshot.profession,
        snapshot.supportsMulticraft)
    return snapshot.profileKey and snapshot or nil
end

    return {
        GetOpenRecipeSnapshot = GetOpenNativeRecipeSnapshot,
        GetOpenProfessionContext = GetOpenProfessionContext,
        GetOpenProfessionDef = GetOpenProfessionDef,
        OpenProfessionMatches = OpenProfessionMatches,
        GetOpenProfessionNodeRanks = GetOpenNativeProfessionNodeRanks,
    }
end
