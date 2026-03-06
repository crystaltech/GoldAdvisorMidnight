-- GoldCraft Advisor - UI.lua
-- Main panel and results display

local _, GCA = ...

-- ================= Constants =================
local PANEL_WIDTH = 700
local PANEL_HEIGHT = 520
local ROW_HEIGHT = 22
local HEADER_HEIGHT = 25
local MAX_VISIBLE_ROWS = 16

-- ================= Colors =================
local COLORS = {
    profit = { r = 0, g = 1, b = 0 },       -- Green
    loss = { r = 1, g = 0, b = 0 },         -- Red
    incomplete = { r = 0.5, g = 0.5, b = 0.5 }, -- Gray
    header = { r = 1, g = 0.82, b = 0 },    -- Gold
    highlight = { r = 0.3, g = 0.3, b = 0.5, a = 0.5 },
    best = { r = 0, g = 0.5, b = 0, a = 0.3 },
}

-- ================= Main Panel =================
local mainPanel = nil
local resultRows = {}
local scrollOffset = 0

function GCA:CreateMainPanel()
    if mainPanel then return mainPanel end

    -- Create main frame
    mainPanel = CreateFrame("Frame", "GoldCraftAdvisorPanel", UIParent, "BackdropTemplate")
    mainPanel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    mainPanel:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    mainPanel:SetMovable(true)
    mainPanel:EnableMouse(true)
    mainPanel:RegisterForDrag("LeftButton")
    mainPanel:SetScript("OnDragStart", mainPanel.StartMoving)
    mainPanel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position
        local point, _, relPoint, x, y = self:GetPoint()
        GCA.db.settings.panelPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    -- Backdrop
    mainPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    mainPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.95)

    -- Title
    local title = mainPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", mainPanel, "TOP", 0, -15)
    title:SetText("GoldCraft Advisor")
    title:SetTextColor(COLORS.header.r, COLORS.header.g, COLORS.header.b)

    -- Version
    local version = mainPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    version:SetPoint("TOPRIGHT", mainPanel, "TOPRIGHT", -35, -18)
    version:SetText("v1.0.0")
    version:SetTextColor(0.7, 0.7, 0.7)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, mainPanel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", mainPanel, "TOPRIGHT", -5, -5)

    -- Settings gear button (opens settings/debug panel)
    self:CreateSettingsButton(mainPanel)

    -- Settings row (Qty/Trim)
    self:CreateSettingsRow(mainPanel)

    -- Scan button
    self:CreateScanButton(mainPanel)

    -- Progress bar
    self:CreateProgressBar(mainPanel)

    -- Results header
    self:CreateResultsHeader(mainPanel)

    -- Results scroll frame
    self:CreateResultsScrollFrame(mainPanel)

    -- Status bar
    self:CreateStatusBar(mainPanel)

    -- Restore position
    if self.db.settings.panelPos then
        local pos = self.db.settings.panelPos
        mainPanel:ClearAllPoints()
        mainPanel:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 300, pos.y or 0)
    end

    -- Initially hidden
    mainPanel:Hide()

    self.mainPanel = mainPanel
    return mainPanel
end

-- ================= Settings Button =================

function GCA:CreateSettingsButton(parent)
    -- Create a gear/settings button
    local settingsBtn = CreateFrame("Button", "GCASettingsButton", parent)
    settingsBtn:SetSize(24, 24)
    settingsBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -35, -12)

    -- Use a gear icon texture
    local icon = settingsBtn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Scenarios\\ScenarioIcon-Interact")
    settingsBtn.icon = icon

    -- Highlight on hover
    settingsBtn:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(1, 1, 0)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Settings")
        GameTooltip:AddLine("Click to open debug/settings panel", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(1, 1, 1)
        GameTooltip:Hide()
    end)
    settingsBtn:SetScript("OnClick", function()
        GCA:ToggleSettingsPanel()
    end)

    self.settingsButton = settingsBtn
end

-- ================= Settings Row =================

function GCA:CreateSettingsRow(parent)
    local yOffset = -42

    -- Quantity label and editbox
    local qtyLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    qtyLabel:SetText("Qty:")

    local qtyBox = CreateFrame("EditBox", "GCAQuantityBox", parent, "InputBoxTemplate")
    qtyBox:SetSize(60, 20)
    qtyBox:SetPoint("LEFT", qtyLabel, "RIGHT", 5, 0)
    qtyBox:SetAutoFocus(false)
    qtyBox:SetNumeric(true)
    qtyBox:SetMaxLetters(6)
    qtyBox:SetText(tostring(self.db.settings.quantity or 10000))
    qtyBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or 10000
        GCA.db.settings.quantity = val
        self:ClearFocus()
        if GCA.RecalculatePrices then
            GCA:RecalculatePrices()
        end
    end)

    -- Trim label and editbox
    local trimLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    trimLabel:SetPoint("LEFT", qtyBox, "RIGHT", 15, 0)
    trimLabel:SetText("Trim:")

    local trimBox = CreateFrame("EditBox", "GCATrimBox", parent, "InputBoxTemplate")
    trimBox:SetSize(35, 20)
    trimBox:SetPoint("LEFT", trimLabel, "RIGHT", 5, 0)
    trimBox:SetAutoFocus(false)
    trimBox:SetNumeric(true)
    trimBox:SetMaxLetters(3)
    trimBox:SetText(tostring(self.db.settings.trim or 3))
    trimBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or 3
        GCA.db.settings.trim = val
        self:ClearFocus()
        if GCA.RecalculatePrices then
            GCA:RecalculatePrices()
        end
    end)

    local trimPercent = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    trimPercent:SetPoint("LEFT", trimBox, "RIGHT", 2, 0)
    trimPercent:SetText("%")

    self.qtyBox = qtyBox
    self.trimBox = trimBox
end

-- ================= Scan Button =================

function GCA:CreateScanButton(parent)
    local scanBtn = CreateFrame("Button", "GCAScanButton", parent, "UIPanelButtonTemplate")
    scanBtn:SetSize(80, 22)
    scanBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, -42)
    scanBtn:SetText("Scan All")
    scanBtn:SetScript("OnClick", function()
        if GCA:IsScanInProgress() then
            GCA:StopScan()
            scanBtn:SetText("Scan All")
        else
            GCA:StartScan()
            scanBtn:SetText("Stop")
        end
    end)

    -- Refresh button
    local refreshBtn = CreateFrame("Button", "GCARefreshButton", parent, "UIPanelButtonTemplate")
    refreshBtn:SetSize(70, 22)
    refreshBtn:SetPoint("RIGHT", scanBtn, "LEFT", -5, 0)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        if GCA.CalculateAllROI then
            GCA:CalculateAllROI()
        end
    end)

    self.scanButton = scanBtn
    self.refreshButton = refreshBtn
end

-- ================= Progress Bar =================

function GCA:CreateProgressBar(parent)
    local progressFrame = CreateFrame("Frame", "GCAProgressFrame", parent, "BackdropTemplate")
    progressFrame:SetSize(PANEL_WIDTH - 40, 18)
    progressFrame:SetPoint("TOP", parent, "TOP", 0, -72)
    progressFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    progressFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    progressFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local progressBar = CreateFrame("StatusBar", "GCAProgressBar", progressFrame)
    progressBar:SetSize(PANEL_WIDTH - 42, 16)
    progressBar:SetPoint("CENTER", progressFrame, "CENTER", 0, 0)
    progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progressBar:SetStatusBarColor(0.2, 0.6, 0.2)
    progressBar:SetMinMaxValues(0, 100)
    progressBar:SetValue(0)

    local progressText = progressBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progressText:SetPoint("CENTER", progressBar, "CENTER", 0, 0)
    progressText:SetText("")
    progressText:SetTextColor(1, 1, 1)

    progressFrame:Hide()

    self.progressFrame = progressFrame
    self.progressBar = progressBar
    self.progressText = progressText
end

function GCA:UpdateScanProgress(current, total)
    if not self.progressFrame then return end

    if total > 0 then
        self.progressFrame:Show()
        local percent = (current / total) * 100
        self.progressBar:SetValue(percent)
        self.progressText:SetText(string.format("Scanning: %d / %d (%.0f%%)", current, total, percent))
    else
        self.progressFrame:Hide()
        self.progressBar:SetValue(0)
        self.progressText:SetText("")
    end

    -- Reset scan button when done
    if current >= total and self.scanButton then
        self.scanButton:SetText("Scan All")
        C_Timer.After(2, function()
            if self.progressFrame then
                self.progressFrame:Hide()
            end
        end)
    end
end

-- ================= Results Header =================

function GCA:CreateResultsHeader(parent)
    local headerFrame = CreateFrame("Frame", "GCAResultsHeader", parent)
    headerFrame:SetSize(PANEL_WIDTH - 40, HEADER_HEIGHT)
    headerFrame:SetPoint("TOP", parent, "TOP", 0, -95)

    -- Column headers (wider for larger panel)
    local columns = {
        { text = "Strategy", width = 300, align = "LEFT" },
        { text = "Cost", width = 90, align = "RIGHT" },
        { text = "Value", width = 90, align = "RIGHT" },
        { text = "Profit", width = 90, align = "RIGHT" },
        { text = "ROI", width = 70, align = "RIGHT" },
    }

    local xOffset = 10
    for _, col in ipairs(columns) do
        local header = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("LEFT", headerFrame, "LEFT", xOffset, 0)
        header:SetWidth(col.width)
        header:SetJustifyH(col.align)
        header:SetText(col.text)
        header:SetTextColor(COLORS.header.r, COLORS.header.g, COLORS.header.b)
        xOffset = xOffset + col.width
    end

    -- Separator line
    local line = headerFrame:CreateTexture(nil, "ARTWORK")
    line:SetSize(PANEL_WIDTH - 40, 1)
    line:SetPoint("BOTTOM", headerFrame, "BOTTOM", 0, 0)
    line:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    self.headerFrame = headerFrame
end

-- ================= Results Scroll Frame =================

function GCA:CreateResultsScrollFrame(parent)
    local scrollFrame = CreateFrame("ScrollFrame", "GCAResultsScroll", parent, "FauxScrollFrameTemplate")
    scrollFrame:SetSize(PANEL_WIDTH - 40, ROW_HEIGHT * MAX_VISIBLE_ROWS)
    scrollFrame:SetPoint("TOP", parent, "TOP", 0, -120)

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
            GCA:UpdateResultRows()
        end)
    end)

    -- Create row frames
    for i = 1, MAX_VISIBLE_ROWS do
        local row = self:CreateResultRow(scrollFrame, i)
        resultRows[i] = row
    end

    self.scrollFrame = scrollFrame
end

function GCA:CreateResultRow(parent, index)
    local row = CreateFrame("Button", "GCAResultRow" .. index, parent)
    row:SetSize(PANEL_WIDTH - 60, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))

    -- Highlight texture
    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(COLORS.highlight.r, COLORS.highlight.g, COLORS.highlight.b, COLORS.highlight.a)
    highlight:Hide()
    row.highlight = highlight

    -- Best indicator
    local best = row:CreateTexture(nil, "BACKGROUND")
    best:SetAllPoints()
    best:SetColorTexture(COLORS.best.r, COLORS.best.g, COLORS.best.b, COLORS.best.a)
    best:Hide()
    row.best = best

    -- Column data (wider for larger panel)
    local columns = {
        { key = "name", width = 300, align = "LEFT" },
        { key = "cost", width = 90, align = "RIGHT" },
        { key = "value", width = 90, align = "RIGHT" },
        { key = "profit", width = 90, align = "RIGHT" },
        { key = "roi", width = 70, align = "RIGHT" },
    }

    row.columns = {}
    local xOffset = 10
    for _, col in ipairs(columns) do
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", row, "LEFT", xOffset, 0)
        text:SetWidth(col.width)
        text:SetJustifyH(col.align)
        text:SetText("")
        row.columns[col.key] = text
        xOffset = xOffset + col.width
    end

    -- Hover effects
    row:SetScript("OnEnter", function(self)
        if self.data then
            self.highlight:Show()
            GCA:ShowResultTooltip(self)
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        GameTooltip:Hide()
    end)

    -- Click to show breakdown in popup (not chat)
    row:SetScript("OnClick", function(self)
        if self.data and self.data.strategyName then
            GCA:ShowStrategyDetail(self.data.strategyName)
        end
    end)

    return row
end

-- ================= Update Results =================

function GCA:UpdateResults()
    if not self.scrollFrame then return end

    -- Always show all results (no category filtering)
    local results = self:GetResultsByCategory("All")

    if not results then
        results = {}
    end

    -- Update scroll frame
    FauxScrollFrame_Update(self.scrollFrame, #results, MAX_VISIBLE_ROWS, ROW_HEIGHT)

    self:UpdateResultRows()
end

function GCA:UpdateResultRows()
    if not self.scrollFrame then return end

    -- Always show all results (no category filtering)
    local results = self:GetResultsByCategory("All")

    if not results then
        results = {}
    end

    local offset = FauxScrollFrame_GetOffset(self.scrollFrame)

    for i = 1, MAX_VISIBLE_ROWS do
        local row = resultRows[i]
        local resultIndex = offset + i
        local result = results[resultIndex]

        if result then
            row:Show()
            row.data = result

            -- Name with indicator
            local namePrefix = ""
            if result.complete and result.roi and result.roi > 0 then
                if resultIndex == 1 then
                    namePrefix = "|cffffd700*|r "  -- Gold star for best
                    row.best:Show()
                else
                    row.best:Hide()
                end
            else
                row.best:Hide()
                if not result.complete then
                    namePrefix = "|cff888888!|r "  -- Warning for incomplete
                end
            end
            row.columns.name:SetText(namePrefix .. (result.name or "Unknown"))

            -- Set colors based on result
            local color = COLORS.incomplete
            if result.complete then
                color = result.profit and result.profit > 0 and COLORS.profit or COLORS.loss
            end

            row.columns.name:SetTextColor(color.r, color.g, color.b)

            if result.complete then
                row.columns.cost:SetText(self:FormatGold(result.cost))
                row.columns.value:SetText(self:FormatGold(result.value))
                row.columns.profit:SetText(self:FormatGold(result.profit))
                row.columns.roi:SetText(string.format("%.1f%%", result.roi or 0))

                row.columns.cost:SetTextColor(1, 1, 1)
                row.columns.value:SetTextColor(1, 1, 1)
                row.columns.profit:SetTextColor(color.r, color.g, color.b)
                row.columns.roi:SetTextColor(color.r, color.g, color.b)
            else
                row.columns.cost:SetText("---")
                row.columns.value:SetText("---")
                row.columns.profit:SetText("---")
                row.columns.roi:SetText("N/A")

                row.columns.cost:SetTextColor(COLORS.incomplete.r, COLORS.incomplete.g, COLORS.incomplete.b)
                row.columns.value:SetTextColor(COLORS.incomplete.r, COLORS.incomplete.g, COLORS.incomplete.b)
                row.columns.profit:SetTextColor(COLORS.incomplete.r, COLORS.incomplete.g, COLORS.incomplete.b)
                row.columns.roi:SetTextColor(COLORS.incomplete.r, COLORS.incomplete.g, COLORS.incomplete.b)
            end
        else
            row:Hide()
            row.data = nil
        end
    end
end

-- ================= Status Bar =================

function GCA:CreateStatusBar(parent)
    local statusBar = CreateFrame("Frame", "GCAStatusBar", parent)
    statusBar:SetSize(PANEL_WIDTH - 40, 20)
    statusBar:SetPoint("BOTTOM", parent, "BOTTOM", 0, 15)

    local statusText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("LEFT", statusBar, "LEFT", 0, 0)
    statusText:SetText("Ready")
    statusText:SetTextColor(0.7, 0.7, 0.7)

    -- Export button
    local exportBtn = CreateFrame("Button", "GCAExportButton", statusBar, "UIPanelButtonTemplate")
    exportBtn:SetSize(60, 18)
    exportBtn:SetPoint("RIGHT", statusBar, "RIGHT", 0, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        GCA:ExportPrices()
    end)

    -- Clear button
    local clearBtn = CreateFrame("Button", "GCAClearButton", statusBar, "UIPanelButtonTemplate")
    clearBtn:SetSize(50, 18)
    clearBtn:SetPoint("RIGHT", exportBtn, "LEFT", -5, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        GCA:ClearPrices()
        GCA:UpdateResults()
    end)

    self.statusBar = statusBar
    self.statusText = statusText
end

function GCA:SetStatus(text)
    if self.statusText then
        self.statusText:SetText(text or "Ready")
    end
end

-- ================= Tooltip =================

function GCA:ShowResultTooltip(row)
    if not row.data then return end

    local result = row.data
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(result.name or "Unknown", COLORS.header.r, COLORS.header.g, COLORS.header.b)
    GameTooltip:AddLine(result.category or "", 0.7, 0.7, 0.7)

    if result.complete then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Total Cost:", self:FormatGold(result.cost), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Total Value:", self:FormatGold(result.value), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Revenue (after 5% AH):", self:FormatGold(result.revenue), 1, 1, 1, 1, 1, 1)

        local color = result.profit > 0 and COLORS.profit or COLORS.loss
        GameTooltip:AddDoubleLine("Profit:", self:FormatGold(result.profit), color.r, color.g, color.b, color.r, color.g, color.b)
        GameTooltip:AddDoubleLine("ROI:", string.format("%.1f%%", result.roi or 0), color.r, color.g, color.b, color.r, color.g, color.b)
    else
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(result.error or "Missing price data", 1, 0.5, 0)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click for detailed breakdown", 0.5, 0.5, 0.5)

    GameTooltip:Show()
end

-- ================= Utility Functions =================

function GCA:FormatGold(copper)
    if not copper then return "---" end

    local gold = copper / 10000
    if gold >= 1000 then
        return string.format("%.1fk", gold / 1000)
    else
        return string.format("%.0f", gold)
    end
end

-- ================= Show/Hide Panel =================

function GCA:ShowPanel()
    if not self.mainPanel then
        self:CreateMainPanel()
    end
    self.mainPanel:Show()
    self:UpdateResults()
end

function GCA:HidePanel()
    if self.mainPanel then
        self.mainPanel:Hide()
    end
end

function GCA:TogglePanel()
    if self.mainPanel and self.mainPanel:IsShown() then
        self:HidePanel()
    else
        self:ShowPanel()
    end
end

-- ================= Initialize UI =================

function GCA:InitializeUI()
    -- Create panel (hidden by default)
    self:CreateMainPanel()

    -- Register for AH events handled in Core.lua
    self:Debug("UI initialized")
end

-- ================= Debug Log Panel =================

local debugPanel = nil
local debugLogText = ""
local MAX_LOG_LINES = 500

function GCA:CreateDebugPanel()
    if debugPanel then return debugPanel end

    -- Create debug frame
    debugPanel = CreateFrame("Frame", "GCADebugPanel", UIParent, "BackdropTemplate")
    debugPanel:SetSize(600, 400)
    debugPanel:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
    debugPanel:SetMovable(true)
    debugPanel:EnableMouse(true)
    debugPanel:RegisterForDrag("LeftButton")
    debugPanel:SetScript("OnDragStart", debugPanel.StartMoving)
    debugPanel:SetScript("OnDragStop", debugPanel.StopMovingOrSizing)
    debugPanel:SetFrameStrata("DIALOG")

    -- Backdrop
    debugPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    debugPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.95)

    -- Title
    local title = debugPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", debugPanel, "TOP", 0, -15)
    title:SetText("GCA Debug Log")
    title:SetTextColor(COLORS.header.r, COLORS.header.g, COLORS.header.b)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, debugPanel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", debugPanel, "TOPRIGHT", -5, -5)

    -- Scroll frame for log
    local scrollFrame = CreateFrame("ScrollFrame", "GCADebugScroll", debugPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", debugPanel, "TOPLEFT", 15, -45)
    scrollFrame:SetPoint("BOTTOMRIGHT", debugPanel, "BOTTOMRIGHT", -35, 45)

    -- Edit box for copyable text
    local editBox = CreateFrame("EditBox", "GCADebugEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetWidth(550)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)

    scrollFrame:SetScrollChild(editBox)
    self.debugEditBox = editBox
    self.debugScrollFrame = scrollFrame

    -- Clear button
    local clearBtn = CreateFrame("Button", nil, debugPanel, "UIPanelButtonTemplate")
    clearBtn:SetSize(60, 22)
    clearBtn:SetPoint("BOTTOMLEFT", debugPanel, "BOTTOMLEFT", 15, 12)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        debugLogText = ""
        GCA:UpdateDebugLog()
    end)

    -- Copy All button
    local copyBtn = CreateFrame("Button", nil, debugPanel, "UIPanelButtonTemplate")
    copyBtn:SetSize(80, 22)
    copyBtn:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
    copyBtn:SetText("Select All")
    copyBtn:SetScript("OnClick", function()
        GCA.debugEditBox:SetFocus()
        GCA.debugEditBox:HighlightText()
    end)

    -- Status text
    local statusText = debugPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMRIGHT", debugPanel, "BOTTOMRIGHT", -15, 17)
    statusText:SetText("Ctrl+A to select, Ctrl+C to copy")
    statusText:SetTextColor(0.5, 0.5, 0.5)

    debugPanel:Hide()
    self.debugPanel = debugPanel

    return debugPanel
end

function GCA:AddDebugLog(message)
    -- Add timestamp
    local timestamp = date("%H:%M:%S")
    local line = string.format("[%s] %s", timestamp, message)

    -- Append to log
    if debugLogText == "" then
        debugLogText = line
    else
        debugLogText = debugLogText .. "\n" .. line
    end

    -- Trim if too long (keep last MAX_LOG_LINES)
    local lineCount = select(2, debugLogText:gsub("\n", "\n")) + 1
    if lineCount > MAX_LOG_LINES then
        local pos = debugLogText:find("\n")
        if pos then
            debugLogText = debugLogText:sub(pos + 1)
        end
    end

    -- Update display if panel is visible
    if self.debugPanel and self.debugPanel:IsShown() then
        self:UpdateDebugLog()
    end
end

function GCA:UpdateDebugLog()
    if self.debugEditBox then
        self.debugEditBox:SetText(debugLogText)
        -- Scroll to bottom
        C_Timer.After(0.01, function()
            if GCA.debugScrollFrame then
                GCA.debugScrollFrame:SetVerticalScroll(GCA.debugScrollFrame:GetVerticalScrollRange())
            end
        end)
    end
end

function GCA:ShowDebugPanel()
    if not self.debugPanel then
        self:CreateDebugPanel()
    end
    self:UpdateDebugLog()
    self.debugPanel:Show()
end

function GCA:HideDebugPanel()
    if self.debugPanel then
        self.debugPanel:Hide()
    end
end

function GCA:ToggleDebugPanel()
    if self.debugPanel and self.debugPanel:IsShown() then
        self:HideDebugPanel()
    else
        self:ShowDebugPanel()
    end
end

-- ================= Strategy Detail Popup =================

local strategyPopup = nil

function GCA:CreateStrategyPopup()
    if strategyPopup then return strategyPopup end

    strategyPopup = CreateFrame("Frame", "GCAStrategyPopup", UIParent, "BackdropTemplate")
    strategyPopup:SetSize(450, 400)
    strategyPopup:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    strategyPopup:SetMovable(true)
    strategyPopup:EnableMouse(true)
    strategyPopup:RegisterForDrag("LeftButton")
    strategyPopup:SetScript("OnDragStart", strategyPopup.StartMoving)
    strategyPopup:SetScript("OnDragStop", strategyPopup.StopMovingOrSizing)
    strategyPopup:SetFrameStrata("DIALOG")

    -- Backdrop
    strategyPopup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    strategyPopup:SetBackdropColor(0.1, 0.1, 0.1, 0.98)

    -- Title
    local title = strategyPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", strategyPopup, "TOP", 0, -15)
    title:SetText("Strategy Details")
    title:SetTextColor(COLORS.header.r, COLORS.header.g, COLORS.header.b)
    strategyPopup.title = title

    -- Close button
    local closeBtn = CreateFrame("Button", nil, strategyPopup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", strategyPopup, "TOPRIGHT", -5, -5)

    -- Scroll frame for content
    local scrollFrame = CreateFrame("ScrollFrame", "GCAStrategyScroll", strategyPopup, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", strategyPopup, "TOPLEFT", 15, -45)
    scrollFrame:SetPoint("BOTTOMRIGHT", strategyPopup, "BOTTOMRIGHT", -35, 45)

    -- Edit box for copyable text
    local editBox = CreateFrame("EditBox", "GCAStrategyEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(GameFontHighlight)
    editBox:SetWidth(400)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        strategyPopup:Hide()
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)

    scrollFrame:SetScrollChild(editBox)
    strategyPopup.editBox = editBox
    strategyPopup.scrollFrame = scrollFrame

    -- Copy button
    local copyBtn = CreateFrame("Button", nil, strategyPopup, "UIPanelButtonTemplate")
    copyBtn:SetSize(80, 22)
    copyBtn:SetPoint("BOTTOMLEFT", strategyPopup, "BOTTOMLEFT", 15, 12)
    copyBtn:SetText("Select All")
    copyBtn:SetScript("OnClick", function()
        strategyPopup.editBox:SetFocus()
        strategyPopup.editBox:HighlightText()
    end)

    -- Status text
    local statusText = strategyPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMRIGHT", strategyPopup, "BOTTOMRIGHT", -15, 17)
    statusText:SetText("Ctrl+C to copy")
    statusText:SetTextColor(0.5, 0.5, 0.5)

    strategyPopup:Hide()
    self.strategyPopup = strategyPopup

    return strategyPopup
end

function GCA:ShowStrategyDetail(strategyName)
    if not self.strategyPopup then
        self:CreateStrategyPopup()
    end

    -- Get the detailed breakdown text
    local text = self:GetDetailedBreakdownText(strategyName)

    -- Update popup
    local strategy = self.Strategies and self.Strategies[strategyName]
    local displayName = strategy and strategy.name or strategyName
    self.strategyPopup.title:SetText(displayName)
    self.strategyPopup.editBox:SetText(text)

    -- Show popup
    self.strategyPopup:Show()

    -- Also log to debug panel
    if self.AddDebugLog then
        self:AddDebugLog("Viewing: " .. displayName)
    end
end

function GCA:GetDetailedBreakdownText(strategyName)
    local strategy = self.Strategies and self.Strategies[strategyName]
    if not strategy then
        return "Strategy not found: " .. tostring(strategyName)
    end

    local lines = {}
    table.insert(lines, "=== " .. (strategy.name or strategyName) .. " ===")
    table.insert(lines, "Category: " .. (strategy.category or "Unknown"))

    if strategy.guide then
        table.insert(lines, "Setup: " .. strategy.guide)
    end

    table.insert(lines, "")
    table.insert(lines, "--- INPUTS ---")

    local totalCost = 0
    for _, input in ipairs(strategy.inputs or {}) do
        local price = self:GetPrice(input.itemID)
        local itemName = self:GetItemName(input.itemID) or ("Item " .. input.itemID)
        local qty = input.quantity or 0

        if price and price > 0 then
            local cost = price * qty
            totalCost = totalCost + cost
            table.insert(lines, string.format("  %s x%d @ %.2fg = %.2fg",
                itemName, qty, price/10000, cost/10000))
        else
            table.insert(lines, string.format("  %s x%d @ MISSING", itemName, qty))
        end
    end

    table.insert(lines, "")
    table.insert(lines, "--- OUTPUTS ---")

    local totalValue = 0
    local inputQty = strategy.inputs and strategy.inputs[1] and strategy.inputs[1].quantity or 1
    local resourceBonus = 1 + (strategy.resourcefulness or 0)

    for _, output in ipairs(strategy.outputs or {}) do
        local price = self:GetPrice(output.itemID)
        local itemName = self:GetItemName(output.itemID) or ("Item " .. output.itemID)
        local avgPer = output.avgPer or 0
        local expectedQty = avgPer * inputQty * resourceBonus

        if price and price > 0 then
            local value = price * expectedQty
            totalValue = totalValue + value
            table.insert(lines, string.format("  %s x%.1f @ %.2fg = %.2fg",
                itemName, expectedQty, price/10000, value/10000))
        else
            table.insert(lines, string.format("  %s x%.1f @ MISSING", itemName, expectedQty))
        end
    end

    table.insert(lines, "")
    table.insert(lines, "--- SUMMARY ---")

    if strategy.resourcefulness and strategy.resourcefulness > 0 then
        table.insert(lines, string.format("Resourcefulness: %.1f%%", strategy.resourcefulness * 100))
    end
    if strategy.multicraft and strategy.multicraft > 0 then
        table.insert(lines, string.format("Multicraft: %.1f%%", strategy.multicraft * 100))
    end

    table.insert(lines, "")
    table.insert(lines, string.format("Total Cost: %.2fg", totalCost/10000))
    table.insert(lines, string.format("Total Value: %.2fg", totalValue/10000))

    local revenue = totalValue * 0.95
    local profit = revenue - totalCost
    local roi = totalCost > 0 and (profit / totalCost * 100) or 0

    table.insert(lines, string.format("Revenue (after 5%% AH): %.2fg", revenue/10000))

    if profit >= 0 then
        table.insert(lines, string.format("Profit: +%.2fg", profit/10000))
    else
        table.insert(lines, string.format("Profit: %.2fg (LOSS)", profit/10000))
    end

    table.insert(lines, string.format("ROI: %.1f%%", roi))

    return table.concat(lines, "\n")
end

-- ================= Settings Panel =================

local settingsPanel = nil

function GCA:CreateSettingsPanel()
    if settingsPanel then return settingsPanel end

    settingsPanel = CreateFrame("Frame", "GCASettingsPanel", UIParent, "BackdropTemplate")
    settingsPanel:SetSize(300, 200)
    settingsPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    settingsPanel:SetMovable(true)
    settingsPanel:EnableMouse(true)
    settingsPanel:RegisterForDrag("LeftButton")
    settingsPanel:SetScript("OnDragStart", settingsPanel.StartMoving)
    settingsPanel:SetScript("OnDragStop", settingsPanel.StopMovingOrSizing)
    settingsPanel:SetFrameStrata("DIALOG")

    -- Backdrop
    settingsPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    settingsPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.98)

    -- Title
    local title = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", settingsPanel, "TOP", 0, -15)
    title:SetText("GCA Settings")
    title:SetTextColor(COLORS.header.r, COLORS.header.g, COLORS.header.b)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", settingsPanel, "TOPRIGHT", -5, -5)

    local yOffset = -50

    -- Debug Mode checkbox
    local debugCheck = CreateFrame("CheckButton", "GCADebugCheck", settingsPanel, "UICheckButtonTemplate")
    debugCheck:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 20, yOffset)
    debugCheck.text = debugCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    debugCheck.text:SetPoint("LEFT", debugCheck, "RIGHT", 5, 0)
    debugCheck.text:SetText("Enable Debug Mode")
    debugCheck:SetChecked(GCA.debugMode or false)
    debugCheck:SetScript("OnClick", function(self)
        GCA.debugMode = self:GetChecked()
        GCA.db.settings.debugMode = GCA.debugMode
        if GCA.AddDebugLog then
            GCA:AddDebugLog("Debug mode: " .. (GCA.debugMode and "ON" or "OFF"))
        end
    end)

    yOffset = yOffset - 30

    -- Open Log Panel button
    local logBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    logBtn:SetSize(120, 22)
    logBtn:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 20, yOffset)
    logBtn:SetText("Open Log Panel")
    logBtn:SetScript("OnClick", function()
        GCA:ShowDebugPanel()
    end)

    yOffset = yOffset - 35

    -- Info text
    local infoText = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 20, yOffset)
    infoText:SetWidth(260)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("Debug output goes to the log panel.\nUse /gca log to open it directly.\n\nCommands:\n  /gca scan - Start AH scan\n  /gca verbose - Toggle debug\n  /gca log - Open log panel")
    infoText:SetTextColor(0.7, 0.7, 0.7)

    settingsPanel:Hide()
    self.settingsPanel = settingsPanel

    return settingsPanel
end

function GCA:ShowSettingsPanel()
    if not self.settingsPanel then
        self:CreateSettingsPanel()
    end
    -- Update checkbox state
    if GCADebugCheck then
        GCADebugCheck:SetChecked(self.debugMode or false)
    end
    self.settingsPanel:Show()
end

function GCA:HideSettingsPanel()
    if self.settingsPanel then
        self.settingsPanel:Hide()
    end
end

function GCA:ToggleSettingsPanel()
    if self.settingsPanel and self.settingsPanel:IsShown() then
        self:HideSettingsPanel()
    else
        self:ShowSettingsPanel()
    end
end
