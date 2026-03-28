-- GoldAdvisorMidnight/UI/MainWindowV2Detail.lua
-- Shared inline-detail builder/renderer for MainWindowV2.
-- Module: GAM.UI.MainWindowV2Detail

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local Detail = {}
GAM.UI.MainWindowV2Detail = Detail

local DEFAULT_GOLD = { 1.0, 0.82, 0.0 }
local DEFAULT_RULE = { 0.7, 0.57, 0.0, 0.7 }

local function Noop()
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
    if args.selectedScanBtn then
        args.selectedScanBtn:Disable()
        args.selectedScanBtn:SetAlpha(0.45)
    end
    if args.selectedCraftSimBtn then
        args.selectedCraftSimBtn:Disable()
    end
    if args.selectedShoppingBtn then
        args.selectedShoppingBtn:Disable()
    end
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
        rpDetail.craftsEB:SetText(tostring(craftsVal))
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
            row.qtyFS:SetText(string.format("%.0f", reagentMetric.required or 0))
            row.needFS:SetText(string.format("%.0f", reagentMetric.needToBuy or 0))
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
            row.qtyFS:SetText(outputItem.expectedQty and string.format("%.0f", math.floor(outputItem.expectedQty)) or "—")
            row.priceFS:SetText(
                outputItem.netRevenue and formatPrice(outputItem.netRevenue)
                or (outputItem.unitPrice and formatPrice(outputItem.unitPrice) or "|cffff8800—|r")
            )
            row._metricTooltip = {
                kind = "output",
                unitPrice = outputItem.unitPrice,
                expectedQty = outputItem.expectedQty,
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
    craftsEB:SetPoint("TOPRIGHT", bodyRoot, "TOPRIGHT", 0, y + 1)
    craftsEB:SetAutoFocus(false)
    craftsEB:SetNumeric(true)
    craftsEB:SetScript("OnEnterPressed", function(self)
        onCommitCrafts(self:GetText())
        self:ClearFocus()
    end)
    craftsEB:SetScript("OnEditFocusLost", function(self)
        self:ClearFocus()
    end)
    rpDetail.craftsEB = craftsEB

    local craftsLabel = bodyRoot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    craftsLabel:SetPoint("RIGHT", craftsEB, "LEFT", -4, 0)
    craftsLabel:SetText((L and L["V2_CRAFTS_LABEL"]) or "Crafts:")
    craftsLabel:SetTextColor(smallHeaderColor[1], smallHeaderColor[2], smallHeaderColor[3], smallHeaderColor[4] or 1)
    applyFontSize(craftsLabel, 12)
    applyTextShadow(craftsLabel)
    y = y - 18

    local detailInnerWidth = usableWidth - 18
    local reagentNameW, reagentQtyW, reagentNeedW = 156, 48, 52
    local reagentPriceW = detailInnerWidth - reagentNameW - reagentQtyW - reagentNeedW
    local reagentSectionHeight = 136
    local outputSectionHeight = 118

    local function MakeSmallColHdr(parent, text, xOff, width, yOff)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, yOff)
        fs:SetWidth(width)
        fs:SetText(text)
        fs:SetTextColor(columnHeaderColor[1], columnHeaderColor[2], columnHeaderColor[3], columnHeaderColor[4] or 1)
        fs:SetJustifyH("LEFT")
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
    MakeSmallColHdr(reagentSection, (L and L["V2_COL_TOTAL"]) or "Total", reagentColumnX + reagentNameW, reagentQtyW, reagentColumnY)
    MakeSmallColHdr(reagentSection, (L and L["V2_COL_NEED"]) or "Need", reagentColumnX + reagentNameW + reagentQtyW, reagentNeedW, reagentColumnY)
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
        qtyFS:SetJustifyH("RIGHT")
        qtyFS:SetWordWrap(false)
        applyFontSize(qtyFS, softInk and 11 or 10)
        applyTextShadow(qtyFS)

        local qtyEB = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        qtyEB:SetSize(reagentQtyW - 6, 18)
        qtyEB:SetPoint("LEFT", row, "LEFT", reagentNameW + 2, 0)
        qtyEB:SetAutoFocus(false)
        qtyEB:SetNumeric(false)
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
        priceFS:SetJustifyH("RIGHT")
        priceFS:SetWordWrap(false)
        applyFontSize(priceFS, softInk and 11 or 10)
        applyTextShadow(priceFS)

        local needFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        needFS:SetPoint("LEFT", row, "LEFT", reagentNameW + reagentQtyW + 2, 0)
        needFS:SetWidth(reagentNeedW - 2)
        needFS:SetJustifyH("RIGHT")
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

    local outputNameW, outputQtyW = 170, 48
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
    MakeSmallColHdr(outputSection, (L and L["V2_COL_TOTAL"]) or "Total", outputColumnX + outputNameW, outputQtyW, outputColumnY)
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
        qtyFS:SetJustifyH("RIGHT")
        qtyFS:SetWordWrap(false)
        applyFontSize(qtyFS, softInk and 11 or 10)
        applyTextShadow(qtyFS)

        local priceFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        priceFS:SetPoint("LEFT", row, "LEFT", outputNameW + outputQtyW + 6, 0)
        priceFS:SetWidth(outputPriceW - 10)
        priceFS:SetJustifyH("RIGHT")
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
