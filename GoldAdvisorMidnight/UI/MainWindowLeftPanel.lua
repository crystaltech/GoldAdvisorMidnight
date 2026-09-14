-- GoldAdvisorMidnight/UI/MainWindowLeftPanel.lua
-- Shared left-panel builder for MainWindow.
-- Module: GAM.UI.MainWindowLeftPanel

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local LeftPanelUI = {}
GAM.UI.MainWindowLeftPanel = LeftPanelUI
GAM.UI.MainWindowV2LeftPanel = LeftPanelUI -- Compatibility alias for pre-refocus callers.

local function Noop()
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
    local buildPlayerProfessionSet = args.buildPlayerProfessionSet or function() return {} end
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
    local setFilterMode = args.setFilterMode or Noop
    local setFilterProf = args.setFilterProf or Noop
    local setFilterProfSet = args.setFilterProfSet or Noop
    local getFilterProfSingleSet = args.getFilterProfSingleSet or function() return {} end
    local setFilterProfSingleSet = args.setFilterProfSingleSet or Noop
    local styleButton = args.styleButton or (GAM.UI.MainWindowCommon and GAM.UI.MainWindowCommon.StyleComfortableButton) or Noop
    local softInk = layoutMode == "soft"
    local labelColor = softInk and bodyTextColor or { 0.9, 0.9, 0.9, 1.0 }
    local helperColor = softInk and mutedTextColor or { 0.65, 0.65, 0.65, 1.0 }

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

    -- Keep this menu entirely addon-owned.  UIDropDownMenu uses shared global
    -- DropDownList frames; changing those frames from addon code can taint
    -- unrelated protected Blizzard UI (for example the Game Menu).
    local ddProf = CreateFrame("Button", GAM.RuntimeName("GAMMainV2ProfDD"), panel, "UIPanelButtonTemplate")
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

    local ddPool, profRows = {}, {}
    local selectionPreset = "mine"
    local learned = {}
    local CHECK_ON = "|TInterface\\Buttons\\UI-CheckBox-Check:14:14|t "
    local CHECK_OFF = "|TInterface\\Buttons\\UI-CheckBox-Highlight:14:14|t "

    local function UpdateProfDDText()
        local names = {}
        for prof in pairs(getFilterProfSingleSet()) do names[#names + 1] = prof end
        table.sort(names)
        local label = "Choose professions"
        if #names > 0 then
            if selectionPreset == "mine" then label = "My professions"
            elseif selectionPreset == "all" then label = "All professions"
            elseif #names == 1 then label = names[1]
            else label = #names .. " professions" end
        end
        ddProf:SetText(label .. "  v")
        attachButtonTooltip(ddProf, "Professions",
            (#names > 0 and table.concat(names, ", ") or "No professions selected.")
            .. "\nChoose one or more professions to filter the list and its price scan.")
    end

    local function RefreshProfMenuRows()
        local selected = getFilterProfSingleSet()
        for i, row in ipairs(profRows) do
            local prof = ddPool[i - 2]
            if i == 1 then row.text:SetText("My professions")
            elseif i == 2 then row.text:SetText("All professions")
            elseif prof then
                row.text:SetText((selected[prof] and CHECK_ON or CHECK_OFF) .. prof
                    .. (learned[prof] and " (learned)" or ""))
            else row.text:SetText("Done") end
        end
    end

    local function SelectPreset(preset)
        learned = buildPlayerProfessionSet() or {}
        local selected = {}
        for _, prof in ipairs(ddPool) do
            if preset == "all" or learned[prof] then selected[prof] = true end
        end
        selectionPreset = preset
        setFilterMode("selected")
        setFilterProf("All")
        setFilterProfSet(nil)
        setFilterProfSingleSet(selected)
    end

    local function InitProfDD()
        wipe(ddPool)
        for _, prof in ipairs(GAM.Importer.GetAllProfessions(getFilterPatch()) or {}) do
            ddPool[#ddPool + 1] = prof
        end
        table.sort(ddPool)
        learned = buildPlayerProfessionSet() or {}
        for i = 1, #ddPool + 3 do
            local row = profRows[i]
            if not row then
                row = CreateFrame("Button", nil, profMenu)
                row:SetHeight(26)
                row:SetPoint("TOPLEFT", profMenu, "TOPLEFT", 2, -4 - ((i - 1) * 26))
                row:SetPoint("TOPRIGHT", profMenu, "TOPRIGHT", -2, -4 - ((i - 1) * 26))
                local highlight = row:CreateTexture(nil, "HIGHLIGHT")
                highlight:SetAllPoints()
                highlight:SetColorTexture(gold[1], gold[2], gold[3], 0.18)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                row.text:SetJustifyH("LEFT")
                applyFontSize(row.text, 11)
                profRows[i] = row
            end
            local index = i
            row:SetScript("OnClick", function()
                if index == #ddPool + 3 then profMenu:Hide(); return end
                if index <= 2 then
                    SelectPreset(index == 1 and "mine" or "all")
                else
                    selectionPreset = nil
                    local selected = getFilterProfSingleSet()
                    local prof = ddPool[index - 2]
                    selected[prof] = not selected[prof] or nil
                end
                UpdateProfDDText()
                RefreshProfMenuRows()
                rebuildList()
                refreshRows()
                relayoutPanels()
            end)
            row:Show()
        end
        for i = #ddPool + 4, #profRows do profRows[i]:Hide() end
        profMenu:SetHeight(8 + (#ddPool + 3) * 26)
        RefreshProfMenuRows()
        UpdateProfDDText()
    end

    ddProf:SetScript("OnClick", function()
        if profMenu:IsShown() then profMenu:Hide()
        else InitProfDD(); profMenu:Show() end
    end)
    panel:HookScript("OnHide", function() profMenu:Hide() end)
    panel.ddProf = ddProf
    panel.initProfDD = InitProfDD
    panel.refreshProfessions = function()
        InitProfDD()
        if selectionPreset then SelectPreset(selectionPreset) end
        UpdateProfDDText()
        RefreshProfMenuRows()
    end
    InitProfDD()
    SelectPreset("mine")
    UpdateProfDDText()
    RefreshProfMenuRows()

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
    fillQtyOKBtn:SetSize(28, 22)
    fillQtyOKBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -LP, -154)
    fillQtyOKBtn:SetText(GetCommitButtonText())
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
        if rankLbl and layoutMode ~= "comfortable" then
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

    local ddRank = CreateFrame("Button", GAM.RuntimeName("GAMMainV2RankDD"), panel, "UIPanelButtonTemplate")
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
    captureMCBtn:SetText((L and L["BTN_SAVE_MC"]) or "Save MC")
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
    captureResBtn:SetText((L and L["BTN_SAVE_RES"]) or "Save Res")
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

    local refreshComfortableSummary = Noop
    RefreshVisiblePanels = function()
        rebuildList()
        refreshBestStratCard()
        refreshRows()
        RefreshRankDropdown()
        RefreshGearPlan()
        refreshVisibleDetail()
        RefreshVIBreakdownToggle()
        refreshComfortableSummary()
    end
    panel.refreshVisiblePanels = RefreshVisiblePanels

    local function CommitFillQty(text)
        local opts = getOpts()
        opts.shallowFillQty = clampFillQtyValue(text)
        fillQtyBox:SetText(tostring(opts.shallowFillQty))
        fillQtyBox._gamCommittedText = tostring(fillQtyBox:GetText() or "")
        RefreshVisiblePanels()
        return tostring(opts.shallowFillQty)
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

    local scanBtnLeft = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scanBtnLeft:SetHeight(primaryScanH)
    scanBtnLeft:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LP, scanRowTop)
    scanBtnLeft:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LP, scanRowTop)
    scanBtnLeft:SetText(L["BTN_SCAN_ALL"])
    scanBtnLeft:SetScript("OnClick", function() doScan() end)
    attachButtonTooltip(
        scanBtnLeft,
        (L and L["TT_SCAN_ALL_TITLE"]) or "Scan Current Strategy List",
        GAM.UI.MainWindowCommon.SCAN_HELP
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

    if layoutMode == "comfortable" then
        charNameFS:Hide()
        realmFS:Hide()
        lpRule:Hide()
        filterLbl:Hide()
        fillRangeFS:Hide()
        actionsLbl:Hide()
        selectedScanBtn:Hide()

        local professionLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        professionLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -17)
        professionLabel:SetText("Professions")
        professionLabel:SetTextColor(unpack(labelColor))
        applyFontSize(professionLabel, 11)
        ddProf:ClearAllPoints()
        ddProf:SetPoint("TOPLEFT", panel, "TOPLEFT", 100, -8)
        ddProf:SetSize(250, 28)
        profMenu:ClearAllPoints()
        profMenu:SetPoint("TOPLEFT", ddProf, "BOTTOMLEFT", 0, -2)
        profMenu:SetWidth(280)

        scanBtnLeft:ClearAllPoints()
        scanBtnLeft:SetPoint("LEFT", ddProf, "RIGHT", 8, 0)
        scanBtnLeft:SetSize(158, 28)
        scanBtnLeft:SetText("Scan prices")

        moreToolsBtn:ClearAllPoints()
        moreToolsBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -8)
        moreToolsBtn:SetSize(118, 28)
        moreToolsBtn:SetText("Tools  v")

        local scanMenuBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        scanMenuBtn:SetSize(28, 28)
        scanMenuBtn:SetPoint("LEFT", scanBtnLeft, "RIGHT", 1, 0)
        scanMenuBtn:SetText("v")
        styleButton(scanMenuBtn, true)
        attachButtonTooltip(scanMenuBtn, "Scan options", "Choose a price scan to start. Your profession selection stays unchanged.")
        local scanMenu = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        panel.scanMenu = scanMenu
        panel.scanMenuBtn = scanMenuBtn
        scanMenu:SetPoint("TOPLEFT", scanBtnLeft, "BOTTOMLEFT", 0, -2)
        scanMenu:SetSize(220, 112)
        scanMenu:SetFrameStrata("DIALOG")
        scanMenu:SetFrameLevel(panel:GetFrameLevel() + 20)
        scanMenu:SetBackdrop(profMenu:GetBackdrop())
        scanMenu:SetBackdropColor(0.035, 0.035, 0.035, 0.98)
        scanMenu:SetBackdropBorderColor(rule[1], rule[2], rule[3], 0.9)
        scanMenu:Hide()
        local scanRows = {}
        panel.scanMenuRows = scanRows
        local scopes = {
            { "list", "Current list", "Scan strategies matching your current filters." },
            { "all", "All professions", "Scan every supported strategy in this patch, regardless of filters." },
            { "favorites", "Favorites", "Scan all favorites in this patch, regardless of profession filters." },
            { "selected", "Selected strategy", "Select a strategy first. Scan only that strategy and its materials." },
        }
        for i, entry in ipairs(scopes) do
            local row = CreateFrame("Button", nil, scanMenu, "UIPanelButtonTemplate")
            row:SetPoint("TOPLEFT", scanMenu, "TOPLEFT", 4, -4 - (i - 1) * 26)
            row:SetSize(212, 26)
            row:SetText(entry[2])
            styleButton(row, false)
            attachButtonTooltip(row, entry[2], entry[3])
            row:SetScript("OnClick", function()
                scanMenu:Hide()
                if args.scanScope then args.scanScope(entry[1]) end
            end)
            scanRows[i] = row
        end
        local function RefreshScanMenu()
            local count, selected = 0, false
            if args.getScanContext then count, selected = args.getScanContext() end
            local active = GAM.AHScan and GAM.AHScan.IsScanning and GAM.AHScan.IsScanning()
            scanRows[1]:SetEnabled(not active and count > 0)
            scanRows[2]:SetEnabled(not active)
            scanRows[3]:SetEnabled(not active)
            scanRows[4]:SetEnabled(not active and selected)
        end
        scanMenuBtn:SetScript("OnClick", function()
            profMenu:Hide(); gearMenu:Hide(); toolsMenu:Hide()
            RefreshScanMenu()
            scanMenu:SetShown(not scanMenu:IsShown())
        end)
        scanBtnLeft:HookScript("OnClick", function() scanMenu:Hide(); profMenu:Hide() end)
        ddProf:HookScript("OnClick", function() scanMenu:Hide(); gearMenu:Hide(); toolsMenu:Hide() end)
        moreToolsBtn:HookScript("OnClick", function() scanMenu:Hide() end)

        -- Addon-owned menus close on Escape and outside mouse-down, without
        -- consuming the click or using Blizzard's shared dropdown frames.
        for _, pair in ipairs({{profMenu, ddProf}, {scanMenu, scanMenuBtn, scanBtnLeft}}) do
            local menu = pair[1]
            menu:EnableKeyboard(true)
            menu:SetPropagateKeyboardInput(true)
            menu:SetScript("OnKeyDown", function(self, key)
                if InCombatLockdown and InCombatLockdown() then self:Hide(); return end
                self:SetPropagateKeyboardInput(key ~= "ESCAPE")
                if key == "ESCAPE" then self:Hide() end
            end)
            menu:RegisterEvent("GLOBAL_MOUSE_DOWN")
            menu:SetScript("OnEvent", function(self)
                if not self:IsShown() or self:IsMouseOver() or pair[2]:IsMouseOver()
                    or (pair[3] and pair[3]:IsMouseOver()) then return end
                self:Hide()
            end)
            panel:HookScript("OnHide", function() menu:Hide() end)
        end

        local optionsBtn = CreateFrame("Button", nil, panel)
        optionsBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -68)
        optionsBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -68)
        optionsBtn:SetHeight(28)
        local optionsText = optionsBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        optionsText:SetPoint("LEFT", optionsBtn, "LEFT", 2, 0)
        optionsText:SetWidth(240)
        optionsText:SetJustifyH("LEFT")
        optionsText:SetTextColor(gold[1], gold[2], gold[3], 1)
        applyFontSize(optionsText, 11)
        local highlight = optionsBtn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(gold[1], gold[2], gold[3], 0.08)
        local divider = optionsBtn:CreateTexture(nil, "ARTWORK")
        divider:SetPoint("TOPLEFT"); divider:SetPoint("TOPRIGHT"); divider:SetHeight(1)
        divider:SetColorTexture(rule[1], rule[2], rule[3], 0.25)

        local workflowHint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        panel.scanScopeText = workflowHint
        workflowHint:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -45)
        workflowHint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -45)
        workflowHint:SetJustifyH("LEFT")
        workflowHint:SetWordWrap(false)
        workflowHint:SetTextColor(unpack(labelColor))
        applyFontSize(workflowHint, 11)
        local scanProgress
        panel.setScanProgress = function(done, total, complete)
            scanProgress = not complete and total and total > 0
                and string.format("Scanning prices: %d / %d items. Click Stop scan to cancel.", done or 0, total) or nil
        end
        panel.refreshScanScope = function()
            local count = args.getScanContext and args.getScanContext() or 0
            local active = GAM.AHScan and GAM.AHScan.IsScanning and GAM.AHScan.IsScanning()
            if active then
                workflowHint:SetText(scanProgress or "Queuing prices... Click Stop scan to cancel.")
                scanMenu:Hide()
            elseif not next(getFilterProfSingleSet()) then
                workflowHint:SetText(selectionPreset == "mine"
                    and "No supported professions detected. Choose professions to scan."
                    or "Choose at least one profession to scan.")
            else
                workflowHint:SetText(string.format("Scans prices for %d matching strategies.%s", count,
                    GAM.ahOpen and "" or "  Open the Auction House to scan."))
            end
            RefreshScanMenu()
        end
        panel.refreshScanScope()
        local summary = optionsBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        summary:SetPoint("LEFT", optionsText, "RIGHT", 10, 0)
        summary:SetPoint("RIGHT", optionsBtn, "RIGHT", -4, 0)
        summary:SetJustifyH("RIGHT")
        summary:SetWordWrap(false)
        summary:SetTextColor(unpack(helperColor))
        applyFontSize(summary, 10)

        fillLbl:ClearAllPoints()
        fillLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -108)
        fillQtyBox:ClearAllPoints()
        fillQtyBox:SetPoint("TOPLEFT", fillLbl, "BOTTOMLEFT", 4, -8)
        fillQtyBox:SetSize(100, 24)
        fillQtyOKBtn:ClearAllPoints()
        fillQtyOKBtn:SetPoint("LEFT", fillQtyBox, "RIGHT", 4, 0)

        rankLbl:ClearAllPoints()
        rankLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 170, -108)
        ddRank:ClearAllPoints()
        ddRank:SetPoint("TOPLEFT", rankLbl, "BOTTOMLEFT", 0, -4)
        ddRank:SetSize(194, 24)

        gearLbl:ClearAllPoints()
        gearLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 382, -108)
        gearPlanBtn:ClearAllPoints()
        gearPlanBtn:SetPoint("TOPLEFT", gearLbl, "BOTTOMLEFT", 0, -4)
        gearPlanBtn:SetSize(194, 24)
        gearMenu:ClearAllPoints()
        gearMenu:SetPoint("TOPLEFT", gearPlanBtn, "BOTTOMLEFT", 0, -2)
        gearMenu:SetSize(240, 56)

        local compactGearGap = 3
        local compactGearW = 76
        for index, mode in ipairs({ "auto", "multicraft", "resourcefulness" }) do
            local button = gearButtons[mode]
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", gearMenu, "TOPLEFT", 2 + ((index - 1) * (compactGearW + compactGearGap)), -2)
            button:SetSize(compactGearW, 22)
        end
        captureMCBtn:ClearAllPoints()
        captureMCBtn:SetPoint("BOTTOMLEFT", gearMenu, "BOTTOMLEFT", 2, 2)
        captureMCBtn:SetSize(115, 22)
        captureResBtn:ClearAllPoints()
        captureResBtn:SetPoint("BOTTOMRIGHT", gearMenu, "BOTTOMRIGHT", -2, 2)
        captureResBtn:SetSize(115, 22)

        viOwn:ClearAllPoints()
        viOwn:SetPoint("TOPLEFT", panel, "TOPLEFT", 600, -122)
        viLbl:SetWidth(200)
        viOwn:SetHitRectInsets(0, -200, 0, 0)
        viBreakdownOwn:ClearAllPoints()
        viBreakdownOwn:SetPoint("TOPLEFT", viOwn, "BOTTOMLEFT", 0, 2)
        viBreakdownLbl:SetWidth(200)
        viBreakdownOwn:SetHitRectInsets(0, -200, 0, 0)

        toolsMenu:ClearAllPoints()
        toolsMenu:SetPoint("TOPRIGHT", moreToolsBtn, "BOTTOMRIGHT", 0, -2)
        toolsMenu:SetSize(286, 83)
        local toolButtons = {
            { selectedShoppingBtn, 1, 1 }, { quickBuyBtn, 2, 1 },
            { cooldownsBtn, 1, 2 }, { selectedCraftSimBtn, 2, 2 },
            { btnARP, 1, 3 },
        }
        for _, entry in ipairs(toolButtons) do
            entry[1]:SetParent(toolsMenu)
            entry[1]:Show()
            entry[1]:ClearAllPoints()
            entry[1]:SetPoint("TOPLEFT", toolsMenu, "TOPLEFT",
                entry[2] == 1 and 2 or 144, -2 - ((entry[3] - 1) * 27))
            entry[1]:SetSize(138, 24)
        end

        for _, button in ipairs({
            ddProf, moreToolsBtn,
            ddRank, gearPlanBtn, selectedShoppingBtn, quickBuyBtn, cooldownsBtn,
            selectedCraftSimBtn, selectedScanBtn, btnARP, captureMCBtn, captureResBtn,
        }) do
            styleButton(button, false)
        end
        styleButton(scanBtnLeft, true)
        for _, button in pairs(gearButtons) do styleButton(button, false) end

        local function SetOptionsShown(shown)
            getOpts().craftingOptionsExpanded = shown and true or false
            optionsText:SetText(shown and "v  Price & crafting settings" or ">  Price & crafting settings")
            summary:SetShown(not shown)
            for _, widget in ipairs({
                fillLbl, fillQtyBox, rankLbl, ddRank,
                gearLbl, gearPlanBtn, viOwn, viLbl, viBreakdownOwn, viBreakdownLbl,
            }) do
                widget:SetShown(shown)
            end
            if shown then
                RefreshCommitButton(fillQtyBox)
                RefreshVIBreakdownToggle()
            else
                fillQtyOKBtn:Hide()
            end
            gearMenu:Hide()
            relayoutPanels()
        end

        refreshComfortableSummary = function()
            local opts = getOpts()
            local rank = ({ lowest = "Rank 1", highest = "Rank 2", optimal = "Best mix" })[opts.rankPolicy or "lowest"]
                or tostring(opts.rankPolicy or "R1 mats")
            local gearStatus = getGearStatus()
            local gear = gearStatus and gearStatus.selected or "Auto"
            if gear == "multicraft" then gear = "Multicraft" end
            if gear == "resourcefulness" then gear = "Resourcefulness" end
            if gear == "auto" then gear = "Auto" end
            summary:SetText(string.format("Price quantity: %s  |  Materials: %s  |  Gear: %s",
                tostring(opts.shallowFillQty or GAM.C.DEFAULT_FILL_QTY), rank, gear))
        end

        optionsBtn:SetScript("OnClick", function()
            SetOptionsShown(not getOpts().craftingOptionsExpanded)
        end)
        optionsBtn:HookScript("OnEnter", function()
            optionsText:SetTextColor(1, 1, 1, 1)
        end)
        optionsBtn:HookScript("OnLeave", function()
            optionsText:SetTextColor(gold[1], gold[2], gold[3], 1)
        end)
        attachButtonTooltip(
            optionsBtn,
            "Price & crafting settings",
            "Show or hide price quantity, material quality, profession gear, and intermediate crafting settings."
        )
        panel.getPreferredHeight = function()
            return getOpts().craftingOptionsExpanded and 184 or 100
        end
        panel.setCraftingOptionsExpanded = SetOptionsShown
        refreshComfortableSummary()
        SetOptionsShown(getOpts().craftingOptionsExpanded and true or false)
    end

    return {
        professionMenu = profMenu,
        professionRows = profRows,
        scanBtnLeft = scanBtnLeft,
        selectedCraftSimBtn = selectedCraftSimBtn,
        selectedShoppingBtn = selectedShoppingBtn,
        selectedScanBtn = selectedScanBtn,
        cooldownsBtn = cooldownsBtn,
    }
end
