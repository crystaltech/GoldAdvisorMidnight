-- GoldAdvisorMidnight/CraftPlanBudget.lua
-- Can the player afford the Craft Queue's shopping list while keeping a gold
-- reserve, and if not, which craft counts would fit? Pure over the queue
-- projection; the Shopping tab renders the answer.
-- Module: GAM.CraftPlanBudget

local ADDON_NAME, GAM = ...
local Budget = {}
GAM.CraftPlanBudget = Budget

local function Options()
    return (GAM.GetOptions and GAM:GetOptions()) or (GAM.db and GAM.db.options) or {}
end

function Budget.ClampReserve(value)
    local n = math.floor(tonumber(value) or GAM.C.DEFAULT_GOLD_RESERVE_PCT)
    return math.max(GAM.C.MIN_GOLD_RESERVE_PCT, math.min(GAM.C.MAX_GOLD_RESERVE_PCT, n))
end

function Budget.GetReservePercent()
    return Budget.ClampReserve(Options().goldReservePct)
end

-- Same price the Shopping rows and Quick Buy use: the cheaper of vendor and
-- the Auction House fill for that quantity. Unpriced items are counted so the
-- warning can say the total may be higher.
function Budget.PriceBuys(buys)
    local total, unpriced = 0, 0
    for _, buy in ipairs(buys or {}) do
        local _, unitPrice = GAM.VendorPrices.ResolvePurchase(buy.itemID, buy.quantity)
        if unitPrice and unitPrice > 0 then
            total = total + unitPrice * buy.quantity
        else
            unpriced = unpriced + 1
        end
    end
    return total, unpriced
end

-- Regular plans only: paused plans are not shopped for and optional extras
-- never create purchases.
local function ActivePlans(data)
    local active = {}
    for _, plan in ipairs(data.plans or {}) do
        if not plan.paused and not plan.optionalExtra then active[#active + 1] = plan end
    end
    return active
end

local function CountFunctions(Plan, data)
    local function count(id)
        return Plan.Count(id) + ((data.incoming[id] and data.incoming[id].quantity) or 0)
    end
    return count, Plan.Count
end

local function CostAt(plans, fraction, count, countReady)
    local views = {}
    for i, plan in ipairs(plans) do
        local view = {}
        for key, value in pairs(plan) do view[key] = value end
        local remaining = math.max(0, plan.target - plan.completed)
        view.target = plan.completed + math.floor(remaining * fraction + 1e-9)
        views[i] = view
    end
    local projection = GAM.CraftPlanModel.Project(views, count, countReady)
    return (Budget.PriceBuys(projection.buys)), views
end

-- Largest share of every plan's remaining crafts whose purchases fit the
-- budget. Purchase cost only grows with craft count, so a bisection over
-- the shared fraction converges; plans shrink together, keeping their mix.
local function Suggest(plans, spendable, count, countReady)
    local low, high = 0, 1
    for _ = 1, 24 do
        local mid = (low + high) / 2
        if CostAt(plans, mid, count, countReady) <= spendable then low = mid else high = mid end
    end
    local _, views = CostAt(plans, low, count, countReady)
    local suggestions, any = {}, false
    for i, plan in ipairs(plans) do
        suggestions[i] = { plan = plan, target = views[i].target }
        if views[i].target > plan.completed then any = true end
    end
    return suggestions, any
end

-- Returns nil when there is nothing to buy. Otherwise:
-- { cost, unpriced, money, reserve, spendable, short, suggestions, affordable }
-- `affordable` is false when not even one more craft fits the budget.
function Budget.Check(projection, money)
    local Plan = GAM.CraftPlan
    if not (projection and projection.buys and #projection.buys > 0 and Plan) then return nil end
    money = money or (GetMoney and GetMoney()) or 0
    local reserve = Budget.GetReservePercent()
    local result = {
        money = money,
        reserve = reserve,
        spendable = math.floor(money * (100 - reserve) / 100),
    }
    result.cost, result.unpriced = Budget.PriceBuys(projection.buys)
    result.short = result.cost > result.spendable
    if result.short then
        local data = Plan.GetData()
        local plans = ActivePlans(data)
        if #plans > 0 then
            local count, countReady = CountFunctions(Plan, data)
            local ok, suggestions, any = pcall(Suggest, plans, result.spendable, count, countReady)
            if ok then
                result.suggestions, result.affordable = suggestions, any
            end
        end
    end
    return result
end

-- Applies the suggested craft counts. Plans already at or below their
-- suggestion are left unchanged.
function Budget.Apply(suggestions)
    local changed = 0
    for _, entry in ipairs(suggestions or {}) do
        if entry.target < entry.plan.target and entry.target >= math.max(1, entry.plan.completed) then
            local ok = GAM.CraftPlan.SetTarget(entry.plan, entry.target)
            if ok then changed = changed + 1 end
        end
    end
    return changed
end
