-- GoldAdvisorMidnight/UI/ShoppingList.lua
-- Aggregated shopping list: sum NeedToBuy across selected strats.
-- Module: GAM.UI.ShoppingList

local ADDON_NAME, GAM = ...
local SL = {}
GAM.UI.ShoppingList = SL

-- Disabled: Auctionator export has been moved into StratDetail.
-- Keep code intact; frame is never built.
SL._disabled = true

local WIN_W, WIN_H = 480, 520
local ROW_H        = 20

local frame
local currentStrats = nil
local currentPatch  = nil
local aggregated    = {}   -- [ { name, needed, have } ]

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

-- ===== Aggregation =====
local function Aggregate(strats, patchTag)
    local totals = {}  -- [name] = { needed=0, have=0, itemID=nil }

    for _, strat in ipairs(strats or {}) do
        local m = GAM.Pricing.CalculateStratMetrics(strat, patchTag)
        if m then
            local pdb = GAM:GetPatchDB(patchTag)
            for _, rm in ipairs(m.reagents) do
                local key = rm.name
                if not totals[key] then
                    totals[key] = { name = key, needed = 0, have = 0, itemID = rm.itemID }
                end
                totals[key].needed = totals[key].needed + rm.needToBuy
                totals[key].have   = totals[key].have   + rm.have
            end
        end
    end

    -- Sort by item name
    local out = {}
    for _, v in pairs(totals) do
        out[#out + 1] = v
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- ===== Row frames =====
local rowFrames = {}

local function MakeRow(parent, idx)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIN_W - 28, ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(idx - 1) * ROW_H)

    local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetPoint("LEFT", row, "LEFT", 0, 0)
    nameFS:SetWidth(200)
    nameFS:SetJustifyH("LEFT")
    row.nameFS = nameFS

    local haveFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    haveFS:SetPoint("LEFT", row, "LEFT", 208, 0)
    haveFS:SetWidth(80)
    haveFS:SetJustifyH("RIGHT")
    row.haveFS = haveFS

    local needFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    needFS:SetPoint("LEFT", row, "LEFT", 296, 0)
    needFS:SetWidth(80)
    needFS:SetJustifyH("RIGHT")
    row.needFS = needFS

    return row
end

-- ===== Build =====
local scrollFrame
local listHost

local function Refresh()
    if not frame then return end
    aggregated = Aggregate(currentStrats, currentPatch)

    for i, row in ipairs(rowFrames) do
        local item = aggregated[i]
        if item then
            row.nameFS:SetText(item.name)
            row.haveFS:SetText(string.format("%.0f", item.have))
            if item.needed > 0 then
                row.needFS:SetText("|cffff8080" .. string.format("%.0f", item.needed) .. "|r")
            else
                row.needFS:SetText("|cff55ff55" .. string.format("%.0f", item.needed) .. "|r")
            end
            row:Show()
        else
            row:Hide()
        end
    end

    -- Update host height for scrolling
    local total = #aggregated
    if listHost then
        listHost:SetHeight(math.max(1, total * ROW_H))
    end

    if total == 0 and frame.emptyFS then
        frame.emptyFS:Show()
    elseif frame.emptyFS then
        frame.emptyFS:Hide()
    end
end

local function FormatCopyText()
    local lines = {}
    lines[1] = "-- Gold Advisor Midnight Shopping List --"
    lines[2] = "Item | Have | Need"
    for _, item in ipairs(aggregated) do
        if item.needed > 0 then
            lines[#lines + 1] = string.format("%s | %d | %d", item.name, math.floor(item.have), math.floor(item.needed))
        end
    end
    return table.concat(lines, "\n")
end

local function CreateAuctionatorList()
    if not (Auctionator and Auctionator.API and Auctionator.API.v1 and
            type(Auctionator.API.v1.CreateShoppingList) == "function") then
        print("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_NOT_FOUND"])
        return
    end

    local addonName  = "GoldAdvisorMidnight"
    local hasConvert = type(Auctionator.API.v1.ConvertToSearchString) == "function"
    local searchStrings = {}
    local qtySummary    = {}

    for _, item in ipairs(aggregated) do
        local qty = math.floor(item.needed)
        if qty > 0 then
            local entry

            if hasConvert then
                local qualityID = item.itemID and
                    C_TradeSkillUI.GetItemReagentQualityByItemInfo(item.itemID) or nil

                local searchTerm = {
                    searchString = item.name,
                    quantity     = qty,
                    isExact      = true,
                }
                if qualityID and qualityID > 0 then
                    searchTerm.tier = qualityID
                end

                entry = Auctionator.API.v1.ConvertToSearchString(addonName, searchTerm)
            else
                if item.itemID then
                    local _, link = GetItemInfo(item.itemID)
                    entry = link or item.name
                else
                    entry = item.name
                end
            end

            if entry then
                searchStrings[#searchStrings + 1] = entry
                qtySummary[#qtySummary + 1] = string.format(
                    "  %s: |cffffd700%d|r", item.name, qty)
            end
        end
    end

    if #searchStrings == 0 then
        print("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_NO_ITEMS"])
        return
    end

    local listName = GAM.L["AUCTIONATOR_LIST_NAME"]
    Auctionator.API.v1.CreateShoppingList(addonName, listName, searchStrings)
    print(string.format("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_CREATED"],
        listName, #searchStrings))
    print("|cffff8800[GAM]|r Quantities needed:")
    for _, line in ipairs(qtySummary) do print(line) end
end

local function Build()
    local L = GAM.L

    frame = CreateFrame("Frame", "GoldAdvisorMidnightShoppingList", UIParent,
                        "BackdropTemplate")
    frame:SetSize(WIN_W, WIN_H)
    frame:SetScale(GetUIScale())
    local mwF = _G["GoldAdvisorMidnightMainWindow"]
    if mwF then
        frame:SetPoint("TOPRIGHT", mwF, "TOPLEFT", -10, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", -380, 0)
    end
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left=11, right=12, top=12, bottom=11 },
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:Hide()

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText(L["SHOP_TITLE"])

    -- Close
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Column headers
    local colY = -32
    local hdrs = {
        { L["SHOP_ITEM"], 14,  200 },
        { L["SHOP_HAVE"], 222, 80  },
        { L["SHOP_NEED"], 310, 80  },
    }
    for _, h in ipairs(hdrs) do
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", h[2], colY)
        fs:SetWidth(h[3])
        fs:SetText(h[1])
    end

    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    sep:SetPoint("TOPLEFT",  frame, "TOPLEFT",  14,  colY - 18)
    sep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, colY - 18)
    sep:SetHeight(1)

    -- Scroll frame
    scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, colY - 20)

    listHost = CreateFrame("Frame", nil, scrollFrame)
    listHost:SetWidth(scrollFrame:GetWidth())
    listHost:SetHeight(1)
    scrollFrame:SetScrollChild(listHost)

    listHost:EnableMouseWheel(true)
    listHost:SetScript("OnMouseWheel", function(_, delta)
        local cur = scrollFrame:GetVerticalScroll()
        local max = scrollFrame:GetVerticalScrollRange()
        scrollFrame:SetVerticalScroll(math.max(0, math.min(max, cur - delta * (ROW_H * 3))))
    end)

    -- Create row pool (max 50 items visible without scroll)
    for i = 1, 50 do
        rowFrames[i] = MakeRow(listHost, i)
        rowFrames[i]:Hide()
    end

    -- Empty label
    local emptyFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyFS:SetPoint("CENTER", scrollFrame, "CENTER")
    emptyFS:SetText(L["SHOP_EMPTY"])
    emptyFS:Hide()
    frame.emptyFS = emptyFS

    -- Auctionator button
    local auctionatorBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    auctionatorBtn:SetSize(120, 22)
    auctionatorBtn:SetText(L["BTN_AUCTIONATOR"])
    auctionatorBtn:SetScript("OnClick", function() CreateAuctionatorList() end)

    -- Copy button (opens a popup with all text)
    local copyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    copyBtn:SetSize(80, 22)
    copyBtn:SetText(L["BTN_COPY_LIST"])
    copyBtn:SetScript("OnClick", function()
        -- Show copy popup
        local txt = FormatCopyText()
        if not frame.copyPopup then
            local pop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            pop:SetSize(WIN_W - 20, 160)
            pop:SetPoint("BOTTOM", frame, "TOP", 0, 4)
            pop:SetBackdrop({
                bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left=8, right=8, top=8, bottom=8 },
            })
            pop:SetBackdropColor(0, 0, 0, 1)
            local eb = CreateFrame("EditBox", nil, pop)
            eb:SetMultiLine(true)
            eb:SetFontObject(GameFontHighlightSmall)
            eb:SetSize(WIN_W - 50, 140)
            eb:SetPoint("CENTER", pop, "CENTER")
            eb:SetAutoFocus(true)
            eb:SetScript("OnEscapePressed", function() pop:Hide() end)
            pop.eb = eb
            frame.copyPopup = pop
        end
        frame.copyPopup.eb:SetText(txt)
        frame.copyPopup.eb:SetFocus()
        frame.copyPopup.eb:HighlightText()
        frame.copyPopup:Show()
    end)

    local function RelayoutBottomButtons()
        auctionatorBtn:SetWidth(MeasureButtonWidth(frame, auctionatorBtn:GetText(), 120, 260, 24))
        copyBtn:SetWidth(MeasureButtonWidth(frame, copyBtn:GetText(), 80, 220, 24))
        local info = LayoutButtonRowBottom(frame, { auctionatorBtn, copyBtn }, {
            left = 14, right = WIN_W - 14, bottom = 20, gap = 8, rowGap = 4, align = "center",
        })
        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, colY - 20)
        scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, info.top + 8)
    end
    RelayoutBottomButtons()
end

-- ===== Public API =====

function SL.Show(strats, patchTag)
    if SL._disabled then return end
    if not frame then Build() end
    currentStrats = strats
    currentPatch  = patchTag or GAM.C.DEFAULT_PATCH
    Refresh()
    frame:Show()
end

function SL.Hide()
    if frame then frame:Hide() end
end

function SL.Toggle(strats, patchTag)
    if SL._disabled then return end
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
    else
        currentStrats = strats or currentStrats
        currentPatch  = patchTag or currentPatch or GAM.C.DEFAULT_PATCH
        Refresh()
        frame:Show()
    end
end
