-- GoldAdvisorMidnight/UI/WindowManager.lua
-- Shared popup/window role helper for addon-owned frames.
-- Module: GAM.UI.WindowManager

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local WindowManager = {}
GAM.UI.WindowManager = WindowManager
WindowManager._registeredFrames = WindowManager._registeredFrames or {}

WindowManager.ROLES = {
    main = "MEDIUM",
    dialog = "DIALOG",
    modal = "TOOLTIP",
    debug = "FULLSCREEN_DIALOG",
}

local function GetRoleStrata(role)
    if not role then
        return WindowManager.ROLES.dialog
    end
    return WindowManager.ROLES[role] or role
end

local function ApplyOwnerLevel(frame)
    if not frame or not frame.SetFrameLevel then
        return
    end

    local owner = frame._gamWindowOwner
    local levelOffset = frame._gamWindowLevelOffset or 0
    if not (owner and owner.GetFrameLevel) then
        return
    end

    local ownerLevel = owner:GetFrameLevel() or 0
    local desiredLevel = ownerLevel + levelOffset
    if (frame:GetFrameLevel() or 0) < desiredLevel then
        frame:SetFrameLevel(desiredLevel)
    end
end

local function IsSettingsFrame(frame)
    if not frame then return false end
    if frame._gamIsSettingsFrame then return true end
    local name = frame.GetName and frame:GetName()
    -- The Settings window itself (its wrapper) is themed like every other
    -- window; only the content panels inside it are left alone. Use the
    -- runtime name suffix so this stays valid for Dev and production prefixes.
    return name and (name:find("SettingsPanel", 1, true) or name:find("SettingsCategoryPanel", 1, true)) ~= nil
end

-- Secondary windows may contain a small number of deliberate card/menu
-- surfaces.  Keep their styling in the same pass as the window chrome so a
-- frame that is recreated or shown after a theme refresh cannot retain an old
-- surface color.  Children opt in with _gamComfortSurface; row backgrounds
-- intentionally do not, since they carry their own alternating/status colors.
local function StyleComfortableSurfaces(frame)
    local common = GAM.UI and GAM.UI.MainWindowCommon
    if not (common and common.GetThemeDef and common.SetBackdropColors) then return end
    local theme = common.GetThemeDef()
    local shell = theme and theme.shells and theme.shells.card
    if not shell then return end
    local function visit(parent)
        if not parent or not parent.GetChildren then return end
        for _, child in ipairs({ parent:GetChildren() }) do
            if child._gamComfortSurface and child.SetBackdrop then
                common.SetBackdropColors(child, shell.outerBgColor, shell.outerBorderColor)
            end
            visit(child)
        end
    end
    visit(frame)
end

function WindowManager.ApplyRole(frame, role, opts)
    if not frame then
        return nil
    end

    if role then
        frame._gamWindowRole = role
    end
    if opts then
        if opts.owner ~= nil then
            frame._gamWindowOwner = opts.owner
        end
        if opts.levelOffset ~= nil then
            frame._gamWindowLevelOffset = opts.levelOffset
        end
        if opts.presentOnShow ~= nil then
            frame._gamWindowPresentOnShow = opts.presentOnShow and true or false
        end
    end

    frame:SetFrameStrata(GetRoleStrata(frame._gamWindowRole))
    frame:SetToplevel(true)
    ApplyOwnerLevel(frame)
    return frame
end

function WindowManager.Register(frame, role, opts)
    if not frame then
        return nil
    end

    WindowManager.ApplyRole(frame, role, opts)
    WindowManager._registeredFrames[frame] = true
    if frame._gamWindowManagerRegistered then
        return frame
    end

    frame._gamWindowManagerRegistered = true
    if frame.HookScript then
        frame:HookScript("OnShow", function(self)
            local common = GAM.UI.MainWindowCommon
            if self._gamWindowRole ~= "main" and not IsSettingsFrame(self)
                and common and common.StyleSecondaryWindow then
                common.StyleSecondaryWindow(self)
                StyleComfortableSurfaces(self)
            end
            if self._gamThemeRefresh then
                self._gamThemeRefresh(self)
            end
            if self._gamWindowPresentOnShow ~= false then
                WindowManager.Present(self)
            end
        end)
        frame:HookScript("OnMouseDown", function(self)
            WindowManager.Present(self)
        end)
    end

    return frame
end

function WindowManager.RefreshThemes()
    local common = GAM.UI and GAM.UI.MainWindowCommon
    if not common then return end
    for frame in pairs(WindowManager._registeredFrames) do
        if frame and frame.IsObjectType and frame:IsObjectType("Frame")
                and frame._gamWindowRole ~= "main" and not IsSettingsFrame(frame)
                and common.StyleSecondaryWindow then
            common.StyleSecondaryWindow(frame)
            StyleComfortableSurfaces(frame)
        end
        if frame and frame._gamThemeRefresh then
            frame._gamThemeRefresh(frame)
        end
    end
end

function WindowManager.Present(frame, role, opts)
    if not frame then
        return nil
    end

    WindowManager.ApplyRole(frame, role, opts)
    if frame.Raise then
        frame:Raise()
    end
    ApplyOwnerLevel(frame)
    return frame
end

function WindowManager.GetRoleStrata(role)
    return GetRoleStrata(role)
end
