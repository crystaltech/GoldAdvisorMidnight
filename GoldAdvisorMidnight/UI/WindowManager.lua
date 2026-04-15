-- GoldAdvisorMidnight/UI/WindowManager.lua
-- Shared popup/window role helper for addon-owned frames.
-- Module: GAM.UI.WindowManager

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local WindowManager = {}
GAM.UI.WindowManager = WindowManager

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
    if frame._gamWindowManagerRegistered then
        return frame
    end

    frame._gamWindowManagerRegistered = true
    if frame.HookScript then
        frame:HookScript("OnShow", function(self)
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
