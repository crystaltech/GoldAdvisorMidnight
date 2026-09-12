-- Offline regression checks for vertical-integration producer boundaries.

local ADDON_NAME = "GoldAdvisorMidnight"
local GAM = {}

local function LoadModule(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk(ADDON_NAME, GAM)
end

LoadModule("PricingDerivation.lua")

local canIntegrate = assert(
    GAM.PricingDerivation.CanVerticallyIntegrate,
    "vertical-integration profession policy unavailable")

assert(canIntegrate(
    { profession = "Alchemy" },
    { profession = " alchemy " }),
    "same-profession producer should be eligible")

assert(not canIntegrate(
    { profession = "Alchemy" },
    { profession = "Jewelcrafting" }),
    "cross-profession producer must not be eligible")

assert(not canIntegrate(
    { profession = "Alchemy" },
    {}),
    "producer without profession must not be eligible")

assert(GAM.PricingDerivation.GetDisplayPlanMode(false) == "direct",
    "VI-off detail should use direct recipe inputs")
assert(GAM.PricingDerivation.GetDisplayPlanMode(true) == "execution",
    "VI-on detail should use the expanded execution plan")
assert(not GAM.PricingDerivation.ShouldExpandDisplayIntermediate("direct", { source = "producer" }),
    "direct display mode expanded an intermediate")
assert(GAM.PricingDerivation.ShouldExpandDisplayIntermediate("execution", { source = "producer" }),
    "VI execution mode did not expand a selected producer")
assert(not GAM.PricingDerivation.ShouldExpandDisplayIntermediate("execution", { source = "direct" }),
    "VI execution mode disagreed with a direct-buy economic choice")

print("PASS: vertical integration profession and display-plan policies")
