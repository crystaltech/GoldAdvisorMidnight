-- GoldAdvisorMidnight/UI/StratCreator.lua
-- In-game strategy creator + encoded export.
-- Opened via Settings → "Create Strategy", or /gam create, or StratDetail "Edit" button.
-- User strats are saved to GAM.db.userStrats[] (SavedVariables).
-- Module: GAM.UI.StratCreator

local ADDON_NAME, GAM = ...
local SC = {}
GAM.UI.StratCreator = SC

local function GetUIScale()
    return (GAM.GetOption and GAM:GetOption("uiScale", 1.0)) or 1.0
end

local function GetUserStrats()
    return (GAM.State and GAM.State.GetUserStrats and GAM.State.GetUserStrats()) or
        ((GAM.db and GAM.db.userStrats) or {})
end

local function AddUserStrat(strat)
    if GAM.State and GAM.State.AddUserStrat then
        GAM.State.AddUserStrat(strat)
        return
    end
    GAM.db.userStrats = GAM.db.userStrats or {}
    GAM.db.userStrats[#GAM.db.userStrats + 1] = strat
end

local function ReplaceUserStrat(index, strat)
    if GAM.State and GAM.State.ReplaceUserStrat then
        return GAM.State.ReplaceUserStrat(index, strat)
    end
    if GAM.db and GAM.db.userStrats and index then
        GAM.db.userStrats[index] = strat
        return true
    end
    return false
end

local function DeleteUserStratAt(index)
    if GAM.State and GAM.State.DeleteUserStratAt then
        return GAM.State.DeleteUserStratAt(index)
    end
    if GAM.db and GAM.db.userStrats and GAM.db.userStrats[index] then
        return table.remove(GAM.db.userStrats, index)
    end
    return nil
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
end

-- ===== Base64 encoder / decoder =====
-- Self-contained implementation; no external library required.

local B64CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function B64Encode(str)
    local out = {}
    local pad = (3 - #str % 3) % 3
    str = str .. string.rep("\0", pad)
    for i = 1, #str, 3 do
        local b1, b2, b3 = str:byte(i, i + 2)
        local n = b1 * 0x10000 + b2 * 0x100 + b3
        out[#out + 1] = B64CHARS:sub(math.floor(n / 0x40000) % 64 + 1, math.floor(n / 0x40000) % 64 + 1)
        out[#out + 1] = B64CHARS:sub(math.floor(n / 0x1000)  % 64 + 1, math.floor(n / 0x1000)  % 64 + 1)
        out[#out + 1] = B64CHARS:sub(math.floor(n / 0x40)    % 64 + 1, math.floor(n / 0x40)    % 64 + 1)
        out[#out + 1] = B64CHARS:sub(n % 64 + 1, n % 64 + 1)
    end
    if pad == 2 then out[#out - 1] = "="; out[#out] = "="
    elseif pad == 1 then out[#out] = "=" end
    return table.concat(out)
end

local B64REV = {}
for i = 1, #B64CHARS do B64REV[B64CHARS:sub(i, i)] = i - 1 end

local function B64Decode(str)
    str = str:gsub("[^A-Za-z0-9+/=]", "")
    local out = {}
    for i = 1, #str, 4 do
        local c1 = B64REV[str:sub(i,   i)]   or 0
        local c2 = B64REV[str:sub(i+1, i+1)] or 0
        local c3 = B64REV[str:sub(i+2, i+2)] or 0
        local c4 = B64REV[str:sub(i+3, i+3)] or 0
        local n  = c1 * 0x40000 + c2 * 0x1000 + c3 * 0x40 + c4
        out[#out + 1] = string.char(math.floor(n / 0x10000) % 256)
        if str:sub(i+2, i+2) ~= "=" then
            out[#out + 1] = string.char(math.floor(n / 0x100) % 256)
        end
        if str:sub(i+3, i+3) ~= "=" then
            out[#out + 1] = string.char(n % 256)
        end
    end
    return table.concat(out)
end

-- ===== Strat encode / decode =====
-- Format: "GAM1:<base64(semicolon-delimited key=value pairs)>"
-- Keys use simple dot notation: out.1.name, reag.2.id, etc.
-- Values are escaped: semicolons → "\;" (no other escaping needed for normal item/profession names)

local function EscVal(s)   return tostring(s or ""):gsub(";", "\\;") end
local function UnescVal(s) return (s or ""):gsub("\\;", ";") end

function SC.EncodeStrat(strat)
    if not strat then return nil end
    local parts = {}
    local function kv(k, v) parts[#parts + 1] = k .. "=" .. EscVal(v) end

    kv("profession",  strat.profession)
    kv("stratName",   strat.stratName)
    kv("patchTag",    strat.patchTag or GAM.C.DEFAULT_PATCH)
    kv("startingAmt", strat.defaultStartingAmount or 1000)
    kv("notes",       strat.notes or "")

    -- outputs: prefer strat.outputs array; fall back to single strat.output
    local outputs = strat.outputs
    if not outputs or #outputs == 0 then
        outputs = strat.output and { strat.output } or {}
    end
    for i, o in ipairs(outputs) do
        kv("out." .. i .. ".name", o.name)
        kv("out." .. i .. ".id",   (o.itemIDs and o.itemIDs[1]) or "")
        kv("out." .. i .. ".qty",  math.floor((o.qtyMultiplier or 0) * (strat.defaultStartingAmount or 1000) + 0.5))
    end

    for i, r in ipairs(strat.reagents or {}) do
        kv("reag." .. i .. ".name", r.name)
        kv("reag." .. i .. ".id",   (r.itemIDs and r.itemIDs[1]) or "")
        kv("reag." .. i .. ".qty",  math.floor((r.qtyMultiplier or 0) * (strat.defaultStartingAmount or 1000) + 0.5))
    end

    return "GAM1:" .. B64Encode(table.concat(parts, ";"))
end

function SC.DecodeStrat(encoded)
    if not encoded or not encoded:match("^GAM1:") then return nil end
    local raw = B64Decode(encoded:sub(6))
    if not raw or raw == "" then return nil end

    local data = {}
    for pair in (raw .. ";"):gmatch("(.-[^\\]);") do
        local k, v = pair:match("^([^=]+)=(.*)")
        if k then data[k] = UnescVal(v) end
    end

    local startingAmt = tonumber(data.startingAmt) or 1000

    -- collect outputs
    local outputs = {}
    for i = 1, 20 do
        local name = data["out." .. i .. ".name"]
        if not name then break end
        local id  = tonumber(data["out." .. i .. ".id"])
        local qty = tonumber(data["out." .. i .. ".qty"]) or 0
        outputs[#outputs + 1] = {
            name          = name,
            itemIDs       = id and { id } or {},
            qtyMultiplier = qty / startingAmt,
        }
    end

    -- collect reagents
    local reagents = {}
    for i = 1, 30 do
        local name = data["reag." .. i .. ".name"]
        if not name then break end
        local id  = tonumber(data["reag." .. i .. ".id"])
        local qty = tonumber(data["reag." .. i .. ".qty"]) or 0
        reagents[#reagents + 1] = {
            name          = name,
            itemIDs       = id and { id } or {},
            qtyMultiplier = qty / startingAmt,
        }
    end

    local strat = {
        profession            = data.profession,
        stratName             = data.stratName,
        patchTag              = data.patchTag or GAM.C.DEFAULT_PATCH,
        defaultStartingAmount = startingAmt,
        notes                 = data.notes or "",
        output                = outputs[1],
        reagents              = reagents,
    }
    if #outputs > 1 then strat.outputs = outputs end
    return strat
end

-- ===== Lua snippet for file-edit export =====

local function SerializeToLua(strat)
    local lines = {
        "-- GoldAdvisorMidnight custom strategy — paste at the bottom of Data/StratsManual.lua",
        "GAM_STRATS_MANUAL[#GAM_STRATS_MANUAL + 1] = {",
        string.format('    profession            = "%s",', strat.profession or ""),
        string.format('    stratName             = "%s",', strat.stratName  or ""),
        string.format('    patchTag              = "%s",', strat.patchTag or GAM.C.DEFAULT_PATCH),
        string.format('    defaultStartingAmount = %d,', strat.defaultStartingAmount or 1000),
        "    output = {",
    }
    local out = strat.output or {}
    lines[#lines + 1] = string.format('        name          = "%s",', out.name or "")
    local ids = out.itemIDs and #out.itemIDs > 0
        and "{ " .. table.concat(out.itemIDs, ", ") .. " }"
        or  "{}"
    lines[#lines + 1] = string.format('        itemIDs       = %s,', ids)
    lines[#lines + 1] = string.format('        qtyMultiplier = %.6f,', out.qtyMultiplier or 0)
    lines[#lines + 1] = "    },"
    if strat.outputs and #strat.outputs > 1 then
        lines[#lines + 1] = "    outputs = {"
        for _, o in ipairs(strat.outputs) do
            local oids = o.itemIDs and #o.itemIDs > 0
                and "{ " .. table.concat(o.itemIDs, ", ") .. " }"
                or  "{}"
            lines[#lines + 1] = string.format(
                '        { name = "%s", itemIDs = %s, qtyMultiplier = %.6f },',
                o.name or "", oids, o.qtyMultiplier or 0)
        end
        lines[#lines + 1] = "    },"
    end
    lines[#lines + 1] = "    reagents = {"
    for _, r in ipairs(strat.reagents or {}) do
        local rids = r.itemIDs and #r.itemIDs > 0
            and "{ " .. table.concat(r.itemIDs, ", ") .. " }"
            or  "{}"
        lines[#lines + 1] = string.format(
            '        { name = "%s", itemIDs = %s, qtyMultiplier = %.6f },',
            r.name or "", rids, r.qtyMultiplier or 0)
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = string.format('    notes = "%s",', strat.notes or "")
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n")
end

-- ===== Export popup =====

local exportPopup

-- Creates a scrollable, read-only text area with a dark inset background.
-- Returns the inner EditBox (so callers can call :SetText).
local function MakeScrollBox(parent, w, h, xOff, yOff)
    -- Inset border frame
    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetSize(w + 6, h + 6)
    border:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff - 3, yOff + 3)
    border:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    border:SetBackdropColor(0.06, 0.06, 0.06, 1)
    border:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetSize(w, h)
    sf:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, yOff)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 18)))
    end)

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetWidth(w)
    eb:SetHeight(h)
    eb:SetScript("OnTextSet", function(self)
        -- Let the scroll frame recalculate its range after text is set
        sf:SetVerticalScroll(0)
        local textH = self:GetStringHeight()
        if textH > h then self:SetHeight(textH + 4) end
    end)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnEscapePressed",   function() exportPopup:Hide() end)
    sf:SetScrollChild(eb)
    return eb
end

local function BuildExportPopup()
    exportPopup = CreateFrame("Frame", "GAMExportPopup", UIParent, "BackdropTemplate")
    exportPopup:SetSize(540, 460)
    exportPopup:SetPoint("CENTER")
    exportPopup:SetScale(GetUIScale())
    exportPopup:SetMovable(true)
    exportPopup:EnableMouse(true)
    exportPopup:RegisterForDrag("LeftButton")
    exportPopup:SetScript("OnDragStart", exportPopup.StartMoving)
    exportPopup:SetScript("OnDragStop",  exportPopup.StopMovingOrSizing)
    exportPopup:SetFrameStrata("TOOLTIP")
    exportPopup:SetToplevel(true)
    exportPopup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left=11, right=12, top=12, bottom=11 },
    })
    exportPopup:SetBackdropColor(0, 0, 0, 1)
    local bgTex = exportPopup:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0, 0, 0, 1)
    exportPopup:Hide()

    local L = GAM.L

    local title = exportPopup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", exportPopup, "TOP", 0, -14)
    title:SetText(L["EXPORT_POPUP_TITLE"])

    local closeBtn = CreateFrame("Button", nil, exportPopup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", exportPopup, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() exportPopup:Hide() end)

    -- Encoded section (short, non-wrapping — scroll lets user copy the full string)
    local lbl1 = exportPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl1:SetPoint("TOPLEFT", exportPopup, "TOPLEFT", 18, -44)
    lbl1:SetText(L["EXPORT_ENCODED_LBL"])

    exportPopup.ebEncoded = MakeScrollBox(exportPopup, 504, 72, 18, -62)

    -- Lua section (multiline — tall scroll box)
    local lbl2 = exportPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl2:SetPoint("TOPLEFT", exportPopup, "TOPLEFT", 18, -148)
    lbl2:SetText(L["EXPORT_LUA_LBL"])

    exportPopup.ebLua = MakeScrollBox(exportPopup, 504, 250, 18, -166)

    local closeBtn2 = CreateFrame("Button", nil, exportPopup, "UIPanelButtonTemplate")
    closeBtn2:SetSize(80, 22)
    closeBtn2:SetPoint("BOTTOMRIGHT", exportPopup, "BOTTOMRIGHT", -14, 10)
    closeBtn2:SetText(GAM.L["BTN_CLOSE"])
    closeBtn2:SetWidth(MeasureButtonWidth(exportPopup, closeBtn2:GetText(), 80, 180, 24))
    closeBtn2:SetScript("OnClick", function() exportPopup:Hide() end)
end

function SC.ShowExportPopup(strat)
    if not exportPopup then BuildExportPopup() end
    exportPopup.ebEncoded:SetText(SC.EncodeStrat(strat) or "")
    exportPopup.ebLua:SetText(SerializeToLua(strat))
    exportPopup:Show()
    exportPopup.ebEncoded:SetFocus()
    exportPopup.ebEncoded:HighlightText()
end

-- ===== Import popup =====

local importPopup

local function BuildImportPopup()
    local L = GAM.L
    importPopup = CreateFrame("Frame", "GAMImportPopup", UIParent, "BackdropTemplate")
    importPopup:SetSize(540, 180)
    importPopup:SetPoint("CENTER")
    importPopup:SetScale(GetUIScale())
    importPopup:SetMovable(true)
    importPopup:EnableMouse(true)
    importPopup:RegisterForDrag("LeftButton")
    importPopup:SetScript("OnDragStart", importPopup.StartMoving)
    importPopup:SetScript("OnDragStop",  importPopup.StopMovingOrSizing)
    importPopup:SetFrameStrata("TOOLTIP")
    importPopup:SetToplevel(true)
    importPopup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left=11, right=12, top=12, bottom=11 },
    })
    importPopup:SetBackdropColor(0, 0, 0, 1)
    local bgTex = importPopup:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0, 0, 0, 1)
    importPopup:Hide()

    local title = importPopup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", importPopup, "TOP", 0, -14)
    title:SetText(L["IMPORT_POPUP_TITLE"])

    local closeX = CreateFrame("Button", nil, importPopup, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", importPopup, "TOPRIGHT", -4, -4)
    closeX:SetScript("OnClick", function() importPopup:Hide() end)

    local lbl = importPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", importPopup, "TOPLEFT", 18, -44)
    lbl:SetText(L["IMPORT_ENCODED_LBL"])

    local eb = CreateFrame("EditBox", nil, importPopup, "InputBoxTemplate")
    eb:SetSize(504, 72)
    eb:SetPoint("TOPLEFT", importPopup, "TOPLEFT", 18, -62)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnEscapePressed",   function() importPopup:Hide() end)
    importPopup.ebImport = eb

    local function DoImport()
        local text = (eb:GetText() or ""):match("^%s*(.-)%s*$")
        local strat = SC.DecodeStrat(text)
        if not strat or not strat.stratName or strat.stratName == "" then
            print("|cffff8800[GAM]|r " .. GAM.L["ERR_IMPORT_INVALID"])
            return
        end
        strat._isUser = true
        AddUserStrat(strat)
        GAM.Importer.Init()
        GAM:GetActiveMainWindow().Refresh()
        print(string.format("|cffff8800[GAM]|r " .. GAM.L["MSG_STRAT_IMPORTED"], strat.stratName))
        importPopup:Hide()
    end

    eb:SetScript("OnEnterPressed", DoImport)

    local btnImport = CreateFrame("Button", nil, importPopup, "UIPanelButtonTemplate")
    btnImport:SetSize(100, 22)
    btnImport:SetPoint("BOTTOMRIGHT", importPopup, "BOTTOMRIGHT", -14, 10)
    btnImport:SetText(L["BTN_IMPORT_STRAT"])
    btnImport:SetWidth(MeasureButtonWidth(importPopup, btnImport:GetText(), 100, 260, 24))
    btnImport:SetScript("OnClick", DoImport)

    local btnClose = CreateFrame("Button", nil, importPopup, "UIPanelButtonTemplate")
    btnClose:SetSize(80, 22)
    btnClose:SetText(L["BTN_CLOSE"])
    btnClose:SetWidth(MeasureButtonWidth(importPopup, btnClose:GetText(), 80, 180, 24))
    btnClose:SetPoint("BOTTOMRIGHT", btnImport, "BOTTOMLEFT", -6, 0)
    btnClose:SetScript("OnClick", function() importPopup:Hide() end)
end

function SC.ShowImport()
    if not importPopup then BuildImportPopup() end
    importPopup.ebImport:SetText("")
    importPopup:Show()
    importPopup.ebImport:SetFocus()
end

-- ===== Creator frame =====

local WIN_W, WIN_H = 520, 620
local ROW_H        = 24
local MAX_OUTPUTS  = 4
local MAX_REAGENTS = 8

local frame
local editingIndex  = nil   -- index in db.userStrats being edited; nil = new strat
local outputRows    = {}    -- { nameEB, idEB, qtyEB, removeBtn, visible }
local reagentRows   = {}    -- same

local function GetProfessions()
    local profs = {}
    for _, p in ipairs(GAM.Importer.GetAllProfessions(GAM.C.DEFAULT_PATCH)) do
        profs[#profs + 1] = p
    end
    return profs
end

-- ===== Row builder for output / reagent tables =====

local function MakeItemRow(parent, yOff, onRemove)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIN_W - 40, ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOff)

    local nameEB = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    nameEB:SetSize(200, 20)
    nameEB:SetPoint("LEFT", row, "LEFT", 0, 0)
    nameEB:SetAutoFocus(false)

    local idEB = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    idEB:SetSize(90, 20)
    idEB:SetPoint("LEFT", nameEB, "RIGHT", 6, 0)
    idEB:SetAutoFocus(false)
    idEB:SetNumeric(true)

    local qtyEB = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    qtyEB:SetSize(70, 20)
    qtyEB:SetPoint("LEFT", idEB, "RIGHT", 6, 0)
    qtyEB:SetAutoFocus(false)
    qtyEB:SetNumeric(true)

    local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    removeBtn:SetSize(22, 20)
    removeBtn:SetPoint("LEFT", qtyEB, "RIGHT", 4, 0)
    removeBtn:SetText(GAM.L["BTN_REMOVE"])
    removeBtn:SetWidth(MeasureButtonWidth(parent, removeBtn:GetText(), 22, 90, 14))
    removeBtn:SetScript("OnClick", onRemove)

    return { nameEB = nameEB, idEB = idEB, qtyEB = qtyEB, btn = removeBtn, frame = row }
end

-- ===== Build the creator frame =====

local function Build()
    local L = GAM.L

    frame = CreateFrame("Frame", "GAMStratCreator", UIParent, "BackdropTemplate")
    frame:SetSize(WIN_W, WIN_H)
    frame:SetPoint("CENTER")
    frame:SetScale(GetUIScale())
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left=11, right=12, top=12, bottom=11 },
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    local bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0, 0, 0, 1)
    frame:Hide()

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -14)
    title:SetText(L["CREATOR_TITLE"])
    frame.titleText = title

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    local y = -46

    -- ── Profession ──
    local profLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, y)
    profLbl:SetText(L["CREATOR_PROFESSION"])

    -- Dropdown (UIDropDownMenu)
    local profDD = CreateFrame("Frame", "GAMCreatorProfDD", frame, "UIDropDownMenuTemplate")
    profDD:SetPoint("TOPLEFT", profLbl, "TOPRIGHT", 4, 4)
    UIDropDownMenu_SetWidth(profDD, 160)

    local currentProf = ""
    local function SetProf(val)
        currentProf = val
        UIDropDownMenu_SetSelectedValue(profDD, val)
        UIDropDownMenu_SetText(profDD, val)
    end
    UIDropDownMenu_Initialize(profDD, function()
        local profs = GetProfessions()
        profs[#profs + 1] = L["CREATOR_CUSTOM_PROF"]
        for _, p in ipairs(profs) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = p
            info.value   = p
            info.checked = (p == currentProf)
            info.func    = function() SetProf(p) end
            UIDropDownMenu_AddButton(info)
        end
    end)
    frame.profDD   = profDD
    frame.SetProf  = SetProf
    frame.GetProf  = function() return currentProf end

    -- Custom profession text box (shown when "(Custom...)" is selected)
    local customProfEB = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    customProfEB:SetSize(160, 20)
    customProfEB:SetPoint("LEFT", profDD, "RIGHT", 4, 0)
    customProfEB:SetAutoFocus(false)
    customProfEB:Hide()
    frame.customProfEB = customProfEB

    profDD:SetScript("OnShow", function()
        -- If selection is custom, show the custom editbox
        local isCustom = (currentProf == L["CREATOR_CUSTOM_PROF"])
        customProfEB:SetShown(isCustom)
    end)

    y = y - 32

    -- ── Strategy Name ──
    local nameLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, y)
    nameLbl:SetText(L["CREATOR_NAME"])

    local nameEB = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    nameEB:SetSize(300, 20)
    nameEB:SetPoint("LEFT", nameLbl, "RIGHT", 6, 0)
    nameEB:SetAutoFocus(false)
    frame.nameEB = nameEB

    y = y - 32

    -- ── Input Quantity ──
    local qtyLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qtyLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, y)
    qtyLbl:SetText(L["CREATOR_INPUT_QTY"])

    local inputQtyEB = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    inputQtyEB:SetSize(80, 20)
    inputQtyEB:SetPoint("LEFT", qtyLbl, "RIGHT", 6, 0)
    inputQtyEB:SetAutoFocus(false)
    inputQtyEB:SetNumeric(true)
    inputQtyEB:SetText("1000")
    frame.inputQtyEB = inputQtyEB

    local qtyTip = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qtyTip:SetPoint("LEFT", inputQtyEB, "RIGHT", 6, 0)
    qtyTip:SetText(L["CREATOR_INPUT_HINT"])
    qtyTip:SetTextColor(0.6, 0.6, 0.6)

    y = y - 36

    -- ── Column headers ──
    local function MakeColHeader(xOff, w, text)
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", xOff, y)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        fs:SetTextColor(0.8, 0.8, 0.8)
    end

    -- ── Outputs section ──
    local outLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    outLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, y)
    outLbl:SetText(L["CREATOR_OUTPUTS"])

    local addOutBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addOutBtn:SetSize(80, 20)
    addOutBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, y + 2)
    addOutBtn:SetText(L["BTN_CREATOR_ADD_OUT"])
    addOutBtn:SetWidth(MeasureButtonWidth(frame, addOutBtn:GetText(), 80, 170, 20))

    y = y - 22
    MakeColHeader(20, 200, L["CREATOR_COL_NAME"])
    MakeColHeader(226, 90, L["CREATOR_COL_ITEMID"])
    MakeColHeader(322, 70, L["CREATOR_COL_QTY"])
    y = y - 20

    local outputHost = CreateFrame("Frame", nil, frame)
    outputHost:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, y)
    outputHost:SetSize(WIN_W - 40, MAX_OUTPUTS * ROW_H)

    local outputRowY = 0
    for i = 1, MAX_OUTPUTS do
        local row = MakeItemRow(outputHost, outputRowY, function()
            outputRows[i].frame:Hide()
        end)
        outputRows[i] = row
        outputRows[i].frame:Hide()
        outputRowY = outputRowY - ROW_H
    end

    addOutBtn:SetScript("OnClick", function()
        for i = 1, MAX_OUTPUTS do
            if not outputRows[i].frame:IsShown() then
                outputRows[i].frame:Show()
                outputRows[i].nameEB:SetFocus()
                break
            end
        end
    end)

    y = y - (MAX_OUTPUTS * ROW_H) - 8

    -- ── Reagents section ──
    local reagLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reagLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, y)
    reagLbl:SetText(L["CREATOR_REAGENTS"])

    local addReagBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addReagBtn:SetSize(80, 20)
    addReagBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, y + 2)
    addReagBtn:SetText(L["BTN_CREATOR_ADD_REAG"])
    addReagBtn:SetWidth(MeasureButtonWidth(frame, addReagBtn:GetText(), 80, 170, 20))

    y = y - 22
    MakeColHeader(20, 200, L["CREATOR_COL_NAME"])
    MakeColHeader(226, 90, L["CREATOR_COL_ITEMID"])
    MakeColHeader(322, 70, L["CREATOR_COL_QTY"])
    y = y - 20

    local reagHost = CreateFrame("Frame", nil, frame)
    reagHost:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, y)
    reagHost:SetSize(WIN_W - 40, MAX_REAGENTS * ROW_H)

    local reagRowY = 0
    for i = 1, MAX_REAGENTS do
        local row = MakeItemRow(reagHost, reagRowY, function()
            reagentRows[i].frame:Hide()
        end)
        reagentRows[i] = row
        reagentRows[i].frame:Hide()
        reagRowY = reagRowY - ROW_H
    end

    addReagBtn:SetScript("OnClick", function()
        for i = 1, MAX_REAGENTS do
            if not reagentRows[i].frame:IsShown() then
                reagentRows[i].frame:Show()
                reagentRows[i].nameEB:SetFocus()
                break
            end
        end
    end)

    y = y - (MAX_REAGENTS * ROW_H) - 8

    -- ── Notes ── (fixed above the button row, independent of y cursor)
    local notesLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notesLbl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 42)
    notesLbl:SetText(L["CREATOR_NOTES"])

    local notesEB = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    notesEB:SetSize(340, 20)
    notesEB:SetPoint("LEFT", notesLbl, "RIGHT", 6, 0)
    notesEB:SetAutoFocus(false)
    frame.notesEB = notesEB

    -- ── Bottom buttons ──
    local function CollectAndSave()
        -- Resolve profession
        local prof = frame.GetProf()
        if prof == GAM.L["CREATOR_CUSTOM_PROF"] then
            prof = (frame.customProfEB:GetText() or ""):match("^%s*(.-)%s*$")
        end
        local stratName  = (frame.nameEB:GetText() or ""):match("^%s*(.-)%s*$")
        local inputQty   = tonumber(frame.inputQtyEB:GetText()) or 1000
        local notes      = frame.notesEB:GetText() or ""

        if prof == "" then
            print("|cffff8800[GAM]|r " .. L["ERR_PROF_REQUIRED"]) return
        end
        if stratName == "" then
            print("|cffff8800[GAM]|r " .. L["ERR_NAME_REQUIRED"]) return
        end
        if inputQty <= 0 then
            print("|cffff8800[GAM]|r " .. L["ERR_QTY_REQUIRED"]) return
        end

        -- Collect outputs
        local outputs = {}
        for _, r in ipairs(outputRows) do
            if r.frame:IsShown() then
                local name = (r.nameEB:GetText() or ""):match("^%s*(.-)%s*$")
                if name ~= "" then
                    local id  = tonumber(r.idEB:GetText())
                    local qty = tonumber(r.qtyEB:GetText()) or 0
                    outputs[#outputs + 1] = {
                        name          = name,
                        itemIDs       = id and { id } or {},
                        qtyMultiplier = qty / inputQty,
                    }
                end
            end
        end
        if #outputs == 0 then
            print("|cffff8800[GAM]|r " .. L["ERR_OUTPUT_REQUIRED"]) return
        end

        -- Collect reagents
        local reagents = {}
        for _, r in ipairs(reagentRows) do
            if r.frame:IsShown() then
                local name = (r.nameEB:GetText() or ""):match("^%s*(.-)%s*$")
                if name ~= "" then
                    local id  = tonumber(r.idEB:GetText())
                    local qty = tonumber(r.qtyEB:GetText()) or 0
                    reagents[#reagents + 1] = {
                        name          = name,
                        itemIDs       = id and { id } or {},
                        qtyMultiplier = qty / inputQty,
                    }
                end
            end
        end

        local strat = {
            profession            = prof,
            stratName             = stratName,
            patchTag              = GAM.C.DEFAULT_PATCH,
            defaultStartingAmount = inputQty,
            output                = outputs[1],
            reagents              = reagents,
            notes                 = notes,
        }
        if #outputs > 1 then strat.outputs = outputs end

        -- Save to db
        if editingIndex then
            ReplaceUserStrat(editingIndex, strat)
        else
            AddUserStrat(strat)
        end

        -- Reload importer so strat appears immediately
        GAM.Importer.Init()
        GAM:GetActiveMainWindow().Refresh()

        print(string.format("|cffff8800[GAM]|r " .. GAM.L["MSG_STRAT_SAVED"], stratName))
        frame:Hide()
    end

    local btnSave = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnSave:SetSize(80, 22)
    btnSave:SetText(GAM.L["BTN_CREATOR_SAVE"])
    btnSave:SetScript("OnClick", CollectAndSave)

    local btnDelete = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnDelete:SetSize(80, 22)
    btnDelete:SetText(GAM.L["BTN_CREATOR_DELETE"])
    btnDelete:SetScript("OnClick", function()
        local userStrats = GetUserStrats()
        if editingIndex and userStrats[editingIndex] then
            local name = userStrats[editingIndex].stratName or "?"
            DeleteUserStratAt(editingIndex)
            GAM.Importer.Init()
            GAM:GetActiveMainWindow().Refresh()
            print(string.format("|cffff8800[GAM]|r " .. GAM.L["MSG_STRAT_DELETED"], name))
        end
        frame:Hide()
    end)
    frame.btnDelete = btnDelete

    local btnCancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnCancel:SetSize(80, 22)
    btnCancel:SetText(GAM.L["BTN_CLOSE"])
    btnCancel:SetScript("OnClick", function() frame:Hide() end)

    btnSave:SetWidth(MeasureButtonWidth(frame, btnSave:GetText(), 80, 180, 24))
    btnDelete:SetWidth(MeasureButtonWidth(frame, btnDelete:GetText(), 80, 220, 24))
    btnCancel:SetWidth(MeasureButtonWidth(frame, btnCancel:GetText(), 80, 180, 24))
    LayoutButtonRowBottom(frame, { btnSave, btnDelete, btnCancel }, {
        left = 14, right = WIN_W - 14, bottom = 10, gap = 8, rowGap = 4, align = "left",
    })
end

-- ===== Clear all form fields =====

local function ClearForm()
    if not frame then return end
    frame.nameEB:SetText("")
    frame.inputQtyEB:SetText("1000")
    frame.notesEB:SetText("")
    frame.customProfEB:SetText("")
    frame.customProfEB:Hide()
    for _, r in ipairs(outputRows)  do r.nameEB:SetText(""); r.idEB:SetText(""); r.qtyEB:SetText(""); r.frame:Hide() end
    for _, r in ipairs(reagentRows) do r.nameEB:SetText(""); r.idEB:SetText(""); r.qtyEB:SetText(""); r.frame:Hide() end
    -- Show first output row by default
    if outputRows[1] then outputRows[1].frame:Show() end
    -- Show two reagent rows by default
    if reagentRows[1] then reagentRows[1].frame:Show() end
    if reagentRows[2] then reagentRows[2].frame:Show() end
end

-- ===== Populate form from existing strat =====

local function PopulateForm(strat)
    if not frame then return end
    ClearForm()
    frame.SetProf(strat.profession or "")
    frame.nameEB:SetText(strat.stratName or "")
    frame.inputQtyEB:SetText(tostring(strat.defaultStartingAmount or 1000))
    frame.notesEB:SetText(strat.notes or "")

    -- Outputs
    local outs = strat.outputs or (strat.output and { strat.output } or {})
    for i, o in ipairs(outs) do
        if outputRows[i] then
            outputRows[i].frame:Show()
            outputRows[i].nameEB:SetText(o.name or "")
            local id = o.itemIDs and o.itemIDs[1]
            outputRows[i].idEB:SetText(id and tostring(id) or "")
            local qty = math.floor((o.qtyMultiplier or 0) * (strat.defaultStartingAmount or 1000) + 0.5)
            outputRows[i].qtyEB:SetText(qty > 0 and tostring(qty) or "")
        end
    end

    -- Reagents
    for i, r in ipairs(strat.reagents or {}) do
        if reagentRows[i] then
            reagentRows[i].frame:Show()
            reagentRows[i].nameEB:SetText(r.name or "")
            local id = r.itemIDs and r.itemIDs[1]
            reagentRows[i].idEB:SetText(id and tostring(id) or "")
            local qty = math.floor((r.qtyMultiplier or 0) * (strat.defaultStartingAmount or 1000) + 0.5)
            reagentRows[i].qtyEB:SetText(qty > 0 and tostring(qty) or "")
        end
    end
end

-- ===== Public API =====

function SC.Show()
    if not frame then Build() end
    editingIndex = nil
    ClearForm()
    frame.titleText:SetText(GAM.L["CREATOR_TITLE"])
    frame.btnDelete:Hide()
    frame:Show()
end

-- Open in edit mode for a user strat by its db.userStrats index.
-- Called by StratDetail's "Edit" button.
function SC.ShowEdit(strat)
    if not frame then Build() end

    -- Find the index in db.userStrats
    editingIndex = nil
    if GAM.State and GAM.State.FindUserStratIndex then
        editingIndex = GAM.State.FindUserStratIndex(strat)
    else
        for i, s in ipairs(GetUserStrats()) do
            if s == strat or (s.stratName == strat.stratName and s.profession == strat.profession) then
                editingIndex = i
                break
            end
        end
    end

    PopulateForm(strat)
    frame.titleText:SetText(L["CREATOR_EDIT_TITLE"])
    frame.btnDelete:Show()
    frame:Show()
end

function SC.Hide()
    if frame then frame:Hide() end
end
