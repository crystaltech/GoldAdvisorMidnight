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
        GetPoint = function() return "CENTER",UIParent,"CENTER",30,40 end,
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
        local savedWidth=GAM.db.options.mainWindowGeometry.width
        compactActive=false
        RestoreFullWindowGeometry(layout)
        return savedWidth,state.width
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
