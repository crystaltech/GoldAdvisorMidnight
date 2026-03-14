-- GoldAdvisorMidnight/Settings.lua
-- Registers a native Blizzard Interface > AddOns canvas panel (no custom backdrop on canvas).
-- Falls back to a draggable standalone popup when Blizzard API is unavailable.
-- Gold section headers, Credits & Thanks scrollbox. Module: GAM.Settings

local ADDON_NAME, GAM = ...

-- Capture Blizzard Settings API before any local `Settings` variable shadows it.
local BlizzardSettingsAPI = Settings

local SettingsMod = {}
GAM.Settings = SettingsMod

local panel          -- plain canvas frame (registered with Blizzard)
local wrapper        -- standalone popup wrapper (only built on Blizzard API failure)
local category       -- Blizzard Settings category reference
local categoryID     -- resolved category ID for OpenToCategory/OpenSettingsPanel
local nativeMode     -- true if Blizzard registration succeeded

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

-- Apply a scale factor to all main addon frames
local function ApplyScaleToFrames(scale)
    local targets = {
        _G["GoldAdvisorMidnightMainWindow"],
        _G["GoldAdvisorMidnightStratDetail"],
        _G["GoldAdvisorMidnightDebugLog"],
        _G["GAMStratCreator"],
        _G["GAMExportPopup"],
        _G["GAMImportPopup"],
        _G["GoldAdvisorMidnightShoppingList"],
        _G["GAMDeleteConfirm"],
    }
    for _, f in ipairs(targets) do
        if f then f:SetScale(scale) end
    end
end

-- Gold accent color used throughout
local GOLD_R, GOLD_G, GOLD_B         = 1.0, 0.82, 0.0
local GOLD_DIM_R, GOLD_DIM_G, GOLD_DIM_B = 0.7, 0.57, 0.0

-- Unique name counter so _G[name.."Low"] / _G[name.."Text"] always resolve.
local _widgetCount = 0
local function NextWidgetName(prefix)
    _widgetCount = _widgetCount + 1
    return "GAMSettings_" .. prefix .. _widgetCount
end

-- ===== Helper: gold section header =====
-- Creates a gold label + a thin gold underline rule spanning the content width.
local function MakeSectionHeader(parent, text, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    lbl:SetText(text)
    lbl:SetTextColor(GOLD_R, GOLD_G, GOLD_B)

    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT",  parent, "TOPLEFT",  14, y - 16)
    rule:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, y - 16)
    rule:SetColorTexture(GOLD_DIM_R, GOLD_DIM_G, GOLD_DIM_B, 0.8)

    return y - 24  -- return next y offset below the rule
end

-- ===== Helper: labeled slider =====
local function MakeSlider(parent, label, tip, minV, maxV, step, yOff)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(300, 40)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOff)

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    lbl:SetText(label)

    local slName = NextWidgetName("Slider")
    local sl = CreateFrame("Slider", slName, f, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -4)
    sl:SetWidth(260)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    sl:SetObeyStepOnDrag(true)
    local lowText  = _G[slName .. "Low"]
    local highText = _G[slName .. "High"]
    if lowText  then lowText:SetText(tostring(minV))  end
    if highText then highText:SetText(tostring(maxV)) end

    local val = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("TOP", sl, "BOTTOM", 0, 2)

    sl:SetScript("OnValueChanged", function(self, v)
        val:SetText(string.format("%.2f", v))
    end)

    if tip then
        sl:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        sl:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return sl, val
end

-- ===== Helper: checkbox =====
local function MakeCheckbox(parent, label, yOff)
    local cbName = NextWidgetName("CB")
    local cb = CreateFrame("CheckButton", cbName, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOff)
    cb:SetSize(24, 24)
    local textFrame = _G[cbName .. "Text"]
    if textFrame then
        textFrame:SetText(label)
    else
        local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetText(label)
    end
    return cb
end

-- ===== Helper: button =====
local function MakeButton(parent, label, w, x, y)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w, 22)
    if x and y then
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end
    btn:SetText(label)
    return btn
end

local function MeasureButtonWidth(parent, text, minW, maxW, padding)
    parent._gamMeasureFS = parent._gamMeasureFS or parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local fs = parent._gamMeasureFS
    fs:SetText(text or "")
    local w = math.ceil(fs:GetStringWidth() + (padding or 24))
    if minW and w < minW then w = minW end
    if maxW and w > maxW then w = maxW end
    return w
end

local function LayoutButtonsTop(parent, buttons, topY, cfg)
    local left   = cfg.left or 14
    local right  = cfg.right or 546
    local gap    = cfg.gap or 8
    local rowGap = cfg.rowGap or 4
    local align  = cfg.align or "center"
    local h      = cfg.height or 22
    local avail  = math.max(1, right - left)

    local rows = { {} }
    local rowWidths = { 0 }
    for _, btn in ipairs(buttons) do
        local bw = btn:GetWidth()
        local row = rows[#rows]
        local nextW = (#row > 0) and (rowWidths[#rows] + gap + bw) or bw
        if #row > 0 and nextW > avail then
            rows[#rows + 1] = { btn }
            rowWidths[#rowWidths + 1] = bw
        else
            row[#row + 1] = btn
            rowWidths[#rowWidths] = nextW
        end
    end

    for ri, row in ipairs(rows) do
        local rw = rowWidths[ri]
        local x
        if align == "right" then
            x = right - rw
        elseif align == "left" then
            x = left
        else
            x = left + math.floor((avail - rw) / 2)
        end
        local y = topY - (ri - 1) * (h + rowGap)
        for bi, btn in ipairs(row) do
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
            x = x + btn:GetWidth() + ((bi < #row) and gap or 0)
        end
    end

    return {
        rows = #rows,
        usedHeight = (#rows * h) + ((#rows - 1) * rowGap),
    }
end

-- ===== Helper: dropdown =====
local function MakeDropdown(parent, label, options, yOff)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(300, 42)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOff)

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    lbl:SetText(label)

    local dd = CreateFrame("Frame", nil, f, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", -15, -2)
    UIDropDownMenu_SetWidth(dd, 200)

    local currentVal
    local function SetVal(val, text)
        currentVal = val
        UIDropDownMenu_SetSelectedValue(dd, val)
        UIDropDownMenu_SetText(dd, text)
    end
    f.SetValue = SetVal
    f.GetValue = function() return currentVal end

    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = opt.text
            info.value   = opt.value
            info.checked = (opt.value == currentVal)
            info.func    = function()
                SetVal(opt.value, opt.text)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    return f
end

-- Formats an integer with thousands-separator commas: 50000 → "50,000"
local function FmtQty(n)
    local s = tostring(math.floor(n))
    return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- ===== Build the settings content panel =====
-- Returns a plain frame with no backdrop — safe to embed in Blizzard's canvas.
local function BuildPanel()
    local L    = GAM.L
    local opts = GAM.db.options

    -- Plain frame: no BackdropTemplate, no custom title, no custom close button.
    -- Blizzard Settings embeds this directly; it inherits the canvas background.
    panel = CreateFrame("Frame", "GoldAdvisorMidnightSettingsPanel", UIParent)
    panel:SetSize(620, 550)
    panel:SetPoint("CENTER", UIParent, "CENTER")
    panel:Hide()

    -- Outer scroll container to keep all controls clipped within Blizzard's canvas.
    local outerScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    outerScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
    outerScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 10)

    local content = CreateFrame("Frame", nil, outerScroll)
    content:SetPoint("TOPLEFT", outerScroll, "TOPLEFT", 0, 0)
    content:SetSize(560, 1)
    outerScroll:SetScrollChild(content)

    local function FinalizeContentLayout(finalY, bottomPadding)
        local viewportW = outerScroll:GetWidth()
        if not viewportW or viewportW <= 0 then
            viewportW = panel:GetWidth() - 40
        end
        content:SetWidth(math.max(1, viewportW))

        local viewportH = outerScroll:GetHeight()
        if not viewportH or viewportH <= 0 then
            viewportH = panel:GetHeight() - 20
        end
        local neededH = math.max(viewportH, math.abs(finalY) + (bottomPadding or 0))
        content:SetHeight(math.max(1, neededH))
    end

    local y = -14

    -- ── Scan Settings ──────────────────────────────────────────────────────
    y = MakeSectionHeader(content, L["SETTINGS_SECTION_SCAN"], y)
    -- y now just below the gold rule

    local slScanDelay, _ = MakeSlider(content, L["OPT_SCAN_DELAY"], L["OPT_SCAN_DELAY_TIP"],
        1, 10, 0.5, y - 4)
    slScanDelay:SetValue(opts.scanDelay)
    y = y - 58

    local slVerbosity, _ = MakeSlider(content, L["OPT_VERBOSITY"], L["OPT_VERBOSITY_TIP"],
        0, 3, 1, y)
    slVerbosity:SetValue(opts.debugVerbosity)
    y = y - 48

    -- ── Display ────────────────────────────────────────────────────────────
    y = MakeSectionHeader(content, L["SETTINGS_SECTION_DISPLAY"], y)

    local cbMinimap = MakeCheckbox(content, L["OPT_MINIMAP"], y - 4)
    cbMinimap:SetChecked(not opts.minimapHidden)
    y = y - 32

    local ddRank = MakeDropdown(content, L["OPT_RANK_POLICY"], {
        { text = L["OPT_RANK_HIGHEST"], value = "highest" },
        { text = L["OPT_RANK_LOWEST"],  value = "lowest"  },
    }, y)
    ddRank.SetValue(opts.rankPolicy == "highest" and "highest" or "lowest",
        opts.rankPolicy == "highest" and L["OPT_RANK_HIGHEST"] or L["OPT_RANK_LOWEST"])
    y = y - 50

    local slScale, slScaleVal = MakeSlider(content, L["OPT_UI_SCALE"], L["OPT_UI_SCALE_TIP"],
        GAM.C.MIN_UI_SCALE, GAM.C.MAX_UI_SCALE, 0.05, y)
    slScale:SetValue(opts.uiScale or GAM.C.DEFAULT_UI_SCALE)
    -- Override OnValueChanged to also apply scale live
    slScale:SetScript("OnValueChanged", function(self, v)
        slScaleVal:SetText(string.format("%.2f", v))
        ApplyScaleToFrames(v)
    end)
    local slScaleRange = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slScaleRange:SetPoint("LEFT", slScale, "RIGHT", 6, 0)
    slScaleRange:SetText(L["OPT_UI_SCALE_RANGE"])
    slScaleRange:SetTextColor(0.55, 0.55, 0.55)
    y = y - 48

    -- ── Pricing ────────────────────────────────────────────────────────────
    y = MakeSectionHeader(content, L["SETTINGS_SECTION_PRICING"], y)

    local ebFillQty

    local lblFillQty = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblFillQty:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y - 3)
    lblFillQty:SetText(L["OPT_SHALLOW_FILL_QTY"])

    ebFillQty = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    ebFillQty:SetSize(60, 22)
    ebFillQty:SetPoint("TOPLEFT", content, "TOPLEFT", 84, y)
    ebFillQty:SetAutoFocus(false)
    ebFillQty:SetNumeric(true)
    ebFillQty:SetText(tostring(opts.shallowFillQty or GAM.C.DEFAULT_FILL_QTY))

    local lblRange = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblRange:SetPoint("LEFT", ebFillQty, "RIGHT", 6, 0)
    lblRange:SetText(L["OPT_SHALLOW_FILL_RANGE"])
    lblRange:SetTextColor(0.55, 0.55, 0.55)

    local function ClampFillQty()
        local raw = tonumber(ebFillQty:GetText())
        local val = raw
            and math.max(GAM.C.MIN_FILL_QTY,
                math.min(GAM.C.MAX_FILL_QTY, math.floor(raw)))
            or GAM.C.DEFAULT_FILL_QTY
        ebFillQty:SetText(tostring(val))
        ebFillQty:ClearFocus()
    end
    ebFillQty:SetScript("OnEnterPressed", ClampFillQty)
    ebFillQty:SetScript("OnEditFocusLost", ClampFillQty)
    ebFillQty:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["OPT_SHALLOW_FILL_TIP"], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    ebFillQty:SetScript("OnLeave", function() GameTooltip:Hide() end)

    y = y - 36

    local cbMillOwn = MakeCheckbox(content, "Mill own herbs for Inscription", y - 4)
    cbMillOwn:SetChecked((opts.pigmentCostSource or "ah") == "mill")
    y = y - 32

    -- ── Actions ────────────────────────────────────────────────────────────
    y = MakeSectionHeader(content, L["SETTINGS_SECTION_ACTIONS"], y)

    -- Row 1: action buttons (auto-sized, centered, wrapped if needed)
    local btnReload = MakeButton(content, L["BTN_RELOAD_DATA"], 120)
    btnReload:SetScript("OnClick", function()
        GAM.Importer.Init()
        GAM.Log.Info("Data reloaded.")
        print("|cffff8800[GAM]|r Data reloaded.")
    end)

    local btnClear = MakeButton(content, L["BTN_CLEAR_CACHE"], 120)
    btnClear:SetScript("OnClick", function()
        wipe(GAM.db.priceCache)
        GAM.Log.Info("Price cache cleared.")
        print("|cffff8800[GAM]|r Cache cleared.")
    end)

    local btnLog = MakeButton(content, L["BTN_OPEN_LOG"], 100)
    btnLog:SetScript("OnClick", function()
        if GAM.UI and GAM.UI.DebugLog then
            GAM.UI.DebugLog.Show()
        end
    end)

    btnReload:SetWidth(MeasureButtonWidth(content, btnReload:GetText(), 120, 220, 24))
    btnClear:SetWidth(MeasureButtonWidth(content, btnClear:GetText(), 120, 260, 24))
    btnLog:SetWidth(MeasureButtonWidth(content, btnLog:GetText(), 100, 240, 24))
    local actionsRow1 = LayoutButtonsTop(content, { btnReload, btnClear, btnLog }, y - 4, {
        left = 14, right = 546, gap = 8, rowGap = 4, align = "center",
    })
    y = y - actionsRow1.usedHeight - 10

    -- Row 2: strategy actions (auto-sized, centered, wrapped if needed)
    local btnCreate = MakeButton(content, L["BTN_CREATE_STRAT"], 150)
    btnCreate:SetScript("OnClick", function()
        SettingsMod.Hide()
        if GAM.UI and GAM.UI.StratCreator then GAM.UI.StratCreator.Show() end
    end)

    local btnImportStrat = MakeButton(content, L["BTN_IMPORT_STRAT"], 150)
    btnImportStrat:SetScript("OnClick", function()
        SettingsMod.Hide()
        if GAM.UI and GAM.UI.StratCreator then GAM.UI.StratCreator.ShowImport() end
    end)

    btnCreate:SetWidth(MeasureButtonWidth(content, btnCreate:GetText(), 150, 260, 24))
    btnImportStrat:SetWidth(MeasureButtonWidth(content, btnImportStrat:GetText(), 150, 260, 24))
    local actionsRow2 = LayoutButtonsTop(content, { btnCreate, btnImportStrat }, y - 4, {
        left = 14, right = 546, gap = 8, rowGap = 4, align = "center",
    })
    y = y - actionsRow2.usedHeight - 14

    -- ── Credits & Thanks ───────────────────────────────────────────────────
    y = MakeSectionHeader(content, L["SETTINGS_SECTION_CREDITS"], y)

    -- Dark gold-tinted box to hold the credits scroll
    local creditsBox = CreateFrame("Frame", nil, content, "BackdropTemplate")
    creditsBox:SetPoint("TOPLEFT",  content, "TOPLEFT",  14, y - 4)
    creditsBox:SetPoint("TOPRIGHT", content, "TOPRIGHT", -14, y - 4)
    creditsBox:SetHeight(148)
    creditsBox:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    creditsBox:SetBackdropColor(0.04, 0.03, 0.0, 0.90)
    creditsBox:SetBackdropBorderColor(GOLD_R, GOLD_G, GOLD_B, 0.85)

    local scroll = CreateFrame("ScrollFrame", nil, creditsBox, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     creditsBox, "TOPLEFT",      6,  -6)
    scroll:SetPoint("BOTTOMRIGHT", creditsBox, "BOTTOMRIGHT", -26,  6)

    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(scroll:GetWidth() or 560)
    scrollChild:SetHeight(1)  -- auto-expand with content
    scroll:SetScrollChild(scrollChild)

    -- Credits text as individual FontStrings stacked top-to-bottom
    local function AddCreditLine(text, r, g, b, cy)
        local fs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, cy)
        fs:SetWidth(scrollChild:GetWidth() - 8)
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(r or 1, g or 1, b or 1)
        fs:SetText(text)
        return cy - 18
    end

    local cy = -4
    cy = AddCreditLine("|cffFFD100Eloncs|r  —  The game economy spreadsheet that powers every strategy in this addon.", 1, 1, 1, cy)
    cy = AddCreditLine("", 1, 1, 1, cy)  -- spacer
    cy = AddCreditLine("|cffFFD100Brrerker|r  —  arp_tracker addon; an invaluable reference for AH scanning patterns.", 1, 1, 1, cy)
    cy = AddCreditLine("", 1, 1, 1, cy)
    cy = AddCreditLine("|cffFFD100CraftSim|r  —  Outstanding crafting simulation addon; GAM integrates directly with it.", 1, 1, 1, cy)
    cy = AddCreditLine("", 1, 1, 1, cy)
    cy = AddCreditLine("|cffaaaaaa... and the wider WoW addon community on Wago, CurseForge, and GitHub.|r", 1, 1, 1, cy)
    cy = AddCreditLine("", 1, 1, 1, cy)
    cy = AddCreditLine("|cff888888Thank you all — this addon stands on your shoulders.|r", 1, 1, 1, cy)

    scrollChild:SetHeight(math.abs(cy) + 8)
    y = y - 162

    -- ── Apply / Close (shown only in standalone/fallback mode) ─────────────
    local applyBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    applyBtn:SetSize(100, 22)
    applyBtn:SetPoint("TOPRIGHT", content, "TOPRIGHT", -14, y)
    applyBtn:SetText(L["BTN_APPLY_CLOSE"])
    applyBtn:SetWidth(MeasureButtonWidth(content, applyBtn:GetText(), 100, 260, 24))
    applyBtn:Hide()  -- hidden by default; shown if nativeMode is false
    y = y - 32
    FinalizeContentLayout(y, 22)

    -- ── Apply logic ────────────────────────────────────────────────────────
    local function ApplySettings()
        local prevQty = opts.shallowFillQty or GAM.C.DEFAULT_FILL_QTY

        opts.scanDelay      = slScanDelay:GetValue()
        opts.debugVerbosity = slVerbosity:GetValue()
        opts.minimapHidden  = not cbMinimap:GetChecked()
        opts.rankPolicy         = ddRank.GetValue() or "lowest"
        opts.pigmentCostSource  = cbMillOwn:GetChecked() and "mill" or "ah"
        opts.uiScale        = slScale:GetValue()
        opts.ahCut          = GAM.C.AH_CUT
        ApplyScaleToFrames(opts.uiScale)

        local raw = tonumber(ebFillQty:GetText())
        opts.shallowFillQty = raw
            and math.max(GAM.C.MIN_FILL_QTY,
                math.min(GAM.C.MAX_FILL_QTY, math.floor(raw)))
            or GAM.C.DEFAULT_FILL_QTY
        ebFillQty:SetText(tostring(opts.shallowFillQty))

        GAM.Log.SetLevel(opts.debugVerbosity)
        if GAM.AHScan then
            GAM.AHScan.SetScanDelay(opts.scanDelay)
        end
        GAM.Minimap.SetShown(not opts.minimapHidden)

        local qtyChanged = opts.shallowFillQty ~= prevQty
        if qtyChanged then
            wipe(GAM.db.priceCache)
            local msg = string.format("Fill qty changed (%s -> %s units). Price cache cleared — re-scan.",
                FmtQty(prevQty), FmtQty(opts.shallowFillQty))
            GAM.Log.Info(msg)
            print("|cffff8800[GAM]|r " .. msg)
        end

        GAM.Log.Info("Fill qty: %d", opts.shallowFillQty)

        if qtyChanged and GAM.UI and GAM.UI.StratDetail and
            GAM.UI.StratDetail.IsShown and GAM.UI.StratDetail.Refresh and
            GAM.UI.StratDetail.IsShown() then
            GAM.UI.StratDetail.Refresh()
        end

        GAM.Log.Info("Settings saved.")
    end

    -- Blizzard Settings ok/cancel callbacks
    panel.name   = L["SETTINGS_NAME"]
    panel.cancel = function() end

    -- Guard prevents double-apply: panel.okay sets the flag so the OnHide
    -- handler (which fires immediately after okay on native Settings close)
    -- knows not to run ApplySettings a second time.
    local applyCalledFromOkay = false
    panel.okay = function()
        applyCalledFromOkay = true
        ApplySettings()
    end

    -- Apply on close for both native Blizzard settings and standalone fallback.
    panel:SetScript("OnHide", function()
        if applyCalledFromOkay then
            applyCalledFromOkay = false
            return
        end
        ApplySettings()
    end)

    applyBtn:SetScript("OnClick", function()
        SettingsMod.Hide()
    end)

    -- Store reference so we can show/hide the apply button after registration attempt
    panel._applyBtn = applyBtn

    return panel
end

-- ===== Public API =====
function SettingsMod.Init()
    local p = BuildPanel()
    nativeMode = false
    category = nil
    categoryID = nil

    -- Attempt native Blizzard Settings registration
    if BlizzardSettingsAPI and BlizzardSettingsAPI.RegisterCanvasLayoutCategory then
        local ok, cat = pcall(BlizzardSettingsAPI.RegisterCanvasLayoutCategory, p, p.name)
        if ok and cat then
            pcall(BlizzardSettingsAPI.RegisterAddOnCategory, cat)
            category   = cat
            categoryID = ResolveCategoryID(cat)
            nativeMode = true
        end
    elseif BlizzardSettingsAPI and BlizzardSettingsAPI.RegisterAddOnCategory then
        local ok, cat = pcall(BlizzardSettingsAPI.RegisterAddOnCategory, p)
        if ok then
            category   = cat or p
            categoryID = ResolveCategoryID(category)
            nativeMode = true
        end
    elseif InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, p)
        category = p
        categoryID = ResolveCategoryID(p) or p.name
        nativeMode = true
    end

    if not nativeMode then
        -- Blizzard API unavailable: build a standalone draggable wrapper and show Apply button
        wrapper = CreateFrame("Frame", "GAMSettingsWrapper", UIParent, "BackdropTemplate")
        wrapper:SetSize(648, 590)
        wrapper:SetPoint("CENTER", UIParent, "CENTER")
        wrapper:SetMovable(true)
        wrapper:EnableMouse(true)
        wrapper:RegisterForDrag("LeftButton")
        wrapper:SetScript("OnDragStart", wrapper.StartMoving)
        wrapper:SetScript("OnDragStop",  wrapper.StopMovingOrSizing)
        wrapper:SetFrameStrata("DIALOG")
        wrapper:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        wrapper:SetBackdropColor(0, 0, 0, 1)
        local wbg = wrapper:CreateTexture(nil, "BACKGROUND", nil, -8)
        wbg:SetAllPoints()
        wbg:SetColorTexture(0, 0, 0, 1)
        wrapper:Hide()

        local wTitle = wrapper:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        wTitle:SetPoint("TOP", wrapper, "TOP", 0, -14)
        wTitle:SetText(GAM.L["SETTINGS_NAME"])
        wTitle:SetTextColor(GOLD_R, GOLD_G, GOLD_B)

        local wClose = CreateFrame("Button", nil, wrapper, "UIPanelCloseButton")
        wClose:SetPoint("TOPRIGHT", wrapper, "TOPRIGHT", -4, -4)
        wClose:SetScript("OnClick", function() wrapper:Hide() end)

        -- Parent the content panel inside the wrapper
        p:SetParent(wrapper)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 14, -40)
        p:Show()

        if p._applyBtn then p._applyBtn:Show() end
    end
end

-- Toggle standalone panel — always works regardless of nativeMode.
function SettingsMod.Toggle()
    if nativeMode then
        SettingsMod.OpenPanel()
        return
    end
    if wrapper then
        if wrapper:IsShown() then wrapper:Hide() else wrapper:Show() end
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
        wrapper:Show()
    elseif panel then
        panel:Show()
    end
end

function SettingsMod.Hide()
    if wrapper then wrapper:Hide() end
    if panel   then panel:Hide() end
end

-- OpenPanel: open the Blizzard Interface > AddOns panel to our category.
-- Falls back to standalone wrapper/panel if the Blizzard API is unavailable or errors.
function SettingsMod.OpenPanel()
    if nativeMode then
        if categoryID and C_SettingsUtil and C_SettingsUtil.OpenSettingsPanel then
            local ok, err = pcall(C_SettingsUtil.OpenSettingsPanel, categoryID)
            if ok then return end
            LogWarn("C_SettingsUtil.OpenSettingsPanel failed for categoryID=%s: %s",
                tostring(categoryID), tostring(err))
        end

        if categoryID and BlizzardSettingsAPI and BlizzardSettingsAPI.OpenToCategory then
            local ok, err = pcall(BlizzardSettingsAPI.OpenToCategory, categoryID)
            if ok then return end
            LogWarn("Settings.OpenToCategory failed for categoryID=%s: %s",
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
        wrapper:Show()
    elseif panel then
        panel:Show()
    end
end
