-- GoldAdvisorMidnight/UI/ManualPrice.lua
-- Manual input prices: right-click a material row to set or clear your own
-- price. Shared by the main window detail panel and the Strategy Detail window.
-- Only active when Settings > Pricing > "Manual material prices" is on.
-- Module: GAM.UI.ManualPrice

local ADDON_NAME, GAM = ...
local ManualPrice = {}
GAM.UI.ManualPrice = ManualPrice

local Common = GAM.UI.MainWindowCommon
local WindowManager = GAM.UI.WindowManager

local popup

local function L(key, fallback)
    return (GAM.L and GAM.L[key]) or fallback
end

local function Enabled()
    return GAM.Pricing and GAM.Pricing.ManualPricesEnabled and GAM.Pricing.ManualPricesEnabled()
end

-- GetManualPrice(itemID, patchTag) → copper or nil (nil also when the feature is off).
function ManualPrice.Get(itemID, patchTag)
    return Enabled() and GAM.Pricing.GetPriceOverride(itemID, patchTag) or nil
end

-- Price cell text: an amber dot marks a manual price.
function ManualPrice.DecoratePrice(text, itemID, patchTag)
    if ManualPrice.Get(itemID, patchTag) == nil then return text end
    return Common.StatusDot("warn", 10) .. " " .. text
end

-- Names of the shown materials that use a manual price, for the strategy note.
function ManualPrice.NamesInUse(reagentMetrics, patchTag)
    local names = {}
    if not Enabled() then return names end
    for _, metric in ipairs(reagentMetrics or {}) do
        if not metric.crafted and ManualPrice.Get(metric.itemID, patchTag) ~= nil then
            names[#names + 1] = metric.name or tostring(metric.itemID)
        end
    end
    return names
end

function ManualPrice.NoteText(reagentMetrics, patchTag)
    local names = ManualPrice.NamesInUse(reagentMetrics, patchTag)
    if #names == 0 then return nil end
    return Common.StatusDot("warn", 10) .. " "
        .. string.format(L("MANUAL_PRICES_IN_USE", "Your prices: %s"), table.concat(names, ", "))
end

-- Extra tooltip lines for a material row (tt = row._metricTooltip).
function ManualPrice.AddTooltipLines(tt)
    if not (tt and tt.kind == "reagent" and tt.itemID and Enabled()) then return end
    if tt.crafted then
        GameTooltip:AddLine(L("TT_MANUAL_PRICE_CRAFTED",
            "Crafted here: set your prices on its materials instead."), 0.75, 0.75, 0.75, true)
        return
    end
    local manual = ManualPrice.Get(tt.itemID, tt.patchTag)
    if manual ~= nil then
        local market = GAM.Pricing.GetMarketPrice(tt.itemID, tt.patchTag, tt.needToBuy)
        GameTooltip:AddLine(string.format(L("TT_MANUAL_PRICE_SET", "Your price: %s (market: %s)"),
            GAM.Pricing.FormatPrice(manual),
            market and GAM.Pricing.FormatPrice(market) or "—"), 1, 0.82, 0)
    end
    GameTooltip:AddLine(L("TT_MANUAL_PRICE_HINT", "Right-click to set your own price."),
        0.75, 0.75, 0.75, true)
end

local function Refresh()
    if GAM.UI.MainWindow and GAM.UI.MainWindow.Refresh then GAM.UI.MainWindow.Refresh() end
    if GAM.UI.StrategyDetail and GAM.UI.StrategyDetail.IsShown and GAM.UI.StrategyDetail.IsShown() then
        GAM.UI.StrategyDetail.Refresh()
    end
    if GAM.UI.CraftPlanWindow and GAM.UI.CraftPlanWindow.Refresh then GAM.UI.CraftPlanWindow.Refresh() end
end

local function MoneyText(copper)
    local gold = copper / 10000
    if gold == math.floor(gold) then return tostring(gold) end
    return (string.format("%.4f", gold):gsub("0+$", ""))
end

local function BuildPopup()
    popup = CreateFrame("Frame", GAM.RuntimeName("GAMManualPricePopup"), UIParent, "BackdropTemplate")
    popup:SetSize(340, 150)
    popup:SetPoint("CENTER")
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    popup:SetClampedToScreen(true)
    popup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    popup:SetBackdropColor(0, 0, 0, 1)
    popup:Hide()
    WindowManager.Register(popup, "modal")

    popup.title = popup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    popup._gamTitle = popup.title
    popup.title:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -18)
    popup.title:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -20, -18)
    popup.title:SetJustifyH("LEFT")
    popup.title:SetWordWrap(false)

    popup.market = popup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    popup.market:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", 0, -6)
    popup.market:SetJustifyH("LEFT")

    local editBox = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    editBox:SetSize(140, 24)
    editBox:SetPoint("TOPLEFT", popup.market, "BOTTOMLEFT", 6, -8)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(20)
    popup.editBox = editBox

    popup.help = popup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    popup.help:SetPoint("LEFT", editBox, "RIGHT", 8, 0)
    popup.help:SetText(L("MANUAL_PRICE_FORMAT", "e.g. 12.5 or 12g 50s"))
    popup.help:SetTextColor(0.68, 0.68, 0.72)

    local function Close() popup:Hide() end
    local function Save()
        local copper = GAM.Pricing.ParseMoneyText(editBox:GetText())
        if not copper then
            popup.market:SetText("|cffff5555" .. L("MANUAL_PRICE_INVALID", "Enter a price such as 12.5 or 12g 50s.") .. "|r")
            return
        end
        GAM.Pricing.SetPriceOverride(popup.itemID, copper, popup.patchTag)
        Close()
        Refresh()
    end
    local function Clear()
        GAM.Pricing.ClearPriceOverride(popup.itemID, popup.patchTag)
        Close()
        Refresh()
    end
    editBox:SetScript("OnEnterPressed", Save)
    editBox:SetScript("OnEscapePressed", Close)

    local saveBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    saveBtn:SetSize(90, 22)
    saveBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -16, 14)
    saveBtn:SetText(L("BTN_MANUAL_PRICE_SET", "Set price"))
    saveBtn:SetScript("OnClick", Save)

    local clearBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    clearBtn:SetSize(110, 22)
    clearBtn:SetPoint("RIGHT", saveBtn, "LEFT", -6, 0)
    clearBtn:SetText(L("BTN_MANUAL_PRICE_CLEAR", "Use market"))
    clearBtn:SetScript("OnClick", Clear)
    popup.clearBtn = clearBtn

    local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)
    cancelBtn:SetText(CANCEL or "Cancel")
    cancelBtn:SetScript("OnClick", Close)
end

function ManualPrice.Open(itemID, name, patchTag, needToBuy)
    if not (itemID and Enabled()) then return end
    if not popup then BuildPopup() end
    popup.itemID, popup.patchTag = itemID, patchTag
    popup:SetScale((GAM.db and GAM.db.options and GAM.db.options.uiScale) or 1)
    popup.title:SetText(string.format(L("MANUAL_PRICE_TITLE", "Your price for %s"), name or tostring(itemID)))
    local market = GAM.Pricing.GetMarketPrice(itemID, patchTag, needToBuy)
    popup.market:SetText(string.format(L("MANUAL_PRICE_MARKET", "Market price: %s"),
        market and GAM.Pricing.FormatPrice(market) or "—"))
    local manual = ManualPrice.Get(itemID, patchTag)
    popup.editBox:SetText((manual or market) and MoneyText(manual or market) or "")
    popup.clearBtn:SetEnabled(manual ~= nil)
    popup:Show()
    WindowManager.Present(popup)
    popup.editBox:SetFocus()
    popup.editBox:HighlightText()
end

-- Row OnMouseUp helper: returns true when a right-click opened the price popup.
function ManualPrice.HandleRowClick(row, button)
    if button ~= "RightButton" or not Enabled() then return false end
    local tt = row and row._metricTooltip
    if not (tt and tt.kind == "reagent" and tt.itemID) or tt.crafted then return false end
    local display = row._itemDisplay
    ManualPrice.Open(tt.itemID, tt.name or (display and display.displayText), tt.patchTag, tt.needToBuy)
    return true
end
