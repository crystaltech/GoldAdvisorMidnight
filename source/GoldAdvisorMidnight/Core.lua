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
        tailMulti        = GAM.C.DEFAULT_TAIL_MULTI,
        tailRes          = GAM.C.DEFAULT_TAIL_RES,
        bsMulti          = GAM.C.DEFAULT_BS_MULTI,
        bsRes            = GAM.C.DEFAULT_BS_RES,
        lwMulti          = GAM.C.DEFAULT_LW_MULTI,
        lwRes            = GAM.C.DEFAULT_LW_RES,
        engMulti         = GAM.C.DEFAULT_ENG_MULTI,
        engRes           = GAM.C.DEFAULT_ENG_RES,
        -- Per-profession spec node bonuses (percent values; default = value baked into spreadsheet)
        -- Used by CalculateStratMetrics to scale from the spreadsheet's baked-in stats
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
        engMcNode        = ProfileDefault("engineering", "defaultMcNode", 50),
        engRsNode        = ProfileDefault("engineering", "defaultRsNode", 50),
        shallowFillQty      = GAM.C.DEFAULT_FILL_QTY,
        uiScale             = GAM.C.DEFAULT_UI_SCALE,
        -- Per-session panel state
        hasSeenOnboarding   = false,   -- set true after first onboarding dismiss
        leftPanelCollapsed  = false,   -- left panel collapse state
        rightPanelCollapsed = false,   -- right panel collapse state
        compactMode         = false,   -- show only strategy detail panel
        -- AH window behavior
        autoOpenWithAH      = true,    -- open addon window when AH opens
        closeWithAH         = false,   -- close addon window when AH closes
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
    -- v6: Formula redesign — output quantities now computed directly from baseYieldMultiplier
    -- (B) instead of baked qtyMultiplier scaled from a baseline. Wipe price cache so any
    -- cached net revenue values (which used the old multipliers) are recalculated.
    {
        dataVersion = 6,
        migrate = function(db)
            if type(db.priceCache) == "table" then
                wipe(db.priceCache)
            end
        end,
    },
    {
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
            -- Wipe stored raw order-book arrays (.raw fields) from all price cache entries.
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
            -- Reset compact mode: the v1.5.0 compact button had a wrong offset that caused
            -- accidental activation. Force it off so the layout is not stuck in compact on
            -- first load after upgrade.
            if type(db.options) == "table" then
                db.options.compactMode = false
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

-- ===== Auctionator Quick Buy =====
GAM.quickBuyList = GAM.quickBuyList or nil
GAM.quickBuyState = {
    active = false,
    searchPending = false,
    searchRetries = 0,
    resultRows = {},
    currentSearchString = nil,
    pendingItemID = nil,
    pendingQty = nil,
    confirmSent = false,   -- prevents double-buy from THROTTLED_SYSTEM_READY firing multiple times
}

local function ResetQuickBuy(silent)
    local qb = GAM.quickBuyState
    qb.active = false
    qb.searchPending = false
    qb.searchRetries = 0
    qb.resultRows = {}
    qb.currentSearchString = nil
    qb.pendingItemID = nil
    qb.pendingQty = nil
    qb.confirmSent = false
    if not silent then
        print("|cffff8800[GAM]|r Auctionator quick buy stopped.")
    end
end

local function GetQuickBuyContext()
    if not GAM.ahOpen then
        return nil, "Open the Auction House first."
    end
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        return nil, "Auctionator is required for quick buy."
    end
    if not AuctionatorShoppingFrame then
        return nil, "Open the Auctionator Shopping tab first."
    end
    if not GAM.quickBuyList or not GAM.quickBuyList.entries or #GAM.quickBuyList.entries == 0 then
        return nil, "Create a GAM shopping list first."
    end
    local listName = GAM.quickBuyList.listName or (GAM.L and GAM.L["AUCTIONATOR_LIST_NAME"]) or "Gold Advisor Midnight"
    local listManager = Auctionator.Shopping and Auctionator.Shopping.ListManager
    local listIndex = listManager and listManager:GetIndexForName(listName)
    if not listIndex then
        return nil, "Create a GAM shopping list first."
    end
    local list = listManager:GetByIndex(listIndex)
    if not list then
        return nil, "Create a GAM shopping list first."
    end
    return {
        listName = listName,
        list = list,
        listsContainer = AuctionatorShoppingFrame.ListsContainer,
        resultsList = AuctionatorShoppingFrame.ResultsListing,
        searchStrings = list:GetAllItems() or {},
        entries = GAM.quickBuyList.entries,
    }
end

local function MapQuickBuyResultRows(entries, resultsList)
    local mapped = {}
    if not resultsList or not resultsList.dataProvider then
        return mapped, false
    end
    local rows = {}
    local used = {}
    for i = 1, resultsList.dataProvider:GetCount() do
        rows[#rows + 1] = resultsList.dataProvider:GetEntryAt(i)
    end
    local allMatched = true
    for _, entry in ipairs(entries or {}) do
        local match
        for idx, row in ipairs(rows) do
            if not used[idx] and row and row.itemKey and row.itemKey.itemID == entry.itemID then
                match = row
                used[idx] = true
                break
            end
        end
        if match then
            mapped[entry.searchString] = match
        else
            allMatched = false
        end
    end
    return mapped, allMatched
end

local AdvanceQuickBuy
AdvanceQuickBuy = function()
    local qb = GAM.quickBuyState
    if not qb.active then return end

    local ctx, err = GetQuickBuyContext()
    if not ctx then
        ResetQuickBuy(true)
        print("|cffff8800[GAM]|r " .. err)
        return
    end

    if #ctx.searchStrings == 0 or #ctx.entries == 0 then
        ResetQuickBuy(true)
        print("|cffff8800[GAM]|r No items left in the GAM shopping list.")
        return
    end

    if ctx.listsContainer and ctx.listsContainer.IsListExpanded and not ctx.listsContainer:IsListExpanded(ctx.list) then
        ctx.listsContainer:ExpandList(ctx.list)
    end

    -- Try to use existing Auctionator results before triggering a new search.
    -- If results for all remaining items are still in the pane, buy immediately.
    local allMatched
    qb.resultRows, allMatched = MapQuickBuyResultRows(ctx.entries, ctx.resultsList)

    if not allMatched then
        -- Results unavailable — search only if not already pending
        if not qb.searchPending then
            qb.searchPending = true
            qb.searchRetries = 0
            AuctionatorShoppingFrame:DoSearch(ctx.searchStrings)
        end
        if qb.searchRetries >= 20 then
            ResetQuickBuy(true)
            print("|cffff8800[GAM]|r Quick buy timed out waiting for Auctionator search results.")
            return
        end
        qb.searchRetries = qb.searchRetries + 1
        C_Timer.After(0.20, function()
            AdvanceQuickBuy()
        end)
        return
    end

    qb.searchPending = false
    qb.searchRetries = 0

    local nextEntry = ctx.entries[1]
    local row = nextEntry and qb.resultRows[nextEntry.searchString]
    if not row or not row.itemKey or not row.purchaseQuantity or row.purchaseQuantity <= 0 then
        ResetQuickBuy(true)
        print("|cffff8800[GAM]|r Quick buy only works for commodity rows with an available purchase quantity.")
        return
    end

    qb.currentSearchString = nextEntry.searchString
    qb.pendingItemID = row.itemKey.itemID
    qb.pendingQty = row.purchaseQuantity
    qb.confirmSent = false
    C_AuctionHouse.StartCommoditiesPurchase(qb.pendingItemID, qb.pendingQty)
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
        -- Centralized scan progress callback: routed through GetActiveMainWindow so all
        -- progress events reach MainWindowV2 without individual files registering separately.
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

    -- Hidden button for QuickBuy macro support.
    -- Users create an in-game macro with:  /click GAMQuickBuyBtn
    -- Each keypress provides a hardware event, satisfying the AH purchase requirement.
    local qbBtn = CreateFrame("Button", "GAMQuickBuyBtn", UIParent)
    qbBtn:SetSize(1, 1)
    qbBtn:SetAlpha(0)
    qbBtn:SetPoint("CENTER", UIParent, "CENTER", 9999, 9999)
    qbBtn:SetScript("OnClick", function()
        if not GAM.quickBuyState.active then
            -- Auto-arm on first press if a shopping list is ready
            if not GAM.quickBuyList or not GAM.quickBuyList.entries or #GAM.quickBuyList.entries == 0 then
                print("|cffff8800[GAM]|r No shopping list loaded. Open a strategy and click Shopping List first.")
                return
            end
            GAM.quickBuyState.active = true
        end
        AdvanceQuickBuy()
    end)
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
        if GAM.UI and GAM.UI.MainWindowV2 then GAM.UI.MainWindowV2.Toggle() end
    end)
    ahBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Gold Advisor", 1, 0.82, 0, 1)
        GameTooltip:AddLine("Click to show/hide", 0.8, 0.8, 0.8, 1)
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
    if self.UI and self.UI.MainWindowV2 and (opts == nil or opts.autoOpenWithAH ~= false) then
        self.UI.MainWindowV2.Show()
    end
    -- Show AH button only when auto-open is disabled
    local btn = GetOrCreateAHButton()
    btn:SetShown(opts ~= nil and opts.autoOpenWithAH == false)
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
    ResetQuickBuy(true)
    if self.AHScan then
        self.AHScan.OnAHClosed()
    end
    if ahBtn then ahBtn:Hide() end
    local opts = self.db and self.db.options
    if opts and opts.closeWithAH and self.UI and self.UI.MainWindowV2 then
        self.UI.MainWindowV2.Hide()
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

handlers["AUCTION_HOUSE_THROTTLED_SYSTEM_READY"] = function(self)
    local qb = self.quickBuyState
    if qb and qb.active and qb.pendingItemID and qb.pendingQty and not qb.confirmSent then
        qb.confirmSent = true
        C_AuctionHouse.ConfirmCommoditiesPurchase(qb.pendingItemID, qb.pendingQty)
    end
end

handlers["COMMODITY_PURCHASE_SUCCEEDED"] = function(self)
    local qb = self.quickBuyState
    if not (qb and qb.active and qb.currentSearchString and qb.pendingQty) then
        return
    end

    local listName = self.quickBuyList and self.quickBuyList.listName
    local oldSearchString = qb.currentSearchString
    local purchasedQty = qb.pendingQty

    qb.pendingItemID = nil
    qb.pendingQty = nil
    qb.currentSearchString = nil
    qb.searchPending = false
    qb.searchRetries = 0

    if Auctionator and Auctionator.API and Auctionator.API.v1 and listName then
        local oldTerms = Auctionator.API.v1.ConvertFromSearchString(ADDON_NAME, oldSearchString)
        if oldTerms and oldTerms.quantity then
            local newQty = oldTerms.quantity - purchasedQty
            if newQty > 0 then
                oldTerms.quantity = newQty
                local newSearchString = Auctionator.API.v1.ConvertToSearchString(ADDON_NAME, oldTerms)
                pcall(Auctionator.API.v1.AlterShoppingListItem, ADDON_NAME, listName, oldSearchString, newSearchString)
                if self.quickBuyList and self.quickBuyList.entries then
                    for _, entry in ipairs(self.quickBuyList.entries) do
                        if entry.searchString == oldSearchString then
                            entry.searchString = newSearchString
                            entry.quantity = newQty
                            break
                        end
                    end
                end
            else
                pcall(Auctionator.API.v1.DeleteShoppingListItem, ADDON_NAME, listName, oldSearchString)
                if self.quickBuyList and self.quickBuyList.entries then
                    for idx, entry in ipairs(self.quickBuyList.entries) do
                        if entry.searchString == oldSearchString then
                            table.remove(self.quickBuyList.entries, idx)
                            break
                        end
                    end
                end
            end
        end
    end

    -- Do NOT auto-advance: each purchase requires a hardware event.
    -- User presses their macro (/click GAMQuickBuyBtn) for each item.
end

handlers["COMMODITY_PURCHASE_FAILED"] = function(self)
    local qb = self.quickBuyState
    if qb and qb.active then
        ResetQuickBuy(true)
        print("|cffff8800[GAM]|r Commodity purchase failed. Quick buy stopped.")
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
GAM:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
GAM:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
GAM:RegisterEvent("COMMODITY_PURCHASE_FAILED")

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
    elseif cmd == "quickbuy" then
        if GAM.quickBuyState.active then
            ResetQuickBuy()
        else
            print("|cffff8800[GAM]|r Quick buy is not active. Press your /click GAMQuickBuyBtn macro to begin.")
        end
    else
        if GAM.UI and GAM.UI.MainWindowV2 then
            GAM.UI.MainWindowV2.Toggle()
        end
    end
end

-- ===== UI namespace =====
GAM.UI = GAM.UI or {}

function GAM:GetActiveMainWindow()
    return self.UI.MainWindowV2
end

GAM._vt = "Midnight"   -- internal version tag
