local GAM={}
assert(loadfile('Data/ProfessionCrafts.lua'))('GoldAdvisorMidnight',GAM)
assert(loadfile('Data/ProfessionCraftsPatch12_1.lua'))('GoldAdvisorMidnight',GAM)
GAM.AppendRuntimeProfessionCrafts()
local rocky
for _,s in ipairs(GAM.RecipesGenerated)do if s.recipeID==1305148 then rocky=s end end
assert(rocky and rocky.outputs[1].baseYieldPerCraft==3,'R0CKY base yield must remain three')
assert(rocky.outputs[1].itemIDs[1]==275676,'R0CKY output identity changed')
for i,qty in ipairs({10,10,20})do assert(rocky.reagents[i].qtyPerCraft==qty,'R0CKY reagent amount changed')end
assert(loadfile('PricingFormula.lua'))('GoldAdvisorMidnight',GAM)
local result=GAM.PricingFormula.CalculateExhaustMaterials({crafts=1,baseYield=3,
 mcPercent=.127,resPercent=.288,mcExtra=1,resExtra=.45,supportsMulticraft=true,supportsResourcefulness=true})
assert(result.expectedOutput>4.5 and result.expectedOutput<4.6,'screenshot bonus-adjusted estimate changed')
local plain=GAM.PricingFormula.CalculateFixedCrafts({crafts=1,baseYield=3})
assert(plain.expectedOutput==3,'unbonused output differs from recipe')
print('PASS: R0CKY base output and bonus-adjusted average remain distinct')

local contract
for _,s in ipairs(GAM.RecipesGenerated)do
    if s.stratName == "Contract: Zul'jarra's Forces" then contract=s end
end
assert(contract and contract.recipeID==1303151, 'contract must use the crafting spell')
assert(contract.outputs[1].baseYieldPerCraft==1, 'contract base yield changed')
assert(#contract.reagents==4, 'contract ingredients lost')
