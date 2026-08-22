-- GoldAdvisorMidnight/Settings.lua
-- Registers a native Blizzard Interface > AddOns canvas panel (no custom backdrop on canvas).
-- Falls back to a draggable standalone popup when Blizzard API is unavailable.
-- Gold section headers, Credits & Thanks scrollbox. Module: GAM.Settings

local ADDON_NAME, GAM = ...

-- Capture Blizzard Settings API before any local `Settings` variable shadows it.
local BlizzardSettingsAPI = Settings

local SettingsMod = {}
GAM.Settings = SettingsMod
local WindowManager = GAM.UI.WindowManager
local NodeDisplay = GAM.ProfessionNodeDisplay

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
        _G["GoldAdvisorMidnightMainWindow"],
        _G["GoldAdvisorMidnightStrategyDetail"],
        _G["GoldAdvisorMidnightDebugLog"],
        _G["GoldAdvisorMidnightShoppingList"],
    }
    for _, f in ipairs(targets) do
        if f then f:SetScale(scale) end
    end
end

-- Gold accent color used throughout
local GOLD_R, GOLD_G, GOLD_B         = 1.0, 0.82, 0.0
local GOLD_DIM_R, GOLD_DIM_G, GOLD_DIM_B = 0.7, 0.57, 0.0
local THALASSIAN_LUMBER_ITEM_ID = 256963

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

-- UIDropDownMenuTemplate replaced with cycle button: pops outside ScrollFrame boundaries.

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

local function FormatGoldInput(copper)
    local n = tonumber(copper)
    if not n or n <= 0 then
        return ""
    end
    local text = string.format("%.4f", n / 10000)
    text = text:gsub("0+$", ""):gsub("%.$", "")
    return text
end

local function ParseGoldInput(text)
    local clean = tostring(text or ""):gsub(",", ""):match("^%s*(.-)%s*$")
    if clean == "" then
        return nil
    end
    local gold = tonumber(clean)
    if not gold or gold <= 0 then
        return nil
    end
    return math.floor((gold * 10000) + 0.5)
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
    local L    = GAM.L
    local opts = GetOpts()

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

    -- Rank policy: cycle button — avoids UIDropDownMenu pop-out bugs.
    local rankLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y)
    rankLabel:SetText(L["OPT_RANK_POLICY"])

    local rankTexts = {
        lowest = L["OPT_RANK_LOWEST"],
        optimal = L["OPT_RANK_OPTIMAL"] or "Best Mix to Max",
        highest = L["OPT_RANK_HIGHEST"],
    }
    local rankCurrent = rankTexts[opts.rankPolicy] and opts.rankPolicy or "lowest"

    local rankBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    rankBtn:SetSize(110, 22)
    rankBtn:SetPoint("LEFT", rankLabel, "RIGHT", 12, 0)
    rankBtn:SetText(rankTexts[rankCurrent])
    rankBtn:SetScript("OnClick", function()
        rankCurrent = rankCurrent == "lowest" and "optimal"
            or rankCurrent == "optimal" and "highest"
            or "lowest"
        rankBtn:SetText(rankTexts[rankCurrent])
    end)

    -- Shim so ApplySettings can call ddRank.GetValue() unchanged
    local ddRank = { GetValue = function() return rankCurrent end }
    y = y - 30

    -- Theme: cycle button (Classic ↔ Soft)
    local themeLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    themeLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y)
    themeLabel:SetText(L["OPT_THEME"])

    local themeTexts = { classic = L["OPT_THEME_CLASSIC"], soft = L["OPT_THEME_SOFT"] }
    local themeCurrent = (opts.v2Theme == "soft") and "soft" or "classic"

    local themeBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    themeBtn:SetSize(80, 22)
    themeBtn:SetPoint("LEFT", themeLabel, "RIGHT", 12, 0)
    themeBtn:SetText(themeTexts[themeCurrent])
    themeBtn:SetScript("OnClick", function()
        themeCurrent = (themeCurrent == "classic") and "soft" or "classic"
        themeBtn:SetText(themeTexts[themeCurrent])
    end)
    y = y - 30

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

    local cbRememberAHState = MakeCheckbox(content, L["OPT_REMEMBER_AH_STATE"], y - 4)
    cbRememberAHState:SetChecked(opts.rememberAHWindowState ~= false)
    cbRememberAHState:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["TT_OPT_REMEMBER_AH_STATE_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["TT_OPT_REMEMBER_AH_STATE_BODY"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    cbRememberAHState:SetScript("OnLeave", function() GameTooltip:Hide() end)
    y = y - 32

    -- ── Pricing ────────────────────────────────────────────────────────────
    y = MakeSectionHeader(content, L["SETTINGS_SECTION_PRICING"], y)

    local ebFillQty
    local ebLumberPrice
    local modeLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modeLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y - 3)
    modeLabel:SetText("Mass Crafting Model")

    local modeTexts = {
        exhaust_materials = "Reinvest Resourcefulness",
    }
    local modeCurrent = "exhaust_materials"
    local modeBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    modeBtn:SetSize(170, 22)
    modeBtn:SetPoint("LEFT", modeLabel, "RIGHT", 12, 0)
    modeBtn:SetText(modeTexts[modeCurrent])
    modeBtn:Disable()

    local modeHelp = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    modeHelp:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y - 28)
    modeHelp:SetText("The starting reagent pool is charged once; expected Resourcefulness procs fund additional crafts.")
    modeHelp:SetTextColor(0.72, 0.72, 0.72, 1)

    y = y - 48

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

    y = y - 40

    local lblLumberPrice = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblLumberPrice:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y - 3)
    lblLumberPrice:SetText("Thalassian Lumber")

    ebLumberPrice = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    ebLumberPrice:SetSize(70, 22)
    ebLumberPrice:SetPoint("TOPLEFT", content, "TOPLEFT", 145, y)
    ebLumberPrice:SetAutoFocus(false)
    ebLumberPrice:SetMaxLetters(12)
    do
        local pdb = GAM.GetPatchDB and GAM:GetPatchDB(GAM.C.DEFAULT_PATCH)
        ebLumberPrice:SetText(FormatGoldInput(pdb and pdb.priceOverrides and pdb.priceOverrides[THALASSIAN_LUMBER_ITEM_ID]))
    end

    local lblLumberUnit = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblLumberUnit:SetPoint("LEFT", ebLumberPrice, "RIGHT", 6, 0)
    lblLumberUnit:SetText("gold each")
    lblLumberUnit:SetTextColor(0.55, 0.55, 0.55)

    local function NormalizeLumberPrice()
        local copper = ParseGoldInput(ebLumberPrice:GetText())
        ebLumberPrice:SetText(FormatGoldInput(copper))
        ebLumberPrice:ClearFocus()
    end
    ebLumberPrice:SetScript("OnEnterPressed", NormalizeLumberPrice)
    ebLumberPrice:SetScript("OnEditFocusLost", NormalizeLumberPrice)
    ebLumberPrice:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Thalassian Lumber price", 1, 1, 1)
        GameTooltip:AddLine("Manual per-unit value for account-bound lumber. Leave blank or 0 to mark lumber as missing price data.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    ebLumberPrice:SetScript("OnLeave", function() GameTooltip:Hide() end)

    y = y - 40

    -- ── Advanced manual stat fallbacks ─────────────────────────────────────
    y = MakeSectionHeader(content, "Advanced: Manual Stat Fallbacks", y)

    local subHdr = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y)
    subHdr:SetText("Profile-wide fallback only. Exact recipe/crafter captures take precedence; these values are not scoped to the selected strategy.")
    y = y - 20

    local chMulti = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chMulti:SetPoint("TOPLEFT", content, "TOPLEFT", 250, y)
    chMulti:SetText("Multi%")
    local chRes = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chRes:SetPoint("TOPLEFT", content, "TOPLEFT", 345, y)
    chRes:SetText("Res%")
    y = y - 20

    local craftStatRows = {}

    local function MakeStatEditBox(anchorX, tooltipTitle, tooltipBody, fallbackValue)
        local eb = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
        eb:SetSize(44, 22)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(6)
        eb:SetPoint("TOPLEFT", content, "TOPLEFT", anchorX, y)
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
        lbl:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y - 3)
        lbl:SetText(def.label)

        local row = {
            label = def.label,
            multiKey = def.multiKey,
            resKey = def.resKey,
            defaultMulti = def.defaultMulti,
            defaultRes = def.defaultRes,
            multiBox = nil,
            resBox = nil,
        }

        if row.multiKey then
            row.multiBox = MakeStatEditBox(
                250,
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
            345,
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
        y = y - 26
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

    local btnResetStatFallbacks = MakeButton(content, "Reset Fallback Defaults", 160, 20, y - 2)
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
    y = y - 34

    -- ── Profession node ranks ──────────────────────────────────────────────
    local professionNodeRows = {}
    local professionNodeSections = {}
    local professionNodeOrder = (GAM.CraftingStats
        and GAM.CraftingStats.GetSupportedNodeProfessions
        and GAM.CraftingStats.GetSupportedNodeProfessions()) or { "Engineering" }
    if #professionNodeOrder == 0 then
        professionNodeOrder = { "Engineering" }
    end
    local currentNodeProfessionIndex = 1
    local professionNodeButtons = {}

    local nodeTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nodeTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y - 3)
    nodeTitle:SetText("Profession Nodes")

    local nodeStatus = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nodeStatus:SetPoint("TOPLEFT", nodeTitle, "BOTTOMLEFT", 0, -4)
    nodeStatus:SetWidth(520)
    nodeStatus:SetJustifyH("LEFT")
    nodeStatus:SetTextColor(0.65, 0.65, 0.65)
    nodeStatus:SetText("Choose a profession. These ranks feed extra-output and resourcefulness pricing bonuses.")

    local nodeButtonTopY = y - 42
    for _, profession in ipairs(professionNodeOrder) do
        local btn = MakeButton(content, profession, MeasureButtonWidth(content, profession, 86, 118, 18))
        btn._gamNodeProfession = profession
        professionNodeButtons[#professionNodeButtons + 1] = btn
    end
    local nodeButtonLayout = LayoutButtonsTop(content, professionNodeButtons, nodeButtonTopY, {
        left = 20,
        right = 540,
        gap = 6,
        rowGap = 4,
        align = "left",
        height = 22,
    })
    y = nodeButtonTopY - nodeButtonLayout.usedHeight - 12

    local nodeRowsFrame = CreateFrame("Frame", nil, content)
    nodeRowsFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y)
    nodeRowsFrame:SetSize(520, 1)

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
        eb:SetSize(36, 20)
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

    local function AddNodeGroupHeader(parent, text, nodeY)
        local hdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, nodeY)
        hdr:SetWidth(505)
        hdr:SetJustifyH("LEFT")
        hdr:SetText(text)
        return nodeY - 20, hdr
    end

    local function AddNodeRow(parent, profession, section, row, nodeY)
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
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, nodeY - 2)
        lbl:SetWidth(310)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(row.name or ("Node " .. tostring(row.nodeID)))
        lbl:EnableMouse(true)
        lbl:SetScript("OnEnter", function(self) ShowNodeTooltip(self, rowState) end)
        lbl:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local eb = MakeNodeRankBox(parent, rowState)
        eb:SetPoint("TOPLEFT", parent, "TOPLEFT", 335, nodeY)

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
        section.rows[#section.rows + 1] = rowState
        professionNodeRows[#professionNodeRows + 1] = rowState
        return nodeY - 25
    end

    local function BuildNodeSection(profession)
        local section = {
            profession = profession,
            rows = {},
            groups = {},
        }
        local frame = CreateFrame("Frame", nil, nodeRowsFrame)
        frame:SetPoint("TOPLEFT", nodeRowsFrame, "TOPLEFT", 0, 0)
        frame:SetSize(520, 1)
        frame:Hide()
        section.frame = frame

        local nodeY = 0
        local nodeData = GAM.CraftingStats
            and GAM.CraftingStats.GetProfessionNodeRows
            and GAM.CraftingStats.GetProfessionNodeRows(profession)
        for _, group in ipairs((nodeData and nodeData.groups) or {}) do
            local header
            nodeY, header = AddNodeGroupHeader(frame, group.label or "Nodes", nodeY)
            section.groups[#section.groups + 1] = {
                header = header,
                rootNodeID = group.rootNodeID,
            }
            for _, row in ipairs(group.rows or {}) do
                nodeY = AddNodeRow(frame, profession, section, row, nodeY)
            end
        end

        local btnResetCaptured = MakeButton(frame, "Use Captured", 120, 12, nodeY - 4)
        btnResetCaptured:SetScript("OnClick", function()
            if GAM.CraftingStats and GAM.CraftingStats.ResetProfessionNodesToCaptured then
                GAM.CraftingStats.ResetProfessionNodesToCaptured(profession)
            end
            if panel and panel.refresh then panel.refresh() end
        end)

        local btnResetDefaults = MakeButton(frame, "Use Defaults", 115, 140, nodeY - 4)
        btnResetDefaults:SetScript("OnClick", function()
            if GAM.CraftingStats and GAM.CraftingStats.ResetProfessionNodesToDefaults then
                GAM.CraftingStats.ResetProfessionNodesToDefaults(profession)
            end
            if panel and panel.refresh then panel.refresh() end
        end)
        nodeY = nodeY - 34
        section.height = math.abs(nodeY) + 4
        frame:SetHeight(section.height)
        professionNodeSections[#professionNodeSections + 1] = section
        return section.height
    end

    local maxNodeSectionHeight = 1
    for _, profession in ipairs(professionNodeOrder) do
        local height = BuildNodeSection(profession)
        if height > maxNodeSectionHeight then
            maxNodeSectionHeight = height
        end
    end
    nodeRowsFrame:SetHeight(maxNodeSectionHeight)

    local function SelectNodeProfession(index)
        currentNodeProfessionIndex = index
        local currentProfession = professionNodeOrder[currentNodeProfessionIndex] or professionNodeOrder[1]
        for i, btn in ipairs(professionNodeButtons) do
            local selected = (i == currentNodeProfessionIndex)
            btn:SetEnabled(not selected)
            if btn:GetFontString() then
                if selected then
                    btn:GetFontString():SetTextColor(GOLD_R, GOLD_G, GOLD_B)
                else
                    btn:GetFontString():SetTextColor(1, 1, 1)
                end
            end
        end
        for _, section in ipairs(professionNodeSections) do
            section.frame:SetShown(section.profession == currentProfession)
        end
        return currentProfession
    end

    local function RefreshProfessionNodeRows()
        local selectedProfession = SelectNodeProfession(currentNodeProfessionIndex)
        local selectedData = nil
        local data = GAM.CraftingStats
            and GAM.CraftingStats.GetProfessionNodeRows
        for _, section in ipairs(professionNodeSections) do
            local sectionData = data and data(section.profession) or nil
            if section.profession == selectedProfession then
                selectedData = sectionData
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
                if rowState.box then
                    rowState.box:SetText(tostring(row.rank or 0))
                end
                if rowState.label then
                    rowState.label:SetText(rowState.name or ("Node " .. tostring(rowState.nodeID)))
                end
                if rowState.maxText then
                    rowState.maxText:SetText("/ " .. tostring(rowState.maxRank))
                end
                if rowState.note then
                    local noteText = "Default"
                    if row.manualRank ~= nil then
                        noteText = "Override"
                    elseif row.capturedRank ~= nil then
                        noteText = "Captured"
                    end
                    rowState.note:SetText(noteText)
                end
                rowState.dirty = false
                rowState.refreshing = false
            end
        end

        if selectedData and selectedData.capturedAt then
            nodeStatus:SetText("Showing captured ranks and in-game names for " .. tostring(selectedProfession) .. ". Edit a rank only when an override is needed.")
        else
            nodeStatus:SetText("Open " .. tostring(selectedProfession) .. " once on its crafter to capture in-game names and learned ranks. Defaults are shown for now.")
        end
    end

    for i, btn in ipairs(professionNodeButtons) do
        btn:SetScript("OnClick", function()
            currentNodeProfessionIndex = i
            RefreshProfessionNodeRows()
        end)
    end
    SelectNodeProfession(currentNodeProfessionIndex)

    y = y - nodeRowsFrame:GetHeight() - 8

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
        ClearPriceCache()
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

    y = y - 4

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
    cy = AddCreditLine("|cffFFD100CraftSim|r  —  Outstanding crafting simulation addon; GAM uses optional interop and MIT-licensed static spec-data references.", 1, 1, 1, cy)
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
        local currentOpts = GetOpts()
        local prevQty = GetOptionValue(currentOpts, "shallowFillQty", GAM.C.DEFAULT_FILL_QTY)
        currentOpts.scanDelay = slScanDelay:GetValue()
        currentOpts.debugVerbosity = slVerbosity:GetValue()
        currentOpts.minimapHidden = not cbMinimap:GetChecked()
        currentOpts.v2Theme = themeCurrent
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

        local raw = tonumber(ebFillQty:GetText())
        currentOpts.shallowFillQty = raw
            and math.max(GAM.C.MIN_FILL_QTY,
                math.min(GAM.C.MAX_FILL_QTY, math.floor(raw)))
            or GAM.C.DEFAULT_FILL_QTY
        ebFillQty:SetText(tostring(currentOpts.shallowFillQty))

        local lumberCopper = ParseGoldInput(ebLumberPrice and ebLumberPrice:GetText())
        if GAM.Pricing then
            if lumberCopper and lumberCopper > 0 then
                GAM.Pricing.SetPriceOverride(THALASSIAN_LUMBER_ITEM_ID, lumberCopper, GAM.C.DEFAULT_PATCH)
            else
                GAM.Pricing.ClearPriceOverride(THALASSIAN_LUMBER_ITEM_ID, GAM.C.DEFAULT_PATCH)
            end
        end
        if ebLumberPrice then
            ebLumberPrice:SetText(FormatGoldInput(lumberCopper))
        end

        GAM.Log.SetLevel(currentOpts.debugVerbosity)
        if GAM.AHScan then
            GAM.AHScan.SetScanDelay(currentOpts.scanDelay)
        end
        GAM.Minimap.SetShown(not currentOpts.minimapHidden)

        local qtyChanged = currentOpts.shallowFillQty ~= prevQty
        if qtyChanged then
            ClearPriceCache()
            local msg = string.format("Fill qty changed (%s -> %s units). Price cache cleared — re-scan.",
                FmtQty(prevQty), FmtQty(currentOpts.shallowFillQty))
            GAM.Log.Info(msg)
            print("|cffff8800[GAM]|r " .. msg)
        end

        GAM.Log.Info("Fill qty: %d", currentOpts.shallowFillQty)
        local lumberPriceText = "unset"
        if lumberCopper and GAM.Pricing and GAM.Pricing.FormatPrice then
            lumberPriceText = GAM.Pricing.FormatPrice(lumberCopper)
        end
        GAM.Log.Info("Thalassian Lumber manual price: %s", lumberPriceText)
        GAM.Log.Info("V2 pricing mode: %s", tostring(currentOpts.v2PricingMode or NormalizeV2PricingMode(nil)))

        if GAM.UI and GAM.UI.MainWindow and GAM.UI.MainWindow.Refresh then
            GAM.UI.MainWindow.Refresh()
        end
        if GAM.UI and GAM.UI.StrategyDetail and
            GAM.UI.StrategyDetail.IsShown and GAM.UI.StrategyDetail.Refresh and
            GAM.UI.StrategyDetail.IsShown() then
            GAM.UI.StrategyDetail.Refresh()
        end

        if GAM.UI and GAM.UI.MainWindow and GAM.UI.MainWindow.ApplyTheme then
            GAM.UI.MainWindow.ApplyTheme()
        end

        GAM.Log.Info("Settings saved.")
    end

    local function RefreshControlsFromOptions(o)
        if not o then return end
        slScanDelay:SetValue(GetOptionValue(o, "scanDelay", GAM.C.DEFAULT_SCAN_DELAY))
        slVerbosity:SetValue(GetOptionValue(o, "debugVerbosity", GAM.C.DEFAULT_VERBOSITY))
        cbMinimap:SetChecked(not o.minimapHidden)
        cbRememberAHState:SetChecked(o.rememberAHWindowState ~= false)
        slScale:SetValue(GetOptionValue(o, "uiScale", GAM.C.DEFAULT_UI_SCALE))
        ebFillQty:SetText(tostring(GetOptionValue(o, "shallowFillQty", GAM.C.DEFAULT_FILL_QTY)))
        do
            local pdb = GAM.GetPatchDB and GAM:GetPatchDB(GAM.C.DEFAULT_PATCH)
            ebLumberPrice:SetText(FormatGoldInput(
                pdb and pdb.priceOverrides and pdb.priceOverrides[THALASSIAN_LUMBER_ITEM_ID]
            ))
        end
        rankCurrent = rankTexts[o.rankPolicy] and o.rankPolicy or "lowest"
        rankBtn:SetText(rankTexts[rankCurrent])
        modeCurrent = "exhaust_materials"
        modeBtn:SetText(modeTexts[modeCurrent])
        themeCurrent = themeTexts[o.v2Theme] and o.v2Theme or "classic"
        themeBtn:SetText(themeTexts[themeCurrent])

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
    panel.OnCommit = panel.okay
    panel.OnRefresh = panel.refresh
    panel.OnDefault = function() end
    panel.default = panel.OnDefault

    -- Native Blizzard settings should not auto-apply on hide/cancel.
    -- Standalone fallback keeps the historical apply-on-close behavior.
    panel:SetScript("OnHide", function()
        if not nativeMode then
            ApplySettings()
        end
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
        WindowManager.Register(wrapper, "dialog")

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
        if wrapper:IsShown() then
            wrapper:Hide()
        else
            wrapper:Show()
            WindowManager.Present(wrapper)
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
        wrapper:Show()
        WindowManager.Present(wrapper)
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
        WindowManager.Present(wrapper)
    elseif panel then
        panel:Show()
    end
end
