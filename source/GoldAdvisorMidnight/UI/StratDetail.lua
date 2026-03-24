-- GoldAdvisorMidnight/UI/StratDetail.lua
-- Strategy detail panel: reagent table, output table, rank selector,
-- scan buttons, 2-column metrics display (Cost/Revenue + ROI/Break-Even, centered Profit),
-- Auctionator export, Push-to-CraftSim. Gold accent theme throughout.
-- Module: GAM.UI.StratDetail

local ADDON_NAME, GAM = ...
local SD = {}
GAM.UI.StratDetail = SD

local WIN_W, WIN_H = 720, 720
local ROW_H        = 22
local PROFIT_BASE_Y = 52
local MIN_NOTICE_GAP_ABOVE_BUTTONS = 6
local MIN_NOTICE_GAP_BELOW_PROFIT  = 10
local TABLE_SCROLL_GUTTER = 20
local TABLE_ROW_W = WIN_W - 28 - TABLE_SCROLL_GUTTER
local ROW_SCAN_BTN_MAX_W = 60

local frame
local currentStrat  = nil
local currentPatch  = nil
local metricsCache  = nil   -- last computed metrics
local positioned    = false -- true once the initial frame position has been set

-- Section scroll child refs (needed in SD.Refresh)
local inputScrollFrame, inputListHost
local outputScrollFrame, outputListHost

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
    local bottom = cfg.bottom or 20
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

-- ===== Delete confirmation (custom frame — avoids StaticPopup strata/close issues) =====
local confirmFrame

local function BuildConfirmFrame()
    confirmFrame = CreateFrame("Frame", "GAMDeleteConfirm", UIParent, "BackdropTemplate")
    confirmFrame:SetSize(300, 130)
    confirmFrame:SetPoint("CENTER")
    confirmFrame:SetScale(GetUIScale())
    confirmFrame:SetFrameStrata("TOOLTIP")
    confirmFrame:SetToplevel(true)
    confirmFrame:EnableMouse(true)
    confirmFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left=11, right=12, top=12, bottom=11 },
    })
    confirmFrame:SetBackdropColor(0, 0, 0, 1)
    local bgTex = confirmFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0, 0, 0, 1)
    confirmFrame:Hide()

    local msg = confirmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msg:SetPoint("TOP", confirmFrame, "TOP", 0, -22)
    msg:SetWidth(260)
    msg:SetJustifyH("CENTER")
    msg:SetWordWrap(true)
    confirmFrame.msg = msg

    -- "Delete" confirm button — OnClick is rewired each time ShowDeleteConfirm is called
    local btnOK = CreateFrame("Button", nil, confirmFrame, "UIPanelButtonTemplate")
    btnOK:SetSize(100, 22)
    btnOK:SetText(GAM.L["BTN_DELETE_STRAT"])
    confirmFrame.btnOK = btnOK

    local btnCancel = CreateFrame("Button", nil, confirmFrame, "UIPanelButtonTemplate")
    btnCancel:SetSize(80, 22)
    btnCancel:SetText(GAM.L["BTN_CLOSE"])
    btnCancel:SetScript("OnClick", function() confirmFrame:Hide() end)

    btnOK:SetWidth(MeasureButtonWidth(confirmFrame, btnOK:GetText(), 100, 220, 24))
    btnCancel:SetWidth(MeasureButtonWidth(confirmFrame, btnCancel:GetText(), 80, 180, 24))
    LayoutButtonRowBottom(confirmFrame, { btnOK, btnCancel }, {
        left = 20, right = 280, bottom = 14, gap = 8, rowGap = 4, align = "center",
    })

    confirmFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then confirmFrame:Hide() end
    end)
    confirmFrame:SetPropagateKeyboardInput(true)
end

local function ShowDeleteConfirm(strat)
    if not confirmFrame then BuildConfirmFrame() end
    confirmFrame.msg:SetText(
        GAM.L["CONFIRM_DELETE_BODY"]:format(strat.stratName or "?"))
    confirmFrame.btnOK:SetScript("OnClick", function()
        confirmFrame:Hide()
        if GAM.db and GAM.db.userStrats then
            for i, s in ipairs(GAM.db.userStrats) do
                if s == strat or (s.stratName == strat.stratName and s.profession == strat.profession) then
                    table.remove(GAM.db.userStrats, i)
                    break
                end
            end
        end
        GAM.Importer.Init()
        GAM:GetActiveMainWindow().Refresh()
        print(string.format("|cffff8800[GAM]|r " .. GAM.L["MSG_STRAT_DELETED"], strat.stratName or "?"))
        if frame then frame:Hide() end
    end)
    confirmFrame:Show()
end

-- ===== Helpers =====
local function GetPDB() return GAM:GetPatchDB(currentPatch) end

-- Save the desired input (primary reagent) qty; drives all calculations via Pricing.CalculateStratMetrics
local function SetInputQtyOverride(value)
    local pdb = GetPDB()
    pdb.inputQtyOverrides = pdb.inputQtyOverrides or {}
    local n = tonumber(value)
    if n and n > 0 then
        pdb.inputQtyOverrides[currentStrat.id] = n
    else
        pdb.inputQtyOverrides[currentStrat.id] = nil
    end
end

-- Formats an integer with thousands-separator commas: 50000 → "50,000"
local function FmtQty(n)
    local s = tostring(math.floor(n))
    return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- ===== Item row helper =====
-- Detail rows only become clickable once WoW has produced a safe cached item link.
-- Before that, the row stays readable but inert so shift-click / SetItemRef never
-- receives a nil or plain-text fallback.
local function BindItemRow(frameObj, display)
    frameObj._itemDisplay = display
    frameObj:EnableMouse(display and display.hasSafeLink and display.itemLink and true or false)
end

local function ItemRowClick(self, button)
    local display = self and self._itemDisplay
    local link = display and display.itemLink
    if not link or link == "" then return end
    if HandleModifiedItemClick and HandleModifiedItemClick(link) then
        return
    end
    local itemString = link:match("|H([^|]+)|h")
    if itemString then
        SetItemRef(itemString, link, button)
    end
end

local function ItemRowEnter(self)
    local display = self and self._itemDisplay
    local link = display and display.itemLink
    if not link or link == "" then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(link)
    local tt = self and self._metricTooltip
    if tt then
        GameTooltip:AddLine(" ")
        if tt.kind == "reagent" then
            GameTooltip:AddLine("Unit Price: " .. (tt.unitPrice and GAM.Pricing.FormatPrice(tt.unitPrice) or "|cffff8800—|r"), 1, 0.82, 0)
            GameTooltip:AddLine("Total Required: " .. string.format("%.0f", tt.required or 0), 1, 0.82, 0)
            GameTooltip:AddLine("Need to Buy: " .. string.format("%.0f", tt.needToBuy or 0), 1, 0.82, 0)
            GameTooltip:AddLine("Full Cost: " .. (tt.totalCostFull and GAM.Pricing.FormatPrice(tt.totalCostFull) or "|cff888888—|r"), 1, 0.82, 0)
            if tt.totalCost and tt.totalCostFull and tt.totalCost ~= tt.totalCostFull then
                GameTooltip:AddLine("Buy Now Cost: " .. GAM.Pricing.FormatPrice(tt.totalCost), 1, 0.82, 0)
            end
        elseif tt.kind == "output" then
            GameTooltip:AddLine("Unit Sell Price: " .. (tt.unitPrice and GAM.Pricing.FormatPrice(tt.unitPrice) or "|cffff8800—|r"), 1, 0.82, 0)
            GameTooltip:AddLine("Expected Output: " .. string.format("%.0f", tt.expectedQty or 0), 1, 0.82, 0)
            GameTooltip:AddLine("Total Net Revenue: " .. (tt.netRevenue and GAM.Pricing.FormatPrice(tt.netRevenue) or "|cff888888—|r"), 1, 0.82, 0)
            GameTooltip:AddLine("The visible Net column is craft-level net revenue, not a per-item price.", 1, 0.82, 0, true)
        end
    end
    GameTooltip:Show()
end

local function ItemRowLeave()
    GameTooltip:Hide()
end

-- ===== Auctionator export =====
local function CreateAuctionatorList()
    if not (Auctionator and Auctionator.API and Auctionator.API.v1 and
            type(Auctionator.API.v1.CreateShoppingList) == "function") then
        print("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_NOT_FOUND"])
        return
    end
    if not currentStrat then return end
    local m = metricsCache or GAM.Pricing.CalculateStratMetrics(currentStrat, currentPatch)
    if not m then return end

    local addonName  = "GoldAdvisorMidnight"
    local hasConvert = type(Auctionator.API.v1.ConvertToSearchString) == "function"
    local searchStrings, qtySummary = {}, {}

    for _, rm in ipairs(m.reagents or {}) do
        local qty = math.floor(rm.needToBuy or 0)
        if qty > 0 then
            local entry
            if hasConvert then
                local qualityID = rm.itemID and
                    C_TradeSkillUI.GetItemReagentQualityByItemInfo(rm.itemID) or nil
                local searchTerm = { searchString = rm.name, quantity = qty, isExact = true }
                if qualityID and qualityID > 0 then searchTerm.tier = qualityID end
                entry = Auctionator.API.v1.ConvertToSearchString(addonName, searchTerm)
            else
                local _, link
                if rm.itemID then
                    _, link = GetItemInfo(rm.itemID)
                end
                entry = link or rm.name
            end
            if entry then
                searchStrings[#searchStrings + 1] = entry
                qtySummary[#qtySummary + 1] = string.format("  %s: |cffffd700%d|r", rm.name, qty)
            end
        end
    end

    if #searchStrings == 0 then
        print("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_NO_ITEMS"])
        return
    end
    local listName = GAM.L["AUCTIONATOR_LIST_NAME"]
    Auctionator.API.v1.CreateShoppingList(addonName, listName, searchStrings)
    print(string.format("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_CREATED"], listName, #searchStrings))
    for _, line in ipairs(qtySummary) do print(line) end
end

-- ===== Metrics section =====
local function RefreshMetrics()
    if not frame or not currentStrat then return end
    local m = metricsCache   -- already computed by SD.Refresh()
    if not m then return end

    frame.metCost:SetText(m.totalCostFull and GAM.Pricing.FormatPrice(m.totalCostFull) or GAM.L["NO_PRICE"])
    frame.metRevenue:SetText(m.netRevenue and GAM.Pricing.FormatPrice(m.netRevenue) or GAM.L["NO_PRICE"])
    if m.profit then
        local c = m.profit >= 0 and "|cff55ff55" or "|cffff5555"
        frame.metProfit:SetText(c .. GAM.Pricing.FormatPrice(m.profit) .. "|r")
    else
        frame.metProfit:SetText("|cff888888" .. GAM.L["NO_PRICE"] .. "|r")
    end

    if m.roi then
        local c = m.roi >= 0 and "|cff55ff55" or "|cffff5555"
        frame.metROI:SetText(c .. string.format("%.2f%%", m.roi) .. "|r")
    else
        frame.metROI:SetText("|cff888888—|r")
    end

    frame.metBreakeven:SetText(m.breakEvenSell and GAM.Pricing.FormatPrice(m.breakEvenSell) or "|cff888888—|r")
    if frame.expNotice then
        local buyNow = m.totalCostToBuy and GAM.Pricing.FormatPrice(m.totalCostToBuy) or GAM.L["NO_PRICE"]
        frame.expNotice:SetText((GAM.L["LBL_BUY_NOW_COST"] or "Buy Now Cost:") .. " " .. buyNow)
        frame.expNotice:Show()
    end
end

-- ===== Reagent rows =====
local reagentRows = {}

local function MakeReagentRow(parent, idx)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(TABLE_ROW_W, ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(idx - 1) * ROW_H)
    row:SetHyperlinksEnabled(false)
    row:SetScript("OnMouseUp",  ItemRowClick)
    row:SetScript("OnEnter",    ItemRowEnter)
    row:SetScript("OnLeave",    ItemRowLeave)

    -- Column x positions: Item | Total Qty | In Bags | NeedBuy | UnitPrice | TotalCost | [Scan]
    -- colX[3] shifted left to 232 to give COL_HAVE 88px (fits translated "In Bags" labels).
    -- COL_QTY_CRAFT narrows from 80 to 62px accordingly; "Total Qty" and its translations are short.
    local colX = { 0, 170, 232, 320, 400, 500, 590 }

    local function MakeFontCell(xOff, w)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", row, "TOPLEFT", xOff, 0)
        fs:SetSize(w - 4, ROW_H)
        fs:SetJustifyH("LEFT")
        return fs
    end

    row.nameText  = MakeFontCell(colX[1], colX[2] - colX[1])

    -- Total Qty: FontString for secondary rows, EditBox for primary reagent
    local qtyFS = MakeFontCell(colX[2], colX[3] - colX[2])
    local qtyEB = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    qtyEB:SetSize(58, 20)   -- narrowed to match 62px COL_QTY_CRAFT column (colX[3]-colX[2]=62)
    qtyEB:SetPoint("TOPLEFT", row, "TOPLEFT", colX[2], 1)
    qtyEB:SetAutoFocus(false)
    qtyEB:SetNumeric(false)
    local function SaveInputQty(self)
        if currentStrat then
            SetInputQtyOverride(self:GetText())
            SD.Refresh()
        end
        self:ClearFocus()
    end
    -- Only commit on explicit Enter; OnEditFocusLost fires before row-click events
    -- propagate, so calling SD.Refresh() there can eat the click and prevent switching strategies.
    qtyEB:SetScript("OnEnterPressed", SaveInputQty)
    qtyEB:SetScript("OnEditFocusLost", function(self) self:ClearFocus() end)
    qtyFS:Hide()
    qtyEB:Hide()
    row.qtyText = qtyFS   -- alias kept for non-primary path
    row.qtyEB   = qtyEB

    row.haveText  = MakeFontCell(colX[3], colX[4] - colX[3])  -- In Bags (read-only)
    row.needText  = MakeFontCell(colX[4], colX[5] - colX[4])
    row.priceText = MakeFontCell(colX[5], colX[6] - colX[5])
    row.costText  = MakeFontCell(colX[6], colX[7] - colX[6])

    -- Scan button
    local scanBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    scanBtn:SetSize(40, 18)
    scanBtn:SetText(GAM.L["BTN_SCAN_ITEM"])
    scanBtn:SetWidth(MeasureButtonWidth(row, scanBtn:GetText(), 40, ROW_SCAN_BTN_MAX_W, 14))
    scanBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    scanBtn:SetScript("OnClick", function()
        if not GAM.ahOpen then
            print("|cffff8800[GAM]|r " .. GAM.L["ERR_NO_AH"])
            return
        end
        local rData = row.reagentData
        if not rData then return end
        GAM.AHScan.StopScan()
        GAM.AHScan.ResetQueue()
        local pdb = GetPDB()
        local ids = rData.itemIDs
        if (not ids or #ids == 0) and rData.name then
            ids = pdb.rankGroups[rData.name] or {}
        end
        if ids and #ids > 0 then
            for _, id in ipairs(ids) do
                GAM.AHScan.QueueItemScan(id, function() SD.Refresh() end)
            end
            GAM.AHScan.StartScan()
        else
            GAM.AHScan.QueueNameScan(rData.name, currentPatch, function() SD.Refresh() end)
            GAM.AHScan.StartScan()
        end
    end)
    scanBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(GAM.L["TT_SCAN_ITEM_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(GAM.L["TT_SCAN_ITEM_BODY"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    scanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.scanBtn = scanBtn

    return row
end

local function PopulateReagentRow(row, reagentMetric, isPrimary)
    -- Store a scannable reference derived from the metric (expanded item, not original strat def)
    row.reagentData = { itemIDs = reagentMetric.itemID and {reagentMetric.itemID} or {}, name = reagentMetric.name }
    local display = GAM.Pricing.GetItemDisplayData(reagentMetric.itemID, reagentMetric.name)
    row.nameText:SetText(display.displayText)
    BindItemRow(row, display)

    local qtyStr = string.format("%.0f", reagentMetric.required or 0)
    if isPrimary then
        row.qtyEB:Show()
        row.qtyText:Hide()
        if not row.qtyEB:HasFocus() then row.qtyEB:SetText(qtyStr) end
    else
        row.qtyEB:Hide()
        row.qtyText:Show()
        row.qtyText:SetText(qtyStr)
    end
    row.haveText:SetText(string.format("%.0f", reagentMetric.have or 0))
    row.needText:SetText(string.format("%.0f", reagentMetric.needToBuy or 0))
    row._metricTooltip = {
        kind = "reagent",
        unitPrice = reagentMetric.unitPrice,
        required = reagentMetric.required,
        needToBuy = reagentMetric.needToBuy,
        totalCost = reagentMetric.totalCost,
        totalCostFull = reagentMetric.totalCostFull,
    }

    if reagentMetric.unitPrice then
        row.priceText:SetText(GAM.Pricing.FormatPrice(reagentMetric.unitPrice))
    else
        row.priceText:SetText("|cffff8800" .. GAM.L["NO_PRICE"] .. "|r")
    end

    if reagentMetric.totalCost then
        row.costText:SetText(GAM.Pricing.FormatPrice(reagentMetric.totalCost))
    else
        row.costText:SetText("|cff888888—|r")
    end

    row:Show()
end

-- ===== Output rows =====
local outputRows = {}

local function MakeOutputRow(parent, idx)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(TABLE_ROW_W, ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(idx - 1) * ROW_H)
    row:SetHyperlinksEnabled(false)
    row:SetScript("OnMouseUp",  ItemRowClick)
    row:SetScript("OnEnter",    ItemRowEnter)
    row:SetScript("OnLeave",    ItemRowLeave)

    local function MakeFontCell(xOff, w)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", row, "TOPLEFT", xOff, 0)
        fs:SetSize(w - 4, ROW_H)
        fs:SetJustifyH("LEFT")
        return fs
    end

    row.nameText    = MakeFontCell(0, 196)
    row.priceText   = MakeFontCell(290, 126)
    row.revenueText = MakeFontCell(420, 126)

    -- Qty: FontString for display, EditBox for primary output
    local qtyFS = MakeFontCell(200, 86)
    local qtyEB = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    qtyEB:SetSize(80, 20)
    qtyEB:SetPoint("TOPLEFT", row, "TOPLEFT", 200, 1)
    qtyEB:SetAutoFocus(false)
    qtyEB:SetNumeric(false)
    -- Output qty is read-only (derived from input qty); no script handlers needed.
    qtyFS:Hide()
    qtyEB:Hide()
    row.qtyFS = qtyFS
    row.qtyEB = qtyEB

    -- Scan button
    local scanBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    scanBtn:SetSize(40, 18)
    scanBtn:SetText(GAM.L["BTN_SCAN_ITEM"])
    scanBtn:SetWidth(MeasureButtonWidth(row, scanBtn:GetText(), 40, ROW_SCAN_BTN_MAX_W, 14))
    scanBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    scanBtn:SetScript("OnClick", function()
        if not GAM.ahOpen then return end
        local od = row.outputData
        if not od then return end
        GAM.AHScan.StopScan()
        GAM.AHScan.ResetQueue()
        if od.itemID then
            GAM.AHScan.QueueItemScan(od.itemID, function() SD.Refresh() end)
        elseif od.name then
            GAM.AHScan.QueueNameScan(od.name, currentPatch, function() SD.Refresh() end)
        end
        GAM.AHScan.StartScan()
    end)
    scanBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(GAM.L["TT_SCAN_ITEM_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(GAM.L["TT_SCAN_ITEM_BODY"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    scanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.scanBtn = scanBtn

    return row
end

local function PopulateOutputRow(row, outputMetric, isPrimary)
    row.outputData = outputMetric
    row._metricTooltip = {
        kind = "output",
        unitPrice = outputMetric.unitPrice,
        expectedQty = outputMetric.expectedQty,
        netRevenue = outputMetric.netRevenue,
    }
    local display = GAM.Pricing.GetItemDisplayData(outputMetric.itemID, outputMetric.name)
    row.nameText:SetText(display.displayText)
    BindItemRow(row, display)

    local qtyStr = outputMetric.expectedQty
        and string.format("%.0f", math.floor(outputMetric.expectedQty)) or "—"
    row.qtyEB:Hide()
    row.qtyFS:Show()
    row.qtyFS:SetText(qtyStr)

    row.priceText:SetText(outputMetric.unitPrice
        and GAM.Pricing.FormatPrice(outputMetric.unitPrice)
        or "|cffff8800" .. GAM.L["NO_PRICE"] .. "|r")

    -- netRevenue is pre-computed in CalculateStratMetrics (after AH cut, integer copper).
    -- Using it here keeps the output row consistent with the bottom "Net Revenue" label.
    row.revenueText:SetText(outputMetric.netRevenue
        and GAM.Pricing.FormatPrice(outputMetric.netRevenue)
        or "|cff888888—|r")

    row:Show()
end

-- ===== Build =====
local function Build()
    local L = GAM.L
    local GR,  GG,  GB  = 1.0, 0.82, 0.0   -- gold accent
    local GDR, GDG, GDB = 0.7, 0.57, 0.0   -- dimmed gold for rules/borders

    frame = CreateFrame("Frame", "GoldAdvisorMidnightStratDetail", UIParent,
                        "BackdropTemplate")
    frame:SetSize(WIN_W, WIN_H)
    frame:SetPoint("CENTER", UIParent, "CENTER")  -- placeholder so child scroll frames get valid width at build time
    frame:SetScale(GAM.db and GAM.db.options and GAM.db.options.uiScale or 1.0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    -- DIALOG renders above HIGH (where Blizzard widget frames live).
    -- SetToplevel raises frame level within DIALOG when clicked.
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left=11, right=12, top=12, bottom=11 },
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    -- Explicit solid fill guards against backdrop edge cases (strata clipping, alpha inheritance).
    local bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0, 0, 0, 1)
    frame:Hide()

    -- Title
    local titleFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOP", frame, "TOP", 0, -10)
    titleFS:SetText(L["DETAIL_TITLE"])
    frame.titleFS = titleFS

    -- Thin gold underline below title
    local titleRule = frame:CreateTexture(nil, "ARTWORK")
    titleRule:SetHeight(1)
    titleRule:SetPoint("TOPLEFT",  frame, "TOPLEFT",  14, -28)
    titleRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -28)
    titleRule:SetColorTexture(GDR, GDG, GDB, 0.7)

    -- Close
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Strat name
    local stratNameFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stratNameFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -34)
    stratNameFS:SetWidth(WIN_W - 80)
    stratNameFS:SetJustifyH("LEFT")
    frame.stratNameFS = stratNameFS

    -- Notes
    local notesFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    notesFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -52)
    notesFS:SetWidth(WIN_W - 28)
    notesFS:SetTextColor(0.8, 0.8, 0.5)
    notesFS:SetJustifyH("LEFT")
    frame.notesFS = notesFS

    -- ── Input Section Frame ──
    local inputSection = CreateFrame("Frame", nil, frame)
    inputSection:SetPoint("TOPLEFT",  notesFS, "BOTTOMLEFT",  0, -10)
    inputSection:SetPoint("TOPRIGHT", notesFS, "BOTTOMRIGHT", 0, -10)
    inputSection:SetHeight(224)

    local inHdr = inputSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    inHdr:SetPoint("TOPLEFT", inputSection, "TOPLEFT", 0, 0)
    inHdr:SetText(L["DETAIL_INPUT_HDR"])
    inHdr:SetTextColor(GR, GG, GB)

    local inColDefs = {
        { L["COL_ITEM"],       0,   170 },
        { L["COL_QTY_CRAFT"], 170,   62 },  -- narrowed; col shifts at colX[3]=232
        { L["COL_HAVE"],      232,   88 },  -- widened for translated "In Bags" labels
        { L["COL_NEED_BUY"],  320,   80 },
        { L["COL_UNIT_PRICE"],400,  100 },
        { L["COL_TOTAL_COST"],500,   90 },
    }
    for _, cd in ipairs(inColDefs) do
        local fs = inputSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", inputSection, "TOPLEFT", cd[2], -22)
        fs:SetWidth(cd[3])
        fs:SetText(cd[1])
    end

    local inSep = inputSection:CreateTexture(nil, "ARTWORK")
    inSep:SetColorTexture(GDR, GDG, GDB, 0.7)
    inSep:SetPoint("TOPLEFT",  inputSection, "TOPLEFT",  0,  -43)
    inSep:SetPoint("TOPRIGHT", inputSection, "TOPRIGHT", -20, -43)
    inSep:SetHeight(1)

    inputScrollFrame = CreateFrame("ScrollFrame", nil, inputSection, "UIPanelScrollFrameTemplate")
    inputScrollFrame:SetPoint("TOPLEFT",     inputSection, "TOPLEFT",     0,  -45)
    inputScrollFrame:SetPoint("BOTTOMRIGHT", inputSection, "BOTTOMRIGHT", -20, 0)

    inputListHost = CreateFrame("Frame", nil, inputScrollFrame)
    inputListHost:SetWidth(inputScrollFrame:GetWidth())
    inputListHost:SetHeight(1)
    inputScrollFrame:SetScrollChild(inputListHost)

    inputListHost:EnableMouseWheel(true)
    inputListHost:SetScript("OnMouseWheel", function(_, delta)
        local cur = inputScrollFrame:GetVerticalScroll()
        local max = inputScrollFrame:GetVerticalScrollRange()
        inputScrollFrame:SetVerticalScroll(math.max(0, math.min(max, cur - delta * (ROW_H * 3))))
    end)

    for i = 1, 16 do
        reagentRows[i] = MakeReagentRow(inputListHost, i)
        reagentRows[i]:Hide()
    end

    -- ── Output Section Frame ──
    local outputSection = CreateFrame("Frame", nil, frame)
    outputSection:SetPoint("TOPLEFT",  inputSection, "BOTTOMLEFT",  0, -6)
    outputSection:SetPoint("TOPRIGHT", inputSection, "BOTTOMRIGHT", 0, -6)
    outputSection:SetHeight(152)

    local outHdr = outputSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    outHdr:SetPoint("TOPLEFT", outputSection, "TOPLEFT", 0, 0)
    outHdr:SetText(L["DETAIL_OUTPUT_HDR"])
    outHdr:SetTextColor(GR, GG, GB)

    local outColDefs = {
        { L["COL_ITEM"],          0,   200 },
        { L["COL_QTY_CRAFT"],   200,    90 },
        { L["COL_AH_SELL_PRICE"],290,  130 },
        { L["COL_REVENUE"],     420,   130 },
    }
    for _, cd in ipairs(outColDefs) do
        local fs = outputSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", outputSection, "TOPLEFT", cd[2], -22)
        fs:SetWidth(cd[3])
        fs:SetText(cd[1])
    end

    local outSep = outputSection:CreateTexture(nil, "ARTWORK")
    outSep:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    outSep:SetPoint("TOPLEFT",  outputSection, "TOPLEFT",  0,  -43)
    outSep:SetPoint("TOPRIGHT", outputSection, "TOPRIGHT", -20, -43)
    outSep:SetHeight(1)

    outputScrollFrame = CreateFrame("ScrollFrame", nil, outputSection, "UIPanelScrollFrameTemplate")
    outputScrollFrame:SetPoint("TOPLEFT",     outputSection, "TOPLEFT",     0,  -45)
    outputScrollFrame:SetPoint("BOTTOMRIGHT", outputSection, "BOTTOMRIGHT", -20, 0)

    outputListHost = CreateFrame("Frame", nil, outputScrollFrame)
    outputListHost:SetWidth(outputScrollFrame:GetWidth())
    outputListHost:SetHeight(1)
    outputScrollFrame:SetScrollChild(outputListHost)

    outputListHost:EnableMouseWheel(true)
    outputListHost:SetScript("OnMouseWheel", function(_, delta)
        local cur = outputScrollFrame:GetVerticalScroll()
        local max = outputScrollFrame:GetVerticalScrollRange()
        outputScrollFrame:SetVerticalScroll(math.max(0, math.min(max, cur - delta * (ROW_H * 3))))
    end)

    for i = 1, 8 do
        outputRows[i] = MakeOutputRow(outputListHost, i)
        outputRows[i]:Hide()
    end

    -- ── Metrics section — 2-column layout, Profit centered ──
    local function MakeMetricPair(label, xOff, yOff, valWidth)
        local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", xOff, yOff)
        lbl:SetWidth(110)
        lbl:SetText(label)
        local val = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        val:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
        val:SetWidth(valWidth or 200)
        return val
    end

    local function MakeCenteredMetric(label, yOff)
        -- Thin gold rule above Profit as a visual separator
        local rule = frame:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        rule:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  14, yOff + 17)
        rule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, yOff + 17)
        rule:SetColorTexture(GDR, GDG, GDB, 0.7)

        local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, yOff)
        lbl:SetWidth(110)
        lbl:SetJustifyH("RIGHT")
        lbl:SetText(label)
        local val = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        val:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, yOff)
        val:SetWidth(160)
        val:SetJustifyH("LEFT")
        return val
    end

    -- Invisible button overlay for FontString labels (FontStrings can't have OnEnter).
    -- Positioned over the label+value area so hovering shows a tooltip.
    local function MakeTooltipAnchor(x, y, w, titleKey, bodyKey)
        local anchor = CreateFrame("Button", nil, frame)
        anchor:SetSize(w, 18)
        anchor:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, y - 2)
        anchor:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(GAM.L[titleKey] or titleKey, 1, 1, 1)
            GameTooltip:AddLine(GAM.L[bodyKey] or bodyKey, 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        anchor:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    frame.metCost      = MakeMetricPair(L["LBL_COST"],       14,  95, 200)
    frame.metRevenue   = MakeMetricPair(L["LBL_REVENUE"],    14,  75, 200)
    frame.metROI       = MakeMetricPair(L["LBL_ROI"],       364,  95, 180)
    frame.metBreakeven = MakeMetricPair(L["LBL_BREAKEVEN"], 364,  75, 180)
    frame.metProfit    = MakeCenteredMetric(L["LBL_PROFIT"],      PROFIT_BASE_Y)

    -- Tooltip anchors over metric label pairs
    MakeTooltipAnchor( 14,  95, 310, "TT_LBL_COST_TITLE",      "TT_LBL_COST_BODY")
    MakeTooltipAnchor( 14,  75, 310, "TT_LBL_REVENUE_TITLE",   "TT_LBL_REVENUE_BODY")
    MakeTooltipAnchor(364,  95, 310, "TT_LBL_ROI_TITLE",       "TT_LBL_ROI_BODY")
    MakeTooltipAnchor(364,  75, 310, "TT_LBL_BREAKEVEN_TITLE", "TT_LBL_BREAKEVEN_BODY")
    -- Profit is centred; anchor spans the middle region
    MakeTooltipAnchor(WIN_W / 2 - 155, PROFIT_BASE_Y, 310, "TT_LBL_PROFIT_TITLE", "TT_LBL_PROFIT_BODY")

    -- Orange notice line reused for Buy Now Cost.
    local expNotice = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    expNotice:SetWidth(WIN_W - 40)
    expNotice:SetJustifyH("CENTER")
    expNotice:SetTextColor(1.0, 0.65, 0.0, 1.0)
    expNotice:Hide()
    frame.expNotice = expNotice
    local expNoticeAnchor = CreateFrame("Button", nil, frame)
    expNoticeAnchor:SetSize(WIN_W - 40, 18)
    expNoticeAnchor:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(GAM.L["TT_LBL_BUY_NOW_COST_TITLE"] or "Buy Now Cost", 1, 1, 1)
        GameTooltip:AddLine(GAM.L["TT_LBL_BUY_NOW_COST_BODY"] or "Only the cost of materials you still need to buy after subtracting items already in your bags and bank.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    expNoticeAnchor:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.expNoticeAnchor = expNoticeAnchor
    -- ── Bottom buttons ──
    -- Rank toggle
    local rankToggleBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    rankToggleBtn:SetSize(80, 22)
    rankToggleBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 20)
    rankToggleBtn:SetScript("OnClick", function()
        if not GAM.db or not GAM.db.options then return end
        local cur = GAM.db.options.rankPolicy or "lowest"
        GAM.db.options.rankPolicy = (cur == "highest") and "lowest" or "highest"
        SD.Refresh()
    end)
    frame.rankToggleBtn = rankToggleBtn

    -- Auctionator button
    local btnAuctionator = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnAuctionator:SetSize(120, 22)
    btnAuctionator:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 104, 20)
    btnAuctionator:SetText(L["BTN_AUCTIONATOR"])
    btnAuctionator:SetScript("OnClick", function() CreateAuctionatorList() end)

    -- Push to CraftSim button (centered)
    local btnCraftSim = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnCraftSim:SetSize(140, 22)
    btnCraftSim:SetPoint("BOTTOM", frame, "BOTTOM", 0, 20)
    btnCraftSim:SetText(L["BTN_PUSH_CRAFTSIM"])
    btnCraftSim:SetScript("OnClick", function()
        if not currentStrat then return end
        local pushed, err = GAM.CraftSimBridge.PushStratPrices(currentStrat, currentPatch)
        if err then
            print("|cffff8800[GAM]|r CraftSim push failed: " .. err)
        elseif pushed == 0 then
            print("|cffff8800[GAM]|r No prices to push — scan items first.")
        else
            print(string.format("|cffff8800[GAM]|r Pushed %d price(s) to CraftSim.", pushed))
        end
    end)
    btnCraftSim:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(GAM.L["TT_CRAFTSIM_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(GAM.L["TT_CRAFTSIM_WARN"], 1, 0.8, 0, true)
        GameTooltip:Show()
    end)
    btnCraftSim:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    btnAuctionator:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(GAM.L["TT_SHOPPING_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(GAM.L["TT_SHOPPING_BODY"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    btnAuctionator:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Scan All button
    local scanAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    scanAllBtn:SetSize(110, 22)
    scanAllBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 20)
    scanAllBtn:SetText(L["BTN_SCAN_ALL_ITEMS"])
    scanAllBtn:SetScript("OnClick", function()
        if not GAM.ahOpen or not currentStrat then return end
        GAM.AHScan.StopScan()
        GAM.AHScan.ResetQueue()
        local pdb = GetPDB()
        local active = (GAM.Pricing and GAM.Pricing.GetActiveRecipeView and GAM.Pricing.GetActiveRecipeView(currentStrat)) or currentStrat
        local seenIDs = {}
        local seenNames = {}
        local function queueItem(item)
            if not item or not item.name then return end
            local ids = item.itemIDs
            if (not ids or #ids == 0) then ids = pdb.rankGroups[item.name] or {} end
            if ids and #ids > 0 then
                for _, id in ipairs(ids) do
                    if not seenIDs[id] then
                        seenIDs[id] = true
                        GAM.AHScan.QueueItemScan(id, function() SD.Refresh() end)
                    end
                end
            else
                local nameKey = item.name .. "@" .. tostring(currentPatch or GAM.C.DEFAULT_PATCH)
                if not seenNames[nameKey] then
                    seenNames[nameKey] = true
                    GAM.AHScan.QueueNameScan(item.name, currentPatch, function() SD.Refresh() end)
                end
            end
        end
        queueItem(active.output)
        if active.outputs then
            for _, o in ipairs(active.outputs) do queueItem(o) end
        end
        -- Use the expanded reagent list from the last metrics computation so that
        -- Scan All queues raw materials (ores, herbs) when vertical integration is on,
        -- not the intermediate crafted items (ingots, pigments) from the base recipe.
        local activeReagents = metricsCache and metricsCache.reagents
        if activeReagents and #activeReagents > 0 then
            for _, r in ipairs(activeReagents) do
                queueItem({ itemIDs = r.itemID and {r.itemID} or {}, name = r.name })
            end
        else
            for _, r in ipairs(active.reagents or {}) do queueItem(r) end
        end
        GAM.AHScan.StartScan()
    end)
    scanAllBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(GAM.L["TT_SCAN_ALL_ITEMS_TITLE"], 1, 1, 1)
        GameTooltip:AddLine(GAM.L["TT_SCAN_ALL_ITEMS_BODY"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    scanAllBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function RelayoutBottomButtons()
        rankToggleBtn:SetWidth(MeasureButtonWidth(frame, rankToggleBtn:GetText(), 80, 180, 24))
        btnAuctionator:SetWidth(MeasureButtonWidth(frame, btnAuctionator:GetText(), 120, 260, 24))
        btnCraftSim:SetWidth(MeasureButtonWidth(frame, btnCraftSim:GetText(), 140, 300, 24))
        scanAllBtn:SetWidth(MeasureButtonWidth(frame, scanAllBtn:GetText(), 110, 260, 24))
        local info = LayoutButtonRowBottom(frame,
            { rankToggleBtn, btnAuctionator, btnCraftSim, scanAllBtn },
            { left = 14, right = WIN_W - 14, bottom = 12, gap = 8, rowGap = 4, align = "center" })
        local profitY    = PROFIT_BASE_Y
        local lowerBound = info.top + MIN_NOTICE_GAP_ABOVE_BUTTONS
        local upperBound = profitY - MIN_NOTICE_GAP_BELOW_PROFIT
        local noticeY
        if lowerBound <= upperBound then
            noticeY = math.floor((lowerBound + upperBound) * 0.5 + 0.5)
        else
            noticeY = lowerBound
        end
        if frame.expNotice then
            frame.expNotice:ClearAllPoints()
            frame.expNotice:SetPoint("BOTTOM", frame, "BOTTOM", 0, noticeY)
        end
        if frame.expNoticeAnchor then
            frame.expNoticeAnchor:ClearAllPoints()
            frame.expNoticeAnchor:SetPoint("BOTTOM", frame, "BOTTOM", 0, noticeY - 2)
        end
        GAM.Log.Verbose("StratDetail: warning layout bounds lower=%d upper=%d chosen=%d",
            lowerBound, upperBound, noticeY)
    end
    frame.RelayoutBottomButtons = RelayoutBottomButtons
    RelayoutBottomButtons()

    -- Delete button — top-right, only visible for user-created strats.
    -- Shows a confirm dialog before removing the strat.
    local btnDelete = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnDelete:SetSize(80, 22)
    btnDelete:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -6)
    btnDelete:SetText(L["BTN_DELETE_STRAT"])
    btnDelete:SetWidth(MeasureButtonWidth(frame, btnDelete:GetText(), 80, 240, 24))
    btnDelete:SetScript("OnClick", function()
        if not currentStrat then return end
        ShowDeleteConfirm(currentStrat)
    end)
    btnDelete:Hide()
    frame.btnDelete = btnDelete

    -- Edit button — only visible for user-created strats (_isUser = true).
    -- Opens the StratCreator in edit mode pre-populated with this strat's values.
    local btnEdit = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnEdit:SetSize(65, 22)
    btnEdit:SetWidth(MeasureButtonWidth(frame, L["BTN_EDIT_STRAT"], 65, 220, 24))
    btnEdit:SetText(L["BTN_EDIT_STRAT"])
    btnEdit:SetScript("OnClick", function()
        if currentStrat and GAM.UI and GAM.UI.StratCreator then
            GAM.UI.StratCreator.ShowEdit(currentStrat)
        end
    end)
    btnEdit:Hide()
    frame.btnEdit = btnEdit

    -- Export button — only visible for user-created strats (_isUser = true).
    -- Opens the export popup with an encoded string and a raw Lua snippet.
    local btnExport = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnExport:SetSize(70, 22)
    btnExport:SetWidth(MeasureButtonWidth(frame, L["BTN_EXPORT_STRAT"], 70, 220, 24))
    btnExport:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -34)
    btnEdit:SetPoint("RIGHT", btnExport, "LEFT", -8, 0)
    btnExport:SetText(L["BTN_EXPORT_STRAT"])
    btnExport:SetScript("OnClick", function()
        if currentStrat and GAM.UI and GAM.UI.StratCreator then
            GAM.UI.StratCreator.ShowExportPopup(currentStrat)
        end
    end)
    btnExport:Hide()
    frame.btnExport = btnExport
end

-- ===== Public API =====

function SD.Show(strat, patchTag)
    if not frame then Build() end
    if not positioned then
        frame:ClearAllPoints()
        local mwF = _G["GoldAdvisorMidnightMainWindowV2"]
        if mwF then
            local screenW = UIParent:GetWidth()
            local mwRight = mwF:GetRight() or (screenW / 2 + 360)
            if mwRight + 10 + WIN_W <= screenW then
                frame:SetPoint("TOPLEFT", mwF, "TOPRIGHT", 10, 0)
            else
                frame:SetPoint("TOPRIGHT", mwF, "TOPLEFT", -10, 0)
            end
        else
            frame:SetPoint("CENTER", UIParent, "CENTER")
        end
        positioned = true
    end
    if strat then
        currentStrat = strat
        currentPatch = patchTag or GAM.C.DEFAULT_PATCH
    end
    SD.Refresh()
    frame:Show()
end

function SD.Refresh()
    if not frame or not currentStrat then return end
    GAM.Pricing.PreloadStratItemData(currentStrat, currentPatch)
    local L = GAM.L

    frame.stratNameFS:SetText(currentStrat.stratName .. " (" .. currentStrat.profession .. ")")
    frame.notesFS:SetText(currentStrat.notes or "")

    -- Compute metrics
    local m = GAM.Pricing.CalculateStratMetrics(currentStrat, currentPatch)
    metricsCache = m

    -- Rank toggle label
    if frame.rankToggleBtn then
        local policy = (GAM.db and GAM.db.options and GAM.db.options.rankPolicy) or "lowest"
        -- Button shows what clicking will switch TO (action label, not current state)
        frame.rankToggleBtn:SetText(policy == "highest" and L["RANK_BTN_R1"] or L["RANK_BTN_R2"])
        if frame.RelayoutBottomButtons then frame.RelayoutBottomButtons() end
    end

    -- Show Delete / Edit / Export only for user-created strats
    local isUser = currentStrat._isUser == true
    if frame.btnDelete then frame.btnDelete:SetShown(isUser) end
    if frame.btnEdit   then frame.btnEdit:SetShown(isUser)   end
    if frame.btnExport then frame.btnExport:Hide() end

    -- Reagents
    -- Only the topmost input row is editable so the field remains stable while browsing.
    local reagentMetrics = m and m.reagents or {}

    -- Guard: only show the editable primary field on row 1 when chain expansion has NOT
    -- changed the first reagent (i.e. the displayed item still matches the base strat's
    -- first reagent).  If the first base reagent expanded to something else (e.g. pigments
    -- to herbs when Mill own herbs is on), the editbox would write the herb qty into
    -- inputQtyOverrides, which expects the strategy's own startingAmount scale.
    local firstMetID  = reagentMetrics[1] and reagentMetrics[1].itemID
    local baseR1IDs   = currentStrat.reagents and currentStrat.reagents[1] and currentStrat.reagents[1].itemIDs or {}
    local firstUnchanged = false
    for _, id in ipairs(baseR1IDs) do
        if id == firstMetID then firstUnchanged = true; break end
    end

    -- Render from m.reagents (expanded/merged metrics) as the source of truth so that
    -- chain-expanded rows (e.g. ore when craft-ingots is on) display correctly.
    for i, row in ipairs(reagentRows) do
        local rMet = reagentMetrics[i]
        if rMet then
            PopulateReagentRow(row, rMet, i == 1 and firstUnchanged)
        else
            BindItemRow(row, nil)
            row:Hide()
            row.reagentData = nil
            row._metricTooltip = nil
        end
    end

    -- Resize input scroll child to match actual expanded reagent count
    if inputListHost then
        inputListHost:SetHeight(math.max(1, #reagentMetrics * ROW_H))
    end

    -- Output section
    -- For multi-output strats, list only explicit outputs[] rows.
    -- For single-output strats, list m.output.
    local outputItems = {}
    if m and m.outputs and #m.outputs > 0 then
        for _, oi in ipairs(m.outputs) do
            outputItems[#outputItems + 1] = { metric = oi, isPrimary = false }
        end
    elseif m and m.output then
        outputItems[1] = { metric = m.output, isPrimary = true }
    end

    for i, row in ipairs(outputRows) do
        local oi = outputItems[i]
        if oi then
            PopulateOutputRow(row, oi.metric, oi.isPrimary)
        else
            BindItemRow(row, nil)
            row._metricTooltip = nil
            row:Hide()
        end
    end

    if outputListHost then
        outputListHost:SetHeight(math.max(1, #outputItems * ROW_H))
    end

    RefreshMetrics()
end

function SD.Hide()
    if frame then frame:Hide() end
end

function SD.IsShown()
    return frame and frame:IsShown()
end

-- ===== Inline panel mode (Phase 5 — stub) =====
-- Called by MainWindowV2 when the right panel is visible.
-- Currently delegates to the floating SD.Show(); full inline rendering
-- (reparented contentHost, 340px layout) will replace this in Phase 5.
function SD.ShowInPanel(strat, patchTag, panelFrame)
    SD.Show(strat, patchTag)
end
