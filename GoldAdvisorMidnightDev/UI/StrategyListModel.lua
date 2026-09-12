-- GoldAdvisorMidnight/UI/StrategyListModel.lua
-- Pure state model for the main strategy list.

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local ListModel = {}
GAM.UI.StrategyListModel = ListModel

local MetricCache = {}
MetricCache.__index = MetricCache

function ListModel.NewMetricCache(calculate)
    assert(type(calculate) == "function", "strategy list metric cache requires a calculator")
    return setmetatable({
        calculate = calculate,
        entries = {},
        patchTag = nil,
        signature = nil,
    }, MetricCache)
end

function MetricCache:Reset(patchTag, signature)
    self.entries = {}
    self.patchTag = patchTag
    self.signature = signature
end

function MetricCache:Get(strategy, patchTag, signature)
    if not strategy then
        return nil, "strategy-unavailable"
    end
    if self.patchTag ~= patchTag or self.signature ~= signature then
        self:Reset(patchTag, signature)
    end

    local strategyID = strategy.id
    if not strategyID then
        return self.calculate(strategy, patchTag)
    end

    local cached = self.entries[strategyID]
    if cached then
        return cached.result, cached.error
    end

    local result, err = self.calculate(strategy, patchTag)
    self.entries[strategyID] = { result = result, error = err }
    return result, err
end

function MetricCache:Invalidate(strategyID, patchTag)
    if patchTag and self.patchTag ~= patchTag then
        return
    end
    if strategyID then
        self.entries[strategyID] = nil
    else
        self:Reset(self.patchTag, self.signature)
    end
end

local function CompareText(a, b, fieldName)
    return tostring(a[fieldName] or "") < tostring(b[fieldName] or "")
end

local function CompareMetric(a, b, fieldName, getMetric)
    local aMetrics = getMetric(a)
    local bMetrics = getMetric(b)
    local aValue = (aMetrics and aMetrics[fieldName]) or -math.huge
    local bValue = (bMetrics and bMetrics[fieldName]) or -math.huge
    return aValue > bValue
end

local function StableTieBreak(a, b)
    local aName = tostring(a.stratName or "")
    local bName = tostring(b.stratName or "")
    if aName ~= bName then
        return aName < bName
    end
    return tostring(a.id or "") < tostring(b.id or "")
end

function ListModel.BuildVisibleList(args)
    args = args or {}
    local matches = args.matches or function() return true end
    local isFavorite = args.isFavorite or function() return false end
    local getMetric = args.getMetric or function() return nil end
    local sortKey = args.sortKey or "roi"
    local sortAscending = args.sortAscending ~= false
    local visible = {}

    for _, strategy in ipairs(args.strategies or {}) do
        if matches(strategy) then
            visible[#visible + 1] = strategy
        end
    end

    local function ComesBefore(a, b)
        local aFavorite = isFavorite(a.id)
        local bFavorite = isFavorite(b.id)
        if aFavorite ~= bFavorite then
            return aFavorite
        end

        local before
        local reverse
        if sortKey == "stratName" or sortKey == "profession" then
            before = CompareText(a, b, sortKey)
            reverse = CompareText(b, a, sortKey)
        else
            local metricField = sortKey == "profit" and "profit" or "roi"
            before = CompareMetric(a, b, metricField, getMetric)
            reverse = CompareMetric(b, a, metricField, getMetric)
        end

        if before ~= reverse then
            if sortAscending then
                return before
            end
            return reverse
        end
        return StableTieBreak(a, b)
    end

    table.sort(visible, ComesBefore)
    return visible
end
