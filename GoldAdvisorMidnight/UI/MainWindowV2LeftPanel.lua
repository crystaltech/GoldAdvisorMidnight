-- GoldAdvisorMidnight/UI/MainWindowV2LeftPanel.lua
-- Shared left-panel builder for MainWindowV2.
-- Module: GAM.UI.MainWindowV2LeftPanel

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local LeftPanelUI = {}
GAM.UI.MainWindowV2LeftPanel = LeftPanelUI

local function Noop()
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

    editBox:SetScript("OnEnterPressed", function()
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

function LeftPanelUI.Build(args)
    local panel = args.panel
    local themeRefs = args.themeRefs or {}
    local leftPanelChecks = args.leftPanelChecks or {}
    local L = args.localizer or GAM.L or {}
    local C = args.constants or GAM.C or {}
    local panelWidth = args.panelWidth or C.LEFT_PANEL_W or 190
    local LP = args.padding or 10
    local gold = (args.colors and args.colors.gold) or { 1.0, 0.82, 0.0 }
    local rule = (args.colors and args.colors.rule) or { 0.7, 0.57, 0.0, 0.7 }
    local layoutMode = args.layoutMode or "classic"
    local bodyTextColor = args.bodyTextColor or { 0.85, 0.82, 0.76, 1.0 }
    local mutedTextColor = args.mutedTextColor or bodyTextColor
    local applyFontSize = args.applyFontSize or Noop
    local attachButtonTooltip = args.attachButtonTooltip or Noop
    local getOpts = args.getOpts or function() return {} end
    local setOption = args.setOption or Noop
    local clampFillQtyValue = args.clampFillQtyValue or tonumber
    local clampStatPercentValue = args.clampStatPercentValue or tonumber
    local formatStatPercentValue = args.formatStatPercentValue or tostring
    local buildPlayerProfessionSet = args.buildPlayerProfessionSet or function() return {} end
    local hasAnyEntries = args.hasAnyEntries or function(set) return set and next(set) ~= nil end
    local getActiveColumnConfig = args.getActiveColumnConfig or function() return nil end
    local getSelectedFormulaProfile = args.getSelectedFormulaProfile or function() return nil, nil, nil end
    local rebuildList = args.rebuildList or Noop
    local refreshRows = args.refreshRows or Noop
    local relayoutPanels = args.relayoutPanels or Noop
    local refreshBestStratCard = args.refreshBestStratCard or Noop
    local refreshVisibleDetail = args.refreshVisibleDetail or Noop
    local hideBreakdownWindow = args.hideBreakdownWindow or Noop
    local doScan = args.doScan or Noop
    local scanSelectedStrat = args.scanSelectedStrat or Noop
    local toggleShoppingSync = args.toggleShoppingSync or Noop
    local pushSelectedToCraftSim = args.pushSelectedToCraftSim or Noop
    local showARPExport = args.showARPExport or Noop
    local getFilterPatch = args.getFilterPatch or function() return GAM.C.DEFAULT_PATCH end
    local getFilterMode = args.getFilterMode or function() return "all" end
    local setFilterMode = args.setFilterMode or Noop
    local getFilterProf = args.getFilterProf or function() return "All" end
    local setFilterProf = args.setFilterProf or Noop
    local getFilterProfSet = args.getFilterProfSet or function() return nil end
    local setFilterProfSet = args.setFilterProfSet or Noop
    local getFilterProfSingle = args.getFilterProfSingle or function() return "All" end
    local setFilterProfSingle = args.setFilterProfSingle or Noop
    local setActiveColConfig = args.setActiveColConfig or Noop
    local softInk = layoutMode == "soft"
    local labelColor = softInk and bodyTextColor or { 0.9, 0.9, 0.9, 1.0 }
    local helperColor = softInk and mutedTextColor or { 0.65, 0.65, 0.65, 1.0 }
    local allFilterText = (L and L["V2_ALL_FILTER"]) or "All"

    local charNameFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    charNameFS:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, -40)
    charNameFS:SetWidth(panelWidth - LP * 2)
    charNameFS:SetJustifyH("LEFT")
    charNameFS:SetTextColor(gold[1], gold[2], gold[3])
    charNameFS:SetText(UnitName("player") or "-")
    applyFontSize(charNameFS, softInk and 12 or 11)

    local realmFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    realmFS:SetPoint("TOPLEFT", charNameFS, "BOTTOMLEFT", 0, -2)
    realmFS:SetWidth(panelWidth - LP * 2)
    realmFS:SetJustifyH("LEFT")
    realmFS:SetTextColor(helperColor[1], helperColor[2], helperColor[3], helperColor[4] or 1)
    realmFS:SetText(GetRealmName() or "-")
    applyFontSize(realmFS, softInk and 11 or 10)

    local lpRule = panel:CreateTexture(nil, "ARTWORK")
    lpRule:SetHeight(1)
    lpRule:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, -78)
    lpRule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LP, -78)
    lpRule:SetColorTexture(rule[1], rule[2], rule[3], 0.4)
    themeRefs.leftRule = lpRule

    local filterLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, -88)
    filterLbl:SetText(L["FILTER_PROFESSION"])
    filterLbl:SetTextColor(gold[1], gold[2], gold[3])
    applyFontSize(filterLbl, 11)

    local segW = math.floor((panelWidth - LP * 2 - 4) / 2)
    local btnFilterMine = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnFilterMine:SetSize(segW, 22)
    btnFilterMine:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, -108)
    btnFilterMine:SetText((L and L["V2_MY_PROFS"]) or "My Profs")

    local btnFilterAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnFilterAll:SetSize(segW, 22)
    btnFilterAll:SetPoint("TOPLEFT", panel, "TOPLEFT", LP + segW + 4, -108)
    btnFilterAll:SetText((L and L["V2_ALL_FILTER"]) or "All")

    panel.btnFilterAll = btnFilterAll
    panel.btnFilterMine = btnFilterMine

    attachButtonTooltip(
        btnFilterMine,
        (L and L["TT_MINE_TITLE"]) or "My Professions Filter",
        (L and L["TT_MINE_BODY"]) or "Show only strategies for professions you have learned."
    )
    attachButtonTooltip(
        btnFilterAll,
        (L and L["TT_ALL_TITLE"]) or "Show All Strategies",
        (L and L["TT_ALL_BODY"]) or "Show all crafting strategies regardless of profession."
    )

    local ddProf = CreateFrame("Frame", "GAMMainV2ProfDD", panel, "UIDropDownMenuTemplate")
    ddProf:SetPoint("TOPLEFT", panel, "TOPLEFT", LP - 16, -136)
    UIDropDownMenu_SetWidth(ddProf, panelWidth - LP * 2 - 20)

    local function InitProfDD()
        UIDropDownMenu_Initialize(ddProf, function()
            local pool = {}
            local filterMode = getFilterMode()
            local filterProfSet = getFilterProfSet()
            if filterMode == "mine" and hasAnyEntries(filterProfSet) then
                for prof in pairs(filterProfSet) do
                    pool[#pool + 1] = prof
                end
                table.sort(pool)
            else
                pool = GAM.Importer.GetAllProfessions(getFilterPatch()) or {}
            end
            table.insert(pool, 1, "All")
            for _, prof in ipairs(pool) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = (prof == "All") and allFilterText or prof
                info.value = prof
                info.func = function()
                    setFilterProfSingle(prof)
                    UIDropDownMenu_SetText(ddProf, (prof == "All") and allFilterText or prof)
                    rebuildList()
                    refreshRows()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        local currentProf = getFilterProfSingle()
        UIDropDownMenu_SetText(ddProf, (currentProf == "All") and allFilterText or currentProf)
    end

    panel.ddProf = ddProf
    panel.initProfDD = InitProfDD
    InitProfDD()

    local fillLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fillLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, -172)
    fillLbl:SetText((L and L["V2_FILL_QTY"]) or "Fill Qty")
    fillLbl:SetTextColor(gold[1], gold[2], gold[3])
    applyFontSize(fillLbl, 11)

    local fillQtyBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    fillQtyBox:SetSize(56, 20)
    fillQtyBox:SetAutoFocus(false)
    fillQtyBox:SetNumeric(true)
    fillQtyBox:SetText(tostring(getOpts().shallowFillQty or GAM.C.DEFAULT_FILL_QTY))
    fillQtyBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((L and L["TT_FILL_QTY_TITLE"]) or "Fill Quantity", 1, 1, 1)
        GameTooltip:AddLine((L and L["TT_FILL_QTY_BODY"]) or "Simulates buying this many units from the AH order book when pricing reagents.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    fillQtyBox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local fillQtyOKBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    fillQtyOKBtn:SetSize(28, 18)
    fillQtyOKBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LP, -168)
    fillQtyOKBtn:SetText(GetCommitButtonText(L))
    fillQtyOKBtn:Hide()
    fillQtyBox:SetPoint("RIGHT", fillQtyOKBtn, "LEFT", -4, 0)

    local fillRangeFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fillRangeFS:SetPoint("TOPLEFT", fillLbl, "BOTTOMLEFT", 0, -4)
    fillRangeFS:SetWidth(panelWidth - LP * 2)
    fillRangeFS:SetJustifyH("LEFT")
    fillRangeFS:SetText(string.format("%d-%d", GAM.C.MIN_FILL_QTY, GAM.C.MAX_FILL_QTY))
    fillRangeFS:SetTextColor(helperColor[1], helperColor[2], helperColor[3], helperColor[4] or 1)
    applyFontSize(fillRangeFS, softInk and 10 or 9)

    -- Single vertical integration toggle: enables all derivation paths atomically
    -- (herbs → pigments, ore → ingots, linen → bolts)
    local viOwn = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    viOwn:SetPoint("TOPLEFT", panel, "TOPLEFT", LP - 4, -210)
    local viActive = (getOpts().pigmentCostSource == "mill")
        or (getOpts().boltCostSource == "craft")
        or (getOpts().ingotCostSource == "craft")
    viOwn:SetChecked(viActive)

    local viLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    viLbl:SetPoint("LEFT", viOwn, "RIGHT", 0, 0)
    viLbl:SetWidth(panelWidth - LP * 2 - 20)
    viLbl:SetJustifyH("LEFT")
    viLbl:SetText((L and L["V2_VERTICAL_INTEGRATION"]) or "Use own items/crafts")
    viLbl:SetTextColor(labelColor[1], labelColor[2], labelColor[3], labelColor[4] or 1)
    applyFontSize(viLbl, softInk and 11 or 10)
    attachButtonTooltip(
        viOwn,
        (L and L["TT_VI_TITLE"]) or "Vertical Integration",
        (L and L["TT_VI_BODY"]) or "Price your intermediate materials from raw inputs (herbs \226\134\146 pigments, ore \226\134\146 ingots, linen \226\134\146 bolts). Disable to use AH prices for those items."
    )

    local viBreakdownOwn = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    viBreakdownOwn:SetPoint("TOPLEFT", panel, "TOPLEFT", LP + 10, -234)

    local viBreakdownLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    viBreakdownLbl:SetPoint("LEFT", viBreakdownOwn, "RIGHT", 0, 0)
    viBreakdownLbl:SetWidth(panelWidth - LP * 2 - 30)
    viBreakdownLbl:SetJustifyH("LEFT")
    viBreakdownLbl:SetText((L and L["V2_VI_BREAKDOWN"]) or "Show VI breakdown")
    viBreakdownLbl:SetTextColor(labelColor[1], labelColor[2], labelColor[3], labelColor[4] or 1)
    applyFontSize(viBreakdownLbl, softInk and 10 or 9)
    attachButtonTooltip(
        viBreakdownOwn,
        (L and L["TT_VI_BREAKDOWN_TITLE"]) or "Show VI Breakdown",
        (L and L["TT_VI_BREAKDOWN_BODY"]) or "Opens the VI breakdown window for the selected strategy while Use own items/crafts is enabled."
    )

    local function RefreshVIBreakdownToggle()
        local opts = getOpts()
        local viEnabled = (opts.pigmentCostSource == "mill")
            or (opts.boltCostSource == "craft")
            or (opts.ingotCostSource == "craft")
        local showBreakdown = opts.showVIBreakdown and true or false
        viBreakdownOwn:SetChecked(viEnabled and showBreakdown)
        viBreakdownOwn:SetEnabled(viEnabled)
        viBreakdownOwn:SetAlpha(viEnabled and 1 or 0.45)
        viBreakdownLbl:SetTextColor(
            labelColor[1],
            labelColor[2],
            labelColor[3],
            viEnabled and (labelColor[4] or 1) or 0.55
        )
    end

    local statSectionLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statSectionLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, -310)
    statSectionLbl:SetText((L and L["V2_CRAFT_STATS"]) or "Craft Stats")
    statSectionLbl:SetTextColor(gold[1], gold[2], gold[3])
    applyFontSize(statSectionLbl, 11)

    local statProfileFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statProfileFS:SetPoint("TOPLEFT", statSectionLbl, "BOTTOMLEFT", 0, -3)
    statProfileFS:SetWidth(panelWidth - LP * 2)
    statProfileFS:SetJustifyH("LEFT")
    statProfileFS:SetTextColor(helperColor[1], helperColor[2], helperColor[3], helperColor[4] or 1)
    applyFontSize(statProfileFS, softInk and 10 or 9)

    local statResLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statResLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, -340)
    statResLbl:SetText((L and L["V2_STAT_RES_LABEL"]) or "Res%")
    statResLbl:SetTextColor(labelColor[1], labelColor[2], labelColor[3], labelColor[4] or 1)
    applyFontSize(statResLbl, softInk and 11 or 10)

    local statResBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    statResBox:SetSize(56, 20)
    statResBox:SetAutoFocus(false)
    statResBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((L and L["TT_STAT_RES_TITLE"]) or "Resourcefulness %", 1, 1, 1)
        GameTooltip:AddLine((L and L["TT_STAT_RES_BODY"]) or "Your Resourcefulness stat from the profession window (%). Higher values reduce average reagent consumption.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    statResBox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local statResOKBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    statResOKBtn:SetSize(28, 18)
    statResOKBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LP, -336)
    statResOKBtn:SetText(GetCommitButtonText(L))
    statResOKBtn:Hide()
    statResBox:SetPoint("RIGHT", statResOKBtn, "LEFT", -4, 0)

    local statMultiLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statMultiLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, -364)
    statMultiLbl:SetText((L and L["V2_STAT_MULTI_LABEL"]) or "Multi%")
    statMultiLbl:SetTextColor(labelColor[1], labelColor[2], labelColor[3], labelColor[4] or 1)
    applyFontSize(statMultiLbl, softInk and 11 or 10)

    local statMultiBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    statMultiBox:SetSize(56, 20)
    statMultiBox:SetAutoFocus(false)
    statMultiBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((L and L["TT_STAT_MULTI_TITLE"]) or "Multicraft %", 1, 1, 1)
        GameTooltip:AddLine((L and L["TT_STAT_MULTI_BODY"]) or "Your Multicraft stat from the profession window (%). Higher values increase expected output quantity.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    statMultiBox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local statMultiOKBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    statMultiOKBtn:SetSize(28, 18)
    statMultiOKBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LP, -360)
    statMultiOKBtn:SetText(GetCommitButtonText(L))
    statMultiOKBtn:Hide()
    statMultiBox:SetPoint("RIGHT", statMultiOKBtn, "LEFT", -4, 0)

    local RefreshVisiblePanels
    local rankLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankLbl:SetText((L and L["V2_MATERIAL_RANK"]) or "Material Rank")
    rankLbl:SetTextColor(gold[1], gold[2], gold[3])
    applyFontSize(rankLbl, 11)

    local innerW = panelWidth - (LP * 2)
    local halfBtnGap = 4
    local halfBtnW = math.floor((innerW - halfBtnGap) / 2)
    local rpBtnH = 24
    local bottomBtnH = 28
    local primaryScanH = 34
    local bottomBtnGap = 4

    local scanRowTop = LP
    local selectedRowTop = scanRowTop + primaryScanH + bottomBtnGap
    local arpRowTop = selectedRowTop + bottomBtnH + bottomBtnGap
    local actionRowTop = arpRowTop + bottomBtnH + 6
    local rankDropTop = actionRowTop + rpBtnH + 6

    rankLbl:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LP, rankDropTop + 28)

    local ddRank = CreateFrame("Frame", "GAMMainV2RankDD", panel, "UIDropDownMenuTemplate")
    ddRank:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LP - 16, rankDropTop - 4)
    UIDropDownMenu_SetWidth(ddRank, innerW - 20)
    local rankTextMap = {
        lowest = (L and L["RANK_DD_LOWEST"]) or "R1 Mats",
        highest = (L and L["RANK_DD_HIGHEST"]) or "R2 Mats",
    }

    local function RefreshRankDropdown()
        local rankPolicy = getOpts().rankPolicy or "lowest"
        UIDropDownMenu_SetText(ddRank, rankTextMap[rankPolicy] or rankTextMap.lowest)
    end

    UIDropDownMenu_Initialize(ddRank, function()
        for _, value in ipairs({ "lowest", "highest" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = rankTextMap[value]
            info.value = value
            info.func = function()
                setOption("rankPolicy", value)
                RefreshRankDropdown()
                RefreshVisiblePanels()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    RefreshRankDropdown()
    panel.refreshRankDropdown = RefreshRankDropdown

    local selectedCraftSimBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    selectedCraftSimBtn:SetHeight(rpBtnH)
    selectedCraftSimBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LP, actionRowTop)
    selectedCraftSimBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMLEFT", LP + halfBtnW, actionRowTop)
    selectedCraftSimBtn:SetText((L and L["BTN_CRAFTSIM_SHORT"]) or "CraftSim")
    selectedCraftSimBtn:Disable()
    selectedCraftSimBtn:SetScript("OnClick", pushSelectedToCraftSim)
    attachButtonTooltip(
        selectedCraftSimBtn,
        (L and L["TT_CRAFTSIM_TITLE"]) or "Push Price Overrides to CraftSim",
        (L and L["TT_CRAFTSIM_WARN"]) or "Warning: This will overwrite any existing manual price overrides in CraftSim for all reagents in this strategy."
    )

    local selectedShoppingBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    selectedShoppingBtn:SetHeight(rpBtnH)
    selectedShoppingBtn:SetPoint("BOTTOMLEFT", selectedCraftSimBtn, "BOTTOMRIGHT", halfBtnGap, 0)
    selectedShoppingBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LP, actionRowTop)
    selectedShoppingBtn:SetText((L and L["BTN_SHOPPING_SHORT"]) or "Shopping")
    selectedShoppingBtn:Disable()
    selectedShoppingBtn:SetScript("OnClick", toggleShoppingSync)
    attachButtonTooltip(
        selectedShoppingBtn,
        (L and L["TT_SHOPPING_TITLE"]) or "Create Auctionator Shopping List",
        (L and L["TT_SHOPPING_BODY"]) or "Creates an Auctionator shopping list for the selected strategy's missing input items and keeps it synced as your bag counts change."
    )

    local function RefreshStatEditors()
        local opts = getOpts()
        local strat, profileKey, profileDef = getSelectedFormulaProfile()
        local hasRes = profileDef and profileDef.resKey
        local hasMulti = profileDef and profileDef.multiKey
        local enabled = profileDef and (hasRes or hasMulti)

        if profileKey and strat then
            statProfileFS:SetText(string.format("%s profile", strat.profession or profileKey))
        elseif profileKey then
            statProfileFS:SetText(string.format("%s profile", profileKey))
        else
            statProfileFS:SetText((L and L["V2_SELECT_FORMULA"]) or "Select a formula strategy")
        end

        statResLbl:SetShown(hasRes and true or false)
        statResBox:SetShown(hasRes and true or false)
        statMultiLbl:SetShown(hasMulti and true or false)
        statMultiBox:SetShown(hasMulti and true or false)

        if hasRes and opts then
            local resVal = opts[profileDef.resKey]
            if resVal == nil then
                resVal = profileDef.defaultRes or 0
            end
            if not statResBox:HasFocus() then
                local resText = formatStatPercentValue(resVal)
                statResBox:SetText(resText)
                statResBox._gamCommittedText = tostring(resText)
                RefreshCommitButton(statResBox)
            end
            statResBox:SetEnabled(true)
            statResBox:SetAlpha(1)
            statResLbl:SetTextColor(labelColor[1], labelColor[2], labelColor[3], labelColor[4] or 1)
        else
            statResBox:SetText("")
            statResBox._gamCommittedText = ""
            statResBox:SetEnabled(false)
            statResBox:SetAlpha(0.55)
            statResOKBtn:Hide()
            statResLbl:SetTextColor(helperColor[1], helperColor[2], helperColor[3], 0.75)
        end

        if hasMulti and opts then
            local multiVal = opts[profileDef.multiKey]
            if multiVal == nil then
                multiVal = profileDef.defaultMulti or 0
            end
            if not statMultiBox:HasFocus() then
                local multiText = formatStatPercentValue(multiVal)
                statMultiBox:SetText(multiText)
                statMultiBox._gamCommittedText = tostring(multiText)
                RefreshCommitButton(statMultiBox)
            end
            statMultiBox:SetEnabled(true)
            statMultiBox:SetAlpha(1)
            statMultiLbl:SetTextColor(labelColor[1], labelColor[2], labelColor[3], labelColor[4] or 1)
        else
            statMultiBox:SetText("")
            statMultiBox._gamCommittedText = ""
            statMultiBox:SetEnabled(false)
            statMultiBox:SetAlpha(0.55)
            statMultiOKBtn:Hide()
            statMultiLbl:SetTextColor(helperColor[1], helperColor[2], helperColor[3], 0.75)
        end

        statProfileFS:SetTextColor(enabled and 0.65 or 0.5, enabled and 0.65 or 0.5, enabled and 0.65 or 0.5, 1)
    end
    panel.refreshStatEditors = RefreshStatEditors

    RefreshVisiblePanels = function()
        rebuildList()
        refreshBestStratCard()
        refreshRows()
        RefreshRankDropdown()
        refreshVisibleDetail()
        RefreshStatEditors()
        RefreshVIBreakdownToggle()
    end
    panel.refreshVisiblePanels = RefreshVisiblePanels

    local function CommitFillQty()
        local opts = getOpts()
        opts.shallowFillQty = clampFillQtyValue(fillQtyBox:GetText())
        fillQtyBox:SetText(tostring(opts.shallowFillQty))
        fillQtyBox._gamCommittedText = tostring(fillQtyBox:GetText() or "")
        RefreshVisiblePanels()
    end
    AttachTransientCommitButton(fillQtyBox, fillQtyOKBtn, CommitFillQty)

    local function CommitStatEditors()
        local opts = getOpts()
        local _, _, profileDef = getSelectedFormulaProfile()
        if not profileDef then
            RefreshStatEditors()
            return
        end

        if profileDef.resKey then
            local fallbackRes = opts[profileDef.resKey]
            if fallbackRes == nil then
                fallbackRes = profileDef.defaultRes or 0
            end
            opts[profileDef.resKey] = clampStatPercentValue(statResBox:GetText(), fallbackRes)
            statResBox:SetText(formatStatPercentValue(opts[profileDef.resKey]))
            statResBox._gamCommittedText = tostring(statResBox:GetText() or "")
        end

        if profileDef.multiKey then
            local fallbackMulti = opts[profileDef.multiKey]
            if fallbackMulti == nil then
                fallbackMulti = profileDef.defaultMulti or 0
            end
            opts[profileDef.multiKey] = clampStatPercentValue(statMultiBox:GetText(), fallbackMulti)
            statMultiBox:SetText(formatStatPercentValue(opts[profileDef.multiKey]))
            statMultiBox._gamCommittedText = tostring(statMultiBox:GetText() or "")
        end

        RefreshVisiblePanels()
    end
    AttachTransientCommitButton(statResBox, statResOKBtn, CommitStatEditors)
    AttachTransientCommitButton(statMultiBox, statMultiOKBtn, CommitStatEditors)

    leftPanelChecks.viOwn = viOwn
    leftPanelChecks.viBreakdownOwn = viBreakdownOwn

    viOwn:SetScript("OnClick", function(self)
        local opts = getOpts()
        C_Timer.After(0, function()
            -- toggle all derivation paths atomically: all on or all off
            local newState = not ((opts.pigmentCostSource == "mill")
                or (opts.boltCostSource == "craft")
                or (opts.ingotCostSource == "craft"))
            opts.pigmentCostSource = newState and "mill" or "ah"
            opts.boltCostSource    = newState and "craft" or "ah"
            opts.ingotCostSource   = newState and "craft" or "ah"
            viOwn:SetChecked(newState)
            if not newState then
                hideBreakdownWindow()
            end
            RefreshVIBreakdownToggle()
            RefreshVisiblePanels()
        end)
    end)

    viBreakdownOwn:SetScript("OnClick", function(self)
        local showBreakdown = self:GetChecked() and true or false
        setOption("showVIBreakdown", showBreakdown)
        if not showBreakdown then
            hideBreakdownWindow()
        end
        RefreshVIBreakdownToggle()
        refreshVisibleDetail()
    end)

    RefreshVIBreakdownToggle()

    local function UpdateSegBtnColors()
        local isAll = getFilterMode() == "all"
        local goldR = isAll and gold[1] or 0.5
        local goldG = isAll and gold[2] or 0.5
        local goldB = isAll and gold[3] or 0.5
        local mineR = isAll and 0.5 or gold[1]
        local mineG = isAll and 0.5 or gold[2]
        local mineB = isAll and 0.5 or gold[3]
        if btnFilterAll:GetFontString() then
            btnFilterAll:GetFontString():SetTextColor(goldR, goldG, goldB)
        end
        if btnFilterMine:GetFontString() then
            btnFilterMine:GetFontString():SetTextColor(mineR, mineG, mineB)
        end
    end
    UpdateSegBtnColors()

    btnFilterAll:SetScript("OnClick", function()
        setFilterMode("all")
        setFilterProf("All")
        setFilterProfSet(nil)
        setFilterProfSingle("All")
        if panel.ddProf then
            UIDropDownMenu_SetText(panel.ddProf, allFilterText)
        end
        setActiveColConfig(getActiveColumnConfig())
        UpdateSegBtnColors()
        rebuildList()
        relayoutPanels()
    end)

    btnFilterMine:SetScript("OnClick", function()
        setFilterMode("mine")
        local filterProfSet = buildPlayerProfessionSet()
        setFilterProfSet(filterProfSet)
        setFilterProf(hasAnyEntries(filterProfSet) and "__mine__" or "All")
        if not hasAnyEntries(filterProfSet) then
            setFilterMode("all")
            setFilterProfSet(nil)
        end
        setFilterProfSingle("All")
        if panel.ddProf then
            UIDropDownMenu_SetText(panel.ddProf, allFilterText)
        end
        setActiveColConfig(getActiveColumnConfig())
        UpdateSegBtnColors()
        rebuildList()
        relayoutPanels()
    end)

    local scanBtnLeft = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scanBtnLeft:SetHeight(primaryScanH)
    scanBtnLeft:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LP, scanRowTop)
    scanBtnLeft:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LP, scanRowTop)
    scanBtnLeft:SetText(L["BTN_SCAN_ALL"])
    scanBtnLeft:SetScript("OnClick", doScan)
    attachButtonTooltip(
        scanBtnLeft,
        (L and L["TT_SCAN_ALL_TITLE"]) or "Scan All Items",
        (L and L["TT_SCAN_ALL_BODY"]) or "Queue all strategy items for AH price queries. The Auction House must be open."
    )

    local btnARP = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnARP:SetHeight(bottomBtnH)
    btnARP:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LP, arpRowTop)
    btnARP:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LP, arpRowTop)
    btnARP:SetText(L["BTN_ARP_EXPORT"] or "Spreadsheet Export")
    btnARP:SetScript("OnClick", showARPExport)

    local selectedScanBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    selectedScanBtn:SetHeight(bottomBtnH)
    selectedScanBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LP, selectedRowTop)
    selectedScanBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LP, selectedRowTop)
    selectedScanBtn:SetText((L and L["BTN_SCAN_SELECTED"]) or "Scan Selected Strat")
    selectedScanBtn:Disable()
    selectedScanBtn:SetAlpha(0.45)
    selectedScanBtn:SetScript("OnClick", scanSelectedStrat)

    local filterProfSet = buildPlayerProfessionSet()
    if hasAnyEntries(filterProfSet) then
        setFilterMode("mine")
        setFilterProf("__mine__")
    else
        setFilterMode("all")
        setFilterProf("All")
        filterProfSet = nil
    end
    setFilterProfSet(filterProfSet)
    setActiveColConfig(getActiveColumnConfig())

    return {
        scanBtnLeft = scanBtnLeft,
        selectedCraftSimBtn = selectedCraftSimBtn,
        selectedShoppingBtn = selectedShoppingBtn,
        selectedScanBtn = selectedScanBtn,
    }
end
