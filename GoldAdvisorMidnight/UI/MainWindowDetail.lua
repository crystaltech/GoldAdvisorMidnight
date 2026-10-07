-- GoldAdvisorMidnight/UI/MainWindowDetail.lua
-- Shared inline-detail builder/renderer for MainWindow.
-- Module: GAM.UI.MainWindowDetail

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local Detail = {}
GAM.UI.MainWindowDetail = Detail
GAM.UI.MainWindowV2Detail = Detail -- Compatibility alias for pre-refocus callers.
local VIBreakdownWindow = GAM.UI.VIBreakdownWindow
local CrushingAnalyzerWindow = GAM.UI.CrushingAnalyzerWindow

Detail.ShowBreakdownWindow = VIBreakdownWindow.Show
Detail.HideBreakdownWindow = VIBreakdownWindow.Hide

local DEFAULT_GOLD = { 1.0, 0.82, 0.0 }
local DEFAULT_RULE = { 0.7, 0.57, 0.0, 0.7 }
local DEFAULT_ITEM_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function Noop()
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
    local text = string.format("%.1f", number):gsub("0+$", ""):gsub("%.$", "")
    return AddThousandsSeparators(text)
end

local function GetCommitButtonText()
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
    editBox._gamPendingText = editBox._gamCommittedText

    local function SetTextWithoutChangingDraft(text)
        editBox._gamRestoringText = true
        editBox:SetText(tostring(text or ""))
        editBox._gamRestoringText = nil
    end

    local function CommitCurrentValue(fromButton)
        if editBox._gamCommitInProgress then
            return
        end
        local text = tostring(editBox._gamPendingText or editBox:GetText() or "")
        editBox._gamCommitInProgress = true
        if fromButton then
            editBox._gamCommitFromButton = true
        end
        local normalizedText = commitFn(text)
        local committedText = normalizedText ~= nil and tostring(normalizedText) or text
        editBox._gamCommittedText = committedText
        editBox._gamPendingText = committedText
        if tostring(editBox:GetText() or "") ~= committedText then
            SetTextWithoutChangingDraft(committedText)
        end
        if editBox:HasFocus() then
            editBox:ClearFocus()
        end
        editBox._gamCommitInProgress = nil
        editBox._gamCommitFromButton = nil
        RefreshCommitButton(editBox)
    end

    button:SetScript("OnMouseDown", function()
        -- Commit before the edit box loses focus. The pending draft survives
        -- any focus-loss redraw that happens during the mouse event.
        CommitCurrentValue(true)
    end)
    button:SetScript("OnHide", function()
        editBox._gamCommitFromButton = nil
    end)

    editBox:SetScript("OnEnterPressed", function()
        CommitCurrentValue(false)
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        SetTextWithoutChangingDraft(self._gamCommittedText or "")
        self._gamPendingText = tostring(self._gamCommittedText or "")
        self._gamCommitFromButton = nil
        self:ClearFocus()
        RefreshCommitButton(self)
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        RefreshCommitButton(self)
    end)
    editBox:SetScript("OnTextChanged", function(self)
        if not self._gamRestoringText and not self._gamCommitInProgress then
            self._gamPendingText = tostring(self:GetText() or "")
        end
        RefreshCommitButton(self)
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        if self._gamCommitFromButton or self._gamCommitInProgress
            or (self._gamCommitButton and MouseIsOver and MouseIsOver(self._gamCommitButton)) then
            self._gamCommitFromButton = self._gamCommitFromButton or true
            return
        end
        local function RestoreCommittedText()
            if self:HasFocus() or self._gamCommitFromButton or self._gamCommitInProgress then
                return
            end
            local committed = tostring(self._gamCommittedText or "")
            if tostring(self:GetText() or "") ~= committed then
                SetTextWithoutChangingDraft(committed)
            end
            self._gamPendingText = committed
            RefreshCommitButton(self)
        end
        if C_Timer and type(C_Timer.After) == "function" then
            -- Let a button mouse-down commit the draft before a normal focus
            -- loss is treated as cancellation.
            C_Timer.After(0, RestoreCommittedText)
        else
            RestoreCommittedText()
        end
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
    local selectionChanged = not rpDetail.currentStrat or rpDetail.currentStrat.id ~= strat.id
        or rpDetail.currentPatch ~= patchTag
    if selectionChanged and rpDetail.queueNotice then
        rpDetail.queueNotice:Hide()
        if rpDetail.layoutQueueNotice then rpDetail.layoutQueueNotice() end
    end
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

    if rpDetail.craftsEB
            and not rpDetail.craftsEB:HasFocus()
            and not rpDetail.craftsEB._gamCommitInProgress then
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
        local model = GAM.UI and GAM.UI.StrategyDetailModel
        local notice = model and model.GetRankMixNotice and model.GetRankMixNotice(projection)
        local lines = {}
        if notice then
            local color = projection.rankMixStatus == "verified" and "|cff55ff55" or "|cffffaa33"
            lines[#lines + 1] = color .. notice .. "|r"
        end
        -- Old scan data must never look as current as a fresh scan.
        local stale = model and model.GetStalePriceNotice and model.GetStalePriceNotice(projection)
        if stale then lines[#lines + 1] = "|cffff5555" .. stale .. "|r" end
        if #lines > 0 then
            rpDetail.notesFS:SetText(table.concat(lines, "\n"))
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
        -- Match the Craft Queue's shopping list, not proc-adjusted chain yields.
        local plan = GAM.CraftPlan
        local upfront = plan and plan.EstimatePurchaseCost
            and plan.EstimatePurchaseCost(strat, patchTag, args.canonicalResult)
        rpDetail.metBuyNowFS:SetText(upfront and formatPrice(upfront) or dash)
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
    local unitBreakEven, stackBreakEven = GAM.UI.StrategyDetailModel.FormatBatchBreakEven(projection, formatPrice)
    rpDetail.metBreakevenFS:SetText(unitBreakEven)
    if rpDetail.metBreakevenStackFS then rpDetail.metBreakevenStackFS:SetText(stackBreakEven) end
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

    local reagentMetrics = projection.reagents or {}
    local ManualPrice = GAM.UI.ManualPrice
    local notes = {}
    if projection.missingPrices and #projection.missingPrices > 0 then
        notes[#notes + 1] = (L and L["MISSING_PRICES"] or "Missing prices") .. ": " .. table.concat(projection.missingPrices, ", ")
    end
    -- Profit built on the player's own prices is always flagged.
    notes[#notes + 1] = ManualPrice and ManualPrice.NoteText(reagentMetrics, patchTag) or nil
    if #notes > 0 then
        rpDetail.missingFS:SetText(table.concat(notes, "   "))
        rpDetail.missingFS:Show()
    else
        rpDetail.missingFS:Hide()
        rpDetail.missingFS:SetText("")
    end

    if rpDetail.ensureRows then rpDetail.ensureRows(#reagentMetrics, #outputItems) end
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
            -- Crafted intermediates are costed through their materials below.
            local priceText = reagentMetric.crafted and "|cff888888—|r"
                or reagentMetric.unitPrice and formatPrice(reagentMetric.unitPrice) or "|cffff8800—|r"
            if ManualPrice and not reagentMetric.crafted then
                priceText = ManualPrice.DecoratePrice(priceText, reagentMetric.itemID, patchTag)
            end
            row.priceFS:SetText(priceText)
            row._metricTooltip = {
                kind = "reagent",
                itemID = reagentMetric.itemID,
                name = reagentMetric.name,
                patchTag = patchTag,
                crafted = reagentMetric.crafted,
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
            row.qtyFS:SetText(outputItem.expectedQty and FormatQuantityValue(outputItem.expectedQtyRaw or outputItem.expectedQty) or "—")
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
        rpDetail.btnOpenRecipe:Show()
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
        local showScan = true
        rpDetail.btnScanStrat:SetShown(showScan)
        if showScan then
            rpDetail.btnScanStrat:Enable()
            rpDetail.btnScanStrat:SetAlpha(1)
        else
            rpDetail.btnScanStrat:Disable()
            rpDetail.btnScanStrat:SetAlpha(0.45)
        end
    end
    if rpDetail.btnVIBreakdown then
        rpDetail.btnVIBreakdown:Show()
        rpDetail.btnVIBreakdown:Enable()
        rpDetail.btnVIBreakdown:SetAlpha(1)
    end
    if rpDetail.btnShop then
        rpDetail.btnShop:Show()
        rpDetail.btnShop:Enable()
        rpDetail.btnShop:SetAlpha(1)
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
    if selectionChanged and rpDetail.reagentScrollFrame then
        rpDetail.reagentScrollFrame:SetVerticalScroll(0)
    end
    if selectionChanged and rpDetail.outputScrollFrame then
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
    if selectionChanged and rpDetail.viewport then rpDetail.viewport:SetVerticalScroll(0) end
    rpDetail.root:Show()
    if rpDetail.reflow then rpDetail.reflow() end
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
    local onQuickBuy = args.onQuickBuy or Noop
    local onShowBreakdown = args.onShowBreakdown or Noop
    local onCloseDetail = args.onCloseDetail or Noop
    local styleButton = args.styleButton
        or (GAM.UI.MainWindowCommon and GAM.UI.MainWindowCommon.StyleComfortableButton)
        or Noop

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

    local closeButton = CreateFrame("Button", nil, root, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", root, "TOPRIGHT", -2, -2)
    closeButton:SetScript("OnClick", onCloseDetail)
    rpDetail.closeButton = closeButton

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
    local contentTop = layoutMode == "comfortable" and 8 or 44
    content:SetPoint("TOPLEFT", root, "TOPLEFT", padding, -contentTop)
    content:SetPoint("TOPRIGHT", root, "TOPRIGHT", -padding, -contentTop)
    content:SetPoint("BOTTOM", root, "BOTTOM", 0, actionHeight + 6)
    rpDetail.content = content
    if layoutMode == "comfortable" then
        titleFS:Hide()
        topRule:Hide()
    end

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
        if layoutMode == "comfortable" then ruleTexture:Hide() end
        return ruleTexture
    end

    MakeRule(y)
    y = y - 6

    local labelWidth = 100
    local metricRows, metricTooltips, columnHeaders = {}, {}, {}
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
        valueFS._gamLabelFS = labelFS
        metricRows[#metricRows + 1] = { value = valueFS, label = labelFS, originalY = yOff }
        return valueFS, yOff - 18
    end

    local function MakeMetricTooltip(yOff, titleKey, bodyKey, bodyProvider)
        local anchor = CreateFrame("Button", nil, bodyRoot)
        metricTooltips[yOff] = anchor
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
    rpDetail.metProfitFS, y = MakeMetricRow(
        layoutMode == "comfortable" and "Estimated profit:" or (L and L["LBL_PROFIT"] or "Profit:"), y)
    applyFontSize(rpDetail.metProfitFS, 12)
    MakeMetricTooltip(yProfit, "Estimated profit",
        "Expected net revenue minus material value for the configured starting crafts.")

    local yReturn = y
    rpDetail.metROIFS, y = MakeMetricRow(
        layoutMode == "comfortable" and "Return:" or (L and L["LBL_ROI"] or "ROI:"), y)
    MakeMetricTooltip(yReturn, "Estimated return",
        "Estimated profit as a percentage of material value. Actual crafting results can vary.")

    local yBreakeven = y
    rpDetail.metBreakevenFS, y = MakeMetricRow((GAM.L and GAM.L["WF_DETAIL_BREAK_EVEN_ITEM"] or "Break-even / item:"), y)
    MakeMetricTooltip(yBreakeven, (GAM.L and GAM.L["WF_DETAIL_BREAK_EVEN_ITEM_TITLE"] or "Break-even sell price per item"),
        (GAM.L and GAM.L["WF_DETAIL_BREAK_EVEN_ITEM_TIP"] or "Minimum posting price per item that recovers expected consumed material value after the Auction House sale fee, rounded up to copper. Uses expected crafting yields; excludes lost deposits from expired auctions. Mixed outputs do not have one shared break-even price."))
    local yBreakevenStack = y
    rpDetail.metBreakevenStackFS, y = MakeMetricRow((GAM.L and GAM.L["WF_DETAIL_BREAK_EVEN_BATCH"] or "Break-even / batch:"), y)
    MakeMetricTooltip(yBreakevenStack, (GAM.L and GAM.L["WF_DETAIL_BREAK_EVEN_BATCH_TITLE"] or "Break-even for the selected crafting batch"),
        (GAM.L and GAM.L["WF_DETAIL_BREAK_EVEN_BATCH_TIP"] or "Total gross sale value needed to recover expected material cost after the AH fee for your selected starting crafts. Uses expected output, which can differ from craft count. Rounded up to copper; actual output may vary."))

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

    rpDetail.metRevenueFS, y = MakeMetricRow(
        layoutMode == "comfortable" and "Net revenue:" or (L and L["LBL_REVENUE"] or "Revenue:"), y)

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
            if GAM.CraftStats then
                return GAM.CraftStats.AppendTooltip(projection.statsTooltip, projection.statStrategyIDs)
            end
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
    craftsOKBtn:SetSize(28, 22)
    craftsOKBtn:SetPoint("TOPRIGHT", bodyRoot, "TOPRIGHT", 0, y + 1)
    craftsOKBtn:SetText(GetCommitButtonText())
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
        columnHeaders[#columnHeaders + 1] = fs
        return fs
    end

    local reagentSection
    local reagentScrollTop = -22
    local reagentScrollBottom = 8
    local reagentColumnY = -8
    local reagentColumnX = flattenSections and 0 or 8
    if flattenSections then
        reagentSection = CreateFrame("Frame", nil, bodyRoot)
        reagentSection:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, y)
        reagentSection:SetPoint("TOPRIGHT", bodyRoot, "TOPRIGHT", 0, y)
        reagentSection:SetHeight(reagentSectionHeight)
        if layoutMode ~= "comfortable" then MakeRule(y - 2, 0.22) end
        rpDetail.reagentHeaderBg = nil
    else
        local reagentShell
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
    local function CreateReagentRow(i)
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
    for i = 1, 12 do CreateReagentRow(i) end
    y = y - reagentSectionHeight - 8

    local outHdr = bodyRoot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    outHdr:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, y)
    outHdr:SetText(((L and L["DETAIL_OUTPUT_HDR"]) or "Expected Output") .. " (average)")
    outHdr:SetTextColor(smallHeaderColor[1], smallHeaderColor[2], smallHeaderColor[3], smallHeaderColor[4] or 1)
    applyFontSize(outHdr, 12)
    applyTextShadow(outHdr)
    y = y - 18

    local outputNameW, outputQtyW = 148, 48
    local outputPriceW = detailInnerWidth - outputNameW - outputQtyW

    local outputSection
    local outputScrollTop = -22
    local outputScrollBottom = 8
    local outputColumnY = -8
    local outputColumnX = flattenSections and 0 or 8
    if flattenSections then
        outputSection = CreateFrame("Frame", nil, bodyRoot)
        outputSection:SetPoint("TOPLEFT", bodyRoot, "TOPLEFT", 0, y)
        outputSection:SetPoint("TOPRIGHT", bodyRoot, "TOPRIGHT", 0, y)
        outputSection:SetHeight(outputSectionHeight)
        if layoutMode ~= "comfortable" then MakeRule(y - 2, 0.22) end
        rpDetail.outputHeaderBg = nil
    else
        local outputShell
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
    local function CreateOutputRow(i)
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
    for i = 1, 10 do CreateOutputRow(i) end
    rpDetail.ensureRows = function(reagents, outputs)
        for i = #rpDetail.reagentRows + 1, reagents do CreateReagentRow(i) end
        for i = #rpDetail.outputRows + 1, outputs do CreateOutputRow(i) end
    end
    local buttonY1 = padding + 22
    -- Keep the detail footer above the clipped panel edge and inside the
    -- height already reserved below `content`.
    local buttonY0 = padding + 6

    local function MakeDetailButton(label, width, xOff, rowY)
        local button = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetText(label)
        button:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", padding + xOff, rowY)
        return button
    end

    local btnScanStrat = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    btnScanStrat:SetSize(110, 22)
    btnScanStrat:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", padding, buttonY0)
    btnScanStrat:SetText((L and L["BTN_GET_CRAFT_PRICE"]) or "Get Craft Price")
    btnScanStrat:SetScript("OnClick", onScanSelected)
    attachButtonTooltip(
        btnScanStrat,
        (L and L["TT_GET_CRAFT_PRICE_TITLE"]) or "Get Selected Craft Price",
        (L and L["TT_GET_CRAFT_PRICE_BODY"])
            or "Update Auction House prices for the selected recipe and its materials. Shift-click to scan visible Favorites instead."
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

    local btnVIBreakdown = MakeDetailButton((GAM.L and GAM.L["WF_ADD_QUEUE"] or "Add to Queue"), 94, 0, buttonY0)
    local queueNotice = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    queueNotice:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", padding, 44)
    queueNotice:SetPoint("RIGHT", root, "RIGHT", -padding, 0)
    queueNotice:SetHeight(28)
    queueNotice:SetJustifyH("LEFT")
    queueNotice:SetWordWrap(true)
    queueNotice:Hide()
    rpDetail.queueNotice = queueNotice
    btnVIBreakdown:SetScript("OnClick", function()
        if GAM.UI.CraftPlanWindow and rpDetail.currentStrat then
            local ok, result = GAM.UI.CraftPlanWindow.Add(rpDetail.currentStrat, rpDetail.currentPatch)
            local count = type(result) == "table" and result.target
            queueNotice:SetText(ok and string.format(GAM.L and GAM.L["WF_QUEUE_ADDED"] or "Queued %d crafts. Add again queues another batch.", count or 0)
                or tostring(result or (GAM.L and GAM.L["WF_FINISH_QUANTITY_EDIT"] or "Finish editing the current queue quantity first.")))
            queueNotice:SetTextColor(ok and 0.5 or 1, ok and 1 or 0.65, 0.4)
            queueNotice:Show()
            if rpDetail.layoutQueueNotice then rpDetail.layoutQueueNotice() end
        else onShowBreakdown() end
    end)
    attachButtonTooltip(
        btnVIBreakdown,
        (GAM.L and GAM.L["WF_ADD_QUEUE_TITLE"] or "Add to Craft Queue"),
        (GAM.L and GAM.L["WF_ADD_QUEUE_TIP"] or "Queue this strategy's crafts and exact materials. Add more strategies to combine shopping and crafting steps.")
    )
    btnVIBreakdown:Hide()
    rpDetail.btnVIBreakdown = btnVIBreakdown

    local btnShop = MakeDetailButton((L and L["BTN_SHOPPING_SHORT"]) or (GAM.L and GAM.L["WF_SHOPPING"] or "Shopping"), 80, 0, buttonY0)
    btnShop:SetScript("OnClick", function()
        if IsShiftKeyDown and IsShiftKeyDown() then
            onQuickBuy()
        else
            onToggleShopping()
        end
    end)
    local shoppingTooltipBody = (L and L["TT_SHOPPING_BODY"])
        or "Create a shopping list for the materials you still need."
    if args.workspaceTabs then shoppingTooltipBody = (GAM.L and GAM.L["WF_SHOPPING_QUEUE_TIP"] or "View combined material shortages for the Craft Queue.") end
    shoppingTooltipBody = shoppingTooltipBody
        .. "\n" .. (GAM.L and GAM.L["WF_QUICK_BUY_SHORTCUT"] or "Shift-click to open Quick Buy for the current list.")
    attachButtonTooltip(
        btnShop,
        args.workspaceTabs and (GAM.L and GAM.L["WF_SHOPPING"] or "Shopping") or ((L and L["TT_SHOPPING_TITLE"]) or "Auctionator Shopping List"),
        shoppingTooltipBody
    )
    rpDetail.btnShop = btnShop

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

    if layoutMode == "comfortable" then
        styleButton(btnScanStrat, false)
        styleButton(btnCraftSim, false)
        styleButton(btnVIBreakdown, false)
        styleButton(btnShop, false)
        styleButton(btnOpenRecipe, true)
    end

    -- Keep the detail footer focused on the selected strategy's immediate
    -- workflow: price it, inspect the VI chain, shop, then refresh its recipe.
    btnScanStrat:ClearAllPoints()
    btnScanStrat:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", padding, buttonY0)
    btnVIBreakdown:ClearAllPoints()
    btnVIBreakdown:SetPoint("LEFT", btnScanStrat, "RIGHT", 4, 0)
    btnShop:ClearAllPoints()
    btnShop:SetPoint("LEFT", btnVIBreakdown, "RIGHT", 4, 0)

    if layoutMode == "comfortable" then
        local diagnostics = {
            rpDetail.metCostFS,
            rpDetail.metStatsFS,
            rpDetail.metGearFS,
            rpDetail.metNodeBonusesFS,
        }
        local btnInfo = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
        btnInfo:SetSize(72, 22)
        btnInfo:SetPoint("RIGHT", btnOpenRecipe, "LEFT", -6, 0)
        rpDetail.infoExpanded = rpDetail.infoExpanded and true or false

        local function RefreshInfoDisclosure()
            local shown = rpDetail.infoExpanded and true or false
            btnInfo:SetText(shown and "Hide Info" or "Info")
            for _, valueFS in ipairs(diagnostics) do
                valueFS:SetShown(shown)
                if valueFS._gamLabelFS then valueFS._gamLabelFS:SetShown(shown) end
            end
        end

        btnInfo:SetScript("OnClick", function()
            rpDetail.infoExpanded = not rpDetail.infoExpanded
            RefreshInfoDisclosure()
            if rpDetail.reflow then rpDetail.reflow() end
        end)
        attachButtonTooltip(btnInfo, "Estimate information",
            "Show or hide the crafting-stat, gear-plan, and recipe-bonus diagnostics used by this estimate.")
        rpDetail.btnInfo = btnInfo
        rpDetail.refreshInfoDisclosure = RefreshInfoDisclosure
        styleButton(btnInfo, false)
        btnInfo:Hide()
        RefreshInfoDisclosure()
    end

    if layoutMode == "comfortable" then
        -- Keep the action row stationary while long names, diagnostics and
        -- material lists share one measured, scrollable content area.
        local viewport = CreateFrame("ScrollFrame", nil, root, "UIPanelScrollFrameTemplate")
        viewport:SetPoint("TOPLEFT", root, "TOPLEFT", padding, -8)
        viewport:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -padding - 20, 52)
        content:ClearAllPoints()
        content:SetParent(viewport)
        content:SetWidth(usableWidth - 20)
        content:SetHeight(1)
        viewport:SetScrollChild(content)
        rpDetail.viewport = viewport
        rpDetail.layoutQueueNotice = function()
            viewport:ClearAllPoints()
            viewport:SetPoint("TOPLEFT", root, "TOPLEFT", padding, -8)
            viewport:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -padding - 20, queueNotice:IsShown() and 82 or 52)
            if rpDetail.reflow then rpDetail.reflow() end
        end
        viewport:EnableMouseWheel(true)
        local function ScrollContent(_, delta)
            viewport:SetVerticalScroll(math.max(0, math.min(viewport:GetVerticalScrollRange(),
                viewport:GetVerticalScroll() - delta * rowHeight * 3)))
        end
        viewport:SetScript("OnMouseWheel", ScrollContent)
        reagentListHost:SetScript("OnMouseWheel", ScrollContent)
        outputListHost:SetScript("OnMouseWheel", ScrollContent)

        local hiddenMetrics = {
            [rpDetail.metCostFS] = true,
            [rpDetail.metStatsFS] = true, [rpDetail.metGearFS] = true,
            [rpDetail.metNodeBonusesFS] = true,
        }
        local function Place(widget, parent, x, yOff, width)
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, yOff)
            if width then widget:SetWidth(math.max(1, width)) end
        end
        rpDetail.reflow = function()
            local width = math.max(250, viewport:GetWidth())
            content:SetWidth(width)
            nameFS:SetWidth(width)
            profFS:SetWidth(width)
            notesFS:SetWidth(width)
            local top = -padding
            Place(nameFS, content, 0, top, width)
            top = top - math.max(18, nameFS:GetStringHeight()) - 6
            Place(profFS, content, 0, top, width)
            top = top - math.max(14, profFS:GetStringHeight()) - 6
            Place(notesFS, content, 0, top, width)
            if notesFS:IsShown() then top = top - notesFS:GetStringHeight() - 6 end
            Place(bodyRoot, content, 0, top, width)
            local cursor = -6
            for _, metric in ipairs(metricRows) do
                local shown = not hiddenMetrics[metric.value] or rpDetail.infoExpanded
                metric.value:SetShown(shown and true or false)
                metric.label:SetShown(shown and true or false)
                local tooltip = metricTooltips[metric.originalY]
                if tooltip then tooltip:SetShown(shown and true or false) end
                if shown then
                    local labelW = math.min(130, width * 0.43)
                    Place(metric.label, bodyRoot, 0, cursor, labelW)
                    Place(metric.value, bodyRoot, labelW + 6, cursor, width - labelW - 6)
                    metric.value:SetWordWrap(true)
                    metric.label:SetJustifyH("LEFT")
                    metric.label:SetWordWrap(true)
                    local h = math.max(20, metric.value:GetStringHeight() + 4, metric.label:GetStringHeight() + 4)
                    if tooltip then Place(tooltip, bodyRoot, 0, cursor, width); tooltip:SetHeight(h) end
                    cursor = cursor - h
                end
            end
            Place(missingFS, bodyRoot, 0, cursor, width)
            missingFS:SetWordWrap(true)
            if missingFS:IsShown() then cursor = cursor - missingFS:GetStringHeight() - 6 end
            cursor = cursor - 10
            Place(reagHdr, bodyRoot, 0, cursor)
            -- Align the batch input with its Materials section heading.
            craftsOKBtn:ClearAllPoints()
            craftsOKBtn:SetPoint("TOPRIGHT", bodyRoot, "TOPRIGHT", 0, cursor + 2)
            cursor = cursor - 28
            local reagentH = math.max(1, rpDetail.reagentListHost:GetHeight()) + 30
            Place(reagentSection, bodyRoot, 0, cursor, width)
            reagentSection:SetHeight(reagentH)
            reagentScroll:ClearAllPoints()
            reagentScroll:SetPoint("TOPLEFT", reagentSection, "TOPLEFT", 0, -22)
            reagentScroll:SetPoint("BOTTOMRIGHT", reagentSection, "BOTTOMRIGHT", 0, 8)
            if reagentScroll.ScrollBar then reagentScroll.ScrollBar:Hide() end
            cursor = cursor - reagentH - 12
            Place(outHdr, bodyRoot, 0, cursor)
            cursor = cursor - 22
            local outputH = math.max(1, rpDetail.outputListHost:GetHeight()) + 30
            Place(outputSection, bodyRoot, 0, cursor, width)
            outputSection:SetHeight(outputH)
            outputScroll:ClearAllPoints()
            outputScroll:SetPoint("TOPLEFT", outputSection, "TOPLEFT", 0, -22)
            outputScroll:SetPoint("BOTTOMRIGHT", outputSection, "BOTTOMRIGHT", 0, 8)
            if outputScroll.ScrollBar then outputScroll.ScrollBar:Hide() end
            bodyRoot:SetHeight(-cursor + outputH)
            content:SetHeight(-top - cursor + outputH + 8)
            local range = math.max(0, content:GetHeight() - viewport:GetHeight())
            viewport:SetVerticalScroll(math.min(viewport:GetVerticalScroll(), range))
            if viewport.ScrollBar then viewport.ScrollBar:SetShown(range > 1) end

            local nameW = math.max(80, width - 48 - 48 - 120)
            local priceW = width - nameW - 96
            reagentListHost:SetWidth(width)
            outputListHost:SetWidth(width)
            for i, header in ipairs(columnHeaders) do
                local offsets = { 0, nameW, nameW + 48, nameW + 96, 0, nameW, nameW + 48 }
                local widths = { nameW, 48, 48, priceW, nameW, 48, priceW + 48 }
                Place(header, i <= 4 and reagentSection or outputSection, offsets[i], -4, widths[i])
            end
            for _, row in ipairs(rpDetail.reagentRows) do
                row:SetWidth(width)
                row.nameFS:SetWidth(nameW - 8)
                row.qtyFS:ClearAllPoints(); row.qtyFS:SetPoint("LEFT", row, "LEFT", nameW, 0)
                row.qtyEB:ClearAllPoints(); row.qtyEB:SetPoint("LEFT", row, "LEFT", nameW, 0)
                row.needFS:ClearAllPoints(); row.needFS:SetPoint("LEFT", row, "LEFT", nameW + 48, 0)
                row.priceFS:ClearAllPoints(); row.priceFS:SetPoint("LEFT", row, "LEFT", nameW + 96, 0)
                row.priceFS:SetWidth(priceW)
            end
            for _, row in ipairs(rpDetail.outputRows) do
                row:SetWidth(width)
                row.nameFS:SetWidth(nameW - 8)
                row.qtyFS:ClearAllPoints(); row.qtyFS:SetPoint("LEFT", row, "LEFT", nameW, 0)
                row.priceFS:ClearAllPoints(); row.priceFS:SetPoint("LEFT", row, "LEFT", nameW + 48, 0)
                row.priceFS:SetWidth(priceW + 48)
            end
        end
        root:HookScript("OnSizeChanged", function() rpDetail.reflow() end)
        btnScanStrat:ClearAllPoints()
        btnScanStrat:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", padding, 12)
        btnScanStrat:SetSize(90, 28)
        btnVIBreakdown:SetSize(94, 28)
        btnShop:SetSize(70, 28)
        btnVIBreakdown:ClearAllPoints()
        btnVIBreakdown:SetPoint("LEFT", btnScanStrat, "RIGHT", 6, 0)
        btnShop:ClearAllPoints()
        btnShop:SetPoint("LEFT", btnVIBreakdown, "RIGHT", 6, 0)
        btnOpenRecipe:SetSize(130, 28)
        btnOpenRecipe:ClearAllPoints()
        btnOpenRecipe:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -padding, 12)
        rpDetail.reflow()
    end

    return root
end
