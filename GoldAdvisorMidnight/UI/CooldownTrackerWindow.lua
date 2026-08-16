-- GoldAdvisorMidnight/UI/CooldownTrackerWindow.lua
-- Crafter-selectable profession cooldown panel.
-- Module: GAM.UI.CooldownTrackerWindow

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local CooldownWindow = {}
GAM.UI.CooldownTrackerWindow = CooldownWindow

local Tracker = GAM.CooldownTracker
local WindowManager = GAM.UI.WindowManager
local WINDOW_W = 650
local WINDOW_H = 430
local ROW_H = 34
local ROW_GAP = 2
local CRAFTER_MENU_ROW_H = 22
local CRAFTER_MENU_MAX_ROWS = 6
local window
local selectedUID
local selectedStrategy
local characterRows = {}
local displayRows = {}
local crafterMenuRows = {}
local Refresh

function CooldownWindow.GetCrafterMenuMetrics(count)
    count = math.max(0, math.floor(tonumber(count) or 0))
    local visibleRows = math.min(count, CRAFTER_MENU_MAX_ROWS)
    return visibleRows, math.max(1, count * CRAFTER_MENU_ROW_H), 4 + (visibleRows * CRAFTER_MENU_ROW_H),
        count > CRAFTER_MENU_MAX_ROWS
end

local function L(key, fallback)
    return (GAM.L and GAM.L[key]) or fallback
end

local function FindSelectedIndex()
    for index, character in ipairs(characterRows) do
        if character.uid == selectedUID then
            return index
        end
    end
    return 1
end

local function SelectCurrentCrafter()
    selectedUID = Tracker.GetCurrentCrafterUID()
end

local function FormatLastChecked(timestamp)
    timestamp = tonumber(timestamp)
    if not timestamp then
        return L("COOLDOWN_NEVER_CHECKED", "Never")
    end
    if type(date) == "function" then
        local ok, text = pcall(date, "%b %d %H:%M", timestamp)
        if ok and text then return text end
    end
    return tostring(timestamp)
end

local function SetButtonEnabled(button, enabled)
    if enabled then
        button:Enable()
        button:SetAlpha(1)
    else
        button:Disable()
        button:SetAlpha(0.45)
    end
end

local function FormatTrackedCount(count)
    if count == 1 then
        return L("COOLDOWN_TRACKED_ONE", "1 tracked craft")
    end
    return string.format(L("COOLDOWN_TRACKED_MANY", "%d tracked crafts"), count)
end

local function SetStatusColor(fontString, status)
    if status == "ready" then
        fontString:SetTextColor(0.25, 1.0, 0.45, 1)
    elseif status == "cooldown" then
        fontString:SetTextColor(1.0, 0.82, 0.0, 1)
    elseif status == "unlearned" or status == "restricted" then
        fontString:SetTextColor(1.0, 0.35, 0.35, 1)
    else
        fontString:SetTextColor(0.72, 0.72, 0.72, 1)
    end
end

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * (ROW_H + ROW_GAP)))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * (ROW_H + ROW_GAP)))
    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    row:SetBackdropColor(index % 2 == 0 and 0.12 or 0.16, index % 2 == 0 and 0.12 or 0.16, index % 2 == 0 and 0.12 or 0.16, 0.96)

    row.nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameFS:SetPoint("LEFT", row, "LEFT", 8, 6)
    row.nameFS:SetWidth(205)
    row.nameFS:SetJustifyH("LEFT")
    row.nameFS:SetWordWrap(false)

    row.professionFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.professionFS:SetPoint("LEFT", row, "LEFT", 8, -8)
    row.professionFS:SetWidth(205)
    row.professionFS:SetJustifyH("LEFT")
    row.professionFS:SetTextColor(0.68, 0.68, 0.68, 1)

    row.statusFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.statusFS:SetPoint("LEFT", row, "LEFT", 224, 0)
    row.statusFS:SetWidth(185)
    row.statusFS:SetJustifyH("LEFT")

    row.checkedFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.checkedFS:SetPoint("LEFT", row, "LEFT", 414, 0)
    row.checkedFS:SetWidth(96)
    row.checkedFS:SetJustifyH("LEFT")
    row.checkedFS:SetTextColor(0.72, 0.72, 0.72, 1)

    row.removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.removeBtn:SetSize(58, 22)
    row.removeBtn:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    row.removeBtn:SetText(L("COOLDOWN_STOP_TRACKING", "Stop"))
    row.removeBtn:SetScript("OnClick", function(self)
        if self.recipeID and selectedUID then
            Tracker.UntrackRecipe(selectedUID, self.recipeID)
        end
    end)
    row:Hide()
    return row
end

local function EnsureDisplayRows(count)
    for index = #displayRows + 1, count do
        displayRows[index] = CreateRow(window.listHost, index)
    end
end

local function RefreshCountdownText()
    if not window or not window:IsShown() then return end
    local now = type(time) == "function" and time() or 0
    for _, row in ipairs(displayRows) do
        if row.data and row:IsShown() then
            local statusText, status = Tracker.GetDisplayStatus(row.data, now)
            row.statusFS:SetText(statusText)
            SetStatusColor(row.statusFS, status)
        end
    end
end

local function RefreshCrafterMenu()
    if not (window and window.crafterMenu and window.crafterMenuHost) then return end
    for index = #crafterMenuRows + 1, #characterRows do
        local row = CreateFrame("Button", nil, window.crafterMenuHost)
        row:SetHeight(CRAFTER_MENU_ROW_H)
        row:SetPoint("TOPLEFT", window.crafterMenuHost, "TOPLEFT", 0, -((index - 1) * CRAFTER_MENU_ROW_H))
        row:SetPoint("TOPRIGHT", window.crafterMenuHost, "TOPRIGHT", 0, -((index - 1) * CRAFTER_MENU_ROW_H))

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 0.82, 0, 0.18)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 7, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            if self.uid then
                selectedUID = self.uid
                window.crafterMenu:Hide()
                Refresh()
            end
        end)
        crafterMenuRows[index] = row
    end

    for index, row in ipairs(crafterMenuRows) do
        local character = characterRows[index]
        if character then
            row.uid = character.uid
            local selected = character.uid == selectedUID
            row.text:SetText((selected and "|cffffd100> |r" or "  ")
                .. character.label
                .. (character.isCurrent and L("COOLDOWN_CURRENT_SUFFIX", " [current]") or ""))
            row:Show()
        else
            row.uid = nil
            row:Hide()
        end
    end

    local visibleRows, hostHeight, menuHeight, overflow = CooldownWindow.GetCrafterMenuMetrics(#characterRows)
    window.crafterMenuHost:SetHeight(hostHeight)
    window.crafterMenu:SetHeight(menuHeight)
    window.crafterMenuScroll:SetVerticalScroll(0)
    window.crafterMenuScroll:SetShown(visibleRows > 0)
    if window.crafterMenuScroll.ScrollBar then
        window.crafterMenuScroll.ScrollBar:SetShown(overflow)
    end
end

Refresh = function()
    if not window then return end
    characterRows = Tracker.GetCharacters()
    if #characterRows == 0 then
        selectedUID = nil
    elseif not selectedUID then
        selectedUID = characterRows[1].uid
    elseif not characterRows[FindSelectedIndex()] or characterRows[FindSelectedIndex()].uid ~= selectedUID then
        selectedUID = characterRows[1].uid
    end

    local selectedIndex = FindSelectedIndex()
    local character = characterRows[selectedIndex]
    if character then
        window.crafterBtn:SetText(string.format("%s%s  v",
            character.label,
            character.isCurrent and L("COOLDOWN_CURRENT_SUFFIX", " [current]") or ""))
        window.crafterNoteFS:SetText(character.isCurrent
            and L("COOLDOWN_CURRENT_NOTE", "Cooldowns can be refreshed on this character now.")
            or string.format(L("COOLDOWN_ALT_NOTE", "Last known state. Log into %s to refresh."), character.name))
    else
        window.crafterBtn:SetText(L("COOLDOWN_NO_CRAFTERS", "No cached crafters"))
        window.crafterNoteFS:SetText("")
    end
    SetButtonEnabled(window.crafterBtn, #characterRows > 0)
    RefreshCrafterMenu()

    local rows, isCurrent = Tracker.GetTrackedRows(selectedUID)
    EnsureDisplayRows(#rows)
    for index, rowFrame in ipairs(displayRows) do
        local data = rows[index]
        rowFrame.data = data
        if data then
            rowFrame.recipeID = data.recipeID
            rowFrame.removeBtn.recipeID = data.recipeID
            rowFrame.nameFS:SetText(data.name or ("Recipe " .. tostring(data.recipeID)))
            rowFrame.professionFS:SetText(data.profession or "")
            rowFrame.checkedFS:SetText(FormatLastChecked(data.lastCheckedAt))
            rowFrame:Show()
        else
            rowFrame.recipeID = nil
            rowFrame.removeBtn.recipeID = nil
            rowFrame:Hide()
        end
    end
    window.listHost:SetHeight(math.max(1, #rows * (ROW_H + ROW_GAP)))
    window.emptyFS:SetShown(#rows == 0)
    window.countFS:SetText(FormatTrackedCount(#rows))
    if window.scroll and window.scroll.ScrollBar then
        local viewportHeight = tonumber(window.scroll:GetHeight()) or 0
        window.scroll.ScrollBar:SetShown(window.listHost:GetHeight() > viewportHeight)
    end

    local selectedCanTrack = selectedStrategy and tonumber(selectedStrategy.recipeID) ~= nil and character ~= nil
    SetButtonEnabled(window.addSelectedBtn, selectedCanTrack)
    window.addSelectedBtn:SetText(selectedStrategy and selectedStrategy.stratName
        and string.format(L("COOLDOWN_ADD_SELECTED_NAMED", "Track: %s"), selectedStrategy.stratName)
        or L("COOLDOWN_ADD_SELECTED", "Track Selected Strategy"))
    SetButtonEnabled(window.trackOpenBtn, Tracker.GetOpenRecipeIdentity() ~= nil)
    SetButtonEnabled(window.refreshBtn, isCurrent)
    window.refreshBtn:SetText(isCurrent
        and L("COOLDOWN_REFRESH_CURRENT", "Refresh Current Crafter")
        or L("COOLDOWN_LOGIN_TO_REFRESH", "Log In To Refresh"))
    RefreshCountdownText()
end

local function EnsureWindow()
    if window then return window end

    window = CreateFrame("Frame", "GAMCooldownTrackerWindow", UIParent, "BackdropTemplate")
    window:SetSize(WINDOW_W, WINDOW_H)
    window:SetPoint("CENTER", UIParent, "CENTER", 50, 20)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetClampedToScreen(true)
    window:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    window:SetBackdropColor(0.025, 0.025, 0.025, 1)
    window:SetBackdropBorderColor(0.7, 0.57, 0.0, 0.72)
    window:Hide()
    WindowManager.Register(window, "dialog")

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", window, "TOP", 0, -14)
    title:SetText(L("COOLDOWN_TITLE", "Craft Cooldowns"))
    title:SetTextColor(1, 0.82, 0, 1)

    local closeBtn = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", window, "TOPRIGHT", -4, -4)

    local crafterLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    crafterLabel:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -50)
    crafterLabel:SetText(L("COOLDOWN_CRAFTER", "Crafter"))
    crafterLabel:SetTextColor(1, 0.82, 0, 1)

    local helpBtn = CreateFrame("Button", nil, window)
    helpBtn:SetSize(18, 18)
    helpBtn:SetPoint("LEFT", crafterLabel, "RIGHT", 5, 0)
    helpBtn:SetNormalTexture("Interface\\Common\\help-i")
    helpBtn:SetPushedTexture("Interface\\Common\\help-i")
    helpBtn:SetHighlightTexture("Interface\\Common\\help-i", "ADD")
    helpBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L("COOLDOWN_HELP_TITLE", "How Cooldown Tracking Works"), 1, 1, 1)
        GameTooltip:AddLine(L("COOLDOWN_HELP_BODY",
            "Tracked recipes are saved separately for each character. The logged-in crafter is refreshed from Blizzard's cooldown and charge data. Offline characters keep their last known state and continue counting down, but you must log into that crafter to verify a reset or newly available charge."),
            1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    helpBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    window.crafterBtn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    window.crafterBtn:SetSize(410, 24)
    window.crafterBtn:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -68)
    window.crafterBtn:SetScript("OnClick", function()
        RefreshCrafterMenu()
        window.crafterMenu:SetShown(not window.crafterMenu:IsShown())
    end)

    window.refreshBtn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    window.refreshBtn:SetSize(190, 24)
    window.refreshBtn:SetPoint("TOPRIGHT", window, "TOPRIGHT", -18, -68)
    window.refreshBtn:SetScript("OnClick", function()
        Tracker.RefreshCurrentCharacter()
        Refresh()
    end)

    window.crafterMenu = CreateFrame("Frame", nil, window, "BackdropTemplate")
    window.crafterMenu:SetPoint("TOPLEFT", window.crafterBtn, "BOTTOMLEFT", 0, -2)
    window.crafterMenu:SetWidth(410)
    window.crafterMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    window.crafterMenu:SetFrameLevel(window:GetFrameLevel() + 30)
    window.crafterMenu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    window.crafterMenu:SetBackdropColor(0.035, 0.035, 0.035, 0.99)
    window.crafterMenu:SetBackdropBorderColor(0.7, 0.57, 0, 0.9)
    window.crafterMenu:Hide()

    window.crafterMenuScroll = CreateFrame("ScrollFrame", nil, window.crafterMenu, "UIPanelScrollFrameTemplate")
    window.crafterMenuScroll:SetPoint("TOPLEFT", window.crafterMenu, "TOPLEFT", 2, -2)
    window.crafterMenuScroll:SetPoint("BOTTOMRIGHT", window.crafterMenu, "BOTTOMRIGHT", -22, 2)
    window.crafterMenuHost = CreateFrame("Frame", nil, window.crafterMenuScroll)
    window.crafterMenuHost:SetPoint("TOPLEFT", window.crafterMenuScroll, "TOPLEFT", 0, 0)
    window.crafterMenuHost:SetWidth(382)
    window.crafterMenuHost:SetHeight(1)
    window.crafterMenuScroll:SetScrollChild(window.crafterMenuHost)
    window.crafterMenuHost:EnableMouseWheel(true)
    window.crafterMenuHost:SetScript("OnMouseWheel", function(_, delta)
        local scroll = window.crafterMenuScroll
        scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange(),
            scroll:GetVerticalScroll() - delta * (CRAFTER_MENU_ROW_H * 3))))
    end)

    window.crafterNoteFS = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.crafterNoteFS:SetPoint("TOPLEFT", window.crafterBtn, "BOTTOMLEFT", 0, -5)
    window.crafterNoteFS:SetPoint("TOPRIGHT", window.refreshBtn, "BOTTOMRIGHT", 0, -5)
    window.crafterNoteFS:SetJustifyH("LEFT")
    window.crafterNoteFS:SetTextColor(0.72, 0.72, 0.72, 1)

    window.addSelectedBtn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    window.addSelectedBtn:SetSize(300, 26)
    window.addSelectedBtn:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -116)
    window.addSelectedBtn:SetScript("OnClick", function()
        if selectedStrategy and selectedUID then
            Tracker.TrackRecipe(selectedUID, selectedStrategy)
            if selectedUID == Tracker.GetCurrentCrafterUID() then
                Tracker.RefreshCurrentCharacter(selectedStrategy.recipeID)
            end
            Refresh()
        end
    end)

    window.trackOpenBtn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    window.trackOpenBtn:SetSize(300, 26)
    window.trackOpenBtn:SetPoint("TOPRIGHT", window, "TOPRIGHT", -18, -116)
    window.trackOpenBtn:SetText(L("COOLDOWN_TRACK_OPEN", "Track Open Profession Recipe"))
    window.trackOpenBtn:SetScript("OnClick", function()
        local ok = Tracker.TrackOpenRecipe()
        if ok then
            SelectCurrentCrafter()
            Refresh()
        else
            print("|cffff8800[GAM]|r " .. L("COOLDOWN_NO_OPEN_RECIPE", "Open a recipe in the profession window first."))
        end
    end)
    window.trackOpenBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L("COOLDOWN_TRACK_OPEN", "Track Open Profession Recipe"), 1, 1, 1)
        GameTooltip:AddLine(L("COOLDOWN_TRACK_OPEN_TIP",
            "Open a recipe in Blizzard's profession window, then add its cooldown to the current crafter."),
            1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    window.trackOpenBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local rule = window:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -152)
    rule:SetPoint("TOPRIGHT", window, "TOPRIGHT", -18, -152)
    rule:SetColorTexture(0.7, 0.57, 0, 0.6)

    local recipeHdr = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recipeHdr:SetPoint("TOPLEFT", window, "TOPLEFT", 26, -162)
    recipeHdr:SetText(L("COOLDOWN_RECIPE", "Recipe"))
    local statusHdr = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusHdr:SetPoint("TOPLEFT", window, "TOPLEFT", 242, -162)
    statusHdr:SetText(L("COOLDOWN_STATUS", "Status"))
    local checkedHdr = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    checkedHdr:SetPoint("TOPLEFT", window, "TOPLEFT", 432, -162)
    checkedHdr:SetText(L("COOLDOWN_LAST_CHECKED", "Last checked"))

    local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -180)
    scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -34, 40)
    window.scroll = scroll

    window.listHost = CreateFrame("Frame", nil, scroll)
    window.listHost:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    window.listHost:SetWidth(WINDOW_W - 70)
    window.listHost:SetHeight(1)
    scroll:SetScrollChild(window.listHost)
    window.listHost:EnableMouseWheel(true)
    window.listHost:SetScript("OnMouseWheel", function(_, delta)
        scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange(),
            scroll:GetVerticalScroll() - delta * (ROW_H * 3))))
    end)

    window.emptyFS = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.emptyFS:SetPoint("CENTER", scroll, "CENTER", 0, 5)
    window.emptyFS:SetWidth(WINDOW_W - 100)
    window.emptyFS:SetJustifyH("CENTER")
    window.emptyFS:SetText(L("COOLDOWN_EMPTY", "No crafts tracked for this character.\nSelect a strategy or open a profession recipe, then add it above."))
    window.emptyFS:SetTextColor(0.72, 0.72, 0.72, 1)

    window.countFS = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.countFS:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 18, 14)
    window.countFS:SetTextColor(0.72, 0.72, 0.72, 1)

    window:SetScript("OnUpdate", function(self, elapsed)
        self._countdownElapsed = (self._countdownElapsed or 0) + elapsed
        if self._countdownElapsed >= 1 then
            self._countdownElapsed = 0
            RefreshCountdownText()
        end
    end)
    window:SetScript("OnShow", Refresh)
    window:HookScript("OnHide", function() window.crafterMenu:Hide() end)
    Tracker.SetChangedCallback(function()
        if window and window:IsShown() then Refresh() end
    end)
    return window
end

function CooldownWindow.Show(strategy)
    selectedStrategy = strategy or selectedStrategy
    local win = EnsureWindow()
    if not selectedUID then SelectCurrentCrafter() end
    Refresh()
    win:Show()
    WindowManager.Present(win)
end

function CooldownWindow.Hide()
    if window then window:Hide() end
end

function CooldownWindow.Toggle(strategy)
    local win = EnsureWindow()
    if win:IsShown() then
        win:Hide()
    else
        CooldownWindow.Show(strategy)
    end
end

function CooldownWindow.Refresh(strategy)
    if strategy ~= nil then selectedStrategy = strategy end
    Refresh()
end
