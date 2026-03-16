-- GoldAdvisorMidnight/Core.lua
-- Namespace init, SavedVariables setup, event backbone, DB migration.
-- Module: GAM (root)

local ADDON_NAME, GAM = ...

-- ===== Namespace =====
GAM.version   = GAM.C.ADDON_VERSION
GAM.ahOpen    = false
GAM.realmKey  = nil   -- set on PLAYER_LOGIN

-- ===== Default DB schema =====
local DB_DEFAULTS = {
    addonVersion = GAM.C.ADDON_VERSION,
    dataVersion  = GAM.C.DATA_VERSION,
    options = {
        ahCut        = GAM.C.AH_CUT,
        scanDelay    = GAM.C.DEFAULT_SCAN_DELAY,
        debugVerbosity = GAM.C.DEFAULT_VERBOSITY,
        minimapHidden  = false,
        minimapAngle   = 45,
        rankPolicy   = GAM.C.DEFAULT_RANK_POLICY,
        priceSource         = GAM.C.DEFAULT_PRICE_SOURCE,
        pigmentCostSource   = GAM.C.DEFAULT_PIGMENT_COST_SOURCE,
        -- Crafting stat overrides (integer %, 0–100; default = baked spreadsheet baseline)
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
        tailMulti        = GAM.C.DEFAULT_TAIL_MULTI,
        tailRes          = GAM.C.DEFAULT_TAIL_RES,
        bsMulti          = GAM.C.DEFAULT_BS_MULTI,
        bsRes            = GAM.C.DEFAULT_BS_RES,
        lwMulti          = GAM.C.DEFAULT_LW_MULTI,
        lwRes            = GAM.C.DEFAULT_LW_RES,
        engMulti         = GAM.C.DEFAULT_ENG_MULTI,
        engRes           = GAM.C.DEFAULT_ENG_RES,
        -- Per-profession spec node bonuses (integer %; default = value baked into spreadsheet)
        -- Used by CalculateStratMetrics to scale from the spreadsheet's baked-in stats
        -- to the user's actual spec tree allocation.
        alchMcNode       = 20,   -- Alchemy MCm node bonus baked in spreadsheet
        alchRsNode       = 0,    -- Alchemy Rs node bonus baked in spreadsheet
        enchMcNode       = 100,  -- Enchanting crafting MCm node bonus baked in spreadsheet
        enchRsNode       = 20,   -- Enchanting Rs node bonus baked in spreadsheet
        inscMcNode       = 100,  -- Inscription ink MCm node bonus baked in spreadsheet
        inscRsNode       = 55,   -- Inscription Rs node bonus baked in spreadsheet
        lwMcNode         = 50,   -- Leatherworking MCm node bonus baked in spreadsheet
        lwRsNode         = 50,   -- Leatherworking Rs node bonus baked in spreadsheet
        jcMcNode         = 50,   -- Jewelcrafting MCm node bonus baked in spreadsheet
        jcRsNode         = 50,   -- Jewelcrafting Rs node bonus baked in spreadsheet
        tailMcNode       = 40,   -- Tailoring MCm node bonus baked in spreadsheet
        tailRsNode       = 50,   -- Tailoring Rs node bonus baked in spreadsheet
        bsMcNode         = 0,    -- Blacksmithing MCm node bonus baked in spreadsheet
        bsRsNode         = 0,    -- Blacksmithing Rs node bonus baked in spreadsheet
        engMcNode        = 50,   -- Engineering MCm node bonus baked in spreadsheet
        engRsNode        = 50,   -- Engineering Rs node bonus baked in spreadsheet
        shallowFillQty      = GAM.C.DEFAULT_FILL_QTY,
        uiScale             = GAM.C.DEFAULT_UI_SCALE,
        -- New UI opt-in + per-session panel state
        useNewUI            = false,   -- false = classic MainWindow; true = MainWindowV2
        hasSeenOnboarding   = false,   -- set true after first onboarding dismiss
        leftPanelCollapsed  = false,   -- V2 left panel collapse state
        rightPanelCollapsed = false,   -- V2 right panel collapse state
    },
    patch      = {},
    priceCache = {},
    scanState  = {},
    itemKeyDB  = {},   -- persisted full AH itemKeys discovered via browse fallback
    userStrats = {},   -- user-created strategies (same schema as GAM_STRATS_MANUAL entries)
}

-- ===== Migrations =====
-- Each entry: { dataVersion = N, migrate = function(db) ... end }
local MIGRATIONS = {
    -- v2: Spreadsheet data refresh (midnight_spreadsheet_extract_updated).
    -- No schema changes; wipe price cache so stale entries for removed/renamed
    -- items don't persist. All user data (favorites, startingAmounts, overrides)
    -- is preserved.
    {
        dataVersion = 2,
        migrate = function(db)
            if type(db.priceCache) == "table" then
                wipe(db.priceCache)
            end
        end,
    },
    -- v3: Remove legacy boolean field from the scrapped "experimentalFillQty" design.
    -- The new schema uses shallowFillQty (injected by ApplyDefaults).
    {
        dataVersion = 3,
        migrate = function(db)
            if type(db.options) == "table" then
                db.options.experimentalFillQty = nil
            end
        end,
    },
    -- v4: Unify fill qty — remove shallow/deep toggle. shallowFillQty is kept as
    -- the SavedVar key for continuity. Remove shallowFillEnabled; reset qty to the
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
    -- v5: New "Dynamic Stats" spreadsheet with per-profession baked MCm/Rs constants.
    -- Wipe price cache so stale multipliers for changed strats don't persist.
    {
        dataVersion = 5,
        migrate = function(db)
            if type(db.priceCache) == "table" then
                wipe(db.priceCache)
            end
        end,
    },
}

local function RunMigrations(db)
    local current = db.dataVersion or 0
    for _, m in ipairs(MIGRATIONS) do
        if current < m.dataVersion then
            GAM.Log.Info("Migrating DB to dataVersion %d", m.dataVersion)
            local ok, err = pcall(m.migrate, db)
            if not ok then
                GAM.Log.Warn("Migration %d failed: %s", m.dataVersion, tostring(err))
            else
                db.dataVersion = m.dataVersion
            end
        end
    end
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
        }
    end
    return db.patch[patchTag]
end

-- ===== Realm key =====
function GAM:GetRealmKey()
    if self.realmKey then return self.realmKey end
    local name   = UnitName("player") or "Unknown"
    local realm  = GetRealmName() or "Unknown"
    local faction = UnitFactionGroup("player") or "Neutral"
    self.realmKey = realm .. "-" .. faction
    return self.realmKey
end

-- ===== Price cache scoped to realm =====
function GAM:GetRealmCache()
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

    -- Init SavedVariables
    GoldAdvisorMidnightDB = GoldAdvisorMidnightDB or {}
    ApplyDefaults(GoldAdvisorMidnightDB, DB_DEFAULTS)
    self.db = GoldAdvisorMidnightDB

    -- Run migrations
    RunMigrations(self.db)

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
    end

    self.Log.Info(self.L["LOADED_MSG"], GAM.C.ADDON_VERSION)

    -- Unregister — only fires once per addon
    eventFrame:UnregisterEvent("ADDON_LOADED")
end

-- ===== PLAYER_LOGIN =====
handlers["PLAYER_LOGIN"] = function(self)
    self:GetRealmKey()
    self.Log.Debug("Realm key: %s", self.realmKey)
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
        end
    end
end

-- ===== AUCTION_HOUSE_SHOW =====
handlers["AUCTION_HOUSE_SHOW"] = function(self)
    self.ahOpen = true
    self.Log.Debug("AH opened.")
    -- Open the main window automatically (routes to V2 if useNewUI is set)
    if self.UI and self.UI.MainWindow then
        self:GetActiveMainWindow().Show()
    end
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
    if self.AHScan then
        self.AHScan.OnAHClosed()
    end
end

-- ===== COMMODITY_SEARCH_RESULTS_UPDATED =====
handlers["COMMODITY_SEARCH_RESULTS_UPDATED"] = function(self, _, itemID)
    if self.AHScan then
        self.AHScan.OnCommodityResults(itemID)
    end
end

-- ===== ITEM_SEARCH_RESULTS_UPDATED =====
handlers["ITEM_SEARCH_RESULTS_UPDATED"] = function(self, _, itemKey)
    if self.AHScan then
        self.AHScan.OnItemResults(itemKey)
    end
end

-- ===== AUCTION_HOUSE_BROWSE_RESULTS_UPDATED =====
-- Fires after SendBrowseQuery completes — used for name→itemID discovery.
handlers["AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"] = function(self)
    if self.AHScan then
        self.AHScan.OnBrowseResults()
    end
end

-- Register persistent events
GAM:RegisterEvent("ADDON_LOADED")
GAM:RegisterEvent("PLAYER_LOGIN")
GAM:RegisterEvent("AUCTION_HOUSE_SHOW")
GAM:RegisterEvent("AUCTION_HOUSE_CLOSED")
GAM:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
GAM:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
GAM:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")

-- ===== Slash command =====
SLASH_GOLDADVISORMIDNIGHT1 = "/gam"
SLASH_GOLDADVISORMIDNIGHT2 = "/goldadvisor"
SlashCmdList["GOLDADVISORMIDNIGHT"] = function(input)
    local cmd = (input or ""):lower():match("^%s*(%S*)")
    if cmd == "log" then
        if GAM.UI and GAM.UI.DebugLog then
            GAM.UI.DebugLog.Toggle()
        end
    elseif cmd == "scan" then
        if not GAM.ahOpen then
            print("|cffff8800[GAM]|r " .. GAM.L["ERR_NO_AH"])
        else
            GAM.AHScan.ResetQueue()
            GAM.AHScan.QueueAllStratItems(GAM.C.DEFAULT_PATCH)
            GAM.AHScan.StartScan()
        end
    elseif cmd == "clearcache" then
        GAM:GetRealmCache()  -- ensures exists
        wipe(GAM.db.priceCache)
        GAM.Log.Info("Price cache cleared.")
        print("|cffff8800[GAM]|r Price cache cleared.")
    elseif cmd == "reload" then
        GAM.Importer.Init()
        GAM.Log.Info("Data reloaded.")
        print("|cffff8800[GAM]|r Data reloaded.")
    elseif cmd == "ids" then
        -- Open debug log then run the dump
        if GAM.UI and GAM.UI.DebugLog then
            GAM.UI.DebugLog.Show()
            GAM.UI.DebugLog.DumpItemIDs()
        end
    elseif cmd == "create" then
        if GAM.UI and GAM.UI.StratCreator then
            GAM.UI.StratCreator.Show()
        end
    else
        -- Default: toggle main window (routes to V2 if useNewUI is set)
        if GAM.UI and GAM.UI.MainWindow then
            GAM:GetActiveMainWindow().Toggle()
        end
    end
end

-- ===== UI namespace =====
GAM.UI = GAM.UI or {}

-- ===== Active main window router =====
-- Returns GAM.UI.MainWindowV2 if the new UI is enabled and loaded, else GAM.UI.MainWindow.
function GAM:GetActiveMainWindow()
    if self.db and self.db.options.useNewUI and self.UI.MainWindowV2 then
        return self.UI.MainWindowV2
    end
    return self.UI.MainWindow
end
