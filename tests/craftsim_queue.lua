-- CraftSim queue adapter: preflight is atomic and preserves execution order.
local GAM = { UI = {}, Importer = {} }
GAM.Importer.GetStratByID = function(id)
    return id == "intermediate" and { recipeID = 101, reagents = {{ itemID = 9, qtyPerCraft = 2 }}} or nil
end
local added = {}
CraftSim = { CRAFTQ = {
    AddRecipe = function(_, o) added[#added + 1] = o end,
    IsRecipeQueueable = function(_, d) return not d.unsupported end,
}}
CraftSimAPI = { GetRecipeData = function(_, o)
    if o.recipeID == 999 then return { unsupported = true } end
    return { recipeID = o.recipeID, SetReagents = function(self, r) self.reagents = r end }
end }
local chunk = assert(loadfile("CraftSimQueue.lua"))
chunk("GoldAdvisorMidnight", GAM)
local Q = assert(GAM.CraftSimQueue)
assert(Q.IsAvailable(), "CraftSim availability detection")
local breakdown = { executionSteps = {
    { producerStratID = "intermediate", craftsExecution = 2, name = "Pigment" },
    { recipeID = 202, craftsExecution = 1, name = "Final" },
}}
local n, err = Q.QueueBreakdown(breakdown, nil, { strategy = { recipeID = 202 } , crafterData = { name="A", realm="R" } })
assert(n == 2 and not err and #added == 2, "queue should write all validated steps")
assert(added[1].recipeData.recipeID == 101 and added[1].amount == 2, "order/quantity")
local beforeDuplicate = #added
n, err = Q.QueueBreakdown(breakdown, nil, { strategy = { recipeID = 202 } , crafterData = { name="A", realm="R" } })
assert(n == 0 and err == "plan already queued" and #added == beforeDuplicate,
    "repeated clicks must not duplicate a queued plan")
added = {}
local bad = { executionSteps = {
    { recipeID = 202, craftsExecution = 1 }, { recipeID = 999, craftsExecution = 1 },
}}
n, err = Q.QueueBreakdown(bad, nil, { crafterData = { name="A", realm="R" } })
assert(n == 0 and err and #added == 0, "unsupported recipe must fail before any queue write")
local ambiguous = { executionSteps = {
    { recipeID = 202, craftsExecution = 1,
      reagents = {{ itemIDs = { 11, 12 }, quantity = 1 }} },
}}
n, err = Q.BuildQueueEntries(ambiguous, nil, { strategy = { recipeID = 202 } })
assert(n == nil and err and err:find("exact rank allocation", 1, true),
    "ambiguous reagent pools must not silently choose a rank")
print("PASS: CraftSim queue preflight and atomic writes")
