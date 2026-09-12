local GAM={C={USE_COMFORTABLE_UI=true},UI={}}
assert(loadfile('UI/MainWindowCommon.lua'))('GoldAdvisorMidnight',GAM)
local common=GAM.UI.MainWindowCommon
local styleButton=common.StyleComfortableButton
local styled={}
common.StyleComfortableButton=function(button)styled[button]=true end
local function button(text,existing)
 return {IsObjectType=function(_,kind)return kind=='Button'end,GetText=function()return text end,_gamComfortBorder=existing}
end
local action,icon,primary=button('Export'),button(nil),button('Buy',true)
local frame={SetBackdropColor=function()end,SetBackdropBorderColor=function()end,
 GetChildren=function()return action,icon,primary end,
 CreateTexture=function()return{SetPoint=function()end,SetHeight=function()end,SetColorTexture=function()end}end}
common.StyleSecondaryWindow(frame)
assert(styled[action] and not styled[icon] and not styled[primary],'secondary skin must preserve icons and primary action styling')
local header=frame._gamComfortHeader
common.StyleSecondaryWindow(frame)
assert(frame._gamComfortHeader==header,'reopening must reuse header texture')
print('PASS: secondary theme preserves icons and existing primary buttons')

-- Disabled actions retain the flat skin and update their label when state
-- changes; this guards the UIPanelButton template transition path.
local function texture()
 local t={}
 function t:ClearAllPoints() end
 function t:SetPoint() end
 function t:SetVertexColor(...) self.color={...} end
 return t
end
local disabledButton={enabled=false, textures={}, scripts={}}
function disabledButton:CreateTexture() return texture() end
function disabledButton:SetNormalTexture() self.textures.normal=texture() end
function disabledButton:SetPushedTexture() self.textures.pushed=texture() end
function disabledButton:SetHighlightTexture() self.textures.highlight=texture() end
function disabledButton:SetDisabledTexture() self.textures.disabled=texture() end
function disabledButton:GetNormalTexture() return self.textures.normal end
function disabledButton:GetPushedTexture() return self.textures.pushed end
function disabledButton:GetHighlightTexture() return self.textures.highlight end
function disabledButton:GetDisabledTexture() return self.textures.disabled end
function disabledButton:GetFontString() return self.font end
function disabledButton:IsEnabled() return self.enabled end
function disabledButton:HookScript(event, callback) self.scripts[event]=callback end
disabledButton.font={SetTextColor=function(self,...) self.color={...} end}
styleButton(disabledButton, false)
assert(disabledButton.textures.disabled and disabledButton.textures.disabled.color,'disabled button must have flat disabled texture')
assert(disabledButton.font.color[1] == 0.58,'disabled button text must remain readable and muted')
disabledButton.enabled=true
disabledButton.scripts.OnEnable(disabledButton)
assert(disabledButton.font.color[1] == 0.90,'enabled transition must restore action text color')

-- WindowManager re-applies opt-in surfaces on every show, while Settings is
-- deliberately excluded from the secondary skin.
local managerGAM={C={USE_COMFORTABLE_UI=true},UI={MainWindowCommon={
 StyleSecondaryWindow=function(frame) frame.skinCalls=(frame.skinCalls or 0)+1 end,
}}}
assert(loadfile('UI/WindowManager.lua'))('GoldAdvisorMidnight',managerGAM)
local manager=managerGAM.UI.WindowManager
local function managed(name)
 local f={name=name,scripts={},children={}}
 function f:GetName() return self.name end
 function f:SetFrameStrata() end
 function f:SetToplevel() end
 function f:Raise() end
 function f:HookScript(event,callback) self.scripts[event]=callback end
 function f:GetChildren() return unpack(self.children) end
 return f
end
local card={_gamComfortSurface=true,SetBackdrop=function()end}
local shown=managed('GoldAdvisorSecondary')
shown.children={card}
manager.Register(shown,'dialog')
shown.scripts.OnShow(shown)
shown.scripts.OnShow(shown)
assert(shown.skinCalls == 2,'secondary chrome must reapply on repeated shows')
local settings=managed('GoldAdvisorMidnight_GAMSettingsWrapper')
manager.Register(settings,'dialog')
settings.scripts.OnShow(settings)
assert(not settings.skinCalls,'Settings wrapper must bypass secondary skin')
print('PASS: disabled button state and Settings-safe secondary lifecycle')
