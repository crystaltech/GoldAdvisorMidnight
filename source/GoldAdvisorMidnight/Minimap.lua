-- GoldAdvisorMidnight/Minimap.lua
-- Pure Blizzard minimap button. No external libs.
-- Module: GAM.Minimap

local ADDON_NAME, GAM = ...
local MM = {}
GAM.Minimap = MM

local btn
local isDragging = false
local dragAngle  = 45  -- degrees, 0 = right, 90 = bottom

local function AngleToRad(deg) return deg * (math.pi / 180) end

local function UpdatePosition()
    local angle = AngleToRad(dragAngle)
    local radius = Minimap:GetWidth() / 2 + 5
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function OnMouseMove()
    if not isDragging then return end
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale  = UIParent:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    local dx, dy = cx - mx, cy - my
    dragAngle = math.atan2(dy, dx) * (180 / math.pi)
    UpdatePosition()
end

function MM.Init()
    local db = GAM.db
    if db.options.minimapAngle then
        dragAngle = db.options.minimapAngle
    end

    btn = CreateFrame("Button", "GoldAdvisorMidnightMinimapBtn", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetClampedToScreen(true)

    -- Background circle
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Icon (gold coin)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER", btn, "CENTER", 1, -1)
    icon:SetSize(18, 18)
    icon:SetTexture("Interface\\Icons\\inv_misc_coin_01")

    -- Highlight
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    btn:SetHighlightTexture(hl)

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(GAM.L["MINIMAP_TIP"], nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Drag
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function()
        isDragging = true
        btn:SetScript("OnUpdate", OnMouseMove)
    end)
    btn:SetScript("OnDragStop", function()
        isDragging = false
        btn:SetScript("OnUpdate", nil)
        db.options.minimapAngle = dragAngle
    end)

    -- Clicks
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if isDragging then return end
        if button == "LeftButton" then
            if GAM.UI and GAM.UI.MainWindow then
                GAM:GetActiveMainWindow().Toggle()
            end
        elseif button == "RightButton" then
            -- Open WoW Interface > AddOns settings tab to the GAM category
            if GAM.Settings and GAM.Settings.OpenPanel then
                GAM.Settings.OpenPanel()
            end
        end
    end)

    UpdatePosition()

    if db.options.minimapHidden then
        btn:Hide()
    else
        btn:Show()
    end
end

function MM.SetShown(show)
    if not btn then return end
    if show then btn:Show() else btn:Hide() end
    GAM.db.options.minimapHidden = not show
end

function MM.Toggle()
    if not btn then return end
    MM.SetShown(not btn:IsShown())
end

GAM._ms = "2026"   -- minimap stamp constant
