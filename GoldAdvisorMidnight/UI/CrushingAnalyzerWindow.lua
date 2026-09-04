-- GoldAdvisorMidnight/UI/CrushingAnalyzerWindow.lua
-- Jewelcrafting crushing comparison window owned independently from base strategy detail.
-- Module: GAM.UI.CrushingAnalyzerWindow

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local CrushingAnalyzerWindow = {}
GAM.UI.CrushingAnalyzerWindow = CrushingAnalyzerWindow

local WindowManager = GAM.UI.WindowManager
local DEFAULT_GOLD = { 1.0, 0.82, 0.0 }
local DEFAULT_RULE = { 0.7, 0.57, 0.0, 0.7 }
local CRUSHING_WINDOW_W = 592
local CRUSHING_WINDOW_H = 278
local CRUSHING_WINDOW_MIN_W = 430
local CRUSHING_WINDOW_MIN_H = 168
local CRUSHING_ROW_H = 22
local CRUSHING_MAX_AUTO_H = 340
local CRUSHING_CHROME_H = 102

function CrushingAnalyzerWindow.GetCompactHeight(rowCount)
    rowCount = math.max(0, math.floor(tonumber(rowCount) or 0))
    return math.max(CRUSHING_WINDOW_MIN_H,
        math.min(CRUSHING_MAX_AUTO_H, CRUSHING_CHROME_H + (rowCount * CRUSHING_ROW_H)))
end

local crushingWindow
local crushingRows = {}

local function ApplyCrushingWindowLayout(win)
    if not win then
        return
    end

    local width = math.max(CRUSHING_WINDOW_MIN_W, math.floor((win:GetWidth() or CRUSHING_WINDOW_W) + 0.5))
    local height = math.max(CRUSHING_WINDOW_MIN_H, math.floor((win:GetHeight() or CRUSHING_WINDOW_H) + 0.5))
    if width ~= (win:GetWidth() or 0) or height ~= (win:GetHeight() or 0) then
        win:SetSize(width, height)
        return
    end

    local contentWidth = math.max(320, width - 32)
    local gap = 6
    local gemW = math.max(150, math.floor(contentWidth * 0.34))
    local priceW = math.max(70, math.floor(contentWidth * 0.15))
    local profitW = math.max(86, math.floor(contentWidth * 0.20))
    local roiW = math.max(56, math.floor(contentWidth * 0.11))
    local breakEvenW = math.max(94, contentWidth - gemW - priceW - profitW - roiW - (gap * 4))

    local gemX = 18
    local priceX = gemX + gemW + gap
    local profitX = priceX + priceW + gap
    local roiX = profitX + profitW + gap
    local breakEvenX = roiX + roiW + gap

    if win.subtitleFS then
        win.subtitleFS:SetWidth(width - 40)
    end
    if win.emptyFS then
        win.emptyFS:SetWidth(contentWidth - 16)
    end

    -- summaryCard not shown in header; hide it so it doesn't consume vertical space
    if win.summaryCard then
        win.summaryCard:Hide()
    end
    if win.summaryRule then
        win.summaryRule:ClearAllPoints()
        win.summaryRule:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -56)
        win.summaryRule:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, -56)
    end

    if win.headerGemFS then
        win.headerGemFS:ClearAllPoints()
        win.headerGemFS:SetPoint("TOPLEFT", win, "TOPLEFT", gemX, -70)
        win.headerGemFS:SetWidth(gemW)
    end
    if win.headerPriceFS then
        win.headerPriceFS:ClearAllPoints()
        win.headerPriceFS:SetPoint("TOPLEFT", win, "TOPLEFT", priceX, -70)
        win.headerPriceFS:SetWidth(priceW)
    end
    if win.headerProfitFS then
        win.headerProfitFS:ClearAllPoints()
        win.headerProfitFS:SetPoint("TOPLEFT", win, "TOPLEFT", profitX, -70)
        win.headerProfitFS:SetWidth(profitW)
    end
    if win.headerROIFS then
        win.headerROIFS:ClearAllPoints()
        win.headerROIFS:SetPoint("TOPLEFT", win, "TOPLEFT", roiX, -70)
        win.headerROIFS:SetWidth(roiW)
    end
    if win.headerBreakEvenFS then
        win.headerBreakEvenFS:ClearAllPoints()
        win.headerBreakEvenFS:SetPoint("TOPLEFT", win, "TOPLEFT", breakEvenX, -70)
        win.headerBreakEvenFS:SetWidth(breakEvenW)
    end

    if win.scrollFrame then
        win.scrollFrame:ClearAllPoints()
        win.scrollFrame:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -84)
        win.scrollFrame:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -30, 12)
    end
    if win.listHost then
        win.listHost:SetWidth(contentWidth)
    end

    for i, row in ipairs(crushingRows) do
        row:SetWidth(contentWidth)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win.listHost, "TOPLEFT", 0, -((i - 1) * CRUSHING_ROW_H))

        row.nameFS:ClearAllPoints()
        row.nameFS:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.nameFS:SetWidth(gemW - 12)

        row.priceFS:ClearAllPoints()
        row.priceFS:SetPoint("LEFT", row, "LEFT", priceX, 0)
        row.priceFS:SetWidth(priceW)

        row.profitFS:ClearAllPoints()
        row.profitFS:SetPoint("LEFT", row, "LEFT", profitX, 0)
        row.profitFS:SetWidth(profitW)

        row.roiFS:ClearAllPoints()
        row.roiFS:SetPoint("LEFT", row, "LEFT", roiX, 0)
        row.roiFS:SetWidth(roiW)

        row.breakEvenFS:ClearAllPoints()
        row.breakEvenFS:SetPoint("LEFT", row, "LEFT", breakEvenX, 0)
        row.breakEvenFS:SetWidth(breakEvenW)
    end
end

local function ClampCrushingWindowSize(win)
    if not win then
        return
    end
    local width = math.max(CRUSHING_WINDOW_MIN_W, math.floor((win:GetWidth() or CRUSHING_WINDOW_W) + 0.5))
    local height = math.max(CRUSHING_WINDOW_MIN_H, math.floor((win:GetHeight() or CRUSHING_WINDOW_H) + 0.5))
    if width ~= (win:GetWidth() or 0) or height ~= (win:GetHeight() or 0) then
        win:SetSize(width, height)
    end
end

local function RefreshCrushingWindowSummary(win, analyzer, metrics, selectedName)
    if not win then
        return
    end

    local craftsText = nil
    if analyzer and analyzer.crafts and analyzer.crafts > 0 then
        craftsText = tostring(math.floor((analyzer.crafts or 0) + 0.5))
    end
    if selectedName then
        win.subtitleFS:SetText(craftsText and ("Active auto-pick: " .. selectedName .. " | Crafts: " .. craftsText)
            or ("Active auto-pick: " .. selectedName))
    else
        win.subtitleFS:SetText(craftsText and ("Current rank-policy gem comparison | Crafts: " .. craftsText)
            or "Current rank-policy gem comparison")
    end

    local metricParts = {}
    if metrics and metrics.requiredCostFull then
        metricParts[#metricParts + 1] = "Cost " .. GAM.Pricing.FormatPrice(metrics.requiredCostFull)
    end
    if metrics and metrics.netRevenue then
        metricParts[#metricParts + 1] = "Net " .. GAM.Pricing.FormatPrice(metrics.netRevenue)
    end
    if metrics and metrics.profit then
        metricParts[#metricParts + 1] = "Profit " .. GAM.Pricing.FormatPrice(metrics.profit)
    end
    if metrics and metrics.roi then
        metricParts[#metricParts + 1] = string.format("ROI %.1f%%", metrics.roi)
    end
    win.summaryFS:SetText(#metricParts > 0 and table.concat(metricParts, "   ")
        or "Comparing eligible gem outcomes")

    if selectedName then
        win.summaryNoteFS:SetText(
            "Comparing eligible gems for the current rank-policy view. The highlighted row is the active auto-pick: "
            .. tostring(selectedName) .. ".")
    else
        win.summaryNoteFS:SetText(
            "Comparing eligible gems for the current rank-policy view. Rows below show the current candidates.")
    end
end

local function RenderCrushingAnalyzer(win, analyzer)
    if not (win and analyzer and analyzer.entries) then
        return nil
    end

    local selectedName = nil
    local shownCount = 0

    for i, row in ipairs(crushingRows) do
        local entry = analyzer.entries[i]
        if entry then
            local display = GAM.Pricing.GetItemDisplayData(entry.itemID, entry.name)
            shownCount = shownCount + 1
            row._entry = entry
            row.nameFS:SetText(display.displayText)
            row.priceFS:SetText(entry.unitPrice and GAM.Pricing.FormatPrice(entry.unitPrice) or "|cffff8800—|r")
            if entry.profit then
                local color = entry.profit >= 0 and "|cff55ff55" or "|cffff5555"
                row.profitFS:SetText(color .. GAM.Pricing.FormatPrice(entry.profit) .. "|r")
            else
                row.profitFS:SetText("|cff888888—|r")
            end
            if entry.roi then
                local color = entry.roi >= 0 and "|cff55ff55" or "|cffff5555"
                row.roiFS:SetText(color .. string.format("%.1f%%", entry.roi) .. "|r")
            else
                row.roiFS:SetText("|cff888888—|r")
            end
            row.breakEvenFS:SetText(entry.breakEvenSell and GAM.Pricing.FormatPrice(entry.breakEvenSell) or "|cff888888—|r")
            if entry.isSelected then
                row.nameFS:SetTextColor(1.0, 0.90, 0.42, 1.0)
                row.priceFS:SetTextColor(1.0, 0.90, 0.72, 1.0)
                row.breakEvenFS:SetTextColor(1.0, 0.84, 0.22, 1.0)
                row.bg:SetColorTexture(0.20, 0.15, 0.05, 0.86)
                row.stageAccent:Show()
                row.topRule:SetShown(i > 1)
                selectedName = entry.name
            else
                row.nameFS:SetTextColor(0.95, 0.95, 0.95, 1.0)
                row.priceFS:SetTextColor(0.92, 0.92, 0.92, 1.0)
                row.breakEvenFS:SetTextColor(0.84, 0.84, 0.84, 1.0)
                row.bg:SetColorTexture(0.10, 0.10, 0.10, (i % 2 == 1) and 0.55 or 0.28)
                row.stageAccent:Hide()
                row.topRule:Hide()
            end
            row:Show()
        else
            row._entry = nil
            row:Hide()
        end
    end

    if shownCount > 0 then
        win.emptyFS:Hide()
    else
        win.emptyFS:SetText(GAM.L["CRUSHING_NO_GEMS"])
        win.emptyFS:Show()
    end
    win.listHost:SetHeight(math.max(1, shownCount * CRUSHING_ROW_H))
    win.scrollFrame:SetVerticalScroll(0)
    if not win._userResized then
        local compactHeight = CrushingAnalyzerWindow.GetCompactHeight(shownCount)
        if math.abs((win:GetHeight() or 0) - compactHeight) >= 1 then
            win:SetHeight(compactHeight)
        end
    end
    ApplyCrushingWindowLayout(win)
    if win.scrollFrame.ScrollBar then
        local viewportHeight = tonumber(win.scrollFrame:GetHeight()) or 0
        win.scrollFrame.ScrollBar:SetShown(win.listHost:GetHeight() > viewportHeight)
    end

    return selectedName
end

local function HideCrushingWindow()
    if crushingWindow then
        crushingWindow:Hide()
    end
end

local function EnsureCrushingWindow()
    if crushingWindow then
        return crushingWindow
    end

    crushingWindow = CreateFrame("Frame", "GAMCrushingAnalyzer", UIParent, "BackdropTemplate")
    crushingWindow:SetSize(CRUSHING_WINDOW_W, CRUSHING_WINDOW_H)
    crushingWindow:SetPoint("CENTER")
    crushingWindow:SetResizable(true)
    crushingWindow:SetScale((GAM.GetOption and GAM:GetOption("uiScale", 1.0)) or 1.0)
    crushingWindow:SetMovable(true)
    crushingWindow:EnableMouse(true)
    crushingWindow:RegisterForDrag("LeftButton")
    crushingWindow:SetScript("OnDragStart", crushingWindow.StartMoving)
    crushingWindow:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self._userMoved = true
    end)
    crushingWindow:SetClampedToScreen(true)
    crushingWindow:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    crushingWindow:SetBackdropColor(0, 0, 0, 1)
    crushingWindow:SetBackdropBorderColor(0.7, 0.57, 0.0, 0.62)
    crushingWindow:Hide()
    WindowManager.Register(crushingWindow, "dialog")
    crushingWindow:SetScript("OnSizeChanged", function(self)
        ClampCrushingWindowSize(self)
        if not self.subtitleFS then
            return
        end
        ApplyCrushingWindowLayout(self)
        if self._lastAnalyzer then
            local selectedName = RenderCrushingAnalyzer(self, self._lastAnalyzer)
            RefreshCrushingWindowSummary(self, self._lastAnalyzer, self._lastMetrics, selectedName)
        end
    end)

    local bgTex = crushingWindow:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0, 0, 0, 1)

    local title = crushingWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", crushingWindow, "TOP", 0, -14)
    title:SetText(GAM.L["CRUSHING_TITLE"])
    title:SetTextColor(DEFAULT_GOLD[1], DEFAULT_GOLD[2], DEFAULT_GOLD[3])
    crushingWindow.titleFS = title

    local subtitle = crushingWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetWidth(CRUSHING_WINDOW_W - 40)
    subtitle:SetJustifyH("CENTER")
    subtitle:SetTextColor(0.75, 0.72, 0.64, 1)
    crushingWindow.subtitleFS = subtitle

    local summaryCard = CreateFrame("Frame", nil, crushingWindow, "BackdropTemplate")
    summaryCard:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    summaryCard:SetBackdropColor(0.09, 0.07, 0.04, 0.96)
    summaryCard:SetBackdropBorderColor(DEFAULT_RULE[1], DEFAULT_RULE[2], DEFAULT_RULE[3], 0.46)
    crushingWindow.summaryCard = summaryCard

    local summary = summaryCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 12, -8)
    summary:SetPoint("TOPRIGHT", summaryCard, "TOPRIGHT", -12, -8)
    summary:SetJustifyH("CENTER")
    summary:SetWordWrap(false)
    summary:SetTextColor(1.0, 0.82, 0.0, 1.0)
    crushingWindow.summaryFS = summary

    local summaryNote = summaryCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summaryNote:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 12, -28)
    summaryNote:SetPoint("TOPRIGHT", summaryCard, "TOPRIGHT", -12, -28)
    summaryNote:SetPoint("BOTTOMLEFT", summaryCard, "BOTTOMLEFT", 12, 8)
    summaryNote:SetPoint("BOTTOMRIGHT", summaryCard, "BOTTOMRIGHT", -12, 8)
    summaryNote:SetJustifyH("LEFT")
    summaryNote:SetWordWrap(true)
    summaryNote:SetTextColor(0.78, 0.78, 0.78, 1.0)
    crushingWindow.summaryNoteFS = summaryNote

    local closeBtn = CreateFrame("Button", nil, crushingWindow, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", crushingWindow, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        crushingWindow:Hide()
    end)

    local rule = crushingWindow:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", crushingWindow, "TOPLEFT", 12, -122)
    rule:SetPoint("TOPRIGHT", crushingWindow, "TOPRIGHT", -12, -122)
    rule:SetColorTexture(DEFAULT_RULE[1], DEFAULT_RULE[2], DEFAULT_RULE[3], 0.6)
    crushingWindow.summaryRule = rule

    local function MakeHdr(text)
        local fs = crushingWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        fs:SetTextColor(1.0, 0.84, 0.22, 1.0)
        return fs
    end

    crushingWindow.headerGemFS = MakeHdr("Gem")
    crushingWindow.headerPriceFS = MakeHdr("Price")
    crushingWindow.headerProfitFS = MakeHdr("Profit")
    crushingWindow.headerROIFS = MakeHdr("ROI")
    crushingWindow.headerBreakEvenFS = MakeHdr("Break-even")

    local scroll = CreateFrame("ScrollFrame", nil, crushingWindow, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", crushingWindow, "TOPLEFT", 16, -150)
    scroll:SetPoint("BOTTOMRIGHT", crushingWindow, "BOTTOMRIGHT", -30, 18)
    crushingWindow.scrollFrame = scroll

    local listHost = CreateFrame("Frame", nil, scroll)
    listHost:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    listHost:SetWidth(math.max(320, CRUSHING_WINDOW_W - 32))
    listHost:SetHeight(1)
    scroll:SetScrollChild(listHost)
    crushingWindow.listHost = listHost

    local emptyFS = crushingWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyFS:SetPoint("TOPLEFT", scroll, "TOPLEFT", 8, -10)
    emptyFS:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -8, -10)
    emptyFS:SetJustifyH("CENTER")
    emptyFS:SetJustifyV("TOP")
    emptyFS:SetWordWrap(true)
    emptyFS:SetTextColor(0.78, 0.78, 0.78, 1.0)
    emptyFS:Hide()
    crushingWindow.emptyFS = emptyFS

    listHost:EnableMouseWheel(true)
    listHost:SetScript("OnMouseWheel", function(_, delta)
        local cur = scroll:GetVerticalScroll()
        local max = scroll:GetVerticalScrollRange()
        scroll:SetVerticalScroll(math.max(0, math.min(max, cur - delta * (CRUSHING_ROW_H * 3))))
    end)

    for i = 1, 10 do
        local row = CreateFrame("Frame", nil, listHost)
        row:SetHeight(CRUSHING_ROW_H)
        row:SetWidth(math.max(320, CRUSHING_WINDOW_W - 32))
        row:SetPoint("TOPLEFT", listHost, "TOPLEFT", 0, -((i - 1) * CRUSHING_ROW_H))

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
        bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 1)
        bg:SetColorTexture(0.10, 0.10, 0.10, (i % 2 == 1) and 0.55 or 0.28)

        local topRule = row:CreateTexture(nil, "ARTWORK")
        topRule:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        topRule:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, 0)
        topRule:SetHeight(1)
        topRule:SetColorTexture(DEFAULT_RULE[1], DEFAULT_RULE[2], DEFAULT_RULE[3], 0.48)
        topRule:Hide()

        local stageAccent = row:CreateTexture(nil, "ARTWORK")
        stageAccent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
        stageAccent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
        stageAccent:SetWidth(3)
        stageAccent:SetColorTexture(1.0, 0.82, 0.0, 0.88)
        stageAccent:Hide()

        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFS:SetPoint("LEFT", row, "LEFT", 8, 0)
        nameFS:SetWidth(128)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)

        local priceFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        priceFS:SetPoint("LEFT", row, "LEFT", 160, 0)
        priceFS:SetWidth(60)
        priceFS:SetJustifyH("LEFT")
        priceFS:SetWordWrap(false)

        local profitFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        profitFS:SetPoint("LEFT", row, "LEFT", 202, 0)
        profitFS:SetWidth(78)
        profitFS:SetJustifyH("LEFT")
        profitFS:SetWordWrap(false)

        local roiFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        roiFS:SetPoint("LEFT", row, "LEFT", 286, 0)
        roiFS:SetWidth(48)
        roiFS:SetJustifyH("LEFT")
        roiFS:SetWordWrap(false)

        local breakEvenFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        breakEvenFS:SetPoint("LEFT", row, "LEFT", 340, 0)
        breakEvenFS:SetWidth(68)
        breakEvenFS:SetJustifyH("LEFT")
        breakEvenFS:SetWordWrap(false)

        row.bg = bg
        row.topRule = topRule
        row.stageAccent = stageAccent
        row.nameFS = nameFS
        row.priceFS = priceFS
        row.profitFS = profitFS
        row.roiFS = roiFS
        row.breakEvenFS = breakEvenFS
        row:Hide()
        crushingRows[i] = row
    end

    local resizeBtn = CreateFrame("Button", nil, crushingWindow)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", crushingWindow, "BOTTOMRIGHT", -8, 8)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:SetScript("OnMouseDown", function()
        crushingWindow:StartSizing("BOTTOMRIGHT")
    end)
    resizeBtn:SetScript("OnMouseUp", function()
        crushingWindow:StopMovingOrSizing()
        crushingWindow._userMoved = true
        crushingWindow._userResized = true
        ApplyCrushingWindowLayout(crushingWindow)
    end)
    crushingWindow.resizeBtn = resizeBtn

    ClampCrushingWindowSize(crushingWindow)
    ApplyCrushingWindowLayout(crushingWindow)

    return crushingWindow
end

local function PositionCrushingWindow(anchor)
    local win = EnsureCrushingWindow()
    if not (anchor and win) or win._userMoved then
        return
    end

    local screenW = UIParent:GetWidth() or 0
    local anchorRight = anchor:GetRight() or 0
    local winWidth = win:GetWidth() or CRUSHING_WINDOW_W
    win:ClearAllPoints()
    if anchorRight + 12 + winWidth <= screenW then
        win:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 12, 0)
    else
        win:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -12, 0)
    end
end

local function RefreshCrushingWindow(anchor, strat, patchTag, metrics)
    if not (strat and GAM.PricingFacade and GAM.PricingFacade.GetCurrentCrushingAnalyzer) then
        HideCrushingWindow()
        return
    end

    local analyzer = GAM.PricingFacade.GetCurrentCrushingAnalyzer(strat, patchTag, metrics)
    if not (analyzer and analyzer.entries and #analyzer.entries > 0) then
        HideCrushingWindow()
        return
    end

    local win = EnsureCrushingWindow()
    PositionCrushingWindow(anchor)
    win._lastAnalyzer = analyzer
    win._lastMetrics = metrics
    local selectedName = RenderCrushingAnalyzer(win, analyzer)
    RefreshCrushingWindowSummary(win, analyzer, metrics, selectedName)
    win:Show()
    WindowManager.Present(win)
end

CrushingAnalyzerWindow.Refresh = RefreshCrushingWindow
CrushingAnalyzerWindow.Hide = HideCrushingWindow
