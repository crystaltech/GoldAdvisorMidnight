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

-- ===== ARP Export =====
-- Produces a CSV-style block matching the AverageReagentPrice addon export format.
-- Format: ItemName, Rank 1, X.XX, Rank 2, X.XX, Rank 3, X.XX
-- X.XX = copper / 10000, 2 decimal places, English decimal. No AH cut applied.
local function GenerateARPExport()
    if not (GAM.Importer and GAM.Importer.GetAllStrats) then
        return "-- Importer not ready"
    end

    local patchTag = GAM.C.DEFAULT_PATCH

    -- Collect unique items by name → itemIDs array (first seen wins)
    local nameToIDs = {}
    local nameOrder = {}

    local function addItem(name, itemIDs)
        if type(name) ~= "string" or name == "" then return end
        if not itemIDs or #itemIDs == 0 then return end
        if not nameToIDs[name] then
            nameToIDs[name] = itemIDs
            nameOrder[#nameOrder + 1] = name
        end
    end

    for _, strat in ipairs(GAM.Importer.GetAllStrats()) do
        local out = strat.output
        if out and out.name and out.itemIDs then addItem(out.name, out.itemIDs) end
        for _, o2 in ipairs(strat.outputs or {}) do
            if o2.name and o2.itemIDs then addItem(o2.name, o2.itemIDs) end
        end
        for _, r in ipairs(strat.reagents or {}) do
            if r.name and r.itemIDs then addItem(r.name, r.itemIDs) end
        end
    end

    table.sort(nameOrder)

    local lines = {}
    for _, name in ipairs(nameOrder) do
        local ids = nameToIDs[name]
        -- Build quality-tier → itemID map using WoW API.
        -- GetItemReagentQualityByItemInfo: nil = uncached OR non-tiered; 0 = non-tiered; 1/2/3 = tiered.
        -- When nil, use GetItemInfo to distinguish: name returned = item is loaded (non-tiered → Rank 1);
        -- nil returned = truly uncached → skip the whole item.
        local rankMap = {}
        local skip = false
        for _, id in ipairs(ids) do
            local q = C_TradeSkillUI.GetItemReagentQualityByItemInfo(id)
            if q == nil then
                if GetItemInfo(id) ~= nil then
                    -- Item loaded but not a tiered reagent → Rank 1
                    rankMap[1] = id
                else
                    -- Truly uncached → skip whole item
                    skip = true
                    break
                end
            elseif q > 0 then
                -- If the item name already encodes the quality tier (e.g. "Eversinging Dust Q2",
                -- "Radiant Shard Q1"), the rank column is redundant — put at Rank 1 so VLOOKUP
                -- with column 3 always finds it. Items without a Q-suffix (e.g. "Oil of Dawn")
                -- keep quality-based placement so Q2-mode VLOOKUP (column 5) works correctly.
                rankMap[name:match(" Q%d$") and 1 or q] = id
            else
                -- q == 0: non-tiered item → Rank 1
                rankMap[1] = id
            end
        end
        if not skip then
            local parts = { name }
            for rankIdx = 1, 3 do
                local itemID = rankMap[rankIdx]
                local price = itemID and GAM.Pricing.GetEffectivePrice(itemID, patchTag)
                parts[#parts + 1] = "Rank " .. rankIdx
                parts[#parts + 1] = (price and price > 0) and string.format("%.2f", price / 10000) or "0.00"
            end
            lines[#lines + 1] = table.concat(parts, ", ")
        end
    end

    return #lines > 0 and table.concat(lines, "\n") or "-- No items found"
end

-- ===== ARP Export popup =====

local arpPopup
local arpPopupEB
local arpPopupSF

local function BuildARPExportPopup()
    arpPopup = CreateFrame("Frame", "GAMARPExportPopup", UIParent, "BackdropTemplate")
    arpPopup:SetSize(540, 380)
    arpPopup:SetPoint("CENTER")
    arpPopup:SetScale(GetUIScale())
    arpPopup:SetMovable(true)
    arpPopup:EnableMouse(true)
    arpPopup:RegisterForDrag("LeftButton")
    arpPopup:SetScript("OnDragStart", arpPopup.StartMoving)
    arpPopup:SetScript("OnDragStop",  arpPopup.StopMovingOrSizing)
    arpPopup:SetFrameStrata("DIALOG")
    arpPopup:SetToplevel(true)
    arpPopup:SetClampedToScreen(true)
    arpPopup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left=11, right=12, top=12, bottom=11 },
    })
    arpPopup:SetBackdropColor(0, 0, 0, 1)
    arpPopup:Hide()

    -- Title
    local title = arpPopup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", arpPopup, "TOP", 0, -14)
    title:SetText("ARP Export")

    -- Close button (top-right X)
    local closeBtn = CreateFrame("Button", nil, arpPopup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", arpPopup, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() arpPopup:Hide() end)

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", nil, arpPopup, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     arpPopup, "TOPLEFT",     14, -40)
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
    sf:SetScrollChild(eb)
    arpPopupEB = eb
    arpPopupSF = sf
end

local function ShowARPExportPopup(text)
    if not arpPopup then BuildARPExportPopup() end
    arpPopupSF:SetVerticalScroll(0)
    arpPopupEB:SetText(text or "")
    arpPopup:Show()
    arpPopup:Raise()
    arpPopupEB:SetFocus()
    arpPopupEB:HighlightText()
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

    local btnClear     = MakeBtn(GAM.L["BTN_CLEAR_LOG"],   80)
    local btnCopy      = MakeBtn(GAM.L["BTN_COPY_LOG"],    90)
    local btnPause     = MakeBtn(GAM.L["BTN_PAUSE_LOG"],   80)
    local btnDump      = MakeBtn(GAM.L["BTN_DUMP_IDS"],   100)
    local btnARPExport = MakeBtn(GAM.L["BTN_ARP_EXPORT"],  90)

    local function RelayoutFooter()
        btnClear:SetWidth(MeasureButtonWidth(frame, btnClear:GetText(), 80, 180, 24))
        btnCopy:SetWidth(MeasureButtonWidth(frame, btnCopy:GetText(), 90, 200, 24))
        btnPause:SetWidth(MeasureButtonWidth(frame, btnPause:GetText(), 80, 200, 24))
        btnDump:SetWidth(MeasureButtonWidth(frame, btnDump:GetText(), 100, 220, 24))
        btnARPExport:SetWidth(MeasureButtonWidth(frame, btnARPExport:GetText(), 90, 220, 24))
        local info = LayoutButtonRowBottom(frame, { btnClear, btnCopy, btnPause, btnDump, btnARPExport }, {
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

    btnARPExport:SetScript("OnClick", function()
        ShowARPExportPopup(GenerateARPExport())
    end)

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
