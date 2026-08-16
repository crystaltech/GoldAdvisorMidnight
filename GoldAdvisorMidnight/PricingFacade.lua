-- GoldAdvisorMidnight/PricingFacade.lua
-- Authoritative versioned boundary around the validated V2 pricing engine.

local ADDON_NAME, GAM = ...

local Facade = {}
GAM.PricingFacade = Facade

local function GetOpts()
    return (GAM.GetOptions and GAM:GetOptions())
        or (GAM.db and GAM.db.options)
        or {}
end

local function GetPatchDB(patchTag)
    if GAM.GetPatchDB then
        return GAM:GetPatchDB(patchTag) or {}
    end
    local db = GAM.db or {}
    local patches = db.patch or {}
    return patches[patchTag] or {}
end

local function NormalizePricingMode(value)
    local mode = tostring(value or ""):lower()
    if mode == "fixed_crafts" or mode == "fixedcrafts" or mode == "craftsim" then
        return "fixed_crafts"
    end
    return "exhaust_materials"
end

local function NormalizePricePolicy(value)
    if tostring(value or ""):lower() == "craftsim" then
        return "craftsim_then_market"
    end
    return "runtime_market"
end

local function IsVerticalIntegrationEnabled(opts)
    return (opts.pigmentCostSource == "mill")
        or (opts.ingotCostSource == "craft")
        or (opts.boltCostSource == "craft")
end

local function GetSavedBatchOverrides(strategy, patchTag)
    local patchDB = GetPatchDB(patchTag)
    local strategyID = strategy and strategy.id
    if not strategyID then
        return nil, nil
    end
    local inputOverride = patchDB.inputQtyOverrides
        and patchDB.inputQtyOverrides[strategyID]
        or nil
    local craftsOverride = patchDB.craftsOverrides
        and patchDB.craftsOverrides[strategyID]
        or nil
    return inputOverride, craftsOverride
end

function Facade.BuildCurrentRequest(strategy, patchTag, craftScale)
    local Contract = GAM.PricingContract
    if not Contract or type(Contract.BuildRequest) ~= "function" then
        return nil, "pricing-contract-unavailable"
    end

    local opts = GetOpts()
    patchTag = patchTag or ((GAM.C and GAM.C.DEFAULT_PATCH) or "midnight-1")
    local inputOverride, craftsOverride = GetSavedBatchOverrides(strategy, patchTag)
    return Contract.BuildRequest({
        strategy = strategy,
        patchTag = patchTag,
        craftScale = craftScale or 1,
        inputQuantityOverride = inputOverride,
        craftsOverride = craftsOverride,
        materialRank = opts.rankPolicy
            or ((GAM.C and GAM.C.DEFAULT_RANK_POLICY) or "lowest"),
        pricingMode = NormalizePricingMode(opts.v2PricingMode),
        inventoryPolicy = "opportunity_cost",
        pricePolicy = NormalizePricePolicy(opts.priceSource),
        useVerticalIntegration = IsVerticalIntegrationEnabled(opts),
        fillQuantity = opts.shallowFillQty
            or ((GAM.C and GAM.C.DEFAULT_FILL_QTY) or 50),
        auctionHouseCut = opts.ahCut,
    })
end

local REQUEST_SNAPSHOT_FIELDS = {
    "patchTag",
    "craftScale",
    "inputQuantityOverride",
    "craftsOverride",
    "materialRank",
    "pricingMode",
    "inventoryPolicy",
    "pricePolicy",
    "useVerticalIntegration",
    "fillQuantity",
    "auctionHouseCut",
}

local function RequestMatchesCurrentState(request)
    local current, err = Facade.BuildCurrentRequest(
        request.strategy,
        request.patchTag,
        request.craftScale)
    if not current then
        return false, err
    end
    for _, fieldName in ipairs(REQUEST_SNAPSHOT_FIELDS) do
        if request[fieldName] ~= current[fieldName] then
            return false, "request-current-state-mismatch:" .. fieldName
        end
    end
    return true
end

function Facade.Calculate(request)
    local Contract = GAM.PricingContract
    if not Contract or type(Contract.ValidateRequest) ~= "function" then
        return nil, "pricing-contract-unavailable"
    end

    local ok, err = Contract.ValidateRequest(request)
    if not ok then
        return nil, err
    end
    ok, err = RequestMatchesCurrentState(request)
    if not ok then
        return nil, err
    end

    local Pricing = GAM.Pricing
    if not Pricing or type(Pricing.CalculateStratMetricsV2) ~= "function" then
        return nil, "v2-pricing-unavailable"
    end
    local metrics = Pricing.CalculateStratMetricsV2(
        request.strategy,
        request.patchTag,
        request.craftScale)
    if not metrics then
        return nil, "v2-pricing-returned-no-result"
    end
    return Contract.FromV2Metrics(request, metrics)
end

function Facade.CalculateCurrent(strategy, patchTag, craftScale)
    local request, err = Facade.BuildCurrentRequest(strategy, patchTag, craftScale)
    if not request then
        return nil, err
    end
    return Facade.Calculate(request)
end

function Facade.GetCurrentVIBreakdown(strategy, patchTag, canonicalResult)
    local result = canonicalResult
    local err = nil
    if not result then
        result, err = Facade.CalculateCurrent(strategy, patchTag)
    end
    if not result then
        return nil, err
    end
    local Pricing = GAM.Pricing
    if not Pricing or type(Pricing.GetVIBreakdownData) ~= "function" then
        return nil, "vi-breakdown-unavailable"
    end
    return Pricing.GetVIBreakdownData(strategy, patchTag, result)
end

function Facade.GetCurrentCrushingAnalyzer(strategy, patchTag, canonicalResult)
    local result = canonicalResult
    local err = nil
    if not result then
        result, err = Facade.CalculateCurrent(strategy, patchTag)
    end
    if not result then
        return nil, err
    end
    local Pricing = GAM.Pricing
    if not Pricing or type(Pricing.GetCrushingAnalyzerData) ~= "function" then
        return nil, "crushing-analyzer-unavailable"
    end
    return Pricing.GetCrushingAnalyzerData(strategy, patchTag, result, function(alternativeStrategy)
        return Facade.CalculateCurrent(alternativeStrategy, patchTag)
    end)
end
