-- GoldAdvisorMidnight/Settings.lua
-- Draggable standalone settings window. The Blizzard 12.1 canvas host can
-- present addon-owned anchored frames without its surrounding chrome, so GAM
-- keeps one deterministic layout for minimap, slash-command, and button entry.
-- Vertical navigation, measured setting rows, and one scroll viewport per page.
-- Module: GAM.Settings

local ADDON_NAME, GAM = ...

-- Capture Blizzard Settings API before any local `Settings` variable shadows it.
local BlizzardSettingsAPI = Settings

local SettingsMod = {}
GAM.Settings = SettingsMod
local WindowManager = GAM.UI.WindowManager
local Common = GAM.UI.MainWindowCommon
local NodeDisplay = GAM.ProfessionNodeDisplay

local panel          -- plain canvas frame (registered with Blizzard)
local wrapper        -- standalone popup wrapper (only built on Blizzard API failure)
local category       -- Blizzard Settings category reference
local categoryID     -- resolved category ID for OpenToCategory/OpenSettingsPanel
local nativeMode     -- true if Blizzard registration succeeded
local categoryPanel  -- stable Blizzard canvas that launches the standalone UI
local nodeCaptureUnsubscribe

local function LogWarn(fmt, ...)
    if GAM.Log and GAM.Log.Warn then
        GAM.Log.Warn(fmt, ...)
    end
end

local function ResolveCategoryID(cat)
    if not cat then return nil end
    if type(cat) == "table" then
        if type(cat.GetID) == "function" then
            local ok, id = pcall(cat.GetID, cat)
            if ok and id ~= nil then return id end
        end
        if cat.ID ~= nil then return cat.ID end
    end
    return cat
end

local function RegisterSettingsCategory()
    if category then return true end
    BlizzardSettingsAPI = _G.Settings

    if not categoryPanel then
        categoryPanel = CreateFrame("Frame", GAM.RuntimeName("GAMSettingsCategoryPanel"), UIParent)
        categoryPanel.name = GAM.L["SETTINGS_NAME"] or "Gold Advisor Midnight"
        categoryPanel:Hide()

        local title = categoryPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", categoryPanel, "TOPLEFT", 24, -24)
        title:SetText(categoryPanel.name)

        local note = categoryPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
        note:SetText("Gold Advisor settings open in their own movable window.")

        local openButton = CreateFrame("Button", nil, categoryPanel, "UIPanelButtonTemplate")
        openButton:SetSize(180, 26)
        openButton:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -18)
        openButton:SetText("Open Gold Advisor Settings")
        openButton:SetScript("OnClick", function()
            if SettingsMod.ShowStandalone then SettingsMod.ShowStandalone() end
        end)
        categoryPanel:SetScript("OnShow", function()
            if SettingsMod.ShowStandalone then SettingsMod.ShowStandalone() end
        end)
    end

    if BlizzardSettingsAPI and BlizzardSettingsAPI.RegisterCanvasLayoutCategory then
        local ok, cat = pcall(BlizzardSettingsAPI.RegisterCanvasLayoutCategory, categoryPanel, categoryPanel.name)
        if ok and cat then
            local registered, err = pcall(BlizzardSettingsAPI.RegisterAddOnCategory, cat)
            if not registered then
                LogWarn("Settings category registration failed: %s", tostring(err))
                return false
            end
            category = cat
            categoryID = ResolveCategoryID(cat)
            return true
        end
    elseif BlizzardSettingsAPI and BlizzardSettingsAPI.RegisterAddOnCategory then
        local ok, cat = pcall(BlizzardSettingsAPI.RegisterAddOnCategory, categoryPanel)
        if ok then
            category = cat or categoryPanel
            categoryID = ResolveCategoryID(category)
            return true
        end
    elseif InterfaceOptions_AddCategory then
        local ok = pcall(InterfaceOptions_AddCategory, categoryPanel)
        if ok then
            category = categoryPanel
            categoryID = ResolveCategoryID(categoryPanel) or categoryPanel.name
            return true
        end
    end
    return false
end

local function GetOpts()
    return (GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {}
end

local function ClearPriceCache()
    if GAM.State and GAM.State.ClearPriceCache then
        GAM.State.ClearPriceCache()
        return
    end
    if GAM.db and GAM.db.priceCache then
        wipe(GAM.db.priceCache)
    end
end

-- Apply a scale factor to all main addon frames
local function ApplyScaleToFrames(scale)
    local targets = {
        "GoldAdvisorMidnightMainWindow", "GoldAdvisorMidnightStrategyDetail",
        "GoldAdvisorMidnightDebugLog", "GAMQuickBuyWindow", "GAMCooldownTrackerWindow",
        "GAMVIBreakdownWindow", "GAMCrushingAnalyzer", "GAMARPExportPopup",
    }
    -- Iterate names: a table of frame values contains holes for unopened
    -- windows, and ipairs stops at the first hole.
    for _, name in ipairs(targets) do
        local f = _G[GAM.RuntimeName(name)]
        if f then f:SetScale(scale) end
    end
end

-- Gold accent color used throughout
local GOLD_R, GOLD_G, GOLD_B         = 1.0, 0.82, 0.0

-- Page, card, and row helpers live in GAM.UI.SettingsLayout (shared with the
-- Debug Log). They are bound in BuildPanel so this file still loads alone.
local Layout
local NewText, MakeSectionHeader, AddText, AddRow, AddCustom, LayoutPage
local MakeSlider, MakeCheckbox, MakeButton, MeasureButtonWidth, LayoutButtonsTop, NextWidgetName

local function MakeColorControl(parent, color)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(170, 28)
    button:SetText("")
    local swatch = button:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("LEFT", button, "LEFT", 8, 0)
    swatch:SetSize(18, 18)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetText("Choose color")
    button.swatch = swatch
    button.labelFS = label
    button:SetScript("OnDisable", function(self)
        self:SetAlpha(0.55)
    end)
    button:SetScript("OnEnable", function(self)
        self:SetAlpha(1)
    end)
    if color then
        swatch:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    end
    return button
end

local function OpenColorPicker(color, onChanged)
    if not ColorPickerFrame then return false end
    local previous = { color[1], color[2], color[3], color[4] or 1 }
    local function ReadPickerColor()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        local a = previous[4]
        if ColorPickerFrame.GetColorAlpha then
            a = ColorPickerFrame:GetColorAlpha()
        elseif ColorPickerFrame.opacity then
            a = 1 - ColorPickerFrame.opacity
        end
        onChanged({ r, g, b, a })
    end
    local info = {
        r = previous[1], g = previous[2], b = previous[3], opacity = previous[4],
        hasOpacity = true,
        swatchFunc = ReadPickerColor,
        opacityFunc = ReadPickerColor,
        cancelFunc = function()
            onChanged(previous)
        end,
    }
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        ColorPickerFrame.func = ReadPickerColor
        ColorPickerFrame.opacityFunc = ReadPickerColor
        ColorPickerFrame.cancelFunc = info.cancelFunc
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame:SetColorRGB(previous[1], previous[2], previous[3])
        if ColorPickerFrame.SetColorAlpha then ColorPickerFrame:SetColorAlpha(previous[4]) end
        ColorPickerFrame:Show()
    end
    return true
end

-- Rank policy uses a cycle button, avoiding pop-out menus inside scroll frames.

-- Formats an integer with thousands-separator commas: 50000 → "50,000"
local function FmtQty(n)
    local s = tostring(math.floor(n))
    return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function GetOptionValue(o, key, default)
    if not o then
        return default
    end
    local value = o[key]
    if value == nil then
        return default
    end
    return value
end

local function ClampStatPercentValue(value, fallback)
    local n = tonumber(value)
    if not n then
        n = fallback or 0
    end
    return math.max(0, math.min(100, n))
end

local function FormatStatPercentValue(value)
    local n = tonumber(value) or 0
    if math.abs(n - math.floor(n + 0.5)) < 0.0001 then
        return tostring(math.floor(n + 0.5))
    end
    return string.format("%.1f", n)
end

local function NormalizeV2PricingMode(mode)
    local value = tostring(mode or ""):lower()
    if value == "fixed_crafts" or value == "fixedcrafts" or value == "craftsim" then
        return "fixed_crafts"
    end
    if value == "exhaust_materials" or value == "exhaust" or value == "exhaustmaterials"
            or value == "fixed_input" or value == "fixedinput" or value == "spreadsheet" then
        return "exhaust_materials"
    end

    local defaultMode = tostring(
        (GAM.C and GAM.C.DEFAULT_V2_PRICING_MODE) or "exhaust_materials"):lower()
    if defaultMode == "fixed_crafts" then
        return "fixed_crafts"
    end
    return "exhaust_materials"
end

local function NormalizeStatBox(eb, fallback)
    if not eb then return fallback end
    local value = ClampStatPercentValue(eb:GetText(), fallback)
    eb:SetText(FormatStatPercentValue(value))
    eb:ClearFocus()
    return value
end

-- ===== Build the settings content panel =====
-- Returns a plain frame with no backdrop — safe to embed in Blizzard's canvas.
local function BuildPanel()
    -- Resolve at initialization too, so an earlier file load cannot retain nil.
    Common = assert(GAM.UI.MainWindowCommon, "Settings requires MainWindowCommon")
    Layout = assert(GAM.UI.SettingsLayout, "Settings requires SettingsLayout")
    NewText, MakeSectionHeader, AddText, AddRow, AddCustom, LayoutPage =
        Layout.NewText, Layout.MakeSectionHeader, Layout.AddText, Layout.AddRow,
        Layout.AddCustom, Layout.LayoutPage
    MakeSlider, MakeCheckbox, MakeButton, MeasureButtonWidth, LayoutButtonsTop, NextWidgetName =
        Layout.MakeSlider, Layout.MakeCheckbox, Layout.MakeButton, Layout.MeasureButtonWidth,
        Layout.LayoutButtonsTop, Layout.NextWidgetName
    local L    = GAM.L
    local opts = GetOpts()

    panel = CreateFrame("Frame", GAM.RuntimeName("GoldAdvisorMidnightSettingsPanel"), UIParent)
    panel:SetSize(760, 570)
    panel:SetPoint("CENTER", UIParent, "CENTER")
    panel:Hide()

    local navDefs = {
        { key = "general", label = "General", description = "Scanning and addon display." },
        { key = "appearance", label = "Appearance", description = "Shared colors for the addon UI." },
        { key = "pricing", label = "Pricing", description = "Default quantities and material prices." },
        { key = "crafting", label = "Stat fallbacks", description = "Manual values used when a captured profile is unavailable." },
        { key = "nodes", label = "Profession nodes", description = "Captured specialization ranks and manual overrides." },
        { key = "tools", label = "Tools", description = "Reload strategy data and manage the price cache." },
        { key = "about", label = "About", description = GAM.C.ADDON_DISPLAY_NAME .. " contributors and acknowledgments." },
    }

    local shell = Layout.CreateShell(panel, navDefs, { bottomKey = "about" })
    local pages, pageHost = shell.pages, shell.pageHost
    local SelectSettingsSection = shell.Select

    local content = pages.general.content
    local function FinalizeContentLayout()
        for _, page in pairs(pages) do
            if page.content == content then LayoutPage(page); break end
        end
    end

    -- ── Scan Settings ──────────────────────────────────────────────────────
    MakeSectionHeader(content, L["SETTINGS_SECTION_SCAN"])

    local slScanDelay, _ = MakeSlider(content, L["OPT_SCAN_DELAY"], L["OPT_SCAN_DELAY_TIP"],
        1, 10, 0.5)
    slScanDelay:SetValue(opts.scanDelay)

    local slVerbosity, _ = MakeSlider(content, L["OPT_VERBOSITY"], L["OPT_VERBOSITY_TIP"],
        0, 3, 1)
    slVerbosity:SetValue(opts.debugVerbosity)

    -- ── Display ────────────────────────────────────────────────────────────
    MakeSectionHeader(content, L["SETTINGS_SECTION_DISPLAY"])

    local cbMinimap = MakeCheckbox(content, L["OPT_MINIMAP"])
    cbMinimap:SetChecked(not opts.minimapHidden)

    -- Rank policy: cycle button — avoids UIDropDownMenu pop-out bugs.
    local rankLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankLabel:SetText(L["OPT_RANK_POLICY"])

    local rankTexts = {
        lowest = L["OPT_RANK_LOWEST"],
        optimal = L["OPT_RANK_OPTIMAL"] or "Best Mix to Max",
        highest = L["OPT_RANK_HIGHEST"],
    }
    local rankCurrent = rankTexts[opts.rankPolicy] and opts.rankPolicy or "lowest"

    local rankBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    rankBtn:SetSize(170, 28)
    rankBtn:SetText(rankTexts[rankCurrent])
    AddRow(content, rankLabel, rankBtn, nil, 170)
    rankBtn:SetScript("OnClick", function()
        rankCurrent = rankCurrent == "lowest" and "optimal"
            or rankCurrent == "optimal" and "highest"
            or "lowest"
        rankBtn:SetText(rankTexts[rankCurrent])
    end)

    -- Shim so ApplySettings can call ddRank.GetValue() unchanged
    local ddRank = { GetValue = function() return rankCurrent end }

    local slScale, slScaleVal = MakeSlider(content, L["OPT_UI_SCALE"], L["OPT_UI_SCALE_TIP"],
        GAM.C.MIN_UI_SCALE, GAM.C.MAX_UI_SCALE, 0.05)
    slScale:SetValue(opts.uiScale or GAM.C.DEFAULT_UI_SCALE)
    -- Override OnValueChanged to also apply scale live
    slScale:SetScript("OnValueChanged", function(self, v)
        slScaleVal:SetText(string.format("%.2f", v))
        ApplyScaleToFrames(v)
    end)

    local cbRememberAHState = MakeCheckbox(content, L["OPT_REMEMBER_AH_STATE"])
    cbRememberAHState:SetChecked(opts.rememberAHWindowState ~= false)
    cbRememberAHState:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["TT_OPT_REMEMBER_AH_STATE_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["TT_OPT_REMEMBER_AH_STATE_BODY"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    cbRememberAHState:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Appearance profiles ─────────────────────────────────────────────────
    FinalizeContentLayout()
    content = pages.appearance.content
    MakeSectionHeader(content, "Appearance profiles")
    local appearanceHint = NewText(content,
        "Choose a shared color profile for this addon. Profiles are saved account-wide, " ..
        "so the same profile can be selected by your other characters. Each character " ..
        "can use a different profile.", "GameFontHighlight")
    appearanceHint:SetTextColor(0.72, 0.72, 0.76)
    AddText(content, appearanceHint)

    local appearanceProfileName = Common.GetActiveThemeProfileName()
    local profileButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    profileButton:SetSize(170, 28)
    AddRow(content, "Active profile", profileButton, "Default uses the addon’s current colors.", 170)

    local newProfileBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    newProfileBox:SetSize(170, 26)
    newProfileBox:SetAutoFocus(false)
    newProfileBox:SetMaxLetters(32)
    AddRow(content, "New profile name", newProfileBox, "Create a named copy of the active profile.", 170)

    local createProfileButton = MakeButton(content, "Create profile", 170)
    AddRow(content, "Save as profile", createProfileButton, nil, 170)

    local resetProfileButton = MakeButton(content, "Reset profile colors", 170)
    AddRow(content, "Reset colors", resetProfileButton,
        "Restores the selected custom profile to the addon’s current default colors.", 170)

    local deleteProfileButton = MakeButton(content, "Delete profile", 170)
    AddRow(content, "Delete profile", deleteProfileButton, "Deletes the selected custom profile.", 170)

    local appearanceRows = {}
    local function RefreshAppearanceControls()
        appearanceProfileName = Common.GetActiveThemeProfileName()
        profileButton:SetText(appearanceProfileName)
        local editable = appearanceProfileName ~= Common.THEME_PROFILE_DEFAULT
        resetProfileButton:SetEnabled(editable)
        deleteProfileButton:SetEnabled(editable)
        for _, row in ipairs(appearanceRows) do
            local color = Common.GetThemeProfile(appearanceProfileName)[row.key]
            row.control.swatch:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
            row.control:SetEnabled(editable)
            row.control.labelFS:SetText(string.format("%.0f%%  %.0f%%  %.0f%%",
                color[1] * 100, color[2] * 100, color[3] * 100))
        end
    end

    profileButton:SetScript("OnClick", function()
        local names = Common.GetThemeProfileNames()
        local current = 1
        for i, name in ipairs(names) do
            if name == appearanceProfileName then current = i break end
        end
        local nextName = names[(current % #names) + 1]
        if Common.SetActiveThemeProfile(nextName) then
            Common.RefreshTheme()
            RefreshAppearanceControls()
        end
    end)

    local function CreateNamedProfile()
        local name = tostring(newProfileBox:GetText() or ""):match("^%s*(.-)%s*$")
        if name == "" then
            return
        end
        if Common.CreateThemeProfile(name, appearanceProfileName) then
            newProfileBox:SetText("")
            Common.RefreshTheme()
            RefreshAppearanceControls()
        else
            LogWarn("Could not create appearance profile '%s'.", name)
        end
    end
    createProfileButton:SetScript("OnClick", CreateNamedProfile)
    newProfileBox:SetScript("OnEnterPressed", CreateNamedProfile)

    resetProfileButton:SetScript("OnClick", function()
        if Common.ResetThemeProfile(appearanceProfileName) then
            Common.RefreshTheme()
            RefreshAppearanceControls()
        end
    end)
    deleteProfileButton:SetScript("OnClick", function()
        if Common.DeleteThemeProfile(appearanceProfileName) then
            Common.RefreshTheme()
            RefreshAppearanceControls()
        end
    end)

    for _, def in ipairs(Common.GetThemeColorDefinitions()) do
        local control = MakeColorControl(content)
        local row = { key = def.key, control = control }
        appearanceRows[#appearanceRows + 1] = row
        AddRow(content, def.label, control, def.help, 170, 44)
        control:SetScript("OnClick", function()
            if appearanceProfileName == Common.THEME_PROFILE_DEFAULT then return end
            local current = Common.GetThemeProfile(appearanceProfileName)[def.key]
            OpenColorPicker(current, function(color)
                if Common.SetThemeProfileColor(appearanceProfileName, def.key, color) then
                    Common.RefreshTheme()
                    RefreshAppearanceControls()
                end
            end)
        end)
    end
    RefreshAppearanceControls()

    -- ── Pricing ────────────────────────────────────────────────────────────
    FinalizeContentLayout()
    content = pages.pricing.content
    MakeSectionHeader(content, L["SETTINGS_SECTION_PRICING"])

    local ebGlobalStartingCrafts

    local startingCraftsLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    startingCraftsLabel:SetText("Default starting crafts")

    ebGlobalStartingCrafts = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    ebGlobalStartingCrafts:SetSize(90, 26)
    ebGlobalStartingCrafts:SetAutoFocus(false)
    ebGlobalStartingCrafts:SetNumeric(true)
    ebGlobalStartingCrafts:SetMaxLetters(7)
    ebGlobalStartingCrafts:SetText(tostring(
        (GAM.State and GAM.State.GetGlobalStartingCrafts
            and GAM.State.GetGlobalStartingCrafts()) or GAM.C.DEFAULT_STARTING_CRAFTS))

    local startingCraftsHelp = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    startingCraftsHelp:SetText(string.format(
        "Used by strategies without an override (%s-%s). Per-strategy values still take priority.",
        FmtQty(GAM.C.MIN_STARTING_CRAFTS), FmtQty(GAM.C.MAX_STARTING_CRAFTS)))
    startingCraftsHelp:SetTextColor(0.68, 0.68, 0.72)
    AddRow(content, startingCraftsLabel, ebGlobalStartingCrafts, startingCraftsHelp, 90)

    local function NormalizeGlobalStartingCraftsBox()
        local value, err = GAM.State.NormalizeStartingCrafts(ebGlobalStartingCrafts:GetText())
        if not value then
            value = GAM.State.GetGlobalStartingCrafts()
            if err then
                GAM.Log.Warn("Invalid global starting crafts in Settings: %s", tostring(err))
            end
        end
        ebGlobalStartingCrafts:SetText(tostring(value))
        ebGlobalStartingCrafts:ClearFocus()
        return value
    end
    ebGlobalStartingCrafts:SetScript("OnEnterPressed", NormalizeGlobalStartingCraftsBox)
    ebGlobalStartingCrafts:SetScript("OnEditFocusLost", NormalizeGlobalStartingCraftsBox)
    ebGlobalStartingCrafts:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Default Starting Crafts", 1, 1, 1)
        GameTooltip:AddLine(
            "Sets the initial craft count for every strategy that does not have its own saved value.",
            1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    ebGlobalStartingCrafts:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local modeLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modeLabel:SetText(L["OPT_MASS_CRAFT_MODEL"])

    local modeTexts = {
        exhaust_materials = "Reinvest Resourcefulness",
    }
    local modeCurrent = "exhaust_materials"
    local modeBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    modeBtn:SetSize(180, 28)
    modeBtn:SetText(modeTexts[modeCurrent])
    modeBtn:Disable()

    local modeHelp = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    modeHelp:SetText(L["OPT_MASS_CRAFT_MODEL_TIP"])
    modeHelp:SetTextColor(0.72, 0.72, 0.72, 1)
    AddRow(content, modeLabel, modeBtn, modeHelp, 180)

    -- Market depth is automatic; explain it instead of asking for a number.
    AddText(content, "Material costs use the Auction House listings for the exact quantity each "
        .. "strategy needs. Unusually cheap bait listings are ignored, and units the market does "
        .. "not list are priced at the highest listed price, so estimates err toward higher costs. "
        .. "Crafted items are valued at the lowest listing.")

    -- Shopping budget check: share of gold kept unspent.
    local function ClampReserve(value)
        local n = math.floor(tonumber(value) or GAM.C.DEFAULT_GOLD_RESERVE_PCT)
        return math.max(GAM.C.MIN_GOLD_RESERVE_PCT, math.min(GAM.C.MAX_GOLD_RESERVE_PCT, n))
    end
    local ebGoldReserve = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    ebGoldReserve:SetSize(90, 26)
    ebGoldReserve:SetAutoFocus(false)
    ebGoldReserve:SetNumeric(true)
    ebGoldReserve:SetMaxLetters(2)
    ebGoldReserve:SetText(tostring(ClampReserve(opts.goldReservePct)))
    local function NormalizeGoldReserve()
        local value = ClampReserve(ebGoldReserve:GetText())
        ebGoldReserve:SetText(tostring(value))
        ebGoldReserve:ClearFocus()
        return value
    end
    ebGoldReserve:SetScript("OnEnterPressed", NormalizeGoldReserve)
    ebGoldReserve:SetScript("OnEditFocusLost", NormalizeGoldReserve)
    AddRow(content, "Gold reserve (%)", ebGoldReserve, string.format(
        "Shopping warns when the queue's materials would leave less than this share of your gold, and suggests craft counts that fit (%d-%d%%).",
        GAM.C.MIN_GOLD_RESERVE_PCT, GAM.C.MAX_GOLD_RESERVE_PCT), 90)

    FinalizeContentLayout()
    content = pages.crafting.content
    MakeSectionHeader(content, "Manual stat fallbacks")

    local subHdr = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subHdr:SetJustifyH("LEFT")
    subHdr:SetWordWrap(true)
    subHdr:SetText(L["OPT_PROFILE_FALLBACK_TIP"])
    AddText(content, subHdr)

    local chMulti = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chMulti:SetText(L["V2_STAT_MULTI_LABEL"])
    local chRes = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chRes:SetText(L["V2_STAT_RES_LABEL"])

    local craftStatRows = {}

    local function MakeStatEditBox(tooltipTitle, tooltipBody, fallbackValue)
        local eb = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
        eb:SetSize(44, 22)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(6)
        eb:SetText(FormatStatPercentValue(fallbackValue))
        eb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltipTitle, 1, 1, 1)
            GameTooltip:AddLine(tooltipBody, 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return eb
    end

    -- multiKey=nil → no Multi% field (Milling/Prospecting/Crushing/Shattering have no Multicraft stat)
    local function MakeStatRow(def)
        local lbl = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetText(def.label)

        local row = {
            label = def.label,
            labelFrame = lbl,
            multiKey = def.multiKey,
            resKey = def.resKey,
            defaultMulti = def.defaultMulti,
            defaultRes = def.defaultRes,
            multiBox = nil,
            resBox = nil,
        }

        if row.multiKey then
            row.multiBox = MakeStatEditBox(
                GAM.L["TT_STAT_MULTI_TITLE"] or "Multicraft %",
                GAM.L["TT_STAT_MULTI_BODY"] or "Your Multicraft stat from the profession window (%). Higher values increase expected output quantity.",
                GetOptionValue(opts, row.multiKey, row.defaultMulti)
            )
            local function NormalizeMulti()
                NormalizeStatBox(
                    row.multiBox,
                    GetOptionValue(GetOpts(), row.multiKey, row.defaultMulti)
                )
            end
            row.multiBox:SetScript("OnEnterPressed", NormalizeMulti)
            row.multiBox:SetScript("OnEditFocusLost", NormalizeMulti)
        end

        row.resBox = MakeStatEditBox(
            GAM.L["TT_STAT_RES_TITLE"] or "Resourcefulness %",
            GAM.L["TT_STAT_RES_BODY"] or "Your Resourcefulness stat from the profession window (%). Higher values reduce average reagent consumption.",
            GetOptionValue(opts, row.resKey, row.defaultRes)
        )
        local function NormalizeRes()
            NormalizeStatBox(
                row.resBox,
                GetOptionValue(GetOpts(), row.resKey, row.defaultRes)
            )
        end
        row.resBox:SetScript("OnEnterPressed", NormalizeRes)
        row.resBox:SetScript("OnEditFocusLost", NormalizeRes)

        craftStatRows[#craftStatRows + 1] = row
    end

    MakeStatRow({
        label = "Inscription - Milling:",
        multiKey = nil,
        resKey = "inscMillingRes",
        defaultMulti = nil,
        defaultRes = GAM.C.DEFAULT_INSC_MILLING_RES,
    })
    MakeStatRow({
        label = "Inscription - Ink:",
        multiKey = "inscInkMulti",
        resKey = "inscInkRes",
        defaultMulti = GAM.C.DEFAULT_INSC_INK_MULTI,
        defaultRes = GAM.C.DEFAULT_INSC_INK_RES,
    })
    MakeStatRow({
        label = "Jewelcrafting - Prospect:",
        multiKey = nil,
        resKey = "jcProspectRes",
        defaultMulti = nil,
        defaultRes = GAM.C.DEFAULT_JC_PROSPECT_RES,
    })
    MakeStatRow({
        label = "Jewelcrafting - Crushing:",
        multiKey = nil,
        resKey = "jcCrushRes",
        defaultMulti = nil,
        defaultRes = GAM.C.DEFAULT_JC_CRUSH_RES,
    })
    MakeStatRow({
        label = "Jewelcrafting - Crafting:",
        multiKey = "jcCraftMulti",
        resKey = "jcCraftRes",
        defaultMulti = GAM.C.DEFAULT_JC_CRAFT_MULTI,
        defaultRes = GAM.C.DEFAULT_JC_CRAFT_RES,
    })
    MakeStatRow({
        label = "Enchanting - Shattering:",
        multiKey = nil,
        resKey = "enchShatterRes",
        defaultMulti = nil,
        defaultRes = GAM.C.DEFAULT_ENCH_SHATTER_RES,
    })
    MakeStatRow({
        label = "Enchanting - Crafting:",
        multiKey = "enchCraftMulti",
        resKey = "enchCraftRes",
        defaultMulti = GAM.C.DEFAULT_ENCH_CRAFT_MULTI,
        defaultRes = GAM.C.DEFAULT_ENCH_CRAFT_RES,
    })
    MakeStatRow({
        label = "Alchemy:",
        multiKey = "alchMulti",
        resKey = "alchRes",
        defaultMulti = GAM.C.DEFAULT_ALCH_MULTI,
        defaultRes = GAM.C.DEFAULT_ALCH_RES,
    })
    MakeStatRow({
        label = "Cooking:",
        multiKey = "cookMulti",
        resKey = "cookRes",
        defaultMulti = GAM.C.DEFAULT_COOK_MULTI,
        defaultRes = GAM.C.DEFAULT_COOK_RES,
    })
    MakeStatRow({
        label = "Tailoring:",
        multiKey = "tailMulti",
        resKey = "tailRes",
        defaultMulti = GAM.C.DEFAULT_TAIL_MULTI,
        defaultRes = GAM.C.DEFAULT_TAIL_RES,
    })
    MakeStatRow({
        label = "Blacksmithing:",
        multiKey = "bsMulti",
        resKey = "bsRes",
        defaultMulti = GAM.C.DEFAULT_BS_MULTI,
        defaultRes = GAM.C.DEFAULT_BS_RES,
    })
    MakeStatRow({
        label = "Leatherworking:",
        multiKey = "lwMulti",
        resKey = "lwRes",
        defaultMulti = GAM.C.DEFAULT_LW_MULTI,
        defaultRes = GAM.C.DEFAULT_LW_RES,
    })
    MakeStatRow({
        label = "Engineering - Recycling:",
        multiKey = nil,
        resKey = "engRecycleRes",
        defaultMulti = nil,
        defaultRes = GAM.C.DEFAULT_ENG_RECYCLE_RES,
    })
    MakeStatRow({
        label = "Engineering - Crafting:",
        multiKey = "engCraftMulti",
        resKey = "engCraftRes",
        defaultMulti = GAM.C.DEFAULT_ENG_CRAFT_MULTI,
        defaultRes = GAM.C.DEFAULT_ENG_CRAFT_RES,
    })

    local statTable = CreateFrame("Frame", nil, content)
    chMulti:SetParent(statTable)
    chRes:SetParent(statTable)
    for _, row in ipairs(craftStatRows) do
        row.labelFrame:SetParent(statTable)
        if row.multiBox then row.multiBox:SetParent(statTable) end
        row.resBox:SetParent(statTable)
        row.rule = statTable:CreateTexture(nil, "BACKGROUND")
        row.rule:SetColorTexture(1, 1, 1, 0.05)
    end
    AddCustom(content, statTable, function(width)
        local colWidth = math.min(104, width * 0.27)
        local multiX, resX = width - colWidth * 2, width - colWidth
        for i, header in ipairs({ chMulti, chRes }) do
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", statTable, "TOPLEFT", i == 1 and multiX or resX, 0)
            header:SetWidth(colWidth - 6)
            header:SetWordWrap(true)
        end
        local top = math.max(chMulti:GetStringHeight(), chRes:GetStringHeight()) + 12
        for _, row in ipairs(craftStatRows) do
            local label = row.labelFrame
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", statTable, "TOPLEFT", 0, -top - 5)
            label:SetWidth(math.max(40, multiX - 12))
            label:SetWordWrap(true)
            local height = math.max(36, label:GetStringHeight() + 14)
            for i = 1, 2 do
                local box
                if i == 1 then box = row.multiBox else box = row.resBox end
                if box then
                    box:ClearAllPoints()
                    box:SetPoint("TOPLEFT", statTable, "TOPLEFT", i == 1 and multiX or resX, -top)
                    box:SetSize(math.min(64, colWidth - 16), 26)
                end
            end
            row.rule:ClearAllPoints()
            row.rule:SetPoint("TOPLEFT", statTable, "TOPLEFT", 0, -top - height + 4)
            row.rule:SetSize(width, 1)
            top = top + height
        end
        return top
    end)

    local btnResetStatFallbacks = MakeButton(content, "Reset Fallback Defaults", 160)
    AddRow(content, "Restore fallback values", btnResetStatFallbacks,
        "Resets the fields on this page to addon defaults.", 170)
    btnResetStatFallbacks:SetScript("OnClick", function()
        for _, row in ipairs(craftStatRows) do
            if row.multiBox and row.defaultMulti ~= nil then
                row.multiBox:SetText(FormatStatPercentValue(row.defaultMulti))
            end
            if row.resBox and row.defaultRes ~= nil then
                row.resBox:SetText(FormatStatPercentValue(row.defaultRes))
            end
        end
    end)

    -- ── Profession node ranks ──────────────────────────────────────────────
    FinalizeContentLayout()
    content = pages.nodes.content
    MakeSectionHeader(content, "Specialization ranks")
    local professionNodeRows = {}
    local professionNodeSections = {}
    local professionNodeOrder = (GAM.CraftingStats
        and GAM.CraftingStats.GetSupportedNodeProfessions
        and GAM.CraftingStats.GetSupportedNodeProfessions()) or { "Engineering" }
    if #professionNodeOrder == 0 then
        professionNodeOrder = { "Engineering" }
    end
    local currentNodeProfessionIndex = 1
    local RefreshProfessionNodeRows

    local nodeStatus = NewText(content, L["OPT_PROFESSION_NODES_TIP"], "GameFontHighlightSmall")
    AddText(content, nodeStatus)

    -- Keep the selector outside the scroll child, visible even in a long tree.
    local selectorBar = CreateFrame("Frame", nil, pages.nodes.frame)
    selectorBar:SetPoint("TOPLEFT", 0, 0)
    selectorBar:SetPoint("TOPRIGHT", -24, 0)
    selectorBar:SetHeight(44)
    pages.nodes.scroll:SetPoint("TOPLEFT", pages.nodes.frame, "TOPLEFT", 0, -48)
    local selectorLabel = NewText(selectorBar, "Profession", "GameFontNormal")
    selectorLabel:SetPoint("LEFT", 8, 0)

    local function ChooseProfession(index)
        if currentNodeProfessionIndex ~= index then
            currentNodeProfessionIndex = index
            pages.nodes.scroll:SetVerticalScroll(0)
        end
        if RefreshProfessionNodeRows then RefreshProfessionNodeRows(true) end
    end
    local UpdateProfessionSelector
    local ok, professionSelector = pcall(CreateFrame, "DropdownButton", nil,
        selectorBar, "WowStyle1DropdownTemplate")
    if ok and professionSelector and professionSelector.SetupMenu then
        professionSelector:SetPoint("LEFT", selectorBar, "LEFT", 102, 0)
        professionSelector:SetPoint("RIGHT", selectorBar, "RIGHT", -8, 0)
        professionSelector:SetHeight(30)
        professionSelector:SetupMenu(function(_, root)
            for i, profession in ipairs(professionNodeOrder) do
                local index = i
                root:CreateRadio(profession, function() return currentNodeProfessionIndex == index end,
                    function() ChooseProfession(index) end)
            end
        end)
        UpdateProfessionSelector = function()
            professionSelector:SetDefaultText(professionNodeOrder[currentNodeProfessionIndex])
        end
    else
        if ok and professionSelector then professionSelector:Hide() end
        -- Older clients use the native legacy menu, also outside the scroll child.
        professionSelector = CreateFrame("Frame", NextWidgetName("ProfessionMenu"),
            selectorBar, "UIDropDownMenuTemplate")
        professionSelector:SetPoint("LEFT", selectorBar, "LEFT", 86, -2)
        UIDropDownMenu_Initialize(professionSelector, function()
            for i, profession in ipairs(professionNodeOrder) do
                local index = i
                local info = UIDropDownMenu_CreateInfo()
                info.text = profession
                info.checked = currentNodeProfessionIndex == index
                info.func = function() ChooseProfession(index) end
                UIDropDownMenu_AddButton(info)
            end
        end)
        UpdateProfessionSelector = function()
            UIDropDownMenu_SetText(professionSelector, professionNodeOrder[currentNodeProfessionIndex])
            UIDropDownMenu_SetWidth(professionSelector, math.max(120, selectorBar:GetWidth() - 134))
        end
        selectorBar:HookScript("OnSizeChanged", UpdateProfessionSelector)
        selectorBar:HookScript("OnHide", function()
            if CloseDropDownMenus then CloseDropDownMenus() end
        end)
    end
    UpdateProfessionSelector()

    local nodeRowsFrame = CreateFrame("Frame", nil, content)
    nodeRowsFrame:SetSize(480, 1)
    local activeNodeHeight = 1
    AddCustom(content, nodeRowsFrame, function(width)
        for _, section in ipairs(professionNodeSections) do
            section.frame:SetWidth(width)
            for _, group in ipairs(section.groups) do group.header:SetWidth(width) end
            for _, row in ipairs(section.rows) do
                row.label:SetWidth(math.max(40, width - 182))
                row.box:ClearAllPoints()
                row.box:SetPoint("LEFT", row.label, "LEFT", math.max(52, width - 170), 0)
                row.note:SetWidth(76)
            end
            local top = 0
            if #section.rows == 0 then
                section.empty:SetWidth(width)
                top = section.empty:GetStringHeight() + 24
            end
            for _, group in ipairs(section.groups) do
                group.header:ClearAllPoints()
                group.header:SetPoint("TOPLEFT", section.frame, "TOPLEFT", 0, -top)
                top = top + group.header:GetStringHeight() + 12
                for _, row in ipairs(group.rows) do
                    row.label:ClearAllPoints()
                    row.label:SetPoint("TOPLEFT", section.frame, "TOPLEFT", 0, -top - 4)
                    top = top + math.max(34, row.label:GetStringHeight() + 12)
                end
                top = top + 10
            end
            local layout = LayoutButtonsTop(section.frame, section.buttons, -top, {
                left = 0, right = width, gap = 8, rowGap = 6, align = "left", height = 28,
            })
            section.height = top + layout.usedHeight + 8
            section.frame:SetHeight(section.height)
            if section.profession == professionNodeOrder[currentNodeProfessionIndex] then
                activeNodeHeight = section.height
            end
        end
        return activeNodeHeight
    end)

    local function GetNodeImpactText(row)
        if NodeDisplay and NodeDisplay.BuildImpactText then
            return NodeDisplay.BuildImpactText(row)
        end
        return "Used by this profession's pricing profile."
    end

    local function ShowNodeTooltip(owner, rowState)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(rowState.name or "Profession Node", 1, 0.82, 0)
        if rowState.description then
            GameTooltip:AddLine(rowState.description, 1, 1, 1, true)
        end
        if rowState.impactText then
            GameTooltip:AddLine(rowState.impactText, 0.55, 0.85, 1, true)
        end
        GameTooltip:AddLine(string.format("Rank 0-%s. Enter a rank only to override the captured value.",
            tostring(rowState.maxRank or 0)), 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end

    local function MakeNodeRankBox(parent, rowState)
        local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        eb:SetSize(40, 26)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(3)
        eb:SetNumeric(true)
        eb:SetScript("OnEnterPressed", function(self)
            local maxRank = tonumber(rowState.maxRank) or 0
            local value = math.max(0, math.min(maxRank, math.floor(tonumber(self:GetText()) or 0)))
            self:SetText(tostring(value))
            self:ClearFocus()
        end)
        eb:SetScript("OnEditFocusLost", function(self)
            local maxRank = tonumber(rowState.maxRank) or 0
            local value = math.max(0, math.min(maxRank, math.floor(tonumber(self:GetText()) or 0)))
            self:SetText(tostring(value))
        end)
        eb:SetScript("OnTextChanged", function()
            if not rowState.refreshing then
                rowState.dirty = true
            end
        end)
        eb:SetScript("OnEnter", function(self)
            ShowNodeTooltip(self, rowState)
        end)
        eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return eb
    end

    local function AddNodeGroupHeader(parent, text)
        local hdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdr:SetJustifyH("LEFT")
        hdr:SetText(text)
        return hdr
    end

    local function AddNodeRow(parent, profession, row)
        local rowState = {
            profession = profession,
            nodeID = row.nodeID,
            name = row.name,
            description = row.description,
            nameSource = row.nameSource,
            maxRank = row.maxRank,
            stats = row.stats,
            impactText = GetNodeImpactText(row),
            dirty = false,
        }
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetWordWrap(true)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(row.name or ("Node " .. tostring(row.nodeID)))
        local hover = CreateFrame("Frame", nil, parent)
        hover:SetAllPoints(lbl)
        hover:EnableMouse(true)
        hover:SetScript("OnEnter", function(self) ShowNodeTooltip(self, rowState) end)
        hover:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local eb = MakeNodeRankBox(parent, rowState)

        local maxText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        maxText:SetPoint("LEFT", eb, "RIGHT", 4, 0)
        maxText:SetText("/ " .. tostring(row.maxRank or 0))
        maxText:SetTextColor(0.55, 0.55, 0.55)

        local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        note:SetPoint("LEFT", maxText, "RIGHT", 10, 0)
        note:SetWidth(115)
        note:SetJustifyH("LEFT")
        note:SetTextColor(0.55, 0.55, 0.55)

        rowState.box = eb
        rowState.label = lbl
        rowState.maxText = maxText
        rowState.note = note
        rowState.hover = hover
        return rowState
    end

    local function BuildNodeSection(profession)
        local section = {
            profession = profession,
            rows = {},
            groups = {},
            rowsByID = {},
            headers = {},
        }
        local frame = CreateFrame("Frame", nil, nodeRowsFrame)
        frame:SetPoint("TOPLEFT", nodeRowsFrame, "TOPLEFT", 0, 0)
        frame:SetSize(520, 1)
        frame:Hide()
        section.frame = frame

        section.empty = NewText(frame,
            "No specialization nodes are available for " .. profession ..
            ". Open that profession on its crafter, then return here. " ..
            "If this stays empty, the addon's profession data may need an update.",
            "GameFontHighlight")
        section.empty:SetPoint("TOPLEFT", 0, 0)
        section.empty:SetTextColor(0.72, 0.72, 0.76)

        local btnResetCaptured = MakeButton(frame, "Use Captured", 120)
        btnResetCaptured:SetScript("OnClick", function()
            if GAM.CraftingStats and GAM.CraftingStats.ResetProfessionNodesToCaptured then
                GAM.CraftingStats.ResetProfessionNodesToCaptured(profession)
            end
            if panel and panel.refresh then panel.refresh() end
        end)

        local btnResetDefaults = MakeButton(frame, "Use Defaults", 115)
        btnResetDefaults:SetScript("OnClick", function()
            if GAM.CraftingStats and GAM.CraftingStats.ResetProfessionNodesToDefaults then
                GAM.CraftingStats.ResetProfessionNodesToDefaults(profession)
            end
            if panel and panel.refresh then panel.refresh() end
        end)
        section.buttons = { btnResetCaptured, btnResetDefaults }
        section.height = 1
        frame:SetHeight(section.height)
        professionNodeSections[#professionNodeSections + 1] = section
        return section.height
    end

    for _, profession in ipairs(professionNodeOrder) do BuildNodeSection(profession) end

    -- Reconcile the provider's current structure on every refresh. Reuse rank
    -- boxes by node ID so captures can add/reorder nodes without losing drafts.
    local function SyncNodeSection(section, data, preserveDirty)
        for _, row in pairs(section.rowsByID) do
            if not preserveDirty then row.dirty = false end
            row.label:Hide(); row.box:Hide(); row.maxText:Hide(); row.note:Hide(); row.hover:Hide()
        end
        for _, header in ipairs(section.headers) do header:Hide() end
        section.rows, section.groups = {}, {}
        local seen = {}
        for groupIndex, group in ipairs((data and data.groups) or {}) do
            local header = section.headers[groupIndex]
            if not header then
                header = AddNodeGroupHeader(section.frame, group.label or "Nodes")
                section.headers[groupIndex] = header
            end
            header:SetText(group.label or "Nodes")
            local groupState = { header = header, rootNodeID = group.rootNodeID, rows = {} }
            for _, rowData in ipairs(group.rows or {}) do
                local id = rowData.nodeID
                if id ~= nil and not seen[id] then
                    seen[id] = true
                    local row = section.rowsByID[id]
                    if not row then
                        row = AddNodeRow(section.frame, section.profession, rowData)
                        section.rowsByID[id] = row
                    end
                    row.label:Show(); row.box:Show(); row.maxText:Show(); row.note:Show(); row.hover:Show()
                    groupState.rows[#groupState.rows + 1] = row
                    section.rows[#section.rows + 1] = row
                    professionNodeRows[#professionNodeRows + 1] = row
                end
            end
            if #groupState.rows > 0 then
                header:Show()
                section.groups[#section.groups + 1] = groupState
            end
        end
        section.empty:SetShown(#section.rows == 0)
        for _, btn in ipairs(section.buttons) do btn:SetEnabled(#section.rows > 0) end
    end

    local function SelectNodeProfession(index)
        currentNodeProfessionIndex = index
        local currentProfession = professionNodeOrder[currentNodeProfessionIndex] or professionNodeOrder[1]
        UpdateProfessionSelector()
        for _, section in ipairs(professionNodeSections) do
            section.frame:SetShown(section.profession == currentProfession)
        end
        LayoutPage(pages.nodes)
        return currentProfession
    end

    RefreshProfessionNodeRows = function(preserveDirty)
        local selectedProfession = SelectNodeProfession(currentNodeProfessionIndex)
        local selectedData = nil
        local data = GAM.CraftingStats
            and GAM.CraftingStats.GetProfessionNodeRows
        wipe(professionNodeRows)
        local selectedRowCount = 0
        for _, section in ipairs(professionNodeSections) do
            local sectionData = data and data(section.profession) or nil
            SyncNodeSection(section, sectionData, preserveDirty)
            if section.profession == selectedProfession then
                selectedData = sectionData
                selectedRowCount = #section.rows
            end
            local byID = {}
            local groupsByRootID = {}
            if type(sectionData) == "table" then
                for _, group in ipairs(sectionData.groups or {}) do
                    if group.rootNodeID then
                        groupsByRootID[group.rootNodeID] = group
                    end
                    for _, row in ipairs(group.rows or {}) do
                        byID[row.nodeID] = row
                    end
                end
            end
            for _, groupState in ipairs(section.groups or {}) do
                local group = groupsByRootID[groupState.rootNodeID]
                if group and groupState.header then
                    groupState.header:SetText(group.label or "Nodes")
                end
            end
            for _, rowState in ipairs(section.rows) do
                local row = byID[rowState.nodeID] or {}
                rowState.refreshing = true
                rowState.name = row.name or rowState.name
                rowState.description = row.description
                rowState.nameSource = row.nameSource or rowState.nameSource
                rowState.maxRank = row.maxRank or rowState.maxRank or 0
                rowState.manualRank = row.manualRank
                rowState.capturedRank = row.capturedRank
                rowState.stats = row.stats or rowState.stats
                rowState.impactText = GetNodeImpactText(row)
                local keepDraft = preserveDirty and rowState.dirty
                if rowState.box and not keepDraft then
                    rowState.box:SetText(tostring(row.rank or 0))
                end
                if rowState.label then
                    rowState.label:SetText(rowState.name or ("Node " .. tostring(rowState.nodeID)))
                end
                if rowState.maxText then
                    rowState.maxText:SetText("/ " .. tostring(rowState.maxRank))
                end
                if rowState.note and not keepDraft then
                    local noteText = "Default"
                    if row.manualRank ~= nil then
                        noteText = "Override"
                    elseif row.capturedRank ~= nil then
                        noteText = "Captured"
                    end
                    rowState.note:SetText(noteText)
                end
                if not keepDraft then
                    rowState.dirty = false
                end
                rowState.refreshing = false
            end
        end

        if selectedRowCount == 0 then
            nodeStatus:SetText("No node data returned for " .. tostring(selectedProfession) .. ".")
        elseif selectedData and selectedData.capturedAt then
            nodeStatus:SetText(string.format(L["OPT_NODES_CAPTURED"], tostring(selectedProfession)))
        else
            nodeStatus:SetText(string.format(L["OPT_NODES_DEFAULT"], tostring(selectedProfession)))
        end
        LayoutPage(pages.nodes)
    end

    RefreshProfessionNodeRows()
    pages.nodes.frame:HookScript("OnShow", function() RefreshProfessionNodeRows(true) end)

    -- ── Actions ────────────────────────────────────────────────────────────
    FinalizeContentLayout()
    content = pages.tools.content
    MakeSectionHeader(content, L["SETTINGS_SECTION_ACTIONS"])

    -- Maintenance actions use the same labeled rows as preferences.
    local btnReload = MakeButton(content, L["BTN_RELOAD_DATA"], 120)
    btnReload:SetScript("OnClick", function()
        GAM.Importer.Init()
        GAM.Log.Info("Data reloaded.")
        print("|cffff8800[GAM]|r " .. L["MSG_DATA_RELOADED"])
    end)

    local btnClear = MakeButton(content, L["BTN_CLEAR_CACHE"], 120)
    btnClear:SetScript("OnClick", function()
        ClearPriceCache()
        GAM.Log.Info("Price cache cleared.")
        print("|cffff8800[GAM]|r " .. L["MSG_CACHE_CLEARED"])
    end)

    local btnLog = MakeButton(content, L["BTN_OPEN_LOG"], 100)
    btnLog:SetScript("OnClick", function()
        if GAM.UI and GAM.UI.DebugLog then
            GAM.UI.DebugLog.Show()
        end
    end)

    AddRow(content, "Strategy data", btnReload, "Reload the bundled strategy data.", 150)
    AddRow(content, "Price cache", btnClear, "Clear saved prices, then scan again for fresh results.", 150)
    AddRow(content, "Diagnostics", btnLog, "Open the Debug Log to filter messages and run troubleshooting checks.", 150)
    -- ── Credits & Thanks ───────────────────────────────────────────────────
    FinalizeContentLayout()
    content = pages.about.content
    local about = CreateFrame("Frame", nil, content)
    local aboutTitle = NewText(about, L["SETTINGS_NAME"], "GameFontNormalLarge")
    aboutTitle:SetTextColor(0.95, 0.95, 0.97)
    local aboutIntro = NewText(about, "Crafting strategy, pricing, and profession insights.", "GameFontHighlight")
    aboutIntro:SetTextColor(0.72, 0.72, 0.76)
    local creditsTitle = NewText(about, L["SETTINGS_SECTION_CREDITS"], "GameFontNormal")
    local contributors = {}
    for _, def in ipairs({
        { "Eloncs", "The game economy spreadsheet that powers every strategy in this addon." },
        { "Brrerker", "Creator of arp_tracker, an invaluable reference for Auction House scanning patterns." },
        { "CraftSim", "Crafting simulation, optional integration, and MIT-licensed static specialization data references." },
    }) do
        local name = NewText(about, def[1], "GameFontNormalLarge")
        local description = NewText(about, def[2], "GameFontHighlight")
        description:SetTextColor(0.82, 0.82, 0.85)
        local rule = about:CreateTexture(nil, "BACKGROUND")
        rule:SetColorTexture(1, 1, 1, 0.10)
        contributors[#contributors + 1] = { name = name, description = description, rule = rule }
    end
    local thanks = NewText(about,
        "And to the wider WoW addon community on Wago, CurseForge, and GitHub: thank you. " ..
        "This addon stands on your shoulders.", "GameFontHighlight")
    thanks:SetTextColor(0.72, 0.72, 0.76)
    AddCustom(content, about, function(width)
        for _, fs in ipairs({ aboutTitle, aboutIntro, creditsTitle, thanks }) do fs:SetWidth(width) end
        aboutTitle:ClearAllPoints()
        aboutTitle:SetPoint("TOPLEFT", 0, 0)
        aboutIntro:ClearAllPoints()
        aboutIntro:SetPoint("TOPLEFT", aboutTitle, "BOTTOMLEFT", 0, -10)
        local top = aboutTitle:GetStringHeight() + aboutIntro:GetStringHeight() + 42
        creditsTitle:ClearAllPoints()
        creditsTitle:SetPoint("TOPLEFT", about, "TOPLEFT", 0, -top)
        top = top + creditsTitle:GetStringHeight() + 24
        local natural = top + thanks:GetStringHeight() + 24
        for _, entry in ipairs(contributors) do
            entry.name:SetWidth(width)
            entry.description:SetWidth(width)
            natural = natural + entry.name:GetStringHeight() + entry.description:GetStringHeight() + 38
        end
        local height = math.max(natural, pages.about.scroll:GetHeight() - 48)
        local extraGap = (height - natural) / #contributors
        for _, entry in ipairs(contributors) do
            entry.name:ClearAllPoints()
            entry.name:SetPoint("TOPLEFT", about, "TOPLEFT", 0, -top)
            entry.description:ClearAllPoints()
            entry.description:SetPoint("TOPLEFT", entry.name, "BOTTOMLEFT", 0, -8)
            top = top + entry.name:GetStringHeight() + entry.description:GetStringHeight() + 24
            entry.rule:ClearAllPoints()
            entry.rule:SetPoint("TOPLEFT", about, "TOPLEFT", 0, -top)
            entry.rule:SetSize(width, 1)
            top = top + 14 + extraGap
        end
        thanks:ClearAllPoints()
        thanks:SetPoint("TOPLEFT", about, "TOPLEFT", 0, -top - 12)
        return height
    end)

    FinalizeContentLayout()

    -- Fixed footer for the standalone fallback; native Settings owns its footer.
    local footer = CreateFrame("Frame", nil, panel)
    footer:SetPoint("BOTTOMLEFT", pageHost, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", pageHost, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(38)
    footer:Hide()
    local applyBtn = MakeButton(footer, L["BTN_APPLY_CLOSE"], 150)
    applyBtn:SetPoint("RIGHT", 0, 0)
    applyBtn:SetWidth(MeasureButtonWidth(footer, applyBtn:GetText(), 150, 260, 24))
    panel._setStandalone = function()
        footer:Show()
        shell.SetBottomInset(46)
    end
    SelectSettingsSection("general")

    -- ── Apply logic ────────────────────────────────────────────────────────
    local function ApplySettings()
        local currentOpts = GetOpts()
        local prevStartingCrafts = GAM.State.GetGlobalStartingCrafts()
        currentOpts.scanDelay = slScanDelay:GetValue()
        currentOpts.debugVerbosity = slVerbosity:GetValue()
        currentOpts.minimapHidden = not cbMinimap:GetChecked()
        currentOpts.rememberAHWindowState = cbRememberAHState:GetChecked()
        currentOpts.rankPolicy = ddRank.GetValue() or "lowest"
        currentOpts.v2PricingMode = "exhaust_materials"

        for _, row in ipairs(craftStatRows) do
            if row.multiKey and row.multiBox then
                currentOpts[row.multiKey] = NormalizeStatBox(
                    row.multiBox,
                    GetOptionValue(currentOpts, row.multiKey, row.defaultMulti)
                )
            end
            if row.resKey and row.resBox then
                currentOpts[row.resKey] = NormalizeStatBox(
                    row.resBox,
                    GetOptionValue(currentOpts, row.resKey, row.defaultRes)
                )
            end
        end

        if GAM.CraftingStats and GAM.CraftingStats.SetManualNodeRank then
            for _, row in ipairs(professionNodeRows) do
                if row.dirty or row.manualRank ~= nil then
                    local maxRank = tonumber(row.maxRank) or 0
                    local rank = math.max(0, math.min(maxRank,
                        math.floor(tonumber(row.box and row.box:GetText()) or 0)))
                    GAM.CraftingStats.SetManualNodeRank(row.profession, row.nodeID, rank)
                end
            end
        end

        currentOpts.uiScale = slScale:GetValue()
        currentOpts.ahCut = GAM.C.AH_CUT
        ApplyScaleToFrames(currentOpts.uiScale)

        local globalStartingCrafts = NormalizeGlobalStartingCraftsBox()
        GAM.State.SetGlobalStartingCrafts(globalStartingCrafts)

        currentOpts.goldReservePct = NormalizeGoldReserve()

        GAM.Log.SetLevel(currentOpts.debugVerbosity)
        if GAM.AHScan then
            GAM.AHScan.SetScanDelay(currentOpts.scanDelay)
        end
        GAM.Minimap.SetShown(not currentOpts.minimapHidden)

        if globalStartingCrafts ~= prevStartingCrafts then
            GAM.Log.Info("Global starting crafts changed: %d -> %d",
                prevStartingCrafts, globalStartingCrafts)
        end

        GAM.Log.Info("V2 pricing mode: %s", tostring(currentOpts.v2PricingMode or NormalizeV2PricingMode(nil)))

        if GAM.UI and GAM.UI.MainWindow and GAM.UI.MainWindow.Refresh then
            GAM.UI.MainWindow.Refresh()
        end
        if GAM.UI and GAM.UI.CraftPlanWindow and GAM.UI.CraftPlanWindow.Refresh then
            GAM.UI.CraftPlanWindow.Refresh()
        end
        if GAM.UI and GAM.UI.StrategyDetail and
            GAM.UI.StrategyDetail.IsShown and GAM.UI.StrategyDetail.Refresh and
            GAM.UI.StrategyDetail.IsShown() then
            GAM.UI.StrategyDetail.Refresh()
        end

        GAM.Log.Info("Settings saved.")
    end

    local function RefreshControlsFromOptions(o)
        if not o then return end
        RefreshAppearanceControls()
        slScanDelay:SetValue(GetOptionValue(o, "scanDelay", GAM.C.DEFAULT_SCAN_DELAY))
        slVerbosity:SetValue(GetOptionValue(o, "debugVerbosity", GAM.C.DEFAULT_VERBOSITY))
        cbMinimap:SetChecked(not o.minimapHidden)
        cbRememberAHState:SetChecked(o.rememberAHWindowState ~= false)
        slScale:SetValue(GetOptionValue(o, "uiScale", GAM.C.DEFAULT_UI_SCALE))
        ebGoldReserve:SetText(tostring(ClampReserve(o.goldReservePct)))
        ebGlobalStartingCrafts:SetText(tostring(
            (GAM.State and GAM.State.GetGlobalStartingCrafts
                and GAM.State.GetGlobalStartingCrafts()) or GAM.C.DEFAULT_STARTING_CRAFTS))
        rankCurrent = rankTexts[o.rankPolicy] and o.rankPolicy or "lowest"
        rankBtn:SetText(rankTexts[rankCurrent])
        modeCurrent = "exhaust_materials"
        modeBtn:SetText(modeTexts[modeCurrent])
        for _, row in ipairs(craftStatRows) do
            if row.multiBox and row.multiKey then
                row.multiBox:SetText(FormatStatPercentValue(
                    GetOptionValue(o, row.multiKey, row.defaultMulti)
                ))
            end
            if row.resBox and row.resKey then
                row.resBox:SetText(FormatStatPercentValue(
                    GetOptionValue(o, row.resKey, row.defaultRes)
                ))
            end
        end
        RefreshProfessionNodeRows()
    end

    -- Re-sync controls from opts whenever the panel is shown
    -- (covers changes made via the V2 left panel since settings was last opened)
    panel:SetScript("OnShow", function()
        RefreshControlsFromOptions(GetOpts())
        SelectSettingsSection(shell.selected)
    end)

    -- Blizzard Settings ok/cancel callbacks
    panel.name   = L["SETTINGS_NAME"]
    panel.okay = ApplySettings
    panel.cancel = function()
        RefreshControlsFromOptions(GetOpts())
    end
    panel.refresh = function()
        RefreshControlsFromOptions(GetOpts())
    end
    panel._refreshProfessionNodes = function()
        RefreshProfessionNodeRows(true)
    end
    panel._refreshGlobalStartingCrafts = function()
        ebGlobalStartingCrafts:SetText(tostring(GAM.State.GetGlobalStartingCrafts()))
    end
    panel.OnCommit = panel.okay
    panel.OnRefresh = panel.refresh
    panel.OnDefault = function() end
    panel.default = panel.OnDefault

    -- Closing discards drafts. Only the explicit apply action commits them.
    panel:SetScript("OnHide", function()
        if not nativeMode then
            RefreshControlsFromOptions(GetOpts())
        end
    end)

    applyBtn:SetScript("OnClick", function()
        ApplySettings()
        SettingsMod.Hide()
    end)
    local cancelBtn = MakeButton(footer, CANCEL or "Cancel", 90)
    cancelBtn:SetPoint("RIGHT", applyBtn, "LEFT", -8, 0)
    cancelBtn:SetScript("OnClick", function() SettingsMod.Hide() end)

    -- Store reference so we can show/hide the apply button after registration attempt
    panel._applyBtn = applyBtn

    return panel
end

-- ===== Public API =====
function SettingsMod.Init()
    if wrapper then
        RegisterSettingsCategory()
        return
    end
    local p = BuildPanel()
    nativeMode = false
    category = nil
    categoryID = nil

    if not nodeCaptureUnsubscribe
            and GAM.CraftingStats
            and GAM.CraftingStats.AddProfessionNodeCaptureListener then
        nodeCaptureUnsubscribe = GAM.CraftingStats.AddProfessionNodeCaptureListener(function()
            if panel and panel:IsShown() and panel._refreshProfessionNodes then
                panel._refreshProfessionNodes()
            end
        end)
    end

    -- Use the standalone host consistently. Registering this anchored panel as
    -- a 12.1 canvas can show only its child navigation over the game world.
    if not nativeMode then
        wrapper = CreateFrame("Frame", GAM.RuntimeName("GAMSettingsWrapper"), UIParent, "BackdropTemplate")
        wrapper:SetSize(800, 640)
        wrapper:SetPoint("CENTER", UIParent, "CENTER")
        wrapper:SetMovable(true)
        wrapper:EnableMouse(true)
        wrapper:SetFrameStrata("DIALOG")
        wrapper:SetToplevel(true)
        wrapper:RegisterForDrag("LeftButton")
        wrapper:SetScript("OnDragStart", wrapper.StartMoving)
        wrapper:SetScript("OnDragStop",  wrapper.StopMovingOrSizing)
        wrapper:SetBackdrop((Common and Common.THIN_BACKDROP) or {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = true, tileSize = 8, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        wrapper:SetBackdropColor(0.055, 0.055, 0.062, 1)
        wrapper:SetBackdropBorderColor(0.48, 0.40, 0.16, 0.95)
        local wbg = wrapper:CreateTexture(nil, "BACKGROUND")
        wbg:SetAllPoints()
        wbg:SetColorTexture(0.055, 0.055, 0.062, 1)
        wrapper._gamBackground = wbg
        wrapper._gamIsSettingsFrame = true
        wrapper:Hide()
        WindowManager.Register(wrapper, "dialog")

        local wTitle = wrapper:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        wTitle:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 18, -14)
        wTitle:SetText(GAM.L["SETTINGS_NAME"])
        wTitle:SetTextColor(GOLD_R, GOLD_G, GOLD_B)

        local wClose = CreateFrame("Button", nil, wrapper, "UIPanelCloseButton")
        wClose:SetPoint("TOPRIGHT", wrapper, "TOPRIGHT", -4, -4)
        wClose:SetScript("OnClick", function() wrapper:Hide() end)

        -- Parent the content panel inside the wrapper
        p:SetParent(wrapper)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 14, -40)
        p:SetPoint("BOTTOMRIGHT", wrapper, "BOTTOMRIGHT", -14, 14)
        wrapper:HookScript("OnShow", function() p:Show() end)
        p:Show()

        if p._setStandalone then p._setStandalone() end
    end

    -- Register a separate, stable canvas so GAM remains discoverable in
    -- Blizzard's AddOns list. The complex settings panel stays in our host.
    RegisterSettingsCategory()
end

local function PresentStandaloneSettings()
    if not (wrapper and panel) then
        return false
    end

    -- The Blizzard settings canvas may retain or restore its former parent.
    -- Repair the standalone relationship whenever this window is presented.
    panel:SetParent(wrapper)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 14, -40)
    panel:SetPoint("BOTTOMRIGHT", wrapper, "BOTTOMRIGHT", -14, 14)
    wrapper:SetAlpha(1)
    wrapper:SetFrameStrata("DIALOG")
    wrapper:SetToplevel(true)
    if wrapper._gamBackground then wrapper._gamBackground:Show() end
    wrapper:Show()
    panel:Show()
    WindowManager.Present(wrapper, "dialog")
    return true
end

-- Toggle standalone panel — always works regardless of nativeMode.
function SettingsMod.Toggle()
    if nativeMode then
        SettingsMod.OpenPanel()
        return
    end
    if wrapper then
        if wrapper:IsShown() then
            wrapper:Hide()
        else
            PresentStandaloneSettings()
        end
    elseif panel then
        if panel:IsShown() then panel:Hide() else panel:Show() end
    end
end

function SettingsMod.Show()
    if nativeMode then
        SettingsMod.OpenPanel()
        return
    end
    if wrapper then
        PresentStandaloneSettings()
    elseif panel then
        panel:Show()
    end
end

function SettingsMod.Hide()
    if wrapper then wrapper:Hide() end
    if panel   then panel:Hide() end
end

function SettingsMod.Refresh()
    if panel and panel._refreshGlobalStartingCrafts then
        panel._refreshGlobalStartingCrafts()
    end
end

function SettingsMod.ShowStandalone()
    return PresentStandaloneSettings()
end

-- OpenPanel: open the Blizzard Interface > AddOns panel to our category.
-- Falls back to standalone wrapper/panel if the Blizzard API is unavailable or errors.
function SettingsMod.OpenPanel()
    if nativeMode then
        -- Retail's current Settings API expects the registered category ID.
        -- Prefer it over the older C_SettingsUtil path so right-clicking the
        -- minimap button lands on GAM's page instead of the generic AddOns list.
        if categoryID and BlizzardSettingsAPI and BlizzardSettingsAPI.OpenToCategory then
            local ok, err = pcall(BlizzardSettingsAPI.OpenToCategory, categoryID)
            if ok then return end
            LogWarn("Settings.OpenToCategory failed for categoryID=%s: %s",
                tostring(categoryID), tostring(err))
        end

        if categoryID and C_SettingsUtil and C_SettingsUtil.OpenSettingsPanel then
            local ok, err = pcall(C_SettingsUtil.OpenSettingsPanel, categoryID)
            if ok then return end
            LogWarn("C_SettingsUtil.OpenSettingsPanel failed for categoryID=%s: %s",
                tostring(categoryID), tostring(err))
        end

        -- Legacy compatibility: some clients accept the category object.
        if category and BlizzardSettingsAPI and BlizzardSettingsAPI.OpenToCategory then
            local ok, err = pcall(BlizzardSettingsAPI.OpenToCategory, category)
            if ok then return end
            LogWarn("Settings.OpenToCategory failed for category object: %s", tostring(err))
        end

        if panel and InterfaceOptionsFrame_OpenToCategory then
            local ok, err = pcall(InterfaceOptionsFrame_OpenToCategory, panel)
            if ok then return end
            LogWarn("InterfaceOptionsFrame_OpenToCategory failed: %s", tostring(err))
        end

        LogWarn("Unable to open native Blizzard settings for %s.", tostring(panel and panel.name))
        return
    end

    -- Fallback: show standalone directly (no Toggle call — avoids any recursion)
    if wrapper then
        PresentStandaloneSettings()
    elseif panel then
        panel:Show()
    end
end
