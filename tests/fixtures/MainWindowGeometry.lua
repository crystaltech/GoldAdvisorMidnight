-- Test-only access to the real private geometry and compact-entry paths.
GAM.TestWindowGeometry = function(saved)
    local state = { width = 1120, height = 720 }
    frame = {
        SetSize = function(_,w,h)
            state.width=w;state.height=h
            if not compactActive and not suppressFrameRelayout then RelayoutPanels(true) end
        end,
        SetWidth = function(_,w)
            state.width=w
            if not compactActive and not suppressFrameRelayout then RelayoutPanels(true) end
        end,
        GetWidth = function() return state.width end,
        GetHeight = function() return state.height end,
        GetPoint = function() return state.point or "CENTER",UIParent,state.relativePoint or "CENTER",state.x or 0,state.y or 0 end,
        ClearAllPoints = function() end,
        SetPoint = function(_,p,_,rp,x,y) state.point=p;state.relativePoint=rp;state.x=x;state.y=y end,
    }
    fullWindowGeometry=nil
    compactActive=false
    GAM.db.options.mainWindowGeometry=saved
    local layout=GetLayoutSpec()
    RestoreFullWindowGeometry(layout)
    return state, function()
        dividerContainer={}
        selectedStratID="fixture"
        GAM.db.options.compactMode=true
        RelayoutPanels()
        local captured=GAM.db.options.mainWindowGeometry
        -- Moving, resizing and hiding Details must never capture full geometry.
        frame:SetSize(510, 660)
        frame:SetPoint("BOTTOMRIGHT",UIParent,"BOTTOMRIGHT",-70,80)
        CaptureFullWindowGeometry()
        assert(GAM.db.options.mainWindowGeometry == captured,
            "detail-only hide/drag overwrote full-window state")
        -- Simulate a reload: only the persisted full-window geometry remains.
        fullWindowGeometry=nil
        compactActive=false
        RestoreFullWindowGeometry(layout)
        return captured,state

    end
end
GAM.TestPresentationResize = function()
    local calls, reflows = 0, 0
    local function Nothing() end
    local function Shell()
        return {Show=Nothing,ClearAllPoints=Nothing,SetPoint=Nothing,SetHeight=Nothing,
            SetWidth=Nothing,SetShown=Nothing}
    end
    leftPanelShell=Shell(); centerPanelShell=Shell(); rightPanelShell=Shell()
    dividerContainer={GetWidth=function()return 1120 end}
    GAM.db.options.compactMode=false
    rpDetail={currentStrat={id="fixture"},root={IsShown=function()return true end},
        reflow=function()reflows=reflows+1 end}
    ShowInlineDetail=function()calls=calls+1 end
    ApplyColumnLayout=Nothing
    MainWindow.RefreshRows=Nothing
    RelayoutPanels(true)
    return calls,reflows
end
