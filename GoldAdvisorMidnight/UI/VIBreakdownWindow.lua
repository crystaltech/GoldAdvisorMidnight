-- GoldAdvisorMidnight/UI/VIBreakdownWindow.lua
-- Vertical-integration analysis window owned independently from base strategy detail.
-- Module: GAM.UI.VIBreakdownWindow

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local VIBreakdownWindow = {}
GAM.UI.VIBreakdownWindow = VIBreakdownWindow

local WindowManager = GAM.UI.WindowManager
local VIBreakdownPlan = GAM.UI.VIBreakdownPlan
local Common = GAM.UI.MainWindowCommon
local DEFAULT_GOLD = { 0.96, 0.82, 0.36 }
local DEFAULT_RULE = { 0.38, 0.32, 0.14, 0.65 }
local VI_WINDOW_W = 820
local VI_WINDOW_H = 260
local VI_WINDOW_MIN_W = 720
local VI_WINDOW_MIN_H = 220
local VI_WINDOW_MAX_H = 640
local VI_ROW_H = 42

local function GetL()
    return GAM.L or {}
end

local function AddThousandsSeparators(text)
    local sign, digits, frac = tostring(text or ""):match("^([%-]?)(%d+)(%.?%d*)$")
    if not digits then
        return tostring(text or "")
    end
    return sign .. digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") .. (frac or "")
end

local function FormatQuantityValue(value)
    if value == nil then
        return "0"
    end
    local number = tonumber(value) or 0
    local rounded = math.floor(number + 0.5)
    if math.abs(number - rounded) < 0.05 then
        return AddThousandsSeparators(tostring(rounded))
    end
    local valueText = string.format("%.1f", number):gsub("0+$", ""):gsub("%.$", "")
    return AddThousandsSeparators(valueText)
end

local viBreakdownWindow
local viBreakdownRows = {}

local function FormatTraceCount(value)
    return (value == nil) and "—" or FormatQuantityValue(value)
end

local function GetBreakdownActionText(entry)
    local L = GetL()
    if not entry then
        return L["VI_ROW_ACTION_REVIEW"] or "Review"
    end
    if entry.excludeFromCost then
        return L["VI_ROW_ACTION_IGNORE"] or "Ignore"
    end
    if entry.kind == "craft" then
        return L["VI_ROW_ACTION_CRAFT"] or "Craft"
    end
    return L["VI_ROW_ACTION_BUY"] or "Buy"
end

local function IsPrimaryBreakdownStage(entry)
    return entry and entry.kind == "craft" and entry.isFinalCraft
end

local function GetBreakdownStepInset(entry)
    return 0
end

local function FormatBreakdownStep(entry)
    local L = GetL()
    if entry and entry.rowType == "section" then
        return string.format("%s (%d)", tostring(entry.name or ""), tonumber(entry.count) or 0)
    end
    local action = GetBreakdownActionText(entry)
    local name = (entry and entry.name) or "Unknown"
    if entry and entry.kind == "craft" then
        local craftText = string.format("%d. %s %s", tonumber(entry.craftOrder) or 0, action, name)
        local quantities = (L["VI_HDR_CRAFT_QTY"] or "Craft Qty") .. ": "
            .. FormatTraceCount(entry.craftsExecution)
        if entry.expectedOutput then
            quantities = quantities .. "   |   " .. string.format(
                L["TT_ROW_EXPECTED_OUTPUT"] or "Expected Output: %s",
                "~" .. FormatTraceCount(entry.expectedOutput))
        end
        return craftText .. "\n" .. quantities
    end
    return action .. " " .. FormatTraceCount(entry and entry.needToBuy) .. " × " .. name

end

local function BuildBreakdownUsedCostText(entry)
    if not entry then
        return "—"
    end
    if entry.rowType == "section" then
        return ""
    end
    if entry.excludeFromCost then
        return "|cff888888Excluded|r"
    end
    if entry.kind == "craft" then
        if entry.chainTotalCostFull and entry.chainTotalCostFull > 0 then
            return GAM.Pricing.FormatPrice(entry.chainTotalCostFull)
        end
        if entry.hasMissingPrice then
            return "|cffff8800Missing|r"
        end
        return "—"
    end
    if entry.effectiveTotalCostToBuy then
        return GAM.Pricing.FormatPrice(entry.effectiveTotalCostToBuy)
    end
    if entry.effectiveTotalCostFull then
        return GAM.Pricing.FormatPrice(entry.effectiveTotalCostFull)
    end
    if entry.effectiveMissingPrice then
        return "|cffff8800Missing|r"
    end
    return "—"
end

local function BuildBreakdownModeText(entry)
    local L = GetL()
    if not entry then
        return "—"
    end
    if entry.rowType == "section" then
        return ""
    end
    if entry.excludeFromCost then
        return L["VI_SOURCE_IGNORED"] or "Ignored"
    end
    if entry.kind == "craft" then
        local gearLabels = {
            multicraft = "MC gear",
            resourcefulness = "Res gear",
            current = "current gear",
        }
        local gearText = gearLabels[entry.gearModeResolved]
            or gearLabels.current
        if entry.isFinalCraft then
            return (L["VI_SOURCE_FINAL_OUTPUT"] or "Final output") .. " · " .. gearText
        end
        return (L["VI_SOURCE_INTERMEDIATE"] or "Intermediate") .. " · " .. gearText
    end
    local mode = (entry.purchaseSource == "vendor")
        and (L["VI_SOURCE_VENDOR"] or "Vendor")
        or (L["VI_SOURCE_AUCTION"] or "Auction House")
    if entry.excludedFromEstimate then
        mode = mode .. " (" .. (L["VI_SOURCE_NOT_ESTIMATED"] or "not in estimate") .. ")"
    end
    return entry.effectiveMissingPrice and (mode .. ", " .. (L["VI_SOURCE_PRICE_MISSING"] or "price missing")) or mode
end

local function ShowBreakdownTooltip(self)
    local L = GetL()
    local entry = self and self._viEntry
    if not entry or entry.rowType == "section" then
        return
    end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(FormatBreakdownStep(entry), 1, 1, 1)
    if entry.selectedInputNames and #entry.selectedInputNames > 0 then
        GameTooltip:AddLine(string.format(L["VI_USE_INPUT_FORMAT"] or "%s — use %s",
            entry.name or "", table.concat(entry.selectedInputNames, ", ")), 1, 0.82, 0, true)
    end
    if entry.kind == "craft" then
        if entry.expectedOutput then
            GameTooltip:AddLine(L["VI_TT_OUTPUT_ESTIMATE"]
                or "Output is an estimate. Check your results before starting the next step.",
                0.82, 0.82, 0.82, true)
        end
        local gearLabels = {
            multicraft = L["GEAR_MODE_MC"] or "Multicraft",
            resourcefulness = L["GEAR_MODE_RES"] or "Resourcefulness",
            current = L["VI_GEAR_CURRENT"] or "Current gear",
        }
        if entry.gearModeResolved then
            GameTooltip:AddLine(string.format(L["VI_GEAR_FORMAT"] or "Gear: %s",
                gearLabels[entry.gearModeResolved] or gearLabels.current), 1, 0.82, 0)
        end
        if entry.gearPresetMissing then
            GameTooltip:AddLine(L["VI_GEAR_MISSING"]
                or "The selected gear setup is not saved; current gear stats are being used.",
                1, 0.45, 0.2, true)
        end
        if entry.expectedOutputPerCraft then
            GameTooltip:AddLine(string.format(L["VI_TT_AVG_OUTPUT"] or "Average output/craft: %.4f", entry.expectedOutputPerCraft), 1, 0.82, 0)
        end
        if entry.chainTotalCostFull and entry.chainTotalCostFull > 0 then
            GameTooltip:AddLine(string.format(L["VI_TT_USED_CHAIN_COST"] or "Used craft-chain cost: %s", GAM.Pricing.FormatPrice(entry.chainTotalCostFull)), 1, 0.82, 0)
        end
        if entry.directUnitPrice then
            GameTooltip:AddLine(string.format(L["VI_TT_DIRECT_AH_UNIT"] or "Direct AH unit: %s", GAM.Pricing.FormatPrice(entry.directUnitPrice)), 1, 0.82, 0)
        end
    else
        GameTooltip:AddLine(string.format(L["VI_TT_ALREADY_HAVE"] or "Already have: %s", FormatTraceCount(entry.have or 0)), 1, 0.82, 0)
        GameTooltip:AddLine(string.format(L["VI_TT_NEED_TO_BUY"] or "Need to buy: %s", FormatTraceCount(entry.needToBuy or 0)), 1, 0.82, 0)
        if entry.effectiveUnitPrice then
            GameTooltip:AddLine(string.format(L["VI_TT_USED_UNIT_PRICE"] or "Used unit price: %s", GAM.Pricing.FormatPrice(entry.effectiveUnitPrice)), 1, 0.82, 0)
        end
        local buyCost = entry.effectiveTotalCostToBuy or entry.effectiveTotalCostFull
        if buyCost then
            GameTooltip:AddLine(string.format(L["VI_TT_USED_TOTAL_COST"] or "Used total cost: %s", GAM.Pricing.FormatPrice(buyCost)), 1, 0.82, 0)
        end
        if entry.directUnitPrice and entry.directUnitPrice ~= entry.effectiveUnitPrice then
            GameTooltip:AddLine(string.format(L["VI_TT_DIRECT_AH_UNIT"] or "Direct AH unit: %s", GAM.Pricing.FormatPrice(entry.directUnitPrice)), 1, 0.82, 0)
        end
    end
    if entry.excludeFromCost or entry.excludedFromEstimate then
        GameTooltip:AddLine(L["VI_TT_EXCLUDED"] or "This step is not included in the estimate.", 1, 0.82, 0, true)
    elseif entry.hasMissingPrice or entry.effectiveMissingPrice then
        GameTooltip:AddLine(L["VI_TT_MISSING_PRICE"] or "Some price data is still missing for this step or its children.", 1, 0.82, 0, true)
    end
    GameTooltip:Show()
end

local function HideBreakdownTooltip()
    GameTooltip:Hide()
end

local function QueueCurrentBreakdown(win)
    local queue = GAM.CraftSimQueue
    local breakdown = win and win._breakdown
    if not (queue and breakdown and win._plan) then
        print("|cffff8800[GAM]|r CraftSim queue is unavailable for this plan.")
        return
    end
    local strategy = GAM.Importer and GAM.Importer.GetStratByID
        and GAM.Importer.GetStratByID(breakdown.stratID)
    local count, err = queue.QueueBreakdown(breakdown, win._plan, { strategy = strategy })
    if err then
        print("|cffff8800[GAM]|r CraftSim queue failed: " .. tostring(err))
    else
        print("|cff55ff55[GAM]|r Queued " .. tostring(count or 0) .. " CraftSim step(s).")
    end
end

local function GetVIBreakdownContentWidth(width)
    return math.max(660, width - 58)
end

local function AutoSizeVIBreakdownWindow(win, rowCount)
    if not win or win._userSized then
        return
    end
    local rows = math.max(0, tonumber(rowCount) or 0)
    local targetHeight = 90 + (rows * VI_ROW_H)
    targetHeight = math.max(VI_WINDOW_MIN_H, math.min(VI_WINDOW_MAX_H, targetHeight))
    if math.abs((win:GetHeight() or 0) - targetHeight) > 1 then
        win:SetHeight(targetHeight)
    end
end

local function SetVIBreakdownHeaderVisibility(win, shown)
    if not win then
        return
    end
    local function ApplyVisibility(fs)
        if not fs then
            return
        end
        if shown then
            fs:Show()
        else
            fs:Hide()
        end
    end
    ApplyVisibility(win.headerStepFS)
    shown = false -- Quantities are inline with each action, not in separate columns.
    ApplyVisibility(win.headerNeedFS)
    ApplyVisibility(win.headerEconomicFS)
    ApplyVisibility(win.headerExecutionFS)
    ApplyVisibility(win.headerUsedCostFS)
    ApplyVisibility(win.headerNoteFS)
end

local function ApplyVIBreakdownLayout(win)
    if not win then
        return
    end

    local width = math.max(VI_WINDOW_MIN_W, math.floor((win:GetWidth() or VI_WINDOW_W) + 0.5))
    local height = math.max(VI_WINDOW_MIN_H, math.floor((win:GetHeight() or VI_WINDOW_H) + 0.5))
    if width ~= (win:GetWidth() or 0) or height ~= (win:GetHeight() or 0) then
        win:SetSize(width, height)
        return
    end

    local contentWidth = GetVIBreakdownContentWidth(width)
    local amountW = 82
    local planW = 86
    local actualW = 86
    local usedCostW = math.max(122, math.floor(contentWidth * 0.17))
    local noteW = math.max(152, math.floor(contentWidth * 0.17))
    local reservedWidth = amountW + planW + actualW + usedCostW + noteW + 34
    local stepW = math.max(220, contentWidth - reservedWidth)
    local xNeed = stepW + 10
    local xEconomic = xNeed + amountW + 6
    local xExecution = xEconomic + planW + 6
    local xUsedCost = xExecution + actualW + 6
    local xNote = xUsedCost + usedCostW + 6

    win.subtitleFS:SetWidth(math.max(120, width - 360))
    win.emptyFS:SetWidth(contentWidth - 16)
    if win.summaryCard then
        win.summaryCard:Hide()
    end
    if win.queueBtn then
        win.queueBtn:ClearAllPoints()
        win.queueBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -42, -8)
    end
    if win.summaryRule then
        win.summaryRule:ClearAllPoints()
        win.summaryRule:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -42)
        win.summaryRule:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, -42)
    end
    win.headerStepFS:ClearAllPoints()
    win.headerStepFS:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -54)
    win.headerStepFS:SetWidth(contentWidth - 16)
    win.headerNeedFS:ClearAllPoints()
    win.headerNeedFS:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + xNeed, -54)
    win.headerNeedFS:SetWidth(amountW)
    win.headerEconomicFS:ClearAllPoints()
    win.headerEconomicFS:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + xEconomic, -54)
    win.headerEconomicFS:SetWidth(planW)
    win.headerExecutionFS:ClearAllPoints()
    win.headerExecutionFS:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + xExecution, -54)
    win.headerExecutionFS:SetWidth(actualW)
    win.headerUsedCostFS:ClearAllPoints()
    win.headerUsedCostFS:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + xUsedCost, -54)
    win.headerUsedCostFS:SetWidth(usedCostW)
    win.headerNoteFS:ClearAllPoints()
    win.headerNoteFS:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + xNote, -54)
    win.headerNoteFS:SetWidth(noteW)
    if win.scrollFrame then
        win.scrollFrame:ClearAllPoints()
        win.scrollFrame:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -68)
        win.scrollFrame:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -30, 14)
    end

    win.listHost:SetWidth(contentWidth)
    for _, row in ipairs(viBreakdownRows) do
        row:SetWidth(contentWidth)
        local stepInset = row._stepInset or 0
        row.stepFS:ClearAllPoints()
        row.stepFS:SetPoint("LEFT", row, "LEFT", 8 + stepInset, 0)
        row.stepFS:SetWidth(contentWidth - stepInset - 16)
        row.stepFS:SetHeight(VI_ROW_H - 6)
        row.needFS:Hide()
        row.economicFS:Hide()
        row.executionFS:Hide()
        row.usedCostFS:Hide()
        row.noteFS:Hide()
        row.needFS:ClearAllPoints()
        row.needFS:SetPoint("LEFT", row, "LEFT", xNeed, 0)
        row.needFS:SetWidth(amountW)
        row.economicFS:ClearAllPoints()
        row.economicFS:SetPoint("LEFT", row, "LEFT", xEconomic, 0)
        row.economicFS:SetWidth(planW)
        row.executionFS:ClearAllPoints()
        row.executionFS:SetPoint("LEFT", row, "LEFT", xExecution, 0)
        row.executionFS:SetWidth(actualW)
        row.usedCostFS:ClearAllPoints()
        row.usedCostFS:SetPoint("LEFT", row, "LEFT", xUsedCost, 0)
        row.usedCostFS:SetWidth(usedCostW)
        row.noteFS:ClearAllPoints()
        row.noteFS:SetPoint("LEFT", row, "LEFT", xNote, 0)
        row.noteFS:SetWidth(noteW - 6)
    end
end

local function ShowVIBreakdownMessage(win, breakdown, message, detail)
    if not win then
        return
    end

    local L = GetL()
    win._breakdown = breakdown
    win._stratID = breakdown and breakdown.stratID or nil
    win._patchTag = breakdown and breakdown.patchTag or nil
    if win.queueBtn then
        win.queueBtn:Disable()
        win.queueBtn:Hide()
    end
    win.titleFS:SetText(L["VI_BREAKDOWN_TITLE"] or "VI Breakdown")
    win.subtitleFS:SetText((breakdown and breakdown.stratName or (L["VI_SELECTED_STRAT"] or "Selected Strategy"))
        .. " | "
        .. (((breakdown and breakdown.chainActive) and (L["VI_STATUS_ENABLED"] or "VI on")) or (L["VI_STATUS_DISABLED"] or "VI off")))
    win.summaryFS:SetText(detail or "")
    win.summaryNoteFS:SetText(message or "")
    SetVIBreakdownHeaderVisibility(win, false)
    for index = 1, #viBreakdownRows do
        viBreakdownRows[index]._viEntry = nil
        viBreakdownRows[index]:Hide()
    end
    win.listHost:SetHeight(1)
    win.emptyFS:SetText(message or "")
    win.emptyFS:Show()
    if win._gamThemeRefresh then win._gamThemeRefresh(win) end
    AutoSizeVIBreakdownWindow(win, 0)
    ApplyVIBreakdownLayout(win)
end

local function GetVIBreakdownThemeColors()
    local theme = Common and Common.GetThemeDef and Common.GetThemeDef() or nil
    local primary = theme and (theme.primaryText or theme.bodyText or theme.cardBodyText)
        or { 0.88, 0.88, 0.90, 1 }
    local secondary = theme and (theme.secondaryText or theme.mutedText)
        or { 0.68, 0.68, 0.72, 1 }
    local accent = theme and (theme.accent or theme.titleText)
        or DEFAULT_GOLD
    local frameBg = theme and theme.frame and theme.frame.bgColor
        or { 0.055, 0.055, 0.062, 1 }
    local frameBorder = theme and theme.frame and theme.frame.borderColor
        or { 0.48, 0.40, 0.16, 0.90 }
    local shell = theme and theme.shells and theme.shells.card
    local cardBg = shell and (shell.outerBgColor or shell.innerBgColor)
        or { 0.105, 0.105, 0.115, 1 }
    local cardBorder = shell and (shell.outerBorderColor or shell.innerBorderColor)
        or { 0.30, 0.28, 0.22, 0.75 }
    local odd = theme and theme.listRowOdd or { 0.155, 0.155, 0.168, 1 }
    local even = theme and theme.listRowEven or { 0.125, 0.125, 0.138, 1 }
    local section = theme and theme.sectionHeader or { 0.22, 0.16, 0.04, 0.96 }
    local separator = theme and theme.separatorColor or DEFAULT_RULE
    return theme, primary, secondary, accent, frameBg, frameBorder,
        cardBg, cardBorder, odd, even, section, separator
end

local function SetTextColor(fontString, color)
    if fontString and color then
        fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function ApplyVIBreakdownRowTheme(row, index, colors)
    if not row or not row._viEntry then return end
    local entry = row._viEntry
    local _, primary, secondary, accent, _, _, _, _, odd, even, section, separator = unpack(colors)
    local rowColor = (index % 2 == 1) and odd or even
    row.topRule:SetColorTexture(separator[1], separator[2], separator[3], separator[4] or 0.48)
    row.stageAccent:SetColorTexture(accent[1], accent[2], accent[3], 0.88)

    if entry.rowType == "section" then
        SetTextColor(row.stepFS, accent)
        row.bg:SetColorTexture(section[1], section[2], section[3], section[4] or 1)
        row.stageAccent:Show()
    elseif entry.excludeFromCost then
        SetTextColor(row.stepFS, secondary)
        SetTextColor(row.usedCostFS, secondary)
        SetTextColor(row.noteFS, secondary)
        row.bg:SetColorTexture(even[1], even[2], even[3], even[4] or 1)
        row.stageAccent:Hide()
    elseif entry.kind == "craft" and row._isStage then
        SetTextColor(row.stepFS, { 0.45, 1.0, 0.45, 1 })
        SetTextColor(row.usedCostFS, accent)
        SetTextColor(row.noteFS, secondary)
        row.bg:SetColorTexture(0.06, 0.18, 0.06, 0.82)
        row.stageAccent:Show()
    elseif entry.kind == "craft" then
        SetTextColor(row.stepFS, accent)
        SetTextColor(row.usedCostFS, accent)
        SetTextColor(row.noteFS, secondary)
        row.bg:SetColorTexture(rowColor[1], rowColor[2], rowColor[3], rowColor[4] or 1)
        row.stageAccent:Hide()
    else
        SetTextColor(row.stepFS, primary)
        SetTextColor(row.usedCostFS, primary)
        SetTextColor(row.noteFS, secondary)
        row.bg:SetColorTexture(rowColor[1], rowColor[2], rowColor[3], rowColor[4] or 1)
        row.stageAccent:Hide()
    end

    SetTextColor(row.needFS, primary)
    SetTextColor(row.economicFS, secondary)
    SetTextColor(row.executionFS, { 0.76, 0.92, 0.76, 1 })
end

local function ApplyVIBreakdownTheme(win)
    if not win then return end
    local theme, primary, secondary, accent, frameBg, frameBorder,
        cardBg, cardBorder, odd, even, section, separator = GetVIBreakdownThemeColors()
    if Common and Common.SetBackdropColors then
        Common.SetBackdropColors(win, frameBg, frameBorder)
        if win.summaryCard then Common.SetBackdropColors(win.summaryCard, cardBg, cardBorder) end
    end
    if win.bgTex then win.bgTex:SetColorTexture(frameBg[1], frameBg[2], frameBg[3], frameBg[4] or 1) end
    SetTextColor(win.titleFS, accent)
    SetTextColor(win.subtitleFS, secondary)
    SetTextColor(win.summaryFS, accent)
    SetTextColor(win.summaryNoteFS, secondary)
    SetTextColor(win.emptyFS, secondary)
    for _, fs in ipairs({
        win.headerStepFS, win.headerNeedFS, win.headerEconomicFS,
        win.headerExecutionFS, win.headerUsedCostFS, win.headerNoteFS,
    }) do
        SetTextColor(fs, accent)
    end
    if win.summaryRule then
        win.summaryRule:SetColorTexture(separator[1], separator[2], separator[3], separator[4] or 0.6)
    end
    if win.queueBtn and Common and Common.StyleComfortableButton then
        Common.StyleComfortableButton(win.queueBtn, false)
    end
    local colors = { theme, primary, secondary, accent, frameBg, frameBorder,
        cardBg, cardBorder, odd, even, section, separator }
    for index, row in ipairs(viBreakdownRows) do
        ApplyVIBreakdownRowTheme(row, index, colors)
    end
end

local function EnsureVIBreakdownWindow()
    if viBreakdownWindow then
        return viBreakdownWindow
    end

    viBreakdownWindow = CreateFrame("Frame", GAM.RuntimeName("GAMVIBreakdownWindow"), UIParent, "BackdropTemplate")
    viBreakdownWindow:SetSize(VI_WINDOW_W, VI_WINDOW_H)
    viBreakdownWindow:SetResizable(true)
    viBreakdownWindow:SetScale((GAM.GetOption and GAM:GetOption("uiScale", 1.0)) or 1.0)
    viBreakdownWindow:SetMovable(true)
    viBreakdownWindow:EnableMouse(true)
    viBreakdownWindow:RegisterForDrag("LeftButton")
    viBreakdownWindow:SetScript("OnDragStart", viBreakdownWindow.StartMoving)
    viBreakdownWindow:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self._userMoved = true
    end)
    viBreakdownWindow:SetClampedToScreen(true)
    viBreakdownWindow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    viBreakdownWindow:SetBackdropColor(0.055, 0.055, 0.062, 1)
    viBreakdownWindow:SetBackdropBorderColor(0.48, 0.40, 0.16, 0.9)
    viBreakdownWindow:Hide()
    WindowManager.Register(viBreakdownWindow, "dialog")

    local bgTex = viBreakdownWindow:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0.055, 0.055, 0.062, 1)
    viBreakdownWindow.bgTex = bgTex

    local title = viBreakdownWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", viBreakdownWindow, "TOPLEFT", 16, -14)
    title:SetText((GetL()["VI_BREAKDOWN_TITLE"]) or "VI Breakdown")
    title:SetTextColor(DEFAULT_GOLD[1], DEFAULT_GOLD[2], DEFAULT_GOLD[3])
    viBreakdownWindow._gamTitle = title
    viBreakdownWindow.titleFS = title

    local subtitle = viBreakdownWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("LEFT", title, "RIGHT", 12, 0)
    subtitle:SetWidth(VI_WINDOW_W - 40)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetTextColor(0.75, 0.72, 0.64, 1)
    viBreakdownWindow._gamSubtitle = subtitle
    viBreakdownWindow.subtitleFS = subtitle

    local summaryCard = CreateFrame("Frame", nil, viBreakdownWindow, "BackdropTemplate")
    summaryCard:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    summaryCard:SetBackdropColor(0.105, 0.105, 0.115, 1)
    summaryCard:SetBackdropBorderColor(0.30, 0.28, 0.22, 0.75)
    summaryCard._gamComfortSurface = true
    viBreakdownWindow.summaryCard = summaryCard

    local summary = summaryCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 12, -5)
    summary:SetPoint("TOPRIGHT", summaryCard, "TOPRIGHT", -164, -5)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(false)
    summary:SetTextColor(1.0, 0.82, 0.0, 1.0)
    viBreakdownWindow.summaryFS = summary

    local summaryNote = summaryCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summaryNote:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 12, -22)
    summaryNote:SetPoint("TOPRIGHT", summaryCard, "TOPRIGHT", -164, -22)
    summaryNote:SetJustifyH("LEFT")
    summaryNote:SetWordWrap(false)
    summaryNote:SetTextColor(0.78, 0.78, 0.78, 1.0)
    viBreakdownWindow.summaryNoteFS = summaryNote

    local queueBtn = CreateFrame("Button", nil, viBreakdownWindow, "UIPanelButtonTemplate")
    queueBtn:SetSize(142, 22)
    queueBtn:SetText(GetL()["BTN_QUEUE_CRAFTSIM"] or "Queue in CraftSim")
    queueBtn:SetScript("OnClick", function()
        QueueCurrentBreakdown(viBreakdownWindow)
    end)
    queueBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(GetL()["BTN_QUEUE_CRAFTSIM"] or "Queue in CraftSim", 1, 1, 1)
        GameTooltip:AddLine(GetL()["TT_QUEUE_CRAFTSIM"]
            or "Validate the full execution plan, then append it to CraftSim.",
            1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    queueBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local common = GAM.UI and GAM.UI.MainWindowCommon
    if common and common.StyleComfortableButton then
        common.StyleComfortableButton(queueBtn, false)
    end
    queueBtn:Disable()
    queueBtn:Hide()
    viBreakdownWindow.queueBtn = queueBtn

    local closeBtn = CreateFrame("Button", nil, viBreakdownWindow, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", viBreakdownWindow, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        viBreakdownWindow:Hide()
    end)
    viBreakdownWindow.closeBtn = closeBtn

    local rule = viBreakdownWindow:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", viBreakdownWindow, "TOPLEFT", 12, -42)
    rule:SetPoint("TOPRIGHT", viBreakdownWindow, "TOPRIGHT", -12, -42)
    rule:SetColorTexture(DEFAULT_RULE[1], DEFAULT_RULE[2], DEFAULT_RULE[3], 0.6)
    viBreakdownWindow.summaryRule = rule

    local function MakeHdr(text)
        local fs = viBreakdownWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        fs:SetTextColor(1.0, 0.84, 0.22, 1.0)
        return fs
    end

    viBreakdownWindow.headerStepFS = MakeHdr((GetL()["VI_HDR_ITEM_OUTPUT"]) or "Item / Output")
    viBreakdownWindow.headerNeedFS = MakeHdr((GetL()["VI_HDR_QTY_NEEDED"]) or "Qty Needed")
    viBreakdownWindow.headerEconomicFS = MakeHdr((GetL()["VI_HDR_EXPECTED_CRAFTS"]) or "Expected")
    viBreakdownWindow.headerExecutionFS = MakeHdr((GetL()["VI_HDR_CRAFT_QTY"]) or "Craft Qty")
    viBreakdownWindow.headerUsedCostFS = MakeHdr((GetL()["VI_HDR_EST_COST"]) or "Est. Cost")
    viBreakdownWindow.headerNoteFS = MakeHdr((GetL()["VI_HDR_METHOD"]) or "Method")
    viBreakdownWindow.headerNeedFS:SetJustifyH("CENTER")
    viBreakdownWindow.headerEconomicFS:SetJustifyH("CENTER")
    viBreakdownWindow.headerExecutionFS:SetJustifyH("CENTER")

    local scroll = CreateFrame("ScrollFrame", nil, viBreakdownWindow, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", viBreakdownWindow, "TOPLEFT", 16, -68)
    scroll:SetPoint("BOTTOMRIGHT", viBreakdownWindow, "BOTTOMRIGHT", -30, 18)
    viBreakdownWindow.scrollFrame = scroll

    local listHost = CreateFrame("Frame", nil, scroll)
    listHost:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    listHost:SetWidth(GetVIBreakdownContentWidth(VI_WINDOW_W))
    listHost:SetHeight(1)
    scroll:SetScrollChild(listHost)
    viBreakdownWindow.listHost = listHost

    local emptyFS = viBreakdownWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyFS:SetPoint("TOPLEFT", scroll, "TOPLEFT", 8, -10)
    emptyFS:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -8, -10)
    emptyFS:SetJustifyH("CENTER")
    emptyFS:SetJustifyV("TOP")
    emptyFS:SetWordWrap(true)
    emptyFS:SetTextColor(0.78, 0.78, 0.78, 1.0)
    emptyFS:Hide()
    viBreakdownWindow.emptyFS = emptyFS

    listHost:EnableMouseWheel(true)
    listHost:SetScript("OnMouseWheel", function(_, delta)
        local cur = scroll:GetVerticalScroll()
        local max = scroll:GetVerticalScrollRange()
        scroll:SetVerticalScroll(math.max(0, math.min(max, cur - delta * (VI_ROW_H * 3))))
    end)

    viBreakdownWindow:SetScript("OnSizeChanged", function(self)
        ApplyVIBreakdownLayout(self)
    end)

    local resizeBtn = CreateFrame("Button", nil, viBreakdownWindow)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", viBreakdownWindow, "BOTTOMRIGHT", -8, 8)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:SetScript("OnMouseDown", function()
        viBreakdownWindow:StartSizing("BOTTOMRIGHT")
    end)
    resizeBtn:SetScript("OnMouseUp", function()
        viBreakdownWindow:StopMovingOrSizing()
        viBreakdownWindow._userSized = true
        viBreakdownWindow._userMoved = true
        ApplyVIBreakdownLayout(viBreakdownWindow)
    end)
    viBreakdownWindow.resizeBtn = resizeBtn
    viBreakdownWindow._gamThemeRefresh = ApplyVIBreakdownTheme
    ApplyVIBreakdownTheme(viBreakdownWindow)
    SetVIBreakdownHeaderVisibility(viBreakdownWindow, true)
    ApplyVIBreakdownLayout(viBreakdownWindow)

    return viBreakdownWindow
end

local function EnsureVIBreakdownRow(index)
    if viBreakdownRows[index] then
        return viBreakdownRows[index]
    end

    local win = EnsureVIBreakdownWindow()
    local row = CreateFrame("Button", nil, win.listHost)
    row:SetHeight(VI_ROW_H)
    row:SetWidth(GetVIBreakdownContentWidth(win:GetWidth() or VI_WINDOW_W))
    row:SetPoint("TOPLEFT", win.listHost, "TOPLEFT", 0, -((index - 1) * VI_ROW_H))

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 1)
    bg:SetColorTexture(0.10, 0.10, 0.10, (index % 2 == 1) and 0.55 or 0.28)

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

    local stepFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stepFS:SetPoint("LEFT", row, "LEFT", 4, 0)
    stepFS:SetJustifyH("LEFT")
    stepFS:SetWordWrap(false)

    local needFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    needFS:SetJustifyH("CENTER")
    needFS:SetWordWrap(false)

    local economicFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    economicFS:SetJustifyH("CENTER")
    economicFS:SetWordWrap(false)

    local executionFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    executionFS:SetJustifyH("CENTER")
    executionFS:SetWordWrap(false)

    local usedCostFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    usedCostFS:SetJustifyH("LEFT")
    usedCostFS:SetWordWrap(false)

    local noteFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    noteFS:SetJustifyH("LEFT")
    noteFS:SetWordWrap(false)

    row.bg = bg
    row.topRule = topRule
    row.stageAccent = stageAccent
    row.stepFS = stepFS
    row.needFS = needFS
    row.economicFS = economicFS
    row.executionFS = executionFS
    row.usedCostFS = usedCostFS
    row.noteFS = noteFS
    row:SetScript("OnEnter", ShowBreakdownTooltip)
    row:SetScript("OnLeave", HideBreakdownTooltip)
    viBreakdownRows[index] = row

    ApplyVIBreakdownLayout(win)
    return row
end

local function RenderVIBreakdownWindow(win, breakdown)
    if not (win and breakdown and breakdown.entries) then
        return
    end

    local L = GetL()
    local vendorPrices = GAM.VendorPrices and GAM.VendorPrices.GetResolvedCatalog
        and GAM.VendorPrices.GetResolvedCatalog()
        or ((GAM.C and GAM.C.VENDOR_PRICES) or {})
    local plan = VIBreakdownPlan.Build(breakdown, vendorPrices, {
        vendor = L["VI_SECTION_VENDOR"] or "Vendor Purchases",
        auction = L["VI_SECTION_AUCTION"] or "Auction House Purchases",
        craft = L["VI_SECTION_CRAFTING"] or "Crafting Order",
    })
    local orderedEntries = plan.rows
    win._breakdown = breakdown
    win._plan = plan
    win._stratID = breakdown.stratID
    win._patchTag = breakdown.patchTag
    if win.queueBtn then
        win.queueBtn:SetText(L["BTN_QUEUE_CRAFTSIM"] or "Queue in CraftSim")
        if GAM.CraftSimQueue and GAM.CraftSimQueue.IsAvailable
                and GAM.CraftSimQueue.IsAvailable()
                and #((plan and plan.craftSteps) or {}) > 0 then
            win.queueBtn:Enable()
            win.queueBtn:Show()
        else
            win.queueBtn:Disable()
            win.queueBtn:Hide()
        end
    end
    win.titleFS:SetText(L["VI_BREAKDOWN_TITLE"] or "VI Breakdown")
    win.subtitleFS:SetText((breakdown.stratName or (L["VI_SELECTED_STRAT"] or "Selected Strategy"))
        .. " | "
        .. ((breakdown.chainActive and (L["VI_STATUS_ENABLED"] or "VI on")) or (L["VI_STATUS_DISABLED"] or "VI off")))

    local metricParts = {}
    local missingCost = breakdown.totalCostFull == nil
    for _, entry in ipairs(orderedEntries) do
        missingCost = missingCost or entry.effectiveMissingPrice or entry.hasMissingPrice
    end
    if missingCost then
        metricParts[#metricParts + 1] = "Cost unavailable (missing prices)"
    elseif breakdown.totalCostFull then
        metricParts[#metricParts + 1] = "Cost " .. GAM.Pricing.FormatPrice(breakdown.totalCostFull)
    end
    if breakdown.netRevenue then
        metricParts[#metricParts + 1] = "Net " .. GAM.Pricing.FormatPrice(breakdown.netRevenue)
    end
    if breakdown.profit then
        metricParts[#metricParts + 1] = "Profit " .. GAM.Pricing.FormatPrice(breakdown.profit)
    end
    if breakdown.roi then
        metricParts[#metricParts + 1] = string.format("ROI %.1f%%", breakdown.roi)
    end
    win.summaryFS:SetText(table.concat(metricParts, "   "))
    if breakdown.capacityLimited then
        local capacityMessage = L["VI_SUMMARY_CAPACITY_LIMITED"]
            or "Live charges limit this craft-now plan to %d of %d requested crafts."
        win.summaryNoteFS:SetText(string.format(
            capacityMessage,
            tonumber(breakdown.finalCraftCapacity) or 0,
            tonumber(breakdown.requestedFinalCraftsExecution) or 0))
    elseif breakdown.usedFallbackRows then
        win.summaryNoteFS:SetText(L["VI_SUMMARY_FALLBACK"] or "Showing the combined shopping view because branch-by-branch VI steps are not available for this strategy.")
    else
        win.summaryNoteFS:SetText(L["VI_SUMMARY_GROUPED"] or "Buy grouped materials first, then complete the crafting order from top to bottom.")
    end
    AutoSizeVIBreakdownWindow(win, #orderedEntries)
    SetVIBreakdownHeaderVisibility(win, #orderedEntries > 0)
    ApplyVIBreakdownLayout(win)

    for index, entry in ipairs(orderedEntries) do
        local row = EnsureVIBreakdownRow(index)
        row._viEntry = entry
        row._stepInset = GetBreakdownStepInset(entry)
        row._isStage = IsPrimaryBreakdownStage(entry)
        row.stepFS:SetText(FormatBreakdownStep(entry))
        row.needFS:SetText(entry.rowType == "section" and "" or FormatTraceCount(
            (entry.kind == "craft") and (entry.requiredRaw or entry.required) or entry.needToBuy))
        row.economicFS:SetText((entry.kind == "craft") and FormatTraceCount(entry.craftsEconomic) or "—")
        row.executionFS:SetText((entry.kind == "craft") and FormatTraceCount(entry.craftsExecution) or "—")
        row.usedCostFS:SetText(BuildBreakdownUsedCostText(entry))
        row.noteFS:SetText(BuildBreakdownModeText(entry))
        if entry.rowType == "section" then
            row.stepFS:SetTextColor(1.0, 0.84, 0.22, 1.0)
            row.needFS:SetText("")
            row.economicFS:SetText("")
            row.executionFS:SetText("")
            row.usedCostFS:SetText("")
            row.noteFS:SetText("")
            row.bg:SetColorTexture(0.22, 0.16, 0.04, 0.96)
            row.stageAccent:Show()
            row.topRule:SetShown(index > 1)
        elseif entry.excludeFromCost then
            row.stepFS:SetTextColor(0.62, 0.62, 0.62, 1)
            row.usedCostFS:SetTextColor(0.62, 0.62, 0.62, 1)
            row.noteFS:SetTextColor(0.62, 0.62, 0.62, 1)
            row.bg:SetColorTexture(0.125, 0.125, 0.138, 1.0)
            row.stageAccent:Hide()
            row.topRule:Hide()
        elseif entry.kind == "craft" then
            row.usedCostFS:SetTextColor(1.0, 0.84, 0.22, 1.0)
            if row._isStage then
                row.stepFS:SetTextColor(0.45, 1.0, 0.45, 1.0)
                row.noteFS:SetTextColor(0.92, 0.86, 0.66, 1.0)
                row.bg:SetColorTexture(0.06, 0.18, 0.06, 0.82)
                row.stageAccent:Show()
                row.topRule:SetShown(index > 1)
            else
                row.stepFS:SetTextColor(1.0, 0.84, 0.22, 1.0)
                row.noteFS:SetTextColor(0.84, 0.80, 0.68, 1.0)
                row.bg:SetColorTexture(0.12, 0.10, 0.04, (index % 2 == 1) and 0.54 or 0.38)
                row.stageAccent:Hide()
                row.topRule:Hide()
            end
        else
            row.stepFS:SetTextColor(0.95, 0.95, 0.95, 1)
            row.usedCostFS:SetTextColor(0.92, 0.92, 0.92, 1)
            row.noteFS:SetTextColor(0.78, 0.78, 0.78, 1)
            row.bg:SetColorTexture(
                index % 2 == 1 and 0.155 or 0.125,
                index % 2 == 1 and 0.155 or 0.125,
                index % 2 == 1 and 0.168 or 0.138,
                1.0
            )
            row.stageAccent:Hide()
            row.topRule:Hide()
        end
        row.needFS:SetTextColor(0.92, 0.92, 0.92, 1)
        row.economicFS:SetTextColor(0.88, 0.88, 0.88, 1)
        row.executionFS:SetTextColor(0.76, 0.92, 0.76, 1)
        row:Show()
    end

    if #orderedEntries > 0 then
        win.emptyFS:Hide()
    else
        win.emptyFS:SetText(L["VI_NO_ROWS"] or "No VI rows were generated for this strategy.")
        win.emptyFS:Show()
    end

    for index = #orderedEntries + 1, #viBreakdownRows do
        viBreakdownRows[index]._viEntry = nil
        viBreakdownRows[index]:Hide()
    end

    if win._gamThemeRefresh then win._gamThemeRefresh(win) end

    win.listHost:SetHeight(math.max(1, #orderedEntries * VI_ROW_H))
    win.scrollFrame:SetVerticalScroll(0)
    ApplyVIBreakdownLayout(win)
    if not win._userMoved then
        win:ClearAllPoints()
        win:SetPoint("CENTER")
    end
end

local function HideVIBreakdownWindow()
    if viBreakdownWindow then
        viBreakdownWindow:Hide()
    end
end

local function ShowVIBreakdownWindow(strat, patchTag, metrics)
    if not (strat and GAM.PricingFacade and GAM.PricingFacade.GetCurrentVIBreakdown) then
        return
    end
    local win = EnsureVIBreakdownWindow()
    local function HandleBreakdownError(message)
        local L = GetL()
        local stack = debugstack and debugstack(2, 6, 6) or ""
        local combined = tostring(message) .. (stack ~= "" and ("\n" .. stack) or "")
        if GAM.Log and GAM.Log.Warn then
            GAM.Log.Warn("VI breakdown render failed for '%s': %s",
                tostring(strat and (strat.stratName or strat.id) or "?"), tostring(combined))
        end
        ShowVIBreakdownMessage(
            win,
            {
                stratID = strat and strat.id or nil,
                stratName = strat and strat.stratName or nil,
                patchTag = patchTag,
                chainActive = true,
            },
            L["VI_RENDER_ERROR"] or "Unable to render VI breakdown for this strategy on the current client state.",
            L["VI_RENDER_ERROR_DETAIL"] or "Use /gam log to capture the underlying UI error."
        )
        win:Show()
        WindowManager.Present(win)
    end

    local ok, breakdownOrErr = xpcall(function()
        local breakdown = GAM.PricingFacade.GetCurrentVIBreakdown(strat, patchTag, metrics)
        if not breakdown then
            return nil
        end
        RenderVIBreakdownWindow(win, breakdown)
        if GAM.Log and GAM.Log.Debug then
            GAM.Log.Debug("VI breakdown ready for '%s': %d rows%s",
                tostring(breakdown.stratName or breakdown.stratID or "?"),
                #(breakdown.entries or {}),
                breakdown.usedFallbackRows and " (fallback)" or "")
        end
        return breakdown
    end, function(message)
        HandleBreakdownError(message)
        return tostring(message)
    end)

    if not ok then
        return
    end
    if not breakdownOrErr then
        local L = GetL()
        ShowVIBreakdownMessage(
            win,
            {
                stratID = strat and strat.id or nil,
                stratName = strat and strat.stratName or nil,
                patchTag = patchTag,
                chainActive = true,
            },
            L["VI_NO_ROWS"] or "No VI rows were generated for this strategy.",
            L["VI_NO_ROWS_DETAIL"] or "If this keeps happening, use /gam log and share the latest entries."
        )
    end
    win:Show()
    WindowManager.Present(win)
end

VIBreakdownWindow.Show = function(...)
    if GAM.UI.CraftPlanWindow then return GAM.UI.CraftPlanWindow.Show(...) end
    return ShowVIBreakdownWindow(...)
end
VIBreakdownWindow.Hide = function()
    -- The saved plan is independent of strategy selection; do not close it
    -- when the main detail panel changes or is hidden.
    HideVIBreakdownWindow()
end
