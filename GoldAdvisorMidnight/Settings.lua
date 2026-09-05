-- GoldAdvisorMidnight/Settings.lua
-- Registers a native Blizzard Interface > AddOns canvas panel (no custom backdrop on canvas).
-- Falls back to a draggable standalone popup when Blizzard API is unavailable.
-- Vertical navigation, measured setting rows, and one scroll viewport per page.
-- Module: GAM.Settings

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

-- Layout is measured from the current canvas width. The same row and section
-- helpers serve native Settings and the standalone fallback; no saved keys move.
-- Reference principles: Common Region / Proximity / Fitts / Hick (lawsofux.com),
-- YAGNI / Hyrum (lawsofsoftwareengineering.com).
local function NewText(parent, text, style)
    local fs = parent:CreateFontString(nil, "OVERLAY", style or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText(text or "")
    return fs
end

local function AddLayoutItem(parent, item)
    parent._gamLayout = parent._gamLayout or {}
    parent._gamLayout[#parent._gamLayout + 1] = item
    return item
end

local function MakeSectionHeader(parent, text)
    local title = NewText(parent, text, "GameFontNormal")
    title:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
    })
    card:SetBackdropColor(0.08, 0.08, 0.095, 0.72)
    card:SetBackdropBorderColor(0.4, 0.4, 0.43, 0.45)
    card:SetFrameLevel(parent:GetFrameLevel())
    card:EnableMouse(false)
    AddLayoutItem(parent, { kind = "section", title = title, card = card })
end

local function AddText(parent, fs)
    if type(fs) == "string" then fs = NewText(parent, fs, "GameFontHighlightSmall") end
    fs:SetTextColor(0.72, 0.72, 0.76)
    return AddLayoutItem(parent, { kind = "text", text = fs })
end

local function AddRow(parent, label, control, help, controlWidth, minHeight)
    local row = CreateFrame("Button", nil, parent)
    row:SetFrameLevel(parent:GetFrameLevel() + 2)
    if type(label) == "string" then label = NewText(row, label) end
    label:SetParent(row)
    label:SetTextColor(0.92, 0.92, 0.94)
    control:SetParent(row)
    if type(help) == "string" then help = NewText(row, help, "GameFontHighlightSmall") end
    if help then
        help:SetParent(row)
        help:SetTextColor(0.65, 0.65, 0.70)
    end
    local line = row:CreateTexture(nil, "BACKGROUND")
    line:SetPoint("BOTTOMLEFT", 16, 0)
    line:SetPoint("BOTTOMRIGHT", -16, 0)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.055)
    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.035)
    -- A checkbox can be toggled from its entire labeled row.
    if control:IsObjectType("CheckButton") then
        row:SetScript("OnClick", function() control:Click() end)
    end
    row:SetScript("OnEnter", function()
        local enter = control:GetScript("OnEnter")
        if enter then enter(control) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return AddLayoutItem(parent, {
        kind = "row", frame = row, label = label, control = control, help = help,
        controlWidth = controlWidth or control:GetWidth(), minHeight = minHeight or 48,
    })
end

local function AddCustom(parent, frame, layout)
    return AddLayoutItem(parent, { kind = "custom", frame = frame, layout = layout })
end

local function LayoutPage(page)
    if page.layingOut then return end
    local width = page.scroll:GetWidth()
    if not width or width < 120 then return end -- not yet attached to its host
    page.layingOut = true
    local content = page.content
    content:SetWidth(width)
    local y, openCard, cardTop = 8, nil, 0
    local function CloseCard()
        if openCard then openCard:SetHeight(math.max(16, y - cardTop + 8)) end
    end
    for _, item in ipairs(content._gamLayout or {}) do
        if item.kind == "section" then
            CloseCard()
            if openCard then y = y + 28 end
            item.title:ClearAllPoints()
            item.title:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)
            item.title:SetWidth(width - 16)
            y = y + item.title:GetStringHeight() + 12
            item.card:ClearAllPoints()
            item.card:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            item.card:SetWidth(width)
            openCard, cardTop = item.card, y
            y = y + 4
        elseif item.kind == "row" then
            local row, control = item.frame, item.control
            local cw = math.min(item.controlWidth, math.max(80, width * 0.45))
            local lw = math.max(40, width - cw - 52)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row:SetWidth(width)
            item.label:ClearAllPoints()
            item.label:SetPoint("TOPLEFT", row, "TOPLEFT", 16, -12)
            item.label:SetWidth(lw)
            item.label:SetWordWrap(true)
            local textHeight = item.label:GetStringHeight()
            if item.help then
                item.help:ClearAllPoints()
                item.help:SetPoint("TOPLEFT", item.label, "BOTTOMLEFT", 0, -5)
                item.help:SetWidth(lw)
                item.help:SetWordWrap(true)
                textHeight = textHeight + 5 + item.help:GetStringHeight()
            end
            local height = math.max(item.minHeight, textHeight + 24)
            row:SetHeight(height)
            control:ClearAllPoints()
            control:SetPoint("RIGHT", row, "RIGHT", -16, 0)
            control:SetWidth(cw)
            y = y + height
        elseif item.kind == "text" then
            item.text:ClearAllPoints()
            item.text:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -y - 10)
            item.text:SetWidth(width - 32)
            item.text:SetWordWrap(true)
            y = y + item.text:GetStringHeight() + 20
        elseif item.kind == "custom" then
            item.frame:ClearAllPoints()
            item.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -y - 8)
            item.frame:SetWidth(width - 32)
            local height = item.layout(width - 32)
            item.frame:SetHeight(math.max(1, height))
            y = y + height + 16
        end
    end
    CloseCard()
    content:SetHeight(math.max(1, y + 20, page.scroll:GetHeight()))
    page.scroll:UpdateScrollChildRect()
    local range = math.max(0, page.scroll:GetVerticalScrollRange())
    page.scroll:SetVerticalScroll(math.min(page.scroll:GetVerticalScroll(), range))
    if page.scroll.ScrollBar then page.scroll.ScrollBar:SetShown(range > 1) end
    page.layingOut = false
end

local function MakeSlider(parent, label, tip, minV, maxV, step)
    local group = CreateFrame("Frame", nil, parent)
    group:SetSize(170, 48)
    local name = NextWidgetName("Slider")
    local sl = CreateFrame("Slider", name, group, "OptionsSliderTemplate")
    sl:SetPoint("LEFT", group, "LEFT", 0, 0)
    sl:SetPoint("RIGHT", group, "RIGHT", 0, 0)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    sl:SetObeyStepOnDrag(true)
    local low, high, title = _G[name .. "Low"], _G[name .. "High"], _G[name .. "Text"]
    if low then low:SetText(tostring(minV)) end
    if high then high:SetText(tostring(maxV)) end
    if title then title:SetText("") end
    local val = NewText(group, "", "GameFontHighlightSmall")
    val:SetPoint("BOTTOM", sl, "TOP", 0, 3)
    sl:SetScript("OnValueChanged", function(_, v)
        val:SetText(step >= 1 and string.format("%.0f", v) or string.format("%.2f", v))
    end)
    if tip then
        local function ShowTip()
            GameTooltip:SetOwner(sl, "ANCHOR_RIGHT")
            GameTooltip:SetText(tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
        sl:SetScript("OnEnter", ShowTip)
        sl:SetScript("OnLeave", function() GameTooltip:Hide() end)
        group:SetScript("OnEnter", ShowTip)
    end
    AddRow(parent, label, group, nil, 170, 68)
    return sl, val
end

local function MakeCheckbox(parent, label)
    local name = NextWidgetName("CB")
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    if _G[name .. "Text"] then _G[name .. "Text"]:SetText("") end
    AddRow(parent, label, cb)
    return cb
end

local function MakeButton(parent, label, w, x, y)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w, 28)
    if x and y then btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y) end
    btn:SetText(label)
    return btn
end

local function MeasureButtonWidth(parent, text, minW, maxW, padding)
    parent._gamMeasureFS = parent._gamMeasureFS or parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local fs = parent._gamMeasureFS
    fs:Hide()
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

    panel = CreateFrame("Frame", "GoldAdvisorMidnightSettingsPanel", UIParent)
    panel:SetSize(760, 570)
    panel:SetPoint("CENTER", UIParent, "CENTER")
    panel:Hide()

    local nav = CreateFrame("Frame", nil, panel)
    nav:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -16)
    nav:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 16)
    nav:SetWidth(144)
    local divider = nav:CreateTexture(nil, "BACKGROUND")
    divider:SetPoint("TOPRIGHT", 8, 0)
    divider:SetPoint("BOTTOMRIGHT", 8, 0)
    divider:SetWidth(1)
    divider:SetColorTexture(1, 1, 1, 0.16)

    local navDefs = {
        { key = "general", label = "General", description = "Scanning and addon display." },
        { key = "pricing", label = "Pricing", description = "Default quantities and material prices." },
        { key = "crafting", label = "Stat fallbacks", description = "Manual values used when a captured profile is unavailable." },
        { key = "nodes", label = "Profession nodes", description = "Captured specialization ranks and manual overrides." },
        { key = "tools", label = "Tools", description = "Reload strategy data and manage the price cache." },
        { key = "about", label = "About", description = "Gold Advisor Midnight contributors and acknowledgments." },
    }

    local pageHost = CreateFrame("Frame", nil, panel)
    pageHost:SetPoint("TOPLEFT", nav, "TOPRIGHT", 28, 0)
    pageHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 14)
    local title = NewText(pageHost, "", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetPoint("TOPRIGHT", 0, 0)
    title:SetTextColor(0.95, 0.95, 0.97)
    local subtitle = NewText(pageHost, "", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -6)
    subtitle:SetTextColor(0.65, 0.65, 0.7)

    -- One scrollbar per page, including About. Its viewport follows the host.
    local pages, navButtons = {}, {}
    local selectedKey = "general"
    local ReflowPages
    for _, def in ipairs(navDefs) do
        local page = CreateFrame("Frame", nil, pageHost)
        page:SetPoint("TOPLEFT", pageHost, "TOPLEFT", 0, -54)
        page:SetPoint("BOTTOMRIGHT", pageHost, "BOTTOMRIGHT", 0, 0)
        page:Hide()
        local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", -24, 0)
        local pageContent = CreateFrame("Frame", nil, scroll)
        pageContent:SetSize(520, 1)
        scroll:SetScrollChild(pageContent)
        local state = { frame = page, scroll = scroll, content = pageContent }
        pages[def.key] = state
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local range = math.max(0, self:GetVerticalScrollRange())
            self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 36)))
        end)
        scroll:HookScript("OnSizeChanged", function() LayoutPage(state) end)
        scroll:HookScript("OnScrollRangeChanged", function(self, _, range)
            if self.ScrollBar then self.ScrollBar:SetShown((range or 0) > 1) end
        end)
        page:SetScript("OnShow", function() LayoutPage(state) end)
    end

    local function SelectSettingsSection(key)
        if not pages[key] then return end
        selectedKey = key
        for _, def in ipairs(navDefs) do
            if def.key == key then
                title:SetText(def.label)
                subtitle:SetText(def.description)
            end
        end
        for pageKey, page in pairs(pages) do
            page.frame:SetShown(pageKey == key)
        end
        for _, entry in ipairs(navButtons) do
            local selected = entry.key == key
            entry.fill:SetShown(selected)
            entry.indicator:SetShown(selected)
            entry.text:SetTextColor(selected and GOLD_R or 0.8,
                selected and GOLD_G or 0.8, selected and GOLD_B or 0.84)
        end
        -- Keep each page's scroll position and pending edits when navigating.
        if ReflowPages then ReflowPages() else LayoutPage(pages[key]) end
    end

    for i, def in ipairs(navDefs) do
        local key = def.key
        local btn = CreateFrame("Button", nil, nav)
        btn:SetSize(144, 36)
        if key == "about" then
            btn:SetPoint("BOTTOMLEFT", 0, 0)
        else
            btn:SetPoint("TOPLEFT", 0, -(i - 1) * 42)
        end
        btn:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        btn:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
        local fill = btn:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        fill:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.10)
        local indicator = btn:CreateTexture(nil, "ARTWORK")
        indicator:SetPoint("TOPLEFT", 0, -4)
        indicator:SetPoint("BOTTOMLEFT", 0, 4)
        indicator:SetWidth(3)
        indicator:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1)
        local text = NewText(btn, def.label)
        text:SetPoint("LEFT", 14, 0)
        text:SetWidth(124)
        btn:SetScript("OnClick", function() SelectSettingsSection(key) end)
        navButtons[#navButtons + 1] = {
            key = key, button = btn, fill = fill, indicator = indicator, text = text,
        }
    end

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

    -- ── Pricing ────────────────────────────────────────────────────────────
    FinalizeContentLayout()
    content = pages.pricing.content
    MakeSectionHeader(content, L["SETTINGS_SECTION_PRICING"])

    local ebFillQty
    local ebLumberPrice
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

    local lblFillQty = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblFillQty:SetText(L["OPT_SHALLOW_FILL_QTY"])

    ebFillQty = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    ebFillQty:SetSize(90, 26)
    ebFillQty:SetAutoFocus(false)
    ebFillQty:SetNumeric(true)
    ebFillQty:SetText(tostring(opts.shallowFillQty or GAM.C.DEFAULT_FILL_QTY))

    local lblRange = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblRange:SetText(L["OPT_SHALLOW_FILL_RANGE"])
    lblRange:SetTextColor(0.55, 0.55, 0.55)
    AddRow(content, lblFillQty, ebFillQty, lblRange, 90)

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

    MakeSectionHeader(content, "Material prices")

    local lblLumberPrice = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblLumberPrice:SetText(L["OPT_LUMBER_PRICE"])

    ebLumberPrice = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    ebLumberPrice:SetSize(90, 26)
    ebLumberPrice:SetAutoFocus(false)
    ebLumberPrice:SetMaxLetters(12)
    do
        local pdb = GAM.GetPatchDB and GAM:GetPatchDB(GAM.C.DEFAULT_PATCH)
        ebLumberPrice:SetText(FormatGoldInput(pdb and pdb.priceOverrides and pdb.priceOverrides[THALASSIAN_LUMBER_ITEM_ID]))
    end

    local lblLumberUnit = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblLumberUnit:SetText(L["OPT_GOLD_EACH"])
    lblLumberUnit:SetTextColor(0.55, 0.55, 0.55)
    AddRow(content, lblLumberPrice, ebLumberPrice, lblLumberUnit, 90)

    local function NormalizeLumberPrice()
        local copper = ParseGoldInput(ebLumberPrice:GetText())
        ebLumberPrice:SetText(FormatGoldInput(copper))
        ebLumberPrice:ClearFocus()
    end
    ebLumberPrice:SetScript("OnEnterPressed", NormalizeLumberPrice)
    ebLumberPrice:SetScript("OnEditFocusLost", NormalizeLumberPrice)
    ebLumberPrice:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["OPT_LUMBER_PRICE_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(L["OPT_LUMBER_PRICE_TIP"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    ebLumberPrice:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Advanced manual stat fallbacks ─────────────────────────────────────
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
    AddRow(content, "Diagnostics", btnLog, "Open the addon log to investigate a problem.", 150)
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
        for _, page in pairs(pages) do
            page.frame:SetPoint("BOTTOMRIGHT", pageHost, "BOTTOMRIGHT", 0, 46)
            LayoutPage(page)
        end
    end
    ReflowPages = function()
        local top = math.max(54, title:GetStringHeight() + subtitle:GetStringHeight() + 24)
        for _, page in pairs(pages) do
            page.frame:SetPoint("TOPLEFT", pageHost, "TOPLEFT", 0, -top)
            LayoutPage(page)
        end
    end
    panel:HookScript("OnSizeChanged", ReflowPages)
    SelectSettingsSection("general")
    ReflowPages()

    -- ── Apply logic ────────────────────────────────────────────────────────
    local function ApplySettings()
        local currentOpts = GetOpts()
        local prevQty = GetOptionValue(currentOpts, "shallowFillQty", GAM.C.DEFAULT_FILL_QTY)
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

        if globalStartingCrafts ~= prevStartingCrafts then
            GAM.Log.Info("Global starting crafts changed: %d -> %d",
                prevStartingCrafts, globalStartingCrafts)
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
        ebGlobalStartingCrafts:SetText(tostring(
            (GAM.State and GAM.State.GetGlobalStartingCrafts
                and GAM.State.GetGlobalStartingCrafts()) or GAM.C.DEFAULT_STARTING_CRAFTS))
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
        SelectSettingsSection(selectedKey)
        ReflowPages()
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

    if not nodeCaptureUnsubscribe
            and GAM.CraftingStats
            and GAM.CraftingStats.AddProfessionNodeCaptureListener then
        nodeCaptureUnsubscribe = GAM.CraftingStats.AddProfessionNodeCaptureListener(function()
            if panel and panel:IsShown() and panel._refreshProfessionNodes then
                panel._refreshProfessionNodes()
            end
        end)
    end

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
        wrapper:SetSize(800, 640)
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
        p:SetPoint("BOTTOMRIGHT", wrapper, "BOTTOMRIGHT", -14, 14)
        wrapper:HookScript("OnShow", function() p:Show() end)
        p:Show()

        if p._setStandalone then p._setStandalone() end
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

function SettingsMod.Refresh()
    if panel and panel._refreshGlobalStartingCrafts then
        panel._refreshGlobalStartingCrafts()
    end
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
