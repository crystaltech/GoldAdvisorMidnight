-- GoldAdvisorMidnight/UI/SettingsLayout.lua
-- Shared page layout for Settings and the Debug Log: vertical navigation,
-- one scroll viewport per page, section cards, and measured label/control rows.
-- Reference principles: Common Region / Proximity / Fitts / Hick (lawsofux.com),
-- DRY / YAGNI (lawsofsoftwareengineering.com).
-- Module: GAM.UI.SettingsLayout

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}
local Layout = {}
GAM.UI.SettingsLayout = Layout

-- Gold accent color used throughout
local GOLD_R, GOLD_G, GOLD_B = 1.0, 0.82, 0.0
Layout.GOLD = { GOLD_R, GOLD_G, GOLD_B }

-- Unique name counter so _G[name.."Low"] / _G[name.."Text"] always resolve.
local widgetCount = 0
function Layout.NextWidgetName(prefix)
    widgetCount = widgetCount + 1
    return GAM.RuntimeName("GAMSettings_" .. prefix .. widgetCount)
end

-- Layout is measured from the current canvas width; no saved keys move.
function Layout.NewText(parent, text, style)
    local fs = parent:CreateFontString(nil, "OVERLAY", style or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText(text or "")
    return fs
end
local NewText = Layout.NewText

local function AddLayoutItem(parent, item)
    parent._gamLayout = parent._gamLayout or {}
    parent._gamLayout[#parent._gamLayout + 1] = item
    return item
end

function Layout.MakeSectionHeader(parent, text)
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

function Layout.AddText(parent, fs)
    if type(fs) == "string" then fs = NewText(parent, fs, "GameFontHighlightSmall") end
    fs:SetTextColor(0.72, 0.72, 0.76)
    return AddLayoutItem(parent, { kind = "text", text = fs })
end

function Layout.AddRow(parent, label, control, help, controlWidth, minHeight)
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
local AddRow = Layout.AddRow

function Layout.AddCustom(parent, frame, layout)
    return AddLayoutItem(parent, { kind = "custom", frame = frame, layout = layout })
end

function Layout.LayoutPage(page)
    if page.layingOut or page.plain then return end
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
local LayoutPage = Layout.LayoutPage

function Layout.MakeSlider(parent, label, tip, minV, maxV, step)
    local group = CreateFrame("Frame", nil, parent)
    group:SetSize(170, 48)
    local name = Layout.NextWidgetName("Slider")
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

function Layout.MakeCheckbox(parent, label)
    local name = Layout.NextWidgetName("CB")
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    if _G[name .. "Text"] then _G[name .. "Text"]:SetText("") end
    AddRow(parent, label, cb)
    return cb
end

function Layout.MakeButton(parent, label, w, x, y)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w, 28)
    if x and y then btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y) end
    btn:SetText(label)
    return btn
end

function Layout.MeasureButtonWidth(parent, text, minW, maxW, padding)
    parent._gamMeasureFS = parent._gamMeasureFS or parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local fs = parent._gamMeasureFS
    fs:Hide()
    fs:SetText(text or "")
    local w = math.ceil(fs:GetStringWidth() + (padding or 24))
    if minW and w < minW then w = minW end
    if maxW and w > maxW then w = maxW end
    return w
end

function Layout.LayoutButtonsTop(parent, buttons, topY, cfg)
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

-- Navigation, page title/subtitle, and one page per nav entry.
-- navDefs: { key, label, description, plain? }. A plain page has no scroll
-- viewport; its `content` frame fills the page and lays itself out.
-- opts.bottomKey pins that entry to the bottom of the navigation.
function Layout.CreateShell(parent, navDefs, opts)
    opts = opts or {}
    local shell = { pages = {}, navButtons = {}, selected = navDefs[1].key, bottomInset = 0 }

    local nav = CreateFrame("Frame", nil, parent)
    nav:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -16)
    nav:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 16)
    nav:SetWidth(144)
    local divider = nav:CreateTexture(nil, "BACKGROUND")
    divider:SetPoint("TOPRIGHT", 8, 0)
    divider:SetPoint("BOTTOMRIGHT", 8, 0)
    divider:SetWidth(1)
    divider:SetColorTexture(1, 1, 1, 0.16)

    local pageHost = CreateFrame("Frame", nil, parent)
    pageHost:SetPoint("TOPLEFT", nav, "TOPRIGHT", 28, 0)
    pageHost:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 14)
    local title = NewText(pageHost, "", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetPoint("TOPRIGHT", 0, 0)
    title:SetTextColor(0.95, 0.95, 0.97)
    local subtitle = NewText(pageHost, "", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -6)
    subtitle:SetTextColor(0.65, 0.65, 0.7)
    shell.nav, shell.pageHost, shell.title, shell.subtitle = nav, pageHost, title, subtitle

    -- One scrollbar per page. Its viewport follows the host.
    for _, def in ipairs(navDefs) do
        local page = CreateFrame("Frame", nil, pageHost)
        page:SetPoint("TOPLEFT", pageHost, "TOPLEFT", 0, -54)
        page:SetPoint("BOTTOMRIGHT", pageHost, "BOTTOMRIGHT", 0, 0)
        page:Hide()
        local state = { frame = page, plain = def.plain }
        if def.plain then
            state.content = page
        else
            local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", 0, 0)
            scroll:SetPoint("BOTTOMRIGHT", -24, 0)
            local pageContent = CreateFrame("Frame", nil, scroll)
            pageContent:SetSize(520, 1)
            scroll:SetScrollChild(pageContent)
            state.scroll, state.content = scroll, pageContent
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
        shell.pages[def.key] = state
    end

    function shell.Reflow()
        local top = math.max(54, title:GetStringHeight() + subtitle:GetStringHeight() + 24)
        for _, page in pairs(shell.pages) do
            page.frame:SetPoint("TOPLEFT", pageHost, "TOPLEFT", 0, -top)
            page.frame:SetPoint("BOTTOMRIGHT", pageHost, "BOTTOMRIGHT", 0, shell.bottomInset)
            LayoutPage(page)
        end
    end

    -- Space reserved below the pages, e.g. for a fixed footer.
    function shell.SetBottomInset(inset)
        shell.bottomInset = inset or 0
        shell.Reflow()
    end

    function shell.Select(key)
        if not shell.pages[key] then return end
        shell.selected = key
        for _, def in ipairs(navDefs) do
            if def.key == key then
                title:SetText(def.label)
                subtitle:SetText(def.description)
            end
        end
        for pageKey, page in pairs(shell.pages) do
            page.frame:SetShown(pageKey == key)
        end
        for _, entry in ipairs(shell.navButtons) do
            local selected = entry.key == key
            entry.fill:SetShown(selected)
            entry.indicator:SetShown(selected)
            entry.text:SetTextColor(selected and GOLD_R or 0.8,
                selected and GOLD_G or 0.8, selected and GOLD_B or 0.84)
        end
        -- Keep each page's scroll position and pending edits when navigating.
        shell.Reflow()
        if opts.onSelect then opts.onSelect(key) end
    end

    for i, def in ipairs(navDefs) do
        local key = def.key
        local btn = CreateFrame("Button", nil, nav)
        btn:SetSize(144, 36)
        if key == opts.bottomKey then
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
        btn:SetScript("OnClick", function() shell.Select(key) end)
        shell.navButtons[#shell.navButtons + 1] = {
            key = key, button = btn, fill = fill, indicator = indicator, text = text,
        }
    end

    parent:HookScript("OnSizeChanged", shell.Reflow)
    return shell
end
