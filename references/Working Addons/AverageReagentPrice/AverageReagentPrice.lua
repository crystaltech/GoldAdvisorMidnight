local addonName, ARP = ...
local AceAddon = LibStub("AceAddon-3.0")
local AceEvent = LibStub("AceEvent-3.0")
local AceConsole = LibStub("AceConsole-3.0")

ARP = AceAddon:NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0")

-- ================= SavedVariables =================
AverageReagentPriceDB = AverageReagentPriceDB or {
    quantity = 10000,
    panelPosX = nil,
    panelPosY = nil,
    panelVisible = true,
    itemDB = {},
    collapsedState = {},
    minimapHidden = false,
    minimapAngle = 45,
    panelLocked = false,
}


-- ================= Patch Version Tracking =================
local CURRENT_PATCH_VERSION = "v1.4.79"
local SHOW_PATCH_NOTICE = false  -- Set to false if this patch doesn't need a popup
ARP.version = CURRENT_PATCH_VERSION
AverageReagentPriceDB.lastSeenVersion = AverageReagentPriceDB.lastSeenVersion or ""

-- Ensure main ARP_DB table exists
ARP_DB = ARP_DB or {}
ARP.ItemKeyCache = {}

-- Ensure sub-tables exist
ARP_DB.UserLists = ARP_DB.UserLists or {}
ARP_DB.ActiveUserList = ARP_DB.ActiveUserList or nil

-- Link existing itemDB and commodityCache
ARP.itemDB = AverageReagentPriceDB.itemDB or {}
ARP.commodityCache = ARP.commodityCache or {}

function ARP:SafeGetCurrentCommodityID()
    if self.GetCurrentCommodityID then
        return self:GetCurrentCommodityID()
    else
        return nil
    end
end

-- ===============================
-- Deferred Recalc for First Launch
-- ===============================

-- Add this at the top near your main addon table
ARP.pendingRecalc = false

-- Hook panel show / AH frame open
function ARP:ShowPanel()
     local currentID = self:SafeGetCurrentCommodityID()
     if not currentID then return end

    
    -- If cache does not exist, request AH data and defer recalc
    if not self.commodityCache[currentID] then
        self.pendingRecalc = true
        -- This triggers a commodity query from AH; results come asynchronously
        self:RequestCommodityData(currentID)
        return
    end

    -- Otherwise, safe to recalc
    self:RecalculateAllAverages()
end

-- Hook your Quantity/Trim input changes
-- Only recalc if cache exists
function ARP:OnQuantityOrTrimChanged()
    local currentID = self:SafeGetCurrentCommodityID()
    if not currentID then return end
    if self.commodityCache[currentID] then
        self:RecalculateAllAverages()
    end
end

-- ====== Helper variables for commodity updates ======
local lastItemID = nil
local lastItemLink = nil
local lastPrintTime = 0
local debounceDelay = 1.0

-- ================= Utilities =================
local function FormatGoldLocalized(copper)
    local gold = copper / 10000
    local useEnglish = AverageReagentPriceDB.useEnglishNumberFormat
    local locale = GetLocale()

    local commaLocales = {
        deDE = true, frFR = true, itIT = true, esES = true,
        nlNL = true, ptPT = true, ptBR = true, ruRU = true,
        plPL = true, trTR = true
    }

    local useComma = not useEnglish and commaLocales[locale]
    local formatted = string.format("%.2f", gold)
    return useComma and string.gsub(formatted, "%.", ",") or formatted
end

local function GetItemCategory(itemID)
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemID)
    if not itemType then 
        return "Miscellaneous" 
    end

    -- Normalize Tradeskill/Trade Goods mismatch
    if itemType == "Tradeskill" then
        itemType = "Trade Goods"
    end

    -- Mapping for Trade Goods subtypes
    local tradeGoodsMap = {
        ["Herb"] = "Herbs",
        ["Enchanting"] = "Enchanting",
        ["Metal & Stone"] = "Blacksmithing",
        ["Jewelcrafting"] = "Jewelcrafting",
        ["Inscription"] = "Inscription",
        ["Parts"] = "Engineering",
        ["Cloth"] = "Tailoring",
        ["Leather"] = "Leatherworking",
        ["Elemental"] = "Miscellaneous",
        ["Cooking"] = "Cooking",
        ["Other"] = "Miscellaneous",
    }

    local category = "Miscellaneous"

    if itemType == "Trade Goods" then
        category = tradeGoodsMap[itemSubType] or "Miscellaneous"
    elseif itemType == "Consumable" then
        if itemSubType == "Food & Drink" then
            category = "Cooking"
        elseif itemSubType == "Potion" then
            category = "Alchemy"
        else
            category = "Miscellaneous"
        end
    elseif itemType == "Recipe" then
        category = itemSubType or "Miscellaneous"
    end

    return category
end

-- Helper: extract rank from itemLink
local function GetItemRank(itemLink)
    if not itemLink then return nil end
    local rank = itemLink:match("|A:Professions%-ChatIcon%-Quality%-Tier(%d):")
    return tonumber(rank)
end

-- Helper: expand results ( {unitPrice, quantity}, ... ) into a flat unit-price list up to targetQuantity
local function ExpandResultsToUnitPrices(results, targetQuantity)
    local unitPrices = {}
    if not results or #results == 0 then return unitPrices end

    -- Sort ascending to pick cheapest units first
    table.sort(results, function(a, b) return a.unitPrice < b.unitPrice end)

    local collected = 0
    for _, r in ipairs(results) do
        local take = math.min(r.quantity or 0, targetQuantity - collected)
        if take <= 0 then break end
        for i = 1, take do
            unitPrices[#unitPrices + 1] = r.unitPrice
        end
        collected = collected + take
        if collected >= targetQuantity then break end
    end

    return unitPrices
end

-- Helper: compute stats from a raw results snapshot according to quantity & trimPercent
local function ComputeStatsFromResults(results, targetQuantity, trimPercent)
    if not results or #results == 0 then return nil end

    local selectedUnits = ExpandResultsToUnitPrices(results, targetQuantity)
    local n = #selectedUnits
    if n == 0 then return nil end

    -- Sort descending so most expensive are at the front
    table.sort(selectedUnits, function(a, b) return a > b end)

    -- trimPercent is expected as a percent (0..100). Convert to items
    local trimPercentNum = tonumber(trimPercent) or 0
    if trimPercentNum < 0 then trimPercentNum = 0 end
    if trimPercentNum > 100 then trimPercentNum = 100 end

    local trimCount = math.floor(n * (trimPercentNum / 100))

    -- If trimming removes all units, return zero-stats (user intentionally trimmed 100%)
    if trimCount >= n then
        return 0, 0, 0, 0
    end

    -- Build list of units to use (skip first trimCount entries)
    local unitsToUse = {}
    for i = trimCount + 1, n do
        unitsToUse[#unitsToUse + 1] = selectedUnits[i]
    end

    if #unitsToUse == 0 then
        return 0, 0, 0, 0
    end

    local sum = 0
    local minUnit, maxUnit = unitsToUse[1], unitsToUse[1]
    for _, price in ipairs(unitsToUse) do
        sum = sum + price
        if price < minUnit then minUnit = price end
        if price > maxUnit then maxUnit = price end
    end

    local avg = sum / #unitsToUse
    return avg, minUnit, maxUnit, #unitsToUse
end

-- ================= Safe Add Item Helper =================
function ARP:SafeAddItem(list, itemID, itemName, itemLink, category)
    if ARP.panelLocked or not ARP_Frame or not ARP_Frame:IsShown() then
        return
    end
    if not list or type(list) ~= "table" then return end

    list.items = list.items or {}
    list.items[itemID] = list.items[itemID] or { quantityOverride = nil }

    -- Ensure global DB has an entry
    AverageReagentPriceDB.itemDB = AverageReagentPriceDB.itemDB or {}
    if itemName and itemID then
        AverageReagentPriceDB.itemDB[itemName] = AverageReagentPriceDB.itemDB[itemName] or {}
        AverageReagentPriceDB.itemDB[itemName][itemID] = AverageReagentPriceDB.itemDB[itemName][itemID] or {
            itemID = itemID,
            itemLink = itemLink,
            mainCategory = category or "Miscellaneous",
            avgPrice = nil,
            minPrice = nil,
            maxPrice = nil,
            collected = nil,
        }

        ARP:GetCachedItemKey(itemID)
    end
end

-- ================= Safe Add Item Check =================
local function SafeAddItemCheck()
    return ARP.panelLocked or not ARP_Frame or not ARP_Frame:IsShown()
end

-- ================= Get Commodity Stats (safe cache + percent-trim from MAX end) =================
local function GetCommodityStats(itemID)
    if not itemID then return nil end
    if not C_AuctionHouse or not C_AuctionHouse.GetNumCommoditySearchResults then return nil end

    local numResults = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    if not numResults or numResults == 0 then
        -- no AH snapshot available right now
        return nil
    end

    local results = {}
    local minPrice, fullMaxPrice = nil, nil
    local totalAvailable = 0

    for i = 1, numResults do
        local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if not result then break end
        results[#results + 1] = { unitPrice = result.unitPrice, quantity = result.quantity or 0 }
        totalAvailable = totalAvailable + (result.quantity or 0)
        if not minPrice or result.unitPrice < minPrice then minPrice = result.unitPrice end
        if not fullMaxPrice or result.unitPrice > fullMaxPrice then fullMaxPrice = result.unitPrice end
    end

    if #results == 0 then
        return nil
    end

    -- Ensure cache table exists; store raw snapshot (do NOT clobber global unless intentionally clearing)
    ARP.commodityCache = ARP.commodityCache or {}
    ARP.commodityCache[itemID] = ARP.commodityCache[itemID] or {}
    ARP.commodityCache[itemID].prices = results
    ARP.commodityCache[itemID].minPrice = minPrice
    ARP.commodityCache[itemID].maxPrice = fullMaxPrice
    ARP.commodityCache[itemID].totalAvailable = totalAvailable

    -- Compute according to current Quantity & percent Trim
    local targetQuantity = tonumber(AverageReagentPriceDB.quantity) or 200
    local trimPercent = tonumber(AverageReagentPriceDB.trim) or 0

    local avg, minP, maxP, count = ComputeStatsFromResults(results, targetQuantity, trimPercent)
    -- avg==nil means nothing available in snapshot; return nil so caller can avoid clobbering DB
    if not avg then
        return nil
    end

    -- Optionally store lastComputed metadata
    ARP.commodityCache[itemID].lastComputed = {
        avg = avg,
        min = minP,
        max = maxP,
        count = count,
        targetQuantity = targetQuantity,
        trimPercent = trimPercent
    }

    return avg, minP, maxP, count
end

local function GetCurrentCommodityItemID()
    if not AuctionHouseFrame or not AuctionHouseFrame.CommoditiesBuyFrame then return nil end
    local f = AuctionHouseFrame.CommoditiesBuyFrame
    if f.GetItemID then return f:GetItemID() end
    return nil
end

function ARP:ShowPatchNoticePopup()
    local popup = CreateFrame("Frame", "ARP_PatchNotice", UIParent, "BasicFrameTemplateWithInset")
    popup:SetSize(400, 250)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("DIALOG")

    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)


    popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    popup.title:SetPoint("TOP", popup, "TOP", 0, -4)
    popup.title:SetJustifyH("CENTER")
    popup.title:SetWidth(popup:GetWidth() - 40)
    popup.title:SetText("ARP Tracker Notice")

    popup.body = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    popup.body:SetPoint("TOPLEFT", 15, -40)
    popup.body:SetPoint("RIGHT", -15, 0)
    popup.body:SetJustifyH("LEFT")
    popup.body:SetJustifyV("TOP")
    popup.body:SetText("Heads Up! This patch includes a database cleanup solution.\n\nIf you're experiencing duplicate entries or anything else weird, run /arp clean and give it a moment to rebuild the DB for you.\n\nThanks for your patience, understanding, and support!")
    popup.okButton = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    popup.okButton:SetSize(80, 25)
    popup.okButton:SetPoint("BOTTOM", 0, 15)
    popup.okButton:SetText("Got it!")
    popup.okButton:SetScript("OnClick", function()
        popup:Hide()
    end)
end

-- ================= Panel Creation =================
local panelWidth, panelHeight = 600, 500
local panel = CreateFrame("Frame", "ARP_PanelFrame", UIParent, "BackdropTemplate")
panel:SetSize(panelWidth, panelHeight)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:SetFrameStrata("HIGH")
panel:SetFrameLevel(1)  -- base panel level
panel:Hide()
panel:SetBackdrop({
    bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 256, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
panel:SetBackdropColor(1,1,1,1)
panel:SetBackdropBorderColor(1, 1, 1, 1)

-- ================= Panel Title (Left) =================
panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
panel.title:SetPoint("TOPLEFT", 12, -8)
panel.title:SetText("ARP Tracker")

-- ================= Version Label (Right) =================
panel.versionLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
panel.versionLabel:SetPoint("TOPRIGHT", -35, -12)
panel.versionLabel:SetText(ARP.version)
panel.versionLabel:SetJustifyH("RIGHT")

-- ================= Panel Close Button =================
local panelClose = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
panelClose:SetSize(24, 24)
panelClose:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)
panelClose:SetFrameLevel(panel:GetFrameLevel() + 5)
panelClose:SetScript("OnClick", function()
    ARP_Frame.wasManuallyHidden = true
    panel:Hide()
end)

-- ================= Checkbox: Lock Panel =================
panel.lockPanelCheckbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
panel.lockPanelCheckbox.text:SetText("Lock Lists")

-- Ensure the User Guide checkbox exists before anchoring
if panel.viewReadMeCheckbox then
    panel.lockPanelCheckbox:SetPoint("RIGHT", panel.viewReadMeCheckbox, "LEFT", -20, 0)
else
    -- fallback in case User Guide checkbox not ready
    panel.lockPanelCheckbox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -165, -45)
end

-- Make sure it is above panel background
panel.lockPanelCheckbox:SetFrameLevel(panel:GetFrameLevel() + 5)
panel.lockPanelCheckbox:Show()

-- Set initial checked state
panel.lockPanelCheckbox:SetChecked(ARP.panelLocked or false)

-- Toggle lock state
panel.lockPanelCheckbox:SetScript("OnClick", function(self)
    local isLocked = self:GetChecked()
    ARP.panelLocked = isLocked
    AverageReagentPriceDB.panelLocked = isLocked

    if isLocked then
        print("|cff33ff99[ARP]|r Panel is now locked.")
    else
        print("|cff33ff99[ARP]|r Panel is now unlocked.")
    end
end)

-- Checkbox for User Guide
panel.viewReadMeCheckbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
panel.viewReadMeCheckbox:SetPoint("TOPRIGHT", -75, -45)
panel.viewReadMeCheckbox.text:SetText("User Guide")
panel.viewReadMeCheckbox:SetScript("OnClick", function(self)
    if self:GetChecked() then
        ARP.readMePanel:Show()
    else
        ARP.readMePanel:Hide()
    end
end)

-- ========== User Guide Panel ==========
local function CreateReadMePanel()
    local width, height = 400, 350
    local titleHeight = 24
    local padding = 8

    -- Main panel
    local readMe = CreateFrame("Frame", "ARP_ReadMePanel", UIParent, "BackdropTemplate")
    readMe:SetSize(width, height)
    readMe:SetPoint("CENTER")
    readMe:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    readMe:SetBackdropColor(0, 0, 0, 0.8)

    -- Make it movable
    readMe:SetMovable(true)
    readMe:EnableMouse(true)
    readMe:RegisterForDrag("LeftButton")
    readMe:SetScript("OnDragStart", readMe.StartMoving)
    readMe:SetScript("OnDragStop", readMe.StopMovingOrSizing)

    readMe:SetFrameStrata("HIGH")
    readMe:SetFrameLevel(1000)
    readMe:Hide()

    -- Title text
    local title = readMe:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", padding, -padding)
    title:SetPoint("TOPRIGHT", -padding, -padding)
    title:SetHeight(titleHeight)
    title:SetJustifyH("CENTER")
    title:SetText("ARP Tracker: User Guide")

    -- Scrollable container
    local scrollHeight = 275
    local scrollContainer = CreateFrame("Frame", nil, readMe)
    scrollContainer:SetSize(width - 2 * padding, scrollHeight)
    scrollContainer:SetPoint("TOPLEFT", padding, -(padding + titleHeight + 24))

    local scrollFrame = CreateFrame("ScrollFrame", nil, scrollContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetAllPoints(scrollContainer)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(width - 40, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Adjust scrollbar width and offsets
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 3, -4)
        scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 3, 4)
        scrollBar:SetWidth(20)
    end

    -- FontString for guide text
    local text = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetPoint("TOPRIGHT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWidth(width - 40)
    text:SetText(ARP_UserGuideText or "User guide not loaded.")

    -- Dynamically size scrollChild to fit text
    scrollChild:SetHeight(text:GetStringHeight() + 20)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, readMe, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", readMe, "TOPRIGHT", -5, -5)
    closeBtn:SetFrameLevel(readMe:GetFrameLevel() + 5)
    closeBtn:SetScript("OnClick", function()
        readMe:Hide()
        if panel.viewReadMeCheckbox then
            panel.viewReadMeCheckbox:SetChecked(false)
        end
    end)

    return readMe
end

-- Top Status: Recent Item
panel.status = panel:CreateFontString(nil, "OVERLAY")
panel.status:SetFont("Fonts\\FRIZQT__.TTF", 14)
panel.status:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -28)
panel.status:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
panel.status:SetJustifyH("LEFT")
panel.status:SetText("No data yet")
panel.status:SetScript("OnMouseUp", function(self)
    if lastItemLink then
        if IsModifiedClick("CHATLINK") then
            ChatEdit_InsertLink(lastItemLink)
        else
            GameTooltip:SetOwner(panel, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(lastItemLink)
            GameTooltip:Show()
        end
    end
end)

panel.status:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Bottom Status: Update Prices Progress
panel.statusBottom = panel:CreateFontString(nil, "OVERLAY")
panel.statusBottom:SetFont("Fonts\\FRIZQT__.TTF", 14)
panel.statusBottom:SetPoint("BOTTOM", panel, "BOTTOM", 0, 10)
panel.statusBottom:SetJustifyH("CENTER")
panel.statusBottom:SetText("")

-- Quantity Input
local qtyLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
qtyLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -55)
qtyLabel:SetText("Quantity:")

local qtyEdit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
qtyEdit:SetSize(80, 20)
qtyEdit:SetAutoFocus(false)
qtyEdit:SetNumeric(true)
qtyEdit:SetPropagateKeyboardInput(false)  -- STOP keystrokes propagating
qtyEdit:SetPoint("LEFT", qtyLabel, "RIGHT", 8, 0)
qtyEdit:SetText(tostring(AverageReagentPriceDB.quantity or 200))

qtyEdit:SetScript("OnEditFocusGained", function(self)
    self:HighlightText()
    self:SetAutoFocus(true)  -- grab keyboard input when clicked
end)

qtyEdit:SetScript("OnEditFocusLost", function(self)
    self:SetAutoFocus(false)
end)

qtyEdit:SetScript("OnEnterPressed", function(self)
    local val = tonumber(self:GetText())
    if val and val >= 1 and val <= 100000 then
        AverageReagentPriceDB.quantity = val
        self:SetText(tostring(val))
        ARP:RecalculateAllAverages(true)
    else
        self:SetText(tostring(AverageReagentPriceDB.quantity))
    end
    self:ClearFocus()
end)

qtyEdit:SetScript("OnEscapePressed", function(self)
    self:SetText(tostring(AverageReagentPriceDB.quantity))
    self:ClearFocus()
end)

-- Trim Input
local trimLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
trimLabel:SetPoint("TOPLEFT", qtyLabel, "TOPLEFT", 150, 0)
trimLabel:SetText("Trim%:")

local trimEdit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
trimEdit:SetSize(50, 20)
trimEdit:SetAutoFocus(false)
trimEdit:SetNumeric(true)
trimEdit:SetPropagateKeyboardInput(false)
trimEdit:SetPoint("LEFT", trimLabel, "RIGHT", 8, 0)
trimEdit:SetText(tostring(AverageReagentPriceDB.trim or 2))

trimEdit:SetScript("OnEditFocusGained", function(self)
    self:HighlightText()
    self:SetAutoFocus(true)
end)

trimEdit:SetScript("OnEditFocusLost", function(self)
    self:SetAutoFocus(false)
end)

trimEdit:SetScript("OnEnterPressed", function(self)
    local val = tonumber(self:GetText())
    if val and val >= 0 then
        AverageReagentPriceDB.trim = val
        self:SetText(tostring(val))
        ARP:RecalculateAllAverages(true)
    else
        self:SetText(tostring(AverageReagentPriceDB.trim or 2))
    end
    self:ClearFocus()
end)

trimEdit:SetScript("OnEscapePressed", function(self)
    self:SetText(tostring(AverageReagentPriceDB.trim or 2))
    self:ClearFocus()
end)

trimEdit:SetScript("OnEditFocusGained", function(self)
    self:HighlightText()
end)

-- ================= Scrollable Database =================
local scrollWidth, scrollHeight, borderPadding = 555, 365, 6
panel.scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
panel.scrollFrame:SetSize(scrollWidth, scrollHeight)
panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -90)
panel.scrollFrame:SetFrameLevel(panel:GetFrameLevel() + 1)

panel.scrollChild = CreateFrame("Frame", nil, panel.scrollFrame)
panel.scrollChild:SetSize(scrollWidth, 1)  -- initial height
panel.scrollFrame:SetScrollChild(panel.scrollChild)
panel.scrollChild:SetFrameLevel(panel.scrollFrame:GetFrameLevel() + 1)

local borderFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
borderFrame:SetPoint("TOPLEFT", panel.scrollFrame, "TOPLEFT", -borderPadding, borderPadding)
borderFrame:SetPoint("BOTTOMRIGHT", panel.scrollFrame, "BOTTOMRIGHT", borderPadding, -borderPadding)
borderFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 14, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
borderFrame:SetBackdropColor(1, 1, 1, 1)
borderFrame:SetBackdropBorderColor(1, 1, 1, .5)
borderFrame:SetFrameStrata(panel.scrollFrame:GetFrameStrata())
borderFrame:SetFrameLevel(panel.scrollFrame:GetFrameLevel())

-- ================= Helper: Add Rows =================
panel.itemEntries = panel.itemEntries or {}
function panel:AddItemRow(itemID, itemName)
    local rowHeight = 20
    local rowSpacing = 2

    local row = CreateFrame("Frame", nil, self.scrollChild)
    row:SetSize(self.scrollChild:GetWidth(), rowHeight)

    local numRows = #self.itemEntries
    if numRows == 0 then
        row:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, 0)
    else
        row:SetPoint("TOPLEFT", self.itemEntries[numRows], "BOTTOMLEFT", 0, -rowSpacing)
    end
    row:SetPoint("TOPRIGHT", self.scrollChild, "TOPRIGHT", 0, 0)

    row.data = { itemID = itemID, name = itemName }

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.text:SetText(itemName or "Unknown")

    row:Show()
    table.insert(self.itemEntries, row)

    -- Update scroll child height to fit all rows
    local totalHeight = #self.itemEntries * (rowHeight + rowSpacing)
    self.scrollChild:SetHeight(totalHeight)

    return row
end

-- ================= Optional: Resize Helper =================
local function ResizeScrollFrame(width, height, padding)
    panel.scrollFrame:SetSize(width, height)
    borderFrame:SetPoint("TOPLEFT", panel.scrollFrame, "TOPLEFT", -padding, padding)
    borderFrame:SetPoint("BOTTOMRIGHT", panel.scrollFrame, "BOTTOMRIGHT", padding, -padding)
    -- optionally resize scroll child width to match new scroll frame width
    panel.scrollChild:SetWidth(width)
end

-- ================= Panel Drag Handling =================
panel:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and not (MouseIsOver(panel.scrollFrame) or MouseIsOver(qtyEdit) or MouseIsOver(trimEdit)) then
        panel:StartMoving()
    end
end)

panel:SetScript("OnMouseUp", function(self)
    panel:StopMovingOrSizing()
    local left, top = panel:GetLeft(), panel:GetTop()
    if left and top then
        AverageReagentPriceDB.panelPosX = left
        AverageReagentPriceDB.panelPosY = top
    end
end)

local function PositionPanel()
    panel:ClearAllPoints()
    if AverageReagentPriceDB.panelPosX and AverageReagentPriceDB.panelPosY then
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", AverageReagentPriceDB.panelPosX, AverageReagentPriceDB.panelPosY)
    else
        panel:SetPoint("TOPLEFT", UIParent, "CENTER", -panelWidth/2, -50)
    end
end
PositionPanel()

-- Make globally accessible for other code (like StoreItemData)
ARP_Frame = panel
ARP_Frame.isOpen = false
ARP_Frame.wasManuallyHidden = false  -- Track user intent

panel:SetScript("OnShow", function(self)
    self.isOpen = true
    AverageReagentPriceDB.panelVisible = true
end)

panel:SetScript("OnHide", function(self)
    self.isOpen = false
    if self.wasManuallyHidden then
        AverageReagentPriceDB.panelVisible = false
    end
end)

-- ================= Filter Panel =================
local filterPanelWidth, filterPanelHeight = 180, panelHeight
local filterPanel = CreateFrame("Frame", "ARP_FilterPanel", panel, "BackdropTemplate")
filterPanel:SetSize(filterPanelWidth, filterPanelHeight)
filterPanel:SetPoint("TOPLEFT", panel, "TOPRIGHT", 4, 0)
filterPanel:SetBackdrop({
    bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
filterPanel:SetBackdropColor(1,1,1,1)
filterPanel:SetBackdropBorderColor(1, 1, 1, 1)
filterPanel:Hide()

-- Title
filterPanel.title = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
filterPanel.title:SetPoint("TOP", filterPanel, "TOP", 0, -8)
filterPanel.title:SetText("Filter Items")

-- Primary Filter Label
local primaryLabel = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
primaryLabel:SetPoint("TOP", filterPanel, "TOP", 0, -30)
primaryLabel:SetText("Primary Filter:")

-- Category Dropdown
local selectedCategory = "All"
local categories = {
    "All",
    "User List", -- special categories
    "Herbs",
    "Inscription",
    "Blacksmithing",
    "Enchanting",
    "Alchemy",
    "Engineering",
    "Jewelcrafting",
    "Cooking",
    "Tailoring",
    "Leatherworking",
    "Miscellaneous"
}

-- Split into special categories and normal categories
local specialCategories = { "All", "User List" }
local normalCategories = {}
for _, cat in ipairs(categories) do
    if not tContains(specialCategories, cat) then
        table.insert(normalCategories, cat)
    end
end
table.sort(normalCategories)

-- Build final dropdown list with spacers
local dropdownCategories = {}
table.insert(dropdownCategories, specialCategories[1]) -- "All"
table.insert(dropdownCategories, "---------------")            -- spacer, non-selectable
table.insert(dropdownCategories, specialCategories[2]) -- "User List"
table.insert(dropdownCategories, "---------------")            -- spacer, non-selectable
for _, cat in ipairs(normalCategories) do
    table.insert(dropdownCategories, cat)
end

-- Create the dropdown
local categoryDropdown = CreateFrame("Frame", "ARP_CategoryDropdown", filterPanel, "UIDropDownMenuTemplate")
categoryDropdown:SetPoint("TOP", primaryLabel, "BOTTOM", 0, -4)
UIDropDownMenu_SetWidth(categoryDropdown, 140)
UIDropDownMenu_SetText(categoryDropdown, selectedCategory)

UIDropDownMenu_Initialize(categoryDropdown, function(self, level, menuList)
    for _, cat in ipairs(dropdownCategories) do
        local info = UIDropDownMenu_CreateInfo()
        if cat == "--------" then
            info.text = cat
            info.isTitle = true
            info.notCheckable = true
        else
            info.text = cat
            info.checked = (cat == selectedCategory)
            info.func = function()
    local previousCategory = selectedCategory
    selectedCategory = cat
    UIDropDownMenu_SetText(categoryDropdown, cat)

    if previousCategory == "User List" and cat ~= "User List" then
        selectedUserList = "None"
        UIDropDownMenu_SetText(filterPanel.userListDropdown, selectedUserList)
        ARP_DB.ActiveUserList = nil
    elseif cat == "User List" then
        -- 🟢 Restore active list context when switching to User List
        if selectedUserList and selectedUserList ~= "None" then
            ARP_DB.ActiveUserList = selectedUserList
        else
            ARP_DB.ActiveUserList = nil
        end
    end
end
        UIDropDownMenu_AddButton(info)
    end
end
end)

-- ================= User Lists =================
ARP_DB = ARP_DB or {}
ARP_DB.UserLists = ARP_DB.UserLists or {}
ARP_DB.ActiveUserList = ARP_DB.ActiveUserList or nil

local userListLabel = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
userListLabel:SetPoint("TOP", categoryDropdown, "BOTTOM", 0, -16)
userListLabel:SetText("User Lists:")

if selectedCategory ~= "User List" then
    selectedUserList = "None"
end

-- Refresh User List Dropdown
local function RefreshUserListDropdown()
    if not filterPanel.userListDropdown then return end
    local dd = filterPanel.userListDropdown
    UIDropDownMenu_Initialize(dd, function(self, level, menuList)
        for name,_ in pairs(ARP_DB.UserLists) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.checked = (name == selectedUserList)
            info.func = function()
                selectedUserList = name
                UIDropDownMenu_SetText(dd, name)

                -- 🟢 Automatically switch Primary Filter to "User List"
                selectedCategory = "User List"
                UIDropDownMenu_SetText(categoryDropdown, selectedCategory)

                -- Optional: visually show it’s ready, but do NOT auto-apply
                print("|cff33ff99[ARP]|r Selected user list:", name, "(Apply Filter manually to activate.)")
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(dd, selectedUserList or "None")
end


filterPanel.userListDropdown = CreateFrame("Frame", "ARP_UserListDropdown", filterPanel, "UIDropDownMenuTemplate")
filterPanel.userListDropdown:SetPoint("TOP", userListLabel, "BOTTOM", 0, -4)
UIDropDownMenu_SetWidth(filterPanel.userListDropdown, 140)
RefreshUserListDropdown()

-- ================= Apply / Clear Buttons =================
local applyBtn = CreateFrame("Button", nil, filterPanel, "UIPanelButtonTemplate")
applyBtn:SetSize(140, 24)
applyBtn:SetPoint("TOP", filterPanel.userListDropdown, "BOTTOM", 0, -10)
applyBtn:SetText("Apply Filter")
applyBtn:SetScript("OnClick", function()
    local selectedFilter = UIDropDownMenu_GetText(categoryDropdown)
    if selectedFilter == "User List" and selectedUserList ~= "None" then
        ARP_DB.ActiveUserList = selectedUserList
        ARP.selectedPrimaryFilter = "UserList"
    else
        ARP_DB.ActiveUserList = nil
        ARP.selectedPrimaryFilter = selectedFilter or "All"
    end

    -- Recalculate using the newly selected active list context, then refresh UI
    ARP:RecalculateAllAverages(true)
    ARP:UpdateAllEntries()
end)

local clearBtn = CreateFrame("Button", nil, filterPanel, "UIPanelButtonTemplate")
clearBtn:SetSize(140, 24)
clearBtn:SetPoint("TOP", applyBtn, "BOTTOM", 0, -4)
clearBtn:SetText("Clear Filter")
clearBtn:SetScript("OnClick", function()
    selectedCategory = "All"
    UIDropDownMenu_SetText(categoryDropdown, selectedCategory)
    selectedUserList = "None"
    RefreshUserListDropdown()
    ARP_DB.ActiveUserList = nil
    ARP.selectedPrimaryFilter = "All"
    ARP:UpdateAllEntries()
end)

-- ================= Create New List =================
local createLabel = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
createLabel:SetPoint("TOP", clearBtn, "BOTTOM", 0, -16)
createLabel:SetText("Create List:")

local createEdit = CreateFrame("EditBox", nil, filterPanel, "InputBoxTemplate")
createEdit:SetSize(140, 20)
createEdit:SetPoint("TOP", createLabel, "BOTTOM", 0, -4)
createEdit:SetAutoFocus(false)
createEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local createBtn = CreateFrame("Button", nil, filterPanel, "UIPanelButtonTemplate")
createBtn:SetSize(140, 24)
createBtn:SetPoint("TOP", createEdit, "BOTTOM", 0, -4)
createBtn:SetText("Create List")
createBtn:SetScript("OnClick", function()
    local name = createEdit:GetText():gsub("^%s*(.-)%s*$", "%1") -- trim spaces
    if name ~= "" and not ARP_DB.UserLists[name] then
        -- Create the new list
        ARP_DB.UserLists[name] = { items = {} }

        -- Set as active immediately
        selectedUserList = name
        ARP_DB.ActiveUserList = name
        ARP.selectedPrimaryFilter = "UserList"

        -- Refresh user list dropdown
        RefreshUserListDropdown()

        -- Update Primary Filter dropdown visually
        selectedCategory = "User List"
        UIDropDownMenu_SetText(categoryDropdown, selectedCategory)

        -- Clear input and update panel
        createEdit:SetText("")
        ARP:UpdateAllEntries()

        print("|cff33ff99[ARP]|r Created and applied list:", name)
    else
        print("|cff33ff99[ARP]|r Invalid or duplicate list name.")
    end
end)

-- ================= Delete List (Button Only) =================
local deleteBtn = CreateFrame("Button", nil, filterPanel, "UIPanelButtonTemplate")
deleteBtn:SetSize(140, 24)
deleteBtn:SetPoint("TOP", createBtn, "BOTTOM", 0, -4)
deleteBtn:SetText("Delete List")
deleteBtn:SetScript("OnClick", function()
    if selectedUserList and selectedUserList ~= "None" and ARP_DB.UserLists[selectedUserList] then
        ARP.UserLists:Delete(selectedUserList)
        selectedUserList = "None"
        ARP_DB.ActiveUserList = nil
        RefreshUserListDropdown()

        selectedCategory = "All"
        UIDropDownMenu_SetText(categoryDropdown, selectedCategory)
        ARP.selectedPrimaryFilter = "All"

        ARP:UpdateAllEntries()
        print("|cff33ff99[ARP]|r Deleted list and reset filter to All.")
    else
        print("|cff33ff99[ARP]|r No valid list selected.")
    end
end)

-- ================= Export/Import User List =================

-- Export List Button
local exportListBtn = CreateFrame("Button", nil, filterPanel, "UIPanelButtonTemplate")
exportListBtn:SetSize(140, 24)
exportListBtn:SetPoint("TOP", deleteBtn, "BOTTOM", 0, -16)
exportListBtn:SetText("Export List")
exportListBtn:SetScript("OnClick", function()
    local listToExport = selectedUserList or ARP_DB.ActiveUserList
    
    if listToExport and ARP_DB.UserLists[listToExport] then
        local items = ARP_DB.UserLists[listToExport].items or {}
        local exportLines = {}

        for itemID, listItem in pairs(items) do
            local override = listItem.quantityOverride
            -- If no override in user list, check itemDB fallback
            if override == nil then
                for _, entrySet in pairs(AverageReagentPriceDB.itemDB or {}) do
                    if entrySet[itemID] and entrySet[itemID].quantityOverride then
                        override = entrySet[itemID].quantityOverride
                        break
                    end
                end
            end

            local value = (type(override) == "number" and override > 0) and override or "DEFAULT"
            table.insert(exportLines, tostring(itemID) .. ":" .. tostring(value))
        end

        local exportString = "ListName:" .. listToExport .. ";Items:" .. table.concat(exportLines, ",")
        if ARP.ShowExportPopup then
            ARP:ShowExportPopup(exportString)
        else
            print("|cffff4444[ARP]|r Export popup handler missing.")
        end
    else
        print("|cff33ff99[ARP]|r No valid list selected for export.")
    end
end)

-- Import Label
local importLabel = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
importLabel:SetPoint("TOP", exportListBtn, "BOTTOM", 0, -12)
importLabel:SetText("Import List:")

-- Import EditBox
local importEdit = CreateFrame("EditBox", nil, filterPanel, "InputBoxTemplate")
importEdit:SetSize(140, 20)
importEdit:SetPoint("TOP", importLabel, "BOTTOM", 0, -4)
importEdit:SetAutoFocus(false)
importEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- Import Button
local importBtn = CreateFrame("Button", nil, filterPanel, "UIPanelButtonTemplate")
importBtn:SetSize(140, 24)
importBtn:SetPoint("TOP", importEdit, "BOTTOM", 0, -4)
importBtn:SetText("Import List")
importBtn:SetScript("OnClick", function()
    local raw = importEdit:GetText():match("^%s*(.-)%s*$")
    local listName, itemString = raw:match("^ListName:(.-);Items:(.+)$")

    if not listName or not itemString then
        print("|cff33ff99[ARP]|r Invalid format. Use: ListName:Name;Items:ID:Val,ID:Val")
        return
    end

    if ARP_DB.UserLists[listName] then
        print("|cff33ff99[ARP]|r List \"" .. listName .. "\" already exists.")
        return
    end

    importEdit:SetText("")
    ARP_DB.UserLists[listName] = { items = {} }
    
    -- Sync UI State
    selectedUserList = listName
    ARP_DB.ActiveUserList = listName
    selectedCategory = "User List"
    ARP.selectedPrimaryFilter = "UserList"

    -- Parse entries
    local entries = {}
    for entry in string.gmatch(itemString, "[^,]+") do
        local id, override = entry:match("^(%d+):?(%w*)$")
        id = tonumber(id)
        if id then
            local value = (override == "" or override == "DEFAULT") and "DEFAULT" or tonumber(override)
            table.insert(entries, { id = id, value = value })
        end
    end

    local index = 1
    local function processNextChunk()
        for _ = 1, 15 do
            if index > #entries then break end
            local entry = entries[index]

            -- Force TABLE structure for items (This fixes the "reverting" bug)
            ARP_DB.UserLists[listName].items[entry.id] = { 
                quantityOverride = (entry.value ~= "DEFAULT") and entry.value or nil 
            }

            -- Ensure item cache exists so the UI doesn't error out
            local itemObj = Item:CreateFromItemID(entry.id)
            itemObj:ContinueOnItemLoad(function()
                local name, link = GetItemInfo(entry.id)
                if name and link then
                    AverageReagentPriceDB.itemDB[name] = AverageReagentPriceDB.itemDB[name] or {}
                    if not AverageReagentPriceDB.itemDB[name][entry.id] then
                        AverageReagentPriceDB.itemDB[name][entry.id] = {
                            itemID = entry.id,
                            itemLink = link,
                            mainCategory = GetItemCategory(entry.id)
                        }
                    end
                end
            end)
            index = index + 1
        end

        if index <= #entries then
            C_Timer.After(0.05, processNextChunk)
        else
            -- Finalize UI update
            ARP:UpdateAllEntries()
            if RefreshUserListDropdown then RefreshUserListDropdown() end
            if filterPanel.userListDropdown then
                UIDropDownMenu_SetText(filterPanel.userListDropdown, listName)
            end
            print("|cff33ff99[ARP]|r Imported " .. #entries .. " items into: " .. listName)
        end
    end
    processNextChunk()
end)

-- ================= Export / Update Buttons =================
local updateBtn = CreateFrame("Button", nil, filterPanel, "UIPanelButtonTemplate")
updateBtn:SetSize(140, 24)
updateBtn:SetPoint("BOTTOM", filterPanel, "BOTTOM", 0, 10)
updateBtn:SetText("Update Prices")
updateBtn:SetScript("OnClick", function()
    if ARP.UpdatePricesButtonClick then ARP:UpdatePricesButtonClick() end
end)

local exportBtn = CreateFrame("Button", nil, filterPanel, "UIPanelButtonTemplate")
exportBtn:SetSize(140, 24)
exportBtn:SetPoint("BOTTOM", updateBtn, "TOP", 0, 4)
exportBtn:SetText("Export Prices")
exportBtn:SetScript("OnClick", function()
    if ARP.ExportAllData then ARP:ExportAllData() end
end)

-- Hook filter panel visibility to main panel
panel:HookScript("OnShow", function() filterPanel:Show() end)
panel:HookScript("OnHide", function() filterPanel:Hide() end)

-- ================= Export Panel =================
ARP.exportPanel = CreateFrame("Frame", "ARP_ExportPanel", UIParent, "BackdropTemplate")
local exportPanel = ARP.exportPanel
exportPanel:SetSize(600, 500)
exportPanel:SetMovable(true)
exportPanel:EnableMouse(true)
exportPanel:SetFrameStrata("DIALOG")
exportPanel:SetFrameLevel(50)
exportPanel:Hide()
exportPanel:SetBackdrop({
    bgFile = "Interface\\BUTTONS\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 14, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
exportPanel:SetBackdropColor(0,0,0,0.85)
exportPanel:SetBackdropBorderColor(1, 0.84, 0, 1)

-- Remember position
exportPanel:SetScript("OnMouseUp", function(self, button)
    self:StopMovingOrSizing()
    local left, top = self:GetLeft(), self:GetTop()
    if left and top then
        AverageReagentPriceDB.exportPanelX = left
        AverageReagentPriceDB.exportPanelY = top
    end
end)
exportPanel:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then self:StartMoving() end
end)

local function PositionExportPanel()
    exportPanel:ClearAllPoints()
    if AverageReagentPriceDB.exportPanelX and AverageReagentPriceDB.exportPanelY then
        exportPanel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", AverageReagentPriceDB.exportPanelX, AverageReagentPriceDB.exportPanelY)
    else
        exportPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end
PositionExportPanel()

-- Title
exportPanel.title = exportPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
exportPanel.title:SetPoint("TOPLEFT", 12, -8)
exportPanel.title:SetText("Export All Data")

-- Use English Names checkbox
exportPanel.useEnglishNames = CreateFrame("CheckButton", nil, exportPanel, "UICheckButtonTemplate")
exportPanel.useEnglishNames:SetPoint("TOPLEFT", exportPanel.title, "BOTTOMLEFT", 0, -10)
exportPanel.useEnglishNames.Text:SetText("Use English Names")
exportPanel.useEnglishNames:SetScript("OnClick", function(self)
    ARP:ExportAllData()
end)

-- Choose Delimiter Dropdown
exportPanel.delimiterDropdown = CreateFrame("Frame", "ARP_DelimiterDropdown", exportPanel, "UIDropDownMenuTemplate")
exportPanel.delimiterDropdown:SetPoint("TOPLEFT", exportPanel.useEnglishNames, "TOPRIGHT", 100, 0)

local delimiters = {
    { text = "Comma (,)", value = "," },
    { text = "Semicolon (;)", value = ";" },
    { text = "Tab", value = "\t" },
    { text = "Pipe (|)", value = "|" },
}

UIDropDownMenu_SetWidth(exportPanel.delimiterDropdown, 150)
UIDropDownMenu_Initialize(exportPanel.delimiterDropdown, function(self, level)
    for _, info in ipairs(delimiters) do
        local entry = UIDropDownMenu_CreateInfo()
        entry.text = info.text
        entry.value = info.value
        entry.func = function()
            AverageReagentPriceDB.exportDelimiter = info.value
            UIDropDownMenu_SetSelectedValue(exportPanel.delimiterDropdown, info.value)
            ARP:ExportAllData()
        end
        UIDropDownMenu_AddButton(entry, level)
    end
end)
UIDropDownMenu_SetSelectedValue(exportPanel.delimiterDropdown, AverageReagentPriceDB.exportDelimiter or ",")

-- Use English Number Format
exportPanel.useEnglishNumbers = CreateFrame("CheckButton", nil, exportPanel, "UICheckButtonTemplate")
exportPanel.useEnglishNumbers:SetPoint("TOPLEFT", exportPanel.delimiterDropdown, "TOPRIGHT", 20, -0)
exportPanel.useEnglishNumbers.Text:SetText("Use English Number Format")
exportPanel.useEnglishNumbers:SetChecked(AverageReagentPriceDB.useEnglishNumberFormat or false)
exportPanel.useEnglishNumbers:SetScript("OnClick", function(self)
    AverageReagentPriceDB.useEnglishNumberFormat = self:GetChecked()
    ARP:ExportAllData()
end)

-- Scrollable EditBox
exportPanel.scrollFrame = CreateFrame("ScrollFrame", nil, exportPanel, "UIPanelScrollFrameTemplate")
exportPanel.scrollFrame:SetPoint("TOPLEFT", exportPanel, "TOPLEFT", 10, -70)
exportPanel.scrollFrame:SetPoint("BOTTOMRIGHT", exportPanel, "BOTTOMRIGHT", -30, 10)

exportPanel.editBox = CreateFrame("EditBox", nil, exportPanel.scrollFrame)
exportPanel.editBox:SetMultiLine(true)
exportPanel.editBox:SetFontObject(GameFontNormal)
exportPanel.editBox:SetWidth(600 - 40)
exportPanel.editBox:SetHeight(350)
exportPanel.editBox:SetAutoFocus(false)
exportPanel.editBox:EnableMouse(true)
exportPanel.editBox:SetScript("OnEscapePressed", function(self) exportPanel:Hide() end)

exportPanel.scrollFrame:SetScrollChild(exportPanel.editBox)

-- Close button
local exportClose = CreateFrame("Button", nil, exportPanel, "UIPanelCloseButton")
exportClose:SetPoint("TOPRIGHT", -6, -6)
exportClose:SetScript("OnClick", function() exportPanel:Hide() end)

-- ================= Export All Data =================
function ARP:ExportAllData()
    local ep = ARP.exportPanel
    if not ep then
        if ARP.CreateExportPanel then
            ARP:CreateExportPanel()
            ep = ARP.exportPanel
        end
        if not ep or not ep.editBox then
            print("AverageReagentPrice: Export panel not ready yet.")
            return
        end
    end

    local useEnglishNames = ep.useEnglishNames and ep.useEnglishNames:GetChecked()
    local lines = {}
    local db = AverageReagentPriceDB.itemDB or {}
    selectedCategory = selectedCategory or "All"

    local applyCategoryFilter = (selectedCategory ~= "All" and selectedCategory ~= "User List")
    local applyUserListFilter = (selectedCategory == "User List" and ARP_DB and ARP_DB.ActiveUserList)
    local activeList = (applyUserListFilter and ARP_DB.UserLists and ARP_DB.UserLists[ARP_DB.ActiveUserList]) or {}

    local ALL_RANKS = {1, 2, 3}
    local delimiter = (AverageReagentPriceDB.exportDelimiter or ",") .. " "

    local itemNames = {}
    for itemName in pairs(db) do table.insert(itemNames, itemName) end
    table.sort(itemNames)

    for _, itemName in ipairs(itemNames) do
        local entries = db[itemName]
        local rankData = {}
        local hasVisible = false

        for _, data in pairs(entries or {}) do
            if data and data.itemID then
                local mainCat = data.mainCategory or "Miscellaneous"
                local showChild = true

                if applyCategoryFilter and mainCat ~= selectedCategory then
                    showChild = false
                end
                if applyUserListFilter and activeList then
                    showChild = (activeList.items or {})[data.itemID]
                end
                if data.locked or data.hidden then
                    showChild = false
                end

                if showChild then
                    hasVisible = true
                    local rank = GetItemRank(data.itemLink) or 1
                    rankData[rank] = tonumber(data.avgPrice) or 0
                end
            end
        end

        if hasVisible then
            local displayName = itemName
            if useEnglishNames and ARP_EnItemNamesDB then
                local itemID
                for _, data in pairs(entries) do
                    if data and data.itemID then
                        itemID = data.itemID
                        break
                    end
                end
                if itemID and ARP_EnItemNamesDB[itemID] then
                    displayName = ARP_EnItemNamesDB[itemID]
                end
            end

            local row = {displayName}
            for _, rank in ipairs(ALL_RANKS) do
                local avg = rankData[rank] or 0
                table.insert(row, "Rank " .. rank)
                table.insert(row, FormatGoldLocalized(avg))
            end
            lines[#lines + 1] = table.concat(row, delimiter)
        end
    end

    ep.editBox:SetText(table.concat(lines, "\n"))
    PositionExportPanel()
    ep:Raise()
    ep:SetFrameStrata("DIALOG")
    ep:SetFrameLevel(50)
    ep:Show()
    ep.editBox:SetFocus()
    ep.editBox:HighlightText()
end

-- ================= Helper: Get All Items for Current Filter =================
function panel:GetAllItemsForFilter()
    local items = {}
    local db = AverageReagentPriceDB.itemDB or {}
    panel.itemEntries = panel.itemEntries or {}

    local applyCategoryFilter = (selectedCategory ~= "All" and selectedCategory ~= "User List")
    local applyUserListFilter = (selectedCategory == "User List" and ARP_DB and ARP_DB.ActiveUserList)
    local activeList = (applyUserListFilter and ARP_DB.UserLists and ARP_DB.UserLists[ARP_DB.ActiveUserList]) or {}

    for itemName, topEntry in pairs(panel.itemEntries) do
        local childKeys = {}
        for key,_ in pairs(db[itemName] or {}) do table.insert(childKeys,key) end

        for _, key in ipairs(childKeys) do
            local data = (db[itemName] or {})[key]
            if data and data.itemID then
                local mainCat = data.mainCategory or "Miscellaneous"
                local itemID = data.itemID

                local include = true
                if applyCategoryFilter and mainCat ~= selectedCategory then
                    include = false
                end
                if applyUserListFilter and not ((activeList.items or {})[itemID]) then
                    include = false
                end

                if include then
                    table.insert(items, itemID)
                end
            end
        end
    end

    return items
end

-- ================= Update Prices Button Logic =================
local updating = false
local cooldown = 5 

-- Helper: Send AH query safely
local function SendAHQuery(itemID)
    if not C_AuctionHouse or not C_AuctionHouse.SendSearchQuery then return end

    -- Force-build the key for Commodities (itemID, 0, 0)
    local itemKey = C_AuctionHouse.MakeItemKey(itemID, 0, 0)

    if itemKey then
        C_AuctionHouse.SendSearchQuery(itemKey, {}, false)
    else
        C_AuctionHouse.SendSearchQuery(itemID, {}, false)
    end
end

-- Helper: Start a cooldown
local function StartUpdateCooldown(sec)
    sec = sec or cooldown
    if not updateBtn then return end
    updateBtn:Disable()
    local remaining = sec
    local ticker
    ticker = C_Timer.NewTicker(1, function()
        remaining = remaining - 1
        if remaining > 0 then
            if panel.statusBottom then panel.statusBottom:SetText("Cooldown: " .. remaining .. "s") end
        else
            if panel.statusBottom then panel.statusBottom:SetText("") end
            updateBtn:Enable()
            ticker:Cancel()
        end
    end)
end

-- Main update function
function ARP:UpdatePrices()
    if updating then return end
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return end

    local itemIDsToUpdate = panel:GetAllItemsForFilter()
    local totalItems = #itemIDsToUpdate
    if totalItems == 0 then return end

    updating = true
    updateBtn:Disable()
 
    local batchDelay = 0.6 

    for i, itemID in ipairs(itemIDsToUpdate) do
        C_Timer.After((i - 1) * batchDelay, function()
            SendAHQuery(itemID)
            
            if panel.statusBottom then
                panel.statusBottom:SetText(string.format("Scanning: %d / %d", i, totalItems))
            end

            -- Completion Logic
            if i == totalItems then
                C_Timer.After(5.0, function()
                    -- Step 1: Staggered "Silent Math" Phase
                    local index = 1
                    local chunkSize = 10 -- Process 10 items at a time to prevent freezing

                    local function ProcessMathChunk()
                        local last = math.min(index + chunkSize - 1, totalItems)
                        
                        for j = index, last do
                            local id = itemIDsToUpdate[j]
                            if id then
                                ARP:RecalculateAverage(id)
                            end
                        end

                        index = index + chunkSize
                        if index <= totalItems then
                            -- Pause for 0.01s (approx 1 frame) before next chunk
                            C_Timer.After(0.01, ProcessMathChunk)
                        else
                            -- Step 2: Calculate Success Count (Only once math is finished)
                            local successCount = 0
                            for _, id in ipairs(itemIDsToUpdate) do
                                local avg = select(1, GetCommodityStats(id))
                                if avg and avg > 0 then successCount = successCount + 1 end
                            end

                            print(string.format("|cff33ff99[ARP]|r Scan complete: %d/%d success.", successCount, totalItems))
                            
                            if panel.statusBottom then
                                panel.statusBottom:SetText(string.format("Done: %d/%d Success", successCount, totalItems))
                            end

                            -- Step 3: The "Grand Reveal"
                            C_Timer.After(0.1, function()
                                updating = false -- This re-enables UI updates
                                StartUpdateCooldown()
                                if ARP.UpdateAllEntries then ARP:UpdateAllEntries() end
                            end)
                        end
                    end

                    -- Start the staggered math processing
                    ProcessMathChunk()
                end)
            end
        end)
    end
end

if updateBtn then
    updateBtn:SetScript("OnClick", function() ARP:UpdatePrices() end)
end

-- ================= Store/Update ItemDB =================
local function StoreItemData(itemName, itemID, avg, minP, maxP, collected, itemLink, category)
    if not itemName or not itemID then return end

    -- Stop if the panel is locked or hidden
    if SafeAddItemCheck() then
        return
    end

    -- Ensure itemID is a valid number
    itemID = tonumber(itemID)
    if not itemID then
        print("|cffff4444[ARP]|r [ERROR] Invalid itemID:", tostring(itemID))
        return
    end

    -- Attempt to safely add item (noop if conditions not met)
    ARP:SafeAddItem(list, itemID)

    -- Initialize the main ItemDB
    AverageReagentPriceDB.itemDB = AverageReagentPriceDB.itemDB or {}
    AverageReagentPriceDB.itemDB[itemName] = AverageReagentPriceDB.itemDB[itemName] or {}

    -- Store or update item entry
    AverageReagentPriceDB.itemDB[itemName][itemID] = {
        avgPrice = tonumber(avg) or 0,
        minPrice = tonumber(minP) or 0,
        maxPrice = tonumber(maxP) or 0,
        collected = tonumber(collected) or 0,
        itemLink = itemLink,
        itemID = itemID,
        mainCategory = category or "Miscellaneous",
    }

    -- Add to the active user list if one exists
    if ARP_DB and ARP_DB.ActiveUserList then
        local userList = ARP_DB.UserLists and ARP_DB.UserLists[ARP_DB.ActiveUserList]
        if userList then
            userList.items = userList.items or {}

            -- Ensure item entry is a table so we can store per-list overrides
            if type(userList.items[itemID]) ~= "table" then
                userList.items[itemID] = {
                    quantityOverride = userList.items[itemID] == true and nil or userList.items[itemID]
                }
            end
        end
    end
end

-- ================= Update All Entries (Safe) =================

-- ===================== Get Effective Quantity =====================
-- Resolves final quantity in this order:
-- 1) Per-list, per-item override
-- 2) Per-list default quantity
-- 3) ItemDB override
-- 4) Global default quantity
function ARP:GetEffectiveQuantity(listName, itemID)
    local globalQty = tonumber(AverageReagentPriceDB.quantity) or 200

    -- No list active → use global or itemDB override
    if not listName then
        -- Check itemDB override
        for _, group in pairs(AverageReagentPriceDB.itemDB or {}) do
            local entry = group[itemID]
            if entry and entry.quantityOverride and entry.quantityOverride ~= "DEFAULT" then
                return tonumber(entry.quantityOverride) or globalQty
            end
        end
        return globalQty
    end

    local userList = ARP_DB.UserLists[listName]
    if not userList then
        return globalQty
    end

    -- ======================
    -- 1) Per-list per-item override
    -- ======================
    local items = userList.items

    if items then
        local item = items[itemID]

        -- OLD LIST FORMAT FIX:
        -- If "item" is a number, the list is legacy; no overrides exist.
        if type(item) == "table" then
            if item.quantityOverride and item.quantityOverride ~= "DEFAULT" then
                return tonumber(item.quantityOverride)
            end
        end
    end

    -- ======================
    -- 2) Per-list default quantity
    -- ======================
    if userList.quantityOverride and tonumber(userList.quantityOverride) then
        return tonumber(userList.quantityOverride)
    end

    -- ======================
    -- 3) ItemDB override
    -- ======================
    for _, group in pairs(AverageReagentPriceDB.itemDB or {}) do
        local entry = group[itemID]
        if entry and entry.quantityOverride and entry.quantityOverride ~= "DEFAULT" then
            return tonumber(entry.quantityOverride)
        end
    end

    -- ======================
    -- 4) Global default
    -- ======================
    return globalQty
end



function ARP:UpdateAllEntries()
    local baseDefault = AverageReagentPriceDB.quantity or 200
    local db = AverageReagentPriceDB.itemDB or {}
    local yOffset = 0
    selectedCategory = selectedCategory or "All"

    local activeListName = ARP_DB.ActiveUserList
    local activeList = (ARP_DB.UserLists and activeListName) and ARP_DB.UserLists[activeListName] or nil
    local isLocked = ARP_DB.ListLock 

    local applyCategoryFilter = (selectedCategory ~= "All" and selectedCategory ~= "User List")
    local applyUserListFilter = (selectedCategory == "User List" and activeList ~= nil)

    panel.itemEntries = panel.itemEntries or {}
    for _, entry in pairs(panel.itemEntries) do
        if entry.bg then entry.bg:Hide() end
        if entry.childEntries then
            for _, c in pairs(entry.childEntries) do
                if c.bg then c.bg:Hide() end
            end
        end
        if entry.summaryEdit then entry.summaryEdit:Hide() end
    end

    local itemNames = {}
    for itemName, _ in pairs(db) do table.insert(itemNames, itemName) end
    table.sort(itemNames)

    for _, itemName in ipairs(itemNames) do
        local topEntry = panel.itemEntries[itemName]
        if not topEntry then
            topEntry = {}
            topEntry.bg = CreateFrame("Frame", nil, panel.scrollChild, "BackdropTemplate")
            topEntry.bg:SetSize(panelWidth - 40, 30)
            topEntry.bg:SetBackdrop({bgFile="Interface\\BUTTONS\\WHITE8X8"})
            topEntry.bg:SetBackdropColor(0,0,0,0)
            topEntry.name = topEntry.bg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            topEntry.name:SetPoint("LEFT", 5, 0)
            topEntry.name:SetText(itemName)
            topEntry.toggleBtn = CreateFrame("Button", nil, topEntry.bg)
            topEntry.toggleBtn:SetSize(16,16)
            topEntry.toggleBtn:SetPoint("RIGHT", topEntry.bg, "RIGHT", -5, 0)
            topEntry.toggleBtn:SetNormalFontObject("GameFontNormal")
            topEntry.toggleBtn:SetHighlightFontObject("GameFontHighlight")
            topEntry.collapsed = (AverageReagentPriceDB.collapsedState or {})[itemName] or false
            topEntry.toggleBtn:SetText(topEntry.collapsed and "+" or "-")
            topEntry.toggleBtn:SetScript("OnClick", function()
                topEntry.collapsed = not topEntry.collapsed
                topEntry.toggleBtn:SetText(topEntry.collapsed and "+" or "-")
                AverageReagentPriceDB.collapsedState = AverageReagentPriceDB.collapsedState or {}
                AverageReagentPriceDB.collapsedState[itemName] = topEntry.collapsed
                ARP:UpdateAllEntries()
            end)
            topEntry.summaryEdit = CreateFrame("EditBox", nil, topEntry.bg, "InputBoxTemplate")
            topEntry.summaryEdit:SetPoint("LEFT", topEntry.name, "RIGHT", 10, 0)
            topEntry.summaryEdit:SetPoint("RIGHT", topEntry.toggleBtn, "LEFT", -5, 0)
            topEntry.summaryEdit:SetAutoFocus(false)
            topEntry.summaryEdit:SetFontObject(GameFontNormal)
            topEntry.summaryEdit:SetHeight(20)
            topEntry.childEntries = {}
            panel.itemEntries[itemName] = topEntry
        end

        local childKeys = {}
        for key, _ in pairs(db[itemName] or {}) do table.insert(childKeys, key) end
        pcall(function() table.sort(childKeys) end)

        local hasVisibleChildren = false
        for _, key in ipairs(childKeys) do
            local data = (db[itemName] or {})[key]
            if data and data.itemID then
                local showChild = true
                if applyCategoryFilter and (data.mainCategory or "Miscellaneous") ~= selectedCategory then showChild = false end
                if applyUserListFilter then showChild = (activeList.items and activeList.items[data.itemID]) ~= nil end
                if showChild then hasVisibleChildren = true; break end
            end
        end

        if (applyCategoryFilter or applyUserListFilter) and not hasVisibleChildren then
            topEntry.bg:Hide()
        else
            topEntry.bg:ClearAllPoints()
            topEntry.bg:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, -yOffset)
            topEntry.bg:Show()

            local childYOffset = yOffset + 35
            local rankData = {}

            if not topEntry.collapsed then
                for idx, key in ipairs(childKeys) do
                    local data = db[itemName][key]
                    if data and data.itemID then
                        local itemID = data.itemID
                        local showChild = true
                        if applyCategoryFilter and (data.mainCategory or "Miscellaneous") ~= selectedCategory then showChild = false end
                        if applyUserListFilter then showChild = (activeList.items and activeList.items[itemID]) ~= nil end

                        if showChild then
                            local child = topEntry.childEntries[key]
                            if not child then
                                child = {}
                                child.bg = CreateFrame("Frame", nil, panel.scrollChild, "BackdropTemplate")
                                child.bg:SetSize(panelWidth - 60, 40)
                                child.bg:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
                                child.bg:SetBackdropColor(0, 0, 0, 0)
                                child.name = child.bg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                                child.name:SetPoint("TOPLEFT", 5, -5)
                                child.qtyLabel = child.bg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                                child.qtyLabel:SetPoint("TOPLEFT", child.name, "TOPRIGHT", 100, 0)
                                child.qtyLabel:SetText("Quantity Override:")
                                child.quantityDropdown = CreateFrame("Frame", nil, child.bg, "UIDropDownMenuTemplate")
                                child.quantityDropdown:SetPoint("LEFT", child.qtyLabel, "RIGHT", -15, -2)
                                UIDropDownMenu_SetWidth(child.quantityDropdown, 80)
                                child.edit = CreateFrame("EditBox", nil, child.bg, "InputBoxTemplate")
                                child.edit:SetPoint("TOPLEFT", child.bg, "TOPLEFT", 5, -25)
                                child.edit:SetPoint("RIGHT", -30, 0)
                                child.edit:SetAutoFocus(false)
                                child.edit:SetFontObject(GameFontNormalSmall)
                                child.edit:SetHeight(18)
                                child.removeBtn = CreateFrame("Button", nil, child.bg, "UIPanelCloseButton")
                                child.removeBtn:SetSize(20, 20)
                                child.removeBtn:SetPoint("RIGHT", child.bg, "RIGHT", -8, -14)
                                child.removeBtn:SetScript("OnClick", function()
                                    if ARP_DB.ListLock then return end
                                    if selectedCategory == "User List" and activeListName then
                                        ARP.UserLists:RemoveItem(key)
                                    else
                                        AverageReagentPriceDB.itemDB[itemName][key] = nil
                                        if next(AverageReagentPriceDB.itemDB[itemName]) == nil then AverageReagentPriceDB.itemDB[itemName] = nil end
                                    end
                                    ARP:UpdateAllEntries()
                                end)
                                topEntry.childEntries[key] = child
                            end

                            if isLocked then child.removeBtn:Hide() else child.removeBtn:Show() end
                            if isLocked then UIDropDownMenu_DisableDropDown(child.quantityDropdown) else UIDropDownMenu_EnableDropDown(child.quantityDropdown) end
                            child.name:SetText(data.itemLink or (itemName .. " - Rank " .. idx))

                            -- DATA RETRIEVAL: Pulling specifically for this render
                            local savedValue = nil
                            if applyUserListFilter and activeList and activeList.items[itemID] then
                                savedValue = activeList.items[itemID].quantityOverride
                            else
                                savedValue = data.quantityOverride
                            end

                            local isDef = (savedValue == nil or savedValue == "DEFAULT")
                            local effectiveVal = isDef and baseDefault or tonumber(savedValue)

                            UIDropDownMenu_Initialize(child.quantityDropdown, function(self, level)
                                local function add(txt, val)
                                    local info = UIDropDownMenu_CreateInfo()
                                    info.text = txt; info.value = val; info.disabled = isLocked
                                    info.func = function()
                                        if isLocked then return end
                                        local target = (val == "DEFAULT") and nil or val
                                        
                                        -- SAVE LOGIC: Targeted specifically to ensure Global DB persistence
                                        if selectedCategory == "User List" and activeList then
                                            activeList.items[itemID] = activeList.items[itemID] or {}
                                            activeList.items[itemID].quantityOverride = target
                                        else
                                            -- Use absolute path to the global DB to ensure it sticks
                                            if AverageReagentPriceDB.itemDB[itemName] and AverageReagentPriceDB.itemDB[itemName][key] then
                                                AverageReagentPriceDB.itemDB[itemName][key].quantityOverride = target
                                            end
                                        end
                                        
                                        ARP:RecalculateAverage(itemID)
                                        CloseDropDownMenus()
                                        ARP:UpdateAllEntries()
                                    end
                                    if val == "DEFAULT" then info.checked = isDef else info.checked = (tonumber(savedValue) == val) end
                                    UIDropDownMenu_AddButton(info, level)
                                end
                                add("Default", "DEFAULT"); add("25", 25); add("100", 100); add("250", 250); add("500", 500); add("1000", 1000); add("2000", 2000)
                            end)

                            UIDropDownMenu_SetText(child.quantityDropdown, isDef and "Default" or tostring(effectiveVal))

                            local sourceLabel = (applyUserListFilter and activeList and activeList.items[itemID] and activeList.items[itemID].quantityOverride) and "Preset" or "Global"
                            child.edit:SetText(string.format("Qty: %s (%s) | Avg: %s | Min: %s | Max: %s",
                                tostring(effectiveVal), sourceLabel, FormatGoldLocalized(data.avgPrice or 0), FormatGoldLocalized(data.minPrice or 0), FormatGoldLocalized(data.maxPrice or 0)))

                            child.bg:ClearAllPoints()
                            child.bg:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 20, -childYOffset)
                            child.bg:Show()
                            childYOffset = childYOffset + 50
                            
                            local itemRank = GetItemRank(data.itemLink) or 1
                            rankData[itemRank] = tonumber(data.avgPrice) or 0
                        end
                    end
                end
            end

            local summaryParts = {itemName}
            for r = 1, 3 do table.insert(summaryParts, "Rank " .. r .. ", " .. FormatGoldLocalized(rankData[r] or 0)) end
            topEntry.summaryEdit:SetText(table.concat(summaryParts, ", "))
            topEntry.summaryEdit:Show()
            yOffset = childYOffset + 10
        end
    end
    panel.scrollChild:SetHeight(math.max(yOffset, 400))
end

-- ================= Recalculate All Averages =================
function ARP:RecalculateAllAverages(ignoreCache)
    local db = AverageReagentPriceDB.itemDB or {}
    local globalQty = tonumber(AverageReagentPriceDB.quantity) or 200
    local trimPercent = math.max( tonumber(AverageReagentPriceDB.trim) or 0, 0 )
    if trimPercent > 100 then trimPercent = 100 end

    for itemName, itemEntries in pairs(db) do
        for key, data in pairs(itemEntries) do
            if data and data.itemID then
                local itemID = data.itemID
                local preservedOverride = data.quantityOverride  -- keep original stored value untouched
                local results = nil

                if (not ignoreCache)
                    and ARP.commodityCache
                    and ARP.commodityCache[itemID]
                    and ARP.commodityCache[itemID].prices
                then
                    results = ARP.commodityCache[itemID].prices
                else
                    GetCommodityStats(itemID)
                    results = ARP.commodityCache
                        and ARP.commodityCache[itemID]
                        and ARP.commodityCache[itemID].prices
                        or nil
                end

                if results and #results > 0 then
                    -- Use the helper that resolves per-list / per-item / itemDB / global precedence
                    local effectiveQty = ARP:GetEffectiveQuantity(ARP_DB.ActiveUserList, itemID) or globalQty
                    local selectedUnits = ExpandResultsToUnitPrices(results, effectiveQty)
                    local collected = #selectedUnits

                    if collected > 0 then
                        table.sort(selectedUnits, function(a, b) return a > b end)

                        local trimCount = math.floor(collected * (trimPercent / 100))
                        if trimCount >= collected then trimCount = collected - 1 end
                        if trimCount < 0 then trimCount = 0 end

                        local unitsToUse = {}
                        for i = trimCount + 1, #selectedUnits do
                            unitsToUse[#unitsToUse + 1] = selectedUnits[i]
                        end

                        if #unitsToUse > 0 then
                            local sum, minP, maxP = 0, unitsToUse[1], unitsToUse[1]
                            for _, price in ipairs(unitsToUse) do
                                sum = sum + price
                                if price < minP then minP = price end
                                if price > maxP then maxP = price end
                            end

                            data.avgPrice = sum / #unitsToUse
                            data.minPrice = minP
                            data.maxPrice = maxP
                            data.collected = #unitsToUse
                        end
                    end
                end

                -- keep stored DB override as-is
                data.quantityOverride = preservedOverride
            end
        end
    end

    -- Deferred redraw; call externally when needed
    C_Timer.After(0, function()
        if ARP.UpdateAllEntries then
            ARP:UpdateAllEntries()
        end
    end)
end

-- ================= Recalculate Single Average =================
function ARP:RecalculateAverage(itemID)
    if not itemID or not AverageReagentPriceDB or not AverageReagentPriceDB.itemDB then return end

    local globalQty = tonumber(AverageReagentPriceDB.quantity) or 200
    local trimPercent = math.max( tonumber(AverageReagentPriceDB.trim) or 0, 0 )
    if trimPercent > 100 then trimPercent = 100 end

    for category, entries in pairs(AverageReagentPriceDB.itemDB) do
        for key, data in pairs(entries) do
            if data.itemID == itemID then
                local preservedOverride = data.quantityOverride
                local results = nil

                if ARP.commodityCache
                    and ARP.commodityCache[itemID]
                    and ARP.commodityCache[itemID].prices
                then
                    results = ARP.commodityCache[itemID].prices
                else
                    GetCommodityStats(itemID)
                    results = ARP.commodityCache
                        and ARP.commodityCache[itemID]
                        and ARP.commodityCache[itemID].prices
                        or nil
                end

                if results and #results > 0 then
                    -- Use the helper to resolve effective quantity (per-list overrides included)
                    local effectiveQty = ARP:GetEffectiveQuantity(ARP_DB.ActiveUserList, itemID) or globalQty
                    local selectedUnits = ExpandResultsToUnitPrices(results, effectiveQty)
                    local collected = #selectedUnits

                    if collected > 0 then
                        table.sort(selectedUnits, function(a, b) return a > b end)

                        local trimCount = math.floor(collected * (trimPercent / 100))
                        if trimCount >= collected then trimCount = collected - 1 end
                        if trimCount < 0 then trimCount = 0 end

                        local unitsToUse = {}
                        for i = trimCount + 1, #selectedUnits do
                            unitsToUse[#unitsToUse + 1] = selectedUnits[i]
                        end

                        if #unitsToUse > 0 then
                            local sum, minP, maxP = 0, unitsToUse[1], unitsToUse[1]
                            for _, price in ipairs(unitsToUse) do
                                sum = sum + price
                                if price < minP then minP = price end
                                if price > maxP then maxP = price end
                            end

                            data.avgPrice = sum / #unitsToUse
                            data.minPrice = minP
                            data.maxPrice = maxP
                            data.collected = #unitsToUse
                        end
                    end
                end

                data.quantityOverride = preservedOverride

                if not updating then 
                C_Timer.After(0, function()
                    if ARP.UpdateAllEntries then
                        ARP:UpdateAllEntries()
                    end
                end)
            end

                return
            end
        end
    end
end

-- =============================
-- User List Section for ARP
-- =============================
ARP.UserLists = {}

-- Ensure database exists
ARP_DB.UserLists = ARP_DB.UserLists or {}
ARP_DB.ActiveUserList = ARP_DB.ActiveUserList or nil

-- -----------------------------
-- Create a new User List
-- -----------------------------
function ARP.UserLists:Create(listName)
    if not listName or listName == "" then
        print("Cannot create a list without a name.")
        return
    end

    if ARP_DB.UserLists[listName] then
        print("A list with that name already exists.")
        return
    end

    ARP_DB.UserLists[listName] = { items = {} }
    ARP_DB.ActiveUserList = listName
    print("User List '" .. listName .. "' created and set as active.")
end

-- -----------------------------
-- Delete a User List
-- -----------------------------
function ARP.UserLists:Delete(listName)
    if not listName or not ARP_DB.UserLists[listName] then
        print("List does not exist.")
        return
    end

    ARP_DB.UserLists[listName] = nil
    if ARP_DB.ActiveUserList == listName then
        ARP_DB.ActiveUserList = nil
    end

    print("User List '" .. listName .. "' deleted.")
end

-- ================= UserLists:AddItem =================
function ARP.UserLists:AddItem(itemID, itemName, itemLink, category)
    if SafeAddItemCheck() then
        print("|cffff4444[ARP]|r Cannot add item: panel locked or hidden.")
        return
    end

    if selectedCategory ~= "User List" then
        print("|cffff4444[ARP]|r Cannot add item: not in User List mode.")
        return
    end

    local listName = ARP_DB.ActiveUserList
    if not listName then
        print("|cffff4444[ARP]|r No active user list selected.")
        return
    end

    local list = ARP_DB.UserLists[listName]
    if not list then
        ARP_DB.UserLists[listName] = { items = {} }
        list = ARP_DB.UserLists[listName]
    end

    -- Add to user list
    list.items[itemID] = list.items[itemID] or { quantityOverride = nil }
    print("|cff33ff99[ARP]|r Item", itemID, "added to user list:", listName)

    -- Also add to global DB
    ARP:SafeAddItem(list, itemID, itemName, itemLink, category)

    ARP:UpdateAllEntries()
end

-- -----------------------------
-- Remove an item from the active list
-- -----------------------------
function ARP.UserLists:RemoveItem(itemID)
    local listName = ARP_DB.ActiveUserList
    if not listName then
        print("No active user list selected.")
        return
    end

    local list = ARP_DB.UserLists[listName]
    if not list then return end

    list.items[itemID] = nil
    --print("|cff33ff99[ARP]|r Removed item", itemID, "from user list:", listName)

    -- Check if any other list still uses this item
    local stillUsed = false
    for otherListName, otherList in pairs(ARP_DB.UserLists) do
        if otherListName ~= listName and otherList.items[itemID] then
            stillUsed = true
            break
        end
    end

    -- Do NOT remove from itemDB — global registry remains intact
end


-- -----------------------------
-- Get all User List names
-- -----------------------------
function ARP.UserLists:GetAll()
    local lists = {}
    for name, _ in pairs(ARP_DB.UserLists) do
        table.insert(lists, name)
    end
    return lists
end

-- -----------------------------
-- Get the active User List
-- -----------------------------
function ARP.UserLists:GetActive()
    return ARP_DB.ActiveUserList
end


-- ================= Export List Popup =================
function ARP:ShowExportPopup(exportString)
    if not ARP_ExportPopup then
        local popup = CreateFrame("Frame", "ARP_ExportPopup", UIParent, "BackdropTemplate")
        popup:SetSize(450, 300)
        popup:SetPoint("CENTER")
        popup:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 14, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        popup:SetBackdropColor(0, 0, 0, 0.85)
        popup:SetBackdropBorderColor(1, 0.84, 0, 1)
        popup:SetFrameStrata("DIALOG")

        -- Make movable
        popup:SetMovable(true)
        popup:EnableMouse(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop", popup.StopMovingOrSizing)

        -- Title
        popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        popup.title:SetPoint("TOPLEFT", 12, -8)
        popup.title:SetText("Export List")

        -- Scrollable EditBox
        popup.scrollFrame = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
        popup.scrollFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -40)
        popup.scrollFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -30, 10)

        popup.editBox = CreateFrame("EditBox", nil, popup.scrollFrame)
        popup.editBox:SetMultiLine(true)
        popup.editBox:SetFontObject(GameFontNormal)
        popup.editBox:SetWidth(600 - 40)
        popup.editBox:SetHeight(450)
        popup.editBox:SetAutoFocus(true)
        popup.editBox:EnableMouse(true)
        popup.editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            popup:Hide()
        end)

        popup.scrollFrame:SetScrollChild(popup.editBox)

        -- Close button
        local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -6, -6)
        closeBtn:SetScript("OnClick", function() popup:Hide() end)

        ARP_ExportPopup = popup
    end

    -- Set text and show
    ARP_ExportPopup.editBox:SetText(exportString)
    ARP_ExportPopup.editBox:HighlightText()
    ARP_ExportPopup:Show()
end

-- ##########################
-- Helper Functions for User List Dropdowns
-- ##########################

ARP.UserLists.Helpers = {}

-- Returns an array of all user list names
function ARP.UserLists.Helpers.GetListNames()
    local names = {}
    for name, _ in pairs(ARP_DB.UserLists) do
        table.insert(names, name)
    end
    table.sort(names) -- optional: alphabetical order
    return names
end

-- Returns the currently active list name
function ARP.UserLists.Helpers.GetActiveListName()
    return ARP_DB.ActiveUserList
end

-- Sets a list as active
function ARP.UserLists.Helpers.SetActiveList(listName)
    if ARP_DB.UserLists[listName] then
        ARP_DB.ActiveUserList = listName
        return true
    else
        return false, "List does not exist"
    end
end

-- Clears the active list (for switching back to 'All')
function ARP.UserLists.Helpers.ClearActiveList()
    ARP_DB.ActiveUserList = nil
end

-- Checks if a given itemID is in the active list
function ARP.UserLists.Helpers.ItemInActiveList(itemID)
    local active = ARP_DB.ActiveUserList
    if not active then return false end
    return ARP_DB.UserLists[active].items[itemID] or false
end

-- ================= User List Helpers =================
local function SetActiveUserList(name)
    if name and ARP_DB.UserLists[name] then
        ARP_DB.ActiveUserList = name
        ARP.selectedPrimaryFilter = "UserList"
    else
        ARP_DB.ActiveUserList = nil
        ARP.selectedPrimaryFilter = "All"
    end
end

-- Add an item to the currently active User List
function ARP:AddItemToActiveList(itemID)
    if SafeAddItemCheck() then
        print("|cffff4444[ARP]|r Cannot add item: panel is locked or hidden.")
        return
    end

    ARP:SafeAddItem(list, itemID)

    if selectedCategory ~= "User List" then
        print("|cffff4444[ARP]|r Blocked AddItemToActiveList: not in User List mode.")
        return
    end

    if ARP_DB.ActiveUserList then
        local activeList = ARP_DB.UserLists[ARP_DB.ActiveUserList]

        activeList.items = activeList.items or {}

        -- Convert old boolean format, or create fresh entry
        if type(activeList.items[itemID]) ~= "table" then
            activeList.items[itemID] = { quantityOverride = nil }
        end

        print("|cff33ff99[ARP]|r Item", itemID, "added via AddItemToActiveList to:", ARP_DB.ActiveUserList)
    end
end

-- ===== ARP Clean Function =====
function ARP:Clean()
    print("|cff33ff99[ARP]|r Starting full cleanup...")

    -- ================= Phase 1: Migrate Legacy itemDB Format =================
    for itemName, group in pairs(AverageReagentPriceDB.itemDB or {}) do
        local migratedGroup = {}

        for legacyKey, entry in pairs(group) do
            if type(legacyKey) == "string" and legacyKey:match("_%d+$") and type(entry) == "table" then
                local itemID = tonumber(legacyKey:match("_(%d+)$"))
                if itemID then
                    migratedGroup[itemID] = {
                        itemID = itemID,
                        itemLink = entry.itemLink,
                        mainCategory = entry.mainCategory,
                        _cleared = true,
                        quantityOverride = entry.quantityOverride or nil
                    }
                    print("|cffffcc00[ARP]|r Migrated legacy entry:", legacyKey, "→", itemID)
                end
            end
        end

        if next(migratedGroup) then
            AverageReagentPriceDB.itemDB[itemName] = migratedGroup
        end
    end

    -- ================= Phase 2: Upgrade Incomplete Entries =================
    for itemName, group in pairs(AverageReagentPriceDB.itemDB or {}) do
        for itemID, entry in pairs(group) do
            if type(entry) == "table" then
                if entry.quantityOverride == nil then
                    entry.quantityOverride = "DEFAULT"
                    print("|cffffcc00[ARP]|r Initialized missing quantityOverride for:", itemName, itemID)
                end
                if entry._cleared == nil and (entry.avgPrice or entry.minPrice or entry.maxPrice) == nil then
                    entry._cleared = true
                    print("|cffffcc00[ARP]|r Marked entry as cleared:", itemName, itemID)
                end
            end
        end
    end

    -- ================= Phase 3: Remove Malformed Entries =================
    for itemName, group in pairs(AverageReagentPriceDB.itemDB or {}) do
        if type(group) ~= "table" then
            AverageReagentPriceDB.itemDB[itemName] = nil
            print("|cffff9900[ARP]|r Removed non-table item group:", itemName)
        else
            for key, entry in pairs(group) do
                local malformed =
                    type(key) ~= "number" or
                    type(entry) ~= "table" or
                    not entry.itemLink or
                    (entry.avgPrice == nil and entry.minPrice == nil and entry.maxPrice == nil and not entry._cleared)

                if malformed then
                    group[key] = nil
                    print("|cffff9900[ARP]|r Removed malformed entry:", itemName, key)
                end
            end
            if next(group) == nil then
                AverageReagentPriceDB.itemDB[itemName] = nil
                print("|cffff9900[ARP]|r Removed empty item group:", itemName)
            end
        end
    end

    print("|cff33ff99[ARP]|r Cleanup complete.")
    ARP:UpdateAllEntries()
end

-- ========== ARP Minimap Button ==========
function ARP:CreateMinimapButton()
    if AverageReagentPriceDB.minimapHidden then return end

    local button = CreateFrame("Button", "ARP_MinimapButton", Minimap)
    button:SetSize(24, 24)
    button:SetHitRectInsets(0, 0, 0, 0)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)

    button:SetNormalTexture("Interface\\Icons\\INV_Misc_Coin_01")
    button:GetNormalTexture():SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("CENTER", button, "CENTER", 10, -10)

    button.angle = AverageReagentPriceDB.minimapAngle or 45
    local function UpdatePosition()
        local radius = 105
        local rad = math.rad(button.angle)
        local x, y = math.cos(rad) * radius, math.sin(rad) * radius
        button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    button:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and IsShiftKeyDown() then
            self.isDragging = true
            self.wasDragging = false
        end
    end)

    button:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            if self.isDragging then
                self.wasDragging = true
            end
            self.isDragging = false
        end
    end)


    button:SetScript("OnUpdate", function(self)
        if self.isDragging then
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            
            -- Use Minimap's effective scale, NOT UIParent's
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale

            -- dx/dy vector from center to cursor
            local dx, dy = cx - mx, cy - my

            -- atan2 gives the correct angle independent of minimap shape/size/scale
            self.angle = math.deg(math.atan2(dy, dx))
            AverageReagentPriceDB.minimapAngle = self.angle

            UpdatePosition()
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:AddLine("ARP Tracker")
        GameTooltip:AddLine("Shift+Left-click: Drag", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Toggle panel", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Options", 1, 1, 1)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local menuFrame = CreateFrame("Frame", "ARP_MinimapMenu", UIParent, "UIDropDownMenuTemplate")
    local function MenuInit(self, level)
        if not level then return end
        local info = UIDropDownMenu_CreateInfo()

        info.text = "Toggle ARP Panel"
        info.func = function()
            if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
                print("|cff33ff99[ARP]|r The Auction House must be open to use the ARP panel.")
                return
            end
        if ARP_Frame:IsShown() then
            ARP_Frame:Hide()
            AverageReagentPriceDB.panelVisible = false
        else
            ARP_Frame:Show()
            AverageReagentPriceDB.panelVisible = true
        end

        end
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Hide Minimap Button"
        info.func = function()
            button:Hide()
            AverageReagentPriceDB.minimapHidden = true
            print("|cff33ff99[ARP]|r Minimap button hidden. Use /arp minimap to restore.")
        end
        UIDropDownMenu_AddButton(info, level)
    end

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, button)
        if self.wasDragging then
            self.wasDragging = false
            return -- suppress click if drag just ended
        end

        if button == "RightButton" then
            UIDropDownMenu_Initialize(menuFrame, MenuInit, "MENU")
            ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
            return
        end

        if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
            print("|cff33ff99[ARP]|r The Auction House must be open to use the ARP panel.")
            return
        end

        if ARP_Frame:IsShown() then
            ARP_Frame:Hide()
            AverageReagentPriceDB.panelVisible = false
            ARP.panelLocked = true
            AverageReagentPriceDB.panelLocked = true
        else
            ARP_Frame:Show()
            AverageReagentPriceDB.panelVisible = true
            ARP.panelLocked = false
            AverageReagentPriceDB.panelLocked = false
        end

    end)


    UpdatePosition()
end

-- ================= Event Handlers =================
function ARP:AUCTION_HOUSE_SHOW()
    PositionPanel()
    if AverageReagentPriceDB.panelVisible then
        panel:Show()
    end

    -- Clear cached price data (not itemDB)
    ARP.commodityCache = {}

    -- Set quantity and trim from SavedVariables
    if qtyEdit then
        qtyEdit:SetText(tostring(AverageReagentPriceDB.quantity or 200))
    end
    if trimEdit then
        trimEdit:SetText(tostring(AverageReagentPriceDB.trim or 2))
    end

    -- Rebuild panel from current data
    ARP:UpdateAllEntries()
end

function ARP:AUCTION_HOUSE_CLOSED()
    if panel:IsShown() then
        ARP_Frame.wasManuallyHidden = false  -- Not a user action
        panel:Hide()
    end

    -- Clear stored prices so they show 0.00 and mark as cleared
    local db = AverageReagentPriceDB.itemDB
    if type(db) ~= "table" then
        return -- or: db = {} if you want to force reset
    end

    for itemName, entries in pairs(db) do
        if type(entries) == "table" then
            for key, data in pairs(entries) do
                if type(data) == "table" then
                    data.avgPrice = nil
                    data.minPrice = nil
                    data.maxPrice = nil
                    data.collected = nil
                    data._cleared = true  -- mark as cleared
                end
            end
        else
            -- Optional: clean up corrupted values
            db[itemName] = nil
        end
    end

    print("|cff33ff99[ARP]|r Cleared cached prices on AH close.")
end

function ARP:ShowReadMePanel(show)
    self:CreateReadMePanel()
    if show then
        self.readMePanel:Show()
    else
        self.readMePanel:Hide()
    end
end

ARP.readMePanel = CreateReadMePanel()

function ARP:COMMODITY_SEARCH_RESULTS_UPDATED()
    C_Timer.After(0, function()
        local itemID = GetCurrentCommodityItemID()
        if not itemID then return end

        local now = GetTime()
        if itemID == lastItemID and (now - lastPrintTime) < debounceDelay then return end
        lastItemID, lastPrintTime = itemID, now

        -- Get fresh stats from AH results
        local avg, minP, maxP, collected = GetCommodityStats(itemID)
        if not avg then
            ARP.pendingRecalc = true
            return
        end

        -- Store item data in the database
        local itemName, itemLink = GetItemInfo(itemID)
        if not itemLink then
            itemLink = string.format("|cffffffffItem %d|r", itemID)
            itemName = "Item " .. itemID
        end

        lastItemLink = itemLink
        local category = GetItemCategory(itemID)
        StoreItemData(itemName, itemID, avg, minP, maxP, collected, itemLink, category)

        -- ✅ Only recalculate this item, not all
        if ARP.RecalculateAverage then
            ARP:RecalculateAverage(itemID)
        else
            -- fallback in case the single-item function doesn't exist
            ARP:RecalculateAllAverages(true)
        end

        ARP.pendingRecalc = false

        -- If a deferred recalc is pending, do it now
        if ARP.pendingRecalc then
            ARP:RecalculateAllAverages()
            ARP.pendingRecalc = false
        end

        -- Update panel entry for this item
        if panel.entries and panel.entries[itemID] then
            panel.entries[itemID]:UpdateDisplay(avg, minP, maxP, collected)
        else
            ARP:UpdateAllEntries()
        end

        panel.status:SetText(itemLink or "No data yet")
    end)
end

-- ================= Slash Commands =================
SLASH_ARP1 = "/arp"
SlashCmdList["ARP"] = function(msg)
    local cmd = msg:lower()

    if cmd == "clear" then
        -- Clear all stored data
        AverageReagentPriceDB.itemDB = {}
        ARP_DB.UserLists = {}
        ARP_DB.ActiveUserList = nil
        AverageReagentPriceDB.collapsedState = {}
        AverageReagentPriceDB.quantity = nil
        AverageReagentPriceDB.trim = nil

        -- Refresh UI
        ARP:UpdateAllEntries()

        print("|cff33ff99[ARP]|r All data cleared, including user lists and categories.")

    elseif cmd == "clean" then
        -- Unified cleanup: itemDB + user list repair
        ARP:Clean()

elseif cmd == "show" then
    if ARP_Frame then
        ARP_Frame:Show()
        AverageReagentPriceDB.panelVisible = true
        -- If previously locked, treat as unlocked when explicitly shown
        if ARP.panelLocked == nil then ARP.panelLocked = false end
    end

elseif cmd == "hide" then
    if ARP_Frame then
        ARP_Frame.wasManuallyHidden = true
        ARP_Frame:Hide()
        -- Treat hiding as locking the panel in the background
        ARP.panelLocked = true
        AverageReagentPriceDB.panelLocked = true
    end

    elseif cmd == "minimap" then
        AverageReagentPriceDB.minimapHidden = false
        if ARP_MinimapButton then
            ARP_MinimapButton:Show()
        elseif ARP.CreateMinimapButton then
            ARP:CreateMinimapButton()
        end
        print("|cff33ff99[ARP]|r Minimap button restored.")

            elseif cmd == "notice" then
        if ARP.ShowPatchNoticePopup then
            ARP:ShowPatchNoticePopup()
        else
            print("|cffff4444[ARP]|r Patch notice function not available.")
        end

    elseif cmd == "help" or cmd == "" then
        print("|cff33ff99[ARP]|r Available commands:")
        print(" - /arp clear       : Clear all saved data")
        print(" - /arp clean       : Clean and repair saved data (itemDB and user lists)")
        print(" - /arp show        : Show the ARP Tracker panel")
        print(" - /arp hide        : Hide the ARP Tracker panel")
        print(" - /arp minimap     : Restore the minimap button")

    else
        print("|cff33ff99[ARP]|r Unknown command. Type /arp help for options.")
    end
end

function ARP:OnInitialize()
    -- Ensure SavedVariables exist
    AverageReagentPriceDB = AverageReagentPriceDB or {}
    AverageReagentPriceDB.itemDB = AverageReagentPriceDB.itemDB or {}

    -- ✅ 1. Initialize the Cache (Building the structural "Skeleton")
    ARP:InitializePreCache()

    -- Default visibility flag
    if AverageReagentPriceDB.panelVisible == nil then
        AverageReagentPriceDB.panelVisible = false
    end

    -- Default minimap visibility flag
    if AverageReagentPriceDB.minimapHidden == nil then
        AverageReagentPriceDB.minimapHidden = false
    end

    -- Default lock state
    if AverageReagentPriceDB.panelLocked == nil then
        AverageReagentPriceDB.panelLocked = false
    end

    -- Patch version tracking
    if SHOW_PATCH_NOTICE and AverageReagentPriceDB.lastSeenVersion ~= CURRENT_PATCH_VERSION then
        C_Timer.After(1, function()
            ARP:ShowPatchNoticePopup()
        end)
        AverageReagentPriceDB.lastSeenVersion = CURRENT_PATCH_VERSION
    end

    -- Create minimap button if not hidden — defer to ensure function is defined
    C_Timer.After(0, function()
        if not AverageReagentPriceDB.minimapHidden and ARP.CreateMinimapButton then
            ARP:CreateMinimapButton()
        end
    end)

    -- ✅ Sync runtime lock state from saved vars
    ARP.panelLocked = AverageReagentPriceDB.panelLocked or false

    -- ✅ Sync the checkbox if it already exists
    C_Timer.After(0, function()
        if panel and panel.lockPanelCheckbox then
            panel.lockPanelCheckbox:SetChecked(ARP.panelLocked)
        end
    end)
end

--- ✅ CACHE HELPERS ---

-- Helper: Gets a key from cache or makes a new one
function ARP:GetCachedItemKey(itemID)
    if not itemID then return nil end
    
    -- Check if we already did the "math" for this item
    if self.ItemKeyCache and self.ItemKeyCache[itemID] then 
        return self.ItemKeyCache[itemID] 
    end

    -- Generate and save for next time
    local itemKey = C_AuctionHouse.MakeItemKey(itemID)
    self.ItemKeyCache = self.ItemKeyCache or {}
    self.ItemKeyCache[itemID] = itemKey
    return itemKey
end

-- Builder: Loops through your SavedVariables to fill the cache at login
function ARP:InitializePreCache()
    local db = AverageReagentPriceDB.itemDB
    if not db then return end
    
    self.ItemKeyCache = self.ItemKeyCache or {}
    
    for itemName, ranks in pairs(db) do
        for _, data in pairs(ranks) do
            if data.itemID then
                -- Warm up the engine for this item
                self:GetCachedItemKey(data.itemID)
            end
        end
    end
end

-- ================= OnEnable =================
function ARP:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")
    self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
end