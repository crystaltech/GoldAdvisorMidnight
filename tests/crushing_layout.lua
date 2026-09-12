local GAM={UI={}}
local Loader=assert(loadfile('../tests/TestLoader.lua'))()
Loader.LoadModuleWithFixture('UI/CrushingAnalyzerWindow.lua','../tests/fixtures/CrushingLayout.lua','GoldAdvisorMidnightDev',GAM)
local function Region()
    return { ClearAllPoints=function()end,SetPoint=function(self,...)self.point={...}end,
        SetWidth=function(self,w)self.width=w end,Hide=function(self)self.hidden=true end }
end
-- Hidden scaled frames can report fractional dimensions even after SetSize.
-- Layout must still anchor the columns, rather than returning before doing so.
local win={GetWidth=function()return 591.9 end,GetHeight=function()return 277.9 end,
    SetSize=function()end,summaryCard=Region(),summaryRule=Region(),scrollFrame=Region(),listHost=Region()}
for _,key in ipairs({'headerGemFS','headerPriceFS','headerProfitFS','headerROIFS','headerBreakEvenFS'})do win[key]=Region()end
GAM.TestCrushingLayout(win)
assert(win.headerGemFS.point and win.headerBreakEvenFS.point,'fractional size skipped header layout')
assert(win.scrollFrame.point,'list viewport was not positioned')
assert(win.summaryCard.hidden,'unused summary card remained visible')
local last=win.headerBreakEvenFS
assert(last.point[4]+last.width<=592-20,'columns exceed available width')
print('PASS: Crushing headers reflow with fractional scaled dimensions')
