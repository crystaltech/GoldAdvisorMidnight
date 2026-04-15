-- GoldAdvisorMidnight/UI/MainWindowV2.lua
-- Primary three-panel main window (replaced legacy MainWindow in v1.6+).
-- Left (tools/scan), Center (strategy list), Right (inline detail).
-- Best Strategy hero card, collapsible panels, onboarding overlay.
-- Module: GAM.UI.MainWindowV2

local ADDON_NAME, GAM = ...
local MW2 = {}
GAM.UI.MainWindowV2 = MW2
local lastScanRefreshAt = 0

-- ===== Layout constants =====
local ROW_H        = 22
local VISIBLE_ROWS = 40
local CARD_H       = 120
local LIST_SECTION_H = 22
local HDR_H        = 20
local LIST_TOP_PAD = CARD_H + LIST_SECTION_H + HDR_H + 16   -- offset from center top to listHost
local PANEL_TOGGLE_GAP = 10   -- px gap between left/right panels and center for collapse handles

-- Color constants (module-local)
local C_GR, C_GG, C_GB = 1.0, 0.82, 0.0        -- gold
local C_DR, C_DG, C_DB, C_DA = 0.7, 0.57, 0.0, 0.7  -- dimmed gold (rules)
local WindowManager = GAM.UI.WindowManager
local Common = GAM.UI.MainWindowV2Common
local DetailUI = GAM.UI.MainWindowV2Detail
local LeftPanelUI = GAM.UI.MainWindowV2LeftPanel
local CenterUI = GAM.UI.MainWindowV2Center
local THIN_BACKDROP = Common.THIN_BACKDROP
local DISCORD_INVITE_CODE = "discord.gg/v7vsCKCsFh"
local DISCORD_INVITE_URL = "https://discord.gg/v7vsCKCsFh"
local FOOTER_TEXT_SIZE = 11
local FOOTER_MIN_HEIGHT = 24

local function GetOpts()
    return (GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {}
end

local function SetOption(key, value)
    if GAM.State and GAM.State.SetOption then
        GAM.State.SetOption(key, value)
        return
    end
    if GAM.db and GAM.db.options then
        GAM.db.options[key] = value
    end
end

local function GetThemeDef()
    return Common.GetThemeDef(GetOpts())
end

local function GetThemeKey()
    return Common.GetThemeKey(GetOpts())
end

local function GetUIScale()
    return GetOpts().uiScale or 1.0
end

local function GetTickerHeight(C)
    return math.max((C and C.TICKER_H) or 18, FOOTER_MIN_HEIGHT)
end

local function IsSoftThemeLayout()
    return GetThemeKey() == "soft"
end

local function GetLayoutSpec()
    local theme = GetThemeDef()
    local C = GAM.C
    if theme and theme.layout and IsSoftThemeLayout() then
        return {
            key = "soft",
            windowWidth = theme.layout.windowWidth,
            windowHeight = theme.layout.windowHeight,
            leftWidth = theme.layout.toolsWidth,
            rightWidth = theme.layout.detailWidth,
            cardGap = theme.layout.cardGap,
            outerPadding = theme.layout.outerPadding,
            guideHeight = theme.layout.guideHeight,
            compactPadding = theme.layout.compactPadding or theme.layout.outerPadding,
            maxVisibleRows = theme.layout.maxVisibleRows or VISIBLE_ROWS,
            listHeaderTop = theme.layout.listHeaderTop or 34,
            scrollBarTop = (theme.layout.listHeaderTop or 34) + HDR_H + 8,
            panelGap = theme.panelGap or PANEL_TOGGLE_GAP,
            cardInsets = theme.paperCard and theme.paperCard.contentInsets,
        }
    end
    return {
        key = "classic",
        windowWidth = C.MAIN_WIN_W,
        windowHeight = C.MAIN_WIN_H,
        leftWidth = C.LEFT_PANEL_W,
        rightWidth = C.RIGHT_PANEL_W,
        cardGap = 0,
        outerPadding = 0,
        guideHeight = CARD_H,
        compactPadding = 0,
        maxVisibleRows = VISIBLE_ROWS,
        listHeaderTop = CARD_H + LIST_SECTION_H + 12,
        scrollBarTop = LIST_TOP_PAD + 4,
        panelGap = (theme and theme.panelGap) or PANEL_TOGGLE_GAP,
    }
end

local function GetPanelToggleGap()
    return GetLayoutSpec().panelGap or PANEL_TOGGLE_GAP
end

local function GetCardContentWidth(cardWidth)
    local layout = GetLayoutSpec()
    if layout.key ~= "soft" then
        return cardWidth
    end
    local insets = layout.cardInsets or {}
    return cardWidth - (insets.left or 0) - (insets.right or 0)
end

local SetBackdropColors = Common.SetBackdropColors
local AttachButtonTooltip = Common.AttachButtonTooltip
local ApplyFontSize = Common.ApplyFontSize
local ApplyTextShadow = Common.ApplyTextShadow
local GetFormulaProfiles = Common.GetFormulaProfiles

-- ===== Column configs =====
-- ALL mode: show profession column
local LIST_COLUMNS_ALL = {
    { id="stratName",  x=14,  w=180, hKey="COL_STRAT",  sKey="stratName",  j="LEFT"  },
    { id="profession", x=200, w=100, hKey="COL_PROF",   sKey="profession", j="LEFT"  },
    { id="profit",     x=306, w=100, hKey="COL_PROFIT", sKey="profit",     j="CENTER" },
    { id="roi",        x=412, w=58,  hKey="COL_ROI",    sKey="roi",        j="CENTER" },
    { id="status",     x=476, w=60,  hKey="COL_STATUS", sKey=nil,          j="LEFT"  },
}
-- FILTERED mode: wider name, profession shown as subtitle, no profession column
local LIST_COLUMNS_FILTERED = {
    { id="stratName", x=14,  w=270, hKey="COL_STRAT",  sKey="stratName", j="LEFT"  },
    { id="profit",    x=290, w=110, hKey="COL_PROFIT", sKey="profit",    j="CENTER" },
    { id="roi",       x=406, w=58,  hKey="COL_ROI",    sKey="roi",       j="CENTER" },
    { id="status",    x=470, w=60,  hKey="COL_STATUS", sKey=nil,         j="LEFT"  },
}

local function NewThemeRefs()
    return {
        collapseButtons = {},
        reagentRowBgs = {},
        outputRowBgs = {},
        shells = {},
        paperCards = {},
        compactBtn = nil,
        tickerText = nil,
        headerBg = nil,
        titleText = nil,
        versionText = nil,
        statusCountText = nil,
        progressText = nil,
        progressBar = nil,
        progressBarBg = nil,
        bestCardBanner = nil,
        bestCardRuleLeft = nil,
        bestCardRuleRight = nil,
        softBoard = nil,
        leftRule = nil,
        titleRule = nil,
        headerSep = nil,
        tickerBg = nil,
        tickerBorder = nil,
        infoPanelTitle = nil,
        infoPanelBody = nil,
        infoPanelRule = nil,
    }
end

-- ===== Module state =====
local frame
local dividerContainer, leftPanel, centerPanel, rightPanel, statusBarFrame
local guidePanel, listPanel, softBoard
local leftPanelShell, centerPanelShell, rightPanelShell, statusBarShell, bestStratCardShell
local guidePanelShell, listPanelShell
local bestStratCard, onboardingOverlay, listHost
local colHeaderBtns = {}
local rowFrames     = {}
local filteredList  = {}
local scrollOffset  = 0
local selectedStratID = nil
local filterPatch      = GAM.C.DEFAULT_PATCH
local filterProf       = "All"
local filterProfSet    = nil
local filterMode       = "mine"
local filterProfSingle = "All"   -- specific profession sub-filter within the current pool
local sortKey       = "roi"
local sortAsc       = true
local scanning      = false
local scanBtnLeft, scanBtnStatus
local activeColConfig = LIST_COLUMNS_ALL
local rpDetail      = {}   -- inline right-panel detail widget refs
local suppressScrollCallback = false
local selectedCraftSimBtn, selectedVIBreakdownBtn, selectedShoppingBtn, selectedScanBtn
local themeRefs = NewThemeRefs()
local shoppingSync = {
    active = false,
    stratID = nil,
    patchTag = nil,
    lastSignature = nil,
    pending = false,
}
local shoppingSyncFrame
local discordPopup
local leftPanelChecks = {}  -- refs for left-panel cost source checkboxes
local compactBtn      = nil -- compact mode toggle button ref
local compactActive   = false -- tracks whether compact mode layout is currently applied
local listMetricCache = {}
local listMetricPatch = nil
local bestStratCardDirty = true
local builtThemeKey   = nil
local scrollBarTopOffset = LIST_TOP_PAD + 4
local columnHeaderTopOffset = CARD_H + LIST_SECTION_H + 12
local STRAT_ICON_W    = 20   -- left gutter for star icon
local UpdateCollapseButtonAnchors
local RebuildList
local RefreshBestStratCard
local RelayoutPanels
local ToggleCompactMode
local RefreshCompactButtonEnabledState
local RefreshScanButtonLabels
local ScanVisibleFavoriteStrats
local ShowInlineDetail
local SelectStrategyByID

-- ===== Helpers =====
local function IsFavorite(id)
    if GAM.State and GAM.State.IsFavorite then
        return GAM.State.IsFavorite(id, filterPatch, GetOpts().rankPolicy)
    end
    local pdb = GAM:GetPatchDB(filterPatch)
    return pdb.favorites and pdb.favorites[id]
end

local function ToggleFavorite(id)
    if GAM.State and GAM.State.ToggleFavorite then
        GAM.State.ToggleFavorite(id, filterPatch, GetOpts().rankPolicy)
        return
    end
    local pdb = GAM:GetPatchDB(filterPatch)
    pdb.favorites = pdb.favorites or {}
    if pdb.favorites[id] then
        pdb.favorites[id] = nil
    else
        pdb.favorites[id] = true
    end
end

local function GetL() return GAM.L end

local function IsShiftScanModifierActive()
    return IsShiftKeyDown and IsShiftKeyDown()
end

local function RememberWindowState(isOpen)
    SetOption("lastAHWindowOpen", isOpen and true or false)
end

local function ApplyTheme()
    if not frame then
        return
    end

    local theme = GetThemeDef()
    if not theme then return end

    if theme.frame then
        frame:SetBackdrop(theme.frame.backdrop)
        SetBackdropColors(frame, theme.frame.bgColor, theme.frame.borderColor)
    end
    if themeRefs.softBoard and theme.board then
        themeRefs.softBoard:SetBackdrop(theme.board.backdrop)
        SetBackdropColors(themeRefs.softBoard, theme.board.bgColor, theme.board.borderColor)
    end
    if themeRefs.headerBg then
        themeRefs.headerBg:SetColorTexture(theme.headerBackdrop[1], theme.headerBackdrop[2], theme.headerBackdrop[3], theme.headerBackdrop[4])
    end
    if themeRefs.titleText then
        themeRefs.titleText:SetTextColor(theme.titleText[1], theme.titleText[2], theme.titleText[3], theme.titleText[4])
    end
    if themeRefs.versionText then
        themeRefs.versionText:SetTextColor(theme.subtitleText[1], theme.subtitleText[2], theme.subtitleText[3], theme.subtitleText[4])
    end
    if themeRefs.infoPanelTitle and theme.cardTitleText then
        themeRefs.infoPanelTitle:SetTextColor(theme.cardTitleText[1], theme.cardTitleText[2], theme.cardTitleText[3], theme.cardTitleText[4] or 1)
    end
    if themeRefs.infoPanelBody and theme.cardBodyText then
        themeRefs.infoPanelBody:SetTextColor(theme.cardBodyText[1], theme.cardBodyText[2], theme.cardBodyText[3], theme.cardBodyText[4] or 1)
        if theme == Common.THEMES.soft and themeRefs.infoPanelBody.SetShadowColor then
            themeRefs.infoPanelBody:SetShadowOffset(1, -1)
            themeRefs.infoPanelBody:SetShadowColor(0, 0, 0, 0.10)
        end
    end
    if themeRefs.infoPanelRule and theme.cardRule then
        themeRefs.infoPanelRule:SetColorTexture(theme.cardRule[1], theme.cardRule[2], theme.cardRule[3], theme.cardRule[4] or C_DA)
    end

    for _, shell in ipairs(themeRefs.shells) do
        local spec = theme.shells and theme.shells[shell._shellVariant]
        if spec then
            shell:SetBackdrop(spec.outerBackdrop)
            SetBackdropColors(shell, spec.outerBgColor, spec.outerBorderColor)
            if shell.inner then
                Common.SetShellInsets(shell, spec.innerInsets or shell._baseInsets)
                shell.inner:SetBackdrop(spec.innerBackdrop)
                SetBackdropColors(shell.inner, spec.innerBgColor, spec.innerBorderColor)
                if shell.innerOverlay then
                    if spec.overlayTexture then
                        shell.innerOverlay:SetTexture(spec.overlayTexture)
                        local vc = spec.overlayVertexColor or { 1, 1, 1, 0.15 }
                        shell.innerOverlay:SetVertexColor(vc[1], vc[2], vc[3], vc[4] or 1)
                        shell.innerOverlay:Show()
                    else
                        shell.innerOverlay:Hide()
                    end
                end
            end
        end
    end
    for _, card in ipairs(themeRefs.paperCards) do
        if theme.paperCard then
            Common.ApplyPaperCardTheme(card, theme.paperCard)
        end
    end

    if themeRefs.leftRule then
        local c = theme.separatorColor
        themeRefs.leftRule:SetColorTexture(c[1], c[2], c[3], 0.55)
    end
    if themeRefs.titleRule then
        local c = theme.separatorColor
        themeRefs.titleRule:SetColorTexture(c[1], c[2], c[3], c[4] or C_DA)
    end
    if themeRefs.bestCardBanner then themeRefs.bestCardBanner:Hide() end
    if themeRefs.bestCardRuleLeft then themeRefs.bestCardRuleLeft:Hide() end
    if themeRefs.bestCardRuleRight then themeRefs.bestCardRuleRight:Hide() end
    if themeRefs.headerSep then
        local c = theme.separatorColor
        themeRefs.headerSep:SetColorTexture(c[1], c[2], c[3], c[4] or C_DA)
    end
    if themeRefs.tickerBg then
        themeRefs.tickerBg:SetColorTexture(theme.tickerBackdrop[1], theme.tickerBackdrop[2], theme.tickerBackdrop[3], theme.tickerBackdrop[4])
    end
    if themeRefs.tickerBorder then
        themeRefs.tickerBorder:SetColorTexture(theme.tickerBorder[1], theme.tickerBorder[2], theme.tickerBorder[3], theme.tickerBorder[4])
    end
    if themeRefs.tickerText then
        themeRefs.tickerText:SetTextColor(theme.tickerText[1], theme.tickerText[2], theme.tickerText[3], theme.tickerText[4])
    end
    if themeRefs.statusCountText then
        themeRefs.statusCountText:SetTextColor(theme.statusText[1], theme.statusText[2], theme.statusText[3], theme.statusText[4])
    end
    if themeRefs.progressText then
        themeRefs.progressText:SetTextColor(theme.progressText[1], theme.progressText[2], theme.progressText[3], theme.progressText[4])
    end
    if themeRefs.progressBar and theme.progressBar then
        themeRefs.progressBar:SetStatusBarColor(theme.progressBar[1], theme.progressBar[2], theme.progressBar[3], theme.progressBar[4] or 1)
    end
    if themeRefs.progressBarBg and theme.progressBarBg then
        themeRefs.progressBarBg:SetColorTexture(theme.progressBarBg[1], theme.progressBarBg[2], theme.progressBarBg[3], theme.progressBarBg[4] or 1)
    end
    if themeRefs.compactBtn then
        themeRefs.compactBtn:SetBackdrop(THIN_BACKDROP)
        SetBackdropColors(themeRefs.compactBtn, theme.compactBackdrop, theme.compactBorder)
    end
    if rightPanel and rightPanel.placeholder then
        rightPanel.placeholder:SetTextColor(theme.placeholderText[1], theme.placeholderText[2], theme.placeholderText[3], theme.placeholderText[4])
        if theme == Common.THEMES.soft and rightPanel.placeholder.SetShadowColor then
            rightPanel.placeholder:SetShadowOffset(1, -1)
            rightPanel.placeholder:SetShadowColor(0, 0, 0, 0.08)
        end
        ApplyFontSize(rightPanel.placeholder, theme == Common.THEMES.soft and 12 or 11)
    end
    if theme.bodyText then
        for _, row in ipairs(rowFrames) do
            if row.nameText then
                row.nameText:SetTextColor(theme.bodyText[1], theme.bodyText[2], theme.bodyText[3], theme.bodyText[4] or 1)
                ApplyFontSize(row.nameText, theme == Common.THEMES.soft and 10 or 11)
                if theme == Common.THEMES.soft and row.nameText.SetShadowColor then
                    row.nameText:SetShadowOffset(1, -1)
                    row.nameText:SetShadowColor(0, 0, 0, 0.08)
                end
            end
            if row.profText then
                local muted = theme.mutedText or theme.bodyText
                row.profText:SetTextColor(muted[1], muted[2], muted[3], muted[4] or 1)
                ApplyFontSize(row.profText, theme == Common.THEMES.soft and 9 or 10)
                if theme == Common.THEMES.soft and row.profText.SetShadowColor then
                    row.profText:SetShadowOffset(1, -1)
                    row.profText:SetShadowColor(0, 0, 0, 0.06)
                end
            end
            if row.profSubText then
                local muted = theme.mutedText or theme.bodyText
                row.profSubText:SetTextColor(muted[1], muted[2], muted[3], muted[4] or 1)
                ApplyFontSize(row.profSubText, theme == Common.THEMES.soft and 9 or 10)
                if theme == Common.THEMES.soft and row.profSubText.SetShadowColor then
                    row.profSubText:SetShadowOffset(1, -1)
                    row.profSubText:SetShadowColor(0, 0, 0, 0.06)
                end
            end
            if row.profitText then
                ApplyFontSize(row.profitText, theme == Common.THEMES.soft and 9 or 10)
            end
            if row.roiText then
                ApplyFontSize(row.roiText, theme == Common.THEMES.soft and 9 or 10)
            end
            if row.missingText then
                ApplyFontSize(row.missingText, theme == Common.THEMES.soft and 9 or 10)
            end
        end
        if rpDetail.profFS then
            local muted = theme.mutedText or theme.bodyText
            rpDetail.profFS:SetTextColor(muted[1], muted[2], muted[3], muted[4] or 1)
            if theme == Common.THEMES.soft and rpDetail.profFS.SetShadowColor then
                rpDetail.profFS:SetShadowOffset(1, -1)
                rpDetail.profFS:SetShadowColor(0, 0, 0, 0.06)
            end
        end
        if rpDetail.outputSummaryLabelFS then
            local muted = theme.mutedText or theme.bodyText
            rpDetail.outputSummaryLabelFS:SetTextColor(muted[1], muted[2], muted[3], muted[4] or 1)
            ApplyFontSize(rpDetail.outputSummaryLabelFS, theme == Common.THEMES.soft and 10 or 11)
            if theme == Common.THEMES.soft and rpDetail.outputSummaryLabelFS.SetShadowColor then
                rpDetail.outputSummaryLabelFS:SetShadowOffset(1, -1)
                rpDetail.outputSummaryLabelFS:SetShadowColor(0, 0, 0, 0.06)
            end
        end
        if rpDetail.outputSummaryNameFS then
            rpDetail.outputSummaryNameFS:SetTextColor(theme.bodyText[1], theme.bodyText[2], theme.bodyText[3], theme.bodyText[4] or 1)
            ApplyFontSize(rpDetail.outputSummaryNameFS, theme == Common.THEMES.soft and 10 or 11)
            if theme == Common.THEMES.soft and rpDetail.outputSummaryNameFS.SetShadowColor then
                rpDetail.outputSummaryNameFS:SetShadowOffset(1, -1)
                rpDetail.outputSummaryNameFS:SetShadowColor(0, 0, 0, 0.06)
            end
        end
        if rpDetail.notesFS then
            local muted = theme.mutedText or theme.bodyText
            rpDetail.notesFS:SetTextColor(muted[1], muted[2], muted[3], muted[4] or 1)
            if theme == Common.THEMES.soft and rpDetail.notesFS.SetShadowColor then
                rpDetail.notesFS:SetShadowOffset(1, -1)
                rpDetail.notesFS:SetShadowColor(0, 0, 0, 0.06)
            end
        end
        local function ApplyDetailRowColors(rows)
            for _, row in ipairs(rows or {}) do
                if row.nameFS then
                    row.nameFS:SetTextColor(theme.bodyText[1], theme.bodyText[2], theme.bodyText[3], theme.bodyText[4] or 1)
                    if theme == Common.THEMES.soft and row.nameFS.SetShadowColor then
                        row.nameFS:SetShadowOffset(1, -1)
                        row.nameFS:SetShadowColor(0, 0, 0, 0.06)
                    end
                end
                if row.qtyFS then
                    local muted = theme.mutedText or theme.bodyText
                    row.qtyFS:SetTextColor(muted[1], muted[2], muted[3], muted[4] or 1)
                    if theme == Common.THEMES.soft and row.qtyFS.SetShadowColor then
                        row.qtyFS:SetShadowOffset(1, -1)
                        row.qtyFS:SetShadowColor(0, 0, 0, 0.06)
                    end
                end
                if row.needFS then
                    local muted = theme.mutedText or theme.bodyText
                    row.needFS:SetTextColor(muted[1], muted[2], muted[3], muted[4] or 1)
                    if theme == Common.THEMES.soft and row.needFS.SetShadowColor then
                        row.needFS:SetShadowOffset(1, -1)
                        row.needFS:SetShadowColor(0, 0, 0, 0.06)
                    end
                end
                if row.priceFS then
                    row.priceFS:SetTextColor(theme.bodyText[1], theme.bodyText[2], theme.bodyText[3], theme.bodyText[4] or 1)
                    if theme == Common.THEMES.soft and row.priceFS.SetShadowColor then
                        row.priceFS:SetShadowOffset(1, -1)
                        row.priceFS:SetShadowColor(0, 0, 0, 0.06)
                    end
                end
            end
        end
        ApplyDetailRowColors(rpDetail.reagentRows)
        ApplyDetailRowColors(rpDetail.outputRows)
    end

    for _, btn in ipairs(themeRefs.collapseButtons) do
        SetBackdropColors(btn, theme.collapseBackdrop, theme.collapseBorder)
    end
    if rpDetail.reagentHeaderBg then
        rpDetail.reagentHeaderBg:SetColorTexture(theme.sectionHeader[1], theme.sectionHeader[2], theme.sectionHeader[3], theme.sectionHeader[4])
    end
    if rpDetail.outputHeaderBg then
        rpDetail.outputHeaderBg:SetColorTexture(theme.sectionHeader[1], theme.sectionHeader[2], theme.sectionHeader[3], theme.sectionHeader[4])
    end

    for i, bg in ipairs(themeRefs.reagentRowBgs) do
        local color = (i % 2 == 1) and theme.listRowOdd or theme.listRowEven
        bg:SetColorTexture(color[1], color[2], color[3], color[4])
    end
    for i, bg in ipairs(themeRefs.outputRowBgs) do
        local color = (i % 2 == 1) and theme.listRowOdd or theme.listRowEven
        bg:SetColorTexture(color[1], color[2], color[3], color[4])
    end
end

local function BuildDiscordPopup(L)
    discordPopup = CreateFrame("Frame", "GAMDiscordPopup", UIParent, "BackdropTemplate")
    discordPopup:SetSize(440, 150)
    discordPopup:SetPoint("CENTER")
    discordPopup:SetScale(GetUIScale())
    discordPopup:SetMovable(true)
    discordPopup:EnableMouse(true)
    discordPopup:RegisterForDrag("LeftButton")
    discordPopup:SetScript("OnDragStart", discordPopup.StartMoving)
    discordPopup:SetScript("OnDragStop", discordPopup.StopMovingOrSizing)
    discordPopup:SetClampedToScreen(true)
    discordPopup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    discordPopup:SetBackdropColor(0, 0, 0, 1)
    discordPopup:Hide()
    WindowManager.Register(discordPopup, "modal")

    local title = discordPopup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", discordPopup, "TOP", 0, -14)
    title:SetText("Discord")

    local closeX = CreateFrame("Button", nil, discordPopup, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", discordPopup, "TOPRIGHT", -4, -4)
    closeX:SetScript("OnClick", function()
        discordPopup:Hide()
    end)

    local prompt = discordPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    prompt:SetPoint("TOPLEFT", discordPopup, "TOPLEFT", 18, -44)
    prompt:SetPoint("TOPRIGHT", discordPopup, "TOPRIGHT", -18, -44)
    prompt:SetJustifyH("LEFT")
    prompt:SetText("Copy or share this Discord invite link:")

    local editBox = CreateFrame("EditBox", nil, discordPopup, "InputBoxTemplate")
    editBox:SetSize(392, 32)
    editBox:SetPoint("TOPLEFT", discordPopup, "TOPLEFT", 24, -72)
    editBox:SetAutoFocus(false)
    editBox:SetMultiLine(false)
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetTextInsets(6, 6, 0, 0)
    editBox:SetScript("OnEscapePressed", function()
        discordPopup:Hide()
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        self:HighlightText()
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    discordPopup.editBox = editBox

    local closeBtn = CreateFrame("Button", nil, discordPopup, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", discordPopup, "BOTTOMRIGHT", -14, 10)
    closeBtn:SetText((L and L["BTN_CLOSE"]) or "Close")
    closeBtn:SetScript("OnClick", function()
        discordPopup:Hide()
    end)
end

local function ShowDiscordPopup(L)
    if not discordPopup then
        BuildDiscordPopup(L)
    end
    discordPopup:SetScale(GetUIScale())
    discordPopup.editBox:SetText(DISCORD_INVITE_URL)
    discordPopup:Show()
    WindowManager.Present(discordPopup)
    discordPopup.editBox:SetFocus()
    discordPopup.editBox:HighlightText()
end

local function CreateShell(parent, variant, insets)
    return Common.CreateShell(parent, variant, insets, themeRefs.shells)
end

local function IsClickInFavoriteGutter(frameObj)
    return Common.IsClickInFavoriteGutter(frameObj, STRAT_ICON_W)
end

local function ClearListMetricCache()
    listMetricCache = {}
    listMetricPatch = filterPatch
    bestStratCardDirty = true
end

local function GetListMetric(strat)
    if not strat then return nil end
    if listMetricPatch ~= filterPatch then
        ClearListMetricCache()
    end
    local id = strat.id
    if id and listMetricCache[id] == nil then
        listMetricCache[id] = GAM.Pricing.CalculateStratMetrics(strat, filterPatch)
    end
    return id and listMetricCache[id] or GAM.Pricing.CalculateStratMetrics(strat, filterPatch)
end

local function InvalidateListMetric(stratID, patchTag)
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    if patchTag ~= filterPatch then
        return
    end
    if stratID then
        listMetricCache[stratID] = nil
        listMetricPatch = filterPatch
        bestStratCardDirty = true
        return
    end
    ClearListMetricCache()
end

local function GetStratMetric(strat, patchTag)
    if not strat then return nil end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    if patchTag == filterPatch then
        return GetListMetric(strat)
    end
    return GAM.Pricing.CalculateStratMetrics(strat, patchTag)
end

local function BuildPlayerProfessionSet()
    return Common.BuildPlayerProfessionSet(filterPatch)
end

local function HasAnyEntries(set)
    return Common.HasAnyEntries(set)
end

local function BuildFrameHeader(L, C, HDR_PX)
    local softInk = IsSoftThemeLayout()
    local headerBg = frame:CreateTexture(nil, "BACKGROUND")
    headerBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -4)
    headerBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -4)
    headerBg:SetHeight(HDR_PX - 4)
    themeRefs.headerBg = headerBg

    local titleFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOP", frame, "TOP", 0, softInk and -7 or -6)
    titleFS:SetText(L["ADDON_TITLE"])
    titleFS:SetTextColor(C_GR, C_GG, C_GB)
    ApplyFontSize(titleFS, softInk and 15 or 14)
    ApplyTextShadow(titleFS)
    themeRefs.titleText = titleFS

    local verFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -1)
    verFS:SetText("v" .. (GAM.C.ADDON_VERSION or "?"))
    verFS:SetTextColor(0.55, 0.45, 0.0, 1)
    ApplyFontSize(verFS, 10)
    ApplyTextShadow(verFS, 0.75)
    themeRefs.versionText = verFS

    local titleRule = frame:CreateTexture(nil, "ARTWORK")
    titleRule:SetHeight(1)
    titleRule:SetPoint("TOPLEFT",  frame, "TOPLEFT",  14, -HDR_PX)
    titleRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -HDR_PX)
    titleRule:SetColorTexture(C_DR, C_DG, C_DB, C_DA)
    themeRefs.titleRule = titleRule

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() MW2.Hide() end)

    compactBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    compactBtn:SetSize(52, 20)
    compactBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -6, -1)
    compactBtn:SetBackdrop(THIN_BACKDROP)
    compactBtn:EnableMouse(true)
    compactBtn:RegisterForClicks("LeftButtonUp")
    themeRefs.compactBtn = compactBtn
    local cBtnLbl = compactBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cBtnLbl:SetAllPoints()
    cBtnLbl:SetJustifyH("CENTER")
    cBtnLbl:SetText("DETAIL")
    cBtnLbl:SetTextColor(C_GR * 0.4, C_GG * 0.4, C_GB * 0.4)
    ApplyFontSize(cBtnLbl, 11)
    ApplyTextShadow(cBtnLbl)
    compactBtn.labelFS = cBtnLbl
    compactBtn:Disable()
    compactBtn:SetScript("OnClick", ToggleCompactMode)
    AttachButtonTooltip(compactBtn,
        (L and L["TT_BTN_COMPACT_TITLE"]) or "Compact Mode",
        (L and L["TT_BTN_COMPACT_BODY"])  or "Show only the strategy detail panel.")
end

local function BuildStatusAndTicker(L, C, SB_H)
    local tickerHeight = GetTickerHeight(C)
    statusBarShell, statusBarFrame = CreateShell(frame, "status", { left = 4, right = 4, top = 4, bottom = 4 })
    statusBarShell:SetHeight(SB_H)
    statusBarShell:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  14, tickerHeight + 8)
    statusBarShell:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, tickerHeight + 8)

    local statusCountText = statusBarFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusCountText:SetPoint("LEFT", statusBarFrame, "LEFT", 10, 0)
    ApplyFontSize(statusCountText, 11)
    ApplyTextShadow(statusCountText, 0.75)
    frame.statusCountText = statusCountText
    themeRefs.statusCountText = statusCountText

    local progBar = CreateFrame("StatusBar", nil, statusBarFrame)
    progBar:SetPoint("TOPLEFT",  statusBarFrame, "TOPLEFT",  108, -6)
    progBar:SetPoint("TOPRIGHT", statusBarFrame, "TOPRIGHT", -12, -6)
    progBar:SetHeight(15)
    progBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progBar:SetStatusBarColor(0.22, 0.62, 0.24, 1)
    progBar:SetMinMaxValues(0, 1)
    progBar:SetValue(0)
    local progBg = progBar:CreateTexture(nil, "BACKGROUND")
    progBg:SetAllPoints()
    progBg:SetColorTexture(0.08, 0.06, 0.04, 0.92)
    local progLabel = progBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progLabel:SetPoint("CENTER", progBar, "CENTER")
    progLabel:SetText("")
    ApplyTextShadow(progLabel)
    progBar:Hide()
    frame.progBar   = progBar
    frame.progLabel = progLabel
    themeRefs.progressText = progLabel
    themeRefs.progressBar = progBar
    themeRefs.progressBarBg = progBg

    scanBtnStatus = CreateFrame("Button", nil, statusBarFrame, "UIPanelButtonTemplate")
    scanBtnStatus:SetSize(82, 18)
    scanBtnStatus:SetText(L["BTN_SCAN_ALL"])
    scanBtnStatus:SetPoint("RIGHT", statusBarFrame, "RIGHT", -2, 0)
    scanBtnStatus:SetScript("OnClick", DoScan)
    scanBtnStatus:Hide()

    local TICK_H  = tickerHeight
    local tickerClip = CreateFrame("Frame", nil, frame)
    tickerClip:SetHeight(TICK_H)
    tickerClip:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  14, 6)
    tickerClip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 6)

    local tickerBg = tickerClip:CreateTexture(nil, "BACKGROUND")
    tickerBg:SetAllPoints()
    tickerBg:SetColorTexture(0.05, 0.05, 0.05, 1)
    themeRefs.tickerBg = tickerBg

    local tickerBorder = tickerClip:CreateTexture(nil, "ARTWORK")
    tickerBorder:SetHeight(1)
    tickerBorder:SetPoint("TOPLEFT",  tickerClip, "TOPLEFT",  0, 0)
    tickerBorder:SetPoint("TOPRIGHT", tickerClip, "TOPRIGHT", 0, 0)
    tickerBorder:SetColorTexture(C_DR, C_DG, C_DB, 0.35)
    themeRefs.tickerBorder = tickerBorder

    local SEP = "   \124cff888888\183\124r   "
    local tickerFS = tickerClip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tickerFS:SetPoint("LEFT",  tickerClip, "LEFT",  8, 0)
    tickerFS:SetPoint("RIGHT", tickerClip, "RIGHT", -8, 0)
    tickerFS:SetJustifyH("CENTER")
    tickerFS:SetWordWrap(false)
    tickerFS:SetText(
        "\124cffffcc00[Gold Advisor Midnight]\124r" ..
        SEP .. "For support and community:" ..
        SEP .. "\124cff7289daDiscord:\124r  " .. DISCORD_INVITE_CODE ..
        SEP .. "\124cff666666v" .. (GAM.version or "?") .. "\124r"
    )
    ApplyFontSize(tickerFS, FOOTER_TEXT_SIZE)
    tickerFS:SetTextColor(0.75, 0.75, 0.75, 1)
    tickerFS:SetShadowOffset(1, -1)
    tickerFS:SetShadowColor(0, 0, 0, 0.9)

    local tickerButton = CreateFrame("Button", nil, tickerClip)
    tickerButton:SetAllPoints(tickerClip)
    tickerButton:RegisterForClicks("LeftButtonUp")
    tickerButton:SetScript("OnClick", function()
        ShowDiscordPopup(L)
    end)
    tickerButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Discord", 1, 1, 1)
        GameTooltip:AddLine("Click to copy the invite link.", 1, 0.82, 0, true)
        GameTooltip:AddLine(DISCORD_INVITE_URL, 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    tickerButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    themeRefs.tickerText = tickerFS
    frame.tickerClip = tickerClip
end

local function FinalizeBuildOnShow(sb, C)
    frame:SetScript("OnShow", function()
        local opts = GetOpts()
        ApplyTheme()
        UpdateCollapseButtonAnchors()
        RelayoutPanels()
        sb:ClearAllPoints()
        sb:SetPoint("TOPRIGHT",    centerPanel, "TOPRIGHT",    -6,  -scrollBarTopOffset)
        sb:SetPoint("BOTTOMRIGHT", centerPanel, "BOTTOMRIGHT", -6,  0)
        RebuildList()
        MW2.RefreshRows()
        RefreshBestStratCard()
        if leftPanel and leftPanel.refreshRankDropdown then
            leftPanel.refreshRankDropdown()
        end
        if leftPanel and leftPanel.refreshStatEditors then
            leftPanel.refreshStatEditors()
        end
        if RefreshScanButtonLabels then
            RefreshScanButtonLabels()
        end
        RefreshCompactButtonEnabledState()
        if not opts.hasSeenOnboarding then
            opts.hasSeenOnboarding = true
            onboardingOverlay:Hide()
        end
    end)
end

local function SafeBuildSection(label, fn)
    local ok, err = xpcall(fn, function(message)
        local stack = debugstack and debugstack(2, 6, 6) or ""
        return tostring(message) .. (stack ~= "" and ("\n" .. stack) or "")
    end)
    if not ok then
        print("|cffff8800[GAM]|r " .. tostring(label) .. " failed while building V2 UI.")
        if err and err ~= "" then
            print(err)
        end
    end
    return ok
end

local function StratMatchesFilter(strat)
    return Common.StratMatchesFilter(strat, filterMode, filterProfSet, filterProf, filterProfSingle, GetOpts().rankPolicy)
end

local function GetActiveColumnConfig()
    return Common.GetActiveColumnConfig(filterMode, filterProf, LIST_COLUMNS_ALL, LIST_COLUMNS_FILTERED)
end

local function SetInputQtyOverride(stratID, patchTag, value)
    if not stratID then return end
    local pdb = GAM:GetPatchDB(patchTag or GAM.C.DEFAULT_PATCH)
    pdb.inputQtyOverrides = pdb.inputQtyOverrides or {}
    local n = tonumber(value)
    if n and n > 0 then
        pdb.inputQtyOverrides[stratID] = n
    else
        pdb.inputQtyOverrides[stratID] = nil
    end
    InvalidateListMetric(stratID, patchTag)
end

local function SetCraftsOverride(stratID, patchTag, value)
    if not stratID then return end
    local pdb = GAM:GetPatchDB(patchTag or GAM.C.DEFAULT_PATCH)
    pdb.craftsOverrides = pdb.craftsOverrides or {}
    local n = tonumber(value)
    if n and n > 0 then
        pdb.craftsOverrides[stratID] = math.floor(n)
    else
        pdb.craftsOverrides[stratID] = nil
    end
    InvalidateListMetric(stratID, patchTag)
end

local function ClampFillQtyValue(value)
    return Common.ClampFillQtyValue(
        value, GAM.C.MIN_FILL_QTY, GAM.C.MAX_FILL_QTY, GAM.C.DEFAULT_FILL_QTY)
end

local function ClampStatPercentValue(value, fallback)
    return Common.ClampStatPercentValue(value, fallback)
end

local function FormatStatPercentValue(value)
    return Common.FormatStatPercentValue(value)
end

local function AddThousandsSeparators(text)
    local sign, digits, frac = tostring(text or ""):match("^([%-]?)(%d+)(%.%d+)?$")
    if not digits then
        return tostring(text or "")
    end
    return sign .. digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") .. (frac or "")
end

local function FormatQuantityValue(value, decimals)
    if value == nil then
        return "0"
    end
    local number = tonumber(value) or 0
    local rounded = math.floor(number + 0.5)
    if math.abs(number - rounded) < 0.05 then
        return AddThousandsSeparators(tostring(rounded))
    end
    local places = decimals or 1
    local text = string.format("%." .. tostring(places) .. "f", number):gsub("0+$", ""):gsub("%.$", "")
    return AddThousandsSeparators(text)
end

local function BindItemRow(frameObj, display)
    frameObj._itemDisplay = display
    frameObj:EnableMouse(display and display.hasSafeLink and display.itemLink and true or false)
end

local function ItemRowClick(self, button)
    local display = self and self._itemDisplay
    local link = display and display.itemLink
    if not link or link == "" then return end
    if HandleModifiedItemClick and HandleModifiedItemClick(link) then
        return
    end
    local itemString = link:match("|H([^|]+)|h")
    if itemString then
        SetItemRef(itemString, link, button)
    end
end

local function FormatExpectedOutputTooltip(qty, qtyRaw)
    local raw = tonumber(qtyRaw)
    if raw and math.abs(raw - math.floor(raw + 0.5)) > 0.01 then
        return FormatQuantityValue(raw, 2)
    end
    return FormatQuantityValue(qty or 0)
end

local function ItemRowEnter(self)
    local display = self and self._itemDisplay
    local link = display and display.itemLink
    local L = GetL()
    if not link or link == "" then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(link)
    local tt = self and self._metricTooltip
    if tt then
        GameTooltip:AddLine(" ")
        if tt.kind == "reagent" then
            GameTooltip:AddLine(string.format((L and L["TT_ROW_UNIT_PRICE"]) or "Unit Price: %s", tt.unitPrice and GAM.Pricing.FormatPrice(tt.unitPrice) or "|cffff8800—|r"), 1, 0.82, 0)
            GameTooltip:AddLine(string.format((L and L["TT_ROW_TOTAL_REQUIRED"]) or "Total Required: %s", FormatQuantityValue(tt.required or 0)), 1, 0.82, 0)
            GameTooltip:AddLine(string.format((L and L["TT_ROW_NEED_TO_BUY"]) or "Need to Buy: %s", FormatQuantityValue(tt.needToBuy or 0)), 1, 0.82, 0)
            GameTooltip:AddLine(string.format((L and L["TT_ROW_FULL_COST"]) or "Full Cost: %s", tt.totalCostFull and GAM.Pricing.FormatPrice(tt.totalCostFull) or "|cff888888—|r"), 1, 0.82, 0)
            if tt.totalCost and tt.totalCostFull and tt.totalCost ~= tt.totalCostFull then
                GameTooltip:AddLine(string.format((L and L["TT_ROW_BUY_NOW_COST"]) or "Buy Now Cost: %s", GAM.Pricing.FormatPrice(tt.totalCost)), 1, 0.82, 0)
            end
        elseif tt.kind == "output" then
            GameTooltip:AddLine(string.format((L and L["TT_ROW_UNIT_SELL_PRICE"]) or "Unit Sell Price: %s", tt.unitPrice and GAM.Pricing.FormatPrice(tt.unitPrice) or "|cffff8800—|r"), 1, 0.82, 0)
            GameTooltip:AddLine(string.format((L and L["TT_ROW_EXPECTED_OUTPUT"]) or "Expected Output: %s", FormatExpectedOutputTooltip(tt.expectedQty, tt.expectedQtyRaw)), 1, 0.82, 0)
            GameTooltip:AddLine(string.format((L and L["TT_ROW_TOTAL_NET_REVENUE"]) or "Total Net Revenue: %s", tt.netRevenue and GAM.Pricing.FormatPrice(tt.netRevenue) or "|cff888888—|r"), 1, 0.82, 0)
            GameTooltip:AddLine((L and L["TT_ROW_NET_NOTE"]) or "The visible Net column is craft-level net revenue, not a per-item price.", 1, 0.82, 0, true)
        end
    end
    GameTooltip:Show()
end

local function ItemRowLeave()
    GameTooltip:Hide()
end

local function BuildAuctionatorShoppingPayload(strat, patchTag)
    if not (Auctionator and Auctionator.API and Auctionator.API.v1 and
            type(Auctionator.API.v1.CreateShoppingList) == "function") then
        print("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_NOT_FOUND"])
        return nil
    end
    if not strat then return nil end
    local m = GetStratMetric(strat, patchTag or GAM.C.DEFAULT_PATCH)
    if not m then return nil end

    local addonName  = "GoldAdvisorMidnight"
    local hasConvert = type(Auctionator.API.v1.ConvertToSearchString) == "function"
    local searchStrings = {}
    local signatureParts = {}
    local items = {}

    for _, rm in ipairs(m.reagents or {}) do
        local qty = math.floor(rm.needToBuy or 0)
        if qty > 0 then
            local entry
            local searchData = GAM.Pricing.GetShoppingSearchData(rm.itemID, rm.name)
            if hasConvert then
                local qualityID = (rm.itemID and C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo)
                    and C_TradeSkillUI.GetItemReagentQualityByItemInfo(rm.itemID) or nil
                local searchTerm = {
                    searchString = searchData.searchName or rm.name,
                    quantity = qty,
                    isExact = true,
                }
                if qualityID and qualityID > 0 then searchTerm.tier = qualityID end
                entry = Auctionator.API.v1.ConvertToSearchString(addonName, searchTerm)
            else
                entry = searchData.searchString
            end
            if entry then
                searchStrings[#searchStrings + 1] = entry
                signatureParts[#signatureParts + 1] = entry
                items[#items + 1] = {
                    searchString = entry,
                    itemID = rm.itemID,
                    name = searchData.displayName,
                    quantity = qty,
                }
            end
        end
    end

    table.sort(signatureParts)
    local signature = table.concat(signatureParts, "\031")
    return {
        addonName = addonName,
        listName = GAM.L["AUCTIONATOR_LIST_NAME"],
        metrics = m,
        searchStrings = searchStrings,
        items = items,
        signature = signature,
    }
end

local function CreateAuctionatorShoppingList(strat, patchTag, quiet)
    local payload = BuildAuctionatorShoppingPayload(strat, patchTag)
    if not payload then return nil end

    if #payload.searchStrings == 0 and not quiet then
        print("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_NO_ITEMS"])
    end

    Auctionator.API.v1.CreateShoppingList(payload.addonName, payload.listName, payload.searchStrings)
    GAM.quickBuyList = {
        listName = payload.listName,
        entries = payload.items,
        signature = payload.signature,
    }
    if not quiet then
        print(string.format("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_CREATED"], payload.listName, #payload.searchStrings))
    end
    return payload
end

local function DisableShoppingSync(silent)
    shoppingSync.active = false
    shoppingSync.stratID = nil
    shoppingSync.patchTag = nil
    shoppingSync.lastSignature = nil
    shoppingSync.pending = false
    if shoppingSyncFrame then
        shoppingSyncFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
        shoppingSyncFrame:UnregisterEvent("AUCTION_HOUSE_CLOSED")
    end
    if not silent then
        print("|cffff8800[GAM]|r Auctionator shopping sync stopped.")
    end
end

local function RefreshShoppingSync()
    if not shoppingSync.active then return end
    local strat = shoppingSync.stratID and GAM.Importer.GetStratByID(shoppingSync.stratID) or nil
    if not strat then
        DisableShoppingSync(true)
        return
    end

    local payload = BuildAuctionatorShoppingPayload(strat, shoppingSync.patchTag)
    if not payload then
        DisableShoppingSync(true)
        return
    end
    if payload.signature == shoppingSync.lastSignature then
        return
    end

    Auctionator.API.v1.CreateShoppingList(payload.addonName, payload.listName, payload.searchStrings)
    GAM.quickBuyList = {
        listName = payload.listName,
        entries = payload.items,
        signature = payload.signature,
    }
    shoppingSync.lastSignature = payload.signature
    if leftPanel and leftPanel.refreshVisiblePanels then
        leftPanel.refreshVisiblePanels()
    end
end

local function EnsureShoppingSyncFrame()
    if shoppingSyncFrame then return end
    shoppingSyncFrame = CreateFrame("Frame")
    shoppingSyncFrame:SetScript("OnEvent", function(_, event)
        if event == "BAG_UPDATE_DELAYED" then
            if shoppingSync.pending then return end
            shoppingSync.pending = true
            C_Timer.After(0.15, function()
                shoppingSync.pending = false
                RefreshShoppingSync()
            end)
        elseif event == "AUCTION_HOUSE_CLOSED" then
            DisableShoppingSync(true)
        end
    end)
end

local function ToggleShoppingSync(strat, patchTag)
    if not strat then return end
    if shoppingSync.active and shoppingSync.stratID == strat.id and shoppingSync.patchTag == (patchTag or GAM.C.DEFAULT_PATCH) then
        DisableShoppingSync()
        return
    end

    local payload = CreateAuctionatorShoppingList(strat, patchTag)
    if not payload then return end

    EnsureShoppingSyncFrame()
    shoppingSync.active = true
    shoppingSync.stratID = strat.id
    shoppingSync.patchTag = patchTag or GAM.C.DEFAULT_PATCH
    shoppingSync.lastSignature = payload.signature
    shoppingSync.pending = false
    shoppingSyncFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    shoppingSyncFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
    print(string.format("|cffff8800[GAM]|r Auctionator shopping sync armed for '%s'.", strat.stratName or "strategy"))
end

local function ScanSingleStrategy(strat, patchTag, callback)
    if not strat or not GAM.AHScan then return end
    if not GAM.ahOpen then
        local L = GetL()
        print("|cffff8800[GAM]|r " .. (L and L["ERR_NO_AH"] or "Open the Auction House first."))
        return
    end
    local pt = patchTag or GAM.C.DEFAULT_PATCH
    local pdb = GAM:GetPatchDB(pt)

    GAM.AHScan.StopScan()
    GAM.AHScan.ResetQueue()

    local displayedMetrics = GetStratMetric(strat, pt)
    local displayed = (GAM.Pricing and GAM.Pricing.GetDisplayedItemSet and GAM.Pricing.GetDisplayedItemSet(strat, pt, displayedMetrics)) or strat
    local seenIDs = {}
    local seenNames = {}

    local function queueItem(item)
        if not item or not item.name then return end
        local ids = item.itemIDs
        if not ids or #ids == 0 then
            ids = pdb.rankGroups and pdb.rankGroups[item.name] or nil
        end
        if ids and #ids > 0 then
            for _, id in ipairs(ids) do
                if not seenIDs[id] then
                    seenIDs[id] = true
                    GAM.AHScan.QueueItemScan(id, callback)
                end
            end
        else
            local nameKey = item.name .. "@" .. pt
            if not seenNames[nameKey] then
                seenNames[nameKey] = true
                GAM.AHScan.QueueNameScan(item.name, pt, callback)
            end
        end
    end

    queueItem(displayed.output)
    for _, o in ipairs(displayed.outputs or {}) do queueItem(o) end
    for _, r in ipairs(displayed.reagents or {}) do queueItem(r) end
    local extraScanItems = (GAM.Pricing and GAM.Pricing.GetExtraScanItems and GAM.Pricing.GetExtraScanItems(strat, pt)) or {}
    for _, extra in ipairs(extraScanItems) do queueItem(extra) end
    GAM.AHScan.StartScan()
end

local function ScanSelectedStrategyAction(strat, patchTag, callback)
    if not strat then
        return
    end
    if IsShiftScanModifierActive() then
        ScanVisibleFavoriteStrats()
        return
    end
    ScanSingleStrategy(strat, patchTag, callback)
end

UpdateCollapseButtonAnchors = function()
    if not frame or not centerPanelShell then return end
    local opts = GetOpts()
    if frame.btnCollapseLeft then
        frame.btnCollapseLeft.labelFS:SetText(opts.leftPanelCollapsed and ">" or "<")
        frame.btnCollapseLeft:ClearAllPoints()
        frame.btnCollapseLeft:SetPoint("RIGHT", centerPanelShell, "LEFT", 0, 0)
    end
    if frame.btnCollapseRight then
        frame.btnCollapseRight.labelFS:SetText(opts.rightPanelCollapsed and "<" or ">")
        frame.btnCollapseRight:ClearAllPoints()
        frame.btnCollapseRight:SetPoint("LEFT", centerPanelShell, "RIGHT", 0, 0)
    end
end

local function GetVisibleListRows()
    return Common.GetVisibleListRows(listHost, ROW_H, GetLayoutSpec().maxVisibleRows or VISIBLE_ROWS)
end

-- ===== Sort =====
local SORT_FNS = {
    stratName  = function(a, b) return a.stratName < b.stratName end,
    profession = function(a, b) return a.profession < b.profession end,
    profit = function(a, b)
        local ma = GetListMetric(a)
        local mb = GetListMetric(b)
        return ((ma and ma.profit) or -math.huge) > ((mb and mb.profit) or -math.huge)
    end,
    roi = function(a, b)
        local ma = GetListMetric(a)
        local mb = GetListMetric(b)
        return ((ma and ma.roi) or -math.huge) > ((mb and mb.roi) or -math.huge)
    end,
}

RebuildList = function()
    local all = GAM.Importer.GetAllStrats(filterPatch)
    local out = {}
    ClearListMetricCache()
    if selectedStratID and not GAM.Importer.GetStratByID(selectedStratID) then
        selectedStratID = nil
    end
    for _, s in ipairs(all) do
        if StratMatchesFilter(s) then
            out[#out + 1] = s
        end
    end

    -- Pre-compute metrics for expensive sort keys so each strategy is evaluated
    -- exactly once (O(n)) rather than once per comparison pair (O(n log n)).
    -- Fixes severe FPS drop on second scan when the price cache is populated
    -- and ComputePriceForQty runs the full order-book simulation per call.
    local fn = SORT_FNS[sortKey]
    if sortKey == "profit" or sortKey == "roi" then
        if sortKey == "profit" then
            fn = function(a, b)
                local ma, mb = GetListMetric(a), GetListMetric(b)
                return ((ma and ma.profit) or -math.huge) > ((mb and mb.profit) or -math.huge)
            end
        else
            fn = function(a, b)
                local ma, mb = GetListMetric(a), GetListMetric(b)
                return ((ma and ma.roi) or -math.huge) > ((mb and mb.roi) or -math.huge)
            end
        end
    end
    fn = fn or SORT_FNS.roi

    table.sort(out, function(a, b)
        local af, bf = IsFavorite(a.id), IsFavorite(b.id)
        if af and not bf then return true end
        if bf and not af then return false end
        if sortAsc then return fn(a, b) else return fn(b, a) end
    end)
    filteredList = out
    if selectedStratID then
        local stillVisible = false
        for _, s in ipairs(filteredList) do
            if s.id == selectedStratID then
                stillVisible = true
                break
            end
        end
        if not stillVisible then
            selectedStratID = nil
        end
    end
    for _, s in ipairs(filteredList) do
        GetListMetric(s)
    end
    scrollOffset = 0
    if RefreshScanButtonLabels then
        RefreshScanButtonLabels()
    end
end

-- ===== DoScan =====
local function DoScan()
    local L = GetL()
    if GAM.AHScan and GAM.AHScan.IsScanning and GAM.AHScan.IsScanning() then
        GAM.AHScan.StopScan()
        return
    end
    if not GAM.ahOpen then
        print("|cffff8800[GAM]|r " .. (L and L["ERR_NO_AH"] or "Open the Auction House first."))
        return
    end
    GAM.AHScan.ResetQueue()
    if IsShiftKeyDown and IsShiftKeyDown() then
        GAM.AHScan.QueueAllStratItems(filterPatch)
    else
        GAM.AHScan.QueueStratListItems(filteredList, filterPatch)
    end
    GAM.AHScan.StartScan()
end

local function GetVisibleFavoriteStrats()
    local favorites = {}
    for _, strat in ipairs(filteredList or {}) do
        if strat and strat.id and IsFavorite(strat.id) then
            favorites[#favorites + 1] = strat
        end
    end
    return favorites
end

ScanVisibleFavoriteStrats = function()
    local L = GetL()
    if not GAM.AHScan then
        return
    end
    if not GAM.ahOpen then
        print("|cffff8800[GAM]|r " .. (L and L["ERR_NO_AH"] or "Open the Auction House first."))
        return
    end

    local favorites = GetVisibleFavoriteStrats()
    if #favorites == 0 then
        print("|cffff8800[GAM]|r " .. ((L and L["MSG_NO_VISIBLE_FAVORITES_TO_SCAN"]) or "No visible favorites to scan."))
        return
    end

    GAM.AHScan.StopScan()
    GAM.AHScan.ResetQueue()
    GAM.AHScan.QueueStratListItems(favorites, filterPatch)
    GAM.AHScan.StartScan()
end

RefreshScanButtonLabels = function()
    local L = GetL()
    local shiftActive = IsShiftScanModifierActive()

    if scanBtnLeft then
        local mainLabel = scanning
            and ((L and L["BTN_SCAN_STOP"]) or "Stop Scan")
            or (shiftActive
                and ((L and L["BTN_SCAN_EVERYTHING"]) or "Scan Everything")
                or ((L and L["BTN_SCAN_ALL"]) or "Scan All"))
        scanBtnLeft:SetText(mainLabel)
    end

    if selectedScanBtn then
        local selectedLabel = shiftActive
            and ((L and L["BTN_SCAN_FAVS"]) or "Scan Favs")
            or ((L and L["BTN_SCAN_SELECTED"]) or "Scan Selected Strat")
        selectedScanBtn:SetText(selectedLabel)
    end

    if rpDetail and rpDetail.btnScanStrat then
        local detailLabel = shiftActive
            and ((L and L["BTN_SCAN_FAVS"]) or "Scan Favs")
            or ((L and L["BTN_SCAN_STRAT"]) or "Scan Strat")
        rpDetail.btnScanStrat:SetText(detailLabel)
    end
end

local function SetScanningState(isScanning)
    scanning = isScanning
    local L = GetL()
    local lbl = isScanning
        and (L and L["BTN_SCAN_STOP"] or "Stop")
        or  (L and L["BTN_SCAN_ALL"]  or "Scan AH")
    if scanBtnLeft then
        scanBtnLeft:Enable()
    end
    if scanBtnStatus then
        scanBtnStatus:SetText(lbl)
        scanBtnStatus:Enable()
    end
    if RefreshScanButtonLabels then
        RefreshScanButtonLabels()
    end
end

-- ===== Forward declarations =====

local function EnsureInlineDetailReady()
    local opts = GetOpts()
    if not compactActive and opts.rightPanelCollapsed then
        opts.rightPanelCollapsed = false
        RelayoutPanels()
    end
    return rightPanel and rightPanel:IsShown() and ShowInlineDetail
end

SelectStrategyByID = function(stratID)
    if not stratID or not GAM.Importer or not GAM.Importer.GetStratByID then
        return nil
    end

    local strat = GAM.Importer.GetStratByID(stratID)
    if not strat then
        return nil
    end

    selectedStratID = stratID
    if EnsureInlineDetailReady() then
        ShowInlineDetail(strat, filterPatch)
    elseif GAM.UI.StratDetail then
        GAM.UI.StratDetail.Show(strat, filterPatch)
    end

    if leftPanel and leftPanel.refreshStatEditors then
        leftPanel.refreshStatEditors()
    end

    return strat
end

-- ===== Row frames (30-slot virtual scroll pool) =====
local function MakeRowFrame(parent, idx)
    return CenterUI.MakeRowFrame({
        rowHeight = ROW_H,
        stratIconWidth = STRAT_ICON_W,
        applyFontSize = ApplyFontSize,
        applyTextShadow = ApplyTextShadow,
        toggleFavorite = ToggleFavorite,
        rebuildList = RebuildList,
        refreshRows = MW2.RefreshRows,
        isFavorite = IsFavorite,
        isClickInFavoriteGutter = IsClickInFavoriteGutter,
        selectStrategyByID = SelectStrategyByID,
        getStratByID = function(stratID)
            return GAM.Importer.GetStratByID(stratID)
        end,
        getLocalizer = GetL,
    }, parent, idx)
end

-- ===== ApplyColumnLayout — re-anchors headers + row cells =====
local function ApplyColumnLayout(config, rowW)
    return Common.ApplyColumnLayout({
        rowW = rowW or 0,
        showProfession = (config == LIST_COLUMNS_ALL),
        localizer = GetL(),
        colHeaderBtns = colHeaderBtns,
        rowFrames = rowFrames,
        centerPanel = centerPanel,
        stratIconWidth = STRAT_ICON_W,
        cardHeight = CARD_H,
        listSectionHeight = LIST_SECTION_H,
        topOffset = columnHeaderTopOffset,
    })
end

-- ===== PopulateRow =====
local function PopulateRow(row, strat)
    CenterUI.PopulateRow({
        getLocalizer = GetL,
        isFavorite = IsFavorite,
        getListMetric = GetListMetric,
        formatPrice = GAM.Pricing.FormatPrice,
        getThemeDef = GetThemeDef,
        getSelectedStratID = function()
            return selectedStratID
        end,
    }, row, strat)
end

-- ===== RefreshRows =====
function MW2.RefreshRows()
    scrollOffset = CenterUI.RefreshRows({
        frame = frame,
        rowFrames = rowFrames,
        filteredList = filteredList,
        scrollOffset = scrollOffset,
        getVisibleListRows = GetVisibleListRows,
        populateRow = PopulateRow,
        setSuppressScrollCallback = function(value)
            suppressScrollCallback = value and true or false
        end,
        getLocalizer = GetL,
    })
end

-- ===== BestStratCard =====
RefreshBestStratCard = function()
    if not bestStratCardDirty then
        return
    end
    CenterUI.RefreshBestStratCard({ bestStratCard = bestStratCard })
    bestStratCardDirty = false
end

-- Returns the current inline detail strategy if one exists, or nil.
local function ResolveCompactDetailTarget()
    if selectedStratID then
        local strat = GAM.Importer and GAM.Importer.GetStratByID(selectedStratID)
        if strat then return strat end
    end
    return nil
end

-- Enable/disable the compact button based on whether a detail target exists.
-- Always enabled in compact mode so the user can always return to full layout.
RefreshCompactButtonEnabledState = function()
    if not compactBtn then return end
    if compactActive then
        compactBtn:Enable()
        if compactBtn.labelFS then
            compactBtn.labelFS:SetText("FULL")
            compactBtn.labelFS:SetTextColor(C_GR, C_GG, C_GB)
        end
    else
        local hasTarget = ResolveCompactDetailTarget() ~= nil
        if hasTarget then
            compactBtn:Enable()
            if compactBtn.labelFS then
                compactBtn.labelFS:SetText("DETAIL")
                compactBtn.labelFS:SetTextColor(C_GR, C_GG, C_GB)
            end
        else
            compactBtn:Disable()
            if compactBtn.labelFS then
                compactBtn.labelFS:SetText("DETAIL")
                compactBtn.labelFS:SetTextColor(C_GR * 0.4, C_GG * 0.4, C_GB * 0.4)
            end
        end
    end
end

-- Show or hide the panel collapse handles depending on compact state.
local function UpdateCollapseTogglePositions(isCompact)
    if frame then
        if frame.btnCollapseLeft  then frame.btnCollapseLeft:SetShown(not isCompact) end
        if frame.btnCollapseRight then frame.btnCollapseRight:SetShown(not isCompact) end
    end
end

-- ===== RelayoutPanels =====
RelayoutPanels = function()
    if not dividerContainer then return end
    local opts    = GetOpts()
    local layout  = GetLayoutSpec()
    local compact = opts.compactMode or false

    -- Self-heal: if compact is persisted but there is no valid detail target, fall back.
    if compact and not ResolveCompactDetailTarget() then
        compact = false
        opts.compactMode = false
    end

    if compact then
        -- Compact mode: show only the right (detail) panel, hide left + center
        if leftPanelShell   then leftPanelShell:Hide() end
        if centerPanelShell then centerPanelShell:Hide() end
        if frame and frame.scrollBar then frame.scrollBar:Hide() end
        if rightPanelShell then
            rightPanelShell:Show()
            rightPanelShell:ClearAllPoints()
            if layout.key == "soft" then
                rightPanelShell:SetPoint("TOPLEFT", dividerContainer, "TOPLEFT", layout.compactPadding, -layout.compactPadding)
                rightPanelShell:SetPoint("BOTTOMRIGHT", dividerContainer, "BOTTOMRIGHT", -layout.compactPadding, layout.compactPadding)
            else
                rightPanelShell:SetPoint("TOPLEFT",     dividerContainer, "TOPLEFT",     0, 0)
                rightPanelShell:SetPoint("BOTTOMRIGHT", dividerContainer, "BOTTOMRIGHT", 0, 0)
            end
        end
        -- Only resize the frame when actually entering compact mode
        if not compactActive and frame then
            frame:SetWidth(layout.rightWidth + (layout.compactPadding * 2) + 28)
        end
        compactActive = true
        UpdateCollapseTogglePositions(true)
        RefreshCompactButtonEnabledState()
        if rpDetail.currentStrat and rpDetail.root and rpDetail.root:IsShown() then
            ShowInlineDetail(rpDetail.currentStrat, rpDetail.currentPatch)
        end
        return
    end

    -- Normal mode
    local wasCompact = compactActive
    compactActive = false

    if wasCompact then
        -- Returning from compact: restore frame size, scrollbar, rightPanel anchors, centerPanel
        if frame then frame:SetSize(layout.windowWidth, layout.windowHeight) end
        if frame and frame.scrollBar then frame.scrollBar:Show() end
        if centerPanelShell then centerPanelShell:Show() end
    end

    local lc    = opts.leftPanelCollapsed or false
    local rc    = opts.rightPanelCollapsed or false
    local leftW = lc and 0 or layout.leftWidth
    local rightW= rc and 0 or layout.rightWidth

    if leftPanelShell  then leftPanelShell:SetShown(not lc) end
    if rightPanelShell then rightPanelShell:SetShown(not rc) end

    local rowW
    if layout.key == "soft" then
        local outer = layout.outerPadding or 0
        local cardGap = layout.cardGap or 0
        local leftGap = lc and 0 or cardGap
        local rightGap = rc and 0 or cardGap
        local dividerW = layout.windowWidth - 28
        local cardInsets = layout.cardInsets or { left = 20, right = 20 }
        local centerCardW = dividerW - (outer * 2) - leftW - rightW - leftGap - rightGap
        local centerContentW = centerCardW - (cardInsets.left or 0) - (cardInsets.right or 0)

        if leftPanelShell and not lc then
            leftPanelShell:ClearAllPoints()
            leftPanelShell:SetWidth(layout.leftWidth)
            leftPanelShell:SetPoint("TOPLEFT", dividerContainer, "TOPLEFT", outer, -outer)
            leftPanelShell:SetPoint("BOTTOMLEFT", dividerContainer, "BOTTOMLEFT", outer, outer)
        end
        if rightPanelShell and not rc then
            rightPanelShell:ClearAllPoints()
            rightPanelShell:SetWidth(layout.rightWidth)
            rightPanelShell:SetPoint("TOPRIGHT", dividerContainer, "TOPRIGHT", -outer, -outer)
            rightPanelShell:SetPoint("BOTTOMRIGHT", dividerContainer, "BOTTOMRIGHT", -outer, outer)
        end
        if centerPanelShell then
            centerPanelShell:ClearAllPoints()
            centerPanelShell:SetPoint("TOPLEFT", dividerContainer, "TOPLEFT", outer + leftW + leftGap, -outer)
            centerPanelShell:SetPoint("BOTTOMRIGHT", dividerContainer, "BOTTOMRIGHT", -(outer + rightW + rightGap), outer)
        end
        if guidePanelShell and listPanelShell then
            guidePanelShell:ClearAllPoints()
            guidePanelShell:SetHeight(layout.guideHeight)
            guidePanelShell:SetPoint("TOPLEFT", centerPanelShell, "TOPLEFT", 0, 0)
            guidePanelShell:SetPoint("TOPRIGHT", centerPanelShell, "TOPRIGHT", 0, 0)

            listPanelShell:ClearAllPoints()
            listPanelShell:SetPoint("TOPLEFT", guidePanelShell, "BOTTOMLEFT", 0, -cardGap)
            listPanelShell:SetPoint("TOPRIGHT", guidePanelShell, "BOTTOMRIGHT", 0, -cardGap)
            listPanelShell:SetPoint("BOTTOMLEFT", centerPanelShell, "BOTTOMLEFT", 0, 0)
            listPanelShell:SetPoint("BOTTOMRIGHT", centerPanelShell, "BOTTOMRIGHT", 0, 0)
        end
        rowW = math.max(0, centerContentW - 36)
    else
        -- Inset center panel by PANEL_TOGGLE_GAP on each visible seam so collapse handles
        -- sit in the gap rather than directly on the panel borders.
        local panelGap = GetPanelToggleGap()
        local leftOff  = leftW  + (lc and 0 or panelGap)
        local rightOff = rightW + (rc and 0 or panelGap)

        if rightPanelShell and not rc then
            rightPanelShell:ClearAllPoints()
            rightPanelShell:SetWidth(layout.rightWidth)
            rightPanelShell:SetPoint("TOPRIGHT", dividerContainer, "TOPRIGHT", 0, 0)
            rightPanelShell:SetPoint("BOTTOMRIGHT", dividerContainer, "BOTTOMRIGHT", 0, 0)
        end
        if leftPanelShell and not lc then
            leftPanelShell:ClearAllPoints()
            leftPanelShell:SetWidth(layout.leftWidth)
            leftPanelShell:SetPoint("TOPLEFT", dividerContainer, "TOPLEFT", 0, 0)
            leftPanelShell:SetPoint("BOTTOMLEFT", dividerContainer, "BOTTOMLEFT", 0, 0)
        end
        if centerPanelShell then
            centerPanelShell:ClearAllPoints()
            centerPanelShell:SetPoint("TOPLEFT",     dividerContainer, "TOPLEFT",     leftOff,   0)
            centerPanelShell:SetPoint("BOTTOMRIGHT", dividerContainer, "BOTTOMRIGHT", -rightOff, 0)
        end

        local totalW  = layout.windowWidth - 28
        local centerW = totalW - leftW - rightW - (lc and 0 or panelGap) - (rc and 0 or panelGap)
        rowW = centerW - 20
    end

    for _, r in ipairs(rowFrames) do r:SetWidth(rowW) end

    activeColConfig = GetActiveColumnConfig()
    ApplyColumnLayout(activeColConfig, rowW)

    UpdateCollapseButtonAnchors()
    UpdateCollapseTogglePositions(false)
    RefreshCompactButtonEnabledState()
    RefreshBestStratCard()
    MW2.RefreshRows()
    if rpDetail.currentStrat and rpDetail.root and rpDetail.root:IsShown() then
        ShowInlineDetail(rpDetail.currentStrat, rpDetail.currentPatch)
    end
end

ToggleCompactMode = function()
    local opts = GetOpts()
    opts.compactMode = not opts.compactMode
    RelayoutPanels()
end

-- ===== Onboarding =====
local function DismissOnboarding()
    SetOption("hasSeenOnboarding", true)
    if onboardingOverlay then onboardingOverlay:Hide() end
end

-- ===== Inline right-panel detail =====

local function HideInlineDetail()
    DetailUI.Hide({
        rpDetail = rpDetail,
        rightPanel = rightPanel,
        selectedScanBtn = selectedScanBtn,
        selectedCraftSimBtn = selectedCraftSimBtn,
        selectedVIBreakdownBtn = selectedVIBreakdownBtn,
        selectedShoppingBtn = selectedShoppingBtn,
        onAfterHide = function()
            if leftPanel and leftPanel.refreshStatEditors then
                leftPanel.refreshStatEditors()
            end
            if RefreshScanButtonLabels then
                RefreshScanButtonLabels()
            end
        end,
    })
end

local function IsVerticalIntegrationEnabled()
    local opts = GetOpts()
    return (opts.pigmentCostSource == "mill")
        or (opts.boltCostSource == "craft")
        or (opts.ingotCostSource == "craft")
end

local function ShouldShowVIBreakdown()
    local opts = GetOpts()
    return (opts.showVIBreakdown and true or false) and IsVerticalIntegrationEnabled()
end

ShowInlineDetail = function(strat, patchTag)
    if not rpDetail.root then return end
    patchTag = patchTag or GAM.C.DEFAULT_PATCH
    GAM.Pricing.PreloadStratItemData(strat, patchTag)
    RefreshBestStratCard()
    local metrics = GetStratMetric(strat, patchTag)
    local rendered = DetailUI.Render({
        rpDetail = rpDetail,
        strat = strat,
        patchTag = patchTag,
        metrics = metrics,
        isCompactMode = compactActive,
        localizer = GetL(),
        rightPanel = rightPanel,
        bindItemRow = BindItemRow,
        getItemDisplayData = GAM.Pricing.GetItemDisplayData,
        formatPrice = GAM.Pricing.FormatPrice,
        selectedScanBtn = selectedScanBtn,
        selectedCraftSimBtn = selectedCraftSimBtn,
        selectedVIBreakdownBtn = selectedVIBreakdownBtn,
        selectedShoppingBtn = selectedShoppingBtn,
        refreshCompactButtonEnabledState = RefreshCompactButtonEnabledState,
        rowHeight = ROW_H,
        onAfterRender = function()
            if leftPanel and leftPanel.refreshStatEditors then
                leftPanel.refreshStatEditors()
            end
            if RefreshScanButtonLabels then
                RefreshScanButtonLabels()
            end
        end,
    })
    if DetailUI and DetailUI.ShowBreakdownWindow and ShouldShowVIBreakdown() then
        DetailUI.ShowBreakdownWindow(strat, patchTag, rendered)
    elseif DetailUI and DetailUI.HideBreakdownWindow then
        DetailUI.HideBreakdownWindow()
    end
    if RefreshScanButtonLabels then
        RefreshScanButtonLabels()
    end
    return rendered
end

local function BuildInlineDetail(panel)
    local layout = GetLayoutSpec()
    return DetailUI.Build({
        panel = panel,
        rpDetail = rpDetail,
        themeRefs = themeRefs,
        localizer = GetL(),
        rightPanelWidth = GetCardContentWidth(layout.rightWidth),
        rowHeight = ROW_H,
        applyFontSize = ApplyFontSize,
        applyTextShadow = ApplyTextShadow,
        flattenSections = (layout.key == "soft"),
        createShell = CreateShell,
        attachButtonTooltip = AttachButtonTooltip,
        itemRowClick = ItemRowClick,
        itemRowEnter = ItemRowEnter,
        itemRowLeave = ItemRowLeave,
        colors = {
            gold = { C_GR, C_GG, C_GB },
            rule = { C_DR, C_DG, C_DB, C_DA },
        },
        layoutMode = layout.key,
        bodyTextColor = (GetThemeDef().bodyText or GetThemeDef().cardBodyText),
        mutedTextColor = (GetThemeDef().mutedText or GetThemeDef().bodyText or GetThemeDef().cardBodyText),
        onCommitCrafts = function(text)
            if rpDetail.currentStrat then
                SetCraftsOverride(rpDetail.currentStrat.id, rpDetail.currentPatch, text)
                ShowInlineDetail(rpDetail.currentStrat, rpDetail.currentPatch)
                MW2.RefreshRows()
            end
        end,
        onCommitInputQty = function(text)
            if rpDetail.currentStrat then
                SetInputQtyOverride(rpDetail.currentStrat.id, rpDetail.currentPatch, text)
                ShowInlineDetail(rpDetail.currentStrat, rpDetail.currentPatch)
                MW2.RefreshRows()
            end
        end,
        onScanSelected = function()
            if not rpDetail.currentStrat then return end
            ScanSelectedStrategyAction(
                rpDetail.currentStrat,
                rpDetail.currentPatch,
                function() ShowInlineDetail(rpDetail.currentStrat, rpDetail.currentPatch) end)
        end,
        onPushCraftSim = function()
            if not rpDetail.currentStrat then return end
            local pushed, err = GAM.CraftSimBridge.PushStratPrices(
                rpDetail.currentStrat,
                rpDetail.currentPatch,
                rpDetail.metrics)
            if err then
                print("|cffff8800[GAM]|r CraftSim: " .. tostring(err))
            else
                print(string.format("|cffff8800[GAM]|r Pushed %d price(s) to CraftSim.", pushed or 0))
            end
        end,
        onToggleShopping = function()
            ToggleShoppingSync(rpDetail.currentStrat, rpDetail.currentPatch)
        end,
        onShowBreakdown = function()
            if rpDetail.currentStrat and DetailUI and DetailUI.ShowBreakdownWindow then
                DetailUI.ShowBreakdownWindow(rpDetail.currentStrat, rpDetail.currentPatch, rpDetail.metrics)
            end
        end,
        onEditSelected = function()
            if rpDetail.currentStrat and GAM.UI.StratCreator then
                GAM.UI.StratCreator.ShowEdit(rpDetail.currentStrat)
            end
        end,
        onDeleteSelected = function()
            if rpDetail.currentStrat and GAM.UI.StratDetail and GAM.UI.StratDetail.ConfirmDeleteStrat then
                GAM.UI.StratDetail.ConfirmDeleteStrat(rpDetail.currentStrat)
            elseif rpDetail.currentStrat and GAM.UI.StratDetail then
                GAM.UI.StratDetail.Show(rpDetail.currentStrat, rpDetail.currentPatch)
            end
        end,
    })
end

local function BuildLeftPanelContent(L, C, LP)
    local layout = GetLayoutSpec()
    local function GetSelectedFormulaProfile()
        local strat
        if selectedStratID and GAM.Importer and GAM.Importer.GetStratByID then
            strat = GAM.Importer.GetStratByID(selectedStratID)
        end
        if not strat then
            strat = rpDetail.currentStrat
        end
        local profileKey = strat and strat.formulaProfile or nil
        local profileDef = profileKey and GetFormulaProfiles()[profileKey] or nil
        return strat, profileKey, profileDef
    end

    local refs = LeftPanelUI.Build({
        panel = leftPanel,
        themeRefs = themeRefs,
        leftPanelChecks = leftPanelChecks,
        localizer = L,
        constants = C,
        panelWidth = GetCardContentWidth(layout.leftWidth),
        padding = LP,
        colors = {
            gold = { C_GR, C_GG, C_GB },
            rule = { C_DR, C_DG, C_DB, C_DA },
        },
        layoutMode = layout.key,
        bodyTextColor = (GetThemeDef().bodyText or GetThemeDef().cardBodyText),
        mutedTextColor = (GetThemeDef().mutedText or GetThemeDef().bodyText or GetThemeDef().cardBodyText),
        applyFontSize = ApplyFontSize,
        attachButtonTooltip = AttachButtonTooltip,
        getOpts = GetOpts,
        setOption = SetOption,
        clampFillQtyValue = ClampFillQtyValue,
        clampStatPercentValue = ClampStatPercentValue,
        formatStatPercentValue = FormatStatPercentValue,
        buildPlayerProfessionSet = BuildPlayerProfessionSet,
        hasAnyEntries = HasAnyEntries,
        getActiveColumnConfig = GetActiveColumnConfig,
        getSelectedFormulaProfile = GetSelectedFormulaProfile,
        rebuildList = RebuildList,
        refreshRows = MW2.RefreshRows,
        relayoutPanels = RelayoutPanels,
        refreshBestStratCard = RefreshBestStratCard,
        refreshVisibleDetail = function()
            if rpDetail.currentStrat and rpDetail.root and rpDetail.root:IsShown() then
                local refreshed = rpDetail.currentStrat.id and GAM.Importer.GetStratByID(rpDetail.currentStrat.id)
                if refreshed then
                    rpDetail.currentStrat = refreshed
                    ShowInlineDetail(refreshed, rpDetail.currentPatch)
                end
            elseif DetailUI and DetailUI.HideBreakdownWindow then
                DetailUI.HideBreakdownWindow()
            end
        end,
        hideBreakdownWindow = function()
            if DetailUI and DetailUI.HideBreakdownWindow then
                DetailUI.HideBreakdownWindow()
            end
        end,
        doScan = DoScan,
        scanSelectedStrat = function()
            if not rpDetail.currentStrat then return end
            ScanSelectedStrategyAction(
                rpDetail.currentStrat,
                rpDetail.currentPatch,
                function() ShowInlineDetail(rpDetail.currentStrat, rpDetail.currentPatch) end
            )
        end,
        toggleShoppingSync = function()
            ToggleShoppingSync(rpDetail.currentStrat, rpDetail.currentPatch)
        end,
        pushSelectedToCraftSim = function()
            if not rpDetail.currentStrat then return end
            local pushed, err = GAM.CraftSimBridge.PushStratPrices(
                rpDetail.currentStrat,
                rpDetail.currentPatch,
                rpDetail.metrics)
            if err then
                print("|cffff8800[GAM]|r CraftSim: " .. tostring(err))
            else
                print(string.format("|cffff8800[GAM]|r Pushed %d price(s) to CraftSim.", pushed or 0))
            end
        end,
        showARPExport = function()
            if GAM.UI and GAM.UI.DebugLog and GAM.UI.DebugLog.ShowARPExport then
                GAM.UI.DebugLog.ShowARPExport()
            end
        end,
        getFilterPatch = function()
            return filterPatch
        end,
        getFilterMode = function()
            return filterMode
        end,
        setFilterMode = function(value)
            filterMode = value
        end,
        getFilterProf = function()
            return filterProf
        end,
        setFilterProf = function(value)
            filterProf = value
        end,
        getFilterProfSet = function()
            return filterProfSet
        end,
        setFilterProfSet = function(value)
            filterProfSet = value
        end,
        getFilterProfSingle = function()
            return filterProfSingle
        end,
        setFilterProfSingle = function(value)
            filterProfSingle = value
        end,
        setActiveColConfig = function(value)
            activeColConfig = value
        end,
    })

    scanBtnLeft = refs.scanBtnLeft
    selectedCraftSimBtn = refs.selectedCraftSimBtn
    selectedVIBreakdownBtn = refs.selectedVIBreakdownBtn
    selectedShoppingBtn = refs.selectedShoppingBtn
    selectedScanBtn = refs.selectedScanBtn
end

local function InitializeMainFrame(L, C, layout)
    local HDR_PX = C.HEADER_H
    local SB_H = C.STATUS_BAR_H + 6
    local tickerHeight = GetTickerHeight(C)

    frame = CreateFrame("Frame", "GoldAdvisorMidnightMainWindowV2", UIParent, "BackdropTemplate")
    frame:SetSize(layout.windowWidth, layout.windowHeight)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetScale(GetOpts().uiScale or 1.0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterEvent("MODIFIER_STATE_CHANGED")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function()
        DisableShoppingSync(true)
    end)
    frame:SetScript("OnEvent", function(_, event)
        if event == "MODIFIER_STATE_CHANGED" and RefreshScanButtonLabels then
            RefreshScanButtonLabels()
        end
    end)
    frame:SetClampedToScreen(true)
    frame:Hide()
    WindowManager.Register(frame, "main")

    SafeBuildSection("Frame header", function()
        BuildFrameHeader(L, C, HDR_PX)
    end)
    SafeBuildSection("Status and ticker", function()
        BuildStatusAndTicker(L, C, SB_H)
    end)

    dividerContainer = CreateFrame("Frame", nil, frame)
    dividerContainer:SetPoint("TOPLEFT",     frame, "TOPLEFT",     14,  -(HDR_PX + 2))
    dividerContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14,  SB_H + tickerHeight + 14)

    if layout.key == "soft" then
        softBoard = CreateFrame("Frame", nil, dividerContainer, "BackdropTemplate")
        softBoard:SetAllPoints(dividerContainer)
        softBoard:SetFrameLevel(dividerContainer:GetFrameLevel())
        themeRefs.softBoard = softBoard
    else
        softBoard = nil
        themeRefs.softBoard = nil
    end
end

local function BuildPanelSurfaces(L, layout)
    if layout.key == "soft" then
        leftPanelShell, leftPanel = Common.CreatePaperCard(dividerContainer, layout.cardInsets, themeRefs.paperCards)
        leftPanelShell:SetWidth(layout.leftWidth)
    else
        leftPanelShell, leftPanel = CreateShell(dividerContainer, "panel", { left = 4, right = 4, top = 4, bottom = 4 })
        leftPanelShell:SetWidth(layout.leftWidth)
        leftPanelShell:SetPoint("TOPLEFT",    dividerContainer, "TOPLEFT",    0, 0)
        leftPanelShell:SetPoint("BOTTOMLEFT", dividerContainer, "BOTTOMLEFT", 0, 0)
    end

    local leftTitle = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    leftTitle:SetPoint("TOP", leftPanel, "TOP", 0, -12)
    leftTitle:SetText((L and L["V2_TOOLS_TITLE"]) or "Strategy Tools")
    leftTitle:SetTextColor(C_GR, C_GG, C_GB)
    ApplyFontSize(leftTitle, layout.key == "soft" and 14 or 13)
    ApplyTextShadow(leftTitle)

    if layout.key == "soft" then
        rightPanelShell, rightPanel = Common.CreatePaperCard(dividerContainer, layout.cardInsets, themeRefs.paperCards)
        rightPanelShell:SetWidth(layout.rightWidth)
    else
        rightPanelShell, rightPanel = CreateShell(dividerContainer, "panel", { left = 4, right = 4, top = 4, bottom = 4 })
        rightPanelShell:SetWidth(layout.rightWidth)
        rightPanelShell:SetPoint("TOPRIGHT",    dividerContainer, "TOPRIGHT",    0, 0)
        rightPanelShell:SetPoint("BOTTOMRIGHT", dividerContainer, "BOTTOMRIGHT", 0, 0)
    end

    local rpPlaceholder = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rpPlaceholder:SetPoint("CENTER", rightPanel, "CENTER", 0, 10)
    rpPlaceholder:SetWidth(layout.rightWidth - 40)
    rpPlaceholder:SetJustifyH("CENTER")
    rpPlaceholder:SetTextColor(0.5, 0.5, 0.5, 1)
    rpPlaceholder:SetText((L and L["V2_PLACEHOLDER_DETAIL"]) or "Select a strategy to review\ncosts, output, and next actions.")
    ApplyFontSize(rpPlaceholder, 11)
    ApplyTextShadow(rpPlaceholder, 0.70)
    rightPanel.placeholder = rpPlaceholder

    SafeBuildSection("Inline detail panel", function()
        BuildInlineDetail(rightPanel)
    end)

    if layout.key == "soft" then
        centerPanelShell = CreateFrame("Frame", nil, dividerContainer)
        guidePanelShell, guidePanel = Common.CreatePaperCard(centerPanelShell, layout.cardInsets, themeRefs.paperCards)
        listPanelShell, listPanel = Common.CreatePaperCard(centerPanelShell, layout.cardInsets, themeRefs.paperCards)
        centerPanel = listPanel
    else
        centerPanelShell, centerPanel = CreateShell(dividerContainer, "center", { left = 4, right = 4, top = 4, bottom = 4 })
        guidePanel = centerPanel
        listPanel = centerPanel
        guidePanelShell = nil
        listPanelShell = nil
    end
end

local function MakeCollapseToggle(anchorSide, anchorX, labelDefault, isLeft)
    local btn = CreateFrame("Button", nil, dividerContainer, "BackdropTemplate")
    btn:SetSize(18, 64)
    if anchorSide == "LEFT" then
        btn:SetPoint("LEFT", dividerContainer, "LEFT", anchorX, 0)
    else
        btn:SetPoint("RIGHT", dividerContainer, "RIGHT", anchorX, 0)
    end
    btn:SetBackdrop(THIN_BACKDROP)
    btn:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
    btn:SetBackdropBorderColor(C_DR, C_DG, C_DB, C_DA)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(frame:GetFrameLevel() + 40)
    table.insert(themeRefs.collapseButtons, btn)

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetAllPoints()
    lbl:SetJustifyH("CENTER")
    lbl:SetText(labelDefault)
    lbl:SetTextColor(C_GR, C_GG, C_GB)
    ApplyFontSize(lbl, 11)
    btn.labelFS = lbl

    local L = GetL()
    local tipTitle = isLeft
        and ((L and L["TT_COLLAPSE_LEFT_TITLE"]) or "Collapse Left Panel")
        or ((L and L["TT_COLLAPSE_RIGHT_TITLE"]) or "Collapse Right Panel")
    local tipBody  = isLeft
        and ((L and L["TT_COLLAPSE_LEFT_BODY"]) or "Hide or show the tools panel.")
        or  ((L and L["TT_COLLAPSE_RIGHT_BODY"]) or "Hide or show the detail panel.")

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C_GR, C_GG, C_GB, 1.0)
        self.labelFS:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tipTitle, 1, 1, 1)
        GameTooltip:AddLine(tipBody, 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C_DR, C_DG, C_DB, C_DA)
        self.labelFS:SetTextColor(C_GR, C_GG, C_GB)
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function()
        local opts = GetOpts()
        if isLeft then
            opts.leftPanelCollapsed = not opts.leftPanelCollapsed
        else
            opts.rightPanelCollapsed = not opts.rightPanelCollapsed
        end
        RelayoutPanels()
    end)
    return btn
end

local function BuildCollapseToggles(layout)
    frame.btnCollapseLeft  = MakeCollapseToggle("LEFT",  layout.leftWidth,  "<", true)
    frame.btnCollapseRight = MakeCollapseToggle("RIGHT", -layout.rightWidth, ">", false)
end

local function BuildCenterContent(L, C, layout)
    local LP = 10

    ApplyTheme()

    SafeBuildSection("Left tools panel", function()
        BuildLeftPanelContent(L, C, LP)
    end)

    local centerRefs = CenterUI.Build({
        frame = frame,
        centerPanel = centerPanel,
        guidePanel = guidePanel,
        listPanel = listPanel,
        createShell = CreateShell,
        themeRefs = themeRefs,
        localizer = L,
        colors = {
            gold = { C_GR, C_GG, C_GB },
            rule = { C_DR, C_DG, C_DB, C_DA },
        },
        bodyTextColor = (GetThemeDef().bodyText or GetThemeDef().cardBodyText),
        mutedTextColor = (GetThemeDef().mutedText or GetThemeDef().bodyText or GetThemeDef().cardBodyText),
        layoutMode = layout.key,
        applyFontSize = ApplyFontSize,
        applyTextShadow = ApplyTextShadow,
        cardHeight = layout.guideHeight,
        listSectionHeight = LIST_SECTION_H,
        headerHeight = HDR_H,
        listTopPad = LIST_TOP_PAD,
        headerTopOffset = layout.listHeaderTop,
        visibleRows = layout.maxVisibleRows,
        getVisibleListRows = GetVisibleListRows,
        getFilteredList = function()
            return filteredList
        end,
        getScrollOffset = function()
            return scrollOffset
        end,
        setScrollOffset = function(value)
            scrollOffset = value
        end,
        getSuppressScrollCallback = function()
            return suppressScrollCallback
        end,
        refreshRows = MW2.RefreshRows,
        rebuildList = RebuildList,
        getSortKey = function()
            return sortKey
        end,
        setSortKey = function(value)
            sortKey = value
        end,
        getSortAsc = function()
            return sortAsc
        end,
        setSortAsc = function(value)
            sortAsc = value and true or false
        end,
        makeRowArgs = {
            rowHeight = ROW_H,
            stratIconWidth = STRAT_ICON_W,
            applyFontSize = ApplyFontSize,
            applyTextShadow = ApplyTextShadow,
            toggleFavorite = ToggleFavorite,
            rebuildList = RebuildList,
            refreshRows = MW2.RefreshRows,
            isFavorite = IsFavorite,
            isClickInFavoriteGutter = IsClickInFavoriteGutter,
            selectStrategyByID = SelectStrategyByID,
            getStratByID = function(stratID)
                return GAM.Importer.GetStratByID(stratID)
            end,
            getLocalizer = GetL,
        },
        onBestCardOpen = function(stratID)
            if SelectStrategyByID(stratID) then
                MW2.RefreshRows()
            end
        end,
        onBestCardClick = function(stratID)
            SelectStrategyByID(stratID)
            MW2.RefreshRows()
        end,
        dismissOnboarding = DismissOnboarding,
        doScan = DoScan,
    })

    bestStratCardShell = centerRefs.bestStratCardShell
    bestStratCard = centerRefs.bestStratCard
    colHeaderBtns = centerRefs.colHeaderBtns
    listHost = centerRefs.listHost
    rowFrames = centerRefs.rowFrames
    onboardingOverlay = centerRefs.onboardingOverlay
    frame.scrollBar = centerRefs.scrollBar
    scrollBarTopOffset = layout.scrollBarTop
    columnHeaderTopOffset = layout.listHeaderTop
    builtThemeKey = GetThemeKey()
    return centerRefs.scrollBar
end

-- ===== Build =====
local function Build()
    local L = GetL()
    local C = GAM.C
    local layout = GetLayoutSpec()
    InitializeMainFrame(L, C, layout)
    BuildPanelSurfaces(L, layout)
    BuildCollapseToggles(layout)
    local sb = BuildCenterContent(L, C, layout)
    FinalizeBuildOnShow(sb, C)
    ApplyTheme()
end

-- ===== Public API =====

function MW2.RefreshProfessionDropdown()
    -- V2 uses segmented buttons; no dropdown to refresh
end

function MW2.OnScanProgress(done, total, isComplete)
    if not frame then return end
    if isComplete then
        frame.progBar:Hide()
        frame.progLabel:SetText("")
        SetScanningState(false)
    else
        SetScanningState(true)
        frame.progBar:Show()
        if total and total > 0 then
            frame.progBar:SetValue(done / total)
            frame.progLabel:SetText(string.format("%d / %d  " .. GAM.L["STATUS_SCANNING_PROG"], done, total))
        else
            frame.progBar:SetValue(0)
            frame.progLabel:SetText(GAM.L["STATUS_QUEUING"])
        end
        if frame:IsShown() and done and done > 0 then
            local now = GetTime()
            if (now - lastScanRefreshAt) >= 0.75 then
                lastScanRefreshAt = now
                ClearListMetricCache()
                -- Skip RebuildList during scan: prices update per-item so the sort
                -- order is unstable mid-scan, and the sort itself is expensive when
                -- the price cache is warm. Full re-sort happens at OnScanComplete.
                MW2.RefreshRows()
                RefreshBestStratCard()
                if rpDetail.currentStrat and rpDetail.root and rpDetail.root:IsShown() then
                    ShowInlineDetail(rpDetail.currentStrat, rpDetail.currentPatch)
                end
            end
        end
    end
end

function MW2.OnScanComplete()
    if frame and frame:IsShown() then
        sortKey = "roi"
        sortAsc = true
        RebuildList()
        MW2.RefreshRows()
        RefreshBestStratCard()
        if leftPanel and leftPanel.refreshStatEditors then
            leftPanel.refreshStatEditors()
        end
        SetScanningState(false)
    end
end

function MW2.ApplyTheme()
    if not frame then
        return
    end
    if frame and builtThemeKey and builtThemeKey ~= GetThemeKey() then
        print("|cffff8800[GAM]|r Reload the UI to rebuild the selected theme layout.")
        return
    end
    ApplyTheme()
    if frame and frame:IsShown() then
        RelayoutPanels()
    end
end

function MW2.Refresh()
    if not frame then return end
    RebuildList()
    MW2.RefreshRows()
    RefreshBestStratCard()
    if leftPanel and leftPanel.refreshRankDropdown then
        leftPanel.refreshRankDropdown()
    end
    if leftPanel and leftPanel.refreshStatEditors then
        leftPanel.refreshStatEditors()
    end
    -- Re-populate inline detail if one was showing (e.g. after strat edit/delete)
    if rpDetail.currentStrat and rpDetail.root and rpDetail.root:IsShown() then
        local refreshed = rpDetail.currentStrat.id and GAM.Importer.GetStratByID(rpDetail.currentStrat.id)
        if refreshed then
            rpDetail.currentStrat = refreshed
            ShowInlineDetail(refreshed, rpDetail.currentPatch)
        else
            rpDetail.currentStrat = nil
            rpDetail.currentPatch = nil
            HideInlineDetail()
        end
    end
end

function MW2.Show()
    if not frame then Build() end
    if frame and builtThemeKey and builtThemeKey ~= GetThemeKey() then
        print("|cffff8800[GAM]|r Reload the UI to rebuild the selected theme layout.")
    end
    RememberWindowState(true)
    frame:Show()
    WindowManager.Present(frame)
end

function MW2.Hide(preserveRememberedState)
    DisableShoppingSync(true)
    if not preserveRememberedState then
        RememberWindowState(false)
    end
    if frame then frame:Hide() end
end

function MW2.Toggle()
    if not frame then Build() end
    if frame:IsShown() then
        MW2.Hide()
    else
        MW2.Show()
    end
end

function MW2.IsShown()
    return frame and frame:IsShown()
end

function MW2.GetCurrentDetailContext()
    return rpDetail.currentStrat, rpDetail.currentPatch, rpDetail.metrics
end
