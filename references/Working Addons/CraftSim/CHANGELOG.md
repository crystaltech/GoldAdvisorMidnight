# CraftSim

## [midnight_beta_3](https://github.com/derfloh205/CraftSim/tree/midnight_beta_3) (2026-02-26)
[Full Changelog](https://github.com/derfloh205/CraftSim/compare/midnight_beta_2...midnight_beta_3) [Previous Releases](https://github.com/derfloh205/CraftSim/releases)

- Update/966 craft buffs data (#967)  
    * Add Midnight expansion support for Shattering Essence buff  
    * Add Haranir Phial of Ingenuity buffs and update Shattering Essence for Midnight  
- use UNIT\_AURA to keep a table of active buffs (#923)  
    * use UNIT\_AURA to keep a table of active buffs  
    * add combat check  
    * remove check if function exists (it does!)  
    * clean up logic  
    * also add updated auras for existing auras on init  
    * small structural changes  
    * moved local table to craft buffs space  
    * full buff iteration on login/reload as isFullUpdate has nil values  
    ---------  
    Co-authored-by: Genju <derfloh205@gmail.com>  
- Process moxie in CraftQueue (#964)  
    * add moxie currency ids  
    * only process reward if itemlink exists  
    * check if currency and process moxie, early out if no item link  
    * return early on currencies  
    * only try to render item if it exists  
    * render currency as reward  