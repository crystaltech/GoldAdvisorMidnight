-- GoldAdvisorMidnight/DataBroker.lua
-- Optional LibDataBroker launcher for Bazooka and similar displays.
-- Module: GAM.DataBroker

local ADDON_NAME, GAM = ...
local Broker = {}
GAM.DataBroker = Broker

local initialized = false
local dataObject = nil
local BROKER_ICON = "Interface\\Icons\\inv_misc_coin_01"

local function GetTitle()
    local L = GAM.L or {}
    return L["AH_BTN_TITLE"] or "Gold Advisor"
end

local function GetTooltipBody()
    local L = GAM.L or {}
    return L["BROKER_TIP"] or "Left-click: Toggle window\nRight-click: Settings"
end

local function ToggleMainWindow()
    if GAM.UI and GAM.UI.MainWindowV2 and GAM.UI.MainWindowV2.Toggle then
        GAM.UI.MainWindowV2.Toggle()
    end
end

local function OpenSettings()
    if GAM.Settings and GAM.Settings.OpenPanel then
        GAM.Settings.OpenPanel()
    end
end

local function HandleClick(_, button)
    if button == "RightButton" then
        OpenSettings()
    else
        ToggleMainWindow()
    end
end

local function PopulateTooltip(tooltip)
    if not tooltip then
        return
    end
    local title = GetTitle()
    local body = GetTooltipBody()
    if tooltip.SetText then
        tooltip:SetText(title, 1, 0.82, 0, 1)
    elseif tooltip.AddLine then
        tooltip:AddLine(title)
    end
    if tooltip.AddLine then
        for line in tostring(body):gmatch("[^\n]+") do
            if tooltip.SetText then
                tooltip:AddLine(line, 1, 1, 1, true)
            else
                tooltip:AddLine(line)
            end
        end
    end
end

function Broker.Init()
    if initialized then
        return dataObject
    end
    if not (LibStub and LibStub.GetLibrary) then
        return nil
    end

    local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not ldb then
        return nil
    end

    dataObject = ldb:NewDataObject("GoldAdvisorMidnight", {
        type = "launcher",
        label = GetTitle(),
        text = GetTitle(),
        icon = BROKER_ICON,
        OnClick = HandleClick,
        OnTooltipShow = PopulateTooltip,
        OnEnter = function(frame)
            GameTooltip:SetOwner(frame, "ANCHOR_BOTTOMRIGHT")
            PopulateTooltip(GameTooltip)
            GameTooltip:Show()
        end,
        OnLeave = function()
            GameTooltip:Hide()
        end,
    })

    initialized = true
    return dataObject
end
