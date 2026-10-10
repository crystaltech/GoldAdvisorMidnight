-- GoldAdvisorMidnight/UI/HistoryWindow.lua
-- The History workspace tab: what made money, what did not, what to do next.
-- Built only from the recorded crafting history. The one action, Queue on a
-- Craft more suggestion, adds a plan to the Craft Queue when clicked.
local ADDON_NAME, GAM = ...
local function L(key, fallback, ...)
    local value = (GAM.L and GAM.L[key]) or fallback
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end
GAM.UI = GAM.UI or {}
local UI = {}
GAM.UI.HistoryWindow = UI

local host, scroll, content, footer, emptyText, moreLink
local stats_ui = {}       -- the five totals: label and value font strings
local themed = {}         -- font strings recolored from the theme on each refresh
local suggestionRows, listRows = {}, {}
local modeButton, periodButton, filterButton
local mode, period, filter = "items", 7, nil
local PERIODS = { 7, 30, 0 }
-- "suggestions" lists every suggestion; the others show the top three above
-- their list.
local MODES = { "items", "batches", "log", "suggestions" }
local FILTERS = { false, "craft", "buy", "post", "sold", "expired", "cancel" }

local VERDICT = {
    more = { "|cff83e896", "HT_V_MORE", "Craft more" },
    keep = { "|cffdddddd", "HT_V_KEEP", "Keep going" },
    loss = { "|cffff8a7a", "HT_V_LOSS", "Losing money" },
    slow = { "|cffffc46b", "HT_V_SLOW", "Post less" },
    stuck = { "|cffffc46b", "HT_V_STUCK", "Unsold stock" },
    few = { "|cff999999", "HT_V_FEW", "Not enough data" },
}
local EVENT = {
    craft = { "HT_E_CRAFT", "Crafted" }, buy = { "HT_E_BUY", "Bought" }, post = { "HT_E_POST", "Posted" },
    sold = { "HT_E_SOLD", "Sold" }, expired = { "HT_E_EXPIRED", "Expired" }, cancel = { "HT_E_CANCEL", "Cancelled" },
}
-- Sign of the gold for each event: money in (+) or out (-).
local EVENT_SIGN = { buy = -1, post = -1, sold = 1, expired = -1, cancel = -1 }

local Common = GAM.UI.MainWindowCommon
local function Money(copper, signed, short)
    if not copper then return "—" end
    if signed then return Common.SignedMoney(copper, short) end
    return (copper < 0 and "-" or "") .. GAM.Pricing.FormatPrice(math.abs(copper))
end
local function Themed(fs, role) themed[#themed + 1] = { fs, role }; return fs end
local function ApplyThemeColors()
    for _, entry in ipairs(themed) do entry[1]:SetTextColor(unpack(Common.ThemeColor(entry[2]))) end
end
-- Ranked items share a name; Blizzard's rank icon tells them apart.
local function RankIcon(id)
    local api = C_TradeSkillUI
    for _, fn in ipairs({ api and api.GetItemReagentQualityByItemInfo, api and api.GetItemCraftedQualityByItemInfo }) do
        if type(fn) == "function" then
            local ok, rank = pcall(fn, id)
            rank = ok and tonumber(rank) or nil
            if rank and rank > 0 then return " |A:Professions-ChatIcon-Quality-12-Tier" .. rank .. ":14:14|a" end
        end
    end
    local known = GAM.ItemRanks and GAM.ItemRanks[tonumber(id)]
    return known and (" |A:Professions-ChatIcon-Quality-12-Tier" .. known .. ":14:14|a") or ""
end
local function ItemName(id)
    return ((C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("item:" .. tostring(id))) .. RankIcon(id)
end
local function Verdict(key) local v = VERDICT[key]; return v[1] .. L(v[2], v[3]) .. "|r" end
local function Percent(value) return value and string.format("%d%%", math.floor(value * 100 + 0.5)) or "—" end
-- Today: the time. This week: the weekday and time. Older: the date.
local function When(t)
    local now = time and time() or 0
    if not date then return "" end
    if date("%Y%m%d", t) == date("%Y%m%d", now) then return date("%H:%M", t) end
    if now - t < 6 * 86400 then return date("%a %H:%M", t) end
    return date("%d %b", t)
end
local function Text(parent, size, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    local face, _, flags = fs:GetFont()
    if face then fs:SetFont(face, size or 11, flags) end
    fs:SetJustifyH("LEFT")
    return fs
end
local function Hover(frame, show)
    frame:SetScript("OnEnter", show)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local function Tip(owner, title, lines, note)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 0.82, 0, 1, true)
    for _, line in ipairs(lines or {}) do GameTooltip:AddDoubleLine(line[1], line[2], 0.8, 0.8, 0.85, 1, 1, 1) end
    if note then GameTooltip:AddLine(note, 0.85, 0.85, 0.85, true) end
    GameTooltip:Show()
end

-- ===== Data =====

local function Data()
    local history, analysis = GAM.CraftHistory, GAM.CraftHistoryAnalysis
    local since = period > 0 and ((GetServerTime and GetServerTime() or time()) - period * 86400) or 0
    local events = history.Events({ since = since })
    local breakEvens, opts = {}, GAM.Posting.Options()
    local plan = GAM.CraftPlan
    -- Finished plans in History keep their break-even (oldest first, newest wins).
    for _, record in ipairs(history.ArchivedPlans and history.ArchivedPlans() or {}) do
        for itemID, value in pairs(record.breakEven or {}) do breakEvens[itemID] = value end
    end
    if plan and plan.Project and plan.OutputSummary then
        local ok, projection = pcall(plan.Project)
        if ok then
            for _, row in ipairs(plan.OutputSummary(projection)) do
                breakEvens[row.itemID] = row.breakEven and math.ceil(row.breakEven)
            end
        end
    end
    -- What each sale cost: its own batch (oldest first), as in the batches view.
    local saleCosts = {}
    local okBatches, _, costs = pcall(analysis.Batches, UI.BatchRecords(), history.Events(), history.PlanPurchases,
        GAM.Posting.MarketPrice, opts.ahCut,
        function(record) return (history.MaterialCost(record.consumed, record.id, GAM.Posting.MarketPrice)) end)
    if okBatches and costs then saleCosts = costs end
    -- Unsold stock: bags, banks, listed and returned items in the mailbox.
    local stock, memo = GAM.Stock, {}
    local itemStats = analysis.ItemStats(events,
        function(id) return (GAM.Posting.YourCost(id, breakEvens[id], opts, memo)) end,
        function(id) return stock.Owned(id).total end,
        function(id) return stock.Listed(id) end,
        function(event) return saleCosts[event.id or event] end)
    return events, itemStats, opts
end

-- Every queue plan as a batch: finished ones from History, current ones live.
function UI.BatchRecords()
    local list = {}
    for _, record in ipairs(GAM.CraftHistory.ArchivedPlans and GAM.CraftHistory.ArchivedPlans() or {}) do
        list[#list + 1] = record
    end
    local plan = GAM.CraftPlan
    for _, saved in ipairs(plan and plan.GetData and plan.GetData().plans or {}) do
        if plan.BatchRecord then list[#list + 1] = plan.BatchRecord(saved) end
    end
    return list
end

-- The newest batch that made the item with a known strategy and craft count.
local function LatestBatchFor(itemID, records)
    local best, bestT
    for _, record in ipairs(records) do
        if record.strategyID and (record.finalOutputs or {})[itemID] and (record.completed or 0) > 0 then
            local t = record.createdAt or record.archivedAt or 0
            if not best or t >= bestT then best, bestT = record, t end
        end
    end
    return best
end

-- How many crafts would bring stock up to a week of your own sales, using
-- the real yield of your latest batch. Never more days ahead than the sales
-- the rate is based on (one strong day is not a week), and never more than
-- the gold on hand can buy. nil when there is no batch to repeat.
local GOLD_SHARE = 0.8   -- at most this share of your gold on one suggestion
local function Restock(itemID, records)
    local record, stock = LatestBatchFor(itemID, records), GAM.Stock
    if not (record and stock) then return nil end
    local perDay, span = stock.SalesPerDay(itemID)
    local owned = stock.Owned(itemID).total
    local yield = record.finalOutputs[itemID] / record.completed
    -- Crafts of this strategy already in the queue count as stock on the way.
    local queued = 0
    for _, plan in ipairs(GAM.CraftPlan and GAM.CraftPlan.GetData and GAM.CraftPlan.GetData().plans or {}) do
        if plan.strategyID == record.strategyID then
            queued = queued + math.floor(math.max(0, (plan.target or 0) - (plan.completed or 0)) * yield)
        end
    end
    local days = math.min(stock.WELL_STOCKED_DAYS, math.max(1, math.floor(span or 1)))
    local out = { record = record, perDay = perDay, owned = owned, queued = queued, days = days,
        crafts = GAM.CraftHistoryAnalysis.RestockCrafts(perDay, owned + queued, yield, days) }
    if out.crafts <= 0 or not (GAM.Importer and GAM.PricingFacade) then return out end
    local strat = GAM.Importer.GetStratByID(record.strategyID)
    local ok, result = pcall(GAM.PricingFacade.CalculateCurrent, strat, record.patchTag or (strat and strat.patchTag))
    result = ok and type(result) == "table" and result or nil
    local minimum = GAM.CraftPlan and GAM.CraftPlan.MinProfit and GAM.CraftPlan.MinProfit()
    local perCraft = result and tonumber(result.profitPerCraft)
    -- History says it sold well, but today's prices decide whether to make more.
    if perCraft and perCraft < 0 then
        out.blocked = L("HT_LOSS_NOW", "Not suggested now: at current prices each craft loses %s. Scan again later.",
            Money(math.floor(-perCraft)))
        return out
    end
    if minimum and perCraft and perCraft < minimum then
        out.blocked = L("HT_BELOW_MIN_PROFIT", "Not suggested: profit per craft is %s, below your minimum %s.",
            Money(math.floor(perCraft)), Money(minimum))
        return out
    end
    -- What one craft's materials cost if all of them are bought.
    local cost = result and tonumber(result.requiredCostFull)
    local crafts = result and tonumber(result.crafts)
    if cost and crafts and cost > 0 and crafts > 0 and GetMoney then
        -- Gold the queue's other materials still need is already spoken for.
        local okCommitted, committed = pcall(GAM.CraftPlan.OpenBuysCost)
        committed = okCommitted and tonumber(committed) or 0
        local spare = math.max(0, (GetMoney() or 0) * GOLD_SHARE - committed)
        local affordable = math.floor(spare / (cost / crafts))
        if affordable < out.crafts then out.crafts, out.goldLimited = math.max(0, affordable), true end
    end
    return out
end

-- ===== Rows =====

local function SuggestionRow(index)
    if suggestionRows[index] then return suggestionRows[index] end
    local row = CreateFrame("Frame", nil, content)
    row.bar = row:CreateTexture(nil, "ARTWORK"); row.bar:SetWidth(3)
    row.bar:SetPoint("TOPLEFT"); row.bar:SetPoint("BOTTOMLEFT")
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
    -- One action at most: queue the suggested crafts.
    row.action = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.action:SetSize(118, 20); row.action:SetPoint("TOPRIGHT", -6, -4)
    local common = GAM.UI.MainWindowCommon
    if common and common.StyleComfortableButton then common.StyleComfortableButton(row.action, true) end
    row.action:SetScript("OnClick", function(self)
        local r = self.restock
        if not (r and GAM.CraftPlan and GAM.CraftPlan.QueueMore) then return end
        local ok, err = GAM.CraftPlan.QueueMore(r.record.strategyID, r.record.patchTag, r.crafts)
        print("|cffffd100[GAM]|r " .. tostring(ok and GAM.CraftPlan.message or err))
        UI.Refresh()
    end)
    row.action:SetScript("OnEnter", function(self)
        local r = self.restock
        if not r then return end
        Tip(self, L("HT_QUEUE_TITLE", "Add to the Craft Queue"), {
            { L("HT_SELLS_PER_DAY", "You sell per day"), string.format("%.1f", r.perDay or 0) },
            { L("HT_YOU_HAVE", "You have"), r.owned },
            { L("HT_IN_QUEUE", "Queued to make"), r.queued or 0 },
            { L("HT_CRAFTS", "Crafts"), r.crafts },
        }, L("HT_QUEUE_NOTE", "Enough crafts for about %d days of your own sales (never more days than you have sales for), using your last batch's real yield. Crafts already queued count as stock, and it buys no more than 80%% of your gold after what the queue still needs. You can change the count in the Craft Queue.", r.days))
    end)
    row.action:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.title = Themed(Text(row, 12, "GameFontNormal"), "accent"); row.title:SetPoint("TOPLEFT", 10, -5)
    row.body = Themed(Text(row, 11), "body"); row.body:SetWordWrap(true)
    row.body:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3); row.body:SetPoint("RIGHT", -6, 0)
    row:EnableMouse(true)
    Hover(row, function(self)
        local s = self.stats
        Tip(self, L("HT_WHY", "Why this suggestion"), {
            { L("HT_CRAFTED", "Crafted"), s.crafted }, { L("HT_POSTED", "Posted"), s.posted },
            { L("HT_SOLD", "Sold"), s.sold }, { L("HT_EXPIRED", "Expired"), s.expired },
            { L("HT_REALIZED", "Realized profit"), s.realized and Money(s.realized, true) or "—" },
        }, L("HT_WHY_NOTE", "Based only on this character's recorded history for the selected period."))
    end)
    suggestionRows[index] = row
    return row
end

local function ListRow(index)
    if listRows[index] then return listRows[index] end
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(22)
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
    row.band = index % 2 == 1
    row.a = Themed(Text(row), "body"); row.a:SetPoint("LEFT", 4, 0); row.a:SetWordWrap(false)
    row.d = Themed(Text(row), "body"); row.d:SetPoint("RIGHT", -4, 0); row.d:SetJustifyH("RIGHT"); row.d:SetWidth(104)
    row.c = Themed(Text(row), "body"); row.c:SetPoint("RIGHT", row.d, "LEFT", -6, 0); row.c:SetJustifyH("RIGHT"); row.c:SetWidth(96)
    row.b = Themed(Text(row), "body"); row.b:SetPoint("RIGHT", row.c, "LEFT", -6, 0); row.b:SetJustifyH("RIGHT"); row.b:SetWidth(116)   -- fits "1163/1429 81%"
    -- One line per row: long values are shortened, never wrapped.
    row.b:SetWordWrap(false); row.c:SetWordWrap(false); row.d:SetWordWrap(false)
    row.a:SetPoint("RIGHT", row.b, "LEFT", -6, 0)
    row:EnableMouse(true)
    Hover(row, function(self) if self.tip then self.tip(self) end end)
    listRows[index] = row
    return row
end

local function Place(frame, y, height)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    frame:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    frame:SetHeight(height)
    return y + height
end

-- ===== Refresh =====

function UI.Refresh()
    -- Visible, not just shown: the tab stays shown inside a closed window.
    if not host or not host:IsVisible() then return end
    if not (GAM.CraftHistory and GAM.CraftHistoryAnalysis) then return end
    local events, stats, opts = Data()
    local analysis = GAM.CraftHistoryAnalysis
    local sum = analysis.Totals(events, stats)
    ApplyThemeColors()
    local band = Common.ThemeColor("band")
    local values = { Money(-sum.spent, true), Money(sum.sold, true), Money(-sum.lost, true),
        Money(sum.realized, true), Money(sum.stock) }
    for index, stat in ipairs(stats_ui) do stat.value:SetText(values[index]) end
    stats_ui[1].note = L("HT_SPENT_NOTE", "Materials bought for your Craft Queue plans. Other purchases in this period (work orders, shopping lists not for a queued plan): %s.",
        Money(-sum.other, true))
    content:SetWidth(math.max(1, scroll:GetWidth()))
    local y = 0

    -- Suggestions, largest gold at stake first: every one in the Suggestions
    -- view, the top three above the other views.
    local allSuggestions = analysis.Suggestions(stats, opts.marginWarn, math.huge)
    local suggestions = allSuggestions
    if mode ~= "suggestions" then
        suggestions = {}
        for index = 1, math.min(analysis.MAX_SUGGESTIONS, #allSuggestions) do suggestions[index] = allSuggestions[index] end
    end
    local records = UI.BatchRecords()
    local colors = { more = { 0.51, 0.91, 0.59 }, loss = { 1, 0.54, 0.48 }, stuck = { 1, 0.77, 0.42 }, slow = { 1, 0.77, 0.42 } }
    for index, suggestion in ipairs(suggestions) do
        local row, s = SuggestionRow(index), suggestion.stats
        row.stats = s
        row:Show()
        local name = ItemName(s.itemID)
        local title, body, restock
        if suggestion.verdict == "more" then
            title = L("HT_S_MORE", "Craft more %s", name)
            body = L("HT_S_MORE_BODY", "Sold %d of %d that finished (%s) at %s over what you paid, for %s. %d left.",
                s.sold, s.resolved, Percent(s.sellThrough), Percent(s.margin), Money(s.realized, true), s.stock)
            restock = Restock(s.itemID, records)
            if restock and restock.blocked then body = body .. " " .. restock.blocked
            elseif restock and restock.crafts > 0 and restock.goldLimited then
                body = body .. " " .. L("HT_RESTOCK_GOLD", "You sell about %.1f a day; %d crafts is what 80%% of your gold buys after the queue's other materials.",
                    restock.perDay, restock.crafts)
            elseif restock and restock.crafts > 0 then
                body = body .. " " .. L("HT_RESTOCK", "You sell about %.1f a day: %d crafts would cover about %d days.",
                    restock.perDay, restock.crafts, restock.days)
            elseif restock and restock.perDay then
                body = body .. " " .. L("HT_STOCKED", "You already have (or have queued) about %d days of stock.",
                    math.floor((restock.owned + (restock.queued or 0)) / restock.perDay + 0.5))
            end
        elseif suggestion.verdict == "loss" then
            title = L("HT_S_LOSS", "%s is losing gold", name)
            body = L("HT_S_LOSS_BODY", "Sold %d of %d that finished; %d expired. After what you paid and %s in lost deposits it made %s. Consider pausing it.",
                s.sold, s.resolved, s.expired, Money(-s.lost, true), Money(s.realized, true))
        elseif suggestion.verdict == "stuck" then
            title = L("HT_S_STUCK", "%d %s unsold", s.stock, name)
            body = s.stockValue and L("HT_S_STUCK_BODY", "%s is sitting in them. Check the Posting tab: post them, or wait if the market is below your break-even.",
                Money(s.stockValue))
                or L("HT_S_STUCK_BODY_NOCOST", "They were crafted but never posted. Check the Posting tab: post them, or wait if the market is below your break-even.")
        else
            title = L("HT_S_SLOW", "Post fewer %s", name)
            body = s.sold == 0
                and L("HT_S_SLOW_NONE", "None sold yet: all %d that finished expired (%s in deposits). Check its price on the Posting tab, and post fewer at a time.",
                    s.expired, Money(-s.lost, true))
                or L("HT_S_SLOW_BODY", "%d of %d that finished expired (%s). Smaller posts lose less deposit and tie up less gold.",
                    s.expired, s.resolved, Percent(s.expireRate))
        end
        local canQueue = restock and not restock.blocked and restock.crafts > 0
        row.action.restock = canQueue and restock or nil
        row.action:SetShown(canQueue and true or false)
        row.action:SetText(canQueue and L("HT_QUEUE_CRAFTS", "Queue %d crafts", restock.crafts) or "")
        row.title:ClearAllPoints(); row.title:SetPoint("TOPLEFT", 10, -5)
        if canQueue then row.title:SetPoint("RIGHT", row.action, "LEFT", -6, 0) else row.title:SetPoint("RIGHT", -6, 0) end
        -- The body starts below the Queue button so its first line is not covered.
        row.body:ClearAllPoints()
        row.body:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, canQueue and -9 or -3)
        row.body:SetPoint("RIGHT", -6, 0)
        row.title:SetText(title); row.body:SetText(body)
        local c = colors[suggestion.verdict] or { 1, 1, 1 }
        row.bar:SetColorTexture(c[1], c[2], c[3], 1)
        row.bg:SetColorTexture(band[1], band[2], band[3], band[4] or 1)
        row.body:SetWidth(math.max(1, content:GetWidth() - 16))
        y = Place(row, y, (canQueue and 32 or 26) + row.body:GetStringHeight()) + 6
    end
    for index = #suggestions + 1, #suggestionRows do suggestionRows[index]:Hide() end
    -- More than fit above the list: a link to see them all.
    local hidden = #allSuggestions - #suggestions
    moreLink:SetShown(hidden > 0)
    if hidden > 0 then
        moreLink.label:SetText(Common.ThemeHex("accent") .. L("HT_ALL_SUGGESTIONS", "Show all %d suggestions", #allSuggestions) .. " ›|r")
        y = Place(moreLink, y, 18) + 6
    end

    -- By item or the raw log.
    local rows = 0
    local function Line(a, b, c, d, tip)
        rows = rows + 1
        local row = ListRow(rows)
        row.a:SetText(a); row.b:SetText(b); row.c:SetText(c); row.d:SetText(d); row.tip = tip
        row.bg:SetColorTexture(band[1], band[2], band[3], row.band and (band[4] or 1) or 0)
        row:Show()
        y = Place(row, y, 22)
    end
    if mode == "items" then
        local accent = Common.ThemeHex("accent")
        Line(accent .. L("HT_ITEM", "Item") .. "|r", accent .. L("HT_SOLD_POSTED", "Sold/posted") .. "|r",
            accent .. L("HT_REALIZED", "Realized profit") .. "|r", accent .. L("HT_VERDICT", "Verdict") .. "|r",
            function(self) Tip(self, L("HT_VERDICT", "Verdict"), nil, L("HT_VERDICT_NOTE",
                "Craft more: 80%+ sell-through and margin above your low-profit warning. Post less: 30%+ expired. Losing money: realized profit below zero. Needs 10+ posted items.")) end)
        table.sort(stats, function(a, b) return (a.realized or -math.huge) > (b.realized or -math.huge) end)
        for _, s in ipairs(stats) do
            local verdict = analysis.Verdict(s, opts.marginWarn)
            Line(ItemName(s.itemID),
                s.posted == 0 and L("HT_NOT_POSTED", "not posted")
                    or s.resolved == 0 and (s.listed > 0 and L("HT_WAITING_SALES", "%d listed", s.listed)
                        or L("HT_NO_RESULT_COUNT", "%d no result", s.pending))
                    or string.format("%d/%d |cff999999%s|r", s.sold, s.resolved, Percent(s.sellThrough)),
                s.realized and Money(s.realized, true, true) or "—", Verdict(verdict),
                function(self) Tip(self, ItemName(s.itemID), {
                    { L("HT_CRAFTED", "Crafted"), s.crafted },
                    { L("HT_SELL_THROUGH", "Sell-through"), Percent(s.sellThrough) },
                    { L("HT_STILL_LISTED", "Still listed"), s.listed },
                    { L("HT_NO_RESULT", "No result yet"), math.max(0, s.pending - s.listed) },
                    { L("HT_EXPIRED", "Expired"), s.expired .. " · " .. Money(-s.lost, true) },
                    { L("HT_MARGIN", "Margin"), Percent(s.margin) },
                    { L("HT_UNSOLD", "Unsold"), s.stock .. (s.stockValue and (" · " .. Money(s.stockValue)) or "") },
                }, s.cost and nil or L("HT_NO_COST", "Your cost is unknown (no recorded purchases for its queue plan), so profit is not shown.")) end)
        end
    elseif mode == "batches" then
        local accent = Common.ThemeHex("accent")
        Line(accent .. L("HT_BATCH", "Batch") .. "|r", accent .. L("HT_SOLD_MADE", "Sold/made") .. "|r",
            accent .. L("HT_REALIZED", "Realized profit") .. "|r", accent .. L("HT_LEFT", "Left") .. "|r",
            function(self) Tip(self, L("HT_BATCH", "Batch"), nil, L("HT_BATCH_NOTE",
                "Each Craft Queue plan from purchase to sale. Sales go to the oldest batch that made the item. Profit counts sold items only, at what the batch cost you.")) end)
        local since = period > 0 and ((GetServerTime and GetServerTime() or time()) - period * 86400) or 0
        local history = GAM.CraftHistory
        local batches = analysis.Batches(records, history.Events(), history.PlanPurchases, GAM.Posting.MarketPrice,
            opts.ahCut, function(record) return (history.MaterialCost(record.consumed, record.id, GAM.Posting.MarketPrice)) end)
        for _, b in ipairs(batches) do
            if b.start >= since or b.left > 0 then
                Line((b.record.name or "?") .. (b.start > 0 and (" |cff999999" .. When(b.start) .. "|r") or ""),
                    string.format("%d/%d", b.sold, b.made),
                    b.realized and Money(b.realized, true, true) or "—",
                    b.left > 0 and L("HT_LEFT_COUNT", "%d left", b.left) or ("|cff83e896" .. L("HT_SOLD_OUT", "sold out") .. "|r"),
                    function(self) Tip(self, b.record.name or "?", {
                        { L("HT_STARTED", "Started"), b.start > 0 and When(b.start) or "—" },
                        { L("HT_CRAFTED", "Crafted"), b.made },
                        { L("HT_BOUGHT", "Bought for it"), Money(b.paid) },
                        { L("HT_COST", "Its items cost you"), b.cost and Money(b.cost) or "—" },
                        { L("HT_SOLD", "Sold"), b.sold .. " · " .. Money(b.revenue) },
                        { L("HT_REALIZED", "Realized profit"), b.realized and Money(b.realized, true) or "—" },
                        { L("HT_UNSOLD", "Unsold"), b.left },
                    }, b.costSource == "used" and L("HT_COST_USED", "Cost counts the materials this batch really used, at what you paid (market price for anything not recorded as bought).")
                        or b.cost and L("HT_COST_ESTIMATE", "Cost is estimated from the break-even: this batch was crafted before GAM counted materials used.")
                        or L("HT_NO_BATCH_COST", "The break-even for this batch is unknown, so profit is not shown.")) end)
            end
        end
    elseif mode == "log" then
        local list = {}
        for _, event in ipairs(events) do
            if not filter or event.kind == filter then list[#list + 1] = event end
        end
        -- By when it happened: a sale mail collected later sorts at its sale time.
        table.sort(list, function(x, y)
            if (x.t or 0) ~= (y.t or 0) then return (x.t or 0) < (y.t or 0) end
            return (x.id or 0) < (y.id or 0)
        end)
        for index = #list, math.max(1, #list - 199), -1 do
            local event = list[index]
            local label = EVENT[event.kind]
            local sign = EVENT_SIGN[event.kind]
            Line(ItemName(event.itemID), When(event.t), L(label[1], label[2]) .. " ×" .. event.qty,
                sign and event.copper > 0 and Money(sign * event.copper, true, true) or "—",
                event.kind == "post" and function(self) Tip(self, L("HT_DEPOSIT", "Deposit"), nil, L("HT_DEPOSIT_NOTE", "Paid when posting; refunded if the auction sells.")) end
                or (event.kind == "expired" or event.kind == "cancel") and function(self) Tip(self, L("HT_DEPOSIT_LOST", "Deposit lost"), nil, L("HT_DEPOSIT_LOST_NOTE", "The auction expired or was cancelled, so its deposit was not refunded. The items come back by mail.")) end
                or nil)
        end
    end
    local empty = rows <= ((mode == "log" or mode == "suggestions") and 0 or 1)
    if mode == "suggestions" then empty = #allSuggestions == 0 end
    emptyText:SetText(mode == "suggestions"
        and L("HT_NO_SUGGESTIONS", "No suggestions yet. An item needs 10+ posted in the selected period before GAM suggests anything.")
        or L("HT_EMPTY", "Nothing recorded yet. Purchases, crafts, posts and sales appear here."))
    emptyText:SetShown(empty)
    if empty then
        emptyText:SetWidth(math.max(1, content:GetWidth() - 8))
        y = Place(emptyText, y + 6, 40)
    end
    for index = rows + 1, #listRows do listRows[index]:Hide() end
    content:SetHeight(math.max(1, y + 6))
    if scroll.ScrollBar then scroll.ScrollBar:SetShown(content:GetHeight() > scroll:GetHeight()) end

    modeButton:SetText(mode == "items" and L("HT_SHOW_BATCHES", "Show batches")
        or mode == "batches" and L("HT_SHOW_LOG", "Show log")
        or mode == "log" and L("HT_SHOW_SUGGESTIONS", "Show suggestions") or L("HT_SHOW_ITEMS", "Show by item"))
    periodButton:SetText(period > 0 and L("HT_LAST_DAYS", "Last %d days", period) or L("HT_ALL_TIME", "All"))
    filterButton:SetShown(mode == "log")
    local fLabel = filter and EVENT[filter] or nil
    filterButton:SetText(fLabel and L(fLabel[1], fLabel[2]) or L("HT_EVERYTHING", "Everything"))
end

-- Verbose reports slow redraws (Settings: Debug log > Capture level).
if GAM.Log and GAM.Log.Timed then UI.Refresh = GAM.Log.Timed("History tab redraw", UI.Refresh) end

function UI.Embed(parent)
    if host then return end
    host = CreateFrame("Frame", nil, parent)
    host:SetAllPoints(parent)
    -- Totals: labeled values in two rows (three, then two).
    local totalsFrame = CreateFrame("Frame", nil, host); totalsFrame:SetHeight(64)
    totalsFrame:SetPoint("TOPLEFT", 6, -2); totalsFrame:SetPoint("RIGHT", -6, 0)
    local defs = {
        { L("HT_SPENT", "Spent on materials"), true }, { L("HT_SOLD_AFTER_CUT", "Sold (after cut)") },
        { L("HT_DEPOSITS_LOST", "Deposits lost"), L("HT_DEPOSITS_LOST_NOTE", "Deposits from auctions that expired or were cancelled. Posting fewer at a time, or shorter durations, lowers this.") },
        { L("HT_REALIZED", "Realized profit"), L("HT_REALIZED_NOTE",
            "Sales after the AH cut, minus what you paid for the materials those items used, minus lost deposits. Gold in unsold stock is valued at what you paid. Only counts what GAM recorded.") },
        { L("HT_UNSOLD_GOLD", "Gold in unsold stock"), L("HT_UNSOLD_GOLD_NOTE", "Items still in bags, banks, unsold auctions or the mailbox, valued at what you paid. Gold sitting here is not working for you.") },
    }
    for index, def in ipairs(defs) do
        local cell = CreateFrame("Frame", nil, totalsFrame); cell:SetSize(140, 30)
        local column, line = (index - 1) % 3, math.floor((index - 1) / 3)
        cell:SetPoint("TOPLEFT", totalsFrame, "TOPLEFT", column * 146, -line * 32)
        local label = Themed(Text(cell, 10), "muted"); label:SetPoint("TOPLEFT"); label:SetText(def[1])
        local value = Themed(Text(cell, 12), "body"); value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        stats_ui[index] = { label = label, value = value }
        if def[2] then
            cell:EnableMouse(true)
            local stat = stats_ui[index]
            -- A note set on refresh (true) or a fixed one.
            Hover(cell, function(self) Tip(self, def[1], nil, def[2] == true and stat.note or def[2]) end)
        end
    end
    local function SmallButton(width, onClick)
        local b = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
        b:SetSize(width, 20); b:SetScript("OnClick", function() onClick(); UI.Refresh() end)
        local fs = b:GetFontString()
        if fs then local face, _, flags = fs:GetFont(); if face then fs:SetFont(face, 10, flags) end end
        local common = GAM.UI.MainWindowCommon
        if common and common.StyleComfortableButton then common.StyleComfortableButton(b, false) end
        return b
    end
    modeButton = SmallButton(104, function()
        for index, value in ipairs(MODES) do
            if value == mode then mode = MODES[index % #MODES + 1]; break end
        end
    end)
    modeButton:SetPoint("TOPLEFT", totalsFrame, "BOTTOMLEFT", 0, -6)
    periodButton = SmallButton(96, function()
        for index, value in ipairs(PERIODS) do
            if value == period then period = PERIODS[index % #PERIODS + 1]; break end
        end
    end)
    periodButton:SetPoint("LEFT", modeButton, "RIGHT", 6, 0)
    filterButton = SmallButton(96, function()
        for index, value in ipairs(FILTERS) do
            if (value or nil) == filter then filter = FILTERS[index % #FILTERS + 1] or nil; break end
        end
    end)
    filterButton:SetPoint("LEFT", periodButton, "RIGHT", 6, 0)
    scroll = CreateFrame("ScrollFrame", nil, host, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", modeButton, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -24, 22)
    content = CreateFrame("Frame", nil, scroll); content:SetSize(400, 1); scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function() UI.Refresh() end)
    -- "Show all N suggestions": opens the Suggestions view.
    moreLink = CreateFrame("Button", nil, content)
    moreLink.label = Text(moreLink, 11); moreLink.label:SetPoint("LEFT", 10, 0)
    moreLink:SetScript("OnClick", function()
        mode = "suggestions"
        scroll:SetVerticalScroll(0)
        UI.Refresh()
    end)
    moreLink:Hide()
    emptyText = Themed(Text(content, 11), "muted"); emptyText:SetWordWrap(true)
    emptyText:SetText(L("HT_EMPTY", "Nothing recorded yet. Purchases, crafts, posts and sales appear here."))
    footer = Themed(Text(host, 10), "muted")
    footer:SetPoint("BOTTOMLEFT", 6, 4); footer:SetPoint("RIGHT", -6, 0)
    footer:SetText(L("HT_FOOTER", "Recorded on this character only. Suggestions need 10+ posted items; nothing changes unless you click."))
    host:SetScript("OnShow", UI.Refresh)
    if GAM.Posting then GAM.Posting.OnChange(UI.Refresh) end
end
