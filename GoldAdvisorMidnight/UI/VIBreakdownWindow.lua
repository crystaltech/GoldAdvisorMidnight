-- GoldAdvisorMidnight/UI/VIBreakdownWindow.lua
-- Vertical-integration analysis window owned independently from base strategy detail.
-- Module: GAM.UI.VIBreakdownWindow

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local VIBreakdownWindow = {}
GAM.UI.VIBreakdownWindow = VIBreakdownWindow

local WindowManager = GAM.UI.WindowManager
local VIBreakdownPlan = GAM.UI.VIBreakdownPlan
local DEFAULT_GOLD = { 1.0, 0.82, 0.0 }
local DEFAULT_RULE = { 0.7, 0.57, 0.0, 0.7 }
local VI_WINDOW_W = 920
local VI_WINDOW_H = 420
local VI_WINDOW_MIN_W = 720
local VI_WINDOW_MIN_H = 280
local VI_ROW_H = 22

local function GetL()
    return GAM.L or {}
end

local function AddThousandsSeparators(text)
    local sign, digits, frac = tostring(text or ""):match("^([%-]?)(%d+)(%.%d+)?$")
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
        if entry.selectedInputNames and #entry.selectedInputNames > 0 then
            return string.format(
                L["VI_USE_INPUT_FORMAT"] or "%s — use %s",
                craftText,
                table.concat(entry.selectedInputNames, ", "))
        end
        return craftText
    end
    return name
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
        if entry.isFinalCraft then
            return L["VI_SOURCE_FINAL_OUTPUT"] or "Final output"
        end
        return L["VI_SOURCE_INTERMEDIATE"] or "Intermediate"
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
    GameTooltip:AddLine(L["VI_TT_ROW"] or "One craft or purchase step", 0.82, 0.82, 0.82)
    GameTooltip:AddLine(string.format(L["VI_TT_AMOUNT_NEEDED"] or "Amount needed: %s",
        FormatTraceCount((entry.kind == "craft") and (entry.requiredRaw or entry.required) or entry.needToBuy)), 1, 0.82, 0)
    if entry.kind == "craft" then
        GameTooltip:AddLine(string.format(L["VI_TT_PLAN_CRAFTS"] or "Plan crafts: %s", FormatTraceCount(entry.craftsEconomic)), 1, 0.82, 0)
        GameTooltip:AddLine(string.format(L["VI_TT_ACTUAL_CRAFTS"] or "Actual crafts: %s", FormatTraceCount(entry.craftsExecution)), 1, 0.82, 0)
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

local function GetVIBreakdownContentWidth(width)
    return math.max(660, width - 58)
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

    win.subtitleFS:SetWidth(width - 40)
    win.emptyFS:SetWidth(contentWidth - 16)
    if win.summaryCard then
        win.summaryCard:ClearAllPoints()
        win.summaryCard:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -54)
        win.summaryCard:SetPoint("TOPRIGHT", win, "TOPRIGHT", -16, -54)
        win.summaryCard:SetHeight(60)
    end
    if win.summaryRule then
        win.summaryRule:ClearAllPoints()
        win.summaryRule:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -122)
        win.summaryRule:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, -122)
    end
    win.headerStepFS:ClearAllPoints()
    win.headerStepFS:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -136)
    win.headerStepFS:SetWidth(stepW)
    win.headerNeedFS:ClearAllPoints()
    win.headerNeedFS:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + xNeed, -136)
    win.headerNeedFS:SetWidth(amountW)
    win.headerEconomicFS:ClearAllPoints()
    win.headerEconomicFS:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + xEconomic, -136)
    win.headerEconomicFS:SetWidth(planW)
    win.headerExecutionFS:ClearAllPoints()
    win.headerExecutionFS:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + xExecution, -136)
    win.headerExecutionFS:SetWidth(actualW)
    win.headerUsedCostFS:ClearAllPoints()
    win.headerUsedCostFS:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + xUsedCost, -136)
    win.headerUsedCostFS:SetWidth(usedCostW)
    win.headerNoteFS:ClearAllPoints()
    win.headerNoteFS:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + xNote, -136)
    win.headerNoteFS:SetWidth(noteW)
    if win.scrollFrame then
        win.scrollFrame:ClearAllPoints()
        win.scrollFrame:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -150)
        win.scrollFrame:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -30, 18)
    end

    win.listHost:SetWidth(contentWidth)
    for _, row in ipairs(viBreakdownRows) do
        row:SetWidth(contentWidth)
        local stepInset = row._stepInset or 0
        row.stepFS:ClearAllPoints()
        row.stepFS:SetPoint("LEFT", row, "LEFT", 8 + stepInset, 0)
        row.stepFS:SetWidth(math.max(80, stepW - stepInset - 12))
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
    ApplyVIBreakdownLayout(win)
end

local function EnsureVIBreakdownWindow()
    if viBreakdownWindow then
        return viBreakdownWindow
    end

    viBreakdownWindow = CreateFrame("Frame", "GAMVIBreakdownWindow", UIParent, "BackdropTemplate")
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
    viBreakdownWindow:SetBackdropColor(0, 0, 0, 1)
    viBreakdownWindow:SetBackdropBorderColor(0.7, 0.57, 0.0, 0.62)
    viBreakdownWindow:Hide()
    WindowManager.Register(viBreakdownWindow, "dialog")

    local bgTex = viBreakdownWindow:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0, 0, 0, 1)

    local title = viBreakdownWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", viBreakdownWindow, "TOP", 0, -14)
    title:SetText((GetL()["VI_BREAKDOWN_TITLE"]) or "VI Breakdown")
    title:SetTextColor(DEFAULT_GOLD[1], DEFAULT_GOLD[2], DEFAULT_GOLD[3])
    viBreakdownWindow.titleFS = title

    local subtitle = viBreakdownWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetWidth(VI_WINDOW_W - 40)
    subtitle:SetJustifyH("CENTER")
    subtitle:SetTextColor(0.75, 0.72, 0.64, 1)
    viBreakdownWindow.subtitleFS = subtitle

    local summaryCard = CreateFrame("Frame", nil, viBreakdownWindow, "BackdropTemplate")
    summaryCard:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    summaryCard:SetBackdropColor(0.09, 0.07, 0.04, 0.96)
    summaryCard:SetBackdropBorderColor(DEFAULT_RULE[1], DEFAULT_RULE[2], DEFAULT_RULE[3], 0.46)
    viBreakdownWindow.summaryCard = summaryCard

    local summary = summaryCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 12, -8)
    summary:SetPoint("TOPRIGHT", summaryCard, "TOPRIGHT", -12, -8)
    summary:SetJustifyH("CENTER")
    summary:SetWordWrap(false)
    summary:SetTextColor(1.0, 0.82, 0.0, 1.0)
    viBreakdownWindow.summaryFS = summary

    local summaryNote = summaryCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summaryNote:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 12, -28)
    summaryNote:SetPoint("TOPRIGHT", summaryCard, "TOPRIGHT", -12, -28)
    summaryNote:SetPoint("BOTTOMLEFT", summaryCard, "BOTTOMLEFT", 12, 8)
    summaryNote:SetPoint("BOTTOMRIGHT", summaryCard, "BOTTOMRIGHT", -12, 8)
    summaryNote:SetJustifyH("CENTER")
    summaryNote:SetWordWrap(true)
    summaryNote:SetTextColor(0.78, 0.78, 0.78, 1.0)
    viBreakdownWindow.summaryNoteFS = summaryNote

    local closeBtn = CreateFrame("Button", nil, viBreakdownWindow, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", viBreakdownWindow, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        viBreakdownWindow:Hide()
    end)

    local rule = viBreakdownWindow:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", viBreakdownWindow, "TOPLEFT", 12, -122)
    rule:SetPoint("TOPRIGHT", viBreakdownWindow, "TOPRIGHT", -12, -122)
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
    scroll:SetPoint("TOPLEFT", viBreakdownWindow, "TOPLEFT", 16, -150)
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
        viBreakdownWindow._userMoved = true
        ApplyVIBreakdownLayout(viBreakdownWindow)
    end)
    viBreakdownWindow.resizeBtn = resizeBtn
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
    local plan = VIBreakdownPlan.Build(breakdown, (GAM.C and GAM.C.VENDOR_PRICES) or {}, {
        vendor = L["VI_SECTION_VENDOR"] or "Vendor Purchases",
        auction = L["VI_SECTION_AUCTION"] or "Auction House Purchases",
        craft = L["VI_SECTION_CRAFTING"] or "Crafting Order",
    })
    local orderedEntries = plan.rows
    win._breakdown = breakdown
    win._plan = plan
    win._stratID = breakdown.stratID
    win._patchTag = breakdown.patchTag
    win.titleFS:SetText(L["VI_BREAKDOWN_TITLE"] or "VI Breakdown")
    win.subtitleFS:SetText((breakdown.stratName or (L["VI_SELECTED_STRAT"] or "Selected Strategy"))
        .. " | "
        .. ((breakdown.chainActive and (L["VI_STATUS_ENABLED"] or "VI on")) or (L["VI_STATUS_DISABLED"] or "VI off")))

    local metricParts = {}
    if breakdown.totalCostFull then
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
    if breakdown.usedFallbackRows then
        win.summaryNoteFS:SetText(L["VI_SUMMARY_FALLBACK"] or "Showing the combined shopping view because branch-by-branch VI steps are not available for this strategy.")
    else
        win.summaryNoteFS:SetText(L["VI_SUMMARY_GROUPED"] or "Buy grouped materials first, then complete the crafting order from top to bottom.")
    end
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
            row.bg:SetColorTexture(0.08, 0.08, 0.08, 0.30)
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
            row.bg:SetColorTexture(0.10, 0.10, 0.10, (index % 2 == 1) and 0.55 or 0.28)
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

VIBreakdownWindow.Show = ShowVIBreakdownWindow
VIBreakdownWindow.Hide = HideVIBreakdownWindow
