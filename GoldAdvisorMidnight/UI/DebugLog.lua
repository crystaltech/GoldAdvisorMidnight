-- GoldAdvisorMidnight/UI/DebugLog.lua
-- Debug Log window in the Settings layout: a filterable Log page and a
-- Troubleshooting page whose buttons run the GAM.Diagnostics reports.
-- Module: GAM.UI.DebugLog

local ADDON_NAME, GAM = ...
local DebugLog = {}
GAM.UI.DebugLog = DebugLog
local WindowManager = GAM.UI.WindowManager

local WIN_W, WIN_H = 820, 580
local frame
local Build  -- forward declaration (the export popup references Build before its definition)

local function T(key, fallback)
    return (GAM.L and GAM.L[key]) or fallback
end

local function GetUIScale()
    return (GAM.db and GAM.db.options and GAM.db.options.uiScale) or 1.0
end

-- ===== ARP Export popup =====

local arpPopup
local arpPopupEB
local arpPopupSF
local arpPopupSizer
local arpPopupTitle

local function RefreshARPExportPopupLayout()
    if not (arpPopupEB and arpPopupSF and arpPopupSizer) then return end
    local width = math.max(40, (arpPopupSF:GetWidth() or 0) - 10)
    arpPopupEB:SetWidth(width)
    arpPopupSizer:SetWidth(width)
    arpPopupSizer:SetText(arpPopupEB:GetText() or "")
    local textHeight = arpPopupSizer:GetStringHeight() or 0
    arpPopupEB:SetHeight(math.max((arpPopupSF:GetHeight() or 0), textHeight + 16))
end

local function AddResizeGrip(window, onResize)
    window:SetResizable(true)
    if window.SetResizeBounds then window:SetResizeBounds(440, 220, 1400, 1000) end
    local grip = CreateFrame("Button", nil, window)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then window:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function() window:StopMovingOrSizing() end)
    window:HookScript("OnSizeChanged", onResize)
end

local function BuildARPExportPopup()
    arpPopup = CreateFrame("Frame", GAM.RuntimeName("GAMARPExportPopup"), UIParent, "BackdropTemplate")
    arpPopup:SetSize(540, 380)
    arpPopup:SetPoint("CENTER")
    arpPopup:SetScale(GetUIScale())
    arpPopup:SetMovable(true)
    arpPopup:EnableMouse(true)
    arpPopup:RegisterForDrag("LeftButton")
    arpPopup:SetScript("OnDragStart", arpPopup.StartMoving)
    arpPopup:SetScript("OnDragStop",  arpPopup.StopMovingOrSizing)
    arpPopup:SetClampedToScreen(true)
    -- Same chrome as the Debug Log window.
    local common = GAM.UI and GAM.UI.MainWindowCommon
    arpPopup:SetBackdrop((common and common.THIN_BACKDROP) or {
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    arpPopup:SetBackdropColor(0.055, 0.055, 0.062, 1)
    arpPopup:SetBackdropBorderColor(0.48, 0.40, 0.16, 0.95)
    arpPopup:Hide()
    WindowManager.Register(arpPopup, "debug", { owner = frame, levelOffset = 8 })

    -- Title
    local title = arpPopup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", arpPopup, "TOPLEFT", 18, -14)
    title:SetPoint("RIGHT", arpPopup, "RIGHT", -36, 0)
    title:SetJustifyH("LEFT")
    title:SetText((GAM.L and GAM.L["BTN_ARP_EXPORT"]) or "ARP Export")
    title:SetTextColor(1, 0.82, 0, 1)
    arpPopupTitle = title
    local hint = arpPopup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetText(T("DBG_COPY_HINT", "Text is selected; press Ctrl+C to copy."))
    hint:SetTextColor(0.65, 0.65, 0.7)

    -- Close button (top-right X)
    local closeBtn = CreateFrame("Button", nil, arpPopup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", arpPopup, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() arpPopup:Hide() end)

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", nil, arpPopup, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     arpPopup, "TOPLEFT",     14, -58)
    sf:SetPoint("BOTTOMRIGHT", arpPopup, "BOTTOMRIGHT", -30, 14)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 18)))
    end)

    -- EditBox inside scroll frame
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetWidth(sf:GetWidth() - 10)
    eb:SetScript("OnEscapePressed", function() arpPopup:Hide() end)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnTextChanged", function()
        RefreshARPExportPopupLayout()
    end)
    sf:SetScrollChild(eb)
    arpPopupEB = eb
    arpPopupSF = sf

    local sizer = sf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sizer:SetJustifyH("LEFT")
    sizer:SetJustifyV("TOP")
    sizer:Hide()
    arpPopupSizer = sizer
    AddResizeGrip(arpPopup, function() RefreshARPExportPopupLayout() end)

    sf:SetScript("OnSizeChanged", function()
        RefreshARPExportPopupLayout()
    end)
end

local function ShowTextExportPopup(title, text)
    if not frame then Build() end
    if not arpPopup then BuildARPExportPopup() end
    if arpPopupTitle then arpPopupTitle:SetText(title or "Export") end
    arpPopupSF:SetVerticalScroll(0)
    arpPopupEB:SetText(text or "")
    RefreshARPExportPopupLayout()
    arpPopup:Show()
    WindowManager.Present(arpPopup, nil, { owner = frame, levelOffset = 8 })
    arpPopupEB:SetFocus()
    arpPopupEB:HighlightText()
end

local function ShowARPExportPopup(text)
    ShowTextExportPopup((GAM.L and GAM.L["BTN_ARP_EXPORT"]) or "ARP Export", text)
end

-- ===== Log page state =====
-- Filters are per session: opening the window later starts from "show all".
local LEVEL_STYLE = {
    ERROR = { key = "DBG_LEVEL_ERROR", label = "Errors", color = "ff5555" },
    WARN = { key = "DBG_LEVEL_WARN", label = "Warnings", color = "ffaa33" },
    INFO = { key = "DBG_LEVEL_INFO", label = "Info", color = "e6e6e6" },
    DEBUG = { key = "DBG_LEVEL_DEBUG", label = "Debug", color = "8fb8de" },
    VERBOSE = { key = "DBG_LEVEL_VERBOSE", label = "Verbose", color = "8a8a8a" },
}
local CAPTURE_LABELS = {
    [0] = { "DBG_CAPTURE_OFF", "Off" }, { "DBG_CAPTURE_INFO", "Info" },
    { "DBG_CAPTURE_DEBUG", "Debug" }, { "DBG_CAPTURE_VERBOSE", "Verbose" },
}
local view = {
    levels = { ERROR = true, WARN = true, INFO = true, DEBUG = true, VERBOSE = true },
    area = nil,       -- nil shows every area
    search = "",
    frozen = false,   -- Pause freezes the view; entries are still recorded
    snapshot = nil,   -- entries shown while paused
    pending = 0,
    renderQueued = false,
}
local ui = {}

local function Matches(entry)
    if not view.levels[entry.level] then return false end
    if view.area and entry.area ~= view.area then return false end
    if view.search ~= "" then
        local haystack = (entry.text .. " " .. entry.area):lower()
        if not haystack:find(view.search, 1, true) then return false end
    end
    return true
end

local function ColorLine(entry)
    local style = LEVEL_STYLE[entry.level] or LEVEL_STYLE.INFO
    local area = entry.area ~= GAM.Log.GENERAL_AREA and ("|cffd4b44a[" .. entry.area .. "]|r ") or ""
    return string.format("|cff777777%s|r |cff%s%s|r %s%s", entry.time, style.color, entry.level, area, entry.text)
end

local function ScrollLogToBottom()
    if not ui.scroll then return end
    C_Timer.After(0, function()
        ui.scroll:SetVerticalScroll(ui.scroll:GetVerticalScrollRange())
    end)
end

local function RefreshFilterLabels(summary)
    for level, button in pairs(ui.levelButtons or {}) do
        local style = LEVEL_STYLE[level]
        local n = summary.levels[level] or 0
        button:SetText(string.format("%s (%d)", T(style.key, style.label), n))
        local fs = button:GetFontString()
        if fs then
            if view.levels[level] then fs:SetTextColor(1, 0.82, 0) else fs:SetTextColor(0.45, 0.45, 0.45) end
        end
    end
    if ui.areaButton then
        ui.areaButton:SetText((view.area or T("DBG_ALL_AREAS", "All areas")) .. "  v")
    end
end

-- A multi-line EditBox in a ScrollFrame does not size itself: give it the
-- viewport width and the measured text height (as the export popup does),
-- otherwise the text is laid out in a zero-sized box and nothing shows.
local function SizeLogText()
    if not (ui.scroll and ui.editBox and ui.sizer) then return end
    local width = math.max(100, (ui.scroll:GetWidth() or 0) - 4)
    ui.editBox:SetWidth(width)
    ui.sizer:SetWidth(width)
    ui.sizer:SetText(ui.editBox:GetText() or "")
    ui.editBox:SetHeight(math.max(ui.scroll:GetHeight() or 0, (ui.sizer:GetStringHeight() or 0) + 16))
end

local function RenderLog()
    view.renderQueued = false
    if not (frame and frame:IsShown() and ui.editBox) then return end
    local entries = view.frozen and view.snapshot or GAM.Log.GetEntries()
    local lines = {}
    for _, entry in ipairs(entries) do
        if Matches(entry) then lines[#lines + 1] = ColorLine(entry) end
    end
    local range = ui.scroll:GetVerticalScrollRange()
    local atBottom = range <= 0 or ui.scroll:GetVerticalScroll() >= range - 4
    ui.editBox:SetText(#lines > 0 and table.concat(lines, "\n")
        or ("|cff888888" .. T("DBG_NO_MATCHES", "No log entries match the current filters.") .. "|r"))
    SizeLogText()
    RefreshFilterLabels(GAM.Log.GetSummary())
    local status = string.format(T("DBG_STATUS_SHOWING", "Showing %d of %d entries"), #lines, #entries)
    if view.frozen then
        status = status .. "  |cffffaa33" .. string.format(T("DBG_STATUS_PAUSED", "Paused - %d new"), view.pending) .. "|r"
    end
    ui.status:SetText(status)
    if atBottom then ScrollLogToBottom() end
end

-- Batches bursts of new entries (a scan writes many) into one redraw.
local function QueueRender()
    if view.renderQueued then return end
    view.renderQueued = true
    C_Timer.After(0.15, RenderLog)
end

local function ShowFullLogExport()
    ShowTextExportPopup(T("DBG_COPY_TITLE", "Debug Log"), GAM.Log.GetAllText())
end

-- ===== Log page =====
local function BuildLogPage(page, Layout, styleButton)
    local filterBar = CreateFrame("Frame", nil, page)
    filterBar:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    filterBar:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    filterBar:SetHeight(56)

    ui.levelButtons = {}
    local levelOrder = {}
    for _, level in ipairs(GAM.Log.LEVELS) do
        local button = CreateFrame("Button", nil, filterBar, "UIPanelButtonTemplate")
        button:SetSize(104, 22)
        button:SetScript("OnClick", function()
            view.levels[level] = not view.levels[level]
            RenderLog()
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(T("DBG_LEVEL_TOGGLE_TIP", "Click to show or hide these entries."), 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        styleButton(button)
        ui.levelButtons[level] = button
        levelOrder[#levelOrder + 1] = button
    end

    -- Area picker: a small addon-owned list (Blizzard menus can open behind
    -- this FULLSCREEN_DIALOG window).
    local areaButton = CreateFrame("Button", nil, filterBar, "UIPanelButtonTemplate")
    areaButton:SetSize(150, 22)
    styleButton(areaButton)
    ui.areaButton = areaButton
    local areaMenu = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    areaMenu:SetPoint("TOPLEFT", areaButton, "BOTTOMLEFT", 0, -2)
    areaMenu:SetFrameLevel(frame:GetFrameLevel() + 40)
    areaMenu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    areaMenu:SetBackdropColor(0.035, 0.035, 0.035, 0.98)
    areaMenu:SetBackdropBorderColor(0.48, 0.40, 0.16, 0.9)
    areaMenu:Hide()
    local areaRows = {}
    local function OpenAreaMenu()
        local choices = { false }
        for _, area in ipairs(GAM.Log.GetSummary().areas) do choices[#choices + 1] = area end
        for index, area in ipairs(choices) do
            local row = areaRows[index]
            if not row then
                row = CreateFrame("Button", nil, areaMenu, "UIPanelButtonTemplate")
                row:SetSize(146, 20)
                row:SetPoint("TOPLEFT", areaMenu, "TOPLEFT", 2, -2 - ((index - 1) * 22))
                styleButton(row)
                areaRows[index] = row
            end
            row:SetText(area or T("DBG_ALL_AREAS", "All areas"))
            row:SetScript("OnClick", function()
                view.area = area or nil
                areaMenu:Hide()
                RenderLog()
            end)
            row:Show()
        end
        for index = #choices + 1, #areaRows do areaRows[index]:Hide() end
        areaMenu:SetSize(150, 4 + (#choices * 22))
        areaMenu:Show()
    end
    areaButton:SetScript("OnClick", function()
        if areaMenu:IsShown() then areaMenu:Hide() else OpenAreaMenu() end
    end)
    page:HookScript("OnHide", function() areaMenu:Hide() end)

    local okSearch, search = pcall(CreateFrame, "EditBox", nil, filterBar, "SearchBoxTemplate")
    if not okSearch or not search then
        search = CreateFrame("EditBox", nil, filterBar, "InputBoxTemplate")
    end
    search:SetSize(200, 22)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function(self)
        view.search = tostring(self:GetText() or ""):lower():match("^%s*(.-)%s*$")
        QueueRender()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if search.Instructions then search.Instructions:SetText(T("DBG_SEARCH", "Search the log")) end

    local function LayoutFilterBar()
        local width = filterBar:GetWidth()
        if not width or width < 100 then return end
        local used = Layout.LayoutButtonsTop(filterBar, levelOrder, 0,
            { left = 0, right = width, gap = 6, rowGap = 6, align = "left", height = 22 }).usedHeight
        areaButton:ClearAllPoints()
        areaButton:SetPoint("TOPLEFT", filterBar, "TOPLEFT", 0, -used - 8)
        search:ClearAllPoints()
        search:SetPoint("LEFT", areaButton, "RIGHT", 14, 0)
        search:SetPoint("RIGHT", filterBar, "RIGHT", -4, 0)
        filterBar:SetHeight(used + 8 + 22)
        if ui.logBox then
            ui.logBox:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(used + 8 + 22 + 8))
        end
    end
    filterBar:SetScript("OnSizeChanged", LayoutFilterBar)
    page:HookScript("OnShow", LayoutFilterBar)

    -- Footer: view controls and the entry count.
    local footer = CreateFrame("Frame", nil, page)
    footer:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(26)
    local function FooterButton(label, width)
        local button = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetText(label)
        styleButton(button)
        return button
    end
    local pauseBtn = FooterButton(T("BTN_PAUSE_LOG", "Pause"), 90)
    pauseBtn:SetPoint("LEFT", footer, "LEFT", 0, 0)
    local clearBtn = FooterButton(T("BTN_CLEAR_LOG", "Clear"), 90)
    clearBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 6, 0)
    local copyBtn = FooterButton(T("BTN_COPY_LOG", "Copy All"), 100)
    copyBtn:SetPoint("LEFT", clearBtn, "RIGHT", 6, 0)
    ui.status = Layout.NewText(footer, "", "GameFontHighlightSmall")
    ui.status:SetPoint("LEFT", copyBtn, "RIGHT", 12, 0)
    ui.status:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
    ui.status:SetJustifyH("RIGHT")
    ui.status:SetWordWrap(false)
    ui.status:SetTextColor(0.65, 0.65, 0.7)

    pauseBtn:SetScript("OnClick", function()
        view.frozen = not view.frozen
        view.snapshot = view.frozen and GAM.Log.GetEntries() or nil
        view.pending = 0
        pauseBtn:SetText(view.frozen and T("BTN_RESUME_LOG", "Resume") or T("BTN_PAUSE_LOG", "Pause"))
        RenderLog()
    end)
    clearBtn:SetScript("OnClick", function()
        view.pending = 0
        GAM.Log.Clear()
        if view.frozen then view.snapshot = GAM.Log.GetEntries() end
        RenderLog()
    end)
    copyBtn:SetScript("OnClick", ShowFullLogExport)

    -- Log text: an EditBox keeps it selectable; typing is discarded.
    -- Anchored to the page only (not between sibling frames, which the client
    -- did not resolve); the top offset follows the filter bar's height.
    -- Named so it can be inspected in game with /run or /fstack.
    local logBox = CreateFrame("Frame", GAM.RuntimeName("GAMDebugLogBox"), page, "BackdropTemplate")
    logBox:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(filterBar:GetHeight() + 8))
    logBox:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 34)
    logBox:SetFrameLevel(page:GetFrameLevel() + 1)
    logBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    logBox:SetBackdropColor(0.03, 0.03, 0.035, 0.9)
    logBox:SetBackdropBorderColor(0.4, 0.4, 0.43, 0.6)
    ui.logBox = logBox
    local scroll = CreateFrame("ScrollFrame", GAM.RuntimeName("GAMDebugLogScroll"), logBox, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", logBox, "TOPLEFT", 8, -6)
    scroll:SetPoint("BOTTOMRIGHT", logBox, "BOTTOMRIGHT", -28, 6)
    local editBox = CreateFrame("EditBox", GAM.RuntimeName("GAMDebugLogText"), scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnTextChanged", function(_, userInput)
        if userInput then RenderLog() end
    end)
    scroll:SetScrollChild(editBox)
    local sizer = scroll:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sizer:SetJustifyH("LEFT")
    sizer:SetJustifyV("TOP")
    sizer:Hide()
    ui.scroll, ui.editBox, ui.sizer = scroll, editBox, sizer
    scroll:SetScript("OnSizeChanged", SizeLogText)
end

-- ===== Troubleshooting page =====
local function BuildToolsPage(content, Layout, shell, styleButton)
    local function ActionButton(label)
        local button = Layout.MakeButton(content, label, 150)
        styleButton(button)
        return button
    end
    -- Reports write to the log, then show it so the result is in view.
    local function Report(label, name, help, fn)
        local button = ActionButton(label)
        button:SetScript("OnClick", function()
            GAM.Diagnostics.Run(fn)
            shell.Select("log")
            RenderLog()
            ScrollLogToBottom()
        end)
        Layout.AddRow(content, name, button, help, 150)
        return button
    end
    local writeLabel = T("DBG_WRITE_REPORT", "Write to log")

    Layout.MakeSectionHeader(content, T("DBG_SECTION_CAPTURE", "Log detail"))
    local captureBtn = ActionButton("")
    local function RefreshCapture()
        local label = CAPTURE_LABELS[GAM.Log.GetLevel()] or CAPTURE_LABELS[1]
        captureBtn:SetText(T(label[1], label[2]))
    end
    -- Cycle button, matching Settings: no pop-out menus inside scroll frames.
    captureBtn:SetScript("OnClick", function()
        local nextLevel = (GAM.Log.GetLevel() + 1) % 4
        GAM.Log.SetLevel(nextLevel)
        local opts = (GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options)
        if opts then opts.debugVerbosity = nextLevel end
        RefreshCapture()
    end)
    Layout.AddRow(content, T("DBG_CAPTURE_LEVEL", "Capture level"), captureBtn,
        T("DBG_CAPTURE_HELP", "Warnings and errors are always recorded. Raise this to Debug or Verbose while you reproduce a problem, then set it back to Info."), 150)
    ui.refreshCapture = RefreshCapture

    Layout.MakeSectionHeader(content, T("DBG_SECTION_STRATEGY", "Selected strategy"))
    Report(writeLabel, T("DBG_SCAN_DUMP", "Prices and formula"),
        T("DBG_SCAN_DUMP_HELP", "Listings, stored prices and formula inputs for the strategy selected in the main window."),
        GAM.Diagnostics.DumpSelectedStrategyScans)

    Layout.MakeSectionHeader(content, T("DBG_SECTION_AH", "Auction House"))
    Report(writeLabel, T("DBG_SCAN_RESULTS", "Last scan results"),
        T("DBG_SCAN_RESULTS_HELP", "Outcome, attempts and timing for each item in this session's scans, with details for anything that failed."),
        GAM.Diagnostics.DumpScanDiagnostics)

    Layout.MakeSectionHeader(content, T("DBG_SECTION_STATS", "Crafting stats"))
    Report(writeLabel, T("DBG_GEAR_SETS", "Gear sets"),
        T("DBG_GEAR_SETS_HELP", "Saved Multicraft and Resourcefulness sets on this character, with their items and stats."),
        GAM.Diagnostics.DumpGearSets)
    Report(writeLabel, T("DBG_STAT_AUDIT", "Stat sources"),
        T("DBG_STAT_AUDIT_HELP", "Which stat profiles use captured, manual or default values, and which still need a recipe capture."),
        function() GAM.CraftingStats.DumpAudit() end)
    Report(writeLabel, T("DBG_STAT_PROFILES", "Stat profiles"),
        T("DBG_STAT_PROFILES_HELP", "Every stat profile with its Multicraft and Resourcefulness values."),
        function() GAM.CraftingStats.DumpProfiles() end)
    Report(writeLabel, T("DBG_CRAFT_RESULTS", "Craft results"),
        T("DBG_CRAFT_RESULTS_HELP", "Multicraft procs and Resourcefulness refunds recorded from your crafts, compared with what GAM expected."),
        function() GAM.CraftStats.DumpReport() end)

    Layout.MakeSectionHeader(content, T("DBG_SECTION_RECIPES", "Recipe data"))
    -- Audits write their summary and every problem row to the log; the full
    -- table stays available from "Copy last audit".
    Report(T("DBG_RUN_AUDIT", "Run audit"), T("DBG_AUDIT_OPEN", "Recipe audit: open profession"),
        T("DBG_AUDIT_OPEN_HELP", "Compares every strategy of the open profession with the live recipe. Open the profession window first."),
        function() GAM.RecipeAudit.Run("", { inLog = true }) end)
    Report(T("DBG_RUN_AUDIT", "Run audit"), T("DBG_AUDIT_ALL", "Recipe audit: all professions"),
        T("DBG_AUDIT_ALL_HELP", "Same check for every strategy; recipes this character has not learned are reported as such."),
        function() GAM.RecipeAudit.Run("all", { inLog = true }) end)
    local copyAudit = ActionButton(T("BTN_COPY_LOG", "Copy All"))
    copyAudit:SetScript("OnClick", function()
        local report = GAM.RecipeAudit.GetLastReport and GAM.RecipeAudit.GetLastReport()
        if report then
            ShowTextExportPopup(T("DBG_AUDIT_REPORT", "Recipe audit report"), report)
        else
            print("|cffff8800[GAM]|r " .. T("DBG_NO_AUDIT", "Run a recipe audit first."))
        end
    end)
    Layout.AddRow(content, T("DBG_AUDIT_COPY", "Copy last audit"), copyAudit,
        T("DBG_AUDIT_COPY_HELP", "Opens the full table from the last recipe audit as plain text."), 150)
    Report(writeLabel, T("DBG_ITEM_IDS", "Item IDs"),
        T("DBG_ITEM_IDS_HELP", "Checks every item ID against its name. ??? means the item is not loaded yet; visit the Auction House and try again."),
        GAM.Diagnostics.DumpItemIDs)

    Layout.MakeSectionHeader(content, T("DBG_SECTION_SUPPORT", "Support"))
    Report(writeLabel, T("DBG_SUPPORT_SUMMARY", "Support summary"),
        T("DBG_SUPPORT_SUMMARY_HELP", "Addon and client versions, installed integrations and error counts, for a bug report."),
        GAM.Diagnostics.DumpSupportSummary)
    local copyAll = ActionButton(T("BTN_COPY_LOG", "Copy All"))
    copyAll:SetScript("OnClick", ShowFullLogExport)
    Layout.AddRow(content, T("DBG_COPY_LOG", "Copy the log"), copyAll,
        T("DBG_COPY_LOG_HELP", "Opens the full log as plain text to copy with Ctrl+C."), 150)
    local exportBtn = ActionButton(T("DBG_EXPORT", "Export"))
    exportBtn:SetScript("OnClick", function() DebugLog.ShowARPExport() end)
    Layout.AddRow(content, T("BTN_ARP_EXPORT", "Spreadsheet Export"), exportBtn,
        T("DBG_EXPORT_HELP", "Current prices for every strategy item in the spreadsheet import format."), 150)

    Layout.MakeSectionHeader(content, T("DBG_SECTION_MAINTENANCE", "Maintenance"))
    local clearCache = ActionButton(T("BTN_CLEAR_CACHE", "Clear Cache"))
    clearCache:SetScript("OnClick", function()
        if GAM.State and GAM.State.ClearPriceCache then GAM.State.ClearPriceCache() end
        GAM.Log.Info("Price cache cleared.")
        print("|cffff8800[GAM]|r " .. T("MSG_CACHE_CLEARED", "Price cache cleared."))
    end)
    Layout.AddRow(content, T("DBG_PRICE_CACHE", "Price cache"), clearCache,
        T("DBG_PRICE_CACHE_HELP", "Clears saved prices. Scan again afterwards for fresh results."), 150)
    local reload = ActionButton(T("BTN_RELOAD_DATA", "Reload Data"))
    reload:SetScript("OnClick", function()
        GAM.Importer.Init()
        GAM.Log.Info("Data reloaded.")
        print("|cffff8800[GAM]|r " .. T("MSG_DATA_RELOADED", "Strategy data reloaded."))
    end)
    Layout.AddRow(content, T("DBG_STRATEGY_DATA", "Strategy data"), reload,
        T("DBG_STRATEGY_DATA_HELP", "Reloads the bundled strategy data without a /reload."), 150)
end

-- ===== Build frame =====
Build = function()
    local Layout = assert(GAM.UI.SettingsLayout, "DebugLog requires SettingsLayout")
    local common = GAM.UI and GAM.UI.MainWindowCommon
    local function styleButton(button)
        if common and common.StyleComfortableButton then common.StyleComfortableButton(button, false) end
    end

    frame = CreateFrame("Frame", GAM.RuntimeName("GoldAdvisorMidnightDebugLog"), UIParent, "BackdropTemplate")
    frame:SetSize(WIN_W, WIN_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 120, -40)
    frame:SetScale(GetUIScale())
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop((common and common.THIN_BACKDROP) or {
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.055, 0.055, 0.062, 1)
    frame:SetBackdropBorderColor(0.48, 0.40, 0.16, 0.95)
    frame:Hide()
    WindowManager.Register(frame, "debug")
    if UISpecialFrames then table.insert(UISpecialFrames, frame:GetName()) end

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -14)
    title:SetText(T("LOG_TITLE", "Debug Log"))
    title:SetTextColor(Layout.GOLD[1], Layout.GOLD[2], Layout.GOLD[3])
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    local host = CreateFrame("Frame", nil, frame)
    host:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -40)
    host:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    local shell = Layout.CreateShell(host, {
        { key = "log", label = T("DBG_PAGE_LOG", "Log"), plain = true,
            description = T("DBG_PAGE_LOG_DESC", "Recent addon messages. Filter by severity, area or text.") },
        { key = "tools", label = T("DBG_PAGE_TOOLS", "Troubleshooting"),
            description = T("DBG_PAGE_TOOLS_DESC", "Run a check; its results are written to the log.") },
    }, {
        onSelect = function(key) if key == "log" then RenderLog() end end,
    })
    BuildLogPage(shell.pages.log.content, Layout, styleButton)
    BuildToolsPage(shell.pages.tools.content, Layout, shell, styleButton)
    Layout.LayoutPage(shell.pages.tools)
    AddResizeGrip(frame, function() shell.Reflow() end)
    if frame.SetResizeBounds then frame:SetResizeBounds(700, 460, 1400, 1000) end

    GAM.Log.AddListener(function()
        if not frame:IsShown() then return end
        if view.frozen then view.pending = view.pending + 1 end
        QueueRender()
    end)

    frame:SetScript("OnShow", function()
        WindowManager.Present(frame)
        if ui.refreshCapture then ui.refreshCapture() end
        shell.Select(shell.selected)
        -- Sizes settle after the first frame; lay the text out again then.
        C_Timer.After(0, function() RenderLog(); ScrollLogToBottom() end)
    end)
end

-- ===== Public API =====
function DebugLog.ShowARPExport()
    ShowARPExportPopup(GAM.Diagnostics.GenerateARPExport())
end

function DebugLog.ShowTextExport(title, text)
    ShowTextExportPopup(title, text)
end

function DebugLog.DumpItemIDs()
    GAM.Diagnostics.Run(GAM.Diagnostics.DumpItemIDs)
end

function DebugLog.DumpSelectedStrategyScans()
    GAM.Diagnostics.Run(GAM.Diagnostics.DumpSelectedStrategyScans)
end

function DebugLog.Show()
    if not frame then Build() end
    frame:Show()
    WindowManager.Present(frame)
end

function DebugLog.Hide()
    if frame then frame:Hide() end
end

function DebugLog.Toggle()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else frame:Show(); WindowManager.Present(frame) end
end

function DebugLog.IsShown()
    return frame and frame:IsShown()
end
