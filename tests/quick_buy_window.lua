-- Real Quick Buy builder: hiding a newly created frame fires OnHide in WoW.
local frame
local function New(name)
 local f={name=name,shown=true,scripts={}}
 local methods={}
 function methods:SetScript(k,v)self.scripts[k]=v end
 function methods:Hide()local was=self.shown;self.shown=false;if was and self.scripts.OnHide then self.scripts.OnHide(self)end end
 function methods:Show()self.shown=true end
 function methods:IsShown()return self.shown end
 function methods:GetName()return self.name end
 function methods:CreateFontString()return New()end
 function methods:CreateTexture()return New()end
 return setmetatable(f,{__index=function(_,k)if k:sub(1,1)=="_" then return nil end;return methods[k] or function()end end})
end
function CreateFrame(_,name) local f=New(name);if name=="GAMQuickBuyWindow" then frame=f end;return f end
UIParent=New();UISpecialFrames={}
local GAM={RuntimeName=function(n)return n end,db={options={}}}
assert(loadfile('QuickBuy.lua'))('GoldAdvisorMidnight',GAM)
GAM.QuickBuy.Init()
assert(frame and not frame:IsShown(),'Quick Buy must initialize hidden')
GAM.QuickBuy.Show()
frame:Hide()
assert(GAM.quickBuyState.phase=='idle','user hide must still reset Quick Buy')
print('PASS: Quick Buy initial hide precedes callbacks and normal close resets')
