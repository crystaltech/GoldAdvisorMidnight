-- Focused frame shim for the actual detail builder, not a mock pricing engine.
local methods = {}
local function New(parent)
    return setmetatable({parent=parent, points={}, scripts={}, shown=true, text=""}, {__index=methods})
end
function methods:SetPoint(point, relative, relativePoint, x, y)
    self.points[#self.points+1]={point,relative,relativePoint,x or 0,y or 0}
end
function methods:ClearAllPoints() self.points={} end
function methods:SetAllPoints(parent) self.all=parent end
function methods:SetParent(parent) self.parent=parent end
function methods:SetWidth(w) assert(w>=0 and w==w,"invalid width"); self.width=w end
function methods:SetHeight(h) assert(h>=0 and h==h,"invalid height"); self.height=h end
function methods:SetSize(w,h) self:SetWidth(w);self:SetHeight(h) end
function methods:GetWidth()
    if self.all then return self.all:GetWidth() end
    if self.width then return self.width end
    if #self.points>=2 then
        local a,b=self.points[1],self.points[2]
        if a[2]==b[2] then return a[2]:GetWidth()+b[4]-a[4] end
    end
    return self.parent and self.parent:GetWidth() or 500
end
function methods:GetHeight()
    if self.all then return self.all:GetHeight() end
    if self.height then return self.height end
    if #self.points>=2 then
        local a,b=self.points[1],self.points[2]
        if a[2]==b[2] then return a[2]:GetHeight()+a[5]-b[5] end
    end
    return self.parent and self.parent:GetHeight() or 600
end
function methods:SetText(s) self.text=tostring(s or "") end
function methods:GetText() return self.text end
function methods:GetStringHeight() return 14*math.max(1, math.ceil(#self.text*7/math.max(1,self:GetWidth()))) end
function methods:IsShown() return self.shown end
function methods:SetShown(v) self.shown=not not v end
function methods:Hide() self.shown=false end
function methods:Show() self.shown=true end
function methods:SetScript(k,f) self.scripts[k]=f end
function methods:HookScript(k,f) local prev=self.scripts[k]; self.scripts[k]=function(...) if prev then prev(...) end; f(...) end end
function methods:CreateFontString() return New(self) end
function methods:CreateTexture() return New(self) end
function methods:SetScrollChild(child) self.child=child end
function methods:SetVerticalScroll(n) self.scroll=n end
function methods:GetVerticalScroll() return self.scroll or 0 end
function methods:GetVerticalScrollRange() return math.max(0,(self.child and self.child:GetHeight() or 0)-self:GetHeight()) end
function methods:HasFocus() return false end
for _,name in ipairs({"SetClipsChildren","SetTextColor","SetWordWrap","SetJustifyH","SetJustifyV",
    "SetColorTexture","SetTexCoord","SetTexture","SetAutoFocus","SetNumeric","EnableMouseWheel",
    "SetHyperlinksEnabled","SetAlpha","Enable","Disable","ClearFocus"}) do methods[name]=function() end end
function CreateFrame(_,_,parent,template)
    local f=New(parent)
    if template=="UIPanelScrollFrameTemplate" then f.ScrollBar=New(f) end
    return f
end
local GAM={UI={VIBreakdownWindow={Show=function()end,Hide=function()end},CrushingAnalyzerWindow={Hide=function()end}},C={USE_COMFORTABLE_UI=true,DEFAULT_PATCH="midnight_1"}}
assert(loadfile("UI/MainWindowCommon.lua"))("GoldAdvisorMidnight",GAM)
GAM.UI.MainWindowCommon.StyleComfortableButton=function()end
assert(loadfile("UI/MainWindowDetail.lua"))("GoldAdvisorMidnight",GAM)
local panel=New();panel:SetSize(500,600)
local detail={}
GAM.UI.MainWindowDetail.Build({panel=panel,rpDetail=detail,themeRefs={reagentRowBgs={},outputRowBgs={}},layoutMode="comfortable",flattenSections=true,rowHeight=28,rightPanelWidth=500})
detail.nameFS:SetText("Example strategy")
detail.profFS:SetText("Cooking - current crafter")
detail.notesFS:Hide()
detail.reagentListHost:SetHeight(28*7)
detail.outputListHost:SetHeight(28)
detail.reflow()
local collapsed=detail.content:GetHeight()
assert(not detail.metStatsFS:IsShown(),"Info defaults expanded")
detail.btnInfo.scripts.OnClick()
assert(detail.metStatsFS:IsShown() and detail.content:GetHeight()>collapsed,"Info did not reclaim/release space")
detail.btnInfo.scripts.OnClick()
assert(detail.content:GetHeight()==collapsed,"Info left a permanent blank area")
local oldNameWidth=detail.reagentRows[1].nameFS:GetWidth()
panel:SetSize(680,650);detail.reflow()
assert(detail.reagentRows[1].nameFS:GetWidth()>oldNameWidth,"extra width did not reach item names")
panel:SetSize(440,360);detail.reflow()
assert(detail.viewport:GetVerticalScrollRange()>0 and detail.viewport.ScrollBar:IsShown(),"short window clips content instead of scrolling")
print("PASS: actual Comfortable detail builder reflows disclosure, tables and short windows")

local first = detail.reagentRows[1]
detail.ensureRows(30, 15)
assert(#detail.reagentRows==30 and #detail.outputRows==15, "long VI plans hit a fixed detail-row cap")
detail.ensureRows(4, 2)
assert(detail.reagentRows[1]==first and #detail.reagentRows==30, "detail rows were rebuilt instead of reused")

detail.reagentListHost.scripts.OnMouseWheel(detail.reagentListHost,-1)
assert(detail.viewport:GetVerticalScroll()>0,"wheel over materials did not scroll the detail content")
