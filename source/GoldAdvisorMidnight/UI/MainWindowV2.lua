-- GoldAdvisorMidnight/UI/MainWindowV2.lua
-- Three-panel redesign: Left (tools/scan), Center (strategy list), Right (inline detail).
-- Best Strategy hero card, collapsible panels, onboarding overlay.
-- Opt-in via Settings > "Use New UI Layout (Beta)".
-- Module: GAM.UI.MainWindowV2

local ADDON_NAME, GAM = ...
local MW2 = {}
GAM.UI.MainWindowV2 = MW2

-- ===== Layout constants =====
local ROW_H        = 22
local VISIBLE_ROWS = 30
local CARD_H       = 90
local HDR_H        = 20
local LIST_TOP_PAD = CARD_H + 6 + HDR_H + 4   -- offset from center top to listHost

-- Color constants (module-local)
local C_BG_PANEL = { 0.06, 0.06, 0.06, 1.0 }
local C_GR, C_GG, C_GB = 1.0, 0.82, 0.0        -- gold
local C_DR, C_DG, C_DB, C_DA = 0.7, 0.57, 0.0, 0.7  -- dimmed gold (rules)

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
local filterPatch   = GAM.C.DEFAULT_PATCH
local filterProf    = "All"
local sortKey       = "roi"
local sortAsc       = true
local scanning      = false
local scanBtnLeft, scanBtnStatus
local activeColConfig = LIST_COLUMNS_ALL
local rpDetail      = {}   -- inline right-panel detail widget refs

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
        if filterProf == "All" or s.profession == filterProf then
            out[#out + 1] = s
        end
    end
    local fn = SORT_FNS[sortKey] or SORT_FNS.roi
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
        -- scan button is informational while scanning; clicking again could stop
        if isScanning then scanBtnLeft:Disable() else scanBtnLeft:Enable() end
    end
    if scanBtnStatus then
        scanBtnStatus:SetText(lbl)
        if isScanning then scanBtnStatus:Disable() else scanBtnStatus:Enable() end
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
    row.nameText = nameText

    local profSubText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profSubText:SetJustifyH("LEFT")
    profSubText:SetTextColor(0.65, 0.65, 0.65, 0.85)
    row.profSubText = profSubText

    local profText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profText:SetJustifyH("LEFT")
    row.profText = profText

    local profitText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profitText:SetJustifyH("RIGHT")
    row.profitText = profitText

    local roiText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    roiText:SetJustifyH("RIGHT")
    row.roiText = roiText

    local missingText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    missingText:SetJustifyH("LEFT")
    missingText:SetTextColor(1, 0.6, 0)
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
    local isAll = (config == LIST_COLUMNS_ALL)

    for i, col in ipairs(config) do
        local btn = colHeaderBtns[i]
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", centerPanel, "TOPLEFT", col.x, -(CARD_H + 8))
            btn:SetWidth(col.w)
            btn.labelFS:SetText(L and L[col.hKey] or col.hKey)
            btn.labelFS:SetJustifyH(col.j)
            btn.sortKeyV2 = col.sKey
            btn:Show()
        end
    end
    for i = #config + 1, #colHeaderBtns do
        if colHeaderBtns[i] then colHeaderBtns[i]:Hide() end
    end

    for _, row in ipairs(rowFrames) do
        if rowW then row:SetWidth(rowW) end

        for _, col in ipairs(config) do
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

        -- Profession column text shown only in ALL mode
        row.profText:SetShown(isAll)

        -- Profession subtitle shown only in FILTERED mode (below strat name)
        if not isAll then
            row.profSubText:ClearAllPoints()
            row.profSubText:SetPoint("TOPLEFT", row, "TOPLEFT", 14 + STRAT_ICON_W, -11)
            row.profSubText:SetWidth(240)
            row.profSubText:Show()
        else
            row.profSubText:Hide()
        end
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
    row.profSubText:SetText(strat.profession)

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
    for i, row in ipairs(rowFrames) do
        local strat = filteredList[scrollOffset + i]
        if strat then
            PopulateRow(row, strat)
        else
            row:Hide()
            row.stratID = nil
        end
    end
    if frame.scrollBar then
        local max = math.max(0, #filteredList - VISIBLE_ROWS)
        frame.scrollBar:SetMinMaxValues(0, max)
        frame.scrollBar:SetValue(scrollOffset)
    end
    if frame.statusCountText then
        local L = GetL()
        frame.statusCountText:SetText(string.format(L and L["STATUS_STRAT_COUNT"] or "%d strategies", #filteredList))
    end
end

-- ===== BestStratCard =====
local function RefreshBestStratCard()
    if not bestStratCard then return end
    local best, profit, roi = GAM.Pricing.GetBestStrategy(filterPatch, filterProf)
    if best then
        bestStratCard.noDataText:Hide()
        bestStratCard.scanNowBtn:Hide()
        bestStratCard.stratNameFS:SetText(best.stratName)
        bestStratCard.stratProfFS:SetText(best.profession)
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
        bestStratCard.scanNowBtn:Show()
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

    activeColConfig = (filterProf == "All") and LIST_COLUMNS_ALL or LIST_COLUMNS_FILTERED
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
end

ShowInlineDetail = function(strat, patchTag)
    if not rpDetail.root then return end
    local L = GetL()
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    local m  = GAM.Pricing.CalculateStratMetrics(strat, patchTag)

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

    -- Reagent rows (Name | Need to Buy | Unit Price)
    local reagentMetrics = m and m.reagents or {}
    for i, row in ipairs(rpDetail.reagentRows) do
        local rDef = strat.reagents and strat.reagents[i]
        local rMet = reagentMetrics[i]
        if rDef and rMet then
            row.nameFS:SetText(rDef.name or "?")
            row.qtyFS:SetText(string.format("%.0f", rMet.needToBuy or 0))
            row.priceFS:SetText(rMet.unitPrice
                and GAM.Pricing.FormatPrice(rMet.unitPrice)
                or "|cffff8800—|r")
            row:Show()
        else
            row:Hide()
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
            row.nameFS:SetText(oi.name or "?")
            row.qtyFS:SetText(oi.expectedQty
                and string.format("%.0f", math.floor(oi.expectedQty)) or "—")
            row:Show()
        else
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
    rpDetail.root:Show()
end

local function BuildInlineDetail(panel)
    local L  = GetL()
    local RW = GAM.C.RIGHT_PANEL_W   -- 340
    local P  = 10                    -- padding
    local UW = RW - P * 2            -- usable width: 320

    local root = CreateFrame("Frame", nil, panel)
    root:SetAllPoints(panel)
    root:Hide()
    rpDetail.root = root

    -- Running y position (negative = down from top)
    local y = -P

    -- ── Strat name ──
    local nameFS = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameFS:SetPoint("TOPLEFT", root, "TOPLEFT", P, y)
    nameFS:SetWidth(UW)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetTextColor(C_GR, C_GG, C_GB)
    nameFS:SetWordWrap(true)
    rpDetail.nameFS = nameFS
    y = y - 34

    local profFS = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profFS:SetPoint("TOPLEFT", root, "TOPLEFT", P, y)
    profFS:SetWidth(UW)
    profFS:SetTextColor(0.65, 0.65, 0.65)
    rpDetail.profFS = profFS
    y = y - 16

    local notesFS = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    notesFS:SetPoint("TOPLEFT", root, "TOPLEFT", P, y)
    notesFS:SetWidth(UW)
    notesFS:SetTextColor(0.8, 0.8, 0.5)
    notesFS:SetWordWrap(true)
    rpDetail.notesFS = notesFS
    y = y - 16

    -- Gold rule
    local function MakeRule(yOff, alpha)
        local r = root:CreateTexture(nil, "ARTWORK")
        r:SetHeight(1)
        r:SetPoint("TOPLEFT",  root, "TOPLEFT",  P,  yOff)
        r:SetPoint("TOPRIGHT", root, "TOPRIGHT", -P, yOff)
        r:SetColorTexture(C_DR, C_DG, C_DB, alpha or C_DA)
        return r
    end
    MakeRule(y)
    y = y - 6

    -- ── Metrics ──
    local LBL_W = 100
    local function MakeMetricRow(label, yOff)
        local lbl = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", root, "TOPLEFT", P, yOff)
        lbl:SetWidth(LBL_W)
        lbl:SetText(label)
        local val = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        val:SetPoint("TOPLEFT", root, "TOPLEFT", P + LBL_W + 6, yOff)
        val:SetWidth(UW - LBL_W - 6)
        val:SetJustifyH("LEFT")
        return val, yOff - 18
    end

    rpDetail.metCostFS,      y = MakeMetricRow(L and L["LBL_COST"]      or "Cost:",       y)
    rpDetail.metRevenueFS,   y = MakeMetricRow(L and L["LBL_REVENUE"]   or "Revenue:",    y)
    MakeRule(y, 0.4)
    y = y - 4
    rpDetail.metProfitFS,    y = MakeMetricRow(L and L["LBL_PROFIT"]    or "Profit:",     y)
    rpDetail.metROIFS,       y = MakeMetricRow(L and L["LBL_ROI"]       or "ROI:",        y)
    rpDetail.metBreakevenFS, y = MakeMetricRow(L and L["LBL_BREAKEVEN"] or "Break-even:", y)

    -- Fill qty notice
    local fillFS = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fillFS:SetPoint("TOPLEFT", root, "TOPLEFT", P, y)
    fillFS:SetWidth(UW)
    fillFS:SetTextColor(1.0, 0.65, 0.0)
    rpDetail.fillNoticeFS = fillFS
    y = y - 16

    MakeRule(y)
    y = y - 6

    -- ── Reagents ──
    local reagHdr = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reagHdr:SetPoint("TOPLEFT", root, "TOPLEFT", P, y)
    reagHdr:SetText(L and L["DETAIL_INPUT_HDR"] or "Reagents")
    reagHdr:SetTextColor(C_GR, C_GG, C_GB)
    y = y - 18

    -- Column widths: Name(130) | Need(62) | Price(rest)
    local RN, RQ, RP = 130, 62, UW - 130 - 62

    local function MakeSmallColHdr(text, xOff, w, yOff)
        local fs = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", root, "TOPLEFT", P + xOff, yOff)
        fs:SetWidth(w)
        fs:SetText(text)
        fs:SetTextColor(C_DR, C_DG, C_DB)
        fs:SetJustifyH("LEFT")
    end
    MakeSmallColHdr(L and L["COL_ITEM"]       or "Item",      0,        RN, y)
    MakeSmallColHdr(L and L["COL_NEED_BUY"]   or "Need",      RN,       RQ, y)
    MakeSmallColHdr(L and L["COL_UNIT_PRICE"] or "Price",     RN + RQ,  RP, y)
    y = y - 3
    MakeRule(y, 0.5)
    y = y - 2

    rpDetail.reagentRows = {}
    for i = 1, 8 do
        local rRow = CreateFrame("Frame", nil, root)
        rRow:SetSize(UW, ROW_H)
        rRow:SetPoint("TOPLEFT", root, "TOPLEFT", P, y - (i - 1) * ROW_H)
        local nFS = rRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nFS:SetPoint("LEFT", rRow, "LEFT", 0, 0)
        nFS:SetWidth(RN - 2)
        nFS:SetJustifyH("LEFT")
        local qFS = rRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        qFS:SetPoint("LEFT", rRow, "LEFT", RN, 0)
        qFS:SetWidth(RQ)
        qFS:SetJustifyH("RIGHT")
        local pFS = rRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pFS:SetPoint("LEFT", rRow, "LEFT", RN + RQ, 0)
        pFS:SetWidth(RP)
        pFS:SetJustifyH("RIGHT")
        rRow.nameFS = nFS
        rRow.qtyFS  = qFS
        rRow.priceFS = pFS
        rRow:Hide()
        rpDetail.reagentRows[i] = rRow
    end
    y = y - 8 * ROW_H - 4

    MakeRule(y)
    y = y - 6

    -- ── Outputs ──
    local outHdr = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    outHdr:SetPoint("TOPLEFT", root, "TOPLEFT", P, y)
    outHdr:SetText(L and L["DETAIL_OUTPUT_HDR"] or "Outputs")
    outHdr:SetTextColor(C_GR, C_GG, C_GB)
    y = y - 18

    local ON, OQ = 185, UW - 185
    MakeSmallColHdr(L and L["COL_ITEM"]       or "Item",         0,  ON, y)
    MakeSmallColHdr(L and L["COL_QTY_CRAFT"]  or "Expected Qty", ON, OQ, y)
    y = y - 3
    MakeRule(y, 0.5)
    y = y - 2

    rpDetail.outputRows = {}
    for i = 1, 4 do
        local oRow = CreateFrame("Frame", nil, root)
        oRow:SetSize(UW, ROW_H)
        oRow:SetPoint("TOPLEFT", root, "TOPLEFT", P, y - (i - 1) * ROW_H)
        local nFS = oRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nFS:SetPoint("LEFT", oRow, "LEFT", 0,  0)
        nFS:SetWidth(ON - 2)
        nFS:SetJustifyH("LEFT")
        local qFS = oRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        qFS:SetPoint("LEFT", oRow, "LEFT", ON, 0)
        qFS:SetWidth(OQ)
        qFS:SetJustifyH("RIGHT")
        oRow.nameFS = nFS
        oRow.qtyFS  = qFS
        oRow:Hide()
        rpDetail.outputRows[i] = oRow
    end
    y = y - 4 * ROW_H - 4

    MakeRule(y)

    -- ── Action buttons (bottom of panel) ──
    local BY1 = P + 24 + 4   -- first row from bottom
    local BY0 = P             -- second row from bottom (Edit/Delete)

    local function MakeRPBtn(lbl, w, xOff, rowY)
        local b = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetText(lbl)
        b:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", P + xOff, rowY)
        return b
    end

    local btnScanAll = MakeRPBtn(L and L["BTN_SCAN_ALL_ITEMS"] or "Scan All", 76, 0, BY1)
    btnScanAll:SetScript("OnClick", function()
        if not GAM.ahOpen or not rpDetail.currentStrat then return end
        local s, pt = rpDetail.currentStrat, rpDetail.currentPatch
        GAM.AHScan.StopScan()
        GAM.AHScan.ResetQueue()
        local pdb = GAM:GetPatchDB(pt)
        local function queueItem(item)
            if not item or not item.name then return end
            local ids = item.itemIDs
            if not ids or #ids == 0 then ids = pdb.rankGroups[item.name] or {} end
            if ids and #ids > 0 then
                for _, id in ipairs(ids) do
                    GAM.AHScan.QueueItemScan(id, function() ShowInlineDetail(s, pt) end)
                end
            else
                GAM.AHScan.QueueNameScan(item.name, pt, function() ShowInlineDetail(s, pt) end)
            end
        end
        queueItem(s.output)
        for _, o in ipairs(s.outputs or {}) do queueItem(o) end
        for _, r in ipairs(s.reagents or {}) do queueItem(r) end
        GAM.AHScan.StartScan()
    end)

    local btnCraftSim = MakeRPBtn(L and L["BTN_PUSH_CRAFTSIM"] or "CraftSim", 84, 84, BY1)
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

    local btnShop = MakeRPBtn(L and L["BTN_AUCTIONATOR"] or "Shopping", 84, 176, BY1)
    btnShop:SetScript("OnClick", function()
        -- Open full floating StratDetail which has Auctionator integration
        if rpDetail.currentStrat and GAM.UI.StratDetail then
            GAM.UI.StratDetail.Show(rpDetail.currentStrat, rpDetail.currentPatch)
        end
    end)

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
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left=11, right=12, top=12, bottom=11 },
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    local bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0.04, 0.04, 0.04, 1)
    frame:Hide()

    -- ── Header ──
    local titleFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOP", frame, "TOP", 0, -8)
    titleFS:SetText(L["MAIN_TITLE"])
    titleFS:SetTextColor(C_GR, C_GG, C_GB)

    local titleRule = frame:CreateTexture(nil, "ARTWORK")
    titleRule:SetHeight(1)
    titleRule:SetPoint("TOPLEFT",  frame, "TOPLEFT",  14, -HDR_PX)
    titleRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -HDR_PX)
    titleRule:SetColorTexture(C_DR, C_DG, C_DB, C_DA)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- ── Status bar (bottom strip) ──
    statusBarFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    statusBarFrame:SetHeight(SB_H)
    statusBarFrame:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  14, 6)
    statusBarFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 6)
    statusBarFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", tile = true, tileSize = 8 })
    statusBarFrame:SetBackdropColor(0.08, 0.08, 0.08, 1)

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

    -- Secondary scan button (right end of status bar)
    scanBtnStatus = CreateFrame("Button", nil, statusBarFrame, "UIPanelButtonTemplate")
    scanBtnStatus:SetSize(82, 18)
    scanBtnStatus:SetText(L["BTN_SCAN_ALL"])
    scanBtnStatus:SetPoint("RIGHT", statusBarFrame, "RIGHT", -2, 0)
    scanBtnStatus:SetScript("OnClick", DoScan)

    -- ── Divider container ──
    dividerContainer = CreateFrame("Frame", nil, frame)
    dividerContainer:SetPoint("TOPLEFT",     frame, "TOPLEFT",     14,  -(HDR_PX + 2))
    dividerContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14,  SB_H + 10)

    -- ── Left Panel ──
    leftPanel = CreateFrame("Frame", nil, dividerContainer, "BackdropTemplate")
    leftPanel:SetWidth(C.LEFT_PANEL_W)
    leftPanel:SetPoint("TOPLEFT",    dividerContainer, "TOPLEFT",    0, 0)
    leftPanel:SetPoint("BOTTOMLEFT", dividerContainer, "BOTTOMLEFT", 0, 0)
    leftPanel:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8,
        insets = { left=1, right=1, top=1, bottom=1 },
    })
    leftPanel:SetBackdropColor(C_BG_PANEL[1], C_BG_PANEL[2], C_BG_PANEL[3], C_BG_PANEL[4])
    leftPanel:SetBackdropBorderColor(C_DR, C_DG, C_DB, 0.4)

    -- ── Right Panel ──
    rightPanel = CreateFrame("Frame", nil, dividerContainer, "BackdropTemplate")
    rightPanel:SetWidth(C.RIGHT_PANEL_W)
    rightPanel:SetPoint("TOPRIGHT",    dividerContainer, "TOPRIGHT",    0, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", dividerContainer, "BOTTOMRIGHT", 0, 0)
    rightPanel:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8,
        insets = { left=1, right=1, top=1, bottom=1 },
    })
    rightPanel:SetBackdropColor(C_BG_PANEL[1], C_BG_PANEL[2], C_BG_PANEL[3], C_BG_PANEL[4])
    rightPanel:SetBackdropBorderColor(C_DR, C_DG, C_DB, 0.4)

    local rpPlaceholder = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rpPlaceholder:SetPoint("TOP", rightPanel, "TOP", 0, -30)
    rpPlaceholder:SetWidth(C.RIGHT_PANEL_W - 20)
    rpPlaceholder:SetJustifyH("CENTER")
    rpPlaceholder:SetTextColor(0.5, 0.5, 0.5, 1)
    rpPlaceholder:SetText("Select a strategy\nto view details.")
    rightPanel.placeholder = rpPlaceholder

    -- Build inline detail widgets inside the right panel
    BuildInlineDetail(rightPanel)

    -- ── Center Panel (anchored by RelayoutPanels) ──
    centerPanel = CreateFrame("Frame", nil, dividerContainer)

    -- ── Left panel content ──
    local LP = 10   -- padding

    local charNameFS = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    charNameFS:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP, -LP)
    charNameFS:SetWidth(C.LEFT_PANEL_W - LP * 2)
    charNameFS:SetJustifyH("LEFT")
    charNameFS:SetTextColor(C_GR, C_GG, C_GB)
    charNameFS:SetText(UnitName("player") or "—")

    local realmFS = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    realmFS:SetPoint("TOPLEFT", charNameFS, "BOTTOMLEFT", 0, -2)
    realmFS:SetWidth(C.LEFT_PANEL_W - LP * 2)
    realmFS:SetJustifyH("LEFT")
    realmFS:SetTextColor(0.6, 0.6, 0.6, 1)
    realmFS:SetText(GetRealmName() or "—")

    local lpRule = leftPanel:CreateTexture(nil, "ARTWORK")
    lpRule:SetHeight(1)
    lpRule:SetPoint("TOPLEFT",  leftPanel, "TOPLEFT",  LP, -50)
    lpRule:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -LP, -50)
    lpRule:SetColorTexture(C_DR, C_DG, C_DB, 0.4)

    local filterLbl = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterLbl:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP, -58)
    filterLbl:SetText(L["FILTER_PROFESSION"])
    filterLbl:SetTextColor(C_GR, C_GG, C_GB)

    -- Segmented filter buttons
    local SEG_W = math.floor((C.LEFT_PANEL_W - LP * 2 - 4) / 2)
    local btnFilterAll  = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnFilterAll:SetSize(SEG_W, 22)
    btnFilterAll:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP, -78)
    btnFilterAll:SetText("All")

    local btnFilterMine = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnFilterMine:SetSize(SEG_W, 22)
    btnFilterMine:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", LP + SEG_W + 4, -78)
    btnFilterMine:SetText("My Profs")

    leftPanel.btnFilterAll  = btnFilterAll
    leftPanel.btnFilterMine = btnFilterMine

    local function UpdateSegBtnColors()
        local isAll = (filterProf == "All")
        local goldR, goldG, goldB = isAll and C_GR or 0.5, isAll and C_GG or 0.5, isAll and C_GB or 0.5
        local mineR, mineG, mineB = isAll and 0.5 or C_GR, isAll and 0.5 or C_GG, isAll and 0.5 or C_GB
        -- Tint the button overlay textures
        if btnFilterAll:GetFontString()  then btnFilterAll:GetFontString():SetTextColor(goldR, goldG, goldB) end
        if btnFilterMine:GetFontString() then btnFilterMine:GetFontString():SetTextColor(mineR, mineG, mineB) end
    end
    UpdateSegBtnColors()

    btnFilterAll:SetScript("OnClick", function()
        filterProf = "All"
        activeColConfig = LIST_COLUMNS_ALL
        UpdateSegBtnColors()
        RebuildList()
        RelayoutPanels()
    end)

    btnFilterMine:SetScript("OnClick", function()
        -- Detect character professions via GetProfessions() (classic API available in Midnight)
        local found = nil
        if GetProfessions then
            local indices = { GetProfessions() }
            for _, idx in ipairs(indices) do
                if idx then
                    local profName = GetProfessionInfo(idx)
                    if profName and GAM.Importer then
                        -- Check if this profession has strats
                        for _, p in ipairs(GAM.Importer.GetAllProfessions(filterPatch)) do
                            if p == profName then
                                found = profName
                                break
                            end
                        end
                        if found then break end
                    end
                end
            end
        end
        filterProf = found or "All"
        activeColConfig = (filterProf == "All") and LIST_COLUMNS_ALL or LIST_COLUMNS_FILTERED
        UpdateSegBtnColors()
        RebuildList()
        RelayoutPanels()
    end)

    -- Large primary scan button at bottom of left panel
    scanBtnLeft = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    scanBtnLeft:SetHeight(28)
    scanBtnLeft:SetPoint("BOTTOMLEFT",  leftPanel, "BOTTOMLEFT",  LP, LP)
    scanBtnLeft:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -LP, LP)
    scanBtnLeft:SetText(L["BTN_SCAN_ALL"])
    scanBtnLeft:SetScript("OnClick", DoScan)

    -- Log + ARP buttons above scan button
    local btnLog = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    btnLog:SetHeight(22)
    btnLog:SetPoint("BOTTOMLEFT",  leftPanel, "BOTTOMLEFT",  LP,  LP + 28 + 4)
    btnLog:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -LP, LP + 28 + 4)
    btnLog:SetText(L["BTN_LOG"])
    btnLog:SetScript("OnClick", function()
        if GAM.UI and GAM.UI.DebugLog then GAM.UI.DebugLog.Toggle() end
    end)

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
    bestStratCard:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8,
        insets = { left=2, right=2, top=2, bottom=2 },
    })
    bestStratCard:SetBackdropColor(0.07, 0.06, 0.02, 1)
    bestStratCard:SetBackdropBorderColor(C_GR, C_GG, C_GB, 0.7)
    bestStratCard:EnableMouse(true)

    local cardBadge = bestStratCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cardBadge:SetPoint("TOPLEFT", bestStratCard, "TOPLEFT", 8, -6)
    cardBadge:SetText("BEST STRATEGY RIGHT NOW")
    cardBadge:SetTextColor(C_GR, C_GG, C_GB)

    local cardName = bestStratCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cardName:SetPoint("TOPLEFT", bestStratCard, "TOPLEFT", 8, -22)
    cardName:SetWidth(320)
    cardName:SetJustifyH("LEFT")
    bestStratCard.stratNameFS = cardName

    local cardProf = bestStratCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cardProf:SetPoint("TOPLEFT", cardName, "BOTTOMLEFT", 0, -2)
    cardProf:SetTextColor(0.65, 0.65, 0.65)
    bestStratCard.stratProfFS = cardProf

    local cardMetrics = bestStratCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cardMetrics:SetPoint("TOPRIGHT", bestStratCard, "TOPRIGHT", -8, -22)
    cardMetrics:SetJustifyH("RIGHT")
    bestStratCard.stratMetricsFS = cardMetrics

    local noDataText = bestStratCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    noDataText:SetPoint("LEFT", bestStratCard, "LEFT", 8, 0)
    noDataText:SetTextColor(0.5, 0.5, 0.5)
    noDataText:SetText("Scan the AH to see your best opportunity.")
    bestStratCard.noDataText = noDataText

    local scanNowBtn = CreateFrame("Button", nil, bestStratCard, "UIPanelButtonTemplate")
    scanNowBtn:SetSize(80, 20)
    scanNowBtn:SetPoint("RIGHT", bestStratCard, "RIGHT", -8, 0)
    scanNowBtn:SetText(L["BTN_SCAN_ALL"])
    scanNowBtn:SetScript("OnClick", DoScan)
    bestStratCard.scanNowBtn = scanNowBtn

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
        end
        MW2.RefreshRows()
    end)

    -- ── Column header buttons ──
    for i = 1, 5 do
        local btn = CreateFrame("Button", nil, centerPanel)
        btn:SetHeight(HDR_H)
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetAllPoints()
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
    hdrSep:SetPoint("TOPLEFT",  centerPanel, "TOPLEFT",  4,  -(CARD_H + 6 + HDR_H + 2))
    hdrSep:SetPoint("TOPRIGHT", centerPanel, "TOPRIGHT", -4, -(CARD_H + 6 + HDR_H + 2))
    hdrSep:SetColorTexture(C_DR, C_DG, C_DB, C_DA)

    -- ── Virtual scroll list ──
    listHost = CreateFrame("Frame", nil, centerPanel)
    listHost:SetPoint("TOPLEFT",     centerPanel, "TOPLEFT",     4,  -(LIST_TOP_PAD + 2))
    listHost:SetPoint("BOTTOMRIGHT", centerPanel, "BOTTOMRIGHT", -18, 0)

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
        if not isUserInput then return end
        scrollOffset = math.floor(val + 0.5)
        MW2.RefreshRows()
    end)
    frame.scrollBar = sb

    listHost:EnableMouseWheel(true)
    listHost:SetScript("OnMouseWheel", function(_, delta)
        local max = math.max(0, #filteredList - VISIBLE_ROWS)
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
        sb:SetPoint("TOPRIGHT",    centerPanel, "TOPRIGHT",    2,  -(LIST_TOP_PAD + 2))
        sb:SetPoint("BOTTOMRIGHT", centerPanel, "BOTTOMRIGHT", 2,  0)

        RebuildList()
        MW2.RefreshRows()
        RefreshBestStratCard()

        if opts and not opts.hasSeenOnboarding then
            onboardingOverlay:SetAllPoints(centerPanel)
            onboardingOverlay:SetFrameLevel(centerPanel:GetFrameLevel() + 20)
            onboardingOverlay:Show()
        end
    end)

    -- Wire scan progress callback
    if GAM.AHScan then
        GAM.AHScan.SetProgressCallback(MW2.OnScanProgress)
    end
end

-- ===== Public API =====

function MW2.RefreshProfessionDropdown()
    -- V2 uses segmented buttons; no dropdown to refresh
end

function MW2.OnScanProgress(done, total, isComplete)
    if not frame then return end
    if isComplete then
        frame.progBar:Hide()
        frame.progLabel:SetText("")
        SetScanningState(false)
    else
        frame.progBar:Show()
        if total and total > 0 then
            frame.progBar:SetValue(done / total)
            frame.progLabel:SetText(string.format("%d / %d  " .. GAM.L["STATUS_SCANNING_PROG"], done, total))
        else
            frame.progBar:SetValue(0)
            frame.progLabel:SetText(GAM.L["STATUS_QUEUING"])
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
        SetScanningState(false)
    end
end

function MW2.Refresh()
    if not frame then return end
    RebuildList()
    MW2.RefreshRows()
    RefreshBestStratCard()
    -- Re-populate inline detail if one was showing (e.g. after strat edit/delete)
    if rpDetail.currentStrat and rpDetail.root and rpDetail.root:IsShown() then
        ShowInlineDetail(rpDetail.currentStrat, rpDetail.currentPatch)
    end
end

function MW2.Show()
    if not frame then Build() end
    frame:Show()
end

function MW2.Hide()
    if frame then frame:Hide() end
end

function MW2.Toggle()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function MW2.IsShown()
    return frame and frame:IsShown()
end
