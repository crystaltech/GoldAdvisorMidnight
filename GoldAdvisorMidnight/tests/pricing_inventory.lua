-- Regression: VI execution planning consumes owned intermediates before
-- expanding the remaining demand into raw-material producer inputs.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {}

function wipe(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end
tinsert = table.insert
time = os.time

local function LoadGlobal(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk()
end

local function LoadModule(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk(ADDON_NAME, GAM)
end

LoadGlobal("Data/WorkbookGenerated.lua")
LoadGlobal("Data/CommodityManifest.lua")
LoadModule("Constants.lua")
LoadModule("CommodityCatalog.lua")
LoadModule("StrategyModel.lua")
LoadModule("PricingDerivation.lua")
LoadModule("PricingContract.lua")
LoadModule("PricingV2Formula.lua")
LoadModule("ReagentMixOptimizer.lua")
LoadModule("PricingV2Engine.lua")

GAM.db = {
    options = {
        rankPolicy = "highest",
        pigmentCostSource = "mill",
        ingotCostSource = "ah",
        boltCostSource = "ah",
        v2PricingMode = "fixed_crafts",
        ahCut = 0.05,
        shallowFillQty = 50,
        inscMillingRes = 30.1,
        inscInkMulti = 29.7,
        inscInkRes = 16.1,
    },
    patch = {},
    userStrats = {},
}
function GAM:GetDB() return self.db end
function GAM:GetOptions() return self.db.options end
function GAM:GetRealmCache() return {} end
function GAM:GetPatchDB(patchTag)
    patchTag = patchTag or self.C.DEFAULT_PATCH
    self.db.patch[patchTag] = self.db.patch[patchTag] or {
        startingAmounts = {}, favorites = {}, rankGroups = {}, priceOverrides = {},
        inputQtyOverrides = {}, craftsOverrides = {}, gearModes = {},
    }
    return self.db.patch[patchTag]
end
GAM.Log = { Info = function() end, Warn = function() end, Debug = function() end }

local qualities = {
    [236761] = 1, [236767] = 2,
    [236770] = 1, [236771] = 2,
    [236778] = 1, [236779] = 2,
    [245807] = 1, [245808] = 2,
    [245865] = 1, [245864] = 2,
    [245867] = 1, [245866] = 2,
    [245801] = 1, [245802] = 2,
}
C_TradeSkillUI = {
    GetItemReagentQualityByItemInfo = function(itemID) return qualities[itemID] end,
    GetItemCraftedQualityByItemInfo = function(itemID) return qualities[itemID] end,
}
C_Item = nil
GetItemInfo = function() return nil end

LoadModule("Pricing.lua")
LoadModule("Importer.lua")
LoadGlobal("Data/StratsGenerated.lua")
LoadGlobal("Data/Strategies/Patch12_1.lua")
GAM.Importer.Init()

local originalGetEffectivePrice = GAM.Pricing.GetEffectivePrice
local originalGetUnitPrice = GAM.Pricing.GetUnitPrice
GAM.Pricing.GetEffectivePrice = function() return 100, false end
GAM.Pricing.GetUnitPrice = function() return 100, false end

local owned = {
    [245808] = 36, -- Powder Pigment R2
    [245864] = 3,  -- Sanguithorn Pigment R2
    [245866] = 20, -- Mana Lily Pigment R2
    [245802] = 45, -- Existing output must not satisfy newly requested crafts
    [236767] = 7,  -- Tranquility Bloom R2
    [236779] = 1,  -- Mana Lily R2
}
GetItemCount = function(itemID)
    return owned[itemID] or 0
end

local strat = assert(GAM.Importer.GetStratByID("inscription__munsell_ink__midnight_1"))
GAM:GetPatchDB(GAM.C.DEFAULT_PATCH).craftsOverrides[strat.id] = 10
local metrics = assert(GAM.Pricing.CalculateStratMetricsV2(strat, GAM.C.DEFAULT_PATCH, 10))
local byID = {}
for _, row in ipairs(metrics.reagents or {}) do
    byID[row.itemID] = row
end

assert(byID[236767] and byID[236767].needToBuy < byID[236767].required,
    "owned Tranquility Bloom was not removed from the shopping quantity")
assert(byID[236779] and byID[236779].needToBuy < byID[236779].required,
    "owned Mana Lily was not removed from the shopping quantity")
assert((byID[236767].required or 0) < 140,
    "owned Powder Pigment was expanded into the original full herb requirement: "
        .. tostring(byID[236767].required))
assert((byID[236779].required or 0) < 40,
    "owned Mana Lily Pigment was expanded into the original full herb requirement: "
        .. tostring(byID[236779].required))

local breakdown = assert(GAM.Pricing.GetVIBreakdownData(strat, GAM.C.DEFAULT_PATCH, metrics))
local craftByName = {}
for _, entry in ipairs(breakdown.entries or {}) do
    if entry.kind == "craft" then craftByName[entry.name] = entry end
end
assert(craftByName["Powder Pigment"] and craftByName["Powder Pigment"].requiredRaw < 200,
    "VI craft step ignored owned Powder Pigment")
assert(craftByName["Mana Lily Pigment"] and craftByName["Mana Lily Pigment"].requiredRaw < 50,
    "VI craft step ignored owned Mana Lily Pigment")

GAM.Pricing.GetEffectivePrice = originalGetEffectivePrice
GAM.Pricing.GetUnitPrice = originalGetUnitPrice
local smokeOK, smokeErr = GAM.Pricing.RunSmokeChecks()
assert(smokeOK, smokeErr)

print("PASS: VI execution inventory is consumed before producer expansion")
