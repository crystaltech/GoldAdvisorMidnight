-- GoldAdvisorMidnight/UI/MainWindowV2.lua
-- Three-panel redesign: Left (tools/scan), Center (strategy list), Right (inline detail).
-- Best Strategy hero card, collapsible panels, onboarding overlay.
-- Opt-in via Settings > "Use New UI Layout (Beta)".
-- Module: GAM.UI.MainWindowV2

local ADDON_NAME, GAM = ...
local MW2 = {}
GAM.UI.MainWindowV2 = MW2
local lastScanRefreshAt = 0

-- ===== Layout constants =====
local ROW_H        = 22
local VISIBLE_ROWS = 30
local CARD_H       = 108
local LIST_SECTION_H = 22
local HDR_H        = 20
local LIST_TOP_PAD = CARD_H + LIST_SECTION_H + HDR_H + 16   -- offset from center top to listHost

-- Color constants (module-local)
local C_BG_PANEL = { 0.06, 0.06, 0.06, 1.0 }
local C_GR, C_GG, C_GB = 1.0, 0.82, 0.0        -- gold
local C_DR, C_DG, C_DB, C_DA = 0.7, 0.57, 0.0, 0.7  -- dimmed gold (rules)
local THIN_BACKDROP = {
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = true,
    tileSize = 8,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local function AttachButtonTooltip(btn, title, body)
    if not btn then return end
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title and title ~= "" then
            GameTooltip:SetText(title, 1, 1, 1)
        end
        if body and body ~= "" then
            GameTooltip:AddLine(body, 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- ===== Column configs =====
-- ALL mode: show profession column
local LIST_COLUMNS_ALL = {
    { id="stratName",  x=14,  w=180, hKey="COL_STRAT",  sKey="stratName",  j="LEFT"  },
    { id="profession", x=200, w=100, hKey="COL_PROF",   sKey="profession", j="LEFT"  },
    { id="profit",     x=306, w=100, hKey="COL_PROFIT", sKey="profit",     j="RIGHT" },
    { id="roi",        x=412, w=58,  hKey="COL_ROI",    sKey="roi",        j="RIGHT" },
    { id="status",     x=476, w=60,  hKey="COL_STATUS", sKey=nil,          j="LEFT"  },
}
-- FILTERED mode: wider name, profession shown as subtitle, no profession column
local LIST_COLUMNS_FILTERED = {
    { id="stratName", x=14,  w=270, hKey="COL_STRAT",  sKey="stratName", j="LEFT"  },
    { id="profit",    x=290, w=110, hKey="COL_PROFIT", sKey="profit",    j="RIGHT" },
    { id="roi",       x=406, w=58,  hKey="COL_ROI",    sKey="roi",       j="RIGHT" },
    { id="status",    x=470, w=60,  hKey="COL_STATUS", sKey=nil,         j="LEFT"  },
}

-- ===== Module state =====
local frame
local dividerContainer, leftPanel, centerPanel, rightPanel, statusBarFrame
local bestStratCard, onboardingOverlay, listHost
local colHeaderBtns = {}
local rowFrames     = {}
local filteredList  = {}
local scrollOffset  = 0
local selectedStratID = nil
local filterPatch      = GAM.C.DEFAULT_PATCH
local filterProf       = "All"
local filterProfSet    = nil
local filterMode       = "mine"
local filterProfSingle = "All"   -- specific profession sub-filter within the current pool
local sortKey       = "roi"
local sortAsc       = true
local scanning      = false
local scanBtnLeft, scanBtnStatus
local activeColConfig = LIST_COLUMNS_ALL
local rpDetail      = {}   -- inline right-panel detail widget refs
local suppressScrollCallback = false
local selectedCraftSimBtn, selectedShoppingBtn, selectedScanBtn
local shoppingSync = {
    active = false,
    stratID = nil,
    patchTag = nil,
    lastSignature = nil,
    pending = false,
}
local shoppingSyncFrame
local leftPanelChecks = {}  -- refs for external sync (millOwn, craftBolts, craftIngots)

-- ===== Helpers =====
local function IsFavorite(id)
    local pdb = GAM:GetPatchDB(filterPatch)
    return pdb.favorites and pdb.favorites[id]
end

local function ToggleFavorite(id)
    local pdb = GAM:GetPatchDB(filterPatch)
    pdb.favorites = pdb.favorites or {}
    pdb.favorites[id] = pdb.favorites[id] and nil or true
end

local function GetL() return GAM.L end

local function GetFormulaProfiles()
    return (GAM_WORKBOOK_GENERATED and GAM_WORKBOOK_GENERATED.formulaProfiles) or {}
end

local function ApplyFontSize(fs, size, flags)
    if not fs or not fs.GetFont or not fs.SetFont then return end
    local fontPath, _, fontFlags = fs:GetFont()
    if fontPath then
        fs:SetFont(fontPath, size, flags or fontFlags)
    end
end

local function BuildPlayerProfessionSet()
    local set = {}
    if not GetProfessions then return set end
    local supported = {}
    for _, p in ipairs(GAM.Importer.GetAllProfessions(filterPatch) or {}) do
        supported[p] = true
    end
    local indices = { GetProfessions() }
    for _, idx in ipairs(indices) do
        if idx then
            local profName = GetProfessionInfo(idx)
            if profName and supported[profName] then
                set[profName] = true
            end
        end
    end
    return set
end

local function HasAnyEntries(set)
    return set and next(set) ~= nil
end

local function StratMatchesFilter(strat)
    -- Step 1: pool check (Mine = player professions, All = global pool)
    local poolOK
    if filterMode == "mine" and HasAnyEntries(filterProfSet) then
        poolOK = filterProfSet[strat.profession] == true
    else
        poolOK = filterProf == "All" or strat.profession == filterProf
    end
    if not poolOK then return false end
    -- Step 2: single-profession sub-filter (narrows within the pool)
    if filterProfSingle ~= "All" and strat.profession ~= filterProfSingle then
        return false
    end
    return true
end

local function GetActiveColumnConfig()
    if filterMode == "mine" then
        return LIST_COLUMNS_ALL
    end
    return (filterProf == "All") and LIST_COLUMNS_ALL or LIST_COLUMNS_FILTERED
end

local function SetInputQtyOverride(stratID, patchTag, value)
    if not stratID then return end
    local pdb = GAM:GetPatchDB(patchTag or GAM.C.DEFAULT_PATCH)
    pdb.inputQtyOverrides = pdb.inputQtyOverrides or {}
    local n = tonumber(value)
    if n and n > 0 then
        pdb.inputQtyOverrides[stratID] = n
    else
        pdb.inputQtyOverrides[stratID] = nil
    end
end

local function SetCraftsOverride(stratID, patchTag, value)
    if not stratID then return end
    local pdb = GAM:GetPatchDB(patchTag or GAM.C.DEFAULT_PATCH)
    pdb.craftsOverrides = pdb.craftsOverrides or {}
    local n = tonumber(value)
    if n and n > 0 then
        pdb.craftsOverrides[stratID] = math.floor(n)
    else
        pdb.craftsOverrides[stratID] = nil
    end
end

local function ClampFillQtyValue(value)
    local n = tonumber(value)
    local fallback = GAM.C.DEFAULT_FILL_QTY
    if not n then return fallback end
    return math.max(GAM.C.MIN_FILL_QTY, math.min(GAM.C.MAX_FILL_QTY, math.floor(n)))
end

local function ClampStatPercentValue(value, fallback)
    local n = tonumber(value)
    if not n then return fallback or 0 end
    if n < 0 then n = 0 end
    if n > 100 then n = 100 end
    return n
end

local function FormatStatPercentValue(value)
    local n = tonumber(value)
    if not n then return "" end
    local s = string.format("%.1f", n)
    return (s:gsub("%.?0+$", ""))
end

local function BindItemRow(frameObj, display)
    frameObj._itemDisplay = display
    frameObj:EnableMouse(display and display.hasSafeLink and display.itemLink and true or false)
end

local function ItemRowClick(self, button)
    local display = self and self._itemDisplay
    local link = display and display.itemLink
    if not link or link == "" then return end
    if HandleModifiedItemClick and HandleModifiedItemClick(link) then
        return
    end
    local itemString = link:match("|H([^|]+)|h")
    if itemString then
        SetItemRef(itemString, link, button)
    end
end

local function ItemRowEnter(self)
    local display = self and self._itemDisplay
    local link = display and display.itemLink
    if not link or link == "" then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end

local function ItemRowLeave()
    GameTooltip:Hide()
end

local function BuildAuctionatorShoppingPayload(strat, patchTag)
    if not (Auctionator and Auctionator.API and Auctionator.API.v1 and
            type(Auctionator.API.v1.CreateShoppingList) == "function") then
        print("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_NOT_FOUND"])
        return nil
    end
    if not strat then return nil end
    local m = GAM.Pricing.CalculateStratMetrics(strat, patchTag or GAM.C.DEFAULT_PATCH)
    if not m then return nil end

    local addonName  = "GoldAdvisorMidnight"
    local hasConvert = type(Auctionator.API.v1.ConvertToSearchString) == "function"
    local searchStrings = {}
    local signatureParts = {}
    local items = {}

    for _, rm in ipairs(m.reagents or {}) do
        local qty = math.floor(rm.needToBuy or 0)
        if qty > 0 then
            local entry
            if hasConvert then
                local qualityID = (rm.itemID and C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo)
                    and C_TradeSkillUI.GetItemReagentQualityByItemInfo(rm.itemID) or nil
                local searchTerm = { searchString = rm.name, quantity = qty, isExact = true }
                if qualityID and qualityID > 0 then searchTerm.tier = qualityID end
                entry = Auctionator.API.v1.ConvertToSearchString(addonName, searchTerm)
            else
                local _, link = rm.itemID and GetItemInfo(rm.itemID) or nil
                entry = link or rm.name
            end
            if entry then
                searchStrings[#searchStrings + 1] = entry
                signatureParts[#signatureParts + 1] = entry
                items[#items + 1] = {
                    searchString = entry,
                    itemID = rm.itemID,
                    name = rm.name,
                    quantity = qty,
                }
            end
        end
    end

    table.sort(signatureParts)
    local signature = table.concat(signatureParts, "\031")
    return {
        addonName = addonName,
        listName = GAM.L["AUCTIONATOR_LIST_NAME"],
        metrics = m,
        searchStrings = searchStrings,
        items = items,
        signature = signature,
    }
end

local function CreateAuctionatorShoppingList(strat, patchTag, quiet)
    local payload = BuildAuctionatorShoppingPayload(strat, patchTag)
    if not payload then return nil end

    if #payload.searchStrings == 0 and not quiet then
        print("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_NO_ITEMS"])
    end

    Auctionator.API.v1.CreateShoppingList(payload.addonName, payload.listName, payload.searchStrings)
    GAM.quickBuyList = {
        listName = payload.listName,
        entries = payload.items,
        signature = payload.signature,
    }
    if not quiet then
        print(string.format("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_CREATED"], payload.listName, #payload.searchStrings))
    end
    return payload
end

local function DisableShoppingSync(silent)
    shoppingSync.active = false
    shoppingSync.stratID = nil
    shoppingSync.patchTag = nil
    shoppingSync.lastSignature = nil
    shoppingSync.pending = false
    if shoppingSyncFrame then
        shoppingSyncFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
        shoppingSyncFrame:UnregisterEvent("AUCTION_HOUSE_CLOSED")
    end
    if not silent then
        print("|cffff8800[GAM]|r Auctionator shopping sync stopped.")
    end
end

local function RefreshShoppingSync()
    if not shoppingSync.active then return end
    local strat = shoppingSync.stratID and GAM.Importer.GetStratByID(shoppingSync.stratID) or nil
    if not strat then
        DisableShoppingSync(true)
        return
    end

    local payload = BuildAuctionatorShoppingPayload(strat, shoppingSync.patchTag)
    if not payload then
        DisableShoppingSync(true)
        return
    end
    if payload.signature == shoppingSync.lastSignature then
        return
    end

    Auctionator.API.v1.CreateShoppingList(payload.addonName, payload.listName, payload.searchStrings)
    GAM.quickBuyList = {
        listName = payload.listName,
        entries = payload.items,
        signature = payload.signature,
    }
    shoppingSync.lastSignature = payload.signature
    if leftPanel and leftPanel.refreshVisiblePanels then
        leftPanel.refreshVisiblePanels()
    end
end

local function EnsureShoppingSyncFrame()
    if shoppingSyncFrame then return end
    shoppingSyncFrame = CreateFrame("Frame")
    shoppingSyncFrame:SetScript("OnEvent", function(_, event)
        if event == "BAG_UPDATE_DELAYED" then
            if shoppingSync.pending then return end
            shoppingSync.pending = true
            C_Timer.After(0.15, function()
                shoppingSync.pending = false
                RefreshShoppingSync()
            end)
        elseif event == "AUCTION_HOUSE_CLOSED" then
            DisableShoppingSync(true)
        end
    end)
end

local function ToggleShoppingSync(strat, patchTag)
    if not strat then return end
    if shoppingSync.active and shoppingSync.stratID == strat.id and shoppingSync.patchTag == (patchTag or GAM.C.DEFAULT_PATCH) then
        DisableShoppingSync()
        return
    end

    local payload = CreateAuctionatorShoppingList(strat, patchTag)
    if not payload then return end

    EnsureShoppingSyncFrame()
    shoppingSync.active = true
    shoppingSync.stratID = strat.id
    shoppingSync.patchTag = patchTag or GAM.C.DEFAULT_PATCH
    shoppingSync.lastSignature = payload.signature
    shoppingSync.pending = false
    shoppingSyncFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    shoppingSyncFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
    print(string.format("|cffff8800[GAM]|r Auctionator shopping sync armed for '%s'.", strat.stratName or "strategy"))
end

local function ScanSingleStrategy(strat, patchTag, callback)
    if not strat or not GAM.AHScan then return end
    if not GAM.ahOpen then
        local L = GetL()
        print("|cffff8800[GAM]|r " .. (L and L["ERR_NO_AH"] or "Open the Auction House first."))
        return
    end
    local pt = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GAM:GetPatchDB(pt)

    GAM.AHScan.StopScan()
    GAM.AHScan.ResetQueue()

    local function queueItem(item)
        if not item or not item.name then return end
        local ids = item.itemIDs
        if not ids or #ids == 0 then
            ids = pdb.rankGroups and pdb.rankGroups[item.name] or nil
        end
        if ids and #ids > 0 then
            for _, id in ipairs(ids) do
                GAM.AHScan.QueueItemScan(id, callback)
            end
        else
            GAM.AHScan.QueueNameScan(item.name, pt, callback)
        end
    end

    queueItem(strat.output)
    for _, o in ipairs(strat.outputs or {}) do queueItem(o) end
    for _, r in ipairs(strat.reagents or {}) do queueItem(r) end
    GAM.AHScan.StartScan()
end

local function BuildRuntimeColumns(config, rowW)
    local cols = {}
    local showProfession = (config == LIST_COLUMNS_ALL)
    local showStatus = rowW >= (showProfession and 420 or 360)
    local gap = 8
    local usable = math.max(220, rowW - 18)

    if showProfession then
        local statusW = showStatus and 68 or 0
        local roiW = 52
        local profitW = 86
        local profW = math.max(82, math.floor(usable * 0.20))
        local nameW = usable - profW - profitW - roiW - statusW - gap * (showStatus and 4 or 3)
        if nameW < 120 then
            local delta = 120 - nameW
            profW = math.max(70, profW - delta)
            nameW = usable - profW - profitW - roiW - statusW - gap * (showStatus and 4 or 3)
        end
        local x = 14
        cols[#cols + 1] = { id="stratName",  x=x, w=nameW,  hKey="COL_STRAT",  sKey="stratName",  j="LEFT"  }
        x = x + nameW + gap
        cols[#cols + 1] = { id="profession", x=x, w=profW,  hKey="COL_PROF",   sKey="profession", j="LEFT"  }
        x = x + profW + gap
        cols[#cols + 1] = { id="profit",     x=x, w=profitW,hKey="COL_PROFIT", sKey="profit",     j="RIGHT" }
        x = x + profitW + gap
        cols[#cols + 1] = { id="roi",        x=x, w=roiW,   hKey="COL_ROI",    sKey="roi",        j="RIGHT" }
        if showStatus then
            x = x + roiW + gap
            cols[#cols + 1] = { id="status", x=x, w=statusW,hKey="COL_STATUS", sKey=nil,          j="LEFT"  }
        end
    else
        local statusW = showStatus and 70 or 0
        local roiW = 52
        local profitW = 92
        local nameW = usable - profitW - roiW - statusW - gap * (showStatus and 3 or 2)
        local x = 14
        cols[#cols + 1] = { id="stratName", x=x, w=nameW,  hKey="COL_STRAT",  sKey="stratName", j="LEFT"  }
        x = x + nameW + gap
        cols[#cols + 1] = { id="profit",    x=x, w=profitW,hKey="COL_PROFIT", sKey="profit",    j="RIGHT" }
        x = x + profitW + gap
        cols[#cols + 1] = { id="roi",       x=x, w=roiW,   hKey="COL_ROI",    sKey="roi",       j="RIGHT" }
        if showStatus then
            x = x + roiW + gap
            cols[#cols + 1] = { id="status", x=x, w=statusW,hKey="COL_STATUS", sKey=nil,        j="LEFT"  }
        end
    end

    return cols, showProfession
end

local function GetVisibleListRows()
    if not listHost or not listHost.GetHeight then return VISIBLE_ROWS end
    local h = listHost:GetHeight() or 0
    local rows = math.floor(h / ROW_H)
    if rows < 1 then rows = VISIBLE_ROWS end
    if rows > VISIBLE_ROWS then rows = VISIBLE_ROWS end
    return rows
end

-- ===== Sort =====
local SORT_FNS = {
    stratName  = function(a, b) return a.stratName < b.stratName end,
    profession = function(a, b) return a.profession < b.profession end,
    profit = function(a, b)
        local ma = GAM.Pricing.CalculateStratMetrics(a, filterPatch)
        local mb = GAM.Pricing.CalculateStratMetrics(b, filterPatch)
        return ((ma and ma.profit) or -math.huge) > ((mb and mb.profit) or -math.huge)
    end,
    roi = function(a, b)
        local ma = GAM.Pricing.CalculateStratMetrics(a, filterPatch)
        local mb = GAM.Pricing.CalculateStratMetrics(b, filterPatch)
        return ((ma and ma.roi) or -math.huge) > ((mb and mb.roi) or -math.huge)
    end,
}

local function RebuildList()
    local all = GAM.Importer.GetAllStrats(filterPatch)
    local out = {}
    for _, s in ipairs(all) do
        if StratMatchesFilter(s) then
            out[#out + 1] = s
        end
    end

    -- Pre-compute metrics for expensive sort keys so each strategy is evaluated
    -- exactly once (O(n)) rather than once per comparison pair (O(n log n)).
    -- Fixes severe FPS drop on second scan when the price cache is populated
    -- and ComputePriceForQty runs the full order-book simulation per call.
    local fn = SORT_FNS[sortKey]
    if sortKey == "profit" or sortKey == "roi" then
        local cache = {}
        for _, s in ipairs(out) do
            cache[s.id] = GAM.Pricing.CalculateStratMetrics(s, filterPatch)
        end
        if sortKey == "profit" then
            fn = function(a, b)
                local ma, mb = cache[a.id], cache[b.id]
                return ((ma and ma.profit) or -math.huge) > ((mb and mb.profit) or -math.huge)
            end
        else
            fn = function(a, b)
                local ma, mb = cache[a.id], cache[b.id]
                return ((ma and ma.roi) or -math.huge) > ((mb and mb.roi) or -math.huge)
            end
        end
    end
    fn = fn or SORT_FNS.roi

    table.sort(out, function(a, b)
        local af, bf = IsFavorite(a.id), IsFavorite(b.id)
        if af and not bf then return true end
        if bf and not af then return false end
        if sortAsc then return fn(a, b) else return fn(b, a) end
    end)
    filteredList = out
    scrollOffset = 0
end

-- ===== DoScan =====
local function DoScan()
    local L = GetL()
    if GAM.AHScan and GAM.AHScan.IsScanning and GAM.AHScan.IsScanning() then
        GAM.AHScan.StopScan()
        return
    end
    if not GAM.ahOpen then
        print("|cffff8800[GAM]|r " .. (L and L["ERR_NO_AH"] or "Open the Auction House first."))
        return
    end
    GAM.AHScan.ResetQueue()
    GAM.AHScan.QueueStratListItems(filteredList, filterPatch)
    GAM.AHScan.StartScan()
end

local function SetScanningState(isScanning)
    scanning = isScanning
    local L = GetL()
    local lbl = isScanning
        and (L and L["BTN_SCAN_STOP"] or "Stop")
        or  (L and L["BTN_SCAN_ALL"]  or "Scan AH")
    if scanBtnLeft then
        scanBtnLeft:SetText(lbl)
        scanBtnLeft:Enable()
    end
    if scanBtnStatus then
        scanBtnStatus:SetText(lbl)
        scanBtnStatus:Enable()
    end
end

-- ===== Forward declarations =====
local ShowInlineDetail   -- defined after BuildInlineDetail; captured by row closures

-- ===== Row frames (30-slot virtual scroll pool) =====
local STRAT_ICON_W = 20   -- left gutter for star icon

local function MakeRowFrame(parent, idx)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(idx - 1) * ROW_H)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

    local star = row:CreateTexture(nil, "OVERLAY")
    star:SetSize(14, 14)
    star:SetPoint("LEFT", row, "LEFT", 4, 0)
    star:SetAtlas("Professions-ChatIcon-Quality-Tier3", false)
    row.star = star

    -- All text cells — anchored by ApplyColumnLayout
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    ApplyFontSize(nameText, 11)
    row.nameText = nameText

    local profSubText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profSubText:SetJustifyH("LEFT")
    profSubText:SetTextColor(0.65, 0.65, 0.65, 0.85)
    profSubText:SetWordWrap(false)
    ApplyFontSize(profSubText, 10)
    row.profSubText = profSubText

    local profText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profText:SetJustifyH("LEFT")
    profText:SetWordWrap(false)
    ApplyFontSize(profText, 10)
    row.profText = profText

    local profitText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profitText:SetJustifyH("RIGHT")
    profitText:SetWordWrap(false)
    ApplyFontSize(profitText, 10)
    row.profitText = profitText

    local roiText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    roiText:SetJustifyH("RIGHT")
    roiText:SetWordWrap(false)
    ApplyFontSize(roiText, 10)
    row.roiText = roiText

    local missingText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    missingText:SetJustifyH("LEFT")
    missingText:SetTextColor(1, 0.6, 0)
    missingText:SetWordWrap(false)
    ApplyFontSize(missingText, 10)
    row.missingText = missingText

    row.missingPriceList = {}

    row:SetScript("OnClick", function(self, btn)
        if btn ~= "LeftButton" or not self.stratID then return end
        selectedStratID = self.stratID
        local s = GAM.Importer.GetStratByID(self.stratID)
        if s then
            if rightPanel and rightPanel:IsShown() and ShowInlineDetail then
                ShowInlineDetail(s, filterPatch)
            elseif GAM.UI.StratDetail then
                GAM.UI.StratDetail.Show(s, filterPatch)
            end
            if leftPanel and leftPanel.refreshStatEditors then
                leftPanel.refreshStatEditors()
            end
        end
        MW2.RefreshRows()
    end)

    row:SetScript("OnDoubleClick", function(self)
        if not self.stratID then return end
        ToggleFavorite(self.stratID)
        RebuildList()
        MW2.RefreshRows()
    end)

    row:SetScript("OnEnter", function(self)
        if not self.stratID then return end
        local s = GAM.Importer.GetStratByID(self.stratID)
        if not s then return end
        local hasNotes   = s.notes and s.notes ~= ""
        local hasMissing = self.missingPriceList and #self.missingPriceList > 0
        if not hasNotes and not hasMissing then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(s.stratName, 1, 1, 1)
        if hasNotes then GameTooltip:AddLine(s.notes, 0.8, 0.8, 0.8, true) end
        if hasMissing then
            GameTooltip:AddLine("Missing prices:", 1, 0.6, 0)
            for _, name in ipairs(self.missingPriceList) do
                GameTooltip:AddLine("  " .. name, 1, 0.8, 0.3)
            end
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

-- ===== ApplyColumnLayout — re-anchors headers + row cells =====
local function ApplyColumnLayout(config, rowW)
    local L = GetL()
    local runtimeCols, showProfession = BuildRuntimeColumns(config, rowW or 0)

    for i, col in ipairs(runtimeCols) do
        local btn = colHeaderBtns[i]
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", centerPanel, "TOPLEFT", col.x, -(CARD_H + LIST_SECTION_H + 12))
            btn:SetWidth(col.w)
            btn.labelFS:SetText(L and L[col.hKey] or col.hKey)
            btn.labelFS:SetJustifyH(col.j)
            btn.sortKeyV2 = col.sKey
            btn:Show()
        end
    end
    for i = #runtimeCols + 1, #colHeaderBtns do
        if colHeaderBtns[i] then colHeaderBtns[i]:Hide() end
    end

    for _, row in ipairs(rowFrames) do
        if rowW then row:SetWidth(rowW) end

        row.nameText:Hide()
        row.profText:Hide()
        row.profitText:Hide()
        row.roiText:Hide()
        row.missingText:Hide()

        for _, col in ipairs(runtimeCols) do
            local fs
            if     col.id == "stratName"  then fs = row.nameText
            elseif col.id == "profession" then fs = row.profText
            elseif col.id == "profit"     then fs = row.profitText
            elseif col.id == "roi"        then fs = row.roiText
            elseif col.id == "status"     then fs = row.missingText
            end
            if fs then
                fs:ClearAllPoints()
                local xOff = (col.id == "stratName") and (col.x + STRAT_ICON_W) or col.x
                local wOff = (col.id == "stratName") and (col.w - STRAT_ICON_W)  or col.w
                fs:SetPoint("LEFT", row, "LEFT", xOff, 0)
                fs:SetWidth(wOff)
                fs:SetJustifyH(col.j)
                fs:Show()
            end
        end

        row.profText:SetShown(showProfession)
        row.profSubText:Hide()
    end
end

-- ===== PopulateRow =====
local function PopulateRow(row, strat)
    local L = GetL()
    row.stratID = strat.id
    local isFav = IsFavorite(strat.id)
    row.star:SetVertexColor(isFav and 1 or 0.5, isFav and 0.85 or 0.5, isFav and 0 or 0.5, 1)
    row.star:SetAlpha(isFav and 1 or 0.35)

    row.nameText:SetText(strat.stratName)
    row.profText:SetText(strat.profession)
    row.profSubText:SetText("")

    local m = GAM.Pricing.CalculateStratMetrics(strat, filterPatch)
    local noPrice = "|cff888888" .. (L and L["NO_PRICE"] or "—") .. "|r"
    if m then
        row.profitText:SetText(m.profit
            and ((m.profit >= 0 and "|cff55ff55" or "|cffff5555") .. GAM.Pricing.FormatPrice(m.profit) .. "|r")
            or  noPrice)
        row.roiText:SetText(m.roi
            and ((m.roi >= 0 and "|cff55ff55" or "|cffff5555") .. string.format("%.1f%%", m.roi) .. "|r")
            or  "|cff888888—|r")
        if #m.missingPrices > 0 then
            row.missingText:SetText(L and L["MISSING_PRICES"] or "!")
            row.missingPriceList = m.missingPrices
        else
            row.missingText:SetText("")
            row.missingPriceList = {}
        end
    else
        row.profitText:SetText(noPrice)
        row.roiText:SetText("|cff888888—|r")
        row.missingText:SetText(L and L["MISSING_PRICES"] or "!")
        row.missingPriceList = {}
    end

    if strat.id == selectedStratID then row:LockHighlight() else row:UnlockHighlight() end
    row:Show()
end

-- ===== RefreshRows =====
function MW2.RefreshRows()
    if not frame then return end
    local visibleRows = GetVisibleListRows()
    for i, row in ipairs(rowFrames) do
        local strat = filteredList[scrollOffset + i]
        if strat and i <= visibleRows then
            PopulateRow(row, strat)
        else
            row:Hide()
            row.stratID = nil
        end
    end
    if frame.scrollBar then
        local max = math.max(0, #filteredList - visibleRows)
        if scrollOffset > max then scrollOffset = max end
        frame.scrollBar:SetMinMaxValues(0, max)
        suppressScrollCallback = true
        frame.scrollBar:SetValue(scrollOffset)
        suppressScrollCallback = false
        frame.scrollBar:SetShown(max > 0)
    end
    if frame.statusCountText then
        local L = GetL()
        frame.statusCountText:SetText(string.format(L and L["STATUS_STRAT_COUNT"] or "%d strategies", #filteredList))
    end
end

-- ===== BestStratCard =====
local function RefreshBestStratCard()
    if not bestStratCard then return end
    local best, profit, roi
    local minProfit = (GAM.C and GAM.C.BEST_STRAT_MIN_PROFIT) or 0
    local minROI = (GAM.C and GAM.C.BEST_STRAT_MIN_ROI) or 0
    for _, strat in ipairs(filteredList) do
        local m = GAM.Pricing.CalculateStratMetrics(strat, filterPatch)
        if m and m.profit and m.roi and m.profit >= minProfit and m.roi >= minROI then
            if (not best) or m.profit > profit then
                best, profit, roi = strat, m.profit, m.roi
            end
        end
    end
    if best then
        bestStratCard.noDataText:Hide()
        if bestStratCard.scanNowBtn then bestStratCard.scanNowBtn:Hide() end
        if bestStratCard.openBtn then bestStratCard.openBtn:Show() end
        bestStratCard.stratNameFS:Show()
        bestStratCard.stratProfFS:Show()
        bestStratCard.stratMetricsFS:Show()
        bestStratCard.stratNameFS:SetText(string.format("%s: %s", best.profession, best.stratName))
        bestStratCard.stratProfFS:SetText("")
        bestStratCard.stratProfFS:Hide()
        local c = (profit >= 0) and "|cff55ff55" or "|cffff5555"
        bestStratCard.stratMetricsFS:SetText(
            c .. GAM.Pricing.FormatPrice(profit) .. "|r   |cffffdd00"
            .. string.format("%.1f%% ROI", roi) .. "|r")
        bestStratCard.stratNameFS:Show()
        bestStratCard.stratProfFS:Show()
        bestStratCard.stratMetricsFS:Show()
        bestStratCard.stratID = best.id
    else
        bestStratCard.stratNameFS:Hide()
        bestStratCard.stratProfFS:Hide()
        bestStratCard.stratMetricsFS:Hide()
        bestStratCard.noDataText:Show()
        if bestStratCard.scanNowBtn then bestStratCard.scanNowBtn:Hide() end
        if bestStratCard.openBtn then bestStratCard.openBtn:Hide() end
        bestStratCard.stratID = nil
    end
end

-- ===== RelayoutPanels =====
local function RelayoutPanels()
    if not dividerContainer then return end
    local opts  = GAM.db and GAM.db.options
    local lc    = opts and opts.leftPanelCollapsed  or false
    local rc    = opts and opts.rightPanelCollapsed or false
    local C     = GAM.C
    local leftW = lc and 0 or C.LEFT_PANEL_W
    local rightW= rc and 0 or C.RIGHT_PANEL_W

    if leftPanel  then leftPanel:SetShown(not lc) end
    if rightPanel then rightPanel:SetShown(not rc) end

    if centerPanel then
        centerPanel:ClearAllPoints()
        centerPanel:SetPoint("TOPLEFT",     dividerContainer, "TOPLEFT",     leftW,   0)
        centerPanel:SetPoint("BOTTOMRIGHT", dividerContainer, "BOTTOMRIGHT", -rightW, 0)
    end

    -- Recompute row width now that center panel has been resized
    -- GetWidth may return stale value until next frame; use arithmetic instead
    local totalW  = C.MAIN_WIN_W - 28  -- frame insets
    local centerW = totalW - leftW - rightW
    local rowW    = centerW - 20       -- scrollbar gutter

    for _, r in ipairs(rowFrames) do r:SetWidth(rowW) end

    activeColConfig = GetActiveColumnConfig()
    ApplyColumnLayout(activeColConfig, rowW)

    RefreshBestStratCard()
    MW2.RefreshRows()
end

-- ===== Onboarding =====
local function DismissOnboarding()
    if GAM.db then GAM.db.options.hasSeenOnboarding = true end
    if onboardingOverlay then onboardingOverlay:Hide() end
end

-- ===== Inline right-panel detail =====

local function HideInlineDetail()
    if rightPanel and rightPanel.placeholder then rightPanel.placeholder:Show() end
    if rpDetail.root then rpDetail.root:Hide() end
    if rpDetail.btnScanStrat then
        rpDetail.btnScanStrat:Disable()
        rpDetail.btnScanStrat:SetAlpha(0.45)
    end
    if selectedScanBtn then
        selectedScanBtn:Disable()
        selectedScanBtn:SetAlpha(0.45)
    end
    if selectedCraftSimBtn then selectedCraftSimBtn:Disable() end
    if selectedShoppingBtn then selectedShoppingBtn:Disable() end
    if leftPanel and leftPanel.refreshStatEditors then
        leftPanel.refreshStatEditors()
    end
end

ShowInlineDetail = function(strat, patchTag)
    if not rpDetail.root then return end
    local L = GetL()
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    GAM.Pricing.PreloadStratItemData(strat, patchTag)
    -- Refresh best-strat card so it uses the same price/bag snapshot as the detail panel.
    RefreshBestStratCard()
    local m  = GAM.Pricing.CalculateStratMetrics(strat, patchTag)

    -- Populate the Crafts editbox with the current craft count
    if rpDetail.craftsEB and not rpDetail.craftsEB:HasFocus() then
        local craftsVal = (m and m.crafts) and math.floor(m.crafts + 0.5) or 1
        rpDetail.craftsEB:SetText(tostring(craftsVal))
    end

    -- Hide placeholder, show detail
    if rightPanel and rightPanel.placeholder then rightPanel.placeholder:Hide() end

    -- Header
    rpDetail.nameFS:SetText(strat.stratName)
    rpDetail.profFS:SetText(strat.profession)
    if strat.notes and strat.notes ~= "" then
        rpDetail.notesFS:SetText(strat.notes)
        rpDetail.notesFS:Show()
    else
        rpDetail.notesFS:Hide()
        rpDetail.notesFS:SetText("")
    end

    -- Metrics
    local dash = "|cff888888—|r"
    rpDetail.metCostFS:SetText(
        (m and m.totalCostToBuy) and GAM.Pricing.FormatPrice(m.totalCostToBuy) or dash)
    rpDetail.metRevenueFS:SetText(
        (m and m.netRevenue) and GAM.Pricing.FormatPrice(m.netRevenue) or dash)
    if m and m.profit then
        local c = m.profit >= 0 and "|cff55ff55" or "|cffff5555"
        rpDetail.metProfitFS:SetText(c .. GAM.Pricing.FormatPrice(m.profit) .. "|r")
    else
        rpDetail.metProfitFS:SetText(dash)
    end
    if m and m.roi then
        local c = m.roi >= 0 and "|cff55ff55" or "|cffff5555"
        rpDetail.metROIFS:SetText(c .. string.format("%.2f%%", m.roi) .. "|r")
    else
        rpDetail.metROIFS:SetText(dash)
    end
    rpDetail.metBreakevenFS:SetText(
        (m and m.breakEvenSell) and GAM.Pricing.FormatPrice(m.breakEvenSell) or dash)

    -- Fill qty notice
    local qty = (GAM.db and GAM.db.options and GAM.db.options.shallowFillQty) or GAM.C.DEFAULT_FILL_QTY
    local qtyStr = tostring(math.floor(qty)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    rpDetail.fillNoticeFS:SetFormattedText(
        L and L["FILL_QTY_ACTIVE"] or "Fill Qty: %s", qtyStr)

    if m and m.missingPrices and #m.missingPrices > 0 then
        rpDetail.missingFS:SetText((L and L["MISSING_PRICES"] or "Missing prices") .. ": " .. table.concat(m.missingPrices, ", "))
        rpDetail.missingFS:Show()
    else
        rpDetail.missingFS:Hide()
        rpDetail.missingFS:SetText("")
    end

    -- Reagent rows (Name | Qty | Need to Buy | Unit Price)
    local reagentMetrics = m and m.reagents or {}
    for i, row in ipairs(rpDetail.reagentRows) do
        local rDef = strat.reagents and strat.reagents[i]
        local rMet = reagentMetrics[i]
        if rDef and rMet then
            local display = GAM.Pricing.GetItemDisplayData(rMet.itemID, rDef.name)
            row.nameFS:SetText(display.displayText)
            BindItemRow(row, display)
            local qtyText = string.format("%.0f", rMet.required or 0)
            row.qtyEB:Hide()
            row.qtyFS:Show()
            row.qtyFS:SetText(qtyText)
            row.needFS:SetText(string.format("%.0f", rMet.needToBuy or 0))
            row.priceFS:SetText(rMet.unitPrice
                and GAM.Pricing.FormatPrice(rMet.unitPrice)
                or "|cffff8800—|r")
            row:Show()
        else
            row:Hide()
            BindItemRow(row, nil)
            row.qtyEB:Hide()
        end
    end

    -- Output rows (Name | Expected Qty)
    local outputItems = {}
    if m and m.outputs and #m.outputs > 0 then
        for _, oi in ipairs(m.outputs) do outputItems[#outputItems + 1] = oi end
    elseif m and m.output then
        outputItems[1] = m.output
    end
    for i, row in ipairs(rpDetail.outputRows) do
        local oi = outputItems[i]
        if oi then
            local display = GAM.Pricing.GetItemDisplayData(oi.itemID, oi.name)
            row.nameFS:SetText(display.displayText)
            BindItemRow(row, display)
            row.qtyFS:SetText(oi.expectedQty
                and string.format("%.0f", math.floor(oi.expectedQty)) or "—")
            row.priceFS:SetText(
                oi.netRevenue and GAM.Pricing.FormatPrice(oi.netRevenue)
                or (oi.unitPrice and GAM.Pricing.FormatPrice(oi.unitPrice) or "|cffff8800—|r")
            )
            row:Show()
        else
            BindItemRow(row, nil)
            row:Hide()
        end
    end

    -- Show/hide Edit+Delete for user strats
    local isUser = strat._isUser == true
    if rpDetail.btnEdit   then rpDetail.btnEdit:SetShown(isUser)   end
    if rpDetail.btnDelete then rpDetail.btnDelete:SetShown(isUser) end

    -- Store for button handlers
    rpDetail.currentStrat = strat
    rpDetail.currentPatch = patchTag
    if rpDetail.btnScanStrat then
        rpDetail.btnScanStrat:Enable()
        rpDetail.btnScanStrat:SetAlpha(1)
    end
    if selectedScanBtn then
        selectedScanBtn:Enable()
        selectedScanBtn:SetAlpha(1)
    end
    if selectedCraftSimBtn then selectedCraftSimBtn:Enable() end
    if selectedShoppingBtn then selectedShoppingBtn:Enable() end
    if rpDetail.reagentScrollFrame then rpDetail.reagentScrollFrame:SetVerticalScroll(0) end
    if rpDetail.outputScrollFrame then rpDetail.outputScrollFrame:SetVerticalScroll(0) end
    if rpDetail.reagentListHost then
        rpDetail.reagentListHost:SetHeight(math.max(1, #reagentMetrics * ROW_H))
    end
    if rpDetail.outputListHost then
        rpDetail.outputListHost:SetHeight(math.max(1, #outputItems * ROW_H))
    end
    rpDetail.root:Show()
    if leftPanel and leftPanel.refreshStatEditors then
        leftPanel.refreshStatEditors()
    end
end

local function BuildInlineDetail(panel)
    local L  = GetL()
    local RW = GAM.C.RIGHT_PANEL_W
    local P  = 12
    local UW = RW - P * 2
    local ACTION_H = 58

    local root = CreateFrame("Frame", nil, panel)
    root:SetAllPoints(panel)
    root:Hide()
    rpDetail.root = root

    local titleFS = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOP", root, "TOP", 0, -12)
    titleFS:SetText((L and L["DETAIL_TITLE"]) or "Strategy Detail")
    titleFS:SetTextColor(C_GR, C_GG, C_GB)
    ApplyFontSize(titleFS, 13)

    local topRule = root:CreateTexture(nil, "ARTWORK")
    topRule:SetHeight(1)
    topRule:SetPoint("TOPLEFT", root, "TOPLEFT", P, -38)
    topRule:SetPoint("TOPRIGHT", root, "TOPRIGHT", -P, -38)
    topRule:SetColorTexture(C_DR, C_DG, C_DB, 0.6)

    local content = CreateFrame("Frame", nil, root)
    content:SetPoint("TOPLEFT", root, "TOPLEFT", P, -44)
    content:SetPoint("TOPRIGHT", root, "TOPRIGHT", -P, -44)
    content:SetPoint("BOTTOM", root, "BOTTOM", 0, ACTION_H + 6)
    rpDetail.content = content

    -- Running y position (negative = down from top)
    local y = -P

    -- ── Strat name ──
    local nameFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    nameFS:SetWidth(UW)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetTextColor(C_GR, C_GG, C_GB)
    nameFS:SetWordWrap(true)
    ApplyFontSize(nameFS, 12)
    rpDetail.nameFS = nameFS
    y = y - 34

    local profFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    profFS:SetWidth(UW)
    profFS:SetTextColor(0.65, 0.65, 0.65)
    ApplyFontSize(profFS, 10)
    rpDetail.profFS = profFS
    y = y - 16

    local notesFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    notesFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    notesFS:SetWidth(UW)
    notesFS:SetTextColor(0.8, 0.8, 0.5)
    notesFS:SetWordWrap(true)
    ApplyFontSize(notesFS, 10)
    rpDetail.notesFS = notesFS
    y = y - 16

    -- Gold rule
    local function MakeRule(yOff, alpha)
        local r = content:CreateTexture(nil, "ARTWORK")
        r:SetHeight(1)
        r:SetPoint("TOPLEFT",  content, "TOPLEFT",  0,  yOff)
        r:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
        r:SetColorTexture(C_DR, C_DG, C_DB, alpha or C_DA)
        return r
    end
    MakeRule(y)
    y = y - 6

    -- ── Metrics ──
    local LBL_W = 100
    local function MakeMetricRow(label, yOff)
        local lbl = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
        lbl:SetWidth(LBL_W)
        lbl:SetText(label)
        ApplyFontSize(lbl, 11)
        local val = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        val:SetPoint("TOPLEFT", content, "TOPLEFT", LBL_W + 6, yOff)
        val:SetWidth(UW - LBL_W - 6)
        val:SetJustifyH("LEFT")
        ApplyFontSize(val, 11)
        return val, yOff - 18
    end

    -- Invisible button overlay for FontString metric labels (FontStrings can't receive OnEnter).
    local function MakeMetricTooltip(yOff, titleKey, bodyKey)
        local anchor = CreateFrame("Button", nil, content)
        anchor:SetSize(UW, 18)
        anchor:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
        anchor:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText((L and L[titleKey]) or titleKey, 1, 1, 1)
            GameTooltip:AddLine((L and L[bodyKey]) or bodyKey, 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        anchor:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local yCost = y
    rpDetail.metCostFS,      y = MakeMetricRow(L and L["LBL_COST"]      or "Cost:",       y)
    MakeMetricTooltip(yCost, "TT_LBL_COST_TITLE", "TT_LBL_COST_BODY")

    local yRevenue = y
    rpDetail.metRevenueFS,   y = MakeMetricRow(L and L["LBL_REVENUE"]   or "Revenue:",    y)
    MakeMetricTooltip(yRevenue, "TT_LBL_REVENUE_TITLE", "TT_LBL_REVENUE_BODY")
    MakeRule(y, 0.4)
    y = y - 4

    local yProfit = y
    rpDetail.metProfitFS,    y = MakeMetricRow(L and L["LBL_PROFIT"]    or "Profit:",     y)
    MakeMetricTooltip(yProfit, "TT_LBL_PROFIT_TITLE", "TT_LBL_PROFIT_BODY")

    local yROI = y
    rpDetail.metROIFS,       y = MakeMetricRow(L and L["LBL_ROI"]       or "ROI:",        y)
    MakeMetricTooltip(yROI, "TT_LBL_ROI_TITLE", "TT_LBL_ROI_BODY")

    local yBreakeven = y
    rpDetail.metBreakevenFS, y = MakeMetricRow(L and L["LBL_BREAKEVEN"] or "Break-even:", y)
    MakeMetricTooltip(yBreakeven, "TT_LBL_BREAKEVEN_TITLE", "TT_LBL_BREAKEVEN_BODY")

    -- Fill qty notice
    local fillFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fillFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    fillFS:SetWidth(UW)
    fillFS:SetTextColor(1.0, 0.65, 0.0)
    ApplyFontSize(fillFS, 10)
    rpDetail.fillNoticeFS = fillFS
    y = y - 16

    local missingFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    missingFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    missingFS:SetWidth(UW)
    missingFS:SetJustifyH("LEFT")
    missingFS:SetTextColor(1.0, 0.75, 0.2, 1.0)
    missingFS:SetWordWrap(true)
    ApplyFontSize(missingFS, 10)
    missingFS:Hide()
    rpDetail.missingFS = missingFS
    y = y - 18

    -- ── Reagents ──
    local reagHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reagHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    reagHdr:SetText((L and L["DETAIL_INPUT_HDR"]) or "Input Items")
    reagHdr:SetTextColor(C_GR, C_GG, C_GB)
    ApplyFontSize(reagHdr, 12)

    -- Crafts editbox on the right side of the Input Items header row
    local craftsEB = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    craftsEB:SetSize(52, 18)
    craftsEB:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y + 1)
    craftsEB:SetAutoFocus(false)
    craftsEB:SetNumeric(true)
    craftsEB:SetScript("OnEnterPressed", function(self)
        if rpDetail.currentStrat then
            SetCraftsOverride(rpDetail.currentStrat.id, rpDetail.currentPatch, self:GetText())
            ShowInlineDetail(rpDetail.currentStrat, rpDetail.currentPatch)
            MW2.RefreshRows()
        end
        self:ClearFocus()
    end)
    craftsEB:SetScript("OnEditFocusLost", function(self)
        if rpDetail.currentStrat then
            SetCraftsOverride(rpDetail.currentStrat.id, rpDetail.currentPatch, self:GetText())
            ShowInlineDetail(rpDetail.currentStrat, rpDetail.currentPatch)
            MW2.RefreshRows()
        end
    end)
    rpDetail.craftsEB = craftsEB

    local craftsLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    craftsLabel:SetPoint("RIGHT", craftsEB, "LEFT", -4, 0)
    craftsLabel:SetText("Crafts:")
    craftsLabel:SetTextColor(C_GR, C_GG, C_GB)
    ApplyFontSize(craftsLabel, 12)

    y = y - 18

    -- Column widths: Name(130) | Need(62) | Price(rest)
    local DETAIL_INNER_W = UW - 18
    local RN, RQ, RNB, RP = 156, 48, 52, DETAIL_INNER_W - 156 - 48 - 52

    local function MakeSmallColHdr(parent, text, xOff, w, yOff)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, yOff)
        fs:SetWidth(w)
        fs:SetText(text)
        fs:SetTextColor(1.0, 0.84, 0.22, 1.0)
        fs:SetJustifyH("LEFT")
        ApplyFontSize(fs, 10)
        return fs
    end
    local reagentSection = CreateFrame("Frame", nil, content, "BackdropTemplate")
    reagentSection:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    reagentSection:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    reagentSection:SetHeight(136)
    reagentSection:SetBackdrop(THIN_BACKDROP)
    reagentSection:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    reagentSection:SetBackdropBorderColor(C_DR, C_DG, C_DB, 0.18)
    local reagentHeaderBg = reagentSection:CreateTexture(nil, "ARTWORK")
    reagentHeaderBg:SetPoint("TOPLEFT", reagentSection, "TOPLEFT", 1, -1)
    reagentHeaderBg:SetPoint("TOPRIGHT", reagentSection, "TOPRIGHT", -1, -1)
    reagentHeaderBg:SetHeight(18)
    reagentHeaderBg:SetColorTexture(0.12, 0.10, 0.03, 0.9)

    MakeSmallColHdr(reagentSection, (L and L["COL_ITEM"]) or "Item",  8,               RN, -8)
    MakeSmallColHdr(reagentSection, (L and L["V2_COL_TOTAL"]) or "Total", 8 + RN,          RQ, -8)
    MakeSmallColHdr(reagentSection, (L and L["V2_COL_NEED"]) or "Need",  8 + RN + RQ,     RNB, -8)
    MakeSmallColHdr(reagentSection, (L and L["V2_COL_PRICE"]) or "Price", 8 + RN + RQ + RNB, RP, -8)

    local reagentScroll = CreateFrame("ScrollFrame", nil, reagentSection, "UIPanelScrollFrameTemplate")
    reagentScroll:SetPoint("TOPLEFT", reagentSection, "TOPLEFT", 8, -22)
    reagentScroll:SetPoint("BOTTOMRIGHT", reagentSection, "BOTTOMRIGHT", -18, 8)
    rpDetail.reagentScrollFrame = reagentScroll

    local reagentListHost = CreateFrame("Frame", nil, reagentScroll)
    reagentListHost:SetWidth(DETAIL_INNER_W)
    reagentListHost:SetHeight(1)
    reagentScroll:SetScrollChild(reagentListHost)
    rpDetail.reagentListHost = reagentListHost

    reagentListHost:EnableMouseWheel(true)
    reagentListHost:SetScript("OnMouseWheel", function(_, delta)
        local cur = reagentScroll:GetVerticalScroll()
        local max = reagentScroll:GetVerticalScrollRange()
        reagentScroll:SetVerticalScroll(math.max(0, math.min(max, cur - delta * (ROW_H * 3))))
    end)

    rpDetail.reagentRows = {}
    for i = 1, 12 do
        local rRow = CreateFrame("Frame", nil, reagentListHost)
        rRow:SetSize(DETAIL_INNER_W, ROW_H)
        rRow:SetPoint("TOPLEFT", reagentListHost, "TOPLEFT", 0, -(i - 1) * ROW_H)
        rRow:SetHyperlinksEnabled(false)
        rRow:SetScript("OnMouseUp", ItemRowClick)
        rRow:SetScript("OnEnter", ItemRowEnter)
        rRow:SetScript("OnLeave", ItemRowLeave)
        local rowBg = rRow:CreateTexture(nil, "BACKGROUND")
        rowBg:SetPoint("TOPLEFT", rRow, "TOPLEFT", 0, -1)
        rowBg:SetPoint("BOTTOMRIGHT", rRow, "BOTTOMRIGHT", -6, 1)
        rowBg:SetColorTexture(0.10, 0.10, 0.10, (i % 2 == 1) and 0.55 or 0.28)
        local nFS = rRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nFS:SetPoint("LEFT", rRow, "LEFT", 6, 0)
        nFS:SetWidth(RN - 14)
        nFS:SetJustifyH("LEFT")
        nFS:SetWordWrap(false)
        ApplyFontSize(nFS, 10)
        local qFS = rRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        qFS:SetPoint("LEFT", rRow, "LEFT", RN + 2, 0)
        qFS:SetWidth(RQ)
        qFS:SetJustifyH("RIGHT")
        qFS:SetWordWrap(false)
        ApplyFontSize(qFS, 10)
        local qEB = CreateFrame("EditBox", nil, rRow, "InputBoxTemplate")
        qEB:SetSize(RQ - 6, 18)
        qEB:SetPoint("LEFT", rRow, "LEFT", RN + 2, 0)
        qEB:SetAutoFocus(false)
        qEB:SetNumeric(false)
        qEB:Hide()
        qEB:SetScript("OnEnterPressed", function(self)
            if rpDetail.currentStrat then
                SetInputQtyOverride(rpDetail.currentStrat.id, rpDetail.currentPatch, self:GetText())
                ShowInlineDetail(rpDetail.currentStrat, rpDetail.currentPatch)
                MW2.RefreshRows()
            end
            self:ClearFocus()
        end)
        qEB:SetScript("OnEditFocusLost", function(self)
            if rpDetail.currentStrat then
                SetInputQtyOverride(rpDetail.currentStrat.id, rpDetail.currentPatch, self:GetText())
                ShowInlineDetail(rpDetail.currentStrat, rpDetail.currentPatch)
                MW2.RefreshRows()
            end
        end)
        local pFS = rRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pFS:SetPoint("LEFT", rRow, "LEFT", RN + RQ + RNB + 4, 0)
        pFS:SetWidth(RP - 6)
        pFS:SetJustifyH("RIGHT")
        pFS:SetWordWrap(false)
        ApplyFontSize(pFS, 10)
        local needFS = rRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        needFS:SetPoint("LEFT", rRow, "LEFT", RN + RQ + 2, 0)
        needFS:SetWidth(RNB - 2)
        needFS:SetJustifyH("RIGHT")
        needFS:SetWordWrap(false)
        ApplyFontSize(needFS, 10)
        rRow.nameFS = nFS
        rRow.qtyFS  = qFS
        rRow.qtyEB = qEB
        rRow.needFS = needFS
        rRow.priceFS = pFS
        rRow:Hide()
        rpDetail.reagentRows[i] = rRow
    end
    y = y - reagentSection:GetHeight() - 8

    -- ── Outputs ──
    local outHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    outHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    outHdr:SetText((L and L["DETAIL_OUTPUT_HDR"]) or "Output Items")
    outHdr:SetTextColor(C_GR, C_GG, C_GB)
    ApplyFontSize(outHdr, 12)
    y = y - 18

    local ON, OQ, OP = 170, 48, DETAIL_INNER_W - 170 - 48

    local outputSection = CreateFrame("Frame", nil, content, "BackdropTemplate")
    outputSection:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    outputSection:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    outputSection:SetHeight(118)
    outputSection:SetBackdrop(THIN_BACKDROP)
    outputSection:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    outputSection:SetBackdropBorderColor(C_DR, C_DG, C_DB, 0.18)
    local outputHeaderBg = outputSection:CreateTexture(nil, "ARTWORK")
    outputHeaderBg:SetPoint("TOPLEFT", outputSection, "TOPLEFT", 1, -1)
    outputHeaderBg:SetPoint("TOPRIGHT", outputSection, "TOPRIGHT", -1, -1)
    outputHeaderBg:SetHeight(18)
    outputHeaderBg:SetColorTexture(0.12, 0.10, 0.03, 0.9)

    MakeSmallColHdr(outputSection, (L and L["COL_ITEM"]) or "Item", 8, ON, -8)
    MakeSmallColHdr(outputSection, (L and L["V2_COL_TOTAL"]) or "Total", 8 + ON, OQ, -8)
    MakeSmallColHdr(outputSection, (L and L["V2_COL_NET"]) or "Net", 8 + ON + OQ, OP, -8)

    local outputScroll = CreateFrame("ScrollFrame", nil, outputSection, "UIPanelScrollFrameTemplate")
    outputScroll:SetPoint("TOPLEFT", outputSection, "TOPLEFT", 8, -22)
    outputScroll:SetPoint("BOTTOMRIGHT", outputSection, "BOTTOMRIGHT", -18, 8)
    rpDetail.outputScrollFrame = outputScroll

    local outputListHost = CreateFrame("Frame", nil, outputScroll)
    outputListHost:SetWidth(DETAIL_INNER_W)
    outputListHost:SetHeight(1)
    outputScroll:SetScrollChild(outputListHost)
    rpDetail.outputListHost = outputListHost

    outputListHost:EnableMouseWheel(true)
    outputListHost:SetScript("OnMouseWheel", function(_, delta)
        local cur = outputScroll:GetVerticalScroll()
        local max = outputScroll:GetVerticalScrollRange()
        outputScroll:SetVerticalScroll(math.max(0, math.min(max, cur - delta * (ROW_H * 3))))
    end)

    rpDetail.outputRows = {}
    for i = 1, 10 do
        local oRow = CreateFrame("Frame", nil, outputListHost)
        oRow:SetSize(DETAIL_INNER_W, ROW_H)
        oRow:SetPoint("TOPLEFT", outputListHost, "TOPLEFT", 0, -(i - 1) * ROW_H)
        oRow:SetHyperlinksEnabled(false)
        oRow:SetScript("OnMouseUp", ItemRowClick)
        oRow:SetScript("OnEnter", ItemRowEnter)
        oRow:SetScript("OnLeave", ItemRowLeave)
        local rowBg = oRow:CreateTexture(nil, "BACKGROUND")
        rowBg:SetPoint("TOPLEFT", oRow, "TOPLEFT", 0, -1)
        rowBg:SetPoint("BOTTOMRIGHT", oRow, "BOTTOMRIGHT", -6, 1)
        rowBg:SetColorTexture(0.10, 0.10, 0.10, (i % 2 == 1) and 0.55 or 0.28)
        local nFS = oRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nFS:SetPoint("LEFT", oRow, "LEFT", 6,  0)
        nFS:SetWidth(ON - 16)
        nFS:SetJustifyH("LEFT")
        nFS:SetWordWrap(false)
        ApplyFontSize(nFS, 10)
        local qFS = oRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        qFS:SetPoint("LEFT", oRow, "LEFT", ON + 2, 0)
        qFS:SetWidth(OQ - 2)
        qFS:SetJustifyH("RIGHT")
        qFS:SetWordWrap(false)
        ApplyFontSize(qFS, 10)
        local pFS = oRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pFS:SetPoint("LEFT", oRow, "LEFT", ON + OQ + 6, 0)
        pFS:SetWidth(OP - 10)
        pFS:SetJustifyH("RIGHT")
        pFS:SetWordWrap(false)
        ApplyFontSize(pFS, 10)
        oRow.nameFS = nFS
        oRow.qtyFS  = qFS
        oRow.priceFS = pFS
        oRow:Hide()
        rpDetail.outputRows[i] = oRow
    end
    y = y - outputSection:GetHeight() - 4

    -- ── Action buttons (bottom of panel) ──
    local BY1 = P + 22   -- first row from bottom
    local BY0 = P - 2    -- second row from bottom (Edit/Delete)

    local function MakeRPBtn(lbl, w, xOff, rowY)
        local b = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetText(lbl)
        b:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", P + xOff, rowY)
        return b
    end

    local btnScanStrat = MakeRPBtn("Scan Strat", 82, 0, BY1)
    btnScanStrat:SetScript("OnClick", function()
        if not rpDetail.currentStrat then return end
        local s, pt = rpDetail.currentStrat, rpDetail.currentPatch
        ScanSingleStrategy(s, pt, function() ShowInlineDetail(s, pt) end)
    end)
    AttachButtonTooltip(btnScanStrat, (L and L["TT_SCAN_ALL_ITEMS_TITLE"]) or "Scan All Strategy Items",
        (L and L["TT_SCAN_ALL_ITEMS_BODY"]) or "Queue all reagents and output items in this strategy for AH price lookups.")
    btnScanStrat:Disable()
    btnScanStrat:SetAlpha(0.45)
    rpDetail.btnScanStrat = btnScanStrat

    local btnCraftSim = MakeRPBtn((L and L["BTN_CRAFTSIM_SHORT"]) or "CraftSim", 70, 90, BY1)
    btnCraftSim:SetScript("OnClick", function()
        if not rpDetail.currentStrat then return end
        local pushed, err = GAM.CraftSimBridge.PushStratPrices(
            rpDetail.currentStrat, rpDetail.currentPatch)
        if err then
            print("|cffff8800[GAM]|r CraftSim: " .. tostring(err))
        else
            print(string.format("|cffff8800[GAM]|r Pushed %d price(s) to CraftSim.", pushed or 0))
        end
    end)
    AttachButtonTooltip(btnCraftSim, (L and L["TT_CRAFTSIM_TITLE"]) or "Push Price Overrides to CraftSim",
        (L and L["TT_CRAFTSIM_WARN"]) or "Warning: This will overwrite any existing manual price overrides in CraftSim for all reagents in this strategy.")
    btnCraftSim:Hide()

    local btnShop = MakeRPBtn((L and L["BTN_SHOPPING_SHORT"]) or "Shopping", 70, 166, BY1)
    btnShop:SetScript("OnClick", function()
        ToggleShoppingSync(rpDetail.currentStrat, rpDetail.currentPatch)
    end)
    AttachButtonTooltip(btnShop, (L and L["TT_SHOPPING_TITLE"]) or "Create Auctionator Shopping List",
        (L and L["TT_SHOPPING_BODY"]) or "Creates an Auctionator shopping list for the selected strategy's missing input items.")
    btnShop:Hide()

    -- Edit / Delete — user strats only; second row
    local btnEdit = MakeRPBtn(L and L["BTN_EDIT_STRAT"] or "Edit", 70, 0, BY0)
    btnEdit:SetScript("OnClick", function()
        if rpDetail.currentStrat and GAM.UI.StratCreator then
            GAM.UI.StratCreator.ShowEdit(rpDetail.currentStrat)
        end
    end)
    rpDetail.btnEdit = btnEdit

    local btnDelete = MakeRPBtn(L and L["BTN_DELETE_STRAT"] or "Delete", 78, 78, BY0)
    btnDelete:SetScript("OnClick", function()
        -- Delegate confirm+delete to the existing floating StratDetail dialog
        if rpDetail.currentStrat and GAM.UI.StratDetail then
            GAM.UI.StratDetail.Show(rpDetail.currentStrat, rpDetail.currentPatch)
        end
    end)
    rpDetail.btnDelete = btnDelete
end

local function BuildLeftPanelContent(L, C, LP)
    local charNameFS = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    charNameFS:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP, -40)
    charNameFS:SetWidth(C.LEFT_PANEL_W - LP * 2)
    charNameFS:SetJustifyH("LEFT")
    charNameFS:SetTextColor(C_GR, C_GG, C_GB)
    charNameFS:SetText(UnitName("player") or "—")
    ApplyFontSize(charNameFS, 11)

    local realmFS = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    realmFS:SetPoint("TOPLEFT", charNameFS, "BOTTOMLEFT", 0, -2)
    realmFS:SetWidth(C.LEFT_PANEL_W - LP * 2)
    realmFS:SetJustifyH("LEFT")
    realmFS:SetTextColor(0.6, 0.6, 0.6, 1)
    realmFS:SetText(GetRealmName() or "—")
    ApplyFontSize(realmFS, 10)

    local lpRule = leftPanel:CreateTexture(nil, "ARTWORK")
    lpRule:SetHeight(1)
    lpRule:SetPoint("TOPLEFT",  leftPanel, "TOPLEFT",  LP, -78)
    lpRule:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -LP, -78)
    lpRule:SetColorTexture(C_DR, C_DG, C_DB, 0.4)

    local filterLbl = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterLbl:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP, -88)
    filterLbl:SetText(L["FILTER_PROFESSION"])
    filterLbl:SetTextColor(C_GR, C_GG, C_GB)
    ApplyFontSize(filterLbl, 11)

    local SEG_W = math.floor((C.LEFT_PANEL_W - LP * 2 - 4) / 2)
    local btnFilterMine = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnFilterMine:SetSize(SEG_W, 22)
    btnFilterMine:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP, -108)
    btnFilterMine:SetText((L and L["V2_MY_PROFS"]) or "My Profs")

    local btnFilterAll  = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnFilterAll:SetSize(SEG_W, 22)
    btnFilterAll:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP + SEG_W + 4, -108)
    btnFilterAll:SetText((L and L["V2_ALL_FILTER"]) or "All")

    leftPanel.btnFilterAll  = btnFilterAll
    leftPanel.btnFilterMine = btnFilterMine

    AttachButtonTooltip(btnFilterMine, (L and L["TT_MINE_TITLE"]) or "My Professions Filter",
        (L and L["TT_MINE_BODY"]) or "Show only strategies for professions you have learned.")
    AttachButtonTooltip(btnFilterAll,  (L and L["TT_ALL_TITLE"])  or "Show All Strategies",
        (L and L["TT_ALL_BODY"])  or "Show all crafting strategies regardless of profession.")

    -- ── Profession sub-filter dropdown ──
    -- Sits between the Mine/All toggle and the Fill Qty controls.
    -- Lets players with multiple professions narrow the list to one.
    local ddProf = CreateFrame("Frame", "GAMMainV2ProfDD", leftPanel, "UIDropDownMenuTemplate")
    ddProf:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP - 16, -136)
    UIDropDownMenu_SetWidth(ddProf, C.LEFT_PANEL_W - LP * 2 - 20)

    local function InitProfDD()
        UIDropDownMenu_Initialize(ddProf, function()
            local pool = {}
            if filterMode == "mine" and HasAnyEntries(filterProfSet) then
                for prof in pairs(filterProfSet) do pool[#pool + 1] = prof end
                table.sort(pool)
            else
                pool = GAM.Importer.GetAllProfessions(filterPatch) or {}
            end
            table.insert(pool, 1, "All")
            for _, prof in ipairs(pool) do
                local info = UIDropDownMenu_CreateInfo()
                info.text  = prof
                info.value = prof
                info.func  = function()
                    filterProfSingle = prof
                    UIDropDownMenu_SetText(ddProf, prof)
                    RebuildList()
                    MW2.RefreshRows()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        UIDropDownMenu_SetText(ddProf, filterProfSingle)
    end
    leftPanel.ddProf     = ddProf
    leftPanel.initProfDD = InitProfDD
    InitProfDD()

    local fillLbl = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fillLbl:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP, -172)
    fillLbl:SetText((L and L["V2_FILL_QTY"]) or "Fill Qty")
    fillLbl:SetTextColor(C_GR, C_GG, C_GB)
    ApplyFontSize(fillLbl, 11)

    local fillQtyBox = CreateFrame("EditBox", nil, leftPanel, "InputBoxTemplate")
    fillQtyBox:SetSize(56, 20)
    fillQtyBox:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -LP, -168)
    fillQtyBox:SetAutoFocus(false)
    fillQtyBox:SetNumeric(true)
    fillQtyBox:SetText(tostring((GAM.db and GAM.db.options and GAM.db.options.shallowFillQty) or GAM.C.DEFAULT_FILL_QTY))
    fillQtyBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((L and L["TT_FILL_QTY_TITLE"]) or "Fill Quantity", 1, 1, 1)
        GameTooltip:AddLine((L and L["TT_FILL_QTY_BODY"]) or "Simulates buying this many units from the AH order book when pricing reagents.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    fillQtyBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local fillRangeFS = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fillRangeFS:SetPoint("TOPLEFT", fillLbl, "BOTTOMLEFT", 0, -4)
    fillRangeFS:SetWidth(C.LEFT_PANEL_W - LP * 2)
    fillRangeFS:SetJustifyH("LEFT")
    fillRangeFS:SetText(string.format("%d-%d", GAM.C.MIN_FILL_QTY, GAM.C.MAX_FILL_QTY))
    fillRangeFS:SetTextColor(0.55, 0.55, 0.55, 1)
    ApplyFontSize(fillRangeFS, 9)

    local millOwn = CreateFrame("CheckButton", nil, leftPanel, "UICheckButtonTemplate")
    millOwn:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP - 4, -210)
    millOwn:SetChecked(((GAM.db and GAM.db.options and GAM.db.options.pigmentCostSource) or GAM.C.DEFAULT_PIGMENT_COST_SOURCE) == "mill")

    local millLbl = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    millLbl:SetPoint("LEFT", millOwn, "RIGHT", 0, 0)
    millLbl:SetWidth(C.LEFT_PANEL_W - LP * 2 - 20)
    millLbl:SetJustifyH("LEFT")
    millLbl:SetText((L and L["V2_MILL_OWN_HERBS"]) or "Mill own herbs")
    millLbl:SetTextColor(0.9, 0.9, 0.9, 1)
    ApplyFontSize(millLbl, 10)
    AttachButtonTooltip(millOwn, (L and L["TT_MILL_HERBS_TITLE"]) or "Mill Own Herbs",
        (L and L["TT_MILL_HERBS_BODY"]) or "Use herb costs instead of AH pigment prices for Inscription strategies.")

    local craftBolts = CreateFrame("CheckButton", nil, leftPanel, "UICheckButtonTemplate")
    craftBolts:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP - 4, -234)
    craftBolts:SetChecked(((GAM.db and GAM.db.options and GAM.db.options.boltCostSource) or GAM.C.DEFAULT_BOLT_COST_SOURCE) == "craft")

    local craftBoltsLbl = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    craftBoltsLbl:SetPoint("LEFT", craftBolts, "RIGHT", 0, 0)
    craftBoltsLbl:SetWidth(C.LEFT_PANEL_W - LP * 2 - 20)
    craftBoltsLbl:SetJustifyH("LEFT")
    craftBoltsLbl:SetText((L and L["V2_CRAFT_OWN_BOLTS"]) or "Craft own bolts")
    craftBoltsLbl:SetTextColor(0.9, 0.9, 0.9, 1)
    ApplyFontSize(craftBoltsLbl, 10)
    AttachButtonTooltip(craftBolts, (L and L["TT_CRAFT_BOLTS_TITLE"]) or "Craft Own Bolts",
        (L and L["TT_CRAFT_BOLTS_BODY"]) or "Derive bolt prices from raw linen costs instead of buying bolts from the AH.")

    local craftIngots = CreateFrame("CheckButton", nil, leftPanel, "UICheckButtonTemplate")
    craftIngots:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP - 4, -258)
    craftIngots:SetChecked(((GAM.db and GAM.db.options and GAM.db.options.ingotCostSource) or GAM.C.DEFAULT_INGOT_COST_SOURCE) == "craft")

    local craftIngotsLbl = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    craftIngotsLbl:SetPoint("LEFT", craftIngots, "RIGHT", 0, 0)
    craftIngotsLbl:SetWidth(C.LEFT_PANEL_W - LP * 2 - 20)
    craftIngotsLbl:SetJustifyH("LEFT")
    craftIngotsLbl:SetText((L and L["V2_CRAFT_OWN_INGOTS"]) or "Craft own ingots")
    craftIngotsLbl:SetTextColor(0.9, 0.9, 0.9, 1)
    ApplyFontSize(craftIngotsLbl, 10)
    AttachButtonTooltip(craftIngots, (L and L["TT_CRAFT_INGOTS_TITLE"]) or "Craft Own Ingots",
        (L and L["TT_CRAFT_INGOTS_BODY"]) or "Derive ingot prices from raw ore costs instead of buying ingots from the AH.")

    local statSectionLbl = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statSectionLbl:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP, -286)
    statSectionLbl:SetText((L and L["V2_CRAFT_STATS"]) or "Craft Stats")
    statSectionLbl:SetTextColor(C_GR, C_GG, C_GB)
    ApplyFontSize(statSectionLbl, 11)

    local statProfileFS = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statProfileFS:SetPoint("TOPLEFT", statSectionLbl, "BOTTOMLEFT", 0, -3)
    statProfileFS:SetWidth(C.LEFT_PANEL_W - LP * 2)
    statProfileFS:SetJustifyH("LEFT")
    statProfileFS:SetTextColor(0.65, 0.65, 0.65, 1)
    ApplyFontSize(statProfileFS, 9)

    local statResLbl = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statResLbl:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP, -316)
    statResLbl:SetText("Res%")
    statResLbl:SetTextColor(0.9, 0.9, 0.9, 1)
    ApplyFontSize(statResLbl, 10)

    local statResBox = CreateFrame("EditBox", nil, leftPanel, "InputBoxTemplate")
    statResBox:SetSize(56, 20)
    statResBox:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -LP, -312)
    statResBox:SetAutoFocus(false)
    statResBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((L and L["TT_STAT_RES_TITLE"]) or "Resourcefulness %", 1, 1, 1)
        GameTooltip:AddLine((L and L["TT_STAT_RES_BODY"]) or "Your Resourcefulness stat from the profession window (%). Higher values reduce average reagent consumption.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    statResBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local statMultiLbl = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statMultiLbl:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP, -340)
    statMultiLbl:SetText("Multi%")
    statMultiLbl:SetTextColor(0.9, 0.9, 0.9, 1)
    ApplyFontSize(statMultiLbl, 10)

    local statMultiBox = CreateFrame("EditBox", nil, leftPanel, "InputBoxTemplate")
    statMultiBox:SetSize(56, 20)
    statMultiBox:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -LP, -336)
    statMultiBox:SetAutoFocus(false)
    statMultiBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((L and L["TT_STAT_MULTI_TITLE"]) or "Multicraft %", 1, 1, 1)
        GameTooltip:AddLine((L and L["TT_STAT_MULTI_BODY"]) or "Your Multicraft stat from the profession window (%). Higher values increase expected output quantity.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    statMultiBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local rankLbl = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankLbl:SetText((L and L["V2_MATERIAL_RANK"]) or "Material Rank")
    rankLbl:SetTextColor(C_GR, C_GG, C_GB)
    ApplyFontSize(rankLbl, 11)

    local SEG_H = 24
    local RP_BTN_H = 24
    local BOTTOM_BTN_H = 28
    local BOTTOM_BTN_GAP = 5

    local scanRowTop = LP + 28 + BOTTOM_BTN_GAP
    local logRowTop = scanRowTop + BOTTOM_BTN_H + BOTTOM_BTN_GAP
    local arpRowTop = logRowTop + BOTTOM_BTN_H + BOTTOM_BTN_GAP
    local actionRowTop = arpRowTop + BOTTOM_BTN_H + 8
    local rankRowTop = actionRowTop + RP_BTN_H + 10

    local btnRankR1 = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnRankR1:SetSize(SEG_W, SEG_H)
    btnRankR1:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMLEFT", LP, rankRowTop)
    btnRankR1:SetText(L["RANK_BTN_R1"] or "R1 Mats")

    local btnRankR2 = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnRankR2:SetSize(SEG_W, SEG_H)
    btnRankR2:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMLEFT", LP + SEG_W + 4, rankRowTop)
    btnRankR2:SetText(L["RANK_BTN_R2"] or "R2 Mats")

    rankLbl:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMLEFT", LP, rankRowTop + SEG_H + 8)

    selectedCraftSimBtn = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    selectedCraftSimBtn:SetSize(78, RP_BTN_H)
    selectedCraftSimBtn:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMLEFT", LP, actionRowTop)
    selectedCraftSimBtn:SetText((L and L["BTN_CRAFTSIM_SHORT"]) or "CraftSim")
    selectedCraftSimBtn:Disable()
    selectedCraftSimBtn:SetScript("OnClick", function()
        if not rpDetail.currentStrat then return end
        local pushed, err = GAM.CraftSimBridge.PushStratPrices(rpDetail.currentStrat, rpDetail.currentPatch)
        if err then
            print("|cffff8800[GAM]|r CraftSim: " .. tostring(err))
        else
            print(string.format("|cffff8800[GAM]|r Pushed %d price(s) to CraftSim.", pushed or 0))
        end
    end)
    AttachButtonTooltip(
        selectedCraftSimBtn,
        (L and L["TT_CRAFTSIM_TITLE"]) or "Push Price Overrides to CraftSim",
        (L and L["TT_CRAFTSIM_WARN"]) or "Warning: This will overwrite any existing manual price overrides in CraftSim for all reagents in this strategy."
    )

    selectedShoppingBtn = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    selectedShoppingBtn:SetSize(78, RP_BTN_H)
    selectedShoppingBtn:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -LP, actionRowTop)
    selectedShoppingBtn:SetText((L and L["BTN_SHOPPING_SHORT"]) or "Shopping")
    selectedShoppingBtn:Disable()
    selectedShoppingBtn:SetScript("OnClick", function()
        ToggleShoppingSync(rpDetail.currentStrat, rpDetail.currentPatch)
    end)
    AttachButtonTooltip(
        selectedShoppingBtn,
        (L and L["TT_SHOPPING_TITLE"]) or "Create Auctionator Shopping List",
        (L and L["TT_SHOPPING_BODY"]) or "Creates an Auctionator shopping list for the selected strategy's missing input items and keeps it synced as your bag counts change."
    )

    local function GetSelectedFormulaProfile()
        local strat
        if selectedStratID and GAM.Importer and GAM.Importer.GetStratByID then
            strat = GAM.Importer.GetStratByID(selectedStratID)
        end
        if not strat then
            strat = rpDetail.currentStrat
        end
        local profileKey = strat and strat.formulaProfile or nil
        local profileDef = profileKey and GetFormulaProfiles()[profileKey] or nil
        return strat, profileKey, profileDef
    end

    local function RefreshStatEditors()
        local opts = GAM.db and GAM.db.options
        local strat, profileKey, profileDef = GetSelectedFormulaProfile()
        local hasRes = profileDef and profileDef.resKey
        local hasMulti = profileDef and profileDef.multiKey
        local enabled = opts and profileDef and (hasRes or hasMulti)

        if profileKey and strat then
            statProfileFS:SetText(string.format("%s profile", strat.profession or profileKey))
        elseif profileKey then
            statProfileFS:SetText(string.format("%s profile", profileKey))
        else
            statProfileFS:SetText((L and L["V2_SELECT_FORMULA"]) or "Select a formula strategy")
        end

        statResLbl:SetShown(hasRes and true or false)
        statResBox:SetShown(hasRes and true or false)
        statMultiLbl:SetShown(hasMulti and true or false)
        statMultiBox:SetShown(hasMulti and true or false)

        if hasRes and opts then
            local resVal = opts[profileDef.resKey]
            if resVal == nil then resVal = profileDef.defaultRes or 0 end
            if not statResBox:HasFocus() then
                statResBox:SetText(FormatStatPercentValue(resVal))
            end
            statResBox:SetEnabled(true)
            statResBox:SetAlpha(1)
            statResLbl:SetTextColor(0.9, 0.9, 0.9, 1)
        else
            statResBox:SetText("")
            statResBox:SetEnabled(false)
            statResBox:SetAlpha(0.55)
            statResLbl:SetTextColor(0.45, 0.45, 0.45, 1)
        end

        if hasMulti and opts then
            local multiVal = opts[profileDef.multiKey]
            if multiVal == nil then multiVal = profileDef.defaultMulti or 0 end
            if not statMultiBox:HasFocus() then
                statMultiBox:SetText(FormatStatPercentValue(multiVal))
            end
            statMultiBox:SetEnabled(true)
            statMultiBox:SetAlpha(1)
            statMultiLbl:SetTextColor(0.9, 0.9, 0.9, 1)
        else
            statMultiBox:SetText("")
            statMultiBox:SetEnabled(false)
            statMultiBox:SetAlpha(0.55)
            statMultiLbl:SetTextColor(0.45, 0.45, 0.45, 1)
        end

        statProfileFS:SetTextColor(enabled and 0.65 or 0.5, enabled and 0.65 or 0.5, enabled and 0.65 or 0.5, 1)
    end
    leftPanel.refreshStatEditors = RefreshStatEditors

    local function RefreshVisiblePanels()
        RebuildList()
        RefreshBestStratCard()
        MW2.RefreshRows()
        if rpDetail.currentStrat and rpDetail.root and rpDetail.root:IsShown() then
            local refreshed = rpDetail.currentStrat.id and GAM.Importer.GetStratByID(rpDetail.currentStrat.id)
            if refreshed then
                rpDetail.currentStrat = refreshed
                ShowInlineDetail(refreshed, rpDetail.currentPatch)
            end
        end
        RefreshStatEditors()
    end
    leftPanel.refreshVisiblePanels = RefreshVisiblePanels

    local function CommitFillQty()
        local opts = GAM.db and GAM.db.options
        if not opts then return end
        opts.shallowFillQty = ClampFillQtyValue(fillQtyBox:GetText())
        fillQtyBox:SetText(tostring(opts.shallowFillQty))
        fillQtyBox:ClearFocus()
        RefreshVisiblePanels()
    end
    fillQtyBox:SetScript("OnEnterPressed", CommitFillQty)
    fillQtyBox:SetScript("OnEditFocusLost", CommitFillQty)

    local function CommitStatEditors()
        local opts = GAM.db and GAM.db.options
        if not opts then return end
        local _, _, profileDef = GetSelectedFormulaProfile()
        if not profileDef then
            RefreshStatEditors()
            return
        end

        if profileDef.resKey then
            local fallbackRes = opts[profileDef.resKey]
            if fallbackRes == nil then fallbackRes = profileDef.defaultRes or 0 end
            opts[profileDef.resKey] = ClampStatPercentValue(statResBox:GetText(), fallbackRes)
            statResBox:SetText(FormatStatPercentValue(opts[profileDef.resKey]))
            statResBox:ClearFocus()
        end

        if profileDef.multiKey then
            local fallbackMulti = opts[profileDef.multiKey]
            if fallbackMulti == nil then fallbackMulti = profileDef.defaultMulti or 0 end
            opts[profileDef.multiKey] = ClampStatPercentValue(statMultiBox:GetText(), fallbackMulti)
            statMultiBox:SetText(FormatStatPercentValue(opts[profileDef.multiKey]))
            statMultiBox:ClearFocus()
        end

        RefreshVisiblePanels()
    end
    statResBox:SetScript("OnEnterPressed", CommitStatEditors)
    statResBox:SetScript("OnEditFocusLost", CommitStatEditors)
    statMultiBox:SetScript("OnEnterPressed", CommitStatEditors)
    statMultiBox:SetScript("OnEditFocusLost", CommitStatEditors)

    leftPanelChecks.millOwn    = millOwn
    leftPanelChecks.craftBolts = craftBolts
    leftPanelChecks.craftIngots = craftIngots

    millOwn:SetScript("OnClick", function(self)
        local opts = GAM.db and GAM.db.options
        if not opts then return end
        opts.pigmentCostSource = self:GetChecked() and "mill" or "ah"
        RefreshVisiblePanels()
    end)

    craftBolts:SetScript("OnClick", function(self)
        local opts = GAM.db and GAM.db.options
        if not opts then return end
        opts.boltCostSource = self:GetChecked() and "craft" or "ah"
        RefreshVisiblePanels()
    end)

    craftIngots:SetScript("OnClick", function(self)
        local opts = GAM.db and GAM.db.options
        if not opts then return end
        opts.ingotCostSource = self:GetChecked() and "craft" or "ah"
        RefreshVisiblePanels()
    end)

    local function UpdateSegBtnColors()
        local isAll = (filterMode == "all")
        local goldR, goldG, goldB = isAll and C_GR or 0.5, isAll and C_GG or 0.5, isAll and C_GB or 0.5
        local mineR, mineG, mineB = isAll and 0.5 or C_GR, isAll and 0.5 or C_GG, isAll and 0.5 or C_GB
        local rankPolicy = ((GAM.db and GAM.db.options and GAM.db.options.rankPolicy) or "lowest")
        local r1R, r1G, r1B = (rankPolicy == "lowest") and C_GR or 0.5, (rankPolicy == "lowest") and C_GG or 0.5, (rankPolicy == "lowest") and C_GB or 0.5
        local r2R, r2G, r2B = (rankPolicy == "highest") and C_GR or 0.5, (rankPolicy == "highest") and C_GG or 0.5, (rankPolicy == "highest") and C_GB or 0.5
        if btnFilterAll:GetFontString()  then btnFilterAll:GetFontString():SetTextColor(goldR, goldG, goldB) end
        if btnFilterMine:GetFontString() then btnFilterMine:GetFontString():SetTextColor(mineR, mineG, mineB) end
        if btnRankR1:GetFontString()    then btnRankR1:GetFontString():SetTextColor(r1R, r1G, r1B) end
        if btnRankR2:GetFontString()    then btnRankR2:GetFontString():SetTextColor(r2R, r2G, r2B) end
    end
    UpdateSegBtnColors()

    btnFilterAll:SetScript("OnClick", function()
        filterMode = "all"
        filterProf = "All"
        filterProfSet = nil
        filterProfSingle = "All"
        if leftPanel.ddProf then UIDropDownMenu_SetText(leftPanel.ddProf, "All") end
        activeColConfig = GetActiveColumnConfig()
        UpdateSegBtnColors()
        RebuildList()
        RelayoutPanels()
    end)

    btnFilterMine:SetScript("OnClick", function()
        filterMode = "mine"
        filterProfSet = BuildPlayerProfessionSet()
        filterProf = HasAnyEntries(filterProfSet) and "__mine__" or "All"
        if not HasAnyEntries(filterProfSet) then
            filterMode = "all"
            filterProfSet = nil
        end
        filterProfSingle = "All"
        if leftPanel.ddProf then UIDropDownMenu_SetText(leftPanel.ddProf, "All") end
        activeColConfig = GetActiveColumnConfig()
        UpdateSegBtnColors()
        RebuildList()
        RelayoutPanels()
    end)

    btnRankR1:SetScript("OnClick", function()
        local opts = GAM.db and GAM.db.options
        if not opts then return end
        opts.rankPolicy = "lowest"
        UpdateSegBtnColors()
        RefreshVisiblePanels()
    end)

    btnRankR2:SetScript("OnClick", function()
        local opts = GAM.db and GAM.db.options
        if not opts then return end
        opts.rankPolicy = "highest"
        UpdateSegBtnColors()
        RefreshVisiblePanels()
    end)

    scanBtnLeft = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    scanBtnLeft:SetHeight(28)
    scanBtnLeft:SetPoint("BOTTOMLEFT",  leftPanel, "BOTTOMLEFT",  LP, LP)
    scanBtnLeft:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -LP, LP)
    scanBtnLeft:SetText(L["BTN_SCAN_ALL"])
    scanBtnLeft:SetScript("OnClick", DoScan)
    AttachButtonTooltip(scanBtnLeft, (L and L["TT_SCAN_ALL_TITLE"]) or "Scan All Items",
        (L and L["TT_SCAN_ALL_BODY"]) or "Queue all strategy items for AH price queries. The Auction House must be open.")

    local btnARP = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnARP:SetHeight(BOTTOM_BTN_H)
    btnARP:SetPoint("BOTTOMLEFT",  leftPanel, "BOTTOMLEFT",  LP,  arpRowTop)
    btnARP:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -LP, arpRowTop)
    btnARP:SetText(L["BTN_ARP_EXPORT"] or "Spreadsheet Export")
    btnARP:SetScript("OnClick", function()
        if GAM.UI and GAM.UI.DebugLog and GAM.UI.DebugLog.ShowARPExport then
            GAM.UI.DebugLog.ShowARPExport()
        end
    end)

    local btnLog = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnLog:SetHeight(BOTTOM_BTN_H)
    btnLog:SetPoint("BOTTOMLEFT",  leftPanel, "BOTTOMLEFT",  LP,  logRowTop)
    btnLog:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -LP, logRowTop)
    btnLog:SetText(L["BTN_LOG"])
    btnLog:SetScript("OnClick", function()
        if GAM.UI and GAM.UI.DebugLog then GAM.UI.DebugLog.Toggle() end
    end)

    selectedScanBtn = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    selectedScanBtn:SetHeight(28)
    selectedScanBtn:SetPoint("BOTTOMLEFT",  leftPanel, "BOTTOMLEFT",  LP,  scanRowTop)
    selectedScanBtn:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -LP, scanRowTop)
    selectedScanBtn:SetText((L and L["BTN_SCAN_SELECTED"]) or "Scan Selected Strat")
    selectedScanBtn:Disable()
    selectedScanBtn:SetAlpha(0.45)
    selectedScanBtn:SetScript("OnClick", function()
        if not rpDetail.currentStrat then return end
        ScanSingleStrategy(
            rpDetail.currentStrat,
            rpDetail.currentPatch,
            function() ShowInlineDetail(rpDetail.currentStrat, rpDetail.currentPatch) end
        )
    end)

    filterProfSet = BuildPlayerProfessionSet()
    if HasAnyEntries(filterProfSet) then
        filterMode = "mine"
        filterProf = "__mine__"
    else
        filterMode = "all"
        filterProf = "All"
        filterProfSet = nil
    end
    activeColConfig = GetActiveColumnConfig()
end

-- ===== Build =====
local function Build()
    local L = GetL()
    local C = GAM.C
    local WIN_W  = C.MAIN_WIN_W   -- 960
    local WIN_H  = C.MAIN_WIN_H   -- 580
    local HDR_PX = C.HEADER_H     -- 34
    local SB_H   = C.STATUS_BAR_H -- 22

    frame = CreateFrame("Frame", "GoldAdvisorMidnightMainWindowV2", UIParent, "BackdropTemplate")
    frame:SetSize(WIN_W, WIN_H)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetScale((GAM.db and GAM.db.options and GAM.db.options.uiScale) or 1.0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function()
        DisableShoppingSync(true)
    end)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop(THIN_BACKDROP)
    frame:SetBackdropColor(0.03, 0.03, 0.03, 1)
    frame:SetBackdropBorderColor(C_DR, C_DG, C_DB, 0.55)
    local bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0.04, 0.04, 0.04, 1)
    frame:Hide()

    -- ── Header ──
    local titleFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOP", frame, "TOP", 0, -6)
    titleFS:SetText(L["ADDON_TITLE"])
    titleFS:SetTextColor(C_GR, C_GG, C_GB)
    ApplyFontSize(titleFS, 14)

    local verFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -1)
    verFS:SetText("v" .. (GAM.C.ADDON_VERSION or "?"))
    verFS:SetTextColor(0.55, 0.45, 0.0, 1)
    ApplyFontSize(verFS, 9)

    local titleRule = frame:CreateTexture(nil, "ARTWORK")
    titleRule:SetHeight(1)
    titleRule:SetPoint("TOPLEFT",  frame, "TOPLEFT",  14, -HDR_PX)
    titleRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -HDR_PX)
    titleRule:SetColorTexture(C_DR, C_DG, C_DB, C_DA)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() MW2.Hide() end)

    -- ── Status bar (above ticker) ──
    statusBarFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    statusBarFrame:SetHeight(SB_H)
    statusBarFrame:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  14, C.TICKER_H + 8)
    statusBarFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, C.TICKER_H + 8)
    statusBarFrame:SetBackdrop(THIN_BACKDROP)
    statusBarFrame:SetBackdropColor(0.05, 0.05, 0.05, 1)
    statusBarFrame:SetBackdropBorderColor(C_DR, C_DG, C_DB, 0.35)

    local statusCountText = statusBarFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusCountText:SetPoint("LEFT", statusBarFrame, "LEFT", 8, 0)
    frame.statusCountText = statusCountText

    -- Scan progress bar
    local progBar = CreateFrame("StatusBar", nil, statusBarFrame)
    progBar:SetPoint("TOPLEFT",  statusBarFrame, "TOPLEFT",  100, -5)
    progBar:SetPoint("TOPRIGHT", statusBarFrame, "TOPRIGHT", -90, -5)
    progBar:SetHeight(12)
    progBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progBar:SetStatusBarColor(0.1, 0.7, 0.2, 1)
    progBar:SetMinMaxValues(0, 1)
    progBar:SetValue(0)
    local progBg = progBar:CreateTexture(nil, "BACKGROUND")
    progBg:SetAllPoints()
    progBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    local progLabel = progBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progLabel:SetPoint("CENTER", progBar, "CENTER")
    progLabel:SetText("")
    progBar:Hide()
    frame.progBar   = progBar
    frame.progLabel = progLabel

    -- Secondary scan button (hidden in V2; left rail is the primary scan entry)
    scanBtnStatus = CreateFrame("Button", nil, statusBarFrame, "UIPanelButtonTemplate")
    scanBtnStatus:SetSize(82, 18)
    scanBtnStatus:SetText(L["BTN_SCAN_ALL"])
    scanBtnStatus:SetPoint("RIGHT", statusBarFrame, "RIGHT", -2, 0)
    scanBtnStatus:SetScript("OnClick", DoScan)
    scanBtnStatus:Hide()

    progBar:ClearAllPoints()
    progBar:SetPoint("TOPLEFT",  statusBarFrame, "TOPLEFT",  100, -5)
    progBar:SetPoint("TOPRIGHT", statusBarFrame, "TOPRIGHT", -8, -5)

    -- ── Community info ticker ──
    -- Scrolling strip at the very bottom of the window. Pauses on hover.
    -- Clicking anywhere on it opens a small dialog to copy the tip link.
    do
        local TICK_H  = C.TICKER_H
        local TICK_SP = 55   -- pixels per second scroll speed

        local tickerClip = CreateFrame("Frame", nil, frame)
        tickerClip:SetHeight(TICK_H)
        tickerClip:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  14, 6)
        tickerClip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 6)
        tickerClip:SetClipsChildren(true)

        local tickerBg = tickerClip:CreateTexture(nil, "BACKGROUND")
        tickerBg:SetAllPoints()
        tickerBg:SetColorTexture(0.05, 0.05, 0.05, 1)

        local tickerBorder = tickerClip:CreateTexture(nil, "ARTWORK")
        tickerBorder:SetHeight(1)
        tickerBorder:SetPoint("TOPLEFT",  tickerClip, "TOPLEFT",  0, 0)
        tickerBorder:SetPoint("TOPRIGHT", tickerClip, "TOPRIGHT", 0, 0)
        tickerBorder:SetColorTexture(C_DR, C_DG, C_DB, 0.35)

        -- Content frame (holds the full-width text that scrolls inside tickerClip)
        local tickerContent = CreateFrame("Frame", nil, tickerClip)
        tickerContent:SetHeight(TICK_H)

        -- ── Ticker message ──
        -- Bullet separator: |cff888888 • |r  (dim gray dot)
        local SEP = "   \124cff888888\183\124r   "   -- \124 = | , \183 = middle dot
        -- Easter egg: 1-in-5 chance one Pepsi message sneaks into the ticker
        local pepsiEggs = {
            SEP .. "\124cff0033ccP\124cffcc0000e\124cffffffff p\124cff0033ccs\124cffcc0000i\124r  \124cffaaddffPepsi Break soon\124r",
            SEP .. "\124cff0066ffPEPSI\124r \124cffff3333RULES\124r \124cffffffff~*~\124r",
        }
        local pepsiInsert = math.random(5) == 1 and pepsiEggs[math.random(#pepsiEggs)] or ""

        local TICKER_MSG = table.concat({
            "  \124cffffcc00[Gold Advisor Midnight]\124r",
            SEP .. "\124cffff9900Twitch:\124r  twitch.tv/eloncs",
            SEP .. "\124cffff9900Patreon:\124r  patreon.com/14598821/join",
            SEP .. "\124cffff9900YouTube:\124r  youtube.com/@Elon_CS",
            SEP .. "\124cff7289daDiscord:\124r  discord.gg/v7vsCKCsFh",
            pepsiInsert,
            SEP .. "\124cff666666v" .. (GAM.version or "?") .. "\124r  ",
        }, "")
        -- Community links shown in the copy popup (label, URL)
        local COMMUNITY_LINKS = {
            { label = "Twitch",   url = "https://www.twitch.tv/eloncs" },
            { label = "Patreon",  url = "https://www.patreon.com/14598821/join" },
            { label = "YouTube",  url = "https://www.youtube.com/@Elon_CS" },
            { label = "Discord",  url = "https://discord.gg/v7vsCKCsFh" },
        }

        local tickerFS = tickerContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tickerFS:SetPoint("LEFT", tickerContent, "LEFT", 0, 0)
        tickerFS:SetJustifyH("LEFT")
        tickerFS:SetWordWrap(false)
        tickerFS:SetText(TICKER_MSG)
        ApplyFontSize(tickerFS, 9)
        tickerFS:SetTextColor(0.75, 0.75, 0.75, 1)

        -- Measure text width after layout (C_Timer gives the engine one frame)
        local tickerW = 0
        C_Timer.After(0, function()
            local tw = tickerFS:GetStringWidth() + 20
            tickerContent:SetWidth(math.max(tw, 10))
            tickerW = tickerContent:GetWidth()
            tickerContent:SetPoint("LEFT", tickerClip, "LEFT", tickerClip:GetWidth(), 0)
        end)

        local tickerX      = 0
        local tickerPaused = false
        local tickerTimer  = nil

        local function TickerTick()
            if not frame:IsShown() then return end
            if tickerPaused then return end
            local clipW = tickerClip:GetWidth()
            if tickerW == 0 then
                tickerW = tickerContent:GetWidth()
                if tickerW == 0 then return end
            end
            tickerX = tickerX - TICK_SP / 30  -- pixels per tick at ~30fps
            if tickerX < -tickerW then tickerX = clipW end
            tickerContent:ClearAllPoints()
            tickerContent:SetPoint("LEFT", tickerClip, "LEFT", tickerX, 0)
        end
        tickerTimer = C_Timer.NewTicker(0.033, TickerTick)

        tickerClip:EnableMouse(true)
        tickerClip:SetScript("OnEnter", function() tickerPaused = true end)
        tickerClip:SetScript("OnLeave", function() tickerPaused = false end)

        -- Click opens a copy-link dialog above the status bar
        tickerClip:SetScript("OnMouseDown", function()
            if not frame._tipDialog then
                local PAD = 10
                local ROW_H_D = 20
                local ROW_GAP = 8
                local LBL_H = 14
                local totalH = PAD + LBL_H + PAD + (#COMMUNITY_LINKS * (ROW_H_D + ROW_GAP)) + PAD
                local d = CreateFrame("Frame", nil, frame, "BackdropTemplate")
                d:SetSize(360, totalH)
                d:SetPoint("BOTTOM", frame, "BOTTOM", 0, TICK_H + SB_H + 16)
                d:SetBackdrop(THIN_BACKDROP)
                d:SetBackdropColor(0.05, 0.05, 0.05, 1)
                d:SetBackdropBorderColor(C_DR, C_DG, C_DB, 0.55)
                d:SetFrameStrata("TOOLTIP")
                d:SetToplevel(true)

                local hdr = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                hdr:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -PAD)
                hdr:SetText("Community links — click to select, then Ctrl+C to copy:")
                hdr:SetTextColor(C_GR, C_GG, C_GB)

                local allEBs = {}
                local yOff = -(PAD + LBL_H + PAD)
                for _, link in ipairs(COMMUNITY_LINKS) do
                    local row = CreateFrame("Frame", nil, d)
                    row:SetSize(340, ROW_H_D)
                    row:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, yOff)

                    local rowLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    rowLbl:SetPoint("LEFT", row, "LEFT", 0, 0)
                    rowLbl:SetWidth(54)
                    rowLbl:SetJustifyH("LEFT")
                    rowLbl:SetText(link.label .. ":")
                    rowLbl:SetTextColor(1, 0.6, 0, 1)   -- orange

                    local eb = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
                    eb:SetSize(280, ROW_H_D)
                    eb:SetPoint("LEFT", rowLbl, "RIGHT", 4, 0)
                    eb:SetAutoFocus(false)
                    eb:SetText(link.url)
                    eb:SetScript("OnEditFocusGained", function(s) s:HighlightText() end)
                    eb:SetScript("OnEscapePressed",   function()  d:Hide() end)
                    table.insert(allEBs, eb)

                    yOff = yOff - (ROW_H_D + ROW_GAP)
                end

                d:SetScript("OnHide", function()
                    for _, eb in ipairs(allEBs) do eb:ClearFocus() end
                end)
                frame._tipDialog = d
            end
            local d = frame._tipDialog
            if d:IsShown() then
                d:Hide()
            else
                d:Show()
            end
        end)

        frame.tickerClip = tickerClip
    end

    -- ── Divider container ──
    dividerContainer = CreateFrame("Frame", nil, frame)
    dividerContainer:SetPoint("TOPLEFT",     frame, "TOPLEFT",     14,  -(HDR_PX + 2))
    dividerContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14,  SB_H + C.TICKER_H + 14)

    -- ── Left Panel ──
    leftPanel = CreateFrame("Frame", nil, dividerContainer, "BackdropTemplate")
    leftPanel:SetWidth(C.LEFT_PANEL_W)
    leftPanel:SetPoint("TOPLEFT",    dividerContainer, "TOPLEFT",    0, 0)
    leftPanel:SetPoint("BOTTOMLEFT", dividerContainer, "BOTTOMLEFT", 0, 0)
    leftPanel:SetBackdrop(THIN_BACKDROP)
    leftPanel:SetBackdropColor(C_BG_PANEL[1], C_BG_PANEL[2], C_BG_PANEL[3], C_BG_PANEL[4])
    leftPanel:SetBackdropBorderColor(C_DR, C_DG, C_DB, 0.3)

    local leftTitle = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    leftTitle:SetPoint("TOP", leftPanel, "TOP", 0, -12)
    leftTitle:SetText((L and L["V2_TOOLS_TITLE"]) or "Strategy Tools")
    leftTitle:SetTextColor(C_GR, C_GG, C_GB)
    ApplyFontSize(leftTitle, 13)

    -- ── Right Panel ──
    rightPanel = CreateFrame("Frame", nil, dividerContainer, "BackdropTemplate")
    rightPanel:SetWidth(C.RIGHT_PANEL_W)
    rightPanel:SetPoint("TOPRIGHT",    dividerContainer, "TOPRIGHT",    0, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", dividerContainer, "BOTTOMRIGHT", 0, 0)
    rightPanel:SetBackdrop(THIN_BACKDROP)
    rightPanel:SetBackdropColor(C_BG_PANEL[1], C_BG_PANEL[2], C_BG_PANEL[3], C_BG_PANEL[4])
    rightPanel:SetBackdropBorderColor(C_DR, C_DG, C_DB, 0.3)

    local rpPlaceholder = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rpPlaceholder:SetPoint("CENTER", rightPanel, "CENTER", 0, 10)
    rpPlaceholder:SetWidth(C.RIGHT_PANEL_W - 20)
    rpPlaceholder:SetJustifyH("CENTER")
    rpPlaceholder:SetTextColor(0.5, 0.5, 0.5, 1)
    rpPlaceholder:SetText("Select a strategy to view\ncosts, outputs, and actions.")
    ApplyFontSize(rpPlaceholder, 11)
    rightPanel.placeholder = rpPlaceholder

    -- Build inline detail widgets inside the right panel
    BuildInlineDetail(rightPanel)

    -- ── Center Panel (anchored by RelayoutPanels) ──
    centerPanel = CreateFrame("Frame", nil, dividerContainer, "BackdropTemplate")
    centerPanel:SetBackdrop(THIN_BACKDROP)
    centerPanel:SetBackdropColor(0.045, 0.045, 0.045, 1)
    centerPanel:SetBackdropBorderColor(C_DR, C_DG, C_DB, 0.22)

    local LP = 10
    BuildLeftPanelContent(L, C, LP)

    -- ── Collapse toggles (children of dividerContainer so visible when panel hidden) ──
    local function MakeCollapseToggle(anchorSide, anchorX, labelDefault, panelRef, isLeft)
        local btn = CreateFrame("Button", nil, dividerContainer)
        btn:SetSize(14, 40)
        if anchorSide == "LEFT" then
            btn:SetPoint("TOPLEFT", dividerContainer, "TOPLEFT", anchorX, 12)
        else
            btn:SetPoint("TOPRIGHT", dividerContainer, "TOPRIGHT", anchorX, 12)
        end
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetAllPoints()
        lbl:SetJustifyH("CENTER")
        lbl:SetText(labelDefault)
        lbl:SetTextColor(C_GR, C_GG, C_GB)
        btn.labelFS = lbl

        btn:SetScript("OnClick", function(self)
            local opts = GAM.db.options
            if isLeft then
                opts.leftPanelCollapsed = not opts.leftPanelCollapsed
                self.labelFS:SetText(opts.leftPanelCollapsed and ">" or "<")
                self:ClearAllPoints()
                local lw = opts.leftPanelCollapsed and 0 or C.LEFT_PANEL_W
                self:SetPoint("TOPLEFT", dividerContainer, "TOPLEFT", lw, 12)
            else
                opts.rightPanelCollapsed = not opts.rightPanelCollapsed
                self.labelFS:SetText(opts.rightPanelCollapsed and "<" or ">")
                self:ClearAllPoints()
                local rw = opts.rightPanelCollapsed and 0 or C.RIGHT_PANEL_W
                self:SetPoint("TOPRIGHT", dividerContainer, "TOPRIGHT", -rw, 12)
            end
            RelayoutPanels()
        end)
        return btn
    end

    frame.btnCollapseLeft  = MakeCollapseToggle("LEFT",  C.LEFT_PANEL_W,  "<", leftPanel,  true)
    frame.btnCollapseRight = MakeCollapseToggle("RIGHT", -C.RIGHT_PANEL_W, ">", rightPanel, false)

    -- ── BestStratCard ──
    bestStratCard = CreateFrame("Button", nil, centerPanel, "BackdropTemplate")
    bestStratCard:SetHeight(CARD_H)
    bestStratCard:SetPoint("TOPLEFT",  centerPanel, "TOPLEFT",  4, -4)
    bestStratCard:SetPoint("TOPRIGHT", centerPanel, "TOPRIGHT", -4, -4)
    bestStratCard:SetBackdrop(THIN_BACKDROP)
    bestStratCard:SetBackdropColor(0.05, 0.05, 0.05, 1)
    bestStratCard:SetBackdropBorderColor(C_DR, C_DG, C_DB, 0.25)
    bestStratCard:EnableMouse(true)

    local cardBadge = bestStratCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cardBadge:SetPoint("TOP", bestStratCard, "TOP", 0, -12)
    cardBadge:SetText((L and L["V2_BEST_TITLE"]) or "Best Strategy")
    cardBadge:SetTextColor(C_GR, C_GG, C_GB)
    ApplyFontSize(cardBadge, 14)

    local cardName = bestStratCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cardName:SetPoint("TOPLEFT", bestStratCard, "TOPLEFT", 18, -40)
    cardName:SetWidth(370)
    cardName:SetJustifyH("CENTER")
    ApplyFontSize(cardName, 13)
    bestStratCard.stratNameFS = cardName

    local cardProf = bestStratCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cardProf:SetPoint("TOPLEFT", cardName, "BOTTOMLEFT", 0, -3)
    cardProf:SetWidth(370)
    cardProf:SetJustifyH("CENTER")
    cardProf:SetTextColor(0.65, 0.65, 0.65)
    ApplyFontSize(cardProf, 11)
    bestStratCard.stratProfFS = cardProf

    local cardMetrics = bestStratCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cardMetrics:SetPoint("BOTTOM", bestStratCard, "BOTTOM", 0, 36)
    cardMetrics:SetWidth(360)
    cardMetrics:SetJustifyH("CENTER")
    ApplyFontSize(cardMetrics, 12)
    bestStratCard.stratMetricsFS = cardMetrics

    local noDataText = bestStratCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    noDataText:SetPoint("CENTER", bestStratCard, "CENTER", 0, -6)
    noDataText:SetWidth(360)
    noDataText:SetJustifyH("CENTER")
    noDataText:SetTextColor(0.5, 0.5, 0.5)
    noDataText:SetText("Use the left-panel scan to see your best opportunity.")
    bestStratCard.noDataText = noDataText
    ApplyFontSize(noDataText, 10)

    local scanNowBtn = CreateFrame("Button", nil, bestStratCard, "UIPanelButtonTemplate")
    scanNowBtn:Hide()
    bestStratCard.scanNowBtn = scanNowBtn

    local openBestBtn = CreateFrame("Button", nil, bestStratCard, "UIPanelButtonTemplate")
    openBestBtn:SetSize(126, 24)
    openBestBtn:SetPoint("BOTTOM", bestStratCard, "BOTTOM", 0, 10)
    openBestBtn:SetText((L and L["BTN_OPEN_STRAT"]) or "Open Strategy")
    openBestBtn:SetScript("OnClick", function()
        if not bestStratCard.stratID then return end
        selectedStratID = bestStratCard.stratID
        local s = GAM.Importer.GetStratByID(bestStratCard.stratID)
        if s then
            if rightPanel and rightPanel:IsShown() and ShowInlineDetail then
                ShowInlineDetail(s, filterPatch)
            elseif GAM.UI.StratDetail then
                GAM.UI.StratDetail.Show(s, filterPatch)
            end
            MW2.RefreshRows()
        end
    end)
    bestStratCard.openBtn = openBestBtn

    bestStratCard:SetScript("OnClick", function(self)
        if not self.stratID then return end
        selectedStratID = self.stratID
        local s = GAM.Importer.GetStratByID(self.stratID)
        if s then
            if rightPanel and rightPanel:IsShown() and ShowInlineDetail then
                ShowInlineDetail(s, filterPatch)
            elseif GAM.UI.StratDetail then
                GAM.UI.StratDetail.Show(s, filterPatch)
            end
            if leftPanel and leftPanel.refreshStatEditors then
                leftPanel.refreshStatEditors()
            end
        end
        MW2.RefreshRows()
    end)

    -- ── Column header buttons ──
    for i = 1, 5 do
        local btn = CreateFrame("Button", nil, centerPanel)
        btn:SetHeight(HDR_H)
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("CENTER", btn, "CENTER", 0, 2)
        lbl:SetTextColor(C_GR, C_GG, C_GB)
        btn.labelFS = lbl
        btn:SetScript("OnClick", function(self)
            if not self.sortKeyV2 then return end
            if sortKey == self.sortKeyV2 then
                sortAsc = not sortAsc
            else
                sortKey = self.sortKeyV2
                sortAsc = true
            end
            RebuildList()
            MW2.RefreshRows()
        end)
        colHeaderBtns[i] = btn
    end

    -- Gold rule below column headers
    local hdrSep = centerPanel:CreateTexture(nil, "ARTWORK")
    hdrSep:SetHeight(1)
    hdrSep:SetPoint("TOPLEFT",  centerPanel, "TOPLEFT",  4,  -(CARD_H + LIST_SECTION_H + HDR_H + 8))
    hdrSep:SetPoint("TOPRIGHT", centerPanel, "TOPRIGHT", -4, -(CARD_H + LIST_SECTION_H + HDR_H + 8))
    hdrSep:SetColorTexture(C_DR, C_DG, C_DB, C_DA)

    local listSectionTitle = centerPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    listSectionTitle:SetPoint("TOPLEFT", centerPanel, "TOPLEFT", 8, -(CARD_H + 14))
    listSectionTitle:SetText((L and L["V2_ALL_STRATS"]) or "All Strategies")
    listSectionTitle:SetTextColor(C_GR, C_GG, C_GB)

    -- ── Virtual scroll list ──
    listHost = CreateFrame("Frame", nil, centerPanel)
    listHost:SetPoint("TOPLEFT",     centerPanel, "TOPLEFT",     4,  -(LIST_TOP_PAD + 4))
    listHost:SetPoint("BOTTOMRIGHT", centerPanel, "BOTTOMRIGHT", -18, 0)
    listHost:SetClipsChildren(true)

    for i = 1, VISIBLE_ROWS do
        rowFrames[i] = MakeRowFrame(listHost, i)
        rowFrames[i]:Hide()
    end

    -- Scrollbar (anchored to centerPanel in OnShow after RelayoutPanels sets size)
    local sb = CreateFrame("Slider", "GAMMainScrollBarV2", frame)
    sb:SetOrientation("VERTICAL")
    sb:SetWidth(16)
    sb:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    sb:GetThumbTexture():SetSize(16, 16)
    sb:SetMinMaxValues(0, 0)
    sb:SetValue(0)
    sb:SetValueStep(1)
    sb:SetObeyStepOnDrag(true)
    sb:SetScript("OnValueChanged", function(self, val, isUserInput)
        if suppressScrollCallback then return end
        scrollOffset = math.floor(val + 0.5)
        MW2.RefreshRows()
    end)
    frame.scrollBar = sb

    listHost:EnableMouseWheel(true)
    listHost:SetScript("OnMouseWheel", function(_, delta)
        local max = math.max(0, #filteredList - GetVisibleListRows())
        scrollOffset = math.max(0, math.min(max, scrollOffset - delta * 3))
        sb:SetValue(scrollOffset)
        MW2.RefreshRows()
    end)

    -- ── Onboarding overlay ──
    onboardingOverlay = CreateFrame("Frame", nil, centerPanel, "BackdropTemplate")
    onboardingOverlay:SetAllPoints(centerPanel)
    onboardingOverlay:SetFrameLevel(centerPanel:GetFrameLevel() + 20)
    onboardingOverlay:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", tile = true, tileSize = 8 })
    onboardingOverlay:SetBackdropColor(0, 0, 0, 0.85)
    onboardingOverlay:EnableMouse(true)
    onboardingOverlay:Hide()

    local owTitle = onboardingOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    owTitle:SetPoint("TOP", onboardingOverlay, "TOP", 0, -40)
    owTitle:SetText("Welcome to Gold Advisor Midnight")
    owTitle:SetTextColor(C_GR, C_GG, C_GB)

    local owSteps = {
        "1.  Open the Auction House.",
        "2.  Click  Scan Auction House  to fetch prices.",
        "3.  Browse strategies sorted by ROI or profit.",
    }
    local prevAnchor = owTitle
    for _, stepText in ipairs(owSteps) do
        local fs = onboardingOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOP", prevAnchor, "BOTTOM", 0, -14)
        fs:SetWidth(300)
        fs:SetJustifyH("CENTER")
        fs:SetText(stepText)
        prevAnchor = fs
    end

    local owBtnGotIt = CreateFrame("Button", nil, onboardingOverlay, "UIPanelButtonTemplate")
    owBtnGotIt:SetSize(100, 26)
    owBtnGotIt:SetPoint("BOTTOM", onboardingOverlay, "BOTTOM", -60, 30)
    owBtnGotIt:SetText("Got It")
    owBtnGotIt:SetScript("OnClick", DismissOnboarding)

    local owBtnScan = CreateFrame("Button", nil, onboardingOverlay, "UIPanelButtonTemplate")
    owBtnScan:SetSize(140, 26)
    owBtnScan:SetPoint("BOTTOM", onboardingOverlay, "BOTTOM", 50, 30)
    owBtnScan:SetText(L["BTN_SCAN_ALL"])
    owBtnScan:SetScript("OnClick", function()
        DismissOnboarding()
        DoScan()
    end)

    -- ── OnShow ──
    frame:SetScript("OnShow", function()
        -- Restore collapse toggle arrow labels to match saved state
        local opts = GAM.db and GAM.db.options
        if opts then
            if frame.btnCollapseLeft  then
                frame.btnCollapseLeft.labelFS:SetText(opts.leftPanelCollapsed  and ">" or "<")
                if opts.leftPanelCollapsed then
                    frame.btnCollapseLeft:ClearAllPoints()
                    frame.btnCollapseLeft:SetPoint("TOPLEFT", dividerContainer, "TOPLEFT", 0, 12)
                else
                    frame.btnCollapseLeft:ClearAllPoints()
                    frame.btnCollapseLeft:SetPoint("TOPLEFT", dividerContainer, "TOPLEFT", C.LEFT_PANEL_W, 12)
                end
            end
            if frame.btnCollapseRight then
                frame.btnCollapseRight.labelFS:SetText(opts.rightPanelCollapsed and "<" or ">")
                if opts.rightPanelCollapsed then
                    frame.btnCollapseRight:ClearAllPoints()
                    frame.btnCollapseRight:SetPoint("TOPRIGHT", dividerContainer, "TOPRIGHT", 0, 12)
                else
                    frame.btnCollapseRight:ClearAllPoints()
                    frame.btnCollapseRight:SetPoint("TOPRIGHT", dividerContainer, "TOPRIGHT", -C.RIGHT_PANEL_W, 12)
                end
            end
        end

        -- Layout panels and anchor scrollbar
        RelayoutPanels()
        sb:ClearAllPoints()
        sb:SetPoint("TOPRIGHT",    centerPanel, "TOPRIGHT",    2,  -(LIST_TOP_PAD + 4))
        sb:SetPoint("BOTTOMRIGHT", centerPanel, "BOTTOMRIGHT", 2,  0)

        RebuildList()
        MW2.RefreshRows()
        RefreshBestStratCard()
        if leftPanel and leftPanel.refreshStatEditors then
            leftPanel.refreshStatEditors()
        end

        if opts and not opts.hasSeenOnboarding then
            opts.hasSeenOnboarding = true
            onboardingOverlay:Hide()
        end
    end)

end

-- ===== Public API =====

function MW2.RefreshProfessionDropdown()
    -- V2 uses segmented buttons; no dropdown to refresh
end

function MW2.SyncSourceCheckboxes()
    local opts = GAM.db and GAM.db.options
    if not opts then return end
    if leftPanelChecks.millOwn    then leftPanelChecks.millOwn:SetChecked((opts.pigmentCostSource or "ah") == "mill") end
    if leftPanelChecks.craftBolts then leftPanelChecks.craftBolts:SetChecked((opts.boltCostSource or "ah") == "craft") end
    if leftPanelChecks.craftIngots then leftPanelChecks.craftIngots:SetChecked((opts.ingotCostSource or "ah") == "craft") end
end

function MW2.OnScanProgress(done, total, isComplete)
    if not frame then return end
    if isComplete then
        frame.progBar:Hide()
        frame.progLabel:SetText("")
        SetScanningState(false)
    else
        SetScanningState(true)
        frame.progBar:Show()
        if total and total > 0 then
            frame.progBar:SetValue(done / total)
            frame.progLabel:SetText(string.format("%d / %d  " .. GAM.L["STATUS_SCANNING_PROG"], done, total))
        else
            frame.progBar:SetValue(0)
            frame.progLabel:SetText(GAM.L["STATUS_QUEUING"])
        end
        if frame:IsShown() and done and done > 0 then
            local now = GetTime()
            if (now - lastScanRefreshAt) >= 0.75 then
                lastScanRefreshAt = now
                -- Skip RebuildList during scan: prices update per-item so the sort
                -- order is unstable mid-scan, and the sort itself is expensive when
                -- the price cache is warm. Full re-sort happens at OnScanComplete.
                MW2.RefreshRows()
                RefreshBestStratCard()
                if rpDetail.currentStrat and rpDetail.root and rpDetail.root:IsShown() then
                    ShowInlineDetail(rpDetail.currentStrat, rpDetail.currentPatch)
                end
            end
        end
    end
end

function MW2.OnScanComplete()
    if frame and frame:IsShown() then
        sortKey = "roi"
        sortAsc = true
        RebuildList()
        MW2.RefreshRows()
        RefreshBestStratCard()
        if leftPanel and leftPanel.refreshStatEditors then
            leftPanel.refreshStatEditors()
        end
        SetScanningState(false)
    end
end

function MW2.Refresh()
    if not frame then return end
    RebuildList()
    MW2.RefreshRows()
    RefreshBestStratCard()
    if leftPanel and leftPanel.refreshStatEditors then
        leftPanel.refreshStatEditors()
    end
    -- Re-populate inline detail if one was showing (e.g. after strat edit/delete)
    if rpDetail.currentStrat and rpDetail.root and rpDetail.root:IsShown() then
        local refreshed = rpDetail.currentStrat.id and GAM.Importer.GetStratByID(rpDetail.currentStrat.id)
        if refreshed then
            rpDetail.currentStrat = refreshed
            ShowInlineDetail(refreshed, rpDetail.currentPatch)
        else
            rpDetail.currentStrat = nil
            rpDetail.currentPatch = nil
            HideInlineDetail()
        end
    end
end

function MW2.Show()
    if not frame then Build() end
    frame:Show()
end

function MW2.Hide()
    DisableShoppingSync(true)
    if frame then frame:Hide() end
end

function MW2.Toggle()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function MW2.IsShown()
    return frame and frame:IsShown()
end
