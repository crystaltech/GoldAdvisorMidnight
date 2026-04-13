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

local WIN_W, WIN_H = 620, 794
local ROW_H = 38
local MAX_OUTPUTS = 12
local MAX_REAGENTS = 16
local MIN_VISIBLE_OUTPUTS = 1
local MIN_VISIBLE_REAGENTS = 1
local ROW_NAME_W = 286
local ROW_ID_W = 92
local ROW_QTY_W = 60

local frame
local editingIndex = nil
local outputRows = {}
local reagentRows = {}
local itemLookupCache = nil

local RefreshFormValidation
local RemoveVisibleRow

local function TrimText(s)
    return (tostring(s or "")):match("^%s*(.-)%s*$")
end

local function SetEditText(editBox, text)
    if not editBox then return end
    text = text or ""
    if editBox:GetText() == text then return end
    editBox._gamSetText = true
    editBox:SetText(text)
    editBox._gamSetText = nil
end

local function CopyArray(src)
    local out = {}
    if type(src) == "table" then
        for i, value in ipairs(src) do
            out[i] = value
        end
    end
    return out
end

local function NormalizeLookupName(name)
    return TrimText(name):lower():gsub("%s+", " ")
end

local function GetPreferredNameScore(name)
    if type(name) ~= "string" or name == "" then
        return math.huge
    end
    local penalty = name:find("%b()") and 1000 or 0
    return penalty + #name
end

local function GetItemLookupCache()
    if itemLookupCache then
        return itemLookupCache
    end

    local catalog = (GAM_WORKBOOK_GENERATED and GAM_WORKBOOK_GENERATED.itemCatalog) or {}
    local byNameKey = {}
    local preferredNameByID = {}

    for itemName, ids in pairs(catalog) do
        if type(itemName) == "string" and itemName ~= "" and type(ids) == "table" then
            local key = NormalizeLookupName(itemName)
            local entry = byNameKey[key]
            if not entry then
                entry = { ids = {}, seen = {} }
                byNameKey[key] = entry
            end

            for _, itemID in ipairs(ids) do
                if type(itemID) == "number" and itemID > 0 and not entry.seen[itemID] then
                    entry.seen[itemID] = true
                    entry.ids[#entry.ids + 1] = itemID
                end

                if type(itemID) == "number" and itemID > 0 then
                    local currentName = preferredNameByID[itemID]
                    if not currentName or GetPreferredNameScore(itemName) < GetPreferredNameScore(currentName) then
                        preferredNameByID[itemID] = itemName
                    end
                end
            end
        end
    end

    for _, entry in pairs(byNameKey) do
        table.sort(entry.ids)
        entry.seen = nil
    end

    itemLookupCache = {
        byNameKey = byNameKey,
        preferredNameByID = preferredNameByID,
    }
    return itemLookupCache
end

local function LookupLocalItemIDs(name)
    local key = NormalizeLookupName(name)
    if key == "" then
        return { kind = "none" }
    end

    local entry = GetItemLookupCache().byNameKey[key]
    if not entry or #entry.ids == 0 then
        return { kind = "none" }
    end
    if #entry.ids == 1 then
        return { kind = "single", id = entry.ids[1], ids = CopyArray(entry.ids) }
    end
    return { kind = "ambiguous", ids = CopyArray(entry.ids) }
end

local function ResolveLocalItemName(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then
        return nil
    end

    if type(GetItemInfo) == "function" then
        local itemName = GetItemInfo(itemID)
        if type(itemName) == "string" and itemName ~= "" then
            return itemName
        end
    end

    if C_Item and type(C_Item.GetItemNameByID) == "function" then
        local ok, itemName = pcall(C_Item.GetItemNameByID, itemID)
        if ok and type(itemName) == "string" and itemName ~= "" then
            return itemName
        end
    end

    if type(GetItemInfoInstant) == "function" then
        local itemName = select(1, GetItemInfoInstant(itemID))
        if type(itemName) == "string" and itemName ~= "" then
            return itemName
        end
    end

    return GetItemLookupCache().preferredNameByID[itemID]
end

local function GetProfessions()
    local profs = {}
    for _, p in ipairs((GAM.Importer and GAM.Importer.GetAllProfessions and GAM.Importer.GetAllProfessions(GAM.C.DEFAULT_PATCH)) or {}) do
        profs[#profs + 1] = p
    end
    return profs
end

local function IsKnownProfession(profession)
    if not profession or profession == "" then
        return false
    end
    for _, p in ipairs(GetProfessions()) do
        if p == profession then
            return true
        end
    end
    return false
end

local function GetUserStratLabel(strat)
    local profession = (strat and strat.profession) or "?"
    local stratName = (strat and strat.stratName) or "?"
    return string.format("%s — %s", profession, stratName)
end

local function MakeInsetBox(parent)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0.05, 0.05, 0.05, 0.96)
    box:SetBackdropBorderColor(0.34, 0.34, 0.34, 1)
    return box
end

local function AnalyzeRowValues(fields)
    local name = TrimText(fields.nameText)
    local idText = TrimText(fields.idText)
    local qtyText = TrimText(fields.qtyText)
    local itemID = tonumber(idText)
    local qty = tonumber(qtyText)
    local hasName = name ~= ""
    local idEntered = idText ~= ""
    local qtyEntered = qtyText ~= ""
    local hasID = itemID ~= nil and itemID > 0
    local hasQty = qty ~= nil and qty > 0
    local any = hasName or idEntered or qtyEntered
    local lookupResult = fields.lookupResult or { kind = "none" }
    local resolvedName = fields.resolvedName

    local state = {
        any = any,
        valid = false,
        countable = false,
        name = name,
        idText = idText,
        itemID = hasID and itemID or nil,
        qty = hasQty and qty or nil,
        lookupResult = lookupResult,
        resolvedName = resolvedName,
    }

    if not any then
        state.valid = true
        state.kind = "empty"
        return state
    end

    if qtyEntered and not hasQty then
        state.kind = "invalid_qty"
        state.invalidReason = "qty"
        return state
    end

    if idEntered and not hasID then
        state.kind = "invalid_id"
        state.invalidReason = "id"
        return state
    end

    if not hasName and not hasID then
        state.kind = "invalid_item"
        state.invalidReason = "item"
        return state
    end

    if not hasQty then
        state.kind = "invalid_finish"
        state.invalidReason = "finish"
        return state
    end

    state.valid = true
    state.countable = true
    if hasName and not hasID then
        if lookupResult.kind == "ambiguous" then
            state.kind = "ambiguous"
        else
            state.kind = "freeform"
        end
    elseif hasID and not hasName then
        if resolvedName and resolvedName ~= "" then
            state.kind = "resolved_id"
        else
            state.kind = "id_only"
        end
    elseif lookupResult.kind == "single" and lookupResult.id == itemID then
        state.kind = "matched"
    else
        state.kind = "ready"
    end

    return state
end

local function GetRowStatusPresentation(state)
    local L = GAM.L or {}
    if not state or state.kind == "empty" then
        return "", 0.72, 0.72, 0.72
    end

    if state.kind == "invalid_qty" then
        return (L["CREATOR_ERR_ROW_QTY"] or "Qty must be greater than 0."), 1.0, 0.35, 0.35
    elseif state.kind == "invalid_id" then
        return (L["CREATOR_ERR_ROW_ID"] or "Item ID must be greater than 0."), 1.0, 0.35, 0.35
    elseif state.kind == "invalid_item" then
        return (L["CREATOR_ERR_ROW_ITEM"] or "Enter an item name or Item ID."), 1.0, 0.35, 0.35
    elseif state.kind == "invalid_finish" then
        return (L["CREATOR_STATUS_CLEAR_OR_FINISH"] or "Finish this row or clear it."), 1.0, 0.35, 0.35
    elseif state.kind == "ambiguous" then
        return (L["CREATOR_STATUS_NAME_AMBIG"] or
            "Multiple local Item IDs match this name; keeping name-only unless you choose an Item ID."),
            1.0, 0.82, 0.18
    elseif state.kind == "freeform" then
        return (L["CREATOR_STATUS_FREEFORM"] or "Freeform name entry."), 0.75, 0.75, 0.75
    elseif state.kind == "resolved_id" then
        return string.format((L["CREATOR_STATUS_ID_MATCH"] or "Resolved name locally: %s."), tostring(state.resolvedName or "?")),
            0.45, 0.95, 0.45
    elseif state.kind == "id_only" then
        return (L["CREATOR_STATUS_ID_ONLY"] or "Item ID entered; no local name available yet."), 1.0, 0.82, 0.18
    elseif state.kind == "matched" then
        return string.format((L["CREATOR_STATUS_NAME_MATCH"] or "Matched local Item ID: %d."), tonumber(state.itemID or 0)),
            0.45, 0.95, 0.45
    end

    return (L["CREATOR_STATUS_READY"] or "Ready."), 0.45, 0.95, 0.45
end

local function GetVisibleRowCount(rows)
    local count = 0
    for _, row in ipairs(rows) do
        if row.frame:IsShown() then
            count = count + 1
        end
    end
    return count
end

local function GetRowTexts(row)
    return {
        nameText = TrimText(row.nameEB:GetText()),
        idText = TrimText(row.idEB:GetText()),
        qtyText = TrimText(row.qtyEB:GetText()),
        autoFilledName = row.autoFilledName and true or false,
        autoFilledID = row.autoFilledID and true or false,
    }
end

local function ApplyRowTexts(row, values)
    row._gamUpdating = true
    SetEditText(row.nameEB, values.nameText or "")
    SetEditText(row.idEB, values.idText or "")
    SetEditText(row.qtyEB, values.qtyText or "")
    row.autoFilledName = values.autoFilledName and true or false
    row.autoFilledID = values.autoFilledID and true or false
    row._gamUpdating = nil
end

local function ClearRow(row)
    ApplyRowTexts(row, {
        nameText = "",
        idText = "",
        qtyText = "",
        autoFilledName = false,
        autoFilledID = false,
    })
    row.state = nil
    row.statusFS:SetText("")
end

local function UpdateRowState(row)
    if not row then return end

    local nameText = TrimText(row.nameEB:GetText())
    local idText = TrimText(row.idEB:GetText())
    local qtyText = TrimText(row.qtyEB:GetText())

    if nameText == "" and idText == "" and qtyText == "" then
        row.autoFilledName = false
        row.autoFilledID = false
    end

    row._gamUpdating = true

    local lookupResult = { kind = "none" }
    if nameText ~= "" then
        lookupResult = LookupLocalItemIDs(nameText)
        if lookupResult.kind == "single" and (idText == "" or row.autoFilledID) then
            SetEditText(row.idEB, tostring(lookupResult.id))
            row.autoFilledID = true
        elseif lookupResult.kind ~= "single" and row.autoFilledID and idText ~= "" then
            SetEditText(row.idEB, "")
            row.autoFilledID = false
        end
    elseif row.autoFilledID and idText ~= "" then
        SetEditText(row.idEB, "")
        row.autoFilledID = false
    end

    idText = TrimText(row.idEB:GetText())
    local itemID = tonumber(idText)
    local resolvedName = nil
    if itemID and itemID > 0 then
        resolvedName = ResolveLocalItemName(itemID)
        if resolvedName and (nameText == "" or row.autoFilledName) then
            SetEditText(row.nameEB, resolvedName)
            row.autoFilledName = true
        elseif not resolvedName and row.autoFilledName and nameText ~= "" then
            SetEditText(row.nameEB, "")
            row.autoFilledName = false
        end
    elseif row.autoFilledName and nameText ~= "" then
        SetEditText(row.nameEB, "")
        row.autoFilledName = false
    end

    row._gamUpdating = nil

    nameText = TrimText(row.nameEB:GetText())
    idText = TrimText(row.idEB:GetText())
    itemID = tonumber(idText)
    if nameText ~= "" then
        lookupResult = LookupLocalItemIDs(nameText)
    else
        lookupResult = { kind = "none" }
    end
    if itemID and itemID > 0 then
        resolvedName = ResolveLocalItemName(itemID)
    else
        resolvedName = nil
    end

    row.state = AnalyzeRowValues({
        nameText = nameText,
        idText = idText,
        qtyText = qtyText,
        lookupResult = lookupResult,
        resolvedName = resolvedName,
    })

    local statusText, r, g, b = GetRowStatusPresentation(row.state)
    row.statusFS:SetText(statusText or "")
    row.statusFS:SetTextColor(r or 1, g or 1, b or 1)
end

RemoveVisibleRow = function(rows, rowIndex, minVisible)
    local visibleCount = GetVisibleRowCount(rows)
    if visibleCount == 0 or not rows[rowIndex] or not rows[rowIndex].frame:IsShown() then
        return
    end

    if visibleCount <= (minVisible or 1) then
        ClearRow(rows[rowIndex])
        if RefreshFormValidation then RefreshFormValidation() end
        return
    end

    for i = rowIndex, visibleCount - 1 do
        ApplyRowTexts(rows[i], GetRowTexts(rows[i + 1]))
    end

    ClearRow(rows[visibleCount])
    rows[visibleCount].frame:Hide()
    if RefreshFormValidation then RefreshFormValidation() end
end

local function MakeItemRow(parent, index, rows, minVisible)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_H))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * ROW_H))

    local nameEB = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    nameEB:SetSize(ROW_NAME_W, 20)
    nameEB:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
    nameEB:SetAutoFocus(false)

    local idEB = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    idEB:SetSize(ROW_ID_W, 20)
    idEB:SetPoint("LEFT", nameEB, "RIGHT", 6, 0)
    idEB:SetAutoFocus(false)
    idEB:SetNumeric(true)

    local qtyEB = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    qtyEB:SetSize(ROW_QTY_W, 20)
    qtyEB:SetPoint("LEFT", idEB, "RIGHT", 6, 0)
    qtyEB:SetAutoFocus(false)
    qtyEB:SetNumeric(true)

    local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    removeBtn:SetSize(22, 20)
    removeBtn:SetPoint("LEFT", qtyEB, "RIGHT", 4, 0)
    removeBtn:SetText(GAM.L["BTN_REMOVE"])
    removeBtn:SetWidth(MeasureButtonWidth(parent, removeBtn:GetText(), 22, 90, 14))
    removeBtn:SetScript("OnClick", function()
        RemoveVisibleRow(rows, index, minVisible)
    end)

    local statusFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusFS:SetPoint("TOPLEFT", nameEB, "BOTTOMLEFT", 2, -4)
    statusFS:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    statusFS:SetJustifyH("LEFT")
    statusFS:SetText("")
    statusFS:SetTextColor(0.75, 0.75, 0.75)

    row.nameEB = nameEB
    row.idEB = idEB
    row.qtyEB = qtyEB
    row.btn = removeBtn
    row.frame = row
    row.statusFS = statusFS
    row.autoFilledName = false
    row.autoFilledID = false

    local function HandleChange(editBox, userInput)
        if row._gamUpdating or editBox._gamSetText then
            return
        end
        if editBox == nameEB and userInput then
            row.autoFilledName = false
        elseif editBox == idEB and userInput then
            row.autoFilledID = false
        end
        if RefreshFormValidation then RefreshFormValidation() end
    end

    nameEB:SetScript("OnTextChanged", HandleChange)
    idEB:SetScript("OnTextChanged", HandleChange)
    qtyEB:SetScript("OnTextChanged", HandleChange)

    nameEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    idEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    qtyEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    return row
end

local function CreateItemSection(parent, topY, boxHeight, titleText, helpText, addText, rows, maxRows, minVisible)
    local titleFS = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFS:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, topY)
    titleFS:SetText(titleText)

    local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetSize(96, 20)
    addBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, topY + 2)
    addBtn:SetText(addText)
    addBtn:SetWidth(MeasureButtonWidth(parent, addBtn:GetText(), 96, 190, 20))

    local helpFS = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helpFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -3)
    helpFS:SetWidth(WIN_W - 40)
    helpFS:SetJustifyH("LEFT")
    helpFS:SetText(helpText)
    helpFS:SetTextColor(0.72, 0.72, 0.72)

    local box = MakeInsetBox(parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, topY - 32)
    box:SetSize(WIN_W - 40, boxHeight)

    local function MakeColHeader(xOff, width, text)
        local fs = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", box, "TOPLEFT", xOff, -10)
        fs:SetWidth(width)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        fs:SetTextColor(0.82, 0.82, 0.82)
        return fs
    end

    MakeColHeader(10, ROW_NAME_W, GAM.L["CREATOR_COL_NAME"])
    MakeColHeader(10 + ROW_NAME_W + 6, ROW_ID_W, GAM.L["CREATOR_COL_ITEMID"])
    MakeColHeader(10 + ROW_NAME_W + 6 + ROW_ID_W + 6, ROW_QTY_W, GAM.L["CREATOR_COL_QTY"])

    local scrollFrame = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -28)
    scrollFrame:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 8)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 18)))
    end)

    local host = CreateFrame("Frame", nil, scrollFrame)
    host:SetWidth(scrollFrame:GetWidth() or (box:GetWidth() - 34))
    host:SetHeight(maxRows * ROW_H)
    scrollFrame:SetScrollChild(host)
    scrollFrame:SetScript("OnSizeChanged", function(self)
        host:SetWidth(math.max(1, (self:GetWidth() or 0) - 8))
    end)

    for i = 1, maxRows do
        rows[i] = MakeItemRow(host, i, rows, minVisible)
        rows[i].frame:Hide()
    end

    addBtn:SetScript("OnClick", function()
        for i = 1, maxRows do
            if not rows[i].frame:IsShown() then
                rows[i].frame:Show()
                rows[i].nameEB:SetFocus()
                scrollFrame:SetVerticalScroll(scrollFrame:GetVerticalScrollRange())
                break
            end
        end
        if RefreshFormValidation then RefreshFormValidation() end
    end)

    return {
        titleFS = titleFS,
        helpFS = helpFS,
        addBtn = addBtn,
        box = box,
        scrollFrame = scrollFrame,
        host = host,
        rows = rows,
        minVisible = minVisible,
    }
end

local function SetVisibleRows(rows, count)
    count = math.max(0, math.min(#rows, count or 0))
    for i, row in ipairs(rows) do
        row.frame:SetShown(i <= count)
        if i > count then
            ClearRow(row)
        end
    end
end

local function ResetScrollPositions()
    if frame and frame.outputSection and frame.outputSection.scrollFrame then
        frame.outputSection.scrollFrame:SetVerticalScroll(0)
    end
    if frame and frame.reagentSection and frame.reagentSection.scrollFrame then
        frame.reagentSection.scrollFrame:SetVerticalScroll(0)
    end
end

local function CollectProfessionValue()
    if not frame then
        return ""
    end

    local prof = frame.GetProf and frame.GetProf() or ""
    if prof == GAM.L["CREATOR_CUSTOM_PROF"] then
        prof = TrimText(frame.customProfEB:GetText())
    end
    return TrimText(prof)
end

local function CollectItemsFromRows(rows, inputQty)
    local items = {}
    for _, row in ipairs(rows) do
        if row.frame:IsShown() and row.state and row.state.countable then
            items[#items + 1] = {
                name = row.state.name or "",
                itemIDs = row.state.itemID and { row.state.itemID } or {},
                qtyMultiplier = (row.state.qty or 0) / inputQty,
            }
        end
    end
    return items
end

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
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
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

    local setupLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    setupLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -46)
    setupLbl:SetText((L and L["CREATOR_SETUP"]) or "Strategy Setup")

    local metaBox = MakeInsetBox(frame)
    metaBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -64)
    metaBox:SetSize(WIN_W - 40, 148)

    local editPickLbl = metaBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editPickLbl:SetPoint("TOPLEFT", metaBox, "TOPLEFT", 12, -16)
    editPickLbl:SetText((L and L["CREATOR_EDIT_SELECT"]) or "Edit Strategy:")
    editPickLbl:Hide()

    local editPickDD = CreateFrame("Frame", "GAMCreatorEditDD", metaBox, "UIDropDownMenuTemplate")
    editPickDD:SetPoint("TOPLEFT", editPickLbl, "TOPRIGHT", 0, 4)
    UIDropDownMenu_SetWidth(editPickDD, 260)
    editPickDD:Hide()

    local function RefreshEditDropdown(selectedIndex)
        UIDropDownMenu_Initialize(editPickDD, function()
            for i, strat in ipairs(GetUserStrats()) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = GetUserStratLabel(strat)
                info.value = i
                info.checked = (i == selectedIndex)
                info.func = function()
                    if SC.SelectEditIndex then
                        SC.SelectEditIndex(i)
                    end
                end
                UIDropDownMenu_AddButton(info)
            end
        end)

        local selected = selectedIndex and GetUserStrats()[selectedIndex] or nil
        UIDropDownMenu_SetSelectedValue(editPickDD, selectedIndex)
        UIDropDownMenu_SetText(editPickDD,
            selected and GetUserStratLabel(selected) or ((L and L["CREATOR_EDIT_SELECT"]) or "Edit Strategy:"))
    end

    local function SetEditSelectorVisible(visible)
        editPickLbl:SetShown(visible)
        editPickDD:SetShown(visible)
    end

    frame.RefreshEditDropdown = RefreshEditDropdown
    frame.SetEditSelectorVisible = SetEditSelectorVisible

    local profLbl = metaBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profLbl:SetPoint("TOPLEFT", metaBox, "TOPLEFT", 12, -48)
    profLbl:SetText(L["CREATOR_PROFESSION"])

    local profDD = CreateFrame("Frame", "GAMCreatorProfDD", metaBox, "UIDropDownMenuTemplate")
    profDD:SetPoint("TOPLEFT", profLbl, "TOPRIGHT", 0, 4)
    UIDropDownMenu_SetWidth(profDD, 170)

    local customProfEB
    local currentProf = ""
    local function SetProf(val)
        currentProf = val or ""
        UIDropDownMenu_SetSelectedValue(profDD, currentProf)
        UIDropDownMenu_SetText(profDD, currentProf ~= "" and currentProf or (L["CREATOR_PROFESSION_PLACEHOLDER"] or "Select..."))
        if customProfEB then
            customProfEB:SetShown(currentProf == L["CREATOR_CUSTOM_PROF"])
        end
    end

    UIDropDownMenu_Initialize(profDD, function()
        local profs = GetProfessions()
        profs[#profs + 1] = L["CREATOR_CUSTOM_PROF"]
        for _, p in ipairs(profs) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = p
            info.value = p
            info.checked = (p == currentProf)
            info.func = function()
                SetProf(p)
                if p == L["CREATOR_CUSTOM_PROF"] and customProfEB then
                    customProfEB:SetFocus()
                end
                if RefreshFormValidation then RefreshFormValidation() end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    frame.profDD = profDD
    frame.SetProf = SetProf
    frame.GetProf = function() return currentProf end

    customProfEB = CreateFrame("EditBox", nil, metaBox, "InputBoxTemplate")
    customProfEB:SetSize(180, 20)
    customProfEB:SetPoint("LEFT", profDD, "RIGHT", 4, 0)
    customProfEB:SetAutoFocus(false)
    customProfEB:Hide()
    customProfEB:SetScript("OnTextChanged", function()
        if RefreshFormValidation then RefreshFormValidation() end
    end)
    frame.customProfEB = customProfEB

    local nameLbl = metaBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLbl:SetPoint("TOPLEFT", metaBox, "TOPLEFT", 12, -82)
    nameLbl:SetText(L["CREATOR_NAME"])

    local nameEB = CreateFrame("EditBox", nil, metaBox, "InputBoxTemplate")
    nameEB:SetSize(352, 20)
    nameEB:SetPoint("LEFT", nameLbl, "RIGHT", 6, 0)
    nameEB:SetAutoFocus(false)
    nameEB:SetScript("OnTextChanged", function()
        if RefreshFormValidation then RefreshFormValidation() end
    end)
    frame.nameEB = nameEB

    local qtyLbl = metaBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qtyLbl:SetPoint("TOPLEFT", metaBox, "TOPLEFT", 12, -116)
    qtyLbl:SetText(L["CREATOR_INPUT_QTY"])

    local inputQtyEB = CreateFrame("EditBox", nil, metaBox, "InputBoxTemplate")
    inputQtyEB:SetSize(80, 20)
    inputQtyEB:SetPoint("LEFT", qtyLbl, "RIGHT", 6, 0)
    inputQtyEB:SetAutoFocus(false)
    inputQtyEB:SetNumeric(true)
    inputQtyEB:SetText("1000")
    inputQtyEB:SetScript("OnTextChanged", function()
        if RefreshFormValidation then RefreshFormValidation() end
    end)
    frame.inputQtyEB = inputQtyEB

    local qtyTip = metaBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qtyTip:SetPoint("LEFT", inputQtyEB, "RIGHT", 6, 0)
    qtyTip:SetWidth(300)
    qtyTip:SetJustifyH("LEFT")
    qtyTip:SetText(L["CREATOR_INPUT_HINT"])
    qtyTip:SetTextColor(0.6, 0.6, 0.6)

    frame.outputSection = CreateItemSection(
        frame,
        -222,
        164,
        L["CREATOR_OUTPUTS"],
        (L["CREATOR_ROW_HELP"] or "Type an item name or Item ID. Qty is required."),
        L["BTN_CREATOR_ADD_OUT"],
        outputRows,
        MAX_OUTPUTS,
        MIN_VISIBLE_OUTPUTS
    )

    frame.reagentSection = CreateItemSection(
        frame,
        -428,
        228,
        L["CREATOR_REAGENTS"],
        (L["CREATOR_ROW_HELP"] or "Type an item name or Item ID. Qty is required."),
        L["BTN_CREATOR_ADD_REAG"],
        reagentRows,
        MAX_REAGENTS,
        MIN_VISIBLE_REAGENTS
    )

    local notesLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notesLbl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 82)
    notesLbl:SetText(L["CREATOR_NOTES"])

    local notesEB = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    notesEB:SetSize(432, 20)
    notesEB:SetPoint("LEFT", notesLbl, "RIGHT", 6, 0)
    notesEB:SetAutoFocus(false)
    frame.notesEB = notesEB

    local validationFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    validationFS:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 48)
    validationFS:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 48)
    validationFS:SetJustifyH("LEFT")
    validationFS:SetJustifyV("TOP")
    validationFS:SetText("")
    frame.validationFS = validationFS

    local function CollectAndSave()
        if not frame._formValid then
            print("|cffff8800[GAM]|r " .. tostring(frame._validationSummary or (L["CREATOR_STATUS_CLEAR_OR_FINISH"] or "Finish this row or clear it.")))
            return
        end

        local prof = CollectProfessionValue()
        local stratName = TrimText(frame.nameEB:GetText())
        local inputQty = tonumber(frame.inputQtyEB:GetText()) or 1000
        local notes = frame.notesEB:GetText() or ""
        local outputs = CollectItemsFromRows(outputRows, inputQty)
        local reagents = CollectItemsFromRows(reagentRows, inputQty)

        if #outputs == 0 or #reagents == 0 then
            if RefreshFormValidation then RefreshFormValidation() end
            print("|cffff8800[GAM]|r " .. tostring(frame._validationSummary or (L["CREATOR_STATUS_CLEAR_OR_FINISH"] or "Finish this row or clear it.")))
            return
        end

        local strat = {
            profession = prof,
            stratName = stratName,
            patchTag = GAM.C.DEFAULT_PATCH,
            defaultStartingAmount = inputQty,
            output = outputs[1],
            reagents = reagents,
            notes = notes,
        }
        if #outputs > 1 then
            strat.outputs = outputs
        end

        if editingIndex then
            ReplaceUserStrat(editingIndex, strat)
        else
            AddUserStrat(strat)
        end

        GAM.Importer.Init()
        local mainWindow = GAM.GetActiveMainWindow and GAM:GetActiveMainWindow() or nil
        if mainWindow and mainWindow.Refresh then
            mainWindow.Refresh()
        end

        print(string.format("|cffff8800[GAM]|r " .. GAM.L["MSG_STRAT_SAVED"], stratName))
        frame:Hide()
    end

    local btnSave = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnSave:SetSize(80, 22)
    btnSave:SetText(GAM.L["BTN_CREATOR_SAVE"])
    btnSave:SetScript("OnClick", CollectAndSave)
    frame.btnSave = btnSave

    local btnDelete = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnDelete:SetSize(80, 22)
    btnDelete:SetText(GAM.L["BTN_CREATOR_DELETE"])
    btnDelete:SetScript("OnClick", function()
        local userStrats = GetUserStrats()
        if editingIndex and userStrats[editingIndex] then
            local name = userStrats[editingIndex].stratName or "?"
            DeleteUserStratAt(editingIndex)
            GAM.Importer.Init()
            local mainWindow = GAM.GetActiveMainWindow and GAM:GetActiveMainWindow() or nil
            if mainWindow and mainWindow.Refresh then
                mainWindow.Refresh()
            end
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
    frame.RelayoutButtons = function()
        local buttons = { btnSave }
        if btnDelete:IsShown() then
            buttons[#buttons + 1] = btnDelete
        end
        buttons[#buttons + 1] = btnCancel
        LayoutButtonRowBottom(frame, buttons, {
            left = 14, right = WIN_W - 14, bottom = 12, gap = 8, rowGap = 4, align = "left",
        })
    end
    frame.RelayoutButtons()
end

RefreshFormValidation = function()
    if not frame then return end

    for _, row in ipairs(outputRows) do
        if row.frame:IsShown() then
            UpdateRowState(row)
        else
            row.state = nil
            row.statusFS:SetText("")
        end
    end

    for _, row in ipairs(reagentRows) do
        if row.frame:IsShown() then
            UpdateRowState(row)
        else
            row.state = nil
            row.statusFS:SetText("")
        end
    end

    local prof = CollectProfessionValue()
    local stratName = TrimText(frame.nameEB:GetText())
    local inputQty = tonumber(frame.inputQtyEB:GetText())

    local outputCount = 0
    local reagentCount = 0
    local firstOutputIssue = nil
    local firstReagentIssue = nil

    for _, row in ipairs(outputRows) do
        if row.frame:IsShown() and row.state then
            if row.state.countable then
                outputCount = outputCount + 1
            elseif row.state.any and not row.state.valid and not firstOutputIssue then
                local issueText = select(1, GetRowStatusPresentation(row.state))
                firstOutputIssue = string.format("%s: %s", GAM.L["CREATOR_OUTPUTS"] or "Outputs", issueText)
            end
        end
    end

    for _, row in ipairs(reagentRows) do
        if row.frame:IsShown() and row.state then
            if row.state.countable then
                reagentCount = reagentCount + 1
            elseif row.state.any and not row.state.valid and not firstReagentIssue then
                local issueText = select(1, GetRowStatusPresentation(row.state))
                firstReagentIssue = string.format("%s: %s", GAM.L["CREATOR_REAGENTS"] or "Reagents", issueText)
            end
        end
    end

    local ok = false
    local summary
    if prof == "" then
        summary = GAM.L["CREATOR_SUMMARY_PROF"] or "Choose a profession."
    elseif stratName == "" then
        summary = GAM.L["CREATOR_SUMMARY_NAME"] or "Enter a strategy name."
    elseif not inputQty or inputQty <= 0 then
        summary = GAM.L["CREATOR_SUMMARY_QTY"] or "Input quantity must be greater than 0."
    elseif firstOutputIssue then
        summary = firstOutputIssue
    elseif outputCount == 0 then
        summary = GAM.L["CREATOR_SUMMARY_OUTPUT"] or "Add at least one complete output row."
    elseif firstReagentIssue then
        summary = firstReagentIssue
    elseif reagentCount == 0 then
        summary = GAM.L["CREATOR_SUMMARY_REAGENT"] or "Add at least one complete reagent row."
    else
        ok = true
        summary = string.format((GAM.L["CREATOR_SUMMARY_READY"] or "Ready to save. %d outputs, %d reagents."),
            outputCount, reagentCount)
    end

    frame._formValid = ok
    frame._validationSummary = summary
    frame.validationFS:SetText(summary or "")
    if ok then
        frame.validationFS:SetTextColor(0.45, 0.95, 0.45)
        frame.btnSave:Enable()
    else
        frame.validationFS:SetTextColor(1.0, 0.35, 0.35)
        frame.btnSave:Disable()
    end

    if frame.outputSection and frame.outputSection.addBtn then
        if GetVisibleRowCount(outputRows) >= MAX_OUTPUTS then
            frame.outputSection.addBtn:Disable()
        else
            frame.outputSection.addBtn:Enable()
        end
    end

    if frame.reagentSection and frame.reagentSection.addBtn then
        if GetVisibleRowCount(reagentRows) >= MAX_REAGENTS then
            frame.reagentSection.addBtn:Disable()
        else
            frame.reagentSection.addBtn:Enable()
        end
    end
end

-- ===== Clear all form fields =====

local function ClearForm()
    if not frame then return end

    frame.SetProf("")
    SetEditText(frame.nameEB, "")
    SetEditText(frame.inputQtyEB, "1000")
    SetEditText(frame.notesEB, "")
    SetEditText(frame.customProfEB, "")
    frame.customProfEB:Hide()

    for _, row in ipairs(outputRows) do
        ClearRow(row)
        row.frame:Hide()
    end
    for _, row in ipairs(reagentRows) do
        ClearRow(row)
        row.frame:Hide()
    end

    SetVisibleRows(outputRows, 1)
    SetVisibleRows(reagentRows, 2)
    ResetScrollPositions()
    RefreshFormValidation()
end

-- ===== Populate form from existing strat =====

local function PopulateForm(strat)
    if not frame then return end

    ClearForm()

    local profession = strat.profession or ""
    if profession ~= "" and not IsKnownProfession(profession) then
        frame.SetProf(GAM.L["CREATOR_CUSTOM_PROF"])
        SetEditText(frame.customProfEB, profession)
        frame.customProfEB:Show()
    else
        frame.SetProf(profession)
        SetEditText(frame.customProfEB, "")
    end

    SetEditText(frame.nameEB, strat.stratName or "")
    SetEditText(frame.inputQtyEB, tostring(strat.defaultStartingAmount or 1000))
    SetEditText(frame.notesEB, strat.notes or "")

    local outs = strat.outputs or (strat.output and { strat.output } or {})
    local outCount = math.max(1, math.min(MAX_OUTPUTS, #outs))
    SetVisibleRows(outputRows, outCount)
    for i = 1, outCount do
        local output = outs[i]
        if output then
            local itemID = output.itemIDs and output.itemIDs[1]
            local qty = math.floor((output.qtyMultiplier or 0) * (strat.defaultStartingAmount or 1000) + 0.5)
            ApplyRowTexts(outputRows[i], {
                nameText = output.name or "",
                idText = itemID and tostring(itemID) or "",
                qtyText = qty > 0 and tostring(qty) or "",
                autoFilledName = false,
                autoFilledID = false,
            })
        end
    end

    local reags = strat.reagents or {}
    local reagentCount = math.max(1, math.min(MAX_REAGENTS, math.max(#reags, 2)))
    SetVisibleRows(reagentRows, reagentCount)
    for i = 1, reagentCount do
        local reagent = reags[i]
        if reagent then
            local itemID = reagent.itemIDs and reagent.itemIDs[1]
            local qty = math.floor((reagent.qtyMultiplier or 0) * (strat.defaultStartingAmount or 1000) + 0.5)
            ApplyRowTexts(reagentRows[i], {
                nameText = reagent.name or "",
                idText = itemID and tostring(itemID) or "",
                qtyText = qty > 0 and tostring(qty) or "",
                autoFilledName = false,
                autoFilledID = false,
            })
        end
    end

    ResetScrollPositions()
    RefreshFormValidation()
end

-- ===== Public API =====

function SC.Show()
    if not frame then Build() end
    editingIndex = nil
    ClearForm()
    frame.titleText:SetText(GAM.L["CREATOR_TITLE"])
    frame.btnDelete:Hide()
    if frame.RelayoutButtons then frame.RelayoutButtons() end
    if frame.SetEditSelectorVisible then frame.SetEditSelectorVisible(false) end
    if frame.RefreshEditDropdown then frame.RefreshEditDropdown(nil) end
    frame:Show()
end

function SC.SelectEditIndex(index)
    if not frame then Build() end
    local userStrats = GetUserStrats()
    local strat = index and userStrats[index] or nil
    if not strat then
        return false
    end

    editingIndex = index
    PopulateForm(strat)
    frame.titleText:SetText((GAM.L and GAM.L["CREATOR_EDIT_TITLE"]) or "Edit Strategy")
    frame.btnDelete:Show()
    if frame.RelayoutButtons then frame.RelayoutButtons() end
    if frame.SetEditSelectorVisible then frame.SetEditSelectorVisible(true) end
    if frame.RefreshEditDropdown then frame.RefreshEditDropdown(index) end
    frame:Show()
    return true
end

function SC.ShowEditPicker()
    local userStrats = GetUserStrats()
    if #userStrats == 0 then
        print("|cffff8800[GAM]|r " .. ((GAM.L and GAM.L["MSG_NO_USER_STRATS"]) or
            "No user-created strategies found. Opening Create Strategy."))
        SC.Show()
        return
    end
    if not frame then Build() end
    if frame.SetEditSelectorVisible then frame.SetEditSelectorVisible(true) end
    SC.SelectEditIndex(editingIndex or 1)
end

-- Open in edit mode for a user strat by its db.userStrats index.
-- Called by StratDetail's "Edit" button.
function SC.ShowEdit(strat)
    local resolvedIndex = nil
    if GAM.State and GAM.State.FindUserStratIndex then
        resolvedIndex = GAM.State.FindUserStratIndex(strat)
    else
        for i, s in ipairs(GetUserStrats()) do
            if s == strat or (s.stratName == strat.stratName and s.profession == strat.profession) then
                resolvedIndex = i
                break
            end
        end
    end

    if resolvedIndex then
        SC.SelectEditIndex(resolvedIndex)
    else
        SC.ShowEditPicker()
    end
end

function SC.Hide()
    if frame then frame:Hide() end
end

function SC.RunSmokeChecks()
    local ok, err = pcall(function()
        local single = LookupLocalItemIDs("Mote of Light")
        assert(single.kind == "single" and single.id == 236949, "single-match local lookup failed")

        local ambiguous = LookupLocalItemIDs("Dawn Crystal")
        assert(ambiguous.kind == "ambiguous" and type(ambiguous.ids) == "table" and #ambiguous.ids >= 2,
            "ambiguous local lookup failed")

        local unknown = LookupLocalItemIDs("Definitely Not A Real Item")
        assert(unknown.kind == "none", "unknown local lookup should be none")

        local resolvedName = ResolveLocalItemName(236949)
        assert(resolvedName == "Mote of Light", "itemID -> name lookup failed")

        local freeform = AnalyzeRowValues({
            nameText = "Custom Herb Mix",
            idText = "",
            qtyText = "5",
            lookupResult = { kind = "none" },
            resolvedName = nil,
        })
        assert(freeform.valid and freeform.countable and freeform.kind == "freeform",
            "freeform row should be valid")

        local partial = AnalyzeRowValues({
            nameText = "Mote of Light",
            idText = "",
            qtyText = "",
            lookupResult = { kind = "single", id = 236949 },
            resolvedName = nil,
        })
        assert(partial.any and not partial.valid and partial.invalidReason == "finish",
            "partial row should be invalid")

        local qtyInvalid = AnalyzeRowValues({
            nameText = "Mote of Light",
            idText = "",
            qtyText = "0",
            lookupResult = { kind = "single", id = 236949 },
            resolvedName = nil,
        })
        assert(not qtyInvalid.valid and qtyInvalid.invalidReason == "qty",
            "qty validation failed")

        local encoded = SC.EncodeStrat({
            profession = "Alchemy",
            stratName = "Smoke Test",
            patchTag = GAM.C.DEFAULT_PATCH,
            defaultStartingAmount = 1000,
            outputs = {
                { name = "Mote of Light", itemIDs = { 236949 }, qtyMultiplier = 0.1 },
            },
            reagents = {
                { name = "Custom Herb Mix", itemIDs = {}, qtyMultiplier = 1.25 },
            },
            notes = "Smoke",
        })

        local decoded = SC.DecodeStrat(encoded)
        assert(decoded and decoded.stratName == "Smoke Test", "encode/decode stratName mismatch")
        assert(decoded.output and decoded.output.itemIDs and decoded.output.itemIDs[1] == 236949,
            "encode/decode output mismatch")
        assert(decoded.reagents and decoded.reagents[1] and decoded.reagents[1].name == "Custom Herb Mix",
            "encode/decode reagent mismatch")
    end)
    return ok, err
end
