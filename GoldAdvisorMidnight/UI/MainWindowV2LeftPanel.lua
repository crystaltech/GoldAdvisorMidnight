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
    local showCooldowns = args.showCooldowns or Noop
    local showQuickBuy = args.showQuickBuy or Noop
    local getGearStatus = args.getGearStatus or function() return nil end
    local setGearMode = args.setGearMode or Noop
    local captureGearPreset = args.captureGearPreset or Noop
    local getFilterPatch = args.getFilterPatch or function() return GAM.C.DEFAULT_PATCH end
    local getFilterMode = args.getFilterMode or function() return "all" end
    local setFilterMode = args.setFilterMode or Noop
    local getFilterProf = args.getFilterProf or function() return "All" end
    local setFilterProf = args.setFilterProf or Noop
    local getFilterProfSet = args.getFilterProfSet or function() return nil end
    local setFilterProfSet = args.setFilterProfSet or Noop
    local getFilterProfSingleSet = args.getFilterProfSingleSet or function() return {} end
    local setFilterProfSingleSet = args.setFilterProfSingleSet or Noop
    local softInk = layoutMode == "soft"
    local labelColor = softInk and bodyTextColor or { 0.9, 0.9, 0.9, 1.0 }
    local helperColor = softInk and mutedTextColor or { 0.65, 0.65, 0.65, 1.0 }
    local allFilterText = (L and L["V2_ALL_FILTER"]) or "All"

    local charNameFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    charNameFS:SetPoint("TOP", panel, "TOP", 0, -40)
    charNameFS:SetWidth(panelWidth - LP * 2)
    charNameFS:SetJustifyH("CENTER")
    charNameFS:SetTextColor(gold[1], gold[2], gold[3])
    charNameFS:SetText(string.format("%s - %s",
        UnitName("player") or "-",
        GetRealmName() or "-"))
    applyFontSize(charNameFS, softInk and 12 or 11)

    local realmFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    realmFS:SetPoint("TOPLEFT", charNameFS, "BOTTOMLEFT", 0, -2)
    realmFS:SetWidth(panelWidth - LP * 2)
    realmFS:SetJustifyH("LEFT")
    realmFS:SetTextColor(helperColor[1], helperColor[2], helperColor[3], helperColor[4] or 1)
    realmFS:SetText(GetRealmName() or "-")
    applyFontSize(realmFS, softInk and 11 or 10)
    realmFS:Hide()

    local lpRule = panel:CreateTexture(nil, "ARTWORK")
    lpRule:SetHeight(1)
    lpRule:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, -62)
    lpRule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LP, -62)
    lpRule:SetColorTexture(rule[1], rule[2], rule[3], 0.4)
    themeRefs.leftRule = lpRule

    local filterLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, -74)
    filterLbl:SetText(L["FILTER_PROFESSION"])
    filterLbl:SetTextColor(gold[1], gold[2], gold[3])
    applyFontSize(filterLbl, 11)

    local segW = math.floor((panelWidth - LP * 2 - 4) / 2)
    local btnFilterMine = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnFilterMine:SetSize(segW, 22)
    btnFilterMine:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, -94)
    btnFilterMine:SetText((L and L["V2_MY_PROFS"]) or "My Profs")

    local btnFilterAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnFilterAll:SetSize(segW, 22)
    btnFilterAll:SetPoint("TOPLEFT", panel, "TOPLEFT", LP + segW + 4, -94)
    btnFilterAll:SetText((L and L["V2_ALL_FILTER"]) or "All")

    panel.btnFilterAll = btnFilterAll
    panel.btnFilterMine = btnFilterMine

    -- Keep this menu entirely addon-owned.  UIDropDownMenu uses shared global
    -- DropDownList frames; changing those frames from addon code can taint
    -- unrelated protected Blizzard UI (for example the Game Menu).
    local ddProf = CreateFrame("Button", "GAMMainV2ProfDD", panel, "UIPanelButtonTemplate")
    ddProf:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, -122)
    ddProf:SetSize(panelWidth - LP * 2, 22)

    local profMenu = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    profMenu:SetPoint("TOPLEFT", ddProf, "BOTTOMLEFT", 0, -2)
    profMenu:SetWidth(panelWidth - LP * 2)
    profMenu:SetFrameStrata("DIALOG")
    profMenu:SetFrameLevel(panel:GetFrameLevel() + 20)
    profMenu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    profMenu:SetBackdropColor(0.035, 0.035, 0.035, 0.98)
    profMenu:SetBackdropBorderColor(rule[1], rule[2], rule[3], 0.9)
    profMenu:Hide()

    local function UpdateProfDDText()
        local currentSet = getFilterProfSingleSet()
        if next(currentSet) == nil then
            ddProf:SetText(allFilterText .. "  v")
        else
            local names = {}
            for prof in pairs(currentSet) do
                names[#names + 1] = prof
            end
            table.sort(names)
            local text = (#names <= 2) and table.concat(names, ", ") or (#names .. " Profs")
            ddProf:SetText(text .. "  v")
        end
    end

    local CHECK_ON  = "|TInterface\\Buttons\\UI-CheckBox-Check:14:14|t "
    local CHECK_OFF = "|TInterface\\Buttons\\UI-CheckBox-Highlight:14:14|t "

    local ddPool = {}
    local profRows = {}

    local function RefreshProfMenuRows()
        local currentSet = getFilterProfSingleSet()
        for i, row in ipairs(profRows) do
            local profession = i == 1 and nil or ddPool[i - 1]
            if i <= #ddPool + 1 then
                row.profession = profession
                if profession then
                    row.text:SetText((currentSet[profession] and CHECK_ON or CHECK_OFF) .. profession)
                else
                    row.text:SetText((next(currentSet) == nil and CHECK_ON or CHECK_OFF) .. allFilterText)
                end
                row:Show()
            else
                row:Hide()
            end
        end
    end

    local function EnsureProfMenuRows()
        local rowCount = #ddPool + 1
        for i = #profRows + 1, rowCount do
            local row = CreateFrame("Button", nil, profMenu)
            row:SetHeight(20)
            row:SetPoint("TOPLEFT", profMenu, "TOPLEFT", 2, -2 - ((i - 1) * 20))
            row:SetPoint("TOPRIGHT", profMenu, "TOPRIGHT", -2, -2 - ((i - 1) * 20))

            local highlight = row:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(gold[1], gold[2], gold[3], 0.18)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row, "LEFT", 5, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -5, 0)
            row.text:SetJustifyH("LEFT")
            applyFontSize(row.text, 10)

            row:SetScript("OnClick", function(self)
                local profession = self.profession
                if profession then
                    local selected = getFilterProfSingleSet()
                    if selected[profession] then
                        selected[profession] = nil
                    else
                        selected[profession] = true
                    end
                else
                    setFilterProfSingleSet({})
                end
                UpdateProfDDText()
                rebuildList()
                refreshRows()
                RefreshProfMenuRows()
            end)
            profRows[i] = row
        end
        profMenu:SetHeight(4 + (rowCount * 20))
        RefreshProfMenuRows()
    end

    local function InitProfDD()
        wipe(ddPool)
        local filterMode = getFilterMode()
        local filterProfSet = getFilterProfSet()
        if filterMode == "mine" and hasAnyEntries(filterProfSet) then
            for prof in pairs(filterProfSet) do
                ddPool[#ddPool + 1] = prof
            end
            table.sort(ddPool)
        else
            for _, p in ipairs(GAM.Importer.GetAllProfessions(getFilterPatch()) or {}) do
                ddPool[#ddPool + 1] = p
            end
        end

        EnsureProfMenuRows()
        UpdateProfDDText()
    end

    ddProf:SetScript("OnClick", function()
        if profMenu:IsShown() then
            profMenu:Hide()
        else
            RefreshProfMenuRows()
            profMenu:Show()
        end
    end)
    panel:HookScript("OnHide", function()
        profMenu:Hide()
    end)

    panel.ddProf = ddProf
    panel.initProfDD = InitProfDD
    InitProfDD()

    local fillLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fillLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, -158)
    fillLbl:SetText((L and L["V2_FILL_QTY"]) or "Fill Qty")
    fillLbl:SetTextColor(gold[1], gold[2], gold[3])
    applyFontSize(fillLbl, 11)

    local fillQtyBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    fillQtyBox:SetHeight(20)
    fillQtyBox:SetAutoFocus(false)
    fillQtyBox:SetNumeric(true)
    fillQtyBox:SetText(tostring(getOpts().shallowFillQty or GAM.C.DEFAULT_FILL_QTY))
    fillQtyBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((L and L["TT_FILL_QTY_TITLE"]) or "Auction Price Quantity", 1, 1, 1)
        GameTooltip:AddLine((L and L["TT_FILL_QTY_BODY"]) or "Number of auction units sampled for market prices. Use a larger number for large batches. Range: 10-10,000.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    fillQtyBox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local fillQtyOKBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    fillQtyOKBtn:SetSize(28, 18)
    fillQtyOKBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LP, -154)
    fillQtyOKBtn:SetText(GetCommitButtonText(L))
    fillQtyOKBtn:Hide()
    fillQtyBox:SetPoint("LEFT", fillLbl, "RIGHT", 8, 0)
    fillQtyBox:SetPoint("RIGHT", fillQtyOKBtn, "LEFT", -4, 0)

    local fillRangeFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fillRangeFS:SetPoint("TOPLEFT", fillLbl, "BOTTOMLEFT", 0, -4)
    fillRangeFS:SetWidth(panelWidth - LP * 2)
    fillRangeFS:SetJustifyH("LEFT")
    fillRangeFS:SetText(string.format("%d-%d", GAM.C.MIN_FILL_QTY, GAM.C.MAX_FILL_QTY))
    fillRangeFS:SetTextColor(helperColor[1], helperColor[2], helperColor[3], helperColor[4] or 1)
    applyFontSize(fillRangeFS, softInk and 10 or 9)
    fillRangeFS:Hide()

    -- Single vertical integration toggle: enables all derivation paths atomically
    -- (herbs → pigments, ore → ingots, linen → bolts)
    local viOwn = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    viOwn:SetPoint("TOPLEFT", panel, "TOPLEFT", LP - 4, -184)
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
        (L and L["TT_VI_TITLE"]) or "Craft Intermediate Items",
        (L and L["TT_VI_BODY"]) or "Include the cost of crafting intermediate materials instead of assuming they are bought from the Auction House."
    )

    local viBreakdownOwn = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    viBreakdownOwn:SetPoint("TOPLEFT", panel, "TOPLEFT", LP + 10, -208)

    local viBreakdownLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    viBreakdownLbl:SetPoint("LEFT", viBreakdownOwn, "RIGHT", 0, 0)
    viBreakdownLbl:SetWidth(panelWidth - LP * 2 - 30)
    viBreakdownLbl:SetJustifyH("LEFT")
    viBreakdownLbl:SetText((L and L["V2_VI_BREAKDOWN"]) or "Show VI breakdown")
    viBreakdownLbl:SetTextColor(labelColor[1], labelColor[2], labelColor[3], labelColor[4] or 1)
    applyFontSize(viBreakdownLbl, softInk and 10 or 9)
    attachButtonTooltip(
        viBreakdownOwn,
        (L and L["TT_VI_BREAKDOWN_TITLE"]) or "Show Craft Steps",
        (L and L["TT_VI_BREAKDOWN_BODY"]) or "Show the materials and intermediate crafts behind the selected estimate."
    )

    local rankLbl
    local function RefreshVIBreakdownToggle()
        local opts = getOpts()
        local viEnabled = (opts.pigmentCostSource == "mill")
            or (opts.boltCostSource == "craft")
            or (opts.ingotCostSource == "craft")
        local showBreakdown = opts.showVIBreakdown and true or false
        viBreakdownOwn:SetChecked(viEnabled and showBreakdown)
        viBreakdownOwn:SetEnabled(viEnabled)
        viBreakdownOwn:SetShown(viEnabled)
        viBreakdownLbl:SetShown(viEnabled)
        viBreakdownLbl:SetTextColor(
            labelColor[1],
            labelColor[2],
            labelColor[3],
            viEnabled and (labelColor[4] or 1) or 0.55
        )
        if rankLbl then
            rankLbl:ClearAllPoints()
            rankLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, viEnabled and -250 or -218)
        end
    end

    local RefreshVisiblePanels
    rankLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankLbl:SetText((L and L["V2_MATERIAL_RANK"]) or "Material Rank")
    rankLbl:SetTextColor(gold[1], gold[2], gold[3])
    applyFontSize(rankLbl, 11)

    local innerW = panelWidth - (LP * 2)
    local halfBtnGap = 4
    local halfBtnW = math.floor((innerW - halfBtnGap) / 2)
    local bottomBtnH = 28
    local primaryScanH = 34
    local bottomBtnGap = 4

    local scanRowTop = LP
    local selectedRowTop = scanRowTop + primaryScanH + bottomBtnGap
    local toolsRowTop = selectedRowTop + bottomBtnH + bottomBtnGap

    rankLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", LP, -218)

    local ddRank = CreateFrame("Button", "GAMMainV2RankDD", panel, "UIPanelButtonTemplate")
    ddRank:SetPoint("TOPLEFT", rankLbl, "BOTTOMLEFT", 0, -4)
    ddRank:SetSize(innerW, 22)
    local rankTextMap = {
        lowest = (L and L["RANK_DD_LOWEST"]) or "R1 Mats",
        highest = (L and L["RANK_DD_HIGHEST"]) or "R2 Mats",
        optimal = (L and L["RANK_DD_OPTIMAL"]) or "Best Mix -> Max Rank",
    }

    local function RefreshRankDropdown()
        local rankPolicy = getOpts().rankPolicy or "lowest"
        ddRank:SetText(rankTextMap[rankPolicy] or rankTextMap.lowest)
    end

    ddRank:SetScript("OnClick", function()
        local current = getOpts().rankPolicy or "lowest"
        local nextPolicy = current == "lowest" and "optimal"
            or current == "optimal" and "highest"
            or "lowest"
        setOption("rankPolicy", nextPolicy)
        RefreshRankDropdown()
        RefreshVisiblePanels()
    end)
    RefreshRankDropdown()
    panel.refreshRankDropdown = RefreshRankDropdown

    local gearLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gearLbl:SetPoint("TOPLEFT", ddRank, "BOTTOMLEFT", 0, -10)
    gearLbl:SetText((L and L["V2_GEAR_PLAN"]) or "Stat Gear")
    gearLbl:SetTextColor(gold[1], gold[2], gold[3])
    applyFontSize(gearLbl, 11)

    local gearPlanBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    gearPlanBtn:SetPoint("TOPLEFT", gearLbl, "BOTTOMLEFT", 0, -4)
    gearPlanBtn:SetSize(innerW, 24)
    attachButtonTooltip(gearPlanBtn,
        (L and L["TT_GEAR_MENU_TITLE"]) or "Stat Gear",
        (L and L["TT_GEAR_MENU_BODY"])
            or "Choose a saved gear setup, or save the stats from the recipe currently open in your profession window.")

    local gearMenu = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    gearMenu:SetPoint("TOPLEFT", gearPlanBtn, "BOTTOMLEFT", 0, -2)
    gearMenu:SetSize(innerW, 56)
    gearMenu:SetFrameStrata("DIALOG")
    gearMenu:SetFrameLevel(panel:GetFrameLevel() + 20)
    gearMenu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    gearMenu:SetBackdropColor(0.035, 0.035, 0.035, 0.98)
    gearMenu:SetBackdropBorderColor(rule[1], rule[2], rule[3], 0.9)
    gearMenu:Hide()

    local gearGap = 3
    local gearButtonW = math.floor((innerW - (gearGap * 2)) / 3)
    local gearButtons = {}
    for index, def in ipairs({
        { mode = "auto", label = "Auto" },
        { mode = "multicraft", label = "MC" },
        { mode = "resourcefulness", label = "Res" },
    }) do
        local button = CreateFrame("Button", nil, gearMenu, "UIPanelButtonTemplate")
        button:SetSize(gearButtonW - 2, 22)
        button:SetPoint("TOPLEFT", gearMenu, "TOPLEFT",
            2 + ((index - 1) * (gearButtonW + gearGap)), -2)
        button:SetText(def.label)
        button.mode = def.mode
        gearButtons[def.mode] = button
        button:SetScript("OnClick", function()
            setGearMode(def.mode)
            gearMenu:Hide()
            RefreshVisiblePanels()
        end)
    end
    attachButtonTooltip(gearButtons.auto, "Auto", "Use whichever saved setup gives more profit.")
    attachButtonTooltip(gearButtons.multicraft, "Multicraft", "Always use the saved Multicraft setup.")
    attachButtonTooltip(gearButtons.resourcefulness, "Resourcefulness", "Always use the saved Resourcefulness setup.")

    local captureMCBtn = CreateFrame("Button", nil, gearMenu, "UIPanelButtonTemplate")
    captureMCBtn:SetSize(halfBtnW - 2, 22)
    captureMCBtn:SetPoint("BOTTOMLEFT", gearMenu, "BOTTOMLEFT", 2, 2)
    captureMCBtn:SetText("Save MC")
    captureMCBtn:SetScript("OnClick", function()
        captureGearPreset("multicraft")
        gearMenu:Hide()
        RefreshVisiblePanels()
    end)
    attachButtonTooltip(captureMCBtn, "Save Multicraft",
        "Save the equipped stats from the open recipe as its Multicraft setup.")

    local captureResBtn = CreateFrame("Button", nil, gearMenu, "UIPanelButtonTemplate")
    captureResBtn:SetSize(halfBtnW - 2, 22)
    captureResBtn:SetPoint("BOTTOMRIGHT", gearMenu, "BOTTOMRIGHT", -2, 2)
    captureResBtn:SetText("Save Res")
    captureResBtn:SetScript("OnClick", function()
        captureGearPreset("resourcefulness")
        gearMenu:Hide()
        RefreshVisiblePanels()
    end)
    attachButtonTooltip(captureResBtn, "Save Resourcefulness",
        "Save the equipped stats from the open recipe as its Resourcefulness setup.")

    gearPlanBtn:SetScript("OnClick", function()
        profMenu:Hide()
        gearMenu:SetShown(not gearMenu:IsShown())
    end)
    panel:HookScript("OnHide", function() gearMenu:Hide() end)

    local function RefreshGearPlan()
        local status = getGearStatus()
        local selected = status and status.selected or "auto"
        local available = status and status.available or {}
        local modeLabels = {
            auto = (L and L["GEAR_MODE_AUTO"]) or "Auto",
            multicraft = (L and L["GEAR_MODE_MC"]) or "Multicraft",
            resourcefulness = (L and L["GEAR_MODE_RES"]) or "Resourcefulness",
        }
        gearPlanBtn:SetText((modeLabels[selected] or modeLabels.auto) .. "  v")
        for mode, button in pairs(gearButtons) do
            local active = mode == selected
            if button:GetFontString() then
                button:GetFontString():SetTextColor(
                    active and gold[1] or 0.65,
                    active and gold[2] or 0.65,
                    active and gold[3] or 0.65)
            end
        end
        captureMCBtn:SetText(available.multicraft and "MC Saved" or "Save MC")
        captureResBtn:SetText(available.resourcefulness and "Res Saved" or "Save Res")
        local enabled = status and status.canCapture or false
        captureMCBtn:SetEnabled(enabled)
        captureResBtn:SetEnabled(enabled)
        captureMCBtn:SetAlpha(enabled and 1 or 0.45)
        captureResBtn:SetAlpha(enabled and 1 or 0.45)
    end
    panel.refreshGearPlan = RefreshGearPlan

    local cooldownsBtn
    local selectedCraftSimBtn
    local selectedShoppingBtn

    -- Compatibility no-op for callers built before manual profile-wide stat
    -- fallbacks moved out of the primary workflow and into Settings.
    panel.refreshStatEditors = Noop

    RefreshVisiblePanels = function()
        rebuildList()
        refreshBestStratCard()
        refreshRows()
        RefreshRankDropdown()
        RefreshGearPlan()
        refreshVisibleDetail()
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
    RefreshGearPlan()

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
        setFilterProfSingleSet({})
        if panel.initProfDD then
            panel.initProfDD()
        elseif panel.ddProf then
            panel.ddProf:SetText(allFilterText .. "  v")
        end
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
        setFilterProfSingleSet({})
        if panel.initProfDD then
            panel.initProfDD()
        elseif panel.ddProf then
            panel.ddProf:SetText(allFilterText .. "  v")
        end
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
        (L and L["TT_SCAN_ALL_TITLE"]) or "Scan Current Strategy List",
        (L and L["TT_SCAN_ALL_BODY"]) or "Update Auction House prices for every strategy allowed by the current profession filters. Shift-click to scan every supported profession."
    )

    local selectedScanBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    selectedScanBtn:SetHeight(bottomBtnH)
    selectedScanBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LP, selectedRowTop)
    selectedScanBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LP, selectedRowTop)
    selectedScanBtn:SetText((L and L["BTN_SCAN_SELECTED"]) or "Scan Selected Strat")
    selectedScanBtn:Disable()
    selectedScanBtn:SetAlpha(0.45)
    selectedScanBtn:SetScript("OnClick", scanSelectedStrat)
    attachButtonTooltip(
        selectedScanBtn,
        (L and L["TT_SCAN_SELECTED_TITLE"]) or "Scan Selected Strategy",
        (L and L["TT_SCAN_SELECTED_BODY"]) or "Update prices for the selected recipe and its materials. Shift-click to scan visible Favorites instead."
    )

    local moreToolsBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    moreToolsBtn:SetHeight(bottomBtnH)
    moreToolsBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LP, toolsRowTop)
    moreToolsBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LP, toolsRowTop)
    moreToolsBtn:SetText((L and L["BTN_MORE_TOOLS"]) or "More Tools...")

    local actionsLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    actionsLbl:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LP, toolsRowTop + bottomBtnH + 8)
    actionsLbl:SetText((L and L["V2_ACTIONS"]) or "Actions")
    actionsLbl:SetTextColor(gold[1], gold[2], gold[3])
    applyFontSize(actionsLbl, 11)

    local toolsMenu = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    toolsMenu:SetPoint("BOTTOMLEFT", moreToolsBtn, "TOPLEFT", 0, 3)
    toolsMenu:SetSize(innerW, 83)
    toolsMenu:SetFrameStrata("DIALOG")
    toolsMenu:SetFrameLevel(panel:GetFrameLevel() + 20)
    toolsMenu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    toolsMenu:SetBackdropColor(0.035, 0.035, 0.035, 0.98)
    toolsMenu:SetBackdropBorderColor(rule[1], rule[2], rule[3], 0.9)
    toolsMenu:Hide()

    local menuBtnW = halfBtnW - 2
    local function MakeToolsButton(label, column, row, onClick)
        local button = CreateFrame("Button", nil, toolsMenu, "UIPanelButtonTemplate")
        button:SetSize(menuBtnW, 24)
        button:SetPoint("TOPLEFT", toolsMenu, "TOPLEFT",
            column == 1 and 2 or (halfBtnW + 2),
            -2 - ((row - 1) * 27))
        button:SetText(label)
        button:SetScript("OnClick", function()
            toolsMenu:Hide()
            onClick()
        end)
        return button
    end

    selectedShoppingBtn = MakeToolsButton(
        (L and L["BTN_SHOPPING_SHORT"]) or "Shopping", 1, 1, toggleShoppingSync)
    local quickBuyBtn = MakeToolsButton(
        (L and L["BTN_QUICK_BUY_SHORT"]) or "Quick Buy", 2, 1, showQuickBuy)
    cooldownsBtn = MakeToolsButton(
        (L and L["BTN_COOLDOWNS_SHORT"]) or "Cooldowns", 1, 2, showCooldowns)
    selectedCraftSimBtn = MakeToolsButton(
        (L and L["BTN_CRAFTSIM_SHORT"]) or "CraftSim", 2, 2, pushSelectedToCraftSim)
    local btnARP = MakeToolsButton(
        (L and L["BTN_EXPORT_SHORT"]) or "Export", 1, 3, showARPExport)
    btnARP:SetWidth(innerW - 4)
    selectedCraftSimBtn:Disable()
    selectedShoppingBtn:Disable()
    attachButtonTooltip(
        quickBuyBtn,
        (L and L["TT_QUICK_BUY_TITLE"]) or "Quick Buy",
        (L and L["TT_QUICK_BUY_BODY"]) or "Purchase the current GAM shopping list one commodity at a time using live Auction House quotes."
    )
    attachButtonTooltip(
        selectedCraftSimBtn,
        (L and L["TT_CRAFTSIM_TITLE"]) or "Send Prices to CraftSim",
        (L and L["TT_CRAFTSIM_WARN"])
            or "Send this strategy's reagent prices to CraftSim. Existing manual prices in CraftSim will be replaced."
    )
    attachButtonTooltip(
        btnARP,
        (L and L["TT_EXPORT_TITLE"]) or "Spreadsheet Export",
        (L and L["TT_EXPORT_BODY"]) or "Copy strategy data for use in external spreadsheet tools."
    )

    moreToolsBtn:SetScript("OnClick", function()
        gearMenu:Hide()
        profMenu:Hide()
        toolsMenu:SetShown(not toolsMenu:IsShown())
    end)
    panel:HookScript("OnHide", function() toolsMenu:Hide() end)

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
    if panel.initProfDD then
        panel.initProfDD()
    end

    return {
        scanBtnLeft = scanBtnLeft,
        selectedCraftSimBtn = selectedCraftSimBtn,
        selectedShoppingBtn = selectedShoppingBtn,
        selectedScanBtn = selectedScanBtn,
        cooldownsBtn = cooldownsBtn,
    }
end
