-- GoldCraft Advisor - Core.lua
-- Main addon initialization, event handling, and lifecycle management

local addonName, GCA = ...

-- Version tracking
GCA.version = "v1.0.0"
local CURRENT_VERSION = 1

-- Initialize Ace3 if available (embed into existing table, don't replace)
local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
local AceConsole = LibStub and LibStub("AceConsole-3.0", true)

local useAce3 = false
if AceAddon and AceEvent and AceConsole then
    -- Embed Ace3 mixins into existing GCA table
    AceEvent:Embed(GCA)
    AceConsole:Embed(GCA)
    useAce3 = true
else
    -- Fallback if Ace3 not available
    GCA.events = {}
end

-- Export to global for other files
_G.GCA = GCA
_G.GoldCraftAdvisor = GCA

-- ================= SavedVariables Initialization =================
local function InitializeDB()
    GoldCraftAdvisorDB = GoldCraftAdvisorDB or {}

    -- Version migration
    if not GoldCraftAdvisorDB.version or GoldCraftAdvisorDB.version < CURRENT_VERSION then
        -- Future: handle migrations here
        GoldCraftAdvisorDB.version = CURRENT_VERSION
    end

    -- Settings defaults
    GoldCraftAdvisorDB.settings = GoldCraftAdvisorDB.settings or {}
    local s = GoldCraftAdvisorDB.settings
    s.quantity = s.quantity or 10000
    s.trim = s.trim or 3
    s.panelPos = s.panelPos or { x = nil, y = nil }
    s.panelVisible = s.panelVisible ~= false  -- default true
    s.showOnAHOpen = s.showOnAHOpen ~= false  -- default true
    s.debugMode = s.debugMode or false  -- persist debug mode

    -- Price cache
    GoldCraftAdvisorDB.prices = GoldCraftAdvisorDB.prices or {}

    -- Filters (user-defined)
    GoldCraftAdvisorDB.filters = GoldCraftAdvisorDB.filters or {}

    -- Scan history ring buffer
    GoldCraftAdvisorDB.scanHistory = GoldCraftAdvisorDB.scanHistory or {}

    -- Link to addon
    GCA.db = GoldCraftAdvisorDB
end

-- ================= Event Handling =================

-- Register events using frame (works with or without Ace3)
function GCA:RegisterAddonEvent(event, handler)
    if useAce3 and AceEvent and AceEvent.RegisterEvent then
        -- Use Ace3 event system
        AceEvent.RegisterEvent(self, event, handler or event)
    else
        -- Fallback: use event frame
        self.events = self.events or {}
        self.events[event] = handler or event
        if self.eventFrame then
            self.eventFrame:RegisterEvent(event)
        end
    end
end

function GCA:UnregisterAddonEvent(event)
    if useAce3 and AceEvent and AceEvent.UnregisterEvent then
        AceEvent.UnregisterEvent(self, event)
    else
        if self.events then
            self.events[event] = nil
        end
        if self.eventFrame then
            self.eventFrame:UnregisterEvent(event)
        end
    end
end

-- ================= Auction House Event Handlers =================

function GCA:AUCTION_HOUSE_SHOW()
    -- Clear cached prices on AH open (ensure fresh data)
    self:ClearPriceCache()

    -- Show panel if configured
    if self.db.settings.showOnAHOpen and self.db.settings.panelVisible then
        self:ShowPanel()
    end

    self:Log("|cff00ff00[GCA]|r Auction House opened. Price cache cleared.", false)
end

function GCA:AUCTION_HOUSE_CLOSED()
    -- Hide panel
    self:HidePanel()

    -- Clear runtime cache (keep saved prices for session)
    self.commodityCache = {}

    self:Log("|cff00ff00[GCA]|r Auction House closed.", false)
end

function GCA:COMMODITY_SEARCH_RESULTS_UPDATED()
    self:Debug("COMMODITY_SEARCH_RESULTS_UPDATED fired")
    -- Delegate to scanner module
    if self.OnCommoditySearchResults then
        self:OnCommoditySearchResults()
    end
end

-- ================= Cache Management =================

function GCA:ClearPriceCache()
    self.commodityCache = {}
    -- Note: We don't clear GoldCraftAdvisorDB.prices here
    -- Those persist for historical reference
end

-- ================= Slash Commands =================

local function HandleSlashCommand(msg)
    local cmd = msg:lower():match("^(%S*)")

    if cmd == "show" then
        GCA:ShowPanel()
        print("|cff00ff00[GCA]|r Panel shown.")

    elseif cmd == "hide" then
        GCA:HidePanel()
        GCA.db.settings.panelVisible = false
        print("|cff00ff00[GCA]|r Panel hidden.")

    elseif cmd == "scan" then
        if GCA.StartScan then
            GCA:StartScan()
        else
            print("|cff00ff00[GCA]|r Scanner not ready.")
        end

    elseif cmd == "clear" then
        GoldCraftAdvisorDB.prices = {}
        GCA.commodityCache = {}
        print("|cff00ff00[GCA]|r All price data cleared.")

    elseif cmd == "codec" then
        -- Test codec
        if GCA.Codec and GCA.Codec.Validate then
            GCA.Codec:Validate()
        end

    elseif cmd == "roi" then
        -- Show all ROI calculations
        if GCA.CalculateAllROI then
            GCA:CalculateAllROI()
        end

    elseif cmd == "debug" then
        -- Debug: show strategy counts by category
        print("|cff00ff00[GCA]|r === Debug Info ===")

        -- Count strategies by category
        local catCounts = {}
        local total = 0
        if GCA.Strategies then
            for name, strat in pairs(GCA.Strategies) do
                local cat = strat.category or "NONE"
                catCounts[cat] = (catCounts[cat] or 0) + 1
                total = total + 1
            end
        end
        print(string.format("Total strategies in GCA.Strategies: %d", total))
        for cat, count in pairs(catCounts) do
            print(string.format("  %s: %d", cat, count))
        end

        -- Check lastResults
        if GCA.lastResults then
            print(string.format("lastResults has %d entries", #GCA.lastResults))
            local resultCats = {}
            for _, r in ipairs(GCA.lastResults) do
                local cat = r.category or "NONE"
                resultCats[cat] = (resultCats[cat] or 0) + 1
            end
            for cat, count in pairs(resultCats) do
                print(string.format("  %s: %d", cat, count))
            end
        else
            print("lastResults is nil")
        end

        -- Current filter
        print(string.format("Active filter: %s", GCA.db.settings.activeFilter or "nil"))

        -- Test filtering
        local testCat = "Thaumaturgy"
        local filtered = 0
        if GCA.lastResults then
            for _, r in ipairs(GCA.lastResults) do
                if r.category == testCat then
                    filtered = filtered + 1
                    if filtered <= 3 then
                        print(string.format("  Found: %s (cat=%s)", r.name, r.category))
                    end
                end
            end
        end
        print(string.format("Strategies matching '%s': %d", testCat, filtered))

        -- Price data
        local priceCount = 0
        if GCA.db.prices then
            for itemID, ranks in pairs(GCA.db.prices) do
                for rank, data in pairs(ranks) do
                    priceCount = priceCount + 1
                end
            end
        end
        print(string.format("Stored prices: %d", priceCount))

    elseif cmd == "verbose" then
        GCA.debugMode = not GCA.debugMode
        GCA.db.settings.debugMode = GCA.debugMode  -- Persist setting
        local msg = string.format("|cff00ff00[GCA]|r Debug mode: %s", GCA.debugMode and "ON" or "OFF")
        GCA:Log(msg, true)  -- Log and print to chat
        if GCA.debugMode then
            GCA:Log("|cff00ff00[GCA]|r Debug output goes to log panel. Use /gca log to view.", true)
        end

    elseif cmd == "log" then
        -- Toggle debug log panel
        if GCA.ToggleDebugPanel then
            GCA:ToggleDebugPanel()
        else
            print("|cffff0000[GCA]|r Debug panel not available")
        end

    elseif cmd:match("^item%s+(%d+)") then
        -- Look up item info: /gca item 210799
        local itemID = tonumber(cmd:match("^item%s+(%d+)"))
        if itemID then
            local itemName = C_Item.GetItemNameByID(itemID)
            local itemLink = C_Item.GetItemInfo(itemID)
            print(string.format("|cff00ff00[GCA]|r Item %d: %s", itemID, itemName or "Unknown"))
            if itemLink then
                print("  Link: " .. itemLink)
            end
            -- Check what we have in our database
            local ourName = GCA:GetItemName(itemID)
            if ourName then
                print(string.format("  Our DB: %s", ourName))
                if ourName ~= itemName then
                    print("  |cffff0000MISMATCH!|r")
                end
            else
                print("  Our DB: Not in database")
            end
        end

    elseif cmd == "scanitem" then
        -- Manually scan a single item for debugging
        local itemID = tonumber(args)
        if itemID then
            GCA:ScanSingleItem(itemID)
        else
            print("|cffff0000[GCA]|r Usage: /gca scanitem <itemID>")
        end

    elseif cmd == "verify" then
        -- Verify all item IDs in our database
        print("|cff00ff00[GCA]|r Verifying item IDs...")
        local mismatches = 0
        local missing = 0
        if GCA.ItemDatabase then
            for itemID, data in pairs(GCA.ItemDatabase) do
                local wowName = C_Item.GetItemNameByID(itemID)
                if wowName then
                    if data.name ~= wowName then
                        print(string.format("  |cffff0000MISMATCH|r %d: Ours='%s' WoW='%s'",
                            itemID, data.name, wowName))
                        mismatches = mismatches + 1
                    end
                else
                    missing = missing + 1
                end
            end
        end
        print(string.format("|cff00ff00[GCA]|r Verification complete: %d mismatches, %d unknown", mismatches, missing))

    elseif cmd == "ahitem" then
        -- Get itemID of item currently viewed in AH commodity frame
        local function logAndPrint(msg)
            print(msg)
            if GCA.AddDebugLog then
                -- Strip color codes for cleaner log output
                local cleanMsg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                GCA:AddDebugLog(cleanMsg)
            end
        end

        if AuctionHouseFrame and AuctionHouseFrame.CommoditiesBuyFrame then
            local f = AuctionHouseFrame.CommoditiesBuyFrame
            if f.GetItemID then
                local itemID = f:GetItemID()
                if itemID then
                    local itemName = C_Item.GetItemNameByID(itemID)
                    logAndPrint(string.format("|cff00ff00[GCA]|r AH Item: %s (ID: %d)", itemName or "Unknown", itemID))
                    -- Check if we have this in our database
                    local ourName = GCA:GetItemName(itemID)
                    if ourName then
                        logAndPrint(string.format("  In our DB as: %s", ourName))
                    else
                        logAndPrint("  |cffff8800NOT in our database!|r")
                    end
                    -- Check if we have a price
                    local price = GCA:GetPrice(itemID)
                    if price then
                        logAndPrint(string.format("  Stored price: %.2fg", price/10000))
                    else
                        logAndPrint("  No stored price")
                    end
                else
                    logAndPrint("|cffff0000[GCA]|r No item selected in AH")
                end
            else
                logAndPrint("|cffff0000[GCA]|r Cannot get item from AH frame")
            end
        else
            logAndPrint("|cffff0000[GCA]|r Auction House commodity frame not open")
        end

    elseif cmd == "missing" then
        -- Show all items that are missing prices
        print("|cff00ff00[GCA]|r Items missing prices:")
        local missingItems = {}
        for stratName, strategy in pairs(GCA.Strategies or {}) do
            for _, input in ipairs(strategy.inputs or {}) do
                if not GCA:GetPrice(input.itemID) then
                    missingItems[input.itemID] = input.label or GCA:GetItemName(input.itemID) or tostring(input.itemID)
                end
            end
            for _, output in ipairs(strategy.outputs or {}) do
                if not GCA:GetPrice(output.itemID) then
                    missingItems[output.itemID] = output.label or GCA:GetItemName(output.itemID) or tostring(output.itemID)
                end
            end
        end
        local count = 0
        for itemID, name in pairs(missingItems) do
            count = count + 1
            print(string.format("  %d: %s", itemID, name))
        end
        print(string.format("|cff00ff00[GCA]|r Total missing: %d items", count))

    elseif cmd == "help" or cmd == "" then
        print("|cff00ff00[GCA]|r GoldCraft Advisor Commands:")
        print("  /gca show      - Show the panel")
        print("  /gca hide      - Hide the panel")
        print("  /gca scan      - Start AH scan")
        print("  /gca clear     - Clear all cached price data")
        print("  /gca roi       - Calculate and display all ROI")
        print("  /gca debug     - Show strategy/category debug info")
        print("  /gca verbose   - Toggle verbose debug output")
        print("  /gca log       - Show debug log panel (copyable)")
        print("  /gca item ID   - Look up item by ID")
        print("  /gca scanitem ID - Manually scan single item")
        print("  /gca ahitem    - Get ID of item shown in AH")
        print("  /gca missing   - List items missing prices")
        print("  /gca verify    - Verify all item IDs")
        print("  /gca help      - Show this help")
    else
        print("|cff00ff00[GCA]|r Unknown command. Type /gca help for options.")
    end
end

-- ================= Initialization =================

function GCA:OnInitialize()
    -- Initialize database
    InitializeDB()

    -- Load debug mode from saved settings
    self.debugMode = self.db.settings.debugMode or false

    -- Initialize commodity cache
    self.commodityCache = {}

    -- Register slash commands
    SLASH_GCA1 = "/gca"
    SLASH_GCA2 = "/goldcraft"
    SlashCmdList["GCA"] = HandleSlashCommand

    -- Log to panel only, minimal chat output
    self:Log("|cff00ff00[GCA]|r GoldCraft Advisor " .. self.version .. " loaded.", true)
end

function GCA:OnEnable()
    -- Register events using the event frame
    self.eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
    self.eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
    self.eventFrame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")

    -- Initialize UI if available
    if self.CreateMainPanel then
        self:CreateMainPanel()
    end

    print("|cff00ff00[GCA]|r UI initialized. Use /gca show to open panel.")
end

-- ================= Event Frame Initialization =================

-- Create event frame for event handling
local eventFrame = CreateFrame("Frame")
GCA.eventFrame = eventFrame

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if GCA[event] then
        GCA[event](GCA, ...)
    elseif GCA.events and GCA.events[event] then
        local handler = GCA.events[event]
        if type(handler) == "function" then
            handler(GCA, ...)
        elseif type(handler) == "string" and GCA[handler] then
            GCA[handler](GCA, ...)
        end
    end
end)

eventFrame:RegisterEvent("ADDON_LOADED")

function GCA:ADDON_LOADED(addon)
    if addon == addonName then
        self:OnInitialize()
        self:OnEnable()
        eventFrame:UnregisterEvent("ADDON_LOADED")
    end
end

-- ================= Utility Functions =================

-- Format gold value from copper
function GCA:FormatGold(copper)
    if not copper then return "---" end
    local gold = copper / 10000
    return string.format("%.2fg", gold)
end

-- Format gold with locale support
function GCA:FormatGoldLocalized(copper)
    if not copper then return "---" end
    local gold = copper / 10000
    local formatted = string.format("%.2f", gold)
    -- Could add locale-specific formatting here
    return formatted .. "g"
end

-- Format ROI percentage
function GCA:FormatROI(roi)
    if not roi then return "N/A" end
    return string.format("%.1f%%", roi)
end

-- Get current timestamp
function GCA:GetTimestamp()
    return time()
end

-- Debug print (only in debug mode) - outputs to log panel only, NOT chat
GCA.debugMode = false
function GCA:Debug(...)
    if self.debugMode then
        -- Build message from varargs
        local args = {...}
        local message = ""
        for i, v in ipairs(args) do
            if i > 1 then message = message .. " " end
            message = message .. tostring(v)
        end

        -- Log to debug panel ONLY (not chat)
        if self.AddDebugLog then
            self:AddDebugLog(message)
        end
    end
end

-- Print to log panel (always logs, optionally prints to chat)
function GCA:Log(msg, alsoChat)
    -- Always add to log panel
    if self.AddDebugLog then
        local cleanMsg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        self:AddDebugLog(cleanMsg)
    end
    -- Only print to chat if requested
    if alsoChat then
        print(msg)
    end
end
