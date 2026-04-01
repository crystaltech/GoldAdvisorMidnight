-- GoldAdvisorMidnight/UI/MainWindowV2Common.lua
-- Shared helper/data layer for MainWindowV2.
-- Module: GAM.UI.MainWindowV2Common

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local Common = {}
GAM.UI.MainWindowV2Common = Common

local C_GR, C_GG, C_GB = 1.0, 0.82, 0.0
local C_DR, C_DG, C_DB, C_DA = 0.7, 0.57, 0.0, 0.7

Common.THIN_BACKDROP = {
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = true,
    tileSize = 8,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

Common.FLAT_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    tile = true,
    tileSize = 8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

Common.SOFT_PAPER_TEXTURE = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal"

Common.SOFT_LAYOUT = {
    windowWidth = 1160,
    windowHeight = 720,
    toolsWidth = 190,
    detailWidth = 408,
    cardGap = 20,
    outerPadding = 16,
    guideHeight = 170,
    cardContentInsets = { left = 20, right = 20, top = 18, bottom = 18 },
    collapseGap = 12,
    compactPadding = 18,
    maxVisibleRows = 40,
    listHeaderTop = 34,
    paperBleed = 8,
}

Common.SOFT_OUTER_BACKDROP = {
    bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 64,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

Common.SOFT_INNER_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = true,
    tileSize = 8,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

Common.THEMES = {
    classic = {
        panelGap = 10,
        frame = {
            backdrop = Common.THIN_BACKDROP,
            bgColor = { 0.03, 0.03, 0.03, 1.0 },
            borderColor = { C_DR, C_DG, C_DB, 0.55 },
        },
        headerBackdrop = { 0.03, 0.03, 0.03, 0.92 },
        titleText      = { C_GR, C_GG, C_GB, 1.0 },
        subtitleText   = { 0.55, 0.45, 0.0, 1.0 },
        cardBanner     = { 0.10, 0.08, 0.02, 0.55 },
        cardRule       = { C_DR, C_DG, C_DB, 0.55 },
        shells = {
            panel = {
                outerBackdrop = Common.THIN_BACKDROP,
                outerBgColor = { 0.05, 0.05, 0.05, 0.96 },
                outerBorderColor = { C_DR, C_DG, C_DB, 0.30 },
                innerBackdrop = Common.THIN_BACKDROP,
                innerBgColor = { 0.05, 0.05, 0.05, 0.92 },
                innerBorderColor = { C_DR, C_DG, C_DB, 0.12 },
            },
            center = {
                outerBackdrop = Common.THIN_BACKDROP,
                outerBgColor = { 0.045, 0.045, 0.045, 1.0 },
                outerBorderColor = { C_DR, C_DG, C_DB, 0.22 },
                innerBackdrop = Common.THIN_BACKDROP,
                innerBgColor = { 0.045, 0.045, 0.045, 0.95 },
                innerBorderColor = { C_DR, C_DG, C_DB, 0.10 },
            },
            card = {
                outerBackdrop = Common.THIN_BACKDROP,
                outerBgColor = { 0.05, 0.05, 0.05, 1.0 },
                outerBorderColor = { C_DR, C_DG, C_DB, 0.25 },
                innerBackdrop = Common.THIN_BACKDROP,
                innerBgColor = { 0.05, 0.05, 0.05, 0.94 },
                innerBorderColor = { C_DR, C_DG, C_DB, 0.10 },
            },
            status = {
                outerBackdrop = Common.THIN_BACKDROP,
                outerBgColor = { 0.05, 0.05, 0.05, 1.0 },
                outerBorderColor = { C_DR, C_DG, C_DB, 0.35 },
                innerBackdrop = Common.THIN_BACKDROP,
                innerBgColor = { 0.05, 0.05, 0.05, 0.95 },
                innerBorderColor = { C_DR, C_DG, C_DB, 0.12 },
            },
            section = {
                outerBackdrop = Common.THIN_BACKDROP,
                outerBgColor = { 0.06, 0.06, 0.06, 0.95 },
                outerBorderColor = { C_DR, C_DG, C_DB, 0.18 },
                innerBackdrop = Common.THIN_BACKDROP,
                innerBgColor = { 0.06, 0.06, 0.06, 0.95 },
                innerBorderColor = { C_DR, C_DG, C_DB, 0.10 },
            },
        },
        tickerBackdrop  = { 0.05, 0.05, 0.05, 1.0 },
        tickerBorder    = { C_DR, C_DG, C_DB, 0.35 },
        tickerText      = { 0.78, 0.78, 0.78, 1.0 },
        statusText      = { 0.85, 0.85, 0.85, 1.0 },
        progressText    = { 1.0, 1.0, 1.0, 1.0 },
        collapseBackdrop = { 0.08, 0.08, 0.08, 0.85 },
        collapseBorder  = { C_DR, C_DG, C_DB, C_DA },
        compactBackdrop = { 0.08, 0.08, 0.08, 0.85 },
        compactBorder   = { C_DR, C_DG, C_DB, 0.75 },
        sectionHeader   = { 0.12, 0.10, 0.03, 0.90 },
        listRowOdd      = { 0.10, 0.10, 0.10, 0.55 },
        listRowEven     = { 0.10, 0.10, 0.10, 0.28 },
        separatorColor  = { C_DR, C_DG, C_DB, C_DA },
        placeholderText = { 0.50, 0.50, 0.50, 1.0 },
        cardTitleText   = { C_GR, C_GG, C_GB, 1.0 },
        cardBodyText    = { 0.85, 0.82, 0.76, 1.0 },
    },
    soft = {
        panelGap = Common.SOFT_LAYOUT.collapseGap,
        layout = Common.SOFT_LAYOUT,
        frame = {
            backdrop = Common.SOFT_OUTER_BACKDROP,
            bgColor = { 0.06, 0.05, 0.04, 0.98 },
            borderColor = { 0.86, 0.78, 0.62, 0.94 },
        },
        board = {
            backdrop = Common.THIN_BACKDROP,
            bgColor = { 0.05, 0.04, 0.03, 0.92 },
            borderColor = { 0.36, 0.25, 0.10, 0.42 },
        },
        paperCard = {
            texture = Common.SOFT_PAPER_TEXTURE,
            textureColor = { 1.0, 0.99, 0.94, 0.98 },
            washColor = { 1.0, 0.97, 0.88, 0.14 },
            edgeShadeColor = { 0.22, 0.12, 0.05, 0.08 },
            edgeSize = 14,
            shadowColor = { 0.0, 0.0, 0.0, 0.14 },
            contentInsets = Common.SOFT_LAYOUT.cardContentInsets,
        },
        headerBackdrop = { 0.08, 0.06, 0.05, 0.96 },
        titleText      = { 1.0, 0.86, 0.36, 1.0 },
        subtitleText   = { 0.84, 0.73, 0.45, 1.0 },
        cardBanner     = { 0.18, 0.13, 0.09, 0.0 },
        cardRule       = { 0.30, 0.18, 0.07, 0.72 },
        shells = {
            panel = {
                outerBackdrop = Common.FLAT_BACKDROP,
                outerBgColor = { 0, 0, 0, 0 },
                outerBorderColor = { 0, 0, 0, 0 },
                innerBackdrop = Common.FLAT_BACKDROP,
                innerBgColor = { 0.40, 0.31, 0.20, 0.60 },
                innerBorderColor = { 0, 0, 0, 0 },
                innerInsets = { left = 0, right = 0, top = 0, bottom = 0 },
                overlayTexture = "Interface\\AchievementFrame\\UI-GuildAchievement-Parchment-Horizontal-Desaturated",
                overlayVertexColor = { 0.96, 0.90, 0.78, 0.88 },
            },
            center = {
                outerBackdrop = Common.FLAT_BACKDROP,
                outerBgColor = { 0, 0, 0, 0 },
                outerBorderColor = { 0, 0, 0, 0 },
                innerBackdrop = Common.FLAT_BACKDROP,
                innerBgColor = { 0.42, 0.33, 0.22, 0.60 },
                innerBorderColor = { 0, 0, 0, 0 },
                innerInsets = { left = 0, right = 0, top = 0, bottom = 0 },
                overlayTexture = "Interface\\AchievementFrame\\UI-GuildAchievement-Parchment-Horizontal-Desaturated",
                overlayVertexColor = { 0.98, 0.92, 0.80, 0.90 },
            },
            card = {
                outerBackdrop = Common.FLAT_BACKDROP,
                outerBgColor = { 0, 0, 0, 0 },
                outerBorderColor = { 0, 0, 0, 0 },
                innerBackdrop = Common.FLAT_BACKDROP,
                innerBgColor = { 0.44, 0.34, 0.22, 0.62 },
                innerBorderColor = { 0, 0, 0, 0 },
                innerInsets = { left = 0, right = 0, top = 0, bottom = 0 },
                overlayTexture = "Interface\\AchievementFrame\\UI-GuildAchievement-Parchment-Horizontal-Desaturated",
                overlayVertexColor = { 1.0, 0.94, 0.82, 0.94 },
            },
            status = {
                outerBackdrop = Common.SOFT_OUTER_BACKDROP,
                outerBgColor = { 0.07, 0.06, 0.05, 0.98 },
                outerBorderColor = { 0.80, 0.72, 0.56, 0.90 },
                innerBackdrop = Common.THIN_BACKDROP,
                innerBgColor = { 0.10, 0.08, 0.06, 0.98 },
                innerBorderColor = { 0.42, 0.33, 0.17, 0.24 },
                innerInsets = { left = 2, right = 2, top = 2, bottom = 2 },
            },
            section = {
                outerBackdrop = Common.FLAT_BACKDROP,
                outerBgColor = { 0, 0, 0, 0 },
                outerBorderColor = { 0, 0, 0, 0 },
                innerBackdrop = Common.FLAT_BACKDROP,
                innerBgColor = { 0.41, 0.32, 0.21, 0.58 },
                innerBorderColor = { 0, 0, 0, 0 },
                innerInsets = { left = 0, right = 0, top = 0, bottom = 0 },
                overlayTexture = "Interface\\AchievementFrame\\UI-GuildAchievement-Parchment-Horizontal-Desaturated",
                overlayVertexColor = { 0.98, 0.92, 0.80, 0.86 },
            },
        },
        tickerBackdrop  = { 0.10, 0.08, 0.06, 0.98 },
        tickerBorder    = { 0.74, 0.60, 0.25, 0.74 },
        tickerText      = { 0.95, 0.88, 0.74, 1.0 },
        statusText      = { 0.94, 0.88, 0.74, 1.0 },
        progressText    = { 1.0, 0.95, 0.84, 1.0 },
        collapseBackdrop = { 0.14, 0.11, 0.08, 0.96 },
        collapseBorder  = { 0.76, 0.62, 0.28, 0.94 },
        compactBackdrop = { 0.15, 0.12, 0.08, 0.98 },
        compactBorder   = { 0.78, 0.64, 0.30, 0.96 },
        sectionHeader   = { 0.26, 0.17, 0.08, 0.08 },
        listRowOdd      = { 0.24, 0.16, 0.08, 0.035 },
        listRowEven     = { 0.16, 0.10, 0.05, 0.015 },
        separatorColor  = { 0.28, 0.17, 0.06, 0.62 },
        placeholderText = { 0.08, 0.05, 0.02, 0.98 },
        cardTitleText   = { 1.0, 0.86, 0.36, 1.0 },
        cardBodyText    = { 0.08, 0.05, 0.02, 1.0 },
        bodyText        = { 0.08, 0.05, 0.02, 1.0 },
        mutedText       = { 0.18, 0.11, 0.05, 0.98 },
    },
}

function Common.GetThemeKey(opts)
    local key = opts and opts.v2Theme or "classic"
    return Common.THEMES[key] and key or "classic"
end

function Common.GetThemeDef(opts)
    return Common.THEMES[Common.GetThemeKey(opts)]
end

function Common.SetBackdropColors(widget, bgColor, borderColor)
    if not widget then return end
    if bgColor and widget.SetBackdropColor then
        widget:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end
    if borderColor and widget.SetBackdropBorderColor then
        widget:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
    end
end

function Common.AttachButtonTooltip(btn, title, body)
    if not btn then return end
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title and title ~= "" then
            GameTooltip:SetText(title, 1, 1, 1)
        end
        if body and body ~= "" then
            GameTooltip:AddLine(body, 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function Common.ApplyFontSize(fs, size, flags)
    if not fs or not fs.GetFont or not fs.SetFont then return end
    local fontPath, _, fontFlags = fs:GetFont()
    if fontPath then
        fs:SetFont(fontPath, size, flags or fontFlags)
    end
end

function Common.ApplyTextShadow(fs, alpha)
    if not fs or not fs.SetShadowOffset or not fs.SetShadowColor then return end
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, alpha or 0.85)
end

local function NormalizeInsets(insets)
    local src = insets or {}
    return {
        left = src.left or 0,
        right = src.right or 0,
        top = src.top or 0,
        bottom = src.bottom or 0,
    }
end

local function SetGradientTexture(texture, orientation, startColor, endColor)
    if not texture then return end

    local s = startColor or { 0, 0, 0, 0 }
    local e = endColor or s
    if texture.SetGradientAlpha then
        texture:SetGradientAlpha(
            orientation,
            s[1] or 0, s[2] or 0, s[3] or 0, s[4] or 0,
            e[1] or 0, e[2] or 0, e[3] or 0, e[4] or 0
        )
    else
        local fallback = ((s[4] or 0) >= (e[4] or 0)) and s or e
        texture:SetColorTexture(fallback[1] or 0, fallback[2] or 0, fallback[3] or 0, fallback[4] or 0)
    end
end

function Common.SetShellInsets(shell, insets)
    if not (shell and shell.inner) then return end
    local ins = NormalizeInsets(insets)
    shell._activeInsets = ins
    shell.inner:ClearAllPoints()
    shell.inner:SetPoint("TOPLEFT", shell, "TOPLEFT", ins.left, -ins.top)
    shell.inner:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -ins.right, ins.bottom)
end

function Common.CreateShell(parent, variant, insets, shellList)
    local shell = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    shell._shellVariant = variant
    local ins = NormalizeInsets(insets or { left = 4, right = 4, top = 4, bottom = 4 })
    local inner = CreateFrame("Frame", nil, shell, "BackdropTemplate")
    local innerOverlay = inner:CreateTexture(nil, "ARTWORK", nil, -7)
    innerOverlay:SetAllPoints(inner)
    innerOverlay:Hide()
    local content = CreateFrame("Frame", nil, inner)
    content:SetAllPoints(inner)
    shell._baseInsets = ins
    shell.inner = inner
    shell.innerOverlay = innerOverlay
    shell.content = content
    Common.SetShellInsets(shell, ins)
    if shellList then
        table.insert(shellList, shell)
    end
    return shell, content
end

function Common.SetPaperCardInsets(card, insets)
    if not (card and card.content) then return end
    local ins = NormalizeInsets(insets)
    card._contentInsets = ins
    card.content:ClearAllPoints()
    card.content:SetPoint("TOPLEFT", card, "TOPLEFT", ins.left, -ins.top)
    card.content:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -ins.right, ins.bottom)
end

function Common.ApplyPaperCardTheme(card, spec)
    if not (card and spec) then return end

    if card.paper then
        card.paper:SetTexture(spec.texture or Common.SOFT_PAPER_TEXTURE)
        local c = spec.textureColor or { 1, 1, 1, 1 }
        card.paper:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end

    if card.paperWash then
        local c = spec.washColor or { 1, 1, 1, 0 }
        card.paperWash:SetColorTexture(c[1], c[2], c[3], c[4] or 0)
    end

    if card.shadow then
        local c = spec.shadowColor or { 0, 0, 0, 0.3 }
        card.shadow:SetColorTexture(c[1], c[2], c[3], c[4] or 0.3)
    end

    local edge = spec.edgeShadeColor or { 0, 0, 0, 0 }
    local clear = { edge[1], edge[2], edge[3], 0 }
    local edgeSize = spec.edgeSize or 24

    if card.paperEdgeTop then
        card.paperEdgeTop:SetHeight(edgeSize)
        SetGradientTexture(card.paperEdgeTop, "VERTICAL", edge, clear)
    end
    if card.paperEdgeBottom then
        card.paperEdgeBottom:SetHeight(edgeSize)
        SetGradientTexture(card.paperEdgeBottom, "VERTICAL", clear, edge)
    end
    if card.paperEdgeLeft then
        card.paperEdgeLeft:SetWidth(edgeSize)
        SetGradientTexture(card.paperEdgeLeft, "HORIZONTAL", edge, clear)
    end
    if card.paperEdgeRight then
        card.paperEdgeRight:SetWidth(edgeSize)
        SetGradientTexture(card.paperEdgeRight, "HORIZONTAL", clear, edge)
    end

    Common.SetPaperCardInsets(card, spec.contentInsets or card._contentInsets)
end

function Common.CreatePaperCard(parent, insets, cardList)
    local card = CreateFrame("Frame", nil, parent)
    local bleed = Common.SOFT_LAYOUT.paperBleed or 8
    local shadow = card:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetTexture("Interface\\Buttons\\WHITE8X8")
    shadow:SetPoint("TOPLEFT", card, "TOPLEFT", -(bleed + 2), bleed + 2)
    shadow:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", bleed + 2, -(bleed + 2))
    shadow:SetColorTexture(0, 0, 0, 0.34)

    local paper = card:CreateTexture(nil, "BACKGROUND", nil, -7)
    paper:SetPoint("TOPLEFT", card, "TOPLEFT", -bleed, bleed)
    paper:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", bleed, -bleed)
    paper:SetTexture(Common.SOFT_PAPER_TEXTURE)
    paper:SetVertexColor(1, 0.97, 0.88, 0.96)

    local wash = card:CreateTexture(nil, "BACKGROUND", nil, -6)
    wash:SetPoint("TOPLEFT", paper, "TOPLEFT", 0, 0)
    wash:SetPoint("BOTTOMRIGHT", paper, "BOTTOMRIGHT", 0, 0)
    wash:SetTexture("Interface\\Buttons\\WHITE8X8")
    wash:SetColorTexture(1.0, 0.97, 0.88, 0.14)

    local edgeTop = card:CreateTexture(nil, "BACKGROUND", nil, -5)
    edgeTop:SetTexture("Interface\\Buttons\\WHITE8X8")
    edgeTop:SetPoint("TOPLEFT", paper, "TOPLEFT", 0, 0)
    edgeTop:SetPoint("TOPRIGHT", paper, "TOPRIGHT", 0, 0)
    edgeTop:SetHeight(14)

    local edgeBottom = card:CreateTexture(nil, "BACKGROUND", nil, -5)
    edgeBottom:SetTexture("Interface\\Buttons\\WHITE8X8")
    edgeBottom:SetPoint("BOTTOMLEFT", paper, "BOTTOMLEFT", 0, 0)
    edgeBottom:SetPoint("BOTTOMRIGHT", paper, "BOTTOMRIGHT", 0, 0)
    edgeBottom:SetHeight(14)

    local edgeLeft = card:CreateTexture(nil, "BACKGROUND", nil, -5)
    edgeLeft:SetTexture("Interface\\Buttons\\WHITE8X8")
    edgeLeft:SetPoint("TOPLEFT", paper, "TOPLEFT", 0, 0)
    edgeLeft:SetPoint("BOTTOMLEFT", paper, "BOTTOMLEFT", 0, 0)
    edgeLeft:SetWidth(14)

    local edgeRight = card:CreateTexture(nil, "BACKGROUND", nil, -5)
    edgeRight:SetTexture("Interface\\Buttons\\WHITE8X8")
    edgeRight:SetPoint("TOPRIGHT", paper, "TOPRIGHT", 0, 0)
    edgeRight:SetPoint("BOTTOMRIGHT", paper, "BOTTOMRIGHT", 0, 0)
    edgeRight:SetWidth(14)

    local content = CreateFrame("Frame", nil, card)
    card.content = content
    card.shadow = shadow
    card.paper = paper
    card.paperWash = wash
    card.paperEdgeTop = edgeTop
    card.paperEdgeBottom = edgeBottom
    card.paperEdgeLeft = edgeLeft
    card.paperEdgeRight = edgeRight
    card._paperCard = true
    Common.ApplyPaperCardTheme(card, Common.THEMES.soft.paperCard)
    Common.SetPaperCardInsets(card, insets or Common.SOFT_LAYOUT.cardContentInsets)
    if cardList then
        table.insert(cardList, card)
    end
    return card, content
end

function Common.IsClickInFavoriteGutter(frameObj, gutterWidth)
    if not frameObj or not frameObj.GetLeft then return false end
    local left = frameObj:GetLeft()
    if not left then return false end
    local cursorX = GetCursorPosition and GetCursorPosition() or nil
    local scale = frameObj.GetEffectiveScale and frameObj:GetEffectiveScale() or 1
    if not cursorX or not scale or scale == 0 then return false end
    local localX = (cursorX / scale) - left
    return localX >= 0 and localX <= (gutterWidth or 0)
end

function Common.ClampFillQtyValue(value, minValue, maxValue, defaultValue)
    local n = tonumber(value)
    if not n then
        return defaultValue
    end
    return math.max(minValue, math.min(maxValue, math.floor(n)))
end

function Common.ClampStatPercentValue(value, fallback)
    local n = tonumber(value)
    if not n then
        n = fallback or 0
    end
    return math.max(0, math.min(100, n))
end

function Common.FormatStatPercentValue(value)
    local n = tonumber(value) or 0
    if math.abs(n - math.floor(n + 0.5)) < 0.0001 then
        return tostring(math.floor(n + 0.5))
    end
    return string.format("%.1f", n)
end

function Common.GetFormulaProfiles()
    return (GAM_WORKBOOK_GENERATED and GAM_WORKBOOK_GENERATED.formulaProfiles) or {}
end

function Common.BuildPlayerProfessionSet(filterPatch)
    local set = {}
    if not GetProfessions then
        return set
    end

    local supported = {}
    for _, profession in ipairs((GAM.Importer and GAM.Importer.GetAllProfessions and GAM.Importer.GetAllProfessions(filterPatch)) or {}) do
        supported[profession] = true
    end

    local indices = { GetProfessions() }
    for _, index in ipairs(indices) do
        if index then
            local professionName = GetProfessionInfo(index)
            if professionName and supported[professionName] then
                set[professionName] = true
            end
        end
    end

    return set
end

function Common.HasAnyEntries(set)
    return set and next(set) ~= nil
end

function Common.StratMatchesFilter(strat, filterMode, filterProfSet, filterProf, filterProfSingle, rankPolicy)
    local poolOK
    if filterMode == "mine" and Common.HasAnyEntries(filterProfSet) then
        poolOK = filterProfSet[strat.profession] == true
    else
        poolOK = filterProf == "All" or strat.profession == filterProf
    end
    if not poolOK then
        return false
    end
    if filterProfSingle ~= "All" and strat.profession ~= filterProfSingle then
        return false
    end
    if rankPolicy == "highest"
        and strat.qualityPolicy == "force_q1_inputs"
        and strat.outputQualityMode == "rank_policy" then
        return false
    end
    return true
end

function Common.GetActiveColumnConfig(filterMode, filterProf, listColumnsAll, listColumnsFiltered)
    if filterMode == "mine" then
        return listColumnsAll
    end
    return (filterProf == "All") and listColumnsAll or listColumnsFiltered
end

function Common.BuildRuntimeColumns(rowW, showProfession)
    local cols = {}
    local showStatus = rowW >= (showProfession and 560 or 430)
    local gap = 6
    local usable = math.max(220, rowW - 12)

    if showProfession then
        local statusW = showStatus and 56 or 0
        local roiW = 58
        local profitW = 100
        local profW = math.max(76, math.floor(usable * 0.18))
        local nameW = usable - profW - profitW - roiW - statusW - gap * (showStatus and 4 or 3)
        if nameW < 150 then
            local delta = 150 - nameW
            profW = math.max(68, profW - delta)
            nameW = usable - profW - profitW - roiW - statusW - gap * (showStatus and 4 or 3)
        end
        local x = 10
        cols[#cols + 1] = { id="stratName",  x=x, w=nameW,  hKey="COL_STRAT",  sKey="stratName",  j="LEFT"  }
        x = x + nameW + gap
        cols[#cols + 1] = { id="profession", x=x, w=profW,  hKey="COL_PROF",   sKey="profession", j="LEFT"  }
        x = x + profW + gap
        cols[#cols + 1] = { id="profit",     x=x, w=profitW,hKey="COL_PROFIT", sKey="profit",     j="CENTER" }
        x = x + profitW + gap
        cols[#cols + 1] = { id="roi",        x=x, w=roiW,   hKey="COL_ROI",    sKey="roi",        j="CENTER" }
        if showStatus then
            x = x + roiW + gap
            cols[#cols + 1] = { id="status", x=x, w=statusW,hKey="COL_STATUS", sKey=nil,          j="LEFT"  }
        end
    else
        local statusW = showStatus and 58 or 0
        local roiW = 58
        local profitW = 110
        local nameW = usable - profitW - roiW - statusW - gap * (showStatus and 3 or 2)
        local x = 10
        cols[#cols + 1] = { id="stratName", x=x, w=nameW,  hKey="COL_STRAT",  sKey="stratName", j="LEFT"  }
        x = x + nameW + gap
        cols[#cols + 1] = { id="profit",    x=x, w=profitW,hKey="COL_PROFIT", sKey="profit",    j="CENTER" }
        x = x + profitW + gap
        cols[#cols + 1] = { id="roi",       x=x, w=roiW,   hKey="COL_ROI",    sKey="roi",       j="CENTER" }
        if showStatus then
            x = x + roiW + gap
            cols[#cols + 1] = { id="status", x=x, w=statusW,hKey="COL_STATUS", sKey=nil,        j="LEFT"  }
        end
    end

    return cols, showProfession
end

function Common.GetVisibleListRows(listHost, rowHeight, maxRows)
    if not listHost or not listHost.GetHeight then
        return maxRows
    end
    local h = listHost:GetHeight() or 0
    local rows = math.floor(h / rowHeight)
    if rows < 1 then rows = maxRows end
    if rows > maxRows then rows = maxRows end
    return rows
end

function Common.ApplyColumnLayout(args)
    local runtimeCols, showProfession = Common.BuildRuntimeColumns(args.rowW or 0, args.showProfession)
    local L = args.localizer
    local colHeaderBtns = args.colHeaderBtns or {}
    local rowFrames = args.rowFrames or {}
    local centerPanel = args.centerPanel
    local stratIconWidth = args.stratIconWidth or 0
    local topOffset = args.topOffset or ((args.cardHeight or 0) + (args.listSectionHeight or 0) + 12)

    for i, col in ipairs(runtimeCols) do
        local btn = colHeaderBtns[i]
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", centerPanel, "TOPLEFT", col.x, -topOffset)
            btn:SetWidth(col.w)
            btn.labelFS:SetText(L and L[col.hKey] or col.hKey)
            btn.labelFS:SetJustifyH(col.j)
            btn.sortKeyV2 = col.sKey
            btn:Show()
        end
    end

    for i = #runtimeCols + 1, #colHeaderBtns do
        if colHeaderBtns[i] then
            colHeaderBtns[i]:Hide()
        end
    end

    for _, row in ipairs(rowFrames) do
        if args.rowW then
            row:SetWidth(args.rowW)
        end

        row.nameText:Hide()
        row.profText:Hide()
        row.profitText:Hide()
        row.roiText:Hide()
        row.missingText:Hide()

        for _, col in ipairs(runtimeCols) do
            local fs
            if col.id == "stratName" then
                fs = row.nameText
            elseif col.id == "profession" then
                fs = row.profText
            elseif col.id == "profit" then
                fs = row.profitText
            elseif col.id == "roi" then
                fs = row.roiText
            elseif col.id == "status" then
                fs = row.missingText
            end

            if fs then
                fs:ClearAllPoints()
                local xOff = (col.id == "stratName") and (col.x + stratIconWidth) or col.x
                local wOff = (col.id == "stratName") and (col.w - stratIconWidth) or col.w
                fs:SetPoint("LEFT", row, "LEFT", xOff, 0)
                fs:SetWidth(wOff)
                fs:SetJustifyH(col.j)
                fs:Show()
            end
        end

        row.profText:SetShown(showProfession)
        row.profSubText:Hide()
    end

    return runtimeCols, showProfession
end
