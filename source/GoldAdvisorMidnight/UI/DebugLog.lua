-- GoldAdvisorMidnight/UI/DebugLog.lua
-- Scrollable, copyable debug log window backed by Log.lua ring buffer.
-- Module: GAM.UI.DebugLog

local ADDON_NAME, GAM = ...
local DebugLog = {}
GAM.UI.DebugLog = DebugLog

local WIN_W, WIN_H = 620, 400
local frame
local scrollFrame
local editBox
local isPaused = false
local pendingLines = {}

local function GetUIScale()
    return (GAM.db and GAM.db.options and GAM.db.options.uiScale) or 1.0
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

local function LayoutButtonRowBottom(parent, buttons, cfg)
    local left   = cfg.left or 14
    local right  = cfg.right or (WIN_W - 14)
    local bottom = cfg.bottom or 10
    local gap    = cfg.gap or 8
    local rowGap = cfg.rowGap or 4
    local align  = cfg.align or "left"
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
        elseif align == "center" then
            x = left + math.floor((avail - rw) / 2)
        else
            x = left
        end
        local y = bottom + (ri - 1) * (h + rowGap)
        for bi, btn in ipairs(row) do
            btn:ClearAllPoints()
            btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
            x = x + btn:GetWidth() + ((bi < #row) and gap or 0)
        end
    end

    return {
        rows = #rows,
        top = bottom + (#rows - 1) * (h + rowGap) + h,
    }
end

-- ===== Item ID dump =====
-- Iterates every itemID in all loaded strats, resolves names via
-- GetItemInfo, and logs a Lua-table block to the debug log.
-- Items not yet in the client cache show "???" — visit their crafting
-- window or AH first so WoW loads them.
local function DumpItemIDs()
    if not (GAM.Importer and GAM.Importer.GetAllStrats) then
        GAM.Log.Warn("DumpItemIDs: Importer not ready")
        return
    end

    -- Collect: expectedName → { [itemID]=true, ... }
    local nameMap = {}
    local function addID(name, id)
        if type(id) == "number" and id > 0 then
            nameMap[name] = nameMap[name] or {}
            nameMap[name][id] = true
        end
    end

    for _, strat in ipairs(GAM.Importer.GetAllStrats()) do
        local out = strat.output
        if out and out.name then
            for _, id in ipairs(out.itemIDs or {}) do addID(out.name, id) end
        end
        -- outputs[]: multi-output strats (JC prospecting, etc.)
        -- Skip IDs already in strat.output to avoid internal Q1/Q2 label duplicates
        local mainIDs = {}
        for _, id in ipairs((out and out.itemIDs) or {}) do mainIDs[id] = true end
        for _, o2 in ipairs(strat.outputs or {}) do
            if o2.name then
                for _, id in ipairs(o2.itemIDs or {}) do
                    if not mainIDs[id] then addID(o2.name, id) end
                end
            end
        end
        for _, r in ipairs(strat.reagents or {}) do
            if r.name then
                for _, id in ipairs(r.itemIDs or {}) do addID(r.name, id) end
            end
        end
    end

    -- Sort names alphabetically
    local names = {}
    for name in pairs(nameMap) do names[#names+1] = name end
    table.sort(names)

    GAM.Log.Info("=== GAM Item ID Dump ===")
    GAM.Log.Info("-- Copy to a reference file; ??? = not in client cache yet")

    local totalIDs, mismatches, uncached = 0, 0, 0

    for _, expectedName in ipairs(names) do
        local ids = {}
        for id in pairs(nameMap[expectedName]) do ids[#ids+1] = id end
        table.sort(ids)

        local idParts   = {}
        local nameParts = {}
        local anyBad    = false

        for _, id in ipairs(ids) do
            totalIDs = totalIDs + 1
            local actual = GetItemInfo(id)
            idParts[#idParts+1] = tostring(id)
            if actual == nil then
                nameParts[#nameParts+1] = "???"
                uncached = uncached + 1
                anyBad = true
            elseif actual ~= expectedName then
                nameParts[#nameParts+1] = "MISMATCH:" .. actual
                mismatches = mismatches + 1
                anyBad = true
            else
                nameParts[#nameParts+1] = "\"" .. actual .. "\""
            end
        end

        local flag = anyBad and "  -- !! CHECK !!" or ""
        GAM.Log.Info('  ["%s"] = {%s},  -- %s%s',
            expectedName,
            table.concat(idParts, ", "),
            table.concat(nameParts, ", "),
            flag)
    end

    GAM.Log.Info("=== Done: %d names, %d IDs | %d mismatches | %d uncached ===",
        #names, totalIDs, mismatches, uncached)
end

-- ===== Build frame =====
local function Build()
    frame = CreateFrame("Frame", "GoldAdvisorMidnightDebugLog", UIParent,
                        "BackdropTemplate")
    frame:SetSize(WIN_W, WIN_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 200, -100)
    frame:SetScale(GetUIScale())
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left=11, right=12, top=12, bottom=11 },
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:Hide()

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -12)
    title:SetText(GAM.L["LOG_TITLE"])

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Scroll frame + edit box (makes content selectable/copyable)
    scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 40)

    editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetWidth(scrollFrame:GetWidth() - 10)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    scrollFrame:SetScrollChild(editBox)

    -- ── Button bar ──
    local function MakeBtn(lbl, minW)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(minW, 22)
        b:SetText(lbl)
        return b
    end

    local btnClear  = MakeBtn(GAM.L["BTN_CLEAR_LOG"],  80)
    local btnCopy   = MakeBtn(GAM.L["BTN_COPY_LOG"],   90)
    local btnPause  = MakeBtn(GAM.L["BTN_PAUSE_LOG"],  80)
    local btnDump   = MakeBtn(GAM.L["BTN_DUMP_IDS"],  100)

    local function RelayoutFooter()
        btnClear:SetWidth(MeasureButtonWidth(frame, btnClear:GetText(), 80, 180, 24))
        btnCopy:SetWidth(MeasureButtonWidth(frame, btnCopy:GetText(), 90, 200, 24))
        btnPause:SetWidth(MeasureButtonWidth(frame, btnPause:GetText(), 80, 200, 24))
        btnDump:SetWidth(MeasureButtonWidth(frame, btnDump:GetText(), 100, 220, 24))
        local info = LayoutButtonRowBottom(frame, { btnClear, btnCopy, btnPause, btnDump }, {
            left = 14, right = WIN_W - 14, bottom = 10, gap = 8, rowGap = 4, align = "left",
        })
        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -32)
        scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, info.top + 8)
    end
    RelayoutFooter()

    btnClear:SetScript("OnClick", function()
        GAM.Log.Clear()
        editBox:SetText("")
    end)

    btnCopy:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
        -- Ctrl+C is user's responsibility; we just select all
        local txt = GAM.Log.GetAllText()
        editBox:SetText(txt)
    end)

    btnPause:SetScript("OnClick", function()
        isPaused = not isPaused
        GAM.Log.SetPaused(isPaused)
        btnPause:SetText(isPaused and GAM.L["BTN_RESUME_LOG"] or GAM.L["BTN_PAUSE_LOG"])
        RelayoutFooter()
    end)

    btnDump:SetScript("OnClick", DumpItemIDs)

    -- ── Log listener: appends new lines when frame is visible ──
    GAM.Log.AddListener(function(entry)
        if not frame:IsShown() or isPaused then return end
        local cur = editBox:GetText()
        if cur == "" then
            editBox:SetText(entry)
        else
            editBox:SetText(cur .. "\n" .. entry)
        end
        -- Scroll to bottom
        local max = scrollFrame:GetVerticalScrollRange()
        scrollFrame:SetVerticalScroll(max)
    end)

    -- On show: populate from ring buffer
    frame:SetScript("OnShow", function()
        local txt = GAM.Log.GetAllText()
        editBox:SetText(txt)
        local max = scrollFrame:GetVerticalScrollRange()
        scrollFrame:SetVerticalScroll(max)
    end)
end

-- ===== Public API =====
function DebugLog.DumpItemIDs()
    if not frame then Build() end
    DumpItemIDs()
end

function DebugLog.Show()
    if not frame then Build() end
    frame:Show()
    frame:Raise()
end

function DebugLog.Hide()
    if frame then frame:Hide() end
end

function DebugLog.Toggle()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else frame:Show(); frame:Raise() end
end

function DebugLog.IsShown()
    return frame and frame:IsShown()
end
