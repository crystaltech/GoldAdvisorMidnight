local GAM={UI={},RuntimeName=function(name)return name.."Dev"end}
local Loader=assert(loadfile("../tests/TestLoader.lua"))()
Loader.LoadModuleWithFixture("Settings.lua","../tests/fixtures/SettingsScale.lua","GoldAdvisorMidnight",GAM)
local applied={}
for _,name in ipairs({"GoldAdvisorMidnightStrategyDetail","GAMQuickBuyWindow","GAMCooldownTrackerWindow","GAMVIBreakdownWindow","GAMCrushingAnalyzer"}) do
    local key=name
    _G[name.."Dev"]={SetScale=function(_,value)applied[key]=value end}
end
-- MainWindow is deliberately unopened; other windows must still receive scale.
GAM.TestApplyScale(0.85)
for _,name in ipairs({"GoldAdvisorMidnightStrategyDetail","GAMQuickBuyWindow","GAMCooldownTrackerWindow","GAMVIBreakdownWindow","GAMCrushingAnalyzer"}) do
    assert(applied[name]==0.85,"scale skipped "..name)
end
print("PASS: UI scale reaches open windows even when the main frame is unopened")
