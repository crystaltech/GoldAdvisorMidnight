-- GoldAdvisorMidnight/UI/MainWindowCommon.lua
-- Shared helper/data layer for MainWindow.
-- Module: GAM.UI.MainWindowCommon

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local Common = {}
GAM.UI.MainWindowCommon = Common
GAM.UI.MainWindowV2Common = Common -- Compatibility alias for pre-refocus callers.

local PROFESSION_SKILL_LINES = (GAM.C and GAM.C.PROFESSION_SKILL_LINES) or {
    Alchemy = 171,
    Blacksmithing = 164,
    Cooking = 185,
    Enchanting = 333,
    Engineering = 202,
    Inscription = 773,
    Jewelcrafting = 755,
    Leatherworking = 165,
    Tailoring = 197,
}

local PROFESSION_NAME_BY_SKILL_LINE = {}
for professionName, skillLineID in pairs(PROFESSION_SKILL_LINES) do
    PROFESSION_NAME_BY_SKILL_LINE[skillLineID] = professionName
end

local unresolvedProfessionSkillLines = {}

local function GetProfessionBySkillLineID(skillLineID)
    skillLineID = tonumber(skillLineID)
    if not skillLineID then return nil end
    return PROFESSION_NAME_BY_SKILL_LINE[skillLineID]
end

local function CacheProfessionSkillLine(skillLineID, professionName)
    skillLineID = tonumber(skillLineID)
    if skillLineID and professionName then
        PROFESSION_NAME_BY_SKILL_LINE[skillLineID] = professionName
    end
    return professionName
end

local function ResolveProfessionFromSkillLine(skillLine)
    skillLine = tonumber(skillLine)
    if not skillLine then return nil end

    local directProfession = GetProfessionBySkillLineID(skillLine)
    if directProfession then
        return directProfession
    end

    local tradeSkillAPI = C_TradeSkillUI
    if tradeSkillAPI and type(tradeSkillAPI.GetProfessionInfoBySkillLineID) == "function" then
        local ok, info = pcall(tradeSkillAPI.GetProfessionInfoBySkillLineID, skillLine)
        if ok and type(info) == "table" then
            local professionName = GetProfessionBySkillLineID(info.professionID)
                or GetProfessionBySkillLineID(info.parentProfessionID)
            if professionName then
                return CacheProfessionSkillLine(skillLine, professionName)
            end
        end
    end

    if tradeSkillAPI and type(tradeSkillAPI.GetTradeSkillLineInfoByID) == "function" then
        local ok, _, _, _, _, parentSkillLineID = pcall(tradeSkillAPI.GetTradeSkillLineInfoByID, skillLine)
        local professionName = ok and GetProfessionBySkillLineID(parentSkillLineID) or nil
        if professionName then
            return CacheProfessionSkillLine(skillLine, professionName)
        end
    end

    return nil
end

local function LogUnresolvedProfessionSkillLine(professionName, skillLine, skillLineName)
    skillLine = tonumber(skillLine)
    if not skillLine or unresolvedProfessionSkillLines[skillLine] then
        return
    end
    unresolvedProfessionSkillLines[skillLine] = true

    if GAM.Log and GAM.Log.Debug then
        GAM.Log.Debug(
            "MainWindow: unresolved profession skill line name=%s skillLine=%s skillLineName=%s",
            tostring(professionName),
            tostring(skillLine),
            tostring(skillLineName)
        )
    end
end

local function ResolvePlayerProfession(professionName, skillLine, skillLineName, supported)
    local canonicalProfession = ResolveProfessionFromSkillLine(skillLine)
    if canonicalProfession and (not supported or supported[canonicalProfession]) then
        return canonicalProfession
    end

    if professionName and (not supported or supported[professionName]) then
        return professionName
    end

    LogUnresolvedProfessionSkillLine(professionName, skillLine, skillLineName)
    return nil
end

local C_DR, C_DG, C_DB = 0.7, 0.57, 0.0

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
    cardGap = 18,
    outerPadding = 18,
    guideHeight = 58,
    cardContentInsets = { left = 22, right = 22, top = 20, bottom = 20 },
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
        panelGap = 12,
        frame = {
            backdrop = Common.THIN_BACKDROP,
            bgColor = { 0.028, 0.028, 0.028, 1.0 },
            borderColor = { C_DR, C_DG, C_DB, 0.62 },
        },
        headerBackdrop = { 0.04, 0.04, 0.04, 0.95 },
        titleText      = { 1.0, 0.84, 0.16, 1.0 },
        subtitleText   = { 0.76, 0.66, 0.22, 1.0 },
        cardBanner     = { 0.11, 0.09, 0.03, 0.58 },
        cardRule       = { 0.80, 0.64, 0.12, 0.46 },
        shells = {
            panel = {
                outerBackdrop = Common.THIN_BACKDROP,
                outerBgColor = { 0.048, 0.048, 0.048, 0.97 },
                outerBorderColor = { C_DR, C_DG, C_DB, 0.34 },
                innerBackdrop = Common.THIN_BACKDROP,
                innerBgColor = { 0.052, 0.052, 0.052, 0.94 },
                innerBorderColor = { C_DR, C_DG, C_DB, 0.16 },
            },
            center = {
                outerBackdrop = Common.THIN_BACKDROP,
                outerBgColor = { 0.042, 0.042, 0.042, 1.0 },
                outerBorderColor = { C_DR, C_DG, C_DB, 0.28 },
                innerBackdrop = Common.THIN_BACKDROP,
                innerBgColor = { 0.046, 0.046, 0.046, 0.96 },
                innerBorderColor = { C_DR, C_DG, C_DB, 0.14 },
            },
            card = {
                outerBackdrop = Common.THIN_BACKDROP,
                outerBgColor = { 0.050, 0.050, 0.050, 1.0 },
                outerBorderColor = { C_DR, C_DG, C_DB, 0.30 },
                innerBackdrop = Common.THIN_BACKDROP,
                innerBgColor = { 0.055, 0.055, 0.055, 0.96 },
                innerBorderColor = { C_DR, C_DG, C_DB, 0.14 },
            },
            status = {
                outerBackdrop = Common.THIN_BACKDROP,
                outerBgColor = { 0.050, 0.050, 0.050, 1.0 },
                outerBorderColor = { C_DR, C_DG, C_DB, 0.42 },
                innerBackdrop = Common.THIN_BACKDROP,
                innerBgColor = { 0.056, 0.056, 0.056, 0.96 },
                innerBorderColor = { C_DR, C_DG, C_DB, 0.16 },
            },
            section = {
                outerBackdrop = Common.THIN_BACKDROP,
                outerBgColor = { 0.062, 0.062, 0.062, 0.96 },
                outerBorderColor = { C_DR, C_DG, C_DB, 0.22 },
                innerBackdrop = Common.THIN_BACKDROP,
                innerBgColor = { 0.066, 0.066, 0.066, 0.96 },
                innerBorderColor = { C_DR, C_DG, C_DB, 0.14 },
            },
        },
        tickerBackdrop  = { 0.058, 0.058, 0.058, 1.0 },
        tickerBorder    = { C_DR, C_DG, C_DB, 0.42 },
        tickerText      = { 0.82, 0.81, 0.77, 1.0 },
        statusText      = { 0.90, 0.88, 0.83, 1.0 },
        progressText    = { 1.0, 0.98, 0.94, 1.0 },
        progressBar     = { 0.28, 0.70, 0.34, 1.0 },
        progressBarBg   = { 0.11, 0.09, 0.05, 0.96 },
        collapseBackdrop = { 0.09, 0.09, 0.09, 0.92 },
        collapseBorder  = { C_DR, C_DG, C_DB, 0.88 },
        compactBackdrop = { 0.09, 0.09, 0.09, 0.92 },
        compactBorder   = { C_DR, C_DG, C_DB, 0.88 },
        sectionHeader   = { 0.15, 0.11, 0.03, 0.92 },
        listRowOdd      = { 0.12, 0.12, 0.12, 0.62 },
        listRowEven     = { 0.10, 0.10, 0.10, 0.34 },
        listRowSelected = { 0.21, 0.16, 0.05, 0.86 },
        separatorColor  = { 0.78, 0.62, 0.12, 0.72 },
        placeholderText = { 0.72, 0.70, 0.66, 1.0 },
        cardTitleText   = { 1.0, 0.84, 0.16, 1.0 },
        cardBodyText    = { 0.90, 0.87, 0.81, 1.0 },
        bodyText        = { 0.92, 0.90, 0.85, 1.0 },
        mutedText       = { 0.73, 0.69, 0.61, 1.0 },
    },
    soft = {
        panelGap = Common.SOFT_LAYOUT.collapseGap,
        layout = Common.SOFT_LAYOUT,
        frame = {
            backdrop = Common.SOFT_OUTER_BACKDROP,
            bgColor = { 0.06, 0.05, 0.04, 0.985 },
            borderColor = { 0.88, 0.80, 0.64, 0.96 },
        },
        board = {
            backdrop = Common.THIN_BACKDROP,
            bgColor = { 0.05, 0.04, 0.03, 0.93 },
            borderColor = { 0.38, 0.27, 0.11, 0.48 },
        },
        paperCard = {
            texture = Common.SOFT_PAPER_TEXTURE,
            textureColor = { 1.0, 0.99, 0.94, 0.98 },
            washColor = { 1.0, 0.97, 0.88, 0.16 },
            edgeShadeColor = { 0.22, 0.12, 0.05, 0.10 },
            edgeSize = 14,
            shadowColor = { 0.0, 0.0, 0.0, 0.16 },
            contentInsets = Common.SOFT_LAYOUT.cardContentInsets,
        },
        headerBackdrop = { 0.08, 0.06, 0.05, 0.97 },
        titleText      = { 1.0, 0.86, 0.36, 1.0 },
        subtitleText   = { 0.86, 0.75, 0.46, 1.0 },
        cardBanner     = { 0.18, 0.13, 0.09, 0.0 },
        cardRule       = { 0.34, 0.20, 0.07, 0.76 },
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
        tickerBackdrop  = { 0.10, 0.08, 0.06, 0.985 },
        tickerBorder    = { 0.76, 0.62, 0.27, 0.76 },
        tickerText      = { 0.95, 0.88, 0.74, 1.0 },
        statusText      = { 0.94, 0.88, 0.74, 1.0 },
        progressText    = { 1.0, 0.95, 0.84, 1.0 },
        progressBar     = { 0.34, 0.67, 0.30, 1.0 },
        progressBarBg   = { 0.16, 0.12, 0.08, 0.94 },
        collapseBackdrop = { 0.14, 0.11, 0.08, 0.96 },
        collapseBorder  = { 0.76, 0.62, 0.28, 0.94 },
        compactBackdrop = { 0.15, 0.12, 0.08, 0.98 },
        compactBorder   = { 0.78, 0.64, 0.30, 0.96 },
        sectionHeader   = { 0.26, 0.17, 0.08, 0.08 },
        listRowOdd      = { 0.24, 0.16, 0.08, 0.050 },
        listRowEven     = { 0.16, 0.10, 0.05, 0.028 },
        listRowSelected = { 0.46, 0.31, 0.12, 0.14 },
        separatorColor  = { 0.30, 0.18, 0.06, 0.66 },
        placeholderText = { 0.08, 0.05, 0.02, 0.98 },
        cardTitleText   = { 1.0, 0.86, 0.36, 1.0 },
        cardBodyText    = { 0.08, 0.05, 0.02, 1.0 },
        bodyText        = { 0.08, 0.05, 0.02, 1.0 },
        mutedText       = { 0.18, 0.11, 0.05, 0.98 },
    },
}

local function ComfortableShell(bg, border)
    return {
        outerBackdrop = Common.THIN_BACKDROP,
        outerBgColor = bg,
        outerBorderColor = border or { 0.38, 0.32, 0.14, 0.72 },
        innerBackdrop = Common.FLAT_BACKDROP,
        innerBgColor = bg,
        innerBorderColor = { 0, 0, 0, 0 },
        innerInsets = { left = 1, right = 1, top = 1, bottom = 1 },
    }
end

-- The Dev build has one presentation, not a user-selectable theme. These
-- tokens keep the hierarchy quiet: content and spacing do the grouping while
-- gold is reserved for decisions, selection, and section labels.
Common.THEMES.comfortable = {
    panelGap = 10,
    frame = {
        backdrop = Common.THIN_BACKDROP,
        bgColor = { 0.055, 0.055, 0.062, 0.99 },
        borderColor = { 0.48, 0.40, 0.16, 0.90 },
    },
    headerBackdrop = { 0.070, 0.070, 0.078, 1.0 },
    titleText = { 0.96, 0.82, 0.36, 1.0 },
    subtitleText = { 0.68, 0.68, 0.70, 1.0 },
    cardBanner = { 0, 0, 0, 0 },
    cardRule = { 0.38, 0.32, 0.14, 0.65 },
    shells = {
        panel = ComfortableShell({ 0.105, 0.105, 0.115, 1.0 }),
        center = ComfortableShell({ 0.090, 0.090, 0.100, 1.0 }),
        card = ComfortableShell({ 0.105, 0.105, 0.115, 1.0 }),
        status = ComfortableShell({ 0.090, 0.090, 0.100, 1.0 }),
        section = ComfortableShell({ 0.115, 0.115, 0.125, 1.0 }),
    },
    tickerBackdrop = { 0.070, 0.070, 0.078, 1.0 },
    tickerBorder = { 0.30, 0.28, 0.20, 0.70 },
    tickerText = { 0.74, 0.74, 0.76, 1.0 },
    statusText = { 0.82, 0.82, 0.84, 1.0 },
    progressText = { 0.96, 0.96, 0.97, 1.0 },
    progressBar = { 0.32, 0.68, 0.38, 1.0 },
    progressBarBg = { 0.08, 0.08, 0.09, 1.0 },
    collapseBackdrop = { 0.12, 0.12, 0.13, 1.0 },
    collapseBorder = { 0.40, 0.34, 0.16, 0.80 },
    compactBackdrop = { 0.15, 0.15, 0.16, 1.0 },
    compactBorder = { 0.42, 0.37, 0.22, 0.90 },
    sectionHeader = { 0.15, 0.15, 0.16, 1.0 },
    listRowOdd = { 0.155, 0.155, 0.168, 1.0 },
    listRowEven = { 0.125, 0.125, 0.138, 1.0 },
    listRowSelected = { 0.30, 0.26, 0.16, 1.0 },
    separatorColor = { 0.35, 0.32, 0.24, 0.78 },
    placeholderText = { 0.58, 0.58, 0.61, 1.0 },
    cardTitleText = { 0.96, 0.82, 0.36, 1.0 },
    cardBodyText = { 0.88, 0.88, 0.90, 1.0 },
    bodyText = { 0.88, 0.88, 0.90, 1.0 },
    mutedText = { 0.68, 0.68, 0.72, 1.0 },
}

Common.THEME_PROFILE_DEFAULT = "Default"

Common.THEME_COLOR_DEFS = {
    { key = "windowBackground", label = "Window background", help = "The main addon window surface." },
    { key = "panelBackground", label = "Panel background", help = "The left, center, right, and status panel surfaces." },
    { key = "cardBackground", label = "Card background", help = "Cards, detail sections, and secondary surfaces." },
    { key = "border", label = "Borders", help = "Window, panel, card, and control borders." },
    { key = "accent", label = "Accent", help = "Titles, section accents, separators, and selections." },
    { key = "primaryText", label = "Primary text", help = "Main labels, item names, and important values." },
    { key = "secondaryText", label = "Secondary text", help = "Supporting text, hints, and subdued values." },
    { key = "row", label = "List rows", help = "Alternating list and detail row backgrounds." },
    { key = "selectedRow", label = "Selected row", help = "The background used for the selected strategy." },
    { key = "progress", label = "Progress bar", help = "The active scan progress indicator." },
    { key = "button", label = "Buttons", help = "Common button surfaces and their borders." },
}

local function CopyThemeValue(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = CopyThemeValue(v)
    end
    return copy
end

local function CopyColor(value, fallback)
    value = type(value) == "table" and value or fallback or { 1, 1, 1, 1 }
    return {
        math.max(0, math.min(1, tonumber(value[1]) or 1)),
        math.max(0, math.min(1, tonumber(value[2]) or 1)),
        math.max(0, math.min(1, tonumber(value[3]) or 1)),
        math.max(0, math.min(1, tonumber(value[4]) or 1)),
    }
end

local function SetThemeColor(target, color)
    if target then
        target[1], target[2], target[3], target[4] = color[1], color[2], color[3], color[4]
    end
end

function Common.GetThemeKey(opts)
    if GAM.C and GAM.C.USE_COMFORTABLE_UI then
        return "comfortable"
    end
    local key = opts and opts.v2Theme or "classic"
    return Common.THEMES[key] and key or "classic"
end

local function GetDefaultPalette(opts)
    local theme = Common.THEMES[Common.GetThemeKey(opts)] or Common.THEMES.classic
    local shell = theme.shells and theme.shells.panel or {}
    local cardShell = theme.shells and theme.shells.card or shell
    return {
        windowBackground = CopyColor(theme.frame and theme.frame.bgColor),
        panelBackground = CopyColor(shell.outerBgColor or theme.frame.bgColor),
        cardBackground = CopyColor(cardShell.innerBgColor or cardShell.outerBgColor or theme.frame.bgColor),
        border = CopyColor(theme.frame and theme.frame.borderColor),
        accent = CopyColor(theme.titleText),
        primaryText = CopyColor(theme.bodyText),
        secondaryText = CopyColor(theme.mutedText),
        row = CopyColor(theme.listRowOdd),
        selectedRow = CopyColor(theme.listRowSelected),
        progress = CopyColor(theme.progressBar),
        button = { 0.16, 0.16, 0.18, 1 },
    }
end

local function GetThemeDB()
    return GAM.db
end

local function EnsureThemeProfiles()
    local db = GetThemeDB()
    if not db then return nil end
    db.themeProfiles = type(db.themeProfiles) == "table" and db.themeProfiles or {}
    db.themeProfileSelections = type(db.themeProfileSelections) == "table"
        and db.themeProfileSelections or {}
    db.activeThemeProfile = type(db.activeThemeProfile) == "string"
        and db.activeThemeProfile ~= "" and db.activeThemeProfile or Common.THEME_PROFILE_DEFAULT
    local characterKey = Common.GetThemeCharacterKey()
    local selected = db.themeProfileSelections[characterKey]
    if selected == nil then selected = db.activeThemeProfile end
    if selected ~= Common.THEME_PROFILE_DEFAULT and type(db.themeProfiles[selected]) ~= "table" then
        selected = Common.THEME_PROFILE_DEFAULT
    end
    db.themeProfileSelections[characterKey] = selected
    return db
end

function Common.GetThemeCharacterKey()
    local name = UnitName and UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or "Unknown"
    return tostring(realm) .. "|" .. tostring(name)
end

function Common.GetThemeProfileNames()
    local db = EnsureThemeProfiles()
    local names = { Common.THEME_PROFILE_DEFAULT }
    if not db then return names end
    for name, profile in pairs(db.themeProfiles) do
        if type(name) == "string" and name ~= Common.THEME_PROFILE_DEFAULT and type(profile) == "table" then
            names[#names + 1] = name
        end
    end
    table.sort(names, function(a, b)
        if a == b then return false end
        if a == Common.THEME_PROFILE_DEFAULT then return true end
        if b == Common.THEME_PROFILE_DEFAULT then return false end
        return a:lower() < b:lower()
    end)
    return names
end

function Common.GetActiveThemeProfileName()
    local db = EnsureThemeProfiles()
    if not db then return Common.THEME_PROFILE_DEFAULT end
    return db.themeProfileSelections[Common.GetThemeCharacterKey()] or Common.THEME_PROFILE_DEFAULT
end

function Common.GetThemeProfile(name, opts)
    name = name or Common.GetActiveThemeProfileName()
    local db = EnsureThemeProfiles()
    if name ~= Common.THEME_PROFILE_DEFAULT and db and type(db.themeProfiles[name]) == "table" then
        local profile = {}
        local defaults = GetDefaultPalette(opts)
        for _, def in ipairs(Common.THEME_COLOR_DEFS) do
            profile[def.key] = CopyColor(db.themeProfiles[name][def.key], defaults[def.key])
        end
        return profile
    end
    return GetDefaultPalette(opts)
end

function Common.SetActiveThemeProfile(name)
    local db = EnsureThemeProfiles()
    if not db then return false end
    if name ~= Common.THEME_PROFILE_DEFAULT and type(db.themeProfiles[name]) ~= "table" then
        return false
    end
    db.themeProfileSelections[Common.GetThemeCharacterKey()] = name
    return true
end

function Common.CreateThemeProfile(name, sourceName, opts)
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    if name == "" or name == Common.THEME_PROFILE_DEFAULT then return false end
    local db = EnsureThemeProfiles()
    if not db then return false end
    if db.themeProfiles[name] ~= nil then return false end
    local source = Common.GetThemeProfile(sourceName or Common.GetActiveThemeProfileName(), opts)
    db.themeProfiles[name] = CopyThemeValue(source)
    db.themeProfileSelections[Common.GetThemeCharacterKey()] = name
    return true
end

function Common.DeleteThemeProfile(name)
    local db = EnsureThemeProfiles()
    if not db or name == Common.THEME_PROFILE_DEFAULT or type(db.themeProfiles[name]) ~= "table" then
        return false
    end
    db.themeProfiles[name] = nil
    for characterKey, selected in pairs(db.themeProfileSelections) do
        if selected == name then
            db.themeProfileSelections[characterKey] = Common.THEME_PROFILE_DEFAULT
        end
    end
    if db.activeThemeProfile == name then
        db.activeThemeProfile = Common.THEME_PROFILE_DEFAULT
    end
    return true
end

function Common.SetThemeProfileColor(name, key, color, opts)
    if name == Common.THEME_PROFILE_DEFAULT then return false end
    local db = EnsureThemeProfiles()
    if not (db and db.themeProfiles[name] and type(color) == "table") then return false end
    local defaults = GetDefaultPalette(opts)
    if not defaults[key] then return false end
    db.themeProfiles[name][key] = CopyColor(color, defaults[key])
    return true
end

function Common.ResetThemeProfile(name, opts)
    if name == Common.THEME_PROFILE_DEFAULT then return false end
    local db = EnsureThemeProfiles()
    if not (db and db.themeProfiles[name]) then return false end
    db.themeProfiles[name] = GetDefaultPalette(opts)
    return true
end

function Common.IsCustomThemeActive()
    return Common.GetActiveThemeProfileName() ~= Common.THEME_PROFILE_DEFAULT
end

local function ApplyPaletteToTheme(theme, palette)
    -- These aliases are also consumed by button styling and make the active
    -- palette available to any future UI module without duplicating token names.
    theme.primaryText = palette.primaryText
    theme.secondaryText = palette.secondaryText
    theme.accent = palette.accent
    theme.buttonNormal = theme.buttonNormal or { 0.16, 0.16, 0.18, 1 }
    theme.buttonPushed = theme.buttonPushed or { 0.12, 0.12, 0.14, 1 }
    theme.buttonBorder = theme.buttonBorder or { 0.34, 0.34, 0.38, 1 }
    local function setShellColor(field, color)
        for _, variant in pairs(theme.shells or {}) do
            if type(variant) == "table" and variant[field] then
                SetThemeColor(variant[field], color)
            end
        end
    end

    SetThemeColor(theme.frame and theme.frame.bgColor, palette.windowBackground)
    setShellColor("outerBgColor", palette.panelBackground)
    setShellColor("innerBgColor", palette.cardBackground)
    SetThemeColor(theme.frame and theme.frame.borderColor, palette.border)
    setShellColor("outerBorderColor", palette.border)
    setShellColor("innerBorderColor", palette.border)
    SetThemeColor(theme.titleText, palette.accent)
    SetThemeColor(theme.cardTitleText, palette.accent)
    SetThemeColor(theme.cardRule, palette.accent)
    SetThemeColor(theme.separatorColor, palette.accent)
    SetThemeColor(theme.collapseBorder, palette.border)
    SetThemeColor(theme.compactBorder, palette.border)
    SetThemeColor(theme.tickerBorder, palette.border)
    SetThemeColor(theme.bodyText, palette.primaryText)
    SetThemeColor(theme.cardBodyText, palette.primaryText)
    SetThemeColor(theme.statusText, palette.primaryText)
    SetThemeColor(theme.progressText, palette.primaryText)
    SetThemeColor(theme.tickerText, palette.secondaryText)
    SetThemeColor(theme.subtitleText, palette.secondaryText)
    SetThemeColor(theme.mutedText, palette.secondaryText)
    SetThemeColor(theme.placeholderText, palette.secondaryText)
    SetThemeColor(theme.listRowOdd, palette.row)
    SetThemeColor(theme.listRowEven, palette.row)
    SetThemeColor(theme.listRowSelected, palette.selectedRow)
    SetThemeColor(theme.progressBar, palette.progress)
    SetThemeColor(theme.buttonNormal, palette.button)
    SetThemeColor(theme.buttonPushed, palette.button)
    SetThemeColor(theme.buttonBorder, palette.border)
end

local themeCacheKey
local themeCache

function Common.InvalidateThemeCache()
    themeCacheKey, themeCache = nil, nil
end

function Common.GetThemeDef(opts)
    local baseKey = Common.GetThemeKey(opts)
    local profileName = Common.GetActiveThemeProfileName()
    local cacheKey = baseKey .. "|" .. profileName
    if themeCacheKey == cacheKey and themeCache then return themeCache end
    local base = Common.THEMES[baseKey] or Common.THEMES.classic
    if profileName == Common.THEME_PROFILE_DEFAULT then
        themeCacheKey, themeCache = cacheKey, base
        return base
    end
    local themed = CopyThemeValue(base)
    ApplyPaletteToTheme(themed, Common.GetThemeProfile(profileName, opts))
    themeCacheKey, themeCache = cacheKey, themed
    return themed
end

function Common.GetThemeColorDefinitions()
    return Common.THEME_COLOR_DEFS
end

-- Colors for workspace tabs, taken from the active theme so appearance
-- profiles apply. Status colors (gain, loss, warning) and coin colors stay fixed.
local THEME_FALLBACK = {
    accent = { 1, 0.82, 0, 1 }, body = { 0.92, 0.92, 0.94, 1 },
    muted = { 0.72, 0.72, 0.76, 1 }, band = { 1, 1, 1, 0.05 },
}
function Common.ThemeColor(role)
    local ok, theme = pcall(Common.GetThemeDef)
    theme = ok and type(theme) == "table" and theme or {}
    local color = (role == "accent" and (theme.cardTitleText or theme.titleText))
        or (role == "body" and theme.bodyText) or (role == "muted" and theme.mutedText)
        or (role == "band" and theme.listRowOdd) or nil
    return color or THEME_FALLBACK[role] or THEME_FALLBACK.body
end
function Common.ThemeHex(role)
    local c = Common.ThemeColor(role)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- Coin-colored gold with a colored sign: + gained, - spent or lost.
-- short drops copper once there is gold (narrow columns).
function Common.SignedMoney(copper, short)
    if not copper then return "—" end
    local abs = math.abs(math.floor(copper))
    -- Short: no copper from 1g, no silver from 100g.
    if short and abs >= 1000000 then abs = abs - abs % 10000
    elseif short and abs >= 10000 then abs = abs - abs % 100 end
    local text = GAM.Pricing and GAM.Pricing.FormatPrice and GAM.Pricing.FormatPrice(abs) or tostring(abs)
    if abs == 0 then return text end
    return (copper < 0 and "|cffff8a7a-|r" or "|cff83e896+|r") .. text
end

-- One status vocabulary across tabs: green ready, amber check, red problem, grey waiting.
Common.STATUS_TEXTURES = {
    ok = "Interface\\COMMON\\Indicator-Green", warn = "Interface\\COMMON\\Indicator-Yellow",
    bad = "Interface\\COMMON\\Indicator-Red", neutral = "Interface\\COMMON\\Indicator-Gray",
}
function Common.StatusDot(kind, size)
    size = size or 12
    return "|T" .. (Common.STATUS_TEXTURES[kind] or Common.STATUS_TEXTURES.neutral) .. ":" .. size .. ":" .. size .. "|t"
end

function Common.RefreshTheme()
    Common.InvalidateThemeCache()
    if GAM.UI and GAM.UI.MainWindow and GAM.UI.MainWindow.ApplyTheme then
        GAM.UI.MainWindow.ApplyTheme()
    end
    if GAM.UI and GAM.UI.WindowManager and GAM.UI.WindowManager.RefreshThemes then
        GAM.UI.WindowManager.RefreshThemes()
    end
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

-- Recipe open/refresh failures arrive as internal codes. Players get a
-- sentence with a next step; the code is kept in the debug log.
local RECIPE_FAILURE_KEYS = {
    ["missing-recipe-id"] = { "ERR_RECIPE_NO_ID", "This strategy has no recipe ID, so its stats cannot be refreshed." },
    ["profession-api-unavailable"] = { "ERR_RECIPE_API", "The profession interface is not available right now. Try again after /reload." },
    ["unsupported-profession"] = { "ERR_RECIPE_UNSUPPORTED", "This profession does not support recipe stat capture." },
    ["profession-not-known"] = { "ERR_RECIPE_NOT_KNOWN", "This character does not know this profession. Log into your crafter and select the recipe once." },
    ["open-profession-failed"] = { "ERR_RECIPE_OPEN_BLOCKED", "The profession window could not be opened. Leave combat and try again." },
    ["open-recipe-failed"] = { "ERR_RECIPE_OPEN_BLOCKED", "The profession window could not be opened. Leave combat and try again." },
    ["recipe-not-in-current-profession"] = { "ERR_RECIPE_NOT_LEARNED", "This recipe is not in this character's recipe list. Learn it, or log into the crafter who knows it." },
    ["no-open-profession"] = { "ERR_RECIPE_WINDOW_LOADING", "The profession window did not finish loading. Open it once, then click Refresh Recipe again." },
    ["no-open-profession-nodes"] = { "ERR_RECIPE_WINDOW_LOADING", "The profession window did not finish loading. Open it once, then click Refresh Recipe again." },
    ["profession-nodes-not-visible"] = { "ERR_RECIPE_WINDOW_LOADING", "The profession window did not finish loading. Open it once, then click Refresh Recipe again." },
    ["open-recipe-not-visible"] = { "ERR_RECIPE_NOT_SHOWN", "The recipe was not shown in time. Click Refresh Recipe again." },
    ["no-open-native-recipe"] = { "ERR_RECIPE_NOT_SHOWN", "The recipe was not shown in time. Click Refresh Recipe again." },
    ["temporary-buff-active"] = { "ERR_TEMP_BUFF_ACTIVE", "Shattered Essence is raising your stats for a few minutes, so GAM won't save them. Try again when it ends." },
    ["open-recipe-mismatch"] = { "ERR_RECIPE_MISMATCH", "A different recipe stayed open. Select this recipe in the profession window, then click Refresh Recipe." },
}

function Common.DescribeRecipeFailure(reason)
    local L = GAM.L or {}
    local code = tostring(reason or "unknown")
    local entry = RECIPE_FAILURE_KEYS[code:match("^([%a%-]+)") or code]
    if GAM.Log and GAM.Log.Warn then GAM.Log.Warn("Recipe: open/refresh failed: %s", code) end
    if entry then return L[entry[1]] or entry[2] end
    return string.format(L["ERR_RECIPE_GENERIC"] or "Could not open the selected recipe (%s).", code)
end

-- One Push-to-CraftSim action for every window, so feedback cannot drift.
function Common.PushPricesToCraftSim(strat, patchTag, canonicalResult)
    if not strat or not (GAM.CraftSimBridge and GAM.CraftSimBridge.PushStratPrices) then return end
    local L = GAM.L or {}
    local pushed, err = GAM.CraftSimBridge.PushStratPrices(strat, patchTag, canonicalResult)
    if err then
        print("|cffff8800[GAM]|r " .. string.format(
            L["MSG_CRAFTSIM_PUSH_FAILED"] or "CraftSim push failed: %s", tostring(err)))
    elseif (pushed or 0) == 0 then
        print("|cffff8800[GAM]|r " .. (L["MSG_NO_PRICES_TO_PUSH"] or "No prices to push - scan items first."))
    else
        print("|cffff8800[GAM]|r " .. string.format(
            L["MSG_PRICES_PUSHED"] or "Pushed %d price(s) to CraftSim.", pushed))
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

function Common.StyleComfortableButton(button, primary)
    if not button or not ((GAM.C and GAM.C.USE_COMFORTABLE_UI) or Common.IsCustomThemeActive()) then return end
    button._gamComfortPrimary = primary and true or false
    local theme = Common.GetThemeDef()
    local normal = primary and { 0.29, 0.25, 0.12, 1 } or (theme.buttonNormal or { 0.16, 0.16, 0.18, 1 })
    local pushed = primary and { 0.36, 0.30, 0.13, 1 } or (theme.buttonPushed or { 0.12, 0.12, 0.14, 1 })
    local border = primary and (theme.accent or { 0.67, 0.56, 0.24, 1 }) or (theme.buttonBorder or { 0.34, 0.34, 0.38, 1 })

    local borderTexture = button._gamComfortBorder or button:CreateTexture(nil, "BACKGROUND")
    if borderTexture.SetAllPoints then
        borderTexture:SetAllPoints(button)
    else
        -- SetAllPoints is available on WoW textures, but keeping the
        -- equivalent anchors as a fallback makes this helper safe for
        -- lightweight UI fixtures and older texture shims.
        borderTexture:ClearAllPoints()
        borderTexture:SetPoint("TOPLEFT", button, "TOPLEFT")
        borderTexture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT")
    end
    if borderTexture.SetColorTexture then
        borderTexture:SetColorTexture(border[1], border[2], border[3], border[4])
    elseif borderTexture.SetVertexColor then
        borderTexture:SetVertexColor(border[1], border[2], border[3], border[4])
    end
    button._gamComfortBorder = borderTexture

    button:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
    button:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
    button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
    -- UIPanelButtonTemplate normally supplies its own disabled art.  Once the
    -- normal/pushed textures are flattened, explicitly flatten the disabled
    -- state too so a disabled action never snaps back to Blizzard's bevel.
    if button.SetDisabledTexture then
        button:SetDisabledTexture("Interface\\Buttons\\WHITE8X8")
    end
    for _, pair in ipairs({
        { button:GetNormalTexture(), normal },
        { button:GetPushedTexture(), pushed },
        { button:GetHighlightTexture(), { 0.22, 0.22, 0.24, 0.45 } },
    }) do
        local texture, color = pair[1], pair[2]
        if texture then
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
            texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
            texture:SetVertexColor(color[1], color[2], color[3], color[4])
        end
    end
    local disabledTexture = button.GetDisabledTexture and button:GetDisabledTexture()
    if disabledTexture then
        disabledTexture:ClearAllPoints()
        disabledTexture:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        disabledTexture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        disabledTexture:SetVertexColor(0.10, 0.10, 0.11, 0.82)
    end
    local function ApplyButtonFontState(self)
        local fontString = self.GetFontString and self:GetFontString()
        if not fontString then return end
        local enabled = not self.IsEnabled or self:IsEnabled()
        if enabled then
            local text = primary and (theme.accent or { 0.96, 0.84, 0.42, 1 }) or (theme.primaryText or { 0.90, 0.90, 0.92, 1 })
            fontString:SetTextColor(text[1], text[2], text[3], text[4] or 1)
        else
            fontString:SetTextColor(0.58, 0.58, 0.62, 1)
        end
    end
    if button.HookScript and not button._gamComfortHooksInstalled then
        button:HookScript("OnEnable", ApplyButtonFontState)
        button:HookScript("OnDisable", ApplyButtonFontState)
        button._gamComfortHooksInstalled = true
    end
    ApplyButtonFontState(button)
end

function Common.RefreshButtonStyles(frame)
    if not frame or not frame.GetChildren then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        if child.IsObjectType and child:IsObjectType("Button")
                and child.GetText and child:GetText() and child:GetText() ~= ""
                and (not child._gamComfortBorder or child._gamComfortPrimary ~= nil) then
            Common.StyleComfortableButton(child, child._gamComfortPrimary)
        end
        Common.RefreshButtonStyles(child)
    end
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
    return (GAM.WorkbookGenerated and GAM.WorkbookGenerated.formulaProfiles) or {}
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

    -- GetProfessions() has nil holes for unlearned secondary professions;
    -- iterate fixed return slots so Cooking is not skipped when earlier slots are nil.
    local indices = { GetProfessions() }
    for i = 1, 6 do
        local index = indices[i]
        if index then
            local professionName, _, _, _, _, _, skillLine, _, _, _, skillLineName = GetProfessionInfo(index)
            local canonicalProfession = ResolvePlayerProfession(professionName, skillLine, skillLineName, supported)
            if canonicalProfession then
                set[canonicalProfession] = true
            end
        end
    end

    return set
end

function Common.HasAnyEntries(set)
    return set and next(set) ~= nil
end

function Common.StratMatchesFilter(strat, filterMode, filterProfSet, filterProf, filterProfSingleSet, rankPolicy)
    -- Explicit selection keeps an empty picker empty instead of widening to all.
    if filterMode == "selected" and not (filterProfSingleSet and filterProfSingleSet[strat.profession]) then
        return false
    end
    local poolOK
    if filterMode == "mine" and Common.HasAnyEntries(filterProfSet) then
        poolOK = filterProfSet[strat.profession] == true
    else
        poolOK = filterProf == "All" or strat.profession == filterProf
    end
    if not poolOK then
        return false
    end
    if filterProfSingleSet and next(filterProfSingleSet) ~= nil and not filterProfSingleSet[strat.profession] then
        return false
    end
    if (rankPolicy == "highest" or rankPolicy == "optimal")
        and strat.qualityPolicy == "force_q1_inputs"
        and strat.outputQualityMode == "rank_policy" then
        return false
    end
    return true
end

function Common.BuildRuntimeColumns(rowW, mini)
    -- Keep the comparison model stable as panels open and close. Profession is
    -- already represented by the filter and row tooltip; missing prices use the
    -- existing dash plus tooltip instead of consuming a mostly-empty Status column.
    local gap = 8
    -- Reserve the scrollbar/collapse-button gutter so ROI never sits under the
    -- right panel toggle or clips against the center panel edge.
    local usable = math.max(300, rowW - 40)
    local roiW = 68
    local profitW = math.min(156, math.max(118, math.floor(usable * 0.24)))
    if mini and rowW < 600 then
        local nameW = usable - profitW - gap
        return {
            {id="stratName", x=10, w=nameW, hKey="COL_STRAT", sKey="stratName", j="LEFT"},
            {id="profit", x=10+nameW+gap, w=profitW, hKey="COL_PROFIT", sKey="profit", j="RIGHT"},
        }
    end
    local showSaleRate = GAM.TSMSaleRate and GAM.TSMSaleRate.IsAvailable()
    local saleW = showSaleRate and 76 or 0
    local nameW = usable - profitW - roiW - gap * 2 - (showSaleRate and saleW + gap or 0)
    local x = 10
    local cols = {
        { id="stratName", x=x, w=nameW, hKey="COL_STRAT", sKey="stratName", j="LEFT" },
    }
    x = x + nameW + gap
    cols[#cols + 1] = { id="profit", x=x, w=profitW, hKey="COL_PROFIT", sKey="profit", j="RIGHT" }
    x = x + profitW + gap
    cols[#cols + 1] = { id="roi", x=x, w=roiW, hKey="COL_ROI", sKey="roi", j="RIGHT" }

    if showSaleRate then
        x = x + roiW + gap
        cols[#cols + 1] = { id="saleRate", x=x, w=saleW, label=(GAM.L and GAM.L["UI_SALE_RATE"] or "Sale rate"), sKey="saleRate", j="RIGHT" }
    end
    return cols
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
    local runtimeCols = Common.BuildRuntimeColumns(args.rowW or 0, args.mini)
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
            btn.labelFS:SetText(col.label or (L and L[col.hKey]) or col.hKey)
            btn.labelFS:ClearAllPoints()
            btn.labelFS:SetPoint("TOPLEFT", btn, "TOPLEFT", i == 1 and stratIconWidth + 8 or 0, 0)
            btn.labelFS:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -6, 0)
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
        row.profitText:Hide()
        row.roiText:Hide()
        if row.saleRateText then row.saleRateText:Hide() end

        for _, col in ipairs(runtimeCols) do
            local fs
            if col.id == "stratName" then
                fs = row.nameText
            elseif col.id == "profit" then
                fs = row.profitText
            elseif col.id == "roi" then
                fs = row.roiText
            elseif col.id == "saleRate" then
                fs = row.saleRateText
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

    end

    return runtimeCols
end

-- Shared scan shortcut policy. Multiple modifiers use Ctrl, then Alt, then Shift.
function Common.GetScanMode(ctrl, alt, shift)
    if ctrl then return "all", "Scan Everything" end
    if alt then return "favorites", "Scan Favorites" end
    if shift then return "selected", "Scan Selected" end
    return "list", "Scan prices"
end
Common.SCAN_HELP = "Click: current list\nCtrl-click: everything\nAlt-click: all favorites\nShift-click: selected strategy\nWhile scanning: click to stop.\nCombined keys: Ctrl takes priority, then Alt, then Shift."

function Common.StyleSecondaryWindow(frame)
    if not frame or not ((GAM.C and GAM.C.USE_COMFORTABLE_UI) or Common.IsCustomThemeActive()) then return end
    local theme = Common.GetThemeDef()
    if frame.SetBackdropColor then
        local color = theme.frame.bgColor
        frame:SetBackdropColor(color[1], color[2], color[3], frame._gamOpaqueBackground and 1 or color[4])
    end
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(unpack(theme.frame.borderColor)) end
    if not frame._gamComfortHeader then
        local header = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
        header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
        header:SetHeight(36)
        frame._gamComfortHeader = header
    end
    if frame._gamComfortHeader then
        frame._gamComfortHeader:SetColorTexture(unpack(theme.headerBackdrop))
    end
    local function StyleButtons(parent)
        if not parent.GetChildren then return end
        for _, child in ipairs({parent:GetChildren()}) do
            if child.IsObjectType and child:IsObjectType("Button")
                and child.GetText and child:GetText() and child:GetText() ~= ""
                and (not child._gamComfortBorder or child._gamComfortPrimary ~= nil) then
                Common.StyleComfortableButton(child, child._gamComfortPrimary)
            end
            StyleButtons(child)
        end
    end
    StyleButtons(frame)
end
