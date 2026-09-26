-- One right-hand workspace for details, the saved queue, and shopping.
local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}
local Workspace = {}
GAM.UI.MainWindowWorkspace = Workspace

function Workspace.Create(panel, deps)
    local self = { buttons = {} }
    local close
    local function Options() return deps.getOptions() end
    function self:GetTab()
        local tab = Options().workspaceTab
        if tab == "strategies" and self.mini then return tab end
        return (tab == "queue" or tab == "shopping") and tab or "details"
    end
    function self:IsOpen() return Options().workspacePaneOpen ~= false end
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetHeight(32)
    bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    local group = CreateFrame("Frame", nil, bar)
    group:SetSize(282, 24); group:SetPoint("TOP", bar, "TOP", 0, -2)
    local rule = bar:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1); rule:SetPoint("BOTTOMLEFT", 4, 0); rule:SetPoint("BOTTOMRIGHT", -4, 0)
    rule:SetColorTexture(0.7, 0.57, 0, 0.4)
    self.detailHost = CreateFrame("Frame", nil, panel)
    self.detailHost:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    self.detailHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    self.planHost = CreateFrame("Frame", nil, panel)
    -- Each tab must have its own bounds. The details host is hidden while
    -- queue/shopping are active; it must not supply their layout rectangle.
    self.planHost:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    self.planHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    self.strategiesHost = CreateFrame("Frame", nil, panel)
    self.strategiesHost:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    self.strategiesHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    GAM.UI.CraftPlanWindow.Embed(self.planHost)
    function self:AttachList(shell, scrollBar, fullParent, title, filters)
        self.listShell, self.scrollBar, self.fullParent = shell, scrollBar, fullParent
        self.listTitle = title
        self.filters = filters
        if title then self.titleFace, self.titleSize, self.titleFlags = title:GetFont() end
        -- Layout may restore Mini before the strategy list has been built.
        -- Apply that restored mode to the newly attached list immediately.
        self.listMode = nil
        if self.mini ~= nil then self:SetMiniMode(self.mini) end
    end
    function self:SetMiniMode(mini)
        self.mini = mini
        if not mini and Options().workspaceTab == "strategies" then Options().workspaceTab = "details" end
        if self.listShell and self.listMode ~= mini then
            self.listMode = mini
            self.listShell:SetParent(mini and self.strategiesHost or self.fullParent)
            -- The existing slider follows the list, including its visibility.
            self.scrollBar:SetParent(self.listShell)
            if mini then
                self.listShell:ClearAllPoints()
                self.listShell:SetAllPoints(self.strategiesHost)
                self.listShell:Show()
            end
        end
        if close then close:SetShown(not mini) end
        if self.listTitle and self.titleFace then
            self.listTitle:SetFont(self.titleFace, mini and 11 or self.titleSize, self.titleFlags)
        end
        if self.filters and self.filters.setMiniFilters and self.listTitle then
            self.filters.setMiniFilters(mini and self.listTitle:GetParent() or nil)
            self.listTitle:SetShown(not mini)
        end
        self:Refresh()
    end
    function self:Refresh()
        local tab = self:GetTab()
        self.detailHost:SetShown(tab == "details")
        self.planHost:SetShown(tab == "queue" or tab == "shopping")
        self.strategiesHost:SetShown(tab == "strategies")
        group:SetWidth(self.mini and 444 or 378)
        local index = 0
        for _, key in ipairs({"strategies", "details", "shopping", "queue", "posting"}) do
            local button = self.buttons[key]
            local shown = key ~= "strategies" or self.mini
            button:SetShown(shown)
            if shown then
                button:SetWidth(self.mini and 84 or 90)
                button:ClearAllPoints()
                button:SetPoint("LEFT", group, "LEFT", index * (self.mini and 90 or 96), 0)
                index = index + 1
            end
        end
        for key, button in pairs(self.buttons) do
            button:SetEnabled(key ~= tab and key ~= "posting")
            button.selected:SetShown(key == tab)
        end
        if tab == "queue" or tab == "shopping" then GAM.UI.CraftPlanWindow.SetEmbeddedTab(tab) end
        if GAM.QuickBuy and GAM.QuickBuy.RefreshPresentation then GAM.QuickBuy.RefreshPresentation() end
    end
    function self:Select(tab)
        if tab == "posting" then return false end
        if not GAM.UI.CraftPlanWindow.FinishEditing() then return false end
        Options().workspaceTab = tab
        Options().workspacePaneOpen = true
        Options().rightPanelCollapsed = false
        self:Refresh()
        deps.onChange()
        return true
    end
    function self:Close()
        if not GAM.UI.CraftPlanWindow.FinishEditing() then return end
        Options().workspacePaneOpen = false
        Options().rightPanelCollapsed = true
        Options().compactMode = false
        deps.onChange()
    end
    for index, spec in ipairs({{"strategies", (GAM.L and GAM.L["WF_STRATS"] or "Strats")}, {"details", (GAM.L and GAM.L["WF_DETAILS"] or "Details")}, {"shopping", (GAM.L and GAM.L["WF_SHOPPING"] or "Shopping")}, {"queue", (GAM.L and GAM.L["WF_QUEUE"] or "Craft Queue")}, {"posting", (GAM.L and GAM.L["WF_POSTING"] or "Posting")}}) do
        local key = spec[1]
        local button = CreateFrame("Button", nil, group, "UIPanelButtonTemplate")
        button:SetSize(90, 24); button:SetPoint("LEFT", group, "LEFT", (index - 1) * 96, 0)
        button:SetText(spec[2]); button:SetScript("OnClick", function() self:Select(key) end)
        local common = GAM.UI.MainWindowCommon
        if common and common.StyleComfortableButton then common.StyleComfortableButton(button, false) end
        local font = button.GetFontString and button:GetFontString()
        if font and deps.applyFontSize then deps.applyFontSize(font, 11) end
        button.selected = button:CreateTexture(nil, "OVERLAY")
        button.selected:SetHeight(2); button.selected:SetPoint("BOTTOMLEFT", 2, 0)
        button.selected:SetPoint("BOTTOMRIGHT", -2, 0); button.selected:SetColorTexture(1, 0.82, 0, 1)
        self.buttons[key] = button
    end
    close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() self:Close() end)
    self:Refresh()
    return self
end
