-- GoldAdvisorMidnight/UI/MainWindowV2Detail.lua
-- Shared inline-detail builder/renderer for MainWindowV2.
-- Module: GAM.UI.MainWindowV2Detail

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local Detail = {}
GAM.UI.MainWindowV2Detail = Detail
local VIBreakdownWindow = GAM.UI.VIBreakdownWindow
local CrushingAnalyzerWindow = GAM.UI.CrushingAnalyzerWindow

Detail.ShowBreakdownWindow = VIBreakdownWindow.Show
Detail.HideBreakdownWindow = VIBreakdownWindow.Hide

local DEFAULT_GOLD = { 1.0, 0.82, 0.0 }
local DEFAULT_RULE = { 0.7, 0.57, 0.0, 0.7 }
local DEFAULT_ITEM_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function Noop()
end

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
    local text = string.format("%.1f", number):gsub("0+$", ""):gsub("%.$", "")
    return AddThousandsSeparators(text)
end

local function GetCommitButtonText(localizer)
    return "OK"
end

local function GetItemIconTexture(itemID)
    if itemID and itemID > 0 then
        if C_Item and C_Item.GetItemIconByID then
            local icon = C_Item.GetItemIconByID(itemID)
            if icon then
                return icon
            end
        end
        local icon = select(5, GetItemInfoInstant(itemID))
        if icon then
            return icon
        end
    end
    return DEFAULT_ITEM_ICON
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
    if rpDetail.btnOpenRecipe then
        rpDetail.btnOpenRecipe:Disable()
        rpDetail.btnOpenRecipe:SetAlpha(0.45)
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
    CrushingAnalyzerWindow.Hide()
    VIBreakdownWindow.Hide()
    if args.onAfterHide then
        args.onAfterHide()
    end
end

function Detail.Render(args)
    local rpDetail = args.rpDetail or {}
    local strat = args.strat
    if not rpDetail.root or not strat then
        return args.canonicalResult
    end

    local patchTag = args.patchTag or GAM.C.DEFAULT_PATCH
    local L = args.localizer or GAM.L
    local placeholder = GetPlaceholder(args)
    local projection = args.projection or {}
    local bindItemRow = args.bindItemRow or Noop
    local getItemDisplayData = args.getItemDisplayData or function(_, name)
        return { displayText = name or "" }
    end
    local isCompactMode = args.isCompactMode and true or false
    local formatPrice = args.formatPrice or function(value)
        return tostring(value)
    end
    local rowHeight = args.rowHeight or 22

    rpDetail.canonicalResult = args.canonicalResult
    rpDetail.detailProjection = projection

    if rpDetail.craftsEB and not rpDetail.craftsEB:HasFocus() then
        local craftsVal = projection.crafts and math.floor(projection.crafts + 0.5) or 1
        local craftsText = tostring(craftsVal)
        rpDetail.craftsEB:SetText(craftsText)
        rpDetail.craftsEB._gamCommittedText = craftsText
        RefreshCommitButton(rpDetail.craftsEB)
    end

    if placeholder then
        placeholder:Hide()
    end

    local outputItems = {}
    for _, outputItem in ipairs(projection.outputs or {}) do
        outputItems[#outputItems + 1] = outputItem
    end

    rpDetail.nameFS:SetText(strat.stratName)
    local professionCaption = tostring(strat.profession or "")
    if projection.crafterCaption then
        professionCaption = professionCaption .. " - " .. projection.crafterCaption
    end
    rpDetail.profFS:SetText(professionCaption)
    -- The output is already shown with quantity and value in Expected Output.
    -- Use the otherwise-empty note line for rank-mix verification status.
    if rpDetail.outputSummaryFrame then rpDetail.outputSummaryFrame:Hide() end
    if rpDetail.outputSummaryLabelFS then rpDetail.outputSummaryLabelFS:Hide() end
    if rpDetail.notesFS then
        if projection.rankMixStatus == "verified" then
            rpDetail.notesFS:SetText("|cff55ff55Best rank mix verified by Blizzard (no Concentration).|r")
            rpDetail.notesFS:Show()
        elseif projection.rankMixStatus == "fallback" then
            rpDetail.notesFS:SetText(string.format(
                "|cffffaa33Best mix fallback: %s. Click Refresh Recipe to capture the breakpoint.|r",
                tostring(projection.rankMixReason or "live recipe data unavailable")))
            rpDetail.notesFS:Show()
        else
            rpDetail.notesFS:Hide()
            rpDetail.notesFS:SetText("")
        end
    end
    UpdateBodyAnchor(rpDetail)

    local dash = "|cff888888—|r"
    rpDetail.metCostFS:SetText(
        projection.cost and formatPrice(projection.cost) or dash)
    if rpDetail.metExpectedCostFS then
        rpDetail.metExpectedCostFS:SetText(
            projection.expectedCost and formatPrice(projection.expectedCost) or dash)
    end
    if rpDetail.metBuyNowFS then
        rpDetail.metBuyNowFS:SetText(
            projection.buyNowCost and formatPrice(projection.buyNowCost) or dash)
    end
    rpDetail.metRevenueFS:SetText(
        projection.revenue and formatPrice(projection.revenue) or dash)
    if projection.profit then
        local color = projection.profit >= 0 and "|cff55ff55" or "|cffff5555"
        rpDetail.metProfitFS:SetText(color .. formatPrice(projection.profit) .. "|r")
    else
        rpDetail.metProfitFS:SetText(dash)
    end
    if projection.roi then
        local color = projection.roi >= 0 and "|cff55ff55" or "|cffff5555"
        rpDetail.metROIFS:SetText(color .. string.format("%.2f%%", projection.roi) .. "|r")
    else
        rpDetail.metROIFS:SetText(dash)
    end
    rpDetail.metBreakevenFS:SetText(
        projection.breakEvenSell and formatPrice(projection.breakEvenSell) or dash)
    if rpDetail.metStatsFS then
        rpDetail.metStatsFS:SetText(projection.statsCaption or dash)
    end
    if rpDetail.metGearFS then
        local gearText = projection.gearCaption or dash
        if projection.gearPresetMissing then
            gearText = "|cffffaa33" .. gearText .. "|r"
        end
        rpDetail.metGearFS:SetText(gearText)
    end
    if rpDetail.metNodeBonusesFS then
        rpDetail.metNodeBonusesFS:SetText(projection.nodeBonusCaption or dash)
    end

    if projection.missingPrices and #projection.missingPrices > 0 then
        rpDetail.missingFS:SetText((L and L["MISSING_PRICES"] or "Missing prices") .. ": " .. table.concat(projection.missingPrices, ", "))
        rpDetail.missingFS:Show()
    else
        rpDetail.missingFS:Hide()
        rpDetail.missingFS:SetText("")
    end

    local reagentMetrics = projection.reagents or {}
    for i, row in ipairs(rpDetail.reagentRows or {}) do
        local reagentMetric = reagentMetrics[i]
        if reagentMetric then
            local display = getItemDisplayData(reagentMetric.itemID, reagentMetric.name)
            local nameText = display.displayText
            if reagentMetric.sourceNote and reagentMetric.sourceNote ~= "" then
                nameText = nameText .. " |cff888888(" .. reagentMetric.sourceNote .. ")|r"
            end
            row.nameFS:SetText(nameText)
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
                sourceNote = reagentMetric.sourceNote,
            }
            row:Show()
        else
            row:Hide()
            bindItemRow(row, nil)
            row._metricTooltip = nil
            row.qtyEB:Hide()
        end
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

    if rpDetail.btnOpenRecipe then
        local canOpen = type(strat.recipeID) == "number"
            or tonumber(strat.recipeID) ~= nil
        if canOpen and type(args.canOpenRecipe) == "function" then
            canOpen = args.canOpenRecipe(strat) and true or false
        end
        rpDetail.btnOpenRecipe:SetShown(canOpen)
        if canOpen then
            rpDetail.btnOpenRecipe:Enable()
            rpDetail.btnOpenRecipe:SetAlpha(1)
        else
            rpDetail.btnOpenRecipe:Disable()
            rpDetail.btnOpenRecipe:SetAlpha(0.45)
        end
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
        local contentHeight = math.max(1, #reagentMetrics * rowHeight)
        rpDetail.reagentListHost:SetHeight(contentHeight)
        local scrollBar = rpDetail.reagentScrollFrame and rpDetail.reagentScrollFrame.ScrollBar
        if scrollBar then
            scrollBar:SetShown(contentHeight > ((rpDetail.reagentScrollFrame:GetHeight() or 0) + 1))
        end
    end
    if rpDetail.outputListHost then
        local contentHeight = math.max(1, #outputItems * rowHeight)
        rpDetail.outputListHost:SetHeight(contentHeight)
        local scrollBar = rpDetail.outputScrollFrame and rpDetail.outputScrollFrame.ScrollBar
        if scrollBar then
            scrollBar:SetShown(contentHeight > ((rpDetail.outputScrollFrame:GetHeight() or 0) + 1))
        end
    end
    rpDetail.root:Show()
    if strat.id == "jewelcrafting__crushing__midnight_1" then
        CrushingAnalyzerWindow.Refresh(rpDetail.root, strat, patchTag, args.canonicalResult)
    else
        CrushingAnalyzerWindow.Hide()
    end
    if args.onAfterRender then
        args.onAfterRender(strat, patchTag, args.canonicalResult, reagentMetrics, outputItems)
    end
    return args.canonicalResult
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
    local actionHeight = args.actionHeight or 38
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
    local onOpenRecipe = args.onOpenRecipe or Noop
    local onPushCraftSim = args.onPushCraftSim or Noop
    local onToggleShopping = args.onToggleShopping or Noop
    local onShowBreakdown = args.onShowBreakdown or Noop

    local usableWidth = rightPanelWidth - padding * 2
    local softInk = layoutMode == "soft"
    local smallHeaderColor = softInk and bodyTextColor or gold
    local metricLabelColor = softInk and bodyTextColor or { 1.0, 0.82, 0.0, 1.0 }
    local metricValueColor = softInk and bodyTextColor or { 1.0, 1.0, 1.0, 1.0 }
    local columnHeaderColor = softInk and mutedTextColor or { 1.0, 0.84, 0.22, 1.0 }

    local root = CreateFrame("Frame", nil, panel)
    root:SetAllPoints(panel)
    root:SetClipsChildren(true)
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
    y = y - 26

    local outputSummaryLabelFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    outputSummaryLabelFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    outputSummaryLabelFS:SetWidth(48)
    outputSummaryLabelFS:SetText((L and L["DETAIL_OUTPUT"]) or "Output:")
    outputSummaryLabelFS:SetTextColor(mutedTextColor[1], mutedTextColor[2], mutedTextColor[3], mutedTextColor[4] or 1)
    applyFontSize(outputSummaryLabelFS, 10)
    applyTextShadow(outputSummaryLabelFS, 0.75)
    rpDetail.outputSummaryLabelFS = outputSummaryLabelFS

    local outputSummaryFrame = CreateFrame("Frame", nil, content)
    outputSummaryFrame:SetPoint("TOPLEFT", outputSummaryLabelFS, "TOPRIGHT", 6, 0)
    outputSummaryFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    outputSummaryFrame:SetHeight(18)
    outputSummaryFrame:SetScript("OnMouseUp", itemRowClick)
    outputSummaryFrame:SetScript("OnEnter", itemRowEnter)
    outputSummaryFrame:SetScript("OnLeave", itemRowLeave)
    rpDetail.outputSummaryFrame = outputSummaryFrame

    local outputSummaryIcon = outputSummaryFrame:CreateTexture(nil, "ARTWORK")
    outputSummaryIcon:SetPoint("LEFT", outputSummaryFrame, "LEFT", 0, 0)
    outputSummaryIcon:SetSize(18, 18)
    outputSummaryIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    outputSummaryIcon:SetTexture(DEFAULT_ITEM_ICON)
    rpDetail.outputSummaryIcon = outputSummaryIcon

    local outputSummaryNameFS = outputSummaryFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    outputSummaryNameFS:SetPoint("LEFT", outputSummaryIcon, "RIGHT", 6, 0)
    outputSummaryNameFS:SetPoint("RIGHT", outputSummaryFrame, "RIGHT", 0, 0)
    outputSummaryNameFS:SetJustifyH("LEFT")
    outputSummaryNameFS:SetWordWrap(false)
    outputSummaryNameFS:SetTextColor(bodyTextColor[1], bodyTextColor[2], bodyTextColor[3], bodyTextColor[4] or 1)
    applyFontSize(outputSummaryNameFS, softInk and 10 or 11)
    applyTextShadow(outputSummaryNameFS, 0.75)
    rpDetail.outputSummaryNameFS = outputSummaryNameFS
    outputSummaryLabelFS:Hide()
    outputSummaryFrame:Hide()

    local profFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    profFS:SetWidth(usableWidth)
    profFS:SetJustifyH("LEFT")
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
    rpDetail.notesReservedHeight = 0

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
        labelFS:SetWordWrap(false)
        labelFS:SetText(label)
        labelFS:SetTextColor(metricLabelColor[1], metricLabelColor[2], metricLabelColor[3], metricLabelColor[4] or 1)
        applyFontSize(labelFS, 11)
        applyTextShadow(labelFS)

        local valueFS = bodyRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        valueFS:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", labelWidth + 6, yOff)
        valueFS:SetWidth(usableWidth - labelWidth - 6)
        valueFS:SetJustifyH("LEFT")
        valueFS:SetWordWrap(false)
        valueFS:SetTextColor(metricValueColor[1], metricValueColor[2], metricValueColor[3], metricValueColor[4] or 1)
        applyFontSize(valueFS, 11)
        applyTextShadow(valueFS)
        return valueFS, yOff - 18
    end

    local function MakeMetricTooltip(yOff, titleKey, bodyKey, bodyProvider)
        local anchor = CreateFrame("Button", nil, bodyRoot)
        anchor:SetSize(usableWidth, 18)
        anchor:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, yOff)
        anchor:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText((L and L[titleKey]) or titleKey, 1, 1, 1)
            local body = bodyProvider and bodyProvider() or ((L and L[bodyKey]) or bodyKey)
            GameTooltip:AddLine(body or ((L and L[bodyKey]) or bodyKey), 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        anchor:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- Decision first: expected return, then material commitment, then setup.
    local yProfit = y
    rpDetail.metProfitFS, y = MakeMetricRow(L and L["LBL_PROFIT"] or "Profit:", y)
    applyFontSize(rpDetail.metProfitFS, 12)

    local yROI = y
    rpDetail.metROIFS, y = MakeMetricRow(L and L["LBL_ROI"] or "ROI:", y)

    local yBreakeven = y
    rpDetail.metBreakevenFS, y = MakeMetricRow(L and L["LBL_BREAKEVEN"] or "Break-even:", y)
    MakeMetricTooltip(yBreakeven, "TT_LBL_BREAKEVEN_TITLE", "TT_LBL_BREAKEVEN_BODY")

    MakeRule(y, 0.4)
    y = y - 4

    local yCost = y
    rpDetail.metCostFS, y = MakeMetricRow(
        L and L["LBL_MATERIAL_VALUE"] or "Material Value:", y)
    MakeMetricTooltip(yCost, "TT_LBL_COST_TITLE", "TT_LBL_COST_BODY")
    rpDetail.metExpectedCostFS = nil

    local yBuyNow = y
    rpDetail.metBuyNowFS, y = MakeMetricRow(L and L["LBL_BUY_NOW_COST"] or "Buy Now Cost:", y)
    MakeMetricTooltip(yBuyNow, "TT_LBL_BUY_NOW_COST_TITLE", "TT_LBL_BUY_NOW_COST_BODY")

    rpDetail.metRevenueFS, y = MakeMetricRow(L and L["LBL_REVENUE"] or "Revenue:", y)

    MakeRule(y, 0.4)
    y = y - 4

    local yStats = y
    rpDetail.metStatsFS, y = MakeMetricRow(L and L["LBL_STATS"] or "Craft Stats:", y)
    MakeMetricTooltip(
        yStats,
        "TT_LBL_STATS_TITLE",
        "TT_LBL_STATS_BODY",
        function()
            local projection = rpDetail.detailProjection or {}
            return projection.statsTooltip
        end)

    local yGear = y
    rpDetail.metGearFS, y = MakeMetricRow(
        L and L["LBL_GEAR_PLAN"] or "Gear Plan:", y)
    MakeMetricTooltip(
        yGear,
        "TT_LBL_GEAR_PLAN_TITLE",
        "TT_LBL_GEAR_PLAN_BODY",
        function()
            local projection = rpDetail.detailProjection or {}
            return projection.gearTooltip
        end)

    local yNodeBonuses = y
    rpDetail.metNodeBonusesFS, y = MakeMetricRow(
        L and L["LBL_NODE_BONUSES"] or "Recipe Bonuses:", y)
    MakeMetricTooltip(
        yNodeBonuses,
        "TT_LBL_NODE_BONUSES_TITLE",
        "TT_LBL_NODE_BONUSES_BODY",
        function()
            local projection = rpDetail.detailProjection or {}
            return projection.nodeBonusTooltip
        end)

    local missingFS = bodyRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    missingFS:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, y)
    missingFS:SetWidth(usableWidth)
    missingFS:SetJustifyH("LEFT")
    missingFS:SetTextColor(1.0, 0.75, 0.2, 1.0)
    missingFS:SetWordWrap(false)
    applyFontSize(missingFS, 10)
    applyTextShadow(missingFS)
    missingFS:Hide()
    rpDetail.missingFS = missingFS
    y = y - 14

    local reagHdr = bodyRoot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reagHdr:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, y)
    reagHdr:SetText((L and L["DETAIL_INPUT_HDR"]) or "Materials")
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
    craftsLabel:SetText((L and L["V2_CRAFTS_LABEL"]) or "Starting crafts:")
    craftsLabel:SetTextColor(smallHeaderColor[1], smallHeaderColor[2], smallHeaderColor[3], smallHeaderColor[4] or 1)
    applyFontSize(craftsLabel, 12)
    applyTextShadow(craftsLabel)
    attachButtonTooltip(
        craftsEB,
        (L and L["TT_STARTING_CRAFTS_TITLE"]) or "Starting Crafts",
        (L and L["TT_STARTING_CRAFTS_BODY"]) or "How many crafts your starting materials would normally support. Expected Resourcefulness savings may allow additional whole crafts."
    )
    y = y - 18

    local detailInnerWidth = usableWidth - 18
    local reagentNameW, reagentQtyW, reagentNeedW = 140, 48, 48
    local reagentPriceW = detailInnerWidth - reagentNameW - reagentQtyW - reagentNeedW
    local reagentSectionHeight = 96
    local outputSectionHeight = 72

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
    outHdr:SetText((L and L["DETAIL_OUTPUT_HDR"]) or "Expected Output")
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
    MakeSmallColHdr(outputSection, (L and L["V2_COL_QTY"]) or "Qty", outputColumnX + outputNameW, outputQtyW, outputColumnY, "CENTER")
    MakeSmallColHdr(outputSection, (L and L["V2_COL_NET"]) or "Net Value", outputColumnX + outputNameW + outputQtyW, outputPriceW, outputColumnY)

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
    -- Keep the only visible detail action above the clipped panel edge and
    -- inside the height already reserved below `content`.
    local buttonY0 = padding + 6

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
        (L and L["TT_SCAN_SELECTED_TITLE"]) or "Scan Selected Strategy",
        (L and L["TT_SCAN_SELECTED_BODY"]) or "Queue the selected strategy's reagents and output items for AH price lookups. Shift-click to scan only the currently visible favorites."
    )
    btnScanStrat:Disable()
    btnScanStrat:SetAlpha(0.45)
    btnScanStrat:Hide()
    rpDetail.btnScanStrat = btnScanStrat

    local btnCraftSim = MakeDetailButton((L and L["BTN_CRAFTSIM_SHORT"]) or "CraftSim", 70, 90, buttonY1)
    btnCraftSim:SetScript("OnClick", onPushCraftSim)
    attachButtonTooltip(
        btnCraftSim,
        (L and L["TT_CRAFTSIM_TITLE"]) or "Send Prices to CraftSim",
        (L and L["TT_CRAFTSIM_WARN"]) or "Send this strategy's reagent prices to CraftSim. Existing manual prices in CraftSim will be replaced."
    )
    btnCraftSim:Hide()

    local btnVIBreakdown = MakeDetailButton((L and L["BTN_VI_BREAKDOWN"]) or "VI Chain", 84, 0, buttonY1)
    btnVIBreakdown:SetScript("OnClick", function()
        onShowBreakdown()
    end)
    attachButtonTooltip(
        btnVIBreakdown,
        (L and L["TT_VI_BREAKDOWN_TITLE"]) or "Show Craft Steps",
        (L and L["TT_VI_BREAKDOWN_BODY"]) or "Show the materials and intermediate crafts behind the selected estimate."
    )
    btnVIBreakdown:Hide()
    rpDetail.btnVIBreakdown = btnVIBreakdown

    local btnShop = MakeDetailButton((L and L["BTN_SHOPPING_SHORT"]) or "Shopping", 70, 166, buttonY1)
    btnShop:SetScript("OnClick", onToggleShopping)
    attachButtonTooltip(
        btnShop,
        (L and L["TT_SHOPPING_TITLE"]) or "Auctionator Shopping List",
        (L and L["TT_SHOPPING_BODY"]) or "Create a shopping list for the materials you still need."
    )
    btnShop:Hide()

    local btnOpenRecipe = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    btnOpenRecipe:SetSize(104, 22)
    btnOpenRecipe:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -padding, buttonY0)
    btnOpenRecipe:SetText((L and L["BTN_REFRESH_RECIPE"]) or "Refresh Recipe")
    btnOpenRecipe:SetScript("OnClick", onOpenRecipe)
    attachButtonTooltip(
        btnOpenRecipe,
        (L and L["TT_REFRESH_RECIPE_TITLE"]) or "Open and Refresh Recipe",
        (L and L["TT_REFRESH_RECIPE_BODY"]) or "Open this recipe in Blizzard's profession window and update its crafting stats and specialization bonuses."
    )
    btnOpenRecipe:Disable()
    btnOpenRecipe:SetAlpha(0.45)
    rpDetail.btnOpenRecipe = btnOpenRecipe

    return root
end
