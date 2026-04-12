-- GoldAdvisorMidnight/UI/MainWindowV2Center.lua
-- Shared center-panel builder and row rendering for MainWindowV2.
-- Module: GAM.UI.MainWindowV2Center

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local CenterUI = {}
GAM.UI.MainWindowV2Center = CenterUI

local function Noop()
end

function CenterUI.MakeRowFrame(args, parent, idx)
    local rowHeight = args.rowHeight or 22
    local stratIconWidth = args.stratIconWidth or 20
    local applyFontSize = args.applyFontSize or Noop
    local applyTextShadow = args.applyTextShadow or Noop
    local toggleFavorite = args.toggleFavorite or Noop
    local rebuildList = args.rebuildList or Noop
    local refreshRows = args.refreshRows or Noop
    local isFavorite = args.isFavorite or function() return false end
    local isClickInFavoriteGutter = args.isClickInFavoriteGutter or function() return false end
    local selectStrategyByID = args.selectStrategyByID or Noop
    local getStratByID = args.getStratByID or function() return nil end
    local getLocalizer = args.getLocalizer or function() return GAM.L end

    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(rowHeight)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(idx - 1) * rowHeight)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")
    row._rowIndex = idx

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -1)
    bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 1)
    bg:SetColorTexture(0.10, 0.10, 0.10, (idx % 2 == 1) and 0.55 or 0.28)
    row.bg = bg

    local accent = row:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
    accent:SetWidth(3)
    accent:SetColorTexture(1.0, 0.82, 0.0, 0.0)
    row.accent = accent

    local star = row:CreateTexture(nil, "OVERLAY")
    star:SetSize(14, 14)
    star:SetPoint("LEFT", row, "LEFT", 4, 0)
    star:SetAtlas("Professions-ChatIcon-Quality-Tier3", false)
    row.star = star

    local starBtn = CreateFrame("Button", nil, row)
    starBtn:SetSize(stratIconWidth, rowHeight)
    starBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
    starBtn:RegisterForClicks("LeftButtonUp")
    starBtn:SetScript("OnClick", function(self)
        local parentRow = self:GetParent()
        if not parentRow or not parentRow.stratID then return end
        toggleFavorite(parentRow.stratID)
        rebuildList()
        refreshRows()
    end)
    starBtn:SetScript("OnEnter", function(self)
        local parentRow = self:GetParent()
        if not parentRow or not parentRow.stratID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(isFavorite(parentRow.stratID) and "Remove Favorite" or "Add Favorite", 1, 1, 1)
        GameTooltip:AddLine("Click the star to toggle favorite without reordering issues.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    starBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    row.starBtn = starBtn

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    applyFontSize(nameText, 11)
    applyTextShadow(nameText)
    row.nameText = nameText

    local profSubText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profSubText:SetJustifyH("LEFT")
    profSubText:SetTextColor(0.65, 0.65, 0.65, 0.85)
    profSubText:SetWordWrap(false)
    applyFontSize(profSubText, 10)
    applyTextShadow(profSubText, 0.75)
    row.profSubText = profSubText

    local profText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profText:SetJustifyH("LEFT")
    profText:SetWordWrap(false)
    applyFontSize(profText, 10)
    applyTextShadow(profText, 0.75)
    row.profText = profText

    local profitText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profitText:SetJustifyH("CENTER")
    profitText:SetWordWrap(false)
    applyFontSize(profitText, 10)
    applyTextShadow(profitText)
    row.profitText = profitText

    local roiText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    roiText:SetJustifyH("CENTER")
    roiText:SetWordWrap(false)
    applyFontSize(roiText, 10)
    applyTextShadow(roiText)
    row.roiText = roiText

    local missingText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    missingText:SetJustifyH("LEFT")
    missingText:SetTextColor(1, 0.6, 0)
    missingText:SetWordWrap(false)
    applyFontSize(missingText, 10)
    applyTextShadow(missingText)
    row.missingText = missingText

    row.missingPriceList = {}

    row:SetScript("OnClick", function(self, btn)
        if btn ~= "LeftButton" or not self.stratID then return end
        if isClickInFavoriteGutter(self) then
            toggleFavorite(self.stratID)
            rebuildList()
            refreshRows()
            return
        end
        selectStrategyByID(self.stratID)
        refreshRows()
    end)

    row:SetScript("OnDoubleClick", function(self)
        if not self.stratID then return end
        if isClickInFavoriteGutter(self) then return end
        toggleFavorite(self.stratID)
        rebuildList()
        refreshRows()
    end)

    row:SetScript("OnEnter", function(self)
        if not self.stratID then return end
        local strat = getStratByID(self.stratID)
        if not strat then return end
        local hasNotes = strat.notes and strat.notes ~= ""
        local hasMissing = self.missingPriceList and #self.missingPriceList > 0
        if not hasNotes and not hasMissing then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(strat.stratName, 1, 1, 1)
        if hasNotes then
            GameTooltip:AddLine(strat.notes, 0.8, 0.8, 0.8, true)
        end
        if hasMissing then
            GameTooltip:AddLine("Missing prices:", 1, 0.6, 0)
            for _, name in ipairs(self.missingPriceList) do
                GameTooltip:AddLine("  " .. name, 1, 0.8, 0.3)
            end
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

function CenterUI.PopulateRow(args, row, strat)
    local L = (args.getLocalizer and args.getLocalizer()) or GAM.L
    local isFavorite = args.isFavorite or function() return false end
    local getListMetric = args.getListMetric or function() return nil end
    local formatPrice = args.formatPrice or tostring
    local selectedStratID = args.getSelectedStratID and args.getSelectedStratID() or nil
    local theme = args.getThemeDef and args.getThemeDef() or nil

    row.stratID = strat.id
    local favorite = isFavorite(strat.id)
    local selected = strat.id == selectedStratID
    row.star:SetVertexColor(favorite and 1 or 0.5, favorite and 0.85 or 0.5, favorite and 0 or 0.5, 1)
    row.star:SetAlpha(favorite and 1 or 0.35)

    row.nameText:SetText(strat.stratName)
    row.profText:SetText(strat.profession)
    row.profSubText:SetText("")

    local metrics = getListMetric(strat)
    local noPrice = "|cff888888" .. (L and L["NO_PRICE"] or "—") .. "|r"
    if metrics then
        row.profitText:SetText(metrics.profit
            and ((metrics.profit >= 0 and "|cff55ff55" or "|cffff5555") .. formatPrice(metrics.profit) .. "|r")
            or noPrice)
        row.roiText:SetText(metrics.roi
            and ((metrics.roi >= 0 and "|cff55ff55" or "|cffff5555") .. string.format("%.1f%%", metrics.roi) .. "|r")
            or "|cff888888—|r")
        if #metrics.missingPrices > 0 then
            row.missingText:SetText(L and L["MISSING_PRICES"] or "!")
            row.missingPriceList = metrics.missingPrices
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

    if row.bg and theme then
        local color = selected and theme.listRowSelected
            or ((row._rowIndex or 1) % 2 == 1 and theme.listRowOdd or theme.listRowEven)
        if color then
            row.bg:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        end
    end
    if row.accent then
        if selected then
            row.accent:SetColorTexture(1.0, 0.82, 0.0, 0.90)
        elseif favorite then
            row.accent:SetColorTexture(1.0, 0.82, 0.0, 0.42)
        else
            row.accent:SetColorTexture(1.0, 0.82, 0.0, 0.0)
        end
    end

    if selected then
        row:LockHighlight()
    else
        row:UnlockHighlight()
    end
    row:Show()
end

function CenterUI.RefreshRows(args)
    local frame = args.frame
    local rowFrames = args.rowFrames or {}
    local filteredList = args.filteredList or {}
    local scrollOffset = args.scrollOffset or 0
    local visibleRows = args.getVisibleListRows and args.getVisibleListRows() or #rowFrames
    local populateRow = args.populateRow or Noop
    local setSuppressScrollCallback = args.setSuppressScrollCallback or Noop
    local L = (args.getLocalizer and args.getLocalizer()) or GAM.L

    if not frame then
        return scrollOffset
    end

    for i, row in ipairs(rowFrames) do
        local strat = filteredList[scrollOffset + i]
        if strat and i <= visibleRows then
            populateRow(row, strat)
        else
            row:Hide()
            row.stratID = nil
        end
    end

    if frame.scrollBar then
        local max = math.max(0, #filteredList - visibleRows)
        if scrollOffset > max then
            scrollOffset = max
        end
        frame.scrollBar:SetMinMaxValues(0, max)
        setSuppressScrollCallback(true)
        frame.scrollBar:SetValue(scrollOffset)
        setSuppressScrollCallback(false)
        frame.scrollBar:SetShown(max > 0)
    end

    if frame.statusCountText then
        frame.statusCountText:SetText(string.format(L and L["STATUS_STRAT_COUNT"] or "%d strategies", #filteredList))
    end

    return scrollOffset
end

function CenterUI.RefreshBestStratCard(args)
    local bestStratCard = args.bestStratCard

    if not bestStratCard then
        return
    end
end

function CenterUI.Build(args)
    local frame = args.frame
    local centerPanel = args.centerPanel
    local guidePanel = args.guidePanel or centerPanel
    local listPanel = args.listPanel or centerPanel
    local createShell = args.createShell or function(parent) return parent, parent end
    local themeRefs = args.themeRefs or {}
    local L = args.localizer or GAM.L or {}
    local gold = (args.colors and args.colors.gold) or { 1.0, 0.82, 0.0 }
    local rule = (args.colors and args.colors.rule) or { 0.7, 0.57, 0.0, 0.7 }
    local bodyTextColor = args.bodyTextColor or { 0.85, 0.82, 0.76, 1.0 }
    local mutedTextColor = args.mutedTextColor or bodyTextColor
    local applyFontSize = args.applyFontSize or Noop
    local applyTextShadow = args.applyTextShadow or Noop
    local cardHeight = args.cardHeight or 120
    local listSectionHeight = args.listSectionHeight or 22
    local headerHeight = args.headerHeight or 20
    local listTopPad = args.listTopPad or (cardHeight + listSectionHeight + headerHeight + 16)
    local headerTopOffset = args.headerTopOffset
    local layoutMode = args.layoutMode or "classic"
    local columnHeaderColor = (layoutMode == "soft") and mutedTextColor or gold
    local visibleRows = args.visibleRows or 30
    local getVisibleListRows = args.getVisibleListRows or function() return visibleRows end
    local getFilteredList = args.getFilteredList or function() return {} end
    local getScrollOffset = args.getScrollOffset or function() return 0 end
    local setScrollOffset = args.setScrollOffset or Noop
    local getSuppressScrollCallback = args.getSuppressScrollCallback or function() return false end
    local refreshRows = args.refreshRows or Noop
    local rebuildList = args.rebuildList or Noop
    local getSortKey = args.getSortKey or function() return "roi" end
    local setSortKey = args.setSortKey or Noop
    local getSortAsc = args.getSortAsc or function() return true end
    local setSortAsc = args.setSortAsc or Noop
    local makeRowArgs = args.makeRowArgs or {}
    local dismissOnboarding = args.dismissOnboarding or Noop
    local doScan = args.doScan or Noop

    local bestStratCardShell, bestStratCard
    if layoutMode == "soft" then
        bestStratCardShell = guidePanel
        bestStratCard = guidePanel
    else
        bestStratCardShell, bestStratCard = createShell(centerPanel, "card", { left = 4, right = 4, top = 4, bottom = 4 })
        bestStratCardShell:SetHeight(cardHeight)
        bestStratCardShell:SetPoint("TOPLEFT", centerPanel, "TOPLEFT", 4, -4)
        bestStratCardShell:SetPoint("TOPRIGHT", centerPanel, "TOPRIGHT", -4, -4)
    end
    if bestStratCardShell.EnableMouse then
        bestStratCardShell:EnableMouse(false)
    end

    local guideLeft = (layoutMode == "soft") and 18 or 22
    local guideRight = (layoutMode == "soft") and 18 or 22
    local guideTop = (layoutMode == "soft") and -18 or -18
    local guideRuleTop = (layoutMode == "soft") and -46 or -42
    local guideBottom = (layoutMode == "soft") and 16 or 16

    local infoTitle = bestStratCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    infoTitle:SetPoint("TOPLEFT", bestStratCard, "TOPLEFT", guideLeft, guideTop)
    infoTitle:SetPoint("TOPRIGHT", bestStratCard, "TOPRIGHT", -guideRight, guideTop)
    infoTitle:SetJustifyH("LEFT")
    infoTitle:SetText((L and L["V2_GUIDE_TITLE"]) or "Before You Craft")
    infoTitle:SetTextColor(gold[1], gold[2], gold[3])
    applyFontSize(infoTitle, (layoutMode == "soft") and 17 or 15)
    applyTextShadow(infoTitle)
    bestStratCard.infoTitleFS = infoTitle
    themeRefs.infoPanelTitle = infoTitle

    local infoRule = bestStratCard:CreateTexture(nil, "ARTWORK")
    infoRule:SetHeight(1)
    infoRule:SetPoint("TOPLEFT", bestStratCard, "TOPLEFT", guideLeft, guideRuleTop)
    infoRule:SetPoint("TOPRIGHT", bestStratCard, "TOPRIGHT", -guideRight, guideRuleTop)
    infoRule:SetColorTexture(rule[1], rule[2], rule[3], rule[4] or 0.7)
    themeRefs.infoPanelRule = infoRule

    local infoBody = bestStratCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoBody:SetPoint("TOPLEFT", infoRule, "BOTTOMLEFT", 0, -10)
    infoBody:SetPoint("TOPRIGHT", infoRule, "BOTTOMRIGHT", 0, -10)
    infoBody:SetPoint("BOTTOMLEFT", bestStratCard, "BOTTOMLEFT", guideLeft, guideBottom)
    infoBody:SetPoint("BOTTOMRIGHT", bestStratCard, "BOTTOMRIGHT", -guideRight, guideBottom)
    infoBody:SetJustifyH("LEFT")
    infoBody:SetJustifyV("TOP")
    infoBody:SetWordWrap(true)
    infoBody:SetText((L and L["V2_GUIDE_BODY"]) or "Profit uses average outcomes from your current setup.\nSmall craft counts can land above or below these estimates.\nCheck prices, ranks, and missing inputs before you commit.")
    infoBody:SetTextColor(bodyTextColor[1], bodyTextColor[2], bodyTextColor[3], bodyTextColor[4] or 1)
    applyFontSize(infoBody, (layoutMode == "soft") and 11 or 11)
    applyTextShadow(infoBody, (layoutMode == "soft") and 0.12 or 0.75)
    bestStratCard.infoBodyFS = infoBody
    themeRefs.infoPanelBody = infoBody

    local colHeaderBtns = {}
    for i = 1, 5 do
        local btn = CreateFrame("Button", nil, listPanel)
        btn:SetHeight(headerHeight)
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("CENTER", btn, "CENTER", 0, 2)
        lbl:SetTextColor(columnHeaderColor[1], columnHeaderColor[2], columnHeaderColor[3], columnHeaderColor[4] or 1)
        btn.labelFS = lbl
        btn:SetScript("OnClick", function(self)
            if not self.sortKeyV2 then return end
            if getSortKey() == self.sortKeyV2 then
                setSortAsc(not getSortAsc())
            else
                setSortKey(self.sortKeyV2)
                setSortAsc(true)
            end
            rebuildList()
            refreshRows()
        end)
        colHeaderBtns[i] = btn
    end

    local listTitleTop = (layoutMode == "soft") and 10 or (cardHeight + 14)
    local listHeaderTop = headerTopOffset or (cardHeight + listSectionHeight + 12)
    local listHostTop = (layoutMode == "soft") and (listHeaderTop + headerHeight + 8) or (listTopPad + 4)

    local hdrSep = listPanel:CreateTexture(nil, "ARTWORK")
    hdrSep:SetHeight(1)
    hdrSep:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 8, -(listHeaderTop + headerHeight + 4))
    hdrSep:SetPoint("TOPRIGHT", listPanel, "TOPRIGHT", -8, -(listHeaderTop + headerHeight + 4))
    hdrSep:SetColorTexture(rule[1], rule[2], rule[3], rule[4] or 0.7)
    themeRefs.headerSep = hdrSep

    local listSectionTitle = listPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    listSectionTitle:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 8, -listTitleTop)
    listSectionTitle:SetText((L and L["V2_ALL_STRATS"]) or "All Strategies")
    listSectionTitle:SetTextColor(gold[1], gold[2], gold[3])
    applyTextShadow(listSectionTitle)

    local listHost = CreateFrame("Frame", nil, listPanel)
    listHost:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 4, -listHostTop)
    listHost:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -24, 0)
    listHost:SetClipsChildren(true)

    local rowFrames = {}
    for i = 1, visibleRows do
        rowFrames[i] = CenterUI.MakeRowFrame(makeRowArgs, listHost, i)
        rowFrames[i]:Hide()
    end

    local scrollBar = CreateFrame("Slider", "GAMMainScrollBarV2", frame)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetWidth(16)
    scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    scrollBar:GetThumbTexture():SetSize(16, 16)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValue(0)
    scrollBar:SetValueStep(1)
    scrollBar:SetObeyStepOnDrag(true)
    scrollBar:SetScript("OnValueChanged", function(self, val)
        if getSuppressScrollCallback() then return end
        setScrollOffset(math.floor(val + 0.5))
        refreshRows()
    end)

    listHost:EnableMouseWheel(true)
    listHost:SetScript("OnMouseWheel", function(_, delta)
        local max = math.max(0, #getFilteredList() - getVisibleListRows())
        local nextOffset = math.max(0, math.min(max, getScrollOffset() - delta * 3))
        setScrollOffset(nextOffset)
        scrollBar:SetValue(nextOffset)
        refreshRows()
    end)

    local onboardingOverlay = CreateFrame("Frame", nil, listPanel, "BackdropTemplate")
    onboardingOverlay:SetAllPoints(listPanel)
    onboardingOverlay:SetFrameLevel(listPanel:GetFrameLevel() + 20)
    onboardingOverlay:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", tile = true, tileSize = 8 })
    onboardingOverlay:SetBackdropColor(0, 0, 0, 0.85)
    onboardingOverlay:EnableMouse(true)
    onboardingOverlay:Hide()

    local owTitle = onboardingOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    owTitle:SetPoint("TOP", onboardingOverlay, "TOP", 0, -40)
    owTitle:SetText((L and L["V2_ONBOARD_TITLE"]) or "Welcome to Gold Advisor Midnight")
    owTitle:SetTextColor(gold[1], gold[2], gold[3])

    local prevAnchor = owTitle
    for _, stepText in ipairs({
        (L and L["V2_ONBOARD_STEP_1"]) or "1. Open the Auction House.",
        (L and L["V2_ONBOARD_STEP_2"]) or "2. Click Scan Auction House to fetch prices.",
        (L and L["V2_ONBOARD_STEP_3"]) or "3. Browse strategies sorted by ROI or profit.",
    }) do
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
    owBtnGotIt:SetText((L and L["BTN_GOT_IT"]) or "Got It")
    owBtnGotIt:SetScript("OnClick", dismissOnboarding)

    local owBtnScan = CreateFrame("Button", nil, onboardingOverlay, "UIPanelButtonTemplate")
    owBtnScan:SetSize(140, 26)
    owBtnScan:SetPoint("BOTTOM", onboardingOverlay, "BOTTOM", 50, 30)
    owBtnScan:SetText(L["BTN_SCAN_ALL"])
    owBtnScan:SetScript("OnClick", function()
        dismissOnboarding()
        doScan()
    end)

    return {
        bestStratCardShell = bestStratCardShell,
        bestStratCard = bestStratCard,
        colHeaderBtns = colHeaderBtns,
        listHost = listHost,
        rowFrames = rowFrames,
        scrollBar = scrollBar,
        onboardingOverlay = onboardingOverlay,
    }
end
