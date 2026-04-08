-- GoldAdvisorMidnight/UI/MainWindowV2Detail.lua
-- Shared inline-detail builder/renderer for MainWindowV2.
-- Module: GAM.UI.MainWindowV2Detail

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local Detail = {}
GAM.UI.MainWindowV2Detail = Detail

local DEFAULT_GOLD = { 1.0, 0.82, 0.0 }
local DEFAULT_RULE = { 0.7, 0.57, 0.0, 0.7 }
local CRUSHING_WINDOW_W = 592
local CRUSHING_WINDOW_H = 262
local CRUSHING_WINDOW_MIN_W = 430
local CRUSHING_WINDOW_MIN_H = 220
local CRUSHING_ROW_H = 18
local CRUSHING_ROWS_TOP = 76
local CRUSHING_ROWS_BOTTOM_PAD = 16
local VI_WINDOW_W = 920
local VI_WINDOW_H = 420
local VI_WINDOW_MIN_W = 720
local VI_WINDOW_MIN_H = 280
local VI_ROW_H = 22

local function Noop()
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
    local text = string.format("%.1f", number):gsub("0+$", ""):gsub("%.$", "")
    return AddThousandsSeparators(text)
end

local function GetCommitButtonText(localizer)
    return "OK"
end

local function RefreshCommitButton(editBox)
    local button = editBox and editBox._gamCommitButton
    if not button then
        return
    end
    local committed = tostring(editBox._gamCommittedText or "")
    local current = tostring(editBox:GetText() or "")
    local keepVisible = editBox._gamCommitFromButton or editBox._gamCommitInProgress
    local shouldShow = editBox:IsShown() and current ~= committed and (editBox:HasFocus() or keepVisible)
    button:SetShown(shouldShow)
end

local function AttachTransientCommitButton(editBox, button, commitFn)
    if not (editBox and button and commitFn) then
        return
    end

    editBox._gamCommitButton = button
    editBox._gamCommittedText = tostring(editBox:GetText() or "")

    local function CommitCurrentValue(fromButton)
        local text = tostring(editBox:GetText() or "")
        editBox._gamCommitInProgress = true
        if fromButton then
            editBox._gamCommitFromButton = true
        end
        commitFn(text)
        editBox._gamCommittedText = tostring(editBox:GetText() or text)
        if editBox:HasFocus() then
            editBox:ClearFocus()
        end
        editBox._gamCommitInProgress = nil
        editBox._gamCommitFromButton = nil
        RefreshCommitButton(editBox)
    end

    button:SetScript("OnMouseDown", function()
        editBox._gamCommitFromButton = true
        RefreshCommitButton(editBox)
    end)
    button:SetScript("OnClick", function()
        CommitCurrentValue(true)
    end)
    button:SetScript("OnHide", function()
        editBox._gamCommitFromButton = nil
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        CommitCurrentValue(false)
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(self._gamCommittedText or "")
        self._gamCommitFromButton = nil
        self:ClearFocus()
        RefreshCommitButton(self)
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        RefreshCommitButton(self)
    end)
    editBox:SetScript("OnTextChanged", function(self)
        RefreshCommitButton(self)
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        if self._gamCommitFromButton or self._gamCommitInProgress
            or (self._gamCommitButton and MouseIsOver and MouseIsOver(self._gamCommitButton)) then
            self._gamCommitFromButton = self._gamCommitFromButton or true
            return
        end
        local committed = tostring(self._gamCommittedText or "")
        if tostring(self:GetText() or "") ~= committed then
            self:SetText(committed)
        end
        RefreshCommitButton(self)
    end)

    button:Hide()
end

local function GetPlaceholder(args)
    return args.placeholder or (args.rightPanel and args.rightPanel.placeholder) or nil
end

local function UpdateBodyAnchor(rpDetail)
    if not (rpDetail and rpDetail.bodyRoot and rpDetail.content) then
        return
    end

    local reservedHeight = rpDetail.notesReservedHeight or 16
    local bodyY = rpDetail.bodyBaseY or 0
    local noteHeight = 0
    if rpDetail.notesFS and rpDetail.notesFS:IsShown() then
        noteHeight = math.ceil(rpDetail.notesFS:GetStringHeight() or 0)
    end

    if noteHeight <= 0 then
        bodyY = bodyY + reservedHeight
    elseif noteHeight > reservedHeight then
        bodyY = bodyY - (noteHeight - reservedHeight)
    end

    rpDetail.bodyRoot:ClearAllPoints()
    rpDetail.bodyRoot:SetPoint("TOPLEFT", rpDetail.content, "TOPLEFT", 0, bodyY)
    rpDetail.bodyRoot:SetPoint("TOPRIGHT", rpDetail.content, "TOPRIGHT", 0, bodyY)
end

local crushingWindow
local crushingRows = {}
local viBreakdownWindow
local viBreakdownRows = {}

local function GetVisibleCrushingRowCount(win)
    local available = math.max(0, (win and win:GetHeight() or CRUSHING_WINDOW_H) - CRUSHING_ROWS_TOP - CRUSHING_ROWS_BOTTOM_PAD)
    return math.max(1, math.min(#crushingRows, math.floor(available / CRUSHING_ROW_H)))
end

local function ApplyCrushingWindowLayout(win)
    if not win then
        return
    end

    local width = math.max(CRUSHING_WINDOW_MIN_W, math.floor((win:GetWidth() or CRUSHING_WINDOW_W) + 0.5))
    local contentWidth = math.max(320, width - 32)
    local gap = 6
    local gemW = math.max(132, math.floor(contentWidth * 0.34))
    local priceW = math.max(62, math.floor(contentWidth * 0.14))
    local profitW = math.max(82, math.floor(contentWidth * 0.22))
    local roiW = math.max(48, math.floor(contentWidth * 0.11))
    local breakEvenW = math.max(68, contentWidth - gemW - priceW - profitW - roiW - (gap * 4))

    local gemX = 16
    local priceX = gemX + gemW + gap
    local profitX = priceX + priceW + gap
    local roiX = profitX + profitW + gap
    local breakEvenX = roiX + roiW + gap

    if win.subtitleFS then
        win.subtitleFS:SetWidth(width - 40)
    end

    if win.headerGemFS then
        win.headerGemFS:ClearAllPoints()
        win.headerGemFS:SetPoint("TOPLEFT", win, "TOPLEFT", gemX, -56)
        win.headerGemFS:SetWidth(gemW)
    end
    if win.headerPriceFS then
        win.headerPriceFS:ClearAllPoints()
        win.headerPriceFS:SetPoint("TOPLEFT", win, "TOPLEFT", priceX, -56)
        win.headerPriceFS:SetWidth(priceW)
    end
    if win.headerProfitFS then
        win.headerProfitFS:ClearAllPoints()
        win.headerProfitFS:SetPoint("TOPLEFT", win, "TOPLEFT", profitX, -56)
        win.headerProfitFS:SetWidth(profitW)
    end
    if win.headerROIFS then
        win.headerROIFS:ClearAllPoints()
        win.headerROIFS:SetPoint("TOPLEFT", win, "TOPLEFT", roiX, -56)
        win.headerROIFS:SetWidth(roiW)
    end
    if win.headerBreakEvenFS then
        win.headerBreakEvenFS:ClearAllPoints()
        win.headerBreakEvenFS:SetPoint("TOPLEFT", win, "TOPLEFT", breakEvenX, -56)
        win.headerBreakEvenFS:SetWidth(breakEvenW)
    end

    for i, row in ipairs(crushingRows) do
        row:SetSize(contentWidth, CRUSHING_ROW_H)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -CRUSHING_ROWS_TOP - ((i - 1) * CRUSHING_ROW_H))

        row.nameFS:ClearAllPoints()
        row.nameFS:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.nameFS:SetWidth(gemW - 8)

        row.priceFS:ClearAllPoints()
        row.priceFS:SetPoint("LEFT", row, "LEFT", priceX - gemX, 0)
        row.priceFS:SetWidth(priceW)

        row.profitFS:ClearAllPoints()
        row.profitFS:SetPoint("LEFT", row, "LEFT", profitX - gemX, 0)
        row.profitFS:SetWidth(profitW)

        row.roiFS:ClearAllPoints()
        row.roiFS:SetPoint("LEFT", row, "LEFT", roiX - gemX, 0)
        row.roiFS:SetWidth(roiW)

        row.breakEvenFS:ClearAllPoints()
        row.breakEvenFS:SetPoint("LEFT", row, "LEFT", breakEvenX - gemX, 0)
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

local function RenderCrushingAnalyzer(win, analyzer)
    if not (win and analyzer and analyzer.entries) then
        return nil
    end

    local selectedName = nil
    local visibleRows = GetVisibleCrushingRowCount(win)

    for i, row in ipairs(crushingRows) do
        local entry = analyzer.entries[i]
        if entry and i <= visibleRows then
            local display = GAM.Pricing.GetItemDisplayData(entry.itemID, entry.name)
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
                row.bg:SetColorTexture(0.18, 0.14, 0.04, 0.92)
                selectedName = entry.name
            else
                row.bg:SetColorTexture(0.10, 0.10, 0.10, (i % 2 == 1) and 0.55 or 0.28)
            end
            row:Show()
        else
            row:Hide()
        end
    end

    return selectedName
end

local function HideCrushingWindow()
    if crushingWindow then
        crushingWindow:Hide()
    end
end

local function FormatTraceCount(value)
    return (value == nil) and "—" or FormatQuantityValue(value)
end

local function CopyNumberPath(path)
    local out = {}
    for i, value in ipairs(path or {}) do
        out[i] = value
    end
    return out
end

local function BuildOrderedBreakdownEntries(breakdown)
    local ordered = {}
    local visited = {}

    local function Visit(index, path)
        local entry = breakdown and breakdown.entries and breakdown.entries[index]
        if not entry or visited[index] then
            return
        end
        visited[index] = true
        entry._displayStepLabel = table.concat(path or {}, ".")
        ordered[#ordered + 1] = entry
        for childPos, childIndex in ipairs(entry.childIndices or {}) do
            local childPath = CopyNumberPath(path)
            childPath[#childPath + 1] = childPos
            Visit(childIndex, childPath)
        end
    end

    for rootPos, rootIndex in ipairs((breakdown and breakdown.rootIndices) or {}) do
        Visit(rootIndex, { rootPos })
    end

    for index, entry in ipairs((breakdown and breakdown.entries) or {}) do
        if not visited[index] then
            entry._displayStepLabel = tostring(#ordered + 1)
            ordered[#ordered + 1] = entry
        end
    end

    return ordered
end

local function GetBreakdownActionText(entry)
    if not entry then
        return "Review"
    end
    if entry.excludeFromCost then
        return "Ignore"
    end
    if entry.kind == "craft" then
        return "Craft"
    end
    return "Get"
end

local function FormatBreakdownStep(entry)
    local stepLabel = entry and entry._displayStepLabel or "?"
    local action = GetBreakdownActionText(entry)
    local name = (entry and entry.name) or "Unknown"
    return string.format("%s %s %s", stepLabel, action, name)
end

local function BuildBreakdownUsedCostText(entry)
    if not entry then
        return "—"
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
    if entry.effectiveTotalCostFull then
        return GAM.Pricing.FormatPrice(entry.effectiveTotalCostFull)
    end
    if entry.effectiveMissingPrice then
        return "|cffff8800Missing|r"
    end
    return "—"
end

local function BuildBreakdownModeText(entry)
    if not entry then
        return "—"
    end
    if entry.excludeFromCost then
        return "|cff888888Excluded|r"
    end
    if entry.kind == "craft" then
        local parts = {}
        if entry.profileKey then
            parts[#parts + 1] = tostring(entry.profileKey)
        end
        if entry.directUnitPrice then
            parts[#parts + 1] = "AH " .. GAM.Pricing.FormatPrice(entry.directUnitPrice)
        elseif entry.directMissingPrice then
            parts[#parts + 1] = "AH missing"
        end
        return (#parts > 0) and table.concat(parts, " | ") or "Craft chain"
    end

    local mode = "Direct"
    if entry.stopReason == "vi_disabled" then
        mode = "VI off"
    elseif entry.stopReason == "skip_derivation" then
        mode = "Skip"
    elseif entry.stopReason == "invalid_output" then
        mode = "Invalid"
    end
    if entry.effectiveUnitPrice then
        if entry.directUnitPrice and entry.directUnitPrice ~= entry.effectiveUnitPrice then
            return mode .. " " .. GAM.Pricing.FormatPrice(entry.effectiveUnitPrice)
                .. " | AH " .. GAM.Pricing.FormatPrice(entry.directUnitPrice)
        end
        return mode .. " " .. GAM.Pricing.FormatPrice(entry.effectiveUnitPrice)
    end
    if entry.effectiveMissingPrice then
        return mode .. " missing"
    end
    return mode
end

local function ShowBreakdownTooltip(self)
    local entry = self and self._viEntry
    if not entry then
        return
    end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(FormatBreakdownStep(entry), 1, 1, 1)
    GameTooltip:AddLine("Row: branch step", 0.82, 0.82, 0.82)
    GameTooltip:AddLine("Header: merged total", 0.82, 0.82, 0.82)
    GameTooltip:AddLine(string.format("Need: %s", FormatTraceCount(entry.requiredRaw or entry.required or 0)), 1, 0.82, 0)
    if entry.kind == "craft" then
        GameTooltip:AddLine(string.format("Economic crafts: %s", FormatTraceCount(entry.craftsEconomic)), 1, 0.82, 0)
        GameTooltip:AddLine(string.format("Execution crafts: %s", FormatTraceCount(entry.craftsExecution)), 1, 0.82, 0)
        if entry.expectedOutputPerCraft then
            GameTooltip:AddLine(string.format("Expected output/craft: %.4f", entry.expectedOutputPerCraft), 1, 0.82, 0)
        end
        if entry.profileKey then
            GameTooltip:AddLine("Profile: " .. tostring(entry.profileKey), 1, 0.82, 0)
        end
        if entry.chainTotalCostFull and entry.chainTotalCostFull > 0 then
            GameTooltip:AddLine("Chain cost: " .. GAM.Pricing.FormatPrice(entry.chainTotalCostFull), 1, 0.82, 0)
        end
        if entry.directUnitPrice then
            GameTooltip:AddLine("Direct AH unit: " .. GAM.Pricing.FormatPrice(entry.directUnitPrice), 1, 0.82, 0)
        end
    else
        GameTooltip:AddLine(string.format("Have: %s", FormatTraceCount(entry.have or 0)), 1, 0.82, 0)
        GameTooltip:AddLine(string.format("Need to buy: %s", FormatTraceCount(entry.needToBuy or 0)), 1, 0.82, 0)
        if entry.effectiveUnitPrice then
            GameTooltip:AddLine("Used unit price: " .. GAM.Pricing.FormatPrice(entry.effectiveUnitPrice), 1, 0.82, 0)
        end
        if entry.effectiveTotalCostFull then
            GameTooltip:AddLine("Used full cost: " .. GAM.Pricing.FormatPrice(entry.effectiveTotalCostFull), 1, 0.82, 0)
        end
        if entry.directUnitPrice and entry.directUnitPrice ~= entry.effectiveUnitPrice then
            GameTooltip:AddLine("Direct AH unit: " .. GAM.Pricing.FormatPrice(entry.directUnitPrice), 1, 0.82, 0)
        end
    end
    if entry.excludeFromCost then
        GameTooltip:AddLine("This node is excluded from cost math.", 1, 0.82, 0, true)
    elseif entry.hasMissingPrice or entry.effectiveMissingPrice then
        GameTooltip:AddLine("Some pricing data is missing for this node or its children.", 1, 0.82, 0, true)
    end
    GameTooltip:Show()
end

local function HideBreakdownTooltip()
    GameTooltip:Hide()
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
    viBreakdownWindow:SetFrameStrata("DIALOG")
    viBreakdownWindow:SetToplevel(true)
    viBreakdownWindow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    viBreakdownWindow:SetBackdropColor(0, 0, 0, 1)
    viBreakdownWindow:Hide()

    local bgTex = viBreakdownWindow:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0, 0, 0, 1)

    local title = viBreakdownWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", viBreakdownWindow, "TOP", 0, -14)
    title:SetText("VI Breakdown")
    title:SetTextColor(DEFAULT_GOLD[1], DEFAULT_GOLD[2], DEFAULT_GOLD[3])
    viBreakdownWindow.titleFS = title

    local subtitle = viBreakdownWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetWidth(VI_WINDOW_W - 40)
    subtitle:SetJustifyH("CENTER")
    subtitle:SetTextColor(0.75, 0.72, 0.64, 1)
    viBreakdownWindow.subtitleFS = subtitle

    local summary = viBreakdownWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", viBreakdownWindow, "TOPLEFT", 18, -58)
    summary:SetPoint("TOPRIGHT", viBreakdownWindow, "TOPRIGHT", -18, -58)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(true)
    summary:SetTextColor(1.0, 0.82, 0.0, 1.0)
    viBreakdownWindow.summaryFS = summary

    local summaryNote = viBreakdownWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summaryNote:SetPoint("TOPLEFT", viBreakdownWindow, "TOPLEFT", 18, -72)
    summaryNote:SetPoint("TOPRIGHT", viBreakdownWindow, "TOPRIGHT", -18, -72)
    summaryNote:SetJustifyH("LEFT")
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
    rule:SetPoint("TOPLEFT", viBreakdownWindow, "TOPLEFT", 12, -92)
    rule:SetPoint("TOPRIGHT", viBreakdownWindow, "TOPRIGHT", -12, -92)
    rule:SetColorTexture(DEFAULT_RULE[1], DEFAULT_RULE[2], DEFAULT_RULE[3], 0.6)

    local function MakeHdr(text)
        local fs = viBreakdownWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        fs:SetTextColor(1.0, 0.84, 0.22, 1.0)
        return fs
    end

    viBreakdownWindow.headerStepFS = MakeHdr("Step / Action")
    viBreakdownWindow.headerNeedFS = MakeHdr("Need")
    viBreakdownWindow.headerEconomicFS = MakeHdr("Econ")
    viBreakdownWindow.headerExecutionFS = MakeHdr("Exec")
    viBreakdownWindow.headerUsedCostFS = MakeHdr("Used Cost")
    viBreakdownWindow.headerNoteFS = MakeHdr("How Priced")

    local scroll = CreateFrame("ScrollFrame", nil, viBreakdownWindow, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", viBreakdownWindow, "TOPLEFT", 16, -114)
    scroll:SetPoint("BOTTOMRIGHT", viBreakdownWindow, "BOTTOMRIGHT", -30, 18)
    viBreakdownWindow.scrollFrame = scroll

    local listHost = CreateFrame("Frame", nil, scroll)
    listHost:SetHeight(1)
    scroll:SetScrollChild(listHost)
    viBreakdownWindow.listHost = listHost

    listHost:EnableMouseWheel(true)
    listHost:SetScript("OnMouseWheel", function(_, delta)
        local cur = scroll:GetVerticalScroll()
        local max = scroll:GetVerticalScrollRange()
        scroll:SetVerticalScroll(math.max(0, math.min(max, cur - delta * (VI_ROW_H * 3))))
    end)

    viBreakdownWindow:SetScript("OnSizeChanged", function(self)
        local width = math.max(VI_WINDOW_MIN_W, math.floor((self:GetWidth() or VI_WINDOW_W) + 0.5))
        local height = math.max(VI_WINDOW_MIN_H, math.floor((self:GetHeight() or VI_WINDOW_H) + 0.5))
        if width ~= (self:GetWidth() or 0) or height ~= (self:GetHeight() or 0) then
            self:SetSize(width, height)
            return
        end

        local contentWidth = math.max(620, width - 58)
        local needW = 62
        local econW = 62
        local execW = 62
        local usedCostW = 120
        local noteW = math.max(150, math.floor(contentWidth * 0.20))
        local reservedWidth = needW + econW + execW + usedCostW + noteW + 28
        local stepW = math.max(180, contentWidth - reservedWidth)
        local xNeed = stepW + 8
        local xEconomic = xNeed + needW + 6
        local xExecution = xEconomic + econW + 6
        local xUsedCost = xExecution + execW + 6
        local xNote = xUsedCost + usedCostW + 6

        self.subtitleFS:SetWidth(width - 40)
        self.summaryFS:SetWidth(width - 36)
        self.summaryNoteFS:SetWidth(width - 36)
        self.headerStepFS:ClearAllPoints()
        self.headerStepFS:SetPoint("TOPLEFT", self, "TOPLEFT", 18, -100)
        self.headerStepFS:SetWidth(stepW)
        self.headerNeedFS:ClearAllPoints()
        self.headerNeedFS:SetPoint("TOPLEFT", self, "TOPLEFT", 18 + xNeed, -100)
        self.headerNeedFS:SetWidth(needW)
        self.headerEconomicFS:ClearAllPoints()
        self.headerEconomicFS:SetPoint("TOPLEFT", self, "TOPLEFT", 18 + xEconomic, -100)
        self.headerEconomicFS:SetWidth(econW)
        self.headerExecutionFS:ClearAllPoints()
        self.headerExecutionFS:SetPoint("TOPLEFT", self, "TOPLEFT", 18 + xExecution, -100)
        self.headerExecutionFS:SetWidth(execW)
        self.headerUsedCostFS:ClearAllPoints()
        self.headerUsedCostFS:SetPoint("TOPLEFT", self, "TOPLEFT", 18 + xUsedCost, -100)
        self.headerUsedCostFS:SetWidth(usedCostW)
        self.headerNoteFS:ClearAllPoints()
        self.headerNoteFS:SetPoint("TOPLEFT", self, "TOPLEFT", 18 + xNote, -100)
        self.headerNoteFS:SetWidth(noteW)

        self.listHost:SetWidth(contentWidth)
        for _, row in ipairs(viBreakdownRows) do
            row:SetWidth(contentWidth)
            row.stepFS:SetWidth(stepW - 8)
            row.needFS:ClearAllPoints()
            row.needFS:SetPoint("LEFT", row, "LEFT", xNeed, 0)
            row.needFS:SetWidth(needW)
            row.economicFS:ClearAllPoints()
            row.economicFS:SetPoint("LEFT", row, "LEFT", xEconomic, 0)
            row.economicFS:SetWidth(econW)
            row.executionFS:ClearAllPoints()
            row.executionFS:SetPoint("LEFT", row, "LEFT", xExecution, 0)
            row.executionFS:SetWidth(execW)
            row.usedCostFS:ClearAllPoints()
            row.usedCostFS:SetPoint("LEFT", row, "LEFT", xUsedCost, 0)
            row.usedCostFS:SetWidth(usedCostW)
            row.noteFS:ClearAllPoints()
            row.noteFS:SetPoint("LEFT", row, "LEFT", xNote, 0)
            row.noteFS:SetWidth(noteW - 6)
        end
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
        viBreakdownWindow:GetScript("OnSizeChanged")(viBreakdownWindow)
    end)
    viBreakdownWindow.resizeBtn = resizeBtn

    return viBreakdownWindow
end

local function EnsureVIBreakdownRow(index)
    if viBreakdownRows[index] then
        return viBreakdownRows[index]
    end

    local win = EnsureVIBreakdownWindow()
    local row = CreateFrame("Button", nil, win.listHost)
    row:SetHeight(VI_ROW_H)
    row:SetPoint("TOPLEFT", win.listHost, "TOPLEFT", 0, -((index - 1) * VI_ROW_H))

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 1)
    bg:SetColorTexture(0.10, 0.10, 0.10, (index % 2 == 1) and 0.55 or 0.28)

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
    row.stepFS = stepFS
    row.needFS = needFS
    row.economicFS = economicFS
    row.executionFS = executionFS
    row.usedCostFS = usedCostFS
    row.noteFS = noteFS
    row:SetScript("OnEnter", ShowBreakdownTooltip)
    row:SetScript("OnLeave", HideBreakdownTooltip)
    viBreakdownRows[index] = row

    win:GetScript("OnSizeChanged")(win)
    return row
end

local function RenderVIBreakdownWindow(win, breakdown)
    if not (win and breakdown and breakdown.entries) then
        return
    end

    local orderedEntries = BuildOrderedBreakdownEntries(breakdown)
    win._breakdown = breakdown
    win._stratID = breakdown.stratID
    win._patchTag = breakdown.patchTag
    win.titleFS:SetText("VI Breakdown")
    win.subtitleFS:SetText((breakdown.stratName or "Selected Strategy") .. (breakdown.chainActive and " | VI enabled" or " | VI disabled"))

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
    win.summaryNoteFS:SetText("Header = merged total   Rows = branch steps")

    for index, entry in ipairs(orderedEntries) do
        local row = EnsureVIBreakdownRow(index)
        row._viEntry = entry
        row.stepFS:SetText(FormatBreakdownStep(entry))
        row.needFS:SetText(FormatTraceCount(entry.requiredRaw or entry.required))
        row.economicFS:SetText((entry.kind == "craft") and FormatTraceCount(entry.craftsEconomic) or "—")
        row.executionFS:SetText((entry.kind == "craft") and FormatTraceCount(entry.craftsExecution) or "—")
        row.usedCostFS:SetText(BuildBreakdownUsedCostText(entry))
        row.noteFS:SetText(BuildBreakdownModeText(entry))
        if entry.excludeFromCost then
            row.stepFS:SetTextColor(0.62, 0.62, 0.62, 1)
            row.usedCostFS:SetTextColor(0.62, 0.62, 0.62, 1)
            row.noteFS:SetTextColor(0.62, 0.62, 0.62, 1)
            row.bg:SetColorTexture(0.08, 0.08, 0.08, 0.28)
        elseif entry.kind == "craft" then
            row.stepFS:SetTextColor(1.0, 0.84, 0.22, 1.0)
            row.usedCostFS:SetTextColor(1.0, 0.84, 0.22, 1.0)
            row.noteFS:SetTextColor(0.86, 0.80, 0.60, 1.0)
            if entry.depth == 0 then
                row.bg:SetColorTexture(0.18, 0.14, 0.04, 0.62)
            else
                row.bg:SetColorTexture(0.12, 0.10, 0.04, (index % 2 == 1) and 0.52 or 0.34)
            end
        else
            row.stepFS:SetTextColor(0.95, 0.95, 0.95, 1)
            row.usedCostFS:SetTextColor(0.92, 0.92, 0.92, 1)
            row.noteFS:SetTextColor(0.78, 0.78, 0.78, 1)
            row.bg:SetColorTexture(0.10, 0.10, 0.10, (index % 2 == 1) and 0.55 or 0.28)
        end
        row.needFS:SetTextColor(0.92, 0.92, 0.92, 1)
        row.economicFS:SetTextColor(0.88, 0.88, 0.88, 1)
        row.executionFS:SetTextColor(0.76, 0.92, 0.76, 1)
        row:Show()
    end

    for index = #orderedEntries + 1, #viBreakdownRows do
        viBreakdownRows[index]._viEntry = nil
        viBreakdownRows[index]:Hide()
    end

    win.listHost:SetHeight(math.max(1, #orderedEntries * VI_ROW_H))
    win.scrollFrame:SetVerticalScroll(0)
    win:GetScript("OnSizeChanged")(win)
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
    if not (strat and GAM.Pricing and GAM.Pricing.GetVIBreakdownData) then
        return
    end
    local win = EnsureVIBreakdownWindow()
    local breakdown = GAM.Pricing.GetVIBreakdownData(strat, patchTag, metrics)
    if not breakdown then
        return
    end
    RenderVIBreakdownWindow(win, breakdown)
    win:Show()
end

Detail.ShowBreakdownWindow = ShowVIBreakdownWindow
Detail.HideBreakdownWindow = HideVIBreakdownWindow

local function EnsureCrushingWindow()
    if crushingWindow then
        return crushingWindow
    end

    crushingWindow = CreateFrame("Frame", "GAMCrushingAnalyzer", UIParent, "BackdropTemplate")
    crushingWindow:SetSize(CRUSHING_WINDOW_W, CRUSHING_WINDOW_H)
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
    crushingWindow:SetFrameStrata("DIALOG")
    crushingWindow:SetToplevel(true)
    crushingWindow:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    crushingWindow:SetBackdropColor(0, 0, 0, 1)
    crushingWindow:Hide()
    crushingWindow:SetScript("OnSizeChanged", function(self)
        ClampCrushingWindowSize(self)
        if not self.subtitleFS then
            return
        end
        ApplyCrushingWindowLayout(self)
        if self._lastAnalyzer then
            local selectedName = RenderCrushingAnalyzer(self, self._lastAnalyzer)
            local craftsText = nil
            if self._lastAnalyzer.crafts and self._lastAnalyzer.crafts > 0 then
                craftsText = tostring(math.floor((self._lastAnalyzer.crafts or 0) + 0.5))
            end
            if selectedName then
                self.subtitleFS:SetText(craftsText and ("Active auto-pick: " .. selectedName .. " | Crafts: " .. craftsText)
                    or ("Active auto-pick: " .. selectedName))
            else
                self.subtitleFS:SetText(craftsText and ("Current rank-policy gem comparison | Crafts: " .. craftsText)
                    or "Current rank-policy gem comparison")
            end
        end
    end)

    local bgTex = crushingWindow:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0, 0, 0, 1)

    local title = crushingWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", crushingWindow, "TOP", 0, -14)
    title:SetText("Crushing Analyzer")
    title:SetTextColor(DEFAULT_GOLD[1], DEFAULT_GOLD[2], DEFAULT_GOLD[3])
    crushingWindow.titleFS = title

    local subtitle = crushingWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetWidth(CRUSHING_WINDOW_W - 40)
    subtitle:SetJustifyH("CENTER")
    subtitle:SetTextColor(0.75, 0.72, 0.64, 1)
    crushingWindow.subtitleFS = subtitle

    local closeBtn = CreateFrame("Button", nil, crushingWindow, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", crushingWindow, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        crushingWindow:Hide()
    end)

    local rule = crushingWindow:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", crushingWindow, "TOPLEFT", 12, -44)
    rule:SetPoint("TOPRIGHT", crushingWindow, "TOPRIGHT", -12, -44)
    rule:SetColorTexture(DEFAULT_RULE[1], DEFAULT_RULE[2], DEFAULT_RULE[3], 0.6)

    local function MakeHdr(text, x, w, justify)
        local fs = crushingWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", crushingWindow, "TOPLEFT", x, -56)
        fs:SetWidth(w)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetText(text)
        fs:SetTextColor(1.0, 0.84, 0.22, 1.0)
        return fs
    end

    crushingWindow.headerGemFS = MakeHdr("Gem", 16, 132, "LEFT")
    crushingWindow.headerPriceFS = MakeHdr("Price", 150, 62, "LEFT")
    crushingWindow.headerProfitFS = MakeHdr("Profit", 214, 82, "LEFT")
    crushingWindow.headerROIFS = MakeHdr("ROI", 298, 52, "LEFT")
    crushingWindow.headerBreakEvenFS = MakeHdr("Break-even", 352, 62, "LEFT")

    for i = 1, 10 do
        local row = CreateFrame("Frame", nil, crushingWindow)
        row:SetSize(CRUSHING_WINDOW_W - 32, CRUSHING_ROW_H)
        row:SetPoint("TOPLEFT", crushingWindow, "TOPLEFT", 16, -CRUSHING_ROWS_TOP - ((i - 1) * CRUSHING_ROW_H))

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.10, 0.10, 0.10, (i % 2 == 1) and 0.55 or 0.28)

        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFS:SetPoint("LEFT", row, "LEFT", 4, 0)
        nameFS:SetWidth(128)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)

        local priceFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        priceFS:SetPoint("LEFT", row, "LEFT", 138, 0)
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
    win:ClearAllPoints()
    if anchorRight + 12 + CRUSHING_WINDOW_W <= screenW then
        win:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 12, 0)
    else
        win:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -12, 0)
    end
end

local function RefreshCrushingWindow(anchor, strat, patchTag, metrics)
    if not (strat and GAM.Pricing and GAM.Pricing.GetCrushingAnalyzerData) then
        HideCrushingWindow()
        return
    end

    local analyzer = GAM.Pricing.GetCrushingAnalyzerData(strat, patchTag, metrics)
    if not (analyzer and analyzer.entries and #analyzer.entries > 0) then
        HideCrushingWindow()
        return
    end

    local win = EnsureCrushingWindow()
    PositionCrushingWindow(anchor)
    win._lastAnalyzer = analyzer
    local selectedName = RenderCrushingAnalyzer(win, analyzer)

    local craftsText = nil
    if analyzer.crafts and analyzer.crafts > 0 then
        craftsText = tostring(math.floor((analyzer.crafts or 0) + 0.5))
    end
    if selectedName then
        win.subtitleFS:SetText(craftsText and ("Active auto-pick: " .. selectedName .. " | Crafts: " .. craftsText)
            or ("Active auto-pick: " .. selectedName))
    else
        win.subtitleFS:SetText(craftsText and ("Current rank-policy gem comparison | Crafts: " .. craftsText)
            or "Current rank-policy gem comparison")
    end
    win:Show()
end

function Detail.Hide(args)
    local rpDetail = args.rpDetail or {}
    local placeholder = GetPlaceholder(args)

    if placeholder then
        placeholder:Show()
    end
    if rpDetail.root then
        rpDetail.root:Hide()
    end
    if rpDetail.btnScanStrat then
        rpDetail.btnScanStrat:Disable()
        rpDetail.btnScanStrat:SetAlpha(0.45)
    end
    if rpDetail.btnVIBreakdown then
        rpDetail.btnVIBreakdown:Disable()
        rpDetail.btnVIBreakdown:SetAlpha(0.45)
    end
    if args.selectedScanBtn then
        args.selectedScanBtn:Disable()
        args.selectedScanBtn:SetAlpha(0.45)
    end
    if args.selectedCraftSimBtn then
        args.selectedCraftSimBtn:Disable()
    end
    if args.selectedVIBreakdownBtn then
        args.selectedVIBreakdownBtn:Disable()
    end
    if args.selectedShoppingBtn then
        args.selectedShoppingBtn:Disable()
    end
    HideCrushingWindow()
    HideVIBreakdownWindow()
    if args.onAfterHide then
        args.onAfterHide()
    end
end

function Detail.Render(args)
    local rpDetail = args.rpDetail or {}
    local strat = args.strat
    if not rpDetail.root or not strat then
        return args.metrics
    end

    local patchTag = args.patchTag or GAM.C.DEFAULT_PATCH
    local L = args.localizer or GAM.L
    local placeholder = GetPlaceholder(args)
    local metrics = args.metrics
    local bindItemRow = args.bindItemRow or Noop
    local getItemDisplayData = args.getItemDisplayData or function(_, name)
        return { displayText = name or "" }
    end
    local isCompactMode = args.isCompactMode and true or false
    local formatPrice = args.formatPrice or function(value)
        return tostring(value)
    end
    local rowHeight = args.rowHeight or 22

    rpDetail.metrics = metrics

    if rpDetail.craftsEB and not rpDetail.craftsEB:HasFocus() then
        local craftsVal = (metrics and metrics.crafts) and math.floor(metrics.crafts + 0.5) or 1
        local craftsText = tostring(craftsVal)
        rpDetail.craftsEB:SetText(craftsText)
        rpDetail.craftsEB._gamCommittedText = craftsText
        RefreshCommitButton(rpDetail.craftsEB)
    end

    if placeholder then
        placeholder:Hide()
    end

    rpDetail.nameFS:SetText(strat.stratName)
    rpDetail.profFS:SetText(strat.profession)
    if strat.notes and strat.notes ~= "" then
        rpDetail.notesFS:SetText(strat.notes)
        rpDetail.notesFS:Show()
    else
        rpDetail.notesFS:Hide()
        rpDetail.notesFS:SetText("")
    end
    UpdateBodyAnchor(rpDetail)

    local dash = "|cff888888—|r"
    rpDetail.metCostFS:SetText(
        (metrics and metrics.totalCostFull) and formatPrice(metrics.totalCostFull) or dash)
    if rpDetail.metBuyNowFS then
        rpDetail.metBuyNowFS:SetText(
            (metrics and metrics.totalCostToBuy) and formatPrice(metrics.totalCostToBuy) or dash)
    end
    rpDetail.metRevenueFS:SetText(
        (metrics and metrics.netRevenue) and formatPrice(metrics.netRevenue) or dash)
    if metrics and metrics.profit then
        local color = metrics.profit >= 0 and "|cff55ff55" or "|cffff5555"
        rpDetail.metProfitFS:SetText(color .. formatPrice(metrics.profit) .. "|r")
    else
        rpDetail.metProfitFS:SetText(dash)
    end
    if metrics and metrics.roi then
        local color = metrics.roi >= 0 and "|cff55ff55" or "|cffff5555"
        rpDetail.metROIFS:SetText(color .. string.format("%.2f%%", metrics.roi) .. "|r")
    else
        rpDetail.metROIFS:SetText(dash)
    end
    rpDetail.metBreakevenFS:SetText(
        (metrics and metrics.breakEvenSell) and formatPrice(metrics.breakEvenSell) or dash)

    if metrics and metrics.missingPrices and #metrics.missingPrices > 0 then
        rpDetail.missingFS:SetText((L and L["MISSING_PRICES"] or "Missing prices") .. ": " .. table.concat(metrics.missingPrices, ", "))
        rpDetail.missingFS:Show()
    else
        rpDetail.missingFS:Hide()
        rpDetail.missingFS:SetText("")
    end

    local reagentMetrics = metrics and metrics.reagents or {}
    for i, row in ipairs(rpDetail.reagentRows or {}) do
        local reagentMetric = reagentMetrics[i]
        if reagentMetric then
            local display = getItemDisplayData(reagentMetric.itemID, reagentMetric.name)
            row.nameFS:SetText(display.displayText)
            bindItemRow(row, display)
            row.qtyEB:Hide()
            row.qtyFS:Show()
            row.qtyFS:SetText(FormatQuantityValue(reagentMetric.required or 0))
            row.needFS:SetText(FormatQuantityValue(reagentMetric.needToBuy or 0))
            row.priceFS:SetText(reagentMetric.unitPrice and formatPrice(reagentMetric.unitPrice) or "|cffff8800—|r")
            row._metricTooltip = {
                kind = "reagent",
                unitPrice = reagentMetric.unitPrice,
                required = reagentMetric.required,
                needToBuy = reagentMetric.needToBuy,
                totalCost = reagentMetric.totalCost,
                totalCostFull = reagentMetric.totalCostFull,
            }
            row:Show()
        else
            row:Hide()
            bindItemRow(row, nil)
            row._metricTooltip = nil
            row.qtyEB:Hide()
        end
    end

    local outputItems = {}
    if metrics and metrics.outputs and #metrics.outputs > 0 then
        for _, outputItem in ipairs(metrics.outputs) do
            outputItems[#outputItems + 1] = outputItem
        end
    elseif metrics and metrics.output then
        outputItems[1] = metrics.output
    end
    for i, row in ipairs(rpDetail.outputRows or {}) do
        local outputItem = outputItems[i]
        if outputItem then
            local display = getItemDisplayData(outputItem.itemID, outputItem.name)
            row.nameFS:SetText(display.displayText)
            bindItemRow(row, display)
            row.qtyFS:SetText(outputItem.expectedQty and FormatQuantityValue(outputItem.expectedQty) or "—")
            row.priceFS:SetText(
                outputItem.netRevenue and formatPrice(outputItem.netRevenue)
                or (outputItem.unitPrice and formatPrice(outputItem.unitPrice) or "|cffff8800—|r")
            )
            row._metricTooltip = {
                kind = "output",
                unitPrice = outputItem.unitPrice,
                expectedQty = outputItem.expectedQty,
                expectedQtyRaw = outputItem.expectedQtyRaw,
                netRevenue = outputItem.netRevenue,
            }
            row:Show()
        else
            bindItemRow(row, nil)
            row._metricTooltip = nil
            row:Hide()
        end
    end

    local isUser = strat._isUser == true
    if rpDetail.btnEdit then
        rpDetail.btnEdit:SetShown(isUser)
    end
    if rpDetail.btnDelete then
        rpDetail.btnDelete:SetShown(isUser)
    end

    rpDetail.currentStrat = strat
    rpDetail.currentPatch = patchTag
    if args.refreshCompactButtonEnabledState then
        args.refreshCompactButtonEnabledState()
    end
    if rpDetail.btnScanStrat then
        rpDetail.btnScanStrat:SetShown(isCompactMode)
        if isCompactMode then
            rpDetail.btnScanStrat:Enable()
            rpDetail.btnScanStrat:SetAlpha(1)
        else
            rpDetail.btnScanStrat:Disable()
            rpDetail.btnScanStrat:SetAlpha(0.45)
        end
    end
    if args.selectedScanBtn then
        args.selectedScanBtn:Enable()
        args.selectedScanBtn:SetAlpha(1)
    end
    if args.selectedCraftSimBtn then
        args.selectedCraftSimBtn:Enable()
    end
    if args.selectedVIBreakdownBtn then
        args.selectedVIBreakdownBtn:Enable()
    end
    if args.selectedShoppingBtn then
        args.selectedShoppingBtn:Enable()
    end
    if rpDetail.reagentScrollFrame then
        rpDetail.reagentScrollFrame:SetVerticalScroll(0)
    end
    if rpDetail.outputScrollFrame then
        rpDetail.outputScrollFrame:SetVerticalScroll(0)
    end
    if rpDetail.reagentListHost then
        rpDetail.reagentListHost:SetHeight(math.max(1, #reagentMetrics * rowHeight))
    end
    if rpDetail.outputListHost then
        rpDetail.outputListHost:SetHeight(math.max(1, #outputItems * rowHeight))
    end
    rpDetail.root:Show()
    if strat.id == "jewelcrafting__crushing__midnight_1" then
        RefreshCrushingWindow(rpDetail.root, strat, patchTag, metrics)
    else
        HideCrushingWindow()
    end
    if args.onAfterRender then
        args.onAfterRender(strat, patchTag, metrics, reagentMetrics, outputItems)
    end
    return metrics
end

function Detail.Build(args)
    local panel = args.panel
    local rpDetail = args.rpDetail or {}
    local themeRefs = args.themeRefs or {}
    local L = args.localizer or GAM.L
    local gold = (args.colors and args.colors.gold) or DEFAULT_GOLD
    local rule = (args.colors and args.colors.rule) or DEFAULT_RULE
    local layoutMode = args.layoutMode or "classic"
    local bodyTextColor = args.bodyTextColor or { 0.85, 0.82, 0.76, 1.0 }
    local mutedTextColor = args.mutedTextColor or bodyTextColor
    local rowHeight = args.rowHeight or 22
    local rightPanelWidth = args.rightPanelWidth or 320
    local padding = args.padding or 12
    local actionHeight = args.actionHeight or 58
    local applyFontSize = args.applyFontSize or Noop
    local applyTextShadow = args.applyTextShadow or Noop
    local flattenSections = args.flattenSections and true or false
    local createShell = args.createShell or function(parent)
        return parent, parent
    end
    local attachButtonTooltip = args.attachButtonTooltip or Noop
    local itemRowClick = args.itemRowClick or Noop
    local itemRowEnter = args.itemRowEnter or Noop
    local itemRowLeave = args.itemRowLeave or Noop
    local onCommitCrafts = args.onCommitCrafts or Noop
    local onCommitInputQty = args.onCommitInputQty or Noop
    local onScanSelected = args.onScanSelected or Noop
    local onPushCraftSim = args.onPushCraftSim or Noop
    local onToggleShopping = args.onToggleShopping or Noop
    local onShowBreakdown = args.onShowBreakdown or Noop
    local onEditSelected = args.onEditSelected or Noop
    local onDeleteSelected = args.onDeleteSelected or Noop

    local usableWidth = rightPanelWidth - padding * 2
    local softInk = layoutMode == "soft"
    local smallHeaderColor = softInk and bodyTextColor or gold
    local metricLabelColor = softInk and bodyTextColor or { 1.0, 0.82, 0.0, 1.0 }
    local metricValueColor = softInk and bodyTextColor or { 1.0, 1.0, 1.0, 1.0 }
    local columnHeaderColor = softInk and mutedTextColor or { 1.0, 0.84, 0.22, 1.0 }

    local root = CreateFrame("Frame", nil, panel)
    root:SetAllPoints(panel)
    root:Hide()
    rpDetail.root = root

    local titleFS = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOP", root, "TOP", 0, -12)
    titleFS:SetText((L and L["DETAIL_TITLE"]) or "Strategy Detail")
    titleFS:SetTextColor(gold[1], gold[2], gold[3])
    applyFontSize(titleFS, 13)
    applyTextShadow(titleFS)

    local topRule = root:CreateTexture(nil, "ARTWORK")
    topRule:SetHeight(1)
    topRule:SetPoint("TOPLEFT", root, "TOPLEFT", padding, -38)
    topRule:SetPoint("TOPRIGHT", root, "TOPRIGHT", -padding, -38)
    topRule:SetColorTexture(rule[1], rule[2], rule[3], 0.6)

    local content = CreateFrame("Frame", nil, root)
    content:SetPoint("TOPLEFT", root, "TOPLEFT", padding, -44)
    content:SetPoint("TOPRIGHT", root, "TOPRIGHT", -padding, -44)
    content:SetPoint("BOTTOM", root, "BOTTOM", 0, actionHeight + 6)
    rpDetail.content = content

    local y = -padding

    local nameFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    nameFS:SetWidth(usableWidth)
    nameFS:SetJustifyH("LEFT")
    if softInk then
        nameFS:SetTextColor(bodyTextColor[1], bodyTextColor[2], bodyTextColor[3], bodyTextColor[4] or 1)
    else
        nameFS:SetTextColor(gold[1], gold[2], gold[3])
    end
    nameFS:SetWordWrap(true)
    applyFontSize(nameFS, 12)
    applyTextShadow(nameFS)
    rpDetail.nameFS = nameFS
    y = y - 34

    local profFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    profFS:SetWidth(usableWidth)
    profFS:SetTextColor(mutedTextColor[1], mutedTextColor[2], mutedTextColor[3], mutedTextColor[4] or 1)
    applyFontSize(profFS, 10)
    applyTextShadow(profFS, 0.75)
    rpDetail.profFS = profFS
    y = y - 16

    local notesFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    notesFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    notesFS:SetWidth(usableWidth)
    notesFS:SetTextColor(mutedTextColor[1], mutedTextColor[2], mutedTextColor[3], mutedTextColor[4] or 1)
    notesFS:SetJustifyH("LEFT")
    notesFS:SetJustifyV("TOP")
    notesFS:SetWordWrap(true)
    applyFontSize(notesFS, 10)
    applyTextShadow(notesFS, 0.75)
    rpDetail.notesFS = notesFS
    rpDetail.notesReservedHeight = 16
    y = y - rpDetail.notesReservedHeight

    local bodyRoot = CreateFrame("Frame", nil, content)
    bodyRoot:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    bodyRoot:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    bodyRoot:SetHeight(1)
    rpDetail.bodyRoot = bodyRoot
    rpDetail.bodyBaseY = y
    y = 0

    local function MakeRule(yOff, alpha)
        local ruleTexture = bodyRoot:CreateTexture(nil, "ARTWORK")
        ruleTexture:SetHeight(1)
        ruleTexture:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, yOff)
        ruleTexture:SetPoint("TOPRIGHT", bodyRoot, "TOPRIGHT", 0, yOff)
        ruleTexture:SetColorTexture(rule[1], rule[2], rule[3], alpha or rule[4] or 0.7)
        return ruleTexture
    end

    MakeRule(y)
    y = y - 6

    local labelWidth = 100
    local function MakeMetricRow(label, yOff)
        local labelFS = bodyRoot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelFS:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, yOff)
        labelFS:SetWidth(labelWidth)
        labelFS:SetText(label)
        labelFS:SetTextColor(metricLabelColor[1], metricLabelColor[2], metricLabelColor[3], metricLabelColor[4] or 1)
        applyFontSize(labelFS, 11)
        applyTextShadow(labelFS)

        local valueFS = bodyRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        valueFS:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", labelWidth + 6, yOff)
        valueFS:SetWidth(usableWidth - labelWidth - 6)
        valueFS:SetJustifyH("LEFT")
        valueFS:SetTextColor(metricValueColor[1], metricValueColor[2], metricValueColor[3], metricValueColor[4] or 1)
        applyFontSize(valueFS, 11)
        applyTextShadow(valueFS)
        return valueFS, yOff - 18
    end

    local function MakeMetricTooltip(yOff, titleKey, bodyKey)
        local anchor = CreateFrame("Button", nil, bodyRoot)
        anchor:SetSize(usableWidth, 18)
        anchor:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, yOff)
        anchor:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText((L and L[titleKey]) or titleKey, 1, 1, 1)
            GameTooltip:AddLine((L and L[bodyKey]) or bodyKey, 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        anchor:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    local yCost = y
    rpDetail.metCostFS, y = MakeMetricRow(L and L["LBL_COST"] or "Cost:", y)
    MakeMetricTooltip(yCost, "TT_LBL_COST_TITLE", "TT_LBL_COST_BODY")

    local yBuyNow = y
    rpDetail.metBuyNowFS, y = MakeMetricRow(L and L["LBL_BUY_NOW_COST"] or "Buy Now Cost:", y)
    MakeMetricTooltip(yBuyNow, "TT_LBL_BUY_NOW_COST_TITLE", "TT_LBL_BUY_NOW_COST_BODY")

    local yRevenue = y
    rpDetail.metRevenueFS, y = MakeMetricRow(L and L["LBL_REVENUE"] or "Revenue:", y)
    MakeMetricTooltip(yRevenue, "TT_LBL_REVENUE_TITLE", "TT_LBL_REVENUE_BODY")
    MakeRule(y, 0.4)
    y = y - 4

    local yProfit = y
    rpDetail.metProfitFS, y = MakeMetricRow(L and L["LBL_PROFIT"] or "Profit:", y)
    MakeMetricTooltip(yProfit, "TT_LBL_PROFIT_TITLE", "TT_LBL_PROFIT_BODY")

    local yROI = y
    rpDetail.metROIFS, y = MakeMetricRow(L and L["LBL_ROI"] or "ROI:", y)
    MakeMetricTooltip(yROI, "TT_LBL_ROI_TITLE", "TT_LBL_ROI_BODY")

    local yBreakeven = y
    rpDetail.metBreakevenFS, y = MakeMetricRow(L and L["LBL_BREAKEVEN"] or "Break-even:", y)
    MakeMetricTooltip(yBreakeven, "TT_LBL_BREAKEVEN_TITLE", "TT_LBL_BREAKEVEN_BODY")

    local missingFS = bodyRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    missingFS:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, y)
    missingFS:SetWidth(usableWidth)
    missingFS:SetJustifyH("LEFT")
    missingFS:SetTextColor(1.0, 0.75, 0.2, 1.0)
    missingFS:SetWordWrap(true)
    applyFontSize(missingFS, 10)
    applyTextShadow(missingFS)
    missingFS:Hide()
    rpDetail.missingFS = missingFS
    y = y - 18

    local reagHdr = bodyRoot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reagHdr:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, y)
    reagHdr:SetText((L and L["DETAIL_INPUT_HDR"]) or "Input Items")
    reagHdr:SetTextColor(smallHeaderColor[1], smallHeaderColor[2], smallHeaderColor[3], smallHeaderColor[4] or 1)
    applyFontSize(reagHdr, 12)
    applyTextShadow(reagHdr)

    local craftsEB = CreateFrame("EditBox", nil, bodyRoot, "InputBoxTemplate")
    craftsEB:SetSize(52, 18)
    craftsEB:SetAutoFocus(false)
    craftsEB:SetNumeric(true)
    rpDetail.craftsEB = craftsEB

    local craftsOKBtn = CreateFrame("Button", nil, bodyRoot, "UIPanelButtonTemplate")
    craftsOKBtn:SetSize(28, 18)
    craftsOKBtn:SetPoint("TOPRIGHT", bodyRoot, "TOPRIGHT", 0, y + 1)
    craftsOKBtn:SetText(GetCommitButtonText(L))
    craftsOKBtn:Hide()
    rpDetail.craftsOKBtn = craftsOKBtn

    craftsEB:SetPoint("RIGHT", craftsOKBtn, "LEFT", -4, 0)
    AttachTransientCommitButton(craftsEB, craftsOKBtn, onCommitCrafts)

    local craftsLabel = bodyRoot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    craftsLabel:SetPoint("RIGHT", craftsEB, "LEFT", -4, 0)
    craftsLabel:SetText((L and L["V2_CRAFTS_LABEL"]) or "Crafts:")
    craftsLabel:SetTextColor(smallHeaderColor[1], smallHeaderColor[2], smallHeaderColor[3], smallHeaderColor[4] or 1)
    applyFontSize(craftsLabel, 12)
    applyTextShadow(craftsLabel)
    y = y - 18

    local detailInnerWidth = usableWidth - 18
    local reagentNameW, reagentQtyW, reagentNeedW = 140, 48, 48
    local reagentPriceW = detailInnerWidth - reagentNameW - reagentQtyW - reagentNeedW
    local reagentSectionHeight = 136
    local outputSectionHeight = 118

    local function MakeSmallColHdr(parent, text, xOff, width, yOff, justify)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, yOff)
        fs:SetWidth(width)
        fs:SetText(text)
        fs:SetTextColor(columnHeaderColor[1], columnHeaderColor[2], columnHeaderColor[3], columnHeaderColor[4] or 1)
        fs:SetJustifyH(justify or "LEFT")
        applyFontSize(fs, 10)
        applyTextShadow(fs)
        return fs
    end

    local reagentShell, reagentSection = nil, bodyRoot
    local reagentScrollTop = -22
    local reagentScrollBottom = 8
    local reagentColumnY = -8
    local reagentColumnX = flattenSections and 0 or 8
    if flattenSections then
        reagentSection = CreateFrame("Frame", nil, bodyRoot)
        reagentSection:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, y)
        reagentSection:SetPoint("TOPRIGHT", bodyRoot, "TOPRIGHT", 0, y)
        reagentSection:SetHeight(reagentSectionHeight)
        MakeRule(y - 2, 0.22)
        rpDetail.reagentHeaderBg = nil
    else
        reagentShell, reagentSection = createShell(bodyRoot, "section", { left = 4, right = 4, top = 4, bottom = 4 })
        reagentShell:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, y)
        reagentShell:SetPoint("TOPRIGHT", bodyRoot, "TOPRIGHT", 0, y)
        reagentShell:SetHeight(reagentSectionHeight)

        local reagentHeaderBg = reagentSection:CreateTexture(nil, "ARTWORK")
        reagentHeaderBg:SetPoint("TOPLEFT", reagentSection, "TOPLEFT", 1, -1)
        reagentHeaderBg:SetPoint("TOPRIGHT", reagentSection, "TOPRIGHT", -1, -1)
        reagentHeaderBg:SetHeight(18)
        reagentHeaderBg:SetColorTexture(0.12, 0.10, 0.03, 0.9)
        rpDetail.reagentHeaderBg = reagentHeaderBg
    end
    rpDetail.reagentSection = reagentSection

    MakeSmallColHdr(reagentSection, (L and L["COL_ITEM"]) or "Item", reagentColumnX, reagentNameW, reagentColumnY)
    MakeSmallColHdr(reagentSection, (L and L["V2_COL_TOTAL"]) or "Total", reagentColumnX + reagentNameW, reagentQtyW, reagentColumnY, "CENTER")
    MakeSmallColHdr(reagentSection, (L and L["V2_COL_NEED"]) or "Need", reagentColumnX + reagentNameW + reagentQtyW, reagentNeedW, reagentColumnY, "CENTER")
    MakeSmallColHdr(reagentSection, (L and L["V2_COL_PRICE"]) or "Price", reagentColumnX + reagentNameW + reagentQtyW + reagentNeedW, reagentPriceW, reagentColumnY)

    local reagentScroll = CreateFrame("ScrollFrame", nil, reagentSection, "UIPanelScrollFrameTemplate")
    reagentScroll:SetPoint("TOPLEFT", reagentSection, "TOPLEFT", reagentColumnX, reagentScrollTop)
    reagentScroll:SetPoint("BOTTOMRIGHT", reagentSection, "BOTTOMRIGHT", -28, reagentScrollBottom)
    if flattenSections then
        reagentScroll:SetHeight(reagentSectionHeight - 28)
    end
    rpDetail.reagentScrollFrame = reagentScroll

    local reagentListHost = CreateFrame("Frame", nil, reagentScroll)
    reagentListHost:SetWidth(detailInnerWidth)
    reagentListHost:SetHeight(1)
    reagentScroll:SetScrollChild(reagentListHost)
    rpDetail.reagentListHost = reagentListHost

    reagentListHost:EnableMouseWheel(true)
    reagentListHost:SetScript("OnMouseWheel", function(_, delta)
        local cur = reagentScroll:GetVerticalScroll()
        local max = reagentScroll:GetVerticalScrollRange()
        reagentScroll:SetVerticalScroll(math.max(0, math.min(max, cur - delta * (rowHeight * 3))))
    end)

    rpDetail.reagentRows = {}
    for i = 1, 12 do
        local row = CreateFrame("Frame", nil, reagentListHost)
        row:SetSize(detailInnerWidth, rowHeight)
        row:SetPoint("TOPLEFT", reagentListHost, "TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetHyperlinksEnabled(false)
        row:SetScript("OnMouseUp", itemRowClick)
        row:SetScript("OnEnter", itemRowEnter)
        row:SetScript("OnLeave", itemRowLeave)

        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
        rowBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 1)
        rowBg:SetColorTexture(0.10, 0.10, 0.10, (i % 2 == 1) and 0.55 or 0.28)
        themeRefs.reagentRowBgs[i] = rowBg

        local nameRowFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameRowFS:SetPoint("LEFT", row, "LEFT", 6, 0)
        nameRowFS:SetWidth(reagentNameW - 14)
        nameRowFS:SetJustifyH("LEFT")
        nameRowFS:SetWordWrap(false)
        applyFontSize(nameRowFS, softInk and 11 or 10)
        applyTextShadow(nameRowFS)

        local qtyFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        qtyFS:SetPoint("LEFT", row, "LEFT", reagentNameW + 2, 0)
        qtyFS:SetWidth(reagentQtyW)
        qtyFS:SetJustifyH("CENTER")
        qtyFS:SetWordWrap(false)
        applyFontSize(qtyFS, softInk and 11 or 10)
        applyTextShadow(qtyFS)

        local qtyEB = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        qtyEB:SetSize(reagentQtyW - 6, 18)
        qtyEB:SetPoint("LEFT", row, "LEFT", reagentNameW + 2, 0)
        qtyEB:SetAutoFocus(false)
        qtyEB:SetNumeric(false)
        qtyEB:SetJustifyH("CENTER")
        qtyEB:Hide()
        qtyEB:SetScript("OnEnterPressed", function(self)
            onCommitInputQty(self:GetText())
            self:ClearFocus()
        end)
        qtyEB:SetScript("OnEditFocusLost", function(self)
            self:ClearFocus()
        end)

        local priceFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        priceFS:SetPoint("LEFT", row, "LEFT", reagentNameW + reagentQtyW + reagentNeedW + 4, 0)
        priceFS:SetWidth(reagentPriceW - 6)
        priceFS:SetJustifyH("LEFT")
        priceFS:SetWordWrap(false)
        applyFontSize(priceFS, softInk and 11 or 10)
        applyTextShadow(priceFS)

        local needFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        needFS:SetPoint("LEFT", row, "LEFT", reagentNameW + reagentQtyW + 2, 0)
        needFS:SetWidth(reagentNeedW - 2)
        needFS:SetJustifyH("CENTER")
        needFS:SetWordWrap(false)
        applyFontSize(needFS, softInk and 11 or 10)
        applyTextShadow(needFS)

        row.nameFS = nameRowFS
        row.qtyFS = qtyFS
        row.qtyEB = qtyEB
        row.needFS = needFS
        row.priceFS = priceFS
        row:Hide()
        rpDetail.reagentRows[i] = row
    end
    y = y - reagentSectionHeight - 8

    local outHdr = bodyRoot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    outHdr:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, y)
    outHdr:SetText((L and L["DETAIL_OUTPUT_HDR"]) or "Output Items")
    outHdr:SetTextColor(smallHeaderColor[1], smallHeaderColor[2], smallHeaderColor[3], smallHeaderColor[4] or 1)
    applyFontSize(outHdr, 12)
    applyTextShadow(outHdr)
    y = y - 18

    local outputNameW, outputQtyW = 148, 48
    local outputPriceW = detailInnerWidth - outputNameW - outputQtyW

    local outputShell, outputSection = nil, bodyRoot
    local outputScrollTop = -22
    local outputScrollBottom = 8
    local outputColumnY = -8
    local outputColumnX = flattenSections and 0 or 8
    if flattenSections then
        outputSection = CreateFrame("Frame", nil, bodyRoot)
        outputSection:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, y)
        outputSection:SetPoint("TOPRIGHT", bodyRoot, "TOPRIGHT", 0, y)
        outputSection:SetHeight(outputSectionHeight)
        MakeRule(y - 2, 0.22)
        rpDetail.outputHeaderBg = nil
    else
        outputShell, outputSection = createShell(bodyRoot, "section", { left = 4, right = 4, top = 4, bottom = 4 })
        outputShell:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, y)
        outputShell:SetPoint("TOPRIGHT", bodyRoot, "TOPRIGHT", 0, y)
        outputShell:SetHeight(outputSectionHeight)

        local outputHeaderBg = outputSection:CreateTexture(nil, "ARTWORK")
        outputHeaderBg:SetPoint("TOPLEFT", outputSection, "TOPLEFT", 1, -1)
        outputHeaderBg:SetPoint("TOPRIGHT", outputSection, "TOPRIGHT", -1, -1)
        outputHeaderBg:SetHeight(18)
        outputHeaderBg:SetColorTexture(0.12, 0.10, 0.03, 0.9)
        rpDetail.outputHeaderBg = outputHeaderBg
    end
    rpDetail.outputSection = outputSection

    MakeSmallColHdr(outputSection, (L and L["COL_ITEM"]) or "Item", outputColumnX, outputNameW, outputColumnY)
    MakeSmallColHdr(outputSection, (L and L["V2_COL_TOTAL"]) or "Total", outputColumnX + outputNameW, outputQtyW, outputColumnY, "CENTER")
    MakeSmallColHdr(outputSection, (L and L["V2_COL_NET"]) or "Net", outputColumnX + outputNameW + outputQtyW, outputPriceW, outputColumnY)

    local outputScroll = CreateFrame("ScrollFrame", nil, outputSection, "UIPanelScrollFrameTemplate")
    outputScroll:SetPoint("TOPLEFT", outputSection, "TOPLEFT", outputColumnX, outputScrollTop)
    outputScroll:SetPoint("BOTTOMRIGHT", outputSection, "BOTTOMRIGHT", -28, outputScrollBottom)
    if flattenSections then
        outputScroll:SetHeight(outputSectionHeight - 28)
    end
    rpDetail.outputScrollFrame = outputScroll

    local outputListHost = CreateFrame("Frame", nil, outputScroll)
    outputListHost:SetWidth(detailInnerWidth)
    outputListHost:SetHeight(1)
    outputScroll:SetScrollChild(outputListHost)
    rpDetail.outputListHost = outputListHost

    outputListHost:EnableMouseWheel(true)
    outputListHost:SetScript("OnMouseWheel", function(_, delta)
        local cur = outputScroll:GetVerticalScroll()
        local max = outputScroll:GetVerticalScrollRange()
        outputScroll:SetVerticalScroll(math.max(0, math.min(max, cur - delta * (rowHeight * 3))))
    end)

    rpDetail.outputRows = {}
    for i = 1, 10 do
        local row = CreateFrame("Frame", nil, outputListHost)
        row:SetSize(detailInnerWidth, rowHeight)
        row:SetPoint("TOPLEFT", outputListHost, "TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetHyperlinksEnabled(false)
        row:SetScript("OnMouseUp", itemRowClick)
        row:SetScript("OnEnter", itemRowEnter)
        row:SetScript("OnLeave", itemRowLeave)

        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
        rowBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 1)
        rowBg:SetColorTexture(0.10, 0.10, 0.10, (i % 2 == 1) and 0.55 or 0.28)
        themeRefs.outputRowBgs[i] = rowBg

        local nameRowFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameRowFS:SetPoint("LEFT", row, "LEFT", 6, 0)
        nameRowFS:SetWidth(outputNameW - 16)
        nameRowFS:SetJustifyH("LEFT")
        nameRowFS:SetWordWrap(false)
        applyFontSize(nameRowFS, softInk and 11 or 10)
        applyTextShadow(nameRowFS)

        local qtyFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        qtyFS:SetPoint("LEFT", row, "LEFT", outputNameW + 2, 0)
        qtyFS:SetWidth(outputQtyW - 2)
        qtyFS:SetJustifyH("CENTER")
        qtyFS:SetWordWrap(false)
        applyFontSize(qtyFS, softInk and 11 or 10)
        applyTextShadow(qtyFS)

        local priceFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        priceFS:SetPoint("LEFT", row, "LEFT", outputNameW + outputQtyW + 6, 0)
        priceFS:SetWidth(outputPriceW - 10)
        priceFS:SetJustifyH("LEFT")
        priceFS:SetWordWrap(false)
        applyFontSize(priceFS, softInk and 11 or 10)
        applyTextShadow(priceFS)

        row.nameFS = nameRowFS
        row.qtyFS = qtyFS
        row.priceFS = priceFS
        row:Hide()
        rpDetail.outputRows[i] = row
    end
    y = y - outputSectionHeight - 4

    local buttonY1 = padding + 22
    local buttonY0 = padding - 2

    local function MakeDetailButton(label, width, xOff, rowY)
        local button = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetText(label)
        button:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", padding + xOff, rowY)
        return button
    end

    local btnScanStrat = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    btnScanStrat:SetSize(82, 22)
    btnScanStrat:SetPoint("BOTTOM", root, "BOTTOM", 0, buttonY0)
    btnScanStrat:SetText((L and L["BTN_SCAN_STRAT"]) or "Scan Strat")
    btnScanStrat:SetScript("OnClick", onScanSelected)
    attachButtonTooltip(
        btnScanStrat,
        (L and L["TT_SCAN_ALL_ITEMS_TITLE"]) or "Scan All Strategy Items",
        (L and L["TT_SCAN_ALL_ITEMS_BODY"]) or "Queue all reagents and output items in this strategy for AH price lookups."
    )
    btnScanStrat:Disable()
    btnScanStrat:SetAlpha(0.45)
    btnScanStrat:Hide()
    rpDetail.btnScanStrat = btnScanStrat

    local btnCraftSim = MakeDetailButton((L and L["BTN_CRAFTSIM_SHORT"]) or "CraftSim", 70, 90, buttonY1)
    btnCraftSim:SetScript("OnClick", onPushCraftSim)
    attachButtonTooltip(
        btnCraftSim,
        (L and L["TT_CRAFTSIM_TITLE"]) or "Push Price Overrides to CraftSim",
        (L and L["TT_CRAFTSIM_WARN"]) or "Warning: This will overwrite any existing manual price overrides in CraftSim for all reagents in this strategy."
    )
    btnCraftSim:Hide()

    local btnVIBreakdown = MakeDetailButton((L and L["BTN_VI_BREAKDOWN"]) or "VI Chain", 84, 0, buttonY1)
    btnVIBreakdown:SetScript("OnClick", function()
        onShowBreakdown()
    end)
    attachButtonTooltip(
        btnVIBreakdown,
        (L and L["TT_VI_BREAKDOWN_TITLE"]) or "Show VI Breakdown",
        (L and L["TT_VI_BREAKDOWN_BODY"]) or "Opens a step-by-step breakdown of the current VI chain, including direct AH comparisons and rounded craft planning."
    )
    btnVIBreakdown:Hide()
    rpDetail.btnVIBreakdown = btnVIBreakdown

    local btnShop = MakeDetailButton((L and L["BTN_SHOPPING_SHORT"]) or "Shopping", 70, 166, buttonY1)
    btnShop:SetScript("OnClick", onToggleShopping)
    attachButtonTooltip(
        btnShop,
        (L and L["TT_SHOPPING_TITLE"]) or "Create Auctionator Shopping List",
        (L and L["TT_SHOPPING_BODY"]) or "Creates an Auctionator shopping list for the selected strategy's missing input items."
    )
    btnShop:Hide()

    local btnEdit = MakeDetailButton(L and L["BTN_EDIT_STRAT"] or "Edit", 70, 0, buttonY0)
    btnEdit:SetScript("OnClick", onEditSelected)
    rpDetail.btnEdit = btnEdit

    local btnDelete = MakeDetailButton(L and L["BTN_DELETE_STRAT"] or "Delete", 78, 78, buttonY0)
    btnDelete:SetScript("OnClick", onDeleteSelected)
    rpDetail.btnDelete = btnDelete

    return root
end
