local GAM={C={IS_DEV_BUILD=true},db={options={}},UI={MainWindowCommon={GetThemeDef=function()return{}end}}}
GAM.Importer={GetStratByID=function()return{id="fixture"}end}
UIParent={}
assert(loadfile("UI/StrategyListModel.lua"))("GoldAdvisorMidnightDev",GAM)
assert(loadfile("UI/MainWindowShopping.lua"))("GoldAdvisorMidnightDev",GAM)
local Loader=assert(loadfile("../tests/TestLoader.lua"))()
Loader.LoadModuleWithFixture("UI/MainWindow.lua","../tests/fixtures/MainWindowGeometry.lua","GoldAdvisorMidnightDev",GAM)
for _,saved in ipairs({false,"invalid",{width="oops",height=0/0,point="INVALID",x="oops"}}) do
    local state=GAM.TestWindowGeometry(saved)
    assert(state.width==1120 and state.height==720,"invalid saved geometry did not use defaults")
    assert(state.point=="CENTER","invalid anchor was restored")
end
local state,focus=GAM.TestWindowGeometry({width=1280,height=800,point="TOPLEFT",relativePoint="TOPLEFT",x=20,y=-20})
assert(state.width==1280 and state.height==800,"valid full geometry lost")
local captured,restored=focus()
assert(captured==1280 and restored==1280,"synchronous resize during Detail mode overwrote full-view width")
print("PASS: saved geometry validation and reentrant Detail-mode resize")
local calculations,reflows=GAM.TestPresentationResize()
assert(calculations==0 and reflows==1,"window resizing recalculated pricing instead of reflowing content")
