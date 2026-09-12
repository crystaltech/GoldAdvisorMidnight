local GAM={C={USE_COMFORTABLE_UI=true},db={options={}},UI={},ahOpen=true}
assert(loadfile('UI/MainWindowCommon.lua'))('GoldAdvisorMidnight',GAM)
assert(loadfile('UI/StrategyListModel.lua'))('GoldAdvisorMidnight',GAM)
assert(loadfile('UI/MainWindowShopping.lua'))('GoldAdvisorMidnight',GAM)
local Loader=assert(loadfile('../tests/TestLoader.lua'))()
Loader.LoadModuleWithFixture('UI/MainWindow.lua','../tests/fixtures/ScanShortcuts.lua','GoldAdvisorMidnight',GAM)
local ctrl,alt,shift=false,false,false
IsControlKeyDown=function()return ctrl end
IsAltKeyDown=function()return alt end
IsShiftKeyDown=function()return shift end
local active=false
local queued,starts,stops,resets=nil,0,0,0
GAM.AHScan={IsScanning=function()return active end,StopScan=function()stops=stops+1 end,
 ResetQueue=function()resets=resets+1 end,StartScan=function()starts=starts+1 end,
 QueueAllStratItems=function()queued='all'end,QueueStratListItems=function(list)queued=list end}
local list={{id='visible'}}
GAM.Importer={GetAllStrats=function()return{{id='visible'},{id='hidden-favorite'}}end}
GAM.State={IsFavorite=function(id)return id=='hidden-favorite'end}
GAM.TestSetScanContext(list,{id='selected'})
local scan=GAM.UI.MainWindow.ScanWithModifiers
scan();assert(queued==list and starts==1,'plain click must scan visible list')
ctrl=true;scan();assert(queued=='all','Ctrl must scan all')
ctrl=false;alt=true;scan();assert(#queued==1 and queued[1].id=='hidden-favorite','Alt favorites must ignore profession filter')
alt=false;shift=true;scan();assert(GAM.testSelected=='selected','Shift must scan selection')
scan({id='detached'},'test');assert(GAM.testSelected=='detached','standalone selection override lost')
ctrl=true;alt=true;scan();assert(queued=='all','combined key precedence changed')
active=true;local before=resets;scan();assert(stops==1 and resets==before,'active scan must stop without queue reset')
active=false;ctrl=false;alt=false;GAM.TestSetScanContext(list,nil)
local previous=GAM.testSelected;scan();assert(GAM.testSelected==previous and resets==before,'missing selection must not scan another scope')
print('PASS: real scan dispatch handles four scopes, hidden favorites, modifiers and stop')
