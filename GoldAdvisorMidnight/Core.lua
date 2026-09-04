-- GoldAdvisorMidnight/Core.lua
-- Namespace init, SavedVariables setup, event backbone, DB migration.
-- Module: GAM (root)

local ADDON_NAME, GAM = ...
local workbookProfiles = (GAM_WORKBOOK_GENERATED and GAM_WORKBOOK_GENERATED.formulaProfiles) or {}

local function ProfileDefault(profileKey, field, fallback)
    local profile = workbookProfiles[profileKey]
    local value = profile and profile[field]
    if value == nil then
        return fallback
    end
    return value
end

-- ===== Namespace =====
GAM.version   = GAM.C.ADDON_VERSION
GAM.ahOpen    = false
GAM.realmKey  = nil   -- set on PLAYER_LOGIN

-- ===== Default DB schema =====
local DB_DEFAULTS = {
    addonVersion = GAM.C.ADDON_VERSION,
    strategySchemaVersion = GAM.C.STRATEGY_SCHEMA_VERSION,
    options = {
        ahCut        = GAM.C.AH_CUT,
        scanDelay    = GAM.C.DEFAULT_SCAN_DELAY,
        debugVerbosity = GAM.C.DEFAULT_VERBOSITY,
        minimapHidden  = false,
        minimapAngle   = 45,
        rankPolicy   = GAM.C.DEFAULT_RANK_POLICY,
        priceSource         = GAM.C.DEFAULT_PRICE_SOURCE,
        pigmentCostSource   = GAM.C.DEFAULT_PIGMENT_COST_SOURCE,
        boltCostSource      = GAM.C.DEFAULT_BOLT_COST_SOURCE,
        ingotCostSource     = GAM.C.DEFAULT_INGOT_COST_SOURCE,
        -- Crafting stat overrides (percent values, 0–100; decimals allowed; default = workbook baseline)
        -- Milling, Prospecting, Crushing, Shattering have no Multicraft stat.
        inscMillingRes   = GAM.C.DEFAULT_INSC_MILLING_RES,
        inscInkMulti     = GAM.C.DEFAULT_INSC_INK_MULTI,
        inscInkRes       = GAM.C.DEFAULT_INSC_INK_RES,
        jcProspectRes    = GAM.C.DEFAULT_JC_PROSPECT_RES,
        jcCrushRes       = GAM.C.DEFAULT_JC_CRUSH_RES,
        jcCraftMulti     = GAM.C.DEFAULT_JC_CRAFT_MULTI,
        jcCraftRes       = GAM.C.DEFAULT_JC_CRAFT_RES,
        enchShatterRes   = GAM.C.DEFAULT_ENCH_SHATTER_RES,
        enchCraftMulti   = GAM.C.DEFAULT_ENCH_CRAFT_MULTI,
        enchCraftRes     = GAM.C.DEFAULT_ENCH_CRAFT_RES,
        alchMulti        = GAM.C.DEFAULT_ALCH_MULTI,
        alchRes          = GAM.C.DEFAULT_ALCH_RES,
        cookMulti        = GAM.C.DEFAULT_COOK_MULTI,
        cookRes          = GAM.C.DEFAULT_COOK_RES,
        tailMulti        = GAM.C.DEFAULT_TAIL_MULTI,
        tailRes          = GAM.C.DEFAULT_TAIL_RES,
        bsMulti          = GAM.C.DEFAULT_BS_MULTI,
        bsRes            = GAM.C.DEFAULT_BS_RES,
        lwMulti          = GAM.C.DEFAULT_LW_MULTI,
        lwRes            = GAM.C.DEFAULT_LW_RES,
        engRecycleRes    = GAM.C.DEFAULT_ENG_RECYCLE_RES,
        engCraftMulti    = GAM.C.DEFAULT_ENG_CRAFT_MULTI,
        engCraftRes      = GAM.C.DEFAULT_ENG_CRAFT_RES,
        -- Per-profession spec node bonuses (percent values; default = value baked into spreadsheet)
        -- Used by canonical pricing to scale from the spreadsheet's baked-in stats
        -- to the user's actual spec tree allocation.
        alchMcNode       = ProfileDefault("alchemy", "defaultMcNode", 20),
        alchRsNode       = ProfileDefault("alchemy", "defaultRsNode", 0),
        enchMcNode       = ProfileDefault("ench_craft", "defaultMcNode", 100),
        enchRsNode       = ProfileDefault("ench_craft", "defaultRsNode", 20),
        inscMcNode       = ProfileDefault("insc_ink", "defaultMcNode", 100),
        inscRsNode       = ProfileDefault("insc_ink", "defaultRsNode", 55),
        lwMcNode         = ProfileDefault("leatherworking", "defaultMcNode", 50),
        lwRsNode         = ProfileDefault("leatherworking", "defaultRsNode", 50),
        jcMcNode         = ProfileDefault("jc_craft", "defaultMcNode", 50),
        jcRsNode         = ProfileDefault("jc_craft", "defaultRsNode", 50),
        tailMcNode       = ProfileDefault("tailoring", "defaultMcNode", 40),
        tailRsNode       = ProfileDefault("tailoring", "defaultRsNode", 50),
        bsMcNode         = ProfileDefault("blacksmithing", "defaultMcNode", 0),
        bsRsNode         = ProfileDefault("blacksmithing", "defaultRsNode", 0),
        engMcNode        = ProfileDefault("engineering_craft", "defaultMcNode", 100),
        engRsNode        = ProfileDefault("engineering_craft", "defaultRsNode", 45),
        shallowFillQty      = GAM.C.DEFAULT_FILL_QTY,
        uiScale             = GAM.C.DEFAULT_UI_SCALE,
        v2Theme             = "classic",
        v2PricingMode        = GAM.C.DEFAULT_V2_PRICING_MODE,
        -- Per-session panel state
        hasSeenOnboarding   = false,   -- set true after first onboarding dismiss
        leftPanelCollapsed  = false,   -- left panel collapse state
        rightPanelCollapsed = false,   -- right panel collapse state
        compactMode         = false,   -- show only strategy detail panel
        -- AH window behavior
        rememberAHWindowState = true,  -- reopen on AH open if the window was last left open
        lastAHWindowOpen    = true,    -- remembered main window state across AH sessions
    },
    patch      = {},
    priceCache = {},
    scanState  = {},
    itemKeyDB  = {},   -- persisted full AH itemKeys discovered via browse fallback
    vendorPriceCache = {
        version = 1,
        characters = {},
    },
    v2StatCache = {
        version = 2,
        characters = {},
    },
    userStrats = {},   -- user-created strategies (same schema as GAM_STRATS_MANUAL entries)
}

-- ===== Migrations =====
-- Each entry: { dataVersion = N, migrate = function(db) ... end }
local MIGRATIONS = {
    -- dataVersion 2: Spreadsheet data refresh.
    -- No schema changes; wipe price cache so stale entries for removed/renamed
    -- items don't persist. Favorites, startingAmounts, and overrides are preserved.
    {
        dataVersion = 2,
        migrate = function(db)
            if type(db.priceCache) == "table" then
                wipe(db.priceCache)
            end
        end,
    },
    -- dataVersion 3: Remove legacy experimentalFillQty field from scrapped fill-qty design.
    -- The new schema uses shallowFillQty (injected by ApplyDefaults).
    {
        dataVersion = 3,
        migrate = function(db)
            if type(db.options) == "table" then
                db.options.experimentalFillQty = nil
            end
        end,
    },
    -- dataVersion 4: Unify fill qty — remove shallow/deep toggle. shallowFillQty kept
    -- as the SavedVar key for continuity. Remove shallowFillEnabled; reset qty to the
    -- new default (50) so all users start fresh.
    {
        dataVersion = 4,
        migrate = function(db)
            if type(db.options) == "table" then
                db.options.shallowFillEnabled = nil
                -- Reset everyone to new default (50). Old default was 1,000 and
                -- users who never changed it should start fresh at the new value.
                db.options.shallowFillQty = GAM.C.DEFAULT_FILL_QTY
            end
        end,
    },
    -- dataVersion 5: New Dynamic Stats spreadsheet with per-profession baked MCm/Rs constants.
    -- Wipe price cache so stale multipliers for changed strats don't persist.
    {
        dataVersion = 5,
        migrate = function(db)
            if type(db.priceCache) == "table" then
                wipe(db.priceCache)
            end
        end,
    },
    -- dataVersion 6: Formula redesign — output qty now uses baseYieldMultiplier directly
    -- instead of baked qtyMultiplier scaled from a baseline. Wipe price cache so cached
    -- net revenue values are recalculated with the new multipliers.
    {
        dataVersion = 6,
        migrate = function(db)
            if type(db.priceCache) == "table" then
                wipe(db.priceCache)
            end
        end,
    },
    {
        -- dataVersion 7: Strat/formula data refresh. Wipe price cache for clean recalculation.
        dataVersion = 7,
        migrate = function(db)
            if type(db.priceCache) == "table" then
                wipe(db.priceCache)
            end
        end,
    },
    {
        dataVersion = 8,
        migrate = function(db)
            -- dataVersion 8: Wipe stored raw order-book arrays (.raw fields) from price cache.
            -- These were persisted by StoreRaw() and caused progressive SavedVariables bloat.
            -- Stored avg prices (.price / .ts) are preserved.
            if type(db.priceCache) == "table" then
                for _, realmTable in pairs(db.priceCache) do
                    if type(realmTable) == "table" then
                        for _, entry in pairs(realmTable) do
                            if type(entry) == "table" then
                                entry.raw = nil
                            end
                        end
                    end
                end
            end
        end,
    },
    {
        dataVersion = 9,
        migrate = function(db)
            -- dataVersion 9: Reset compact mode — the compact button had a wrong offset that
            -- caused accidental activation. Force it off so layout is not stuck compact on
            -- first load after upgrade.
            if type(db.options) == "table" then
                db.options.compactMode = false
            end
        end,
    },
    {
        -- dataVersion 10: Replace autoOpenWithAH with rememberAHWindowState.
        -- Migrate existing value so users keep their preference.
        dataVersion = 10,
        migrate = function(db)
            if type(db.options) == "table" then
                local opts = db.options
                if opts.rememberAHWindowState == nil then
                    opts.rememberAHWindowState = (opts.autoOpenWithAH ~= false)
                end
                if opts.lastAHWindowOpen == nil then
                    opts.lastAHWindowOpen = (opts.autoOpenWithAH ~= false)
                end
                opts.autoOpenWithAH = nil
            end
        end,
    },
    {
        -- dataVersion 11: Remove closeWithAH option (feature removed).
        dataVersion = 11,
        migrate = function(db)
            if type(db.options) == "table" then
                db.options.closeWithAH = nil
            end
        end,
    },
    {
        -- dataVersion 12: Split Engineering stat keys and carry forward stale
        -- workbook-baseline defaults to the live-sheet baseline without
        -- overwriting user-customized values.
        dataVersion = 12,
        migrate = function(db)
            if type(db.options) ~= "table" then
                return
            end

            local opts = db.options
            local function approxEqual(value, expected)
                local num = tonumber(value)
                return num ~= nil and math.abs(num - expected) < 0.001
            end

            if opts.engRes ~= nil then
                if opts.engRecycleRes == nil or approxEqual(opts.engRecycleRes, GAM.C.DEFAULT_ENG_RECYCLE_RES) then
                    opts.engRecycleRes = opts.engRes
                end
                if opts.engCraftRes == nil or approxEqual(opts.engCraftRes, GAM.C.DEFAULT_ENG_CRAFT_RES) then
                    opts.engCraftRes = opts.engRes
                end
            end

            if opts.engMulti ~= nil then
                if opts.engCraftMulti == nil or approxEqual(opts.engCraftMulti, GAM.C.DEFAULT_ENG_CRAFT_MULTI) then
                    opts.engCraftMulti = opts.engMulti
                end
            end

            opts.engRes = nil
            opts.engMulti = nil

            if approxEqual(opts.inscInkMulti, 25.9) then
                opts.inscInkMulti = 29.7
            end
            if approxEqual(opts.lwMulti, 28.2) then
                opts.lwMulti = 32.0
            end
            if approxEqual(opts.jcCrushRes, 35.0) then
                opts.jcCrushRes = 33.0
            end
        end,
    },
    {
        -- dataVersion 13: Refresh Blacksmithing to the live workbook baseline
        -- without overwriting clearly user-customized values.
        dataVersion = 13,
        migrate = function(db)
            if type(db.options) ~= "table" then
                return
            end

            local opts = db.options
            local function approxEqual(value, expected)
                local num = tonumber(value)
                return num ~= nil and math.abs(num - expected) < 0.001
            end

            if approxEqual(opts.bsMulti, 27.9) then
                opts.bsMulti = 33.0
            end
            if opts.bsMcNode == nil or approxEqual(opts.bsMcNode, 0.0) then
                opts.bsMcNode = 12
            end
        end,
    },
    {
        -- dataVersion 14: Add explicit V2 formula economics mode.
        dataVersion = 14,
        migrate = function(db)
            if type(db.options) == "table" and db.options.v2PricingMode == nil then
                db.options.v2PricingMode = GAM.C.DEFAULT_V2_PRICING_MODE
            end
        end,
    },
    {
        -- dataVersion 15: Default to the live craft-count model so expected
        -- output matches pressing Craft N times in CraftSim/WoW.
        dataVersion = 15,
        migrate = function(db)
            if type(db.options) ~= "table" then
                return
            end

            local opts = db.options
            if opts.pricingEngine == nil or opts.pricingEngine == "legacy" then
                opts.pricingEngine = "v2"
            end
            if opts.v2PricingMode == nil or opts.v2PricingMode == "fixed_input" then
                opts.v2PricingMode = GAM.C.DEFAULT_V2_PRICING_MODE
            end
        end,
    },
    {
        -- dataVersion 16: Mark the canonical commodity strategy schema. User
        -- strategies remain byte-for-byte intact; Importer creates runtime
        -- models without rewriting SavedVariables.
        dataVersion = 16,
        migrate = function(db)
            db.strategySchemaVersion = GAM.C.STRATEGY_SCHEMA_VERSION
            if type(db.userStrats) ~= "table" then
                db.userStrats = {}
            end
        end,
    },
    {
        -- dataVersion 17: The commodity mass-crafting model replaces the first
        -- V2 fixed-input approximation. Keep Fixed Crafts available as a
        -- comparison mode, but make Exhaust Materials the active refocus default.
        dataVersion = 17,
        migrate = function(db)
            if type(db.options) ~= "table" then
                db.options = {}
            end
            db.options.v2PricingMode = GAM.C.DEFAULT_V2_PRICING_MODE
        end,
    },
    {
        -- dataVersion 18: Every production consumer now uses PricingFacade.
        -- Retire the user-selectable legacy engine flag before deleting the
        -- spreadsheet-era calculator and comparison diagnostic.
        dataVersion = 18,
        migrate = function(db)
            if type(db.options) == "table" then
                db.options.pricingEngine = nil
            end
        end,
    },
}

local function RunMigrations(db)
    for _, m in ipairs(MIGRATIONS) do
        local current = tonumber(db.dataVersion) or 0
        if current < m.dataVersion then
            GAM.Log.Info("Migrating DB to dataVersion %d", m.dataVersion)
            local ok, err = pcall(m.migrate, db)
            if not ok then
                GAM.Log.Warn("Migration %d failed: %s", m.dataVersion, tostring(err))
                return false, err
            else
                db.dataVersion = m.dataVersion
            end
        end
    end
    return true
end

-- ===== Deep-merge defaults into target =====
local function ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                ApplyDefaults(target[k], v)
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            ApplyDefaults(target[k], v)
        end
    end
end

-- ===== Patch scope helper =====
function GAM:GetPatchDB(patchTag)
    if self.State and self.State.GetPatchDB then
        return self.State.GetPatchDB(patchTag)
    end
    patchTag = patchTag or self.C.DEFAULT_PATCH
    local db  = self.db
    db.patch  = db.patch or {}
    if not db.patch[patchTag] then
        db.patch[patchTag] = {
            startingAmounts = {},
            favorites       = {},
            rankGroups      = {},
            priceOverrides    = {},
            inputQtyOverrides = {},
            craftsOverrides   = {},
            gearModes         = {},
        }
    end
    return db.patch[patchTag]
end

-- ===== Realm key =====
function GAM:GetRealmKey()
    if self.realmKey then return self.realmKey end
    local realm  = GetRealmName() or "Unknown"
    local faction = UnitFactionGroup("player") or "Neutral"
    self.realmKey = realm .. "-" .. faction
    return self.realmKey
end

-- ===== Price cache scoped to realm =====
function GAM:GetRealmCache()
    if self.State and self.State.GetRealmCache then
        return self.State.GetRealmCache()
    end
    local key = self:GetRealmKey()
    self.db.priceCache        = self.db.priceCache or {}
    self.db.priceCache[key]   = self.db.priceCache[key] or {}
    return self.db.priceCache[key]
end

-- ===== Event frame =====
local eventFrame = CreateFrame("Frame")
GAM._eventFrame  = eventFrame

local handlers = {}

function GAM:RegisterEvent(event, fn)
    handlers[event] = fn or handlers[event]
    eventFrame:RegisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local h = handlers[event]
    if h then
        local ok, err = pcall(h, GAM, event, ...)
        if not ok then
            GAM.Log.Warn("Event %s error: %s", event, tostring(err))
        end
    end
end)

-- ===== ADDON_LOADED =====
handlers["ADDON_LOADED"] = function(self, _, name)
    if name ~= ADDON_NAME then return end

    -- Initialize only the containers migrations need. Full defaults must come
    -- afterward so they cannot mask legacy values a migration needs to inspect.
    GoldAdvisorMidnightDB = GoldAdvisorMidnightDB or {}
    self.db = GoldAdvisorMidnightDB
    self.db.options = type(self.db.options) == "table" and self.db.options or {}

    local migrationsOK = RunMigrations(self.db)
    if not migrationsOK then
        GAM.Log.Warn("Database migration stopped; defaults will fill only missing fields")
    end
    ApplyDefaults(self.db, DB_DEFAULTS)

    -- Update addonVersion in DB
    self.db.addonVersion = GAM.C.ADDON_VERSION

    -- Init Log with saved options
    local opts = self.db.options
    self.Log.Init(self.C.LOG_RING_SIZE, opts.debugVerbosity)

    -- Init Importer (loads strat tables)
    self.Importer.Init()

    -- Init Minimap
    self.Minimap.Init()

    -- Init Settings (after Minimap so the button exists)
    if self.Settings then self.Settings.Init() end

    -- Apply saved scan delay so the first scan uses the user's preference,
    -- not the compiled constant (AHScan captures the constant at load time).
    if self.AHScan then
        self.AHScan.SetScanDelay(opts.scanDelay)
        -- Centralized scan progress callback: routed through GetActiveMainWindow so all
        -- progress events reach MainWindow without individual files registering separately.
        self.AHScan.SetProgressCallback(function(done, total, isComplete)
            local win = self:GetActiveMainWindow()
            if win and win.OnScanProgress then
                win.OnScanProgress(done, total, isComplete)
            end
        end)
    end

    self.Log.Info(self.L["LOADED_MSG"], GAM.C.ADDON_VERSION)

    -- Unregister — only fires once per addon
    eventFrame:UnregisterEvent("ADDON_LOADED")
end

-- ===== PLAYER_LOGIN =====
handlers["PLAYER_LOGIN"] = function(self)
    self:GetRealmKey()
    self.Log.Debug("Realm key: %s", self.realmKey)
    if self.DataBroker and self.DataBroker.Init then
        self.DataBroker.Init()
    end
    if self.CooldownTracker and self.CooldownTracker.Init then
        self.CooldownTracker.Init()
    end

    if self.QuickBuy and self.QuickBuy.Init then
        self.QuickBuy.Init()
    end
    -- Pre-warm WoW item cache for all strat itemIDs so crafting quality API
    -- calls (used by ARP Export) return correct data on first use.
    if self.Importer and self.Importer.GetAllStrats then
        local seen = {}
        for _, strat in ipairs(self.Importer.GetAllStrats()) do
            local function touch(item)
                if item and item.itemIDs then
                    for _, id in ipairs(item.itemIDs) do
                        if not seen[id] then
                            seen[id] = true
                            GetItemInfo(id)
                        end
                    end
                end
            end
            touch(strat.output)
            for _, o in ipairs(strat.outputs or {}) do touch(o) end
            for _, r in ipairs(strat.reagents or {}) do touch(r) end
            for _, variant in pairs(strat.rankVariants or {}) do
                touch(variant.output)
                for _, o in ipairs(variant.outputs or {}) do touch(o) end
                for _, r in ipairs(variant.reagents or {}) do touch(r) end
            end
        end
    end
end

-- ===== AH mini-button =====
-- Small circle button on AuctionHouseFrame. Shows only when auto-open is disabled.
-- Lazy-created on first AH open so AuctionHouseFrame is guaranteed to exist.
local ahBtn
local function GetOrCreateAHButton()
    if ahBtn then return ahBtn end
    ahBtn = CreateFrame("Button", "GAMAHButton", AuctionHouseFrame)
    ahBtn:SetSize(26, 26)
    local closeBtn = AuctionHouseFrame.CloseButton or _G["AuctionHouseFrameCloseButton"]
    if closeBtn then
        ahBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    else
        ahBtn:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -30, -4)
    end
    ahBtn:SetFrameStrata("HIGH")
    ahBtn:SetFrameLevel(AuctionHouseFrame:GetFrameLevel() + 5)
    local bg = ahBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = ahBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\inv_misc_coin_01")
    local hl = ahBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    hl:SetAlpha(0.4)
    ahBtn:SetScript("OnClick", function()
        if GAM.UI and GAM.UI.MainWindow then GAM.UI.MainWindow.Toggle() end
    end)
    ahBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(GAM.L["AH_BTN_TITLE"], 1, 0.82, 0, 1)
        GameTooltip:AddLine(GAM.L["AH_BTN_TIP"], 0.8, 0.8, 0.8, 1)
        GameTooltip:Show()
    end)
    ahBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ahBtn:Hide()
    return ahBtn
end

-- ===== AUCTION_HOUSE_SHOW =====
handlers["AUCTION_HOUSE_SHOW"] = function(self)
    self.ahOpen = true
    self.Log.Debug("AH opened.")
    local opts = self.db and self.db.options
    if self.UI and self.UI.MainWindow
            and (opts == nil or opts.rememberAHWindowState ~= false)
            and (opts == nil or opts.lastAHWindowOpen ~= false) then
        self.UI.MainWindow.Show()
    end
    GetOrCreateAHButton():Show()
    -- Pre-warm itemKey cache from persisted DB (skips slow browse on subsequent scans)
    if self.AHScan and self.AHScan.PreWarmCache then
        self.AHScan.PreWarmCache()
    end
    -- Resume scan if interrupted by AH close (flag set by AHScan.OnAHClosed).
    if self.AHScan and self.AHScan._pendingResume then
        self.AHScan.StartScan()
        self.AHScan._pendingResume = false
    end
end

-- ===== AUCTION_HOUSE_CLOSED =====
handlers["AUCTION_HOUSE_CLOSED"] = function(self)
    self.ahOpen = false
    self.Log.Debug("AH closed.")
    if self.QuickBuy and self.QuickBuy.Reset then
        self.QuickBuy.Reset()
    end
    if self.AHScan then
        self.AHScan.OnAHClosed()
    end
    if ahBtn then ahBtn:Hide() end
end

-- ===== COMMODITY_SEARCH_RESULTS_UPDATED =====
handlers["COMMODITY_SEARCH_RESULTS_UPDATED"] = function(self, _, itemID)
    if self.AHScan then
        self.AHScan.OnCommodityResults(itemID)
    end
end

handlers["COMMODITY_SEARCH_RESULTS_ADDED"] = handlers["COMMODITY_SEARCH_RESULTS_UPDATED"]

handlers["COMMODITY_SEARCH_RESULTS_RECEIVED"] = function(self)
    if self.AHScan and self.AHScan.OnCommodityResultsReceived then
        self.AHScan.OnCommodityResultsReceived()
    end
end

-- ===== ITEM_SEARCH_RESULTS_UPDATED =====
handlers["ITEM_SEARCH_RESULTS_UPDATED"] = function(self, _, itemKey)
    if self.AHScan then
        self.AHScan.OnItemResults(itemKey)
    end
end

handlers["ITEM_SEARCH_RESULTS_ADDED"] = handlers["ITEM_SEARCH_RESULTS_UPDATED"]

handlers["AUCTION_HOUSE_NEW_RESULTS_RECEIVED"] = function(self, _, itemKey)
    if self.AHScan and self.AHScan.OnNewResults then
        self.AHScan.OnNewResults(itemKey)
    end
end

handlers["AUCTION_HOUSE_THROTTLED_SYSTEM_READY"] = function(self)
    if self.AHScan and self.AHScan.OnThrottleReady then
        self.AHScan.OnThrottleReady()
    end
end

handlers["AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED"] = function(self)
    if self.AHScan and self.AHScan.OnThrottleMessageDropped then
        self.AHScan.OnThrottleMessageDropped()
    end
end

handlers["AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED"] = function(self)
    if self.AHScan and self.AHScan.OnThrottleResponseReceived then
        self.AHScan.OnThrottleResponseReceived()
    end
end

-- ===== AUCTION_HOUSE_BROWSE_RESULTS_UPDATED =====
-- Fires after SendBrowseQuery completes — used for name→itemID discovery.
handlers["AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"] = function(self)
    if self.AHScan then
        self.AHScan.OnBrowseResults()
    end
end

handlers["COMMODITY_PRICE_UPDATED"] = function(self, _, unitPrice, totalPrice)
    if self.QuickBuy and self.QuickBuy.OnPriceUpdated then
        self.QuickBuy.OnPriceUpdated(unitPrice, totalPrice)
    end
end

handlers["COMMODITY_PRICE_UNAVAILABLE"] = function(self)
    if self.QuickBuy and self.QuickBuy.OnPriceUnavailable then
        self.QuickBuy.OnPriceUnavailable()
    end
end

handlers["COMMODITY_PURCHASE_SUCCEEDED"] = function(self)
    if self.QuickBuy and self.QuickBuy.OnPurchaseSucceeded then
        self.QuickBuy.OnPurchaseSucceeded()
    end
end

handlers["COMMODITY_PURCHASE_FAILED"] = function(self)
    if self.QuickBuy and self.QuickBuy.OnPurchaseFailed then
        self.QuickBuy.OnPurchaseFailed()
    end
end

-- Register persistent events
GAM:RegisterEvent("ADDON_LOADED")
GAM:RegisterEvent("PLAYER_LOGIN")
GAM:RegisterEvent("AUCTION_HOUSE_SHOW")
GAM:RegisterEvent("AUCTION_HOUSE_CLOSED")
GAM:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
GAM:RegisterEvent("COMMODITY_SEARCH_RESULTS_ADDED")
GAM:RegisterEvent("COMMODITY_SEARCH_RESULTS_RECEIVED")
GAM:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
GAM:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED")
GAM:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
GAM:RegisterEvent("AUCTION_HOUSE_NEW_RESULTS_RECEIVED")
GAM:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
GAM:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
GAM:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED")
GAM:RegisterEvent("COMMODITY_PRICE_UPDATED")
GAM:RegisterEvent("COMMODITY_PRICE_UNAVAILABLE")
GAM:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
GAM:RegisterEvent("COMMODITY_PURCHASE_FAILED")

-- ===== Slash command =====
SLASH_GOLDADVISORMIDNIGHT1 = "/gam"
SLASH_GOLDADVISORMIDNIGHT2 = "/goldadvisor"
SlashCmdList["GOLDADVISORMIDNIGHT"] = function(input)
    local rawInput = input or ""
    local cmd = rawInput:lower():match("^%s*(%S*)")
    if cmd == "log" then
        if GAM.UI and GAM.UI.DebugLog then
            GAM.UI.DebugLog.Toggle()
        end
    elseif cmd == "help" then
        print("|cffff8800[GAM]|r " .. GAM.L["MSG_COMMAND_HELP"])
    elseif cmd == "" then
        if GAM.UI and GAM.UI.MainWindow then
            GAM.UI.MainWindow.Toggle()
        end
    else
        print("|cffff8800[GAM]|r " .. GAM.L["MSG_UNKNOWN_COMMAND"])
    end
end

-- ===== UI namespace =====
GAM.UI = GAM.UI or {}

function GAM:GetActiveMainWindow()
    return self.UI.MainWindow
end
