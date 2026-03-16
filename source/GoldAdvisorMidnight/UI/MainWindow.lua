-- GoldAdvisorMidnight/UI/MainWindow.lua
-- Main strategy list: virtual scroll, profession filter, sort, favorites,
-- scan progress bar. Gold accent title, column headers, and separator.
-- Module: GAM.UI.MainWindow

local ADDON_NAME, GAM = ...
local MW = {}
GAM.UI.MainWindow = MW
local L = GAM.L   -- file-scope so all module functions (RefreshRows, etc.) can access it

local WIN_W, WIN_H   = 720, 540
local ROW_H          = 22
local VISIBLE_ROWS   = 18   -- number of rendered row frames
local STRAT_TEXT_PAD = 10   -- star icon gutter inside strategy column

-- Single source of truth for list headers + row fields.
-- Keep header/row positions in sync to avoid scale-dependent drift.
local LIST_COLUMNS = {
    { id = "stratName",  x = 14,  w = 240, headerKey = "COL_STRAT",  sortKey = "stratName",  justify = "LEFT"  },
    { id = "profession", x = 270, w = 120, headerKey = "COL_PROF",   sortKey = "profession", justify = "LEFT"  },
    { id = "profit",     x = 400, w = 130, headerKey = "COL_PROFIT", sortKey = "profit",     justify = "RIGHT" },
    { id = "roi",        x = 540, w = 60,  headerKey = "COL_ROI",    sortKey = "roi",        justify = "RIGHT" },
    { id = "status",     x = 608, w = 80,  headerKey = "COL_STATUS", sortKey = nil,          justify = "LEFT"  },
}

local LIST_COL_BY_ID = {}
for _, col in ipairs(LIST_COLUMNS) do
    LIST_COL_BY_ID[col.id] = col
end

-- ===== State =====
local frame
local filterPatch     = GAM.C.DEFAULT_PATCH
local filterProf      = "All"
local sortKey         = "stratName"
local sortAsc         = true
local filteredList    = {}   -- current sorted+filtered strat list
local scrollOffset    = 0    -- first visible row index (0-based)
local rowFrames       = {}   -- reusable row frames
local selectedStratID = nil

local function MeasureButtonWidth(parent, text, minW, maxW, padding)
    parent._gamMeasureFS = parent._gamMeasureFS or parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local fs = parent._gamMeasureFS
    fs:SetText(text or "")
    local w = math.ceil(fs:GetStringWidth() + (padding or 24))
    if minW and w < minW then w = minW end
    if maxW and w > maxW then w = maxW end
    return w
end

local function LayoutButtonRowBottom(parent, buttons, cfg)
    local left   = cfg.left or 14
    local right  = cfg.right or (WIN_W - 14)
    local bottom = cfg.bottom or 10
    local gap    = cfg.gap or 8
    local rowGap = cfg.rowGap or 4
    local align  = cfg.align or "center"
    local h      = cfg.height or 22
    local avail  = math.max(1, right - left)

    local rows = { {} }
    local rowWidths = { 0 }
    for _, btn in ipairs(buttons) do
        local bw = btn:GetWidth()
        local row = rows[#rows]
        local nextW = (#row > 0) and (rowWidths[#rows] + gap + bw) or bw
        if #row > 0 and nextW > avail then
            rows[#rows + 1] = { btn }
            rowWidths[#rowWidths + 1] = bw
        else
            row[#row + 1] = btn
            rowWidths[#rowWidths] = nextW
        end
    end

    for ri, row in ipairs(rows) do
        local rw = rowWidths[ri]
        local x
        if align == "right" then
            x = right - rw
        elseif align == "left" then
            x = left
        else
            x = left + math.floor((avail - rw) / 2)
        end
        local y = bottom + (ri - 1) * (h + rowGap)
        for bi, btn in ipairs(row) do
            btn:ClearAllPoints()
            btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
            x = x + btn:GetWidth() + ((bi < #row) and gap or 0)
        end
    end

    return {
        rows = #rows,
        top = bottom + (#rows - 1) * (h + rowGap) + h,
    }
end

-- Favorites shortcut
local function IsFavorite(stratID)
    local pdb = GAM:GetPatchDB(filterPatch)
    return pdb.favorites and pdb.favorites[stratID]
end

local function ToggleFavorite(stratID)
    local pdb = GAM:GetPatchDB(filterPatch)
    pdb.favorites = pdb.favorites or {}
    -- Store true when favoriting, nil (removes key) when un-favoriting
    pdb.favorites[stratID] = pdb.favorites[stratID] and nil or true
end

-- ===== Filter + sort =====
local SORT_FNS = {
    stratName  = function(a, b) return a.stratName < b.stratName end,
    profession = function(a, b) return a.profession < b.profession end,
    profit = function(a, b)
        local ma = GAM.Pricing.CalculateStratMetrics(a, filterPatch)
        local mb = GAM.Pricing.CalculateStratMetrics(b, filterPatch)
        local pa = (ma and ma.profit) or -math.huge
        local pb = (mb and mb.profit) or -math.huge
        return pa > pb  -- descending by default
    end,
    roi = function(a, b)
        local ma = GAM.Pricing.CalculateStratMetrics(a, filterPatch)
        local mb = GAM.Pricing.CalculateStratMetrics(b, filterPatch)
        local ra = (ma and ma.roi) or -math.huge
        local rb = (mb and mb.roi) or -math.huge
        return ra > rb
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

    -- Sort: favorites first, then by sortKey
    local fn = SORT_FNS[sortKey] or SORT_FNS.stratName
    table.sort(out, function(a, b)
        local af = IsFavorite(a.id)
        local bf = IsFavorite(b.id)
        if af and not bf then return true end
        if bf and not af then return false end
        if sortAsc then return fn(a, b) else return fn(b, a) end
    end)

    filteredList  = out
    scrollOffset  = 0
end

-- ===== Row frames (virtual scroll pool) =====
local function MakeRowFrame(parent, idx)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(WIN_W - 30, ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(idx - 1) * ROW_H)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

    -- Favorite star (texture; unicode ★ not supported by WoW default fonts)
    local star = row:CreateTexture(nil, "OVERLAY")
    star:SetSize(16, 16)
    star:SetPoint("LEFT", row, "LEFT", 4, 0)
    star:SetAtlas("Professions-ChatIcon-Quality-Tier3", false)
    row.star = star

    local colStrat  = LIST_COL_BY_ID.stratName
    local colProf   = LIST_COL_BY_ID.profession
    local colProfit = LIST_COL_BY_ID.profit
    local colRoi    = LIST_COL_BY_ID.roi
    local colStatus = LIST_COL_BY_ID.status

    -- Strategy name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("LEFT", row, "LEFT", colStrat.x + STRAT_TEXT_PAD, 0)
    nameText:SetWidth(colStrat.w - STRAT_TEXT_PAD)
    nameText:SetJustifyH(colStrat.justify)
    row.nameText = nameText

    -- Profession
    local profText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profText:SetPoint("LEFT", row, "LEFT", colProf.x, 0)
    profText:SetWidth(colProf.w)
    profText:SetJustifyH(colProf.justify)
    row.profText = profText

    -- Profit
    local profitText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profitText:SetPoint("LEFT", row, "LEFT", colProfit.x, 0)
    profitText:SetWidth(colProfit.w)
    profitText:SetJustifyH(colProfit.justify)
    row.profitText = profitText

    -- ROI
    local roiText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    roiText:SetPoint("LEFT", row, "LEFT", colRoi.x, 0)
    roiText:SetWidth(colRoi.w)
    roiText:SetJustifyH(colRoi.justify)
    row.roiText = roiText

    -- Missing price indicator
    local missingText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    missingText:SetPoint("LEFT", row, "LEFT", colStatus.x, 0)
    missingText:SetWidth(colStatus.w)
    missingText:SetJustifyH(colStatus.justify)
    missingText:SetTextColor(1, 0.6, 0)
    row.missingText = missingText

    -- Initialise missing-price list so OnEnter can always reference it safely
    row.missingPriceList = {}

    -- Click handlers
    row:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if self.stratID then
                selectedStratID = self.stratID
                if GAM.UI.StratDetail then
                    GAM.UI.StratDetail.Show(GAM.Importer.GetStratByID(self.stratID), filterPatch)
                end
                MW.RefreshRows()
            end
        end
    end)

    row:SetScript("OnDoubleClick", function(self)
        if self.stratID then
            ToggleFavorite(self.stratID)
            RebuildList()
            MW.RefreshRows()
        end
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
        if hasNotes then
            GameTooltip:AddLine(s.notes, 0.8, 0.8, 0.8, true)
            if s.output and s.output.name then
                GameTooltip:AddLine("Output: " .. s.output.name, 0.5, 1, 0.5)
            end
        end
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

-- ===== Populate one row from data =====
local function PopulateRow(row, strat)
    row.stratID = strat.id
    local isFav = IsFavorite(strat.id)
    if isFav then
        row.star:SetVertexColor(1, 0.85, 0, 1)    -- gold
        row.star:SetAlpha(1)
    else
        row.star:SetVertexColor(0.5, 0.5, 0.5, 1) -- grey
        row.star:SetAlpha(0.35)
    end
    row.nameText:SetText(strat.stratName)
    row.profText:SetText(strat.profession)

    -- Compute metrics (cached where possible)
    local m = GAM.Pricing.CalculateStratMetrics(strat, filterPatch)
    if m then
        if m.profit then
            local color = m.profit >= 0 and "|cff55ff55" or "|cffff5555"
            row.profitText:SetText(color .. GAM.Pricing.FormatPrice(m.profit) .. "|r")
        else
            row.profitText:SetText("|cff888888" .. GAM.L["NO_PRICE"] .. "|r")
        end
        if m.roi then
            local color = m.roi >= 0 and "|cff55ff55" or "|cffff5555"
            row.roiText:SetText(color .. string.format("%.1f%%", m.roi) .. "|r")
        else
            row.roiText:SetText("|cff888888—|r")
        end
        if #m.missingPrices > 0 then
            row.missingText:SetText(GAM.L["MISSING_PRICES"])
            row.missingPriceList = m.missingPrices
        else
            row.missingText:SetText("")
            row.missingPriceList = {}
        end
    else
        row.profitText:SetText("|cff888888" .. GAM.L["NO_PRICE"] .. "|r")
        row.roiText:SetText("|cff888888—|r")
        row.missingText:SetText(GAM.L["MISSING_PRICES"])
        row.missingPriceList = {}   -- no metrics means we can't enumerate names
    end

    -- Highlight selected
    if strat.id == selectedStratID then
        row:LockHighlight()
    else
        row:UnlockHighlight()
    end
    row:Show()
end

-- ===== RefreshRows =====
function MW.RefreshRows()
    if not frame then return end
    for i, row in ipairs(rowFrames) do
        local dataIdx = scrollOffset + i
        local strat   = filteredList[dataIdx]
        if strat then
            PopulateRow(row, strat)
        else
            row:Hide()
            row.stratID = nil
        end
    end
    -- Update scroll bar
    if frame.scrollBar then
        local total = #filteredList
        local max   = math.max(0, total - VISIBLE_ROWS)
        frame.scrollBar:SetMinMaxValues(0, max)
        frame.scrollBar:SetValue(scrollOffset)
        frame.scrollBar:Show()
    end
    -- Status text
    if frame.statusText then
        frame.statusText:SetText(string.format(L["STATUS_STRAT_COUNT"], #filteredList))
    end
end

-- ===== Build =====
local function Build()
    frame = CreateFrame("Frame", "GoldAdvisorMidnightMainWindow", UIParent,
                        "BackdropTemplate")
    frame:SetSize(WIN_W, WIN_H)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetScale(GAM.db and GAM.db.options and GAM.db.options.uiScale or 1.0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    -- DIALOG renders above HIGH (where Blizzard widget frames live).
    -- SetToplevel raises frame level within DIALOG when clicked.
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
    -- Explicit solid fill guards against backdrop edge cases (strata clipping, alpha inheritance).
    local bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0, 0, 0, 1)
    frame:Hide()

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText(L["MAIN_TITLE"])
    title:SetTextColor(1.0, 0.82, 0.0)
    local titleRule = frame:CreateTexture(nil, "ARTWORK")
    titleRule:SetHeight(1)
    titleRule:SetPoint("TOPLEFT",  frame, "TOPLEFT",  14, -27)
    titleRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -27)
    titleRule:SetColorTexture(0.7, 0.57, 0.0, 0.7)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- ── Filter bar ──
    local filterY = -32

    -- Profession dropdown (left-aligned, no patch dropdown)
    local profLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, filterY)
    profLabel:SetText(L["FILTER_PROFESSION"])

    local ddProf = CreateFrame("Frame", "GAMProfDropDown", frame, "UIDropDownMenuTemplate")
    ddProf:SetPoint("TOPLEFT", profLabel, "TOPRIGHT", -10, 4)
    UIDropDownMenu_SetWidth(ddProf, 150)

    local function InitProfDD()
        UIDropDownMenu_Initialize(ddProf, function()
            local profs = { "All" }
            for _, p in ipairs(GAM.Importer.GetAllProfessions(filterPatch)) do
                profs[#profs + 1] = p
            end
            for _, prof in ipairs(profs) do
                local info = UIDropDownMenu_CreateInfo()
                info.text  = prof
                info.value = prof
                info.func  = function()
                    filterProf = prof
                    UIDropDownMenu_SetText(ddProf, prof)
                    RebuildList()
                    MW.RefreshRows()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        UIDropDownMenu_SetText(ddProf, filterProf)
    end
    InitProfDD()
    frame.ddProf     = ddProf
    frame.InitProfDD = InitProfDD

    -- ── Column headers ──
    local colY   = filterY - 28
    local hdrFn  = "GameFontNormal"

    local function MakeColHdr(label, x, w, key, justify)
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(w, 18)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x, colY)
        local fs = btn:CreateFontString(nil, "OVERLAY", hdrFn)
        fs:SetAllPoints()
        fs:SetJustifyH(justify or "LEFT")
        fs:SetText(label)
        fs:SetTextColor(1.0, 0.82, 0.0)
        if key then
            btn:SetScript("OnClick", function()
                if sortKey == key then
                    sortAsc = not sortAsc
                else
                    sortKey = key
                    sortAsc = true
                end
                RebuildList()
                MW.RefreshRows()
            end)
        else
            btn:EnableMouse(false)
        end
        return btn
    end

    for _, col in ipairs(LIST_COLUMNS) do
        MakeColHdr(L[col.headerKey], col.x, col.w, col.sortKey, col.justify)
    end

    -- Separator
    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.7, 0.57, 0.0, 0.7)
    sep:SetPoint("TOPLEFT",  frame, "TOPLEFT",  14,  colY - 20)
    sep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, colY - 20)
    sep:SetHeight(1)

    -- ── Scan progress bar (hidden when idle) ──
    local PROG_H = 14
    local progBar = CreateFrame("StatusBar", nil, frame)
    progBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  14,  colY - 22)
    progBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, colY - 22)
    progBar:SetHeight(PROG_H)
    progBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progBar:SetStatusBarColor(0.1, 0.7, 0.2, 1)
    progBar:SetMinMaxValues(0, 1)
    progBar:SetValue(0)
    -- background
    local progBg = progBar:CreateTexture(nil, "BACKGROUND")
    progBg:SetAllPoints(true)
    progBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    -- label
    local progLabel = progBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progLabel:SetPoint("CENTER", progBar, "CENTER", 0, 0)
    progLabel:SetText("")
    progBar:Hide()
    frame.progBar   = progBar
    frame.progLabel = progLabel

    -- ── Virtual scroll list ──
    -- Shift list down when progress bar is visible (PROG_H + 2 gap)
    local listY = colY - 22 - PROG_H - 2

    local listHost = CreateFrame("Frame", nil, frame)
    listHost:SetPoint("TOPLEFT",     frame, "TOPLEFT",  14,  listY)
    listHost:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 44)

    for i = 1, VISIBLE_ROWS do
        rowFrames[i] = MakeRowFrame(listHost, i)
    end

    -- Scroll bar — plain slider (no UIPanelScrollBarTemplate, which requires a
    -- real ScrollFrame via SecureScrollTemplates and errors on virtual lists).
    local sb = CreateFrame("Slider", "GAMMainScrollBar", frame)
    sb:SetOrientation("VERTICAL")
    sb:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",   -8, listY)
    sb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 44)
    sb:SetWidth(16)
    sb:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    sb:GetThumbTexture():SetSize(16, 16)
    sb:SetMinMaxValues(0, 0)
    sb:SetValue(0)
    sb:SetValueStep(1)
    sb:SetObeyStepOnDrag(true)
    -- isUserInput guards against re-entry when RefreshRows programmatically calls SetValue
    sb:SetScript("OnValueChanged", function(self, val, isUserInput)
        if not isUserInput then return end
        scrollOffset = math.floor(val + 0.5)
        MW.RefreshRows()
    end)
    frame.scrollBar = sb

    -- Mouse wheel scrolling
    listHost:EnableMouseWheel(true)
    listHost:SetScript("OnMouseWheel", function(_, delta)
        local total = #filteredList
        local max   = math.max(0, total - VISIBLE_ROWS)
        scrollOffset = math.max(0, math.min(max, scrollOffset - delta * 3))
        sb:SetValue(scrollOffset)
        MW.RefreshRows()
    end)

    -- Status text
    local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.statusText = statusText

    -- ── Bottom buttons ──
    local function MakeBottomBtn(lbl, minW)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(minW, 22)
        b:SetText(lbl)
        return b
    end

    local btnClose = MakeBottomBtn(L["BTN_CLOSE"],         70)
    local btnLog   = MakeBottomBtn(L["BTN_LOG"],           90)
    local btnScan  = MakeBottomBtn(L["BTN_SCAN_ALL"],     105)
    local btnARP   = MakeBottomBtn(L["BTN_ARP_EXPORT"],   130)
    frame.btnScan = btnScan

    local BTN_H    = 22
    local BTN_Y    = 10  -- pixels from frame bottom
    local LABEL_Y  = BTN_Y + BTN_H + 4

    local function RelayoutBottomButtons()
        btnClose:SetWidth(MeasureButtonWidth(frame, btnClose:GetText(), 70, 180, 24))
        btnLog:SetWidth(MeasureButtonWidth(frame, btnLog:GetText(), 90, 220, 24))
        btnScan:SetWidth(MeasureButtonWidth(frame, btnScan:GetText(), 105, 260, 24))
        -- Right-aligned group
        LayoutButtonRowBottom(frame, { btnScan, btnLog, btnClose }, {
            left = 14, right = WIN_W - 14, bottom = BTN_Y, gap = 8, rowGap = 4, align = "right",
        })
        -- ARP button anchored bottom-left
        btnARP:SetWidth(MeasureButtonWidth(frame, btnARP:GetText(), 130, 260, 24))
        btnARP:ClearAllPoints()
        btnARP:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, BTN_Y)
        -- Status text above ARP button
        statusText:ClearAllPoints()
        statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, LABEL_Y)
    end
    frame.RelayoutBottomButtons = RelayoutBottomButtons
    RelayoutBottomButtons()

    btnClose:SetScript("OnClick", function() frame:Hide() end)
    btnLog:SetScript("OnClick",   function() GAM.UI.DebugLog.Toggle() end)
    btnARP:SetScript("OnClick",   function() GAM.UI.DebugLog.ShowARPExport() end)
    btnScan:SetScript("OnClick", function()
        if GAM.AHScan.IsScanning() then
            GAM.AHScan.StopScan()
            btnScan:SetText(L["BTN_SCAN_ALL"])
            RelayoutBottomButtons()
        else
            if not GAM.ahOpen then
                print("|cffff8800[GAM]|r " .. L["ERR_NO_AH"])
                return
            end
            GAM.AHScan.ResetQueue()
            GAM.AHScan.QueueStratListItems(filteredList, filterPatch)
            GAM.AHScan.StartScan()
            btnScan:SetText(L["BTN_SCAN_STOP"])
            RelayoutBottomButtons()
        end
    end)

    -- OnShow: build list
    frame:SetScript("OnShow", function()
        RebuildList()
        MW.RefreshRows()
        frame.InitProfDD()
    end)

end

-- ===== Public API =====

function MW.RefreshProfessionDropdown()
    if frame and frame.InitProfDD then frame.InitProfDD() end
end

function MW.OnScanProgress(done, total, isComplete)
    if not frame then return end
    if isComplete then
        frame.progBar:Hide()
        frame.progLabel:SetText("")
        if frame.btnScan then
            frame.btnScan:SetText(GAM.L["BTN_SCAN_ALL"])
            if frame.RelayoutBottomButtons then frame.RelayoutBottomButtons() end
        end
    else
        frame.progBar:Show()
        if total and total > 0 then
            frame.progBar:SetValue(done / total)
            frame.progLabel:SetText(string.format("%d / %d  " .. L["STATUS_SCANNING_PROG"], done, total))
        else
            frame.progBar:SetValue(0)
            frame.progLabel:SetText(L["STATUS_QUEUING"])
        end
    end
end

function MW.OnScanComplete()
    -- Progress cleanup is handled by OnScanProgress(isComplete=true) via callback.
    -- This function handles the list refresh once prices have been stored.
    if frame and frame:IsShown() then
        -- Auto-sort by highest ROI after each scan so the best opportunities surface immediately.
        sortKey = "roi"
        sortAsc = true  -- ROI sort fn already sorts descending (highest first)
        RebuildList()
        MW.RefreshRows()
    end
end

-- Refresh: rebuild and repaint the list. Called by StratDetail/StratCreator after
-- adding, editing, or deleting a user strategy.
function MW.Refresh()
    if not frame then return end
    RebuildList()
    MW.RefreshRows()
end

function MW.Show()
    if not frame then Build() end
    frame:Show()
end

function MW.Hide()
    if frame then frame:Hide() end
end

function MW.Toggle()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function MW.IsShown()
    return frame and frame:IsShown()
end
