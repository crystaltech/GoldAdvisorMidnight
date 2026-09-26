-- Craft Plan replaces the VI steps surface with shopping, crafting and outputs.
local ADDON_NAME, GAM = ...
local function L(key, fallback, ...)
    local value = (GAM.L and GAM.L[key]) or fallback
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end
GAM.UI = GAM.UI or {}
local UI = {}
GAM.UI.CraftPlanWindow = UI
local window, scroll, host, status, nextButton, stopButton, title
local rows, showHistory = {}, false
local busyRefresh = false
local shoppingAwaitingMaterials
local visibleRows = 0
local rankProposal, editing, nextAction
local embedded, viewMode = false, "queue"
local Plan = GAM.CraftPlan
local FinishEditing
local function Price(value)
    return value and GAM.Pricing.FormatPrice(math.ceil(value)) or "—"
end
-- Ranked items carry Blizzard's rank icon so Shopping and queue rows show
-- exactly which rank is bought or used, even before item data loads.
local function Rank(id)
    local api = C_TradeSkillUI
    for _, fn in ipairs({ api and api.GetItemReagentQualityByItemInfo, api and api.GetItemCraftedQualityByItemInfo }) do
        if type(fn) == "function" then
            local ok, rank = pcall(fn, id)
            rank = ok and tonumber(rank) or nil
            if rank and rank > 0 then return rank end
        end
    end
    return GAM.ItemRanks and GAM.ItemRanks[tonumber(id)] or nil
end
local function RankIcon(id)
    local rank = id and Rank(id)
    return rank and (" |A:Professions-ChatIcon-Quality-12-Tier" .. rank .. ":14:14|a") or ""
end
local function Name(id, fallback)
    return ((C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or fallback or tostring(id)) .. RankIcon(id)
end
local function Report(ok, err)
    if not ok then Plan.Notify(tostring(err or (GAM.L and GAM.L["WF_ACTION_UNAVAILABLE"] or "This action is not available."))) end
end
local function Button(parent, text, width, action)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 26); button:SetText(text); button:SetScript("OnClick", function(...)
        if FinishEditing and not FinishEditing() then return end
        action(...)
    end)
    local common = GAM.UI.MainWindowCommon
    if common and common.StyleComfortableButton then common.StyleComfortableButton(button, false) end
    return button
end
local function Text(parent, font)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    local face, _, flags = text:GetFont()
    if face then text:SetFont(face, embedded and 11 or (font and 16 or 14), flags) end
    text:SetTextColor(0.95, 0.95, 0.95)
    text:SetJustifyH("LEFT"); text:SetWordWrap(true)
    return text
end
FinishEditing = function(cancel)
    if not editing then return true end
    local draft = editing
    local value = draft.box:GetText()
    editing = nil
    draft.box:ClearFocus()
    local ok, err = true, nil
    if not cancel and tonumber(value) ~= draft.plan.target then
        ok, err = Plan.SetTarget(draft.plan, value)
    end
    draft.box:SetText(tostring(draft.plan.target))
    if not ok then Report(ok, err) end
    UI.Refresh()
    return ok
end
local function Row(index)
    if rows[index] then return rows[index] end
    local row = CreateFrame("Frame", nil, host)
    row:SetHeight(54)
    row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -(index - 1) * 54)
    row:SetPoint("RIGHT", host, "RIGHT")
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, index % 2 == 1 and 0.055 or 0.015)
    row.label = Text(row); row.label:SetPoint("TOPLEFT", 10, -8); row.label:SetPoint("RIGHT", row, "RIGHT", -302, 0)
    row.amount = Text(row); row.amount:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -10); row.amount:SetWidth(210)
    row.action = Button(row, "", 100, function() if row.click then row.click() end end)
    row.action:SetScript("OnClick", function()
        local click = row.click
        if FinishEditing() and click then click() end
    end)
    row.action:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.secondary = Button(row, "", 96, function() if row.other then row.other() end end)
    row.secondary:SetPoint("RIGHT", row.action, "LEFT", -5, 0)
    row.edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.edit:SetSize(70, 24); row.edit:SetPoint("RIGHT", row.secondary, "LEFT", -10, 0)
    row.edit:SetAutoFocus(false); row.edit:SetNumeric(true)
    row.edit:SetScript("OnEditFocusGained", function(self)
        if row.editPlan then editing = {plan = row.editPlan, box = self} end
    end)
    row.edit:SetScript("OnEditFocusLost", function(self)
        if editing and editing.box == self then FinishEditing() end
    end)
    row.edit:SetScript("OnEnterPressed", function(self)
        if row.editPlan then
            editing = editing or {plan = row.editPlan, box = self}
            FinishEditing()
        else
            self:ClearFocus()
        end
    end)
    row.edit:SetScript("OnEscapePressed", function(self)
        if row.editPlan then FinishEditing(true) else self:ClearFocus() end
    end)
    row.editLabel = Text(row)
    row.editLabel:SetPoint("RIGHT", row.edit, "LEFT", -10, 0)
    row.editLabel:SetText((GAM.L and GAM.L["WF_TOTAL_CRAFTS"] or "Total crafts"))
    row:EnableMouse(true)
    row:SetScript("OnMouseDown", function() FinishEditing() end)
    row:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and row.purchaseItemID and FinishEditing() then Plan.Buy(row.purchaseItemID) end
    end)
    row:SetScript("OnEnter", function()
        if row.itemID then
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(row.itemID)
            if row.tip and GameTooltip.AddLine then GameTooltip:AddLine(row.tip, 0.85, 0.85, 0.85, true) end
            GameTooltip:Show()
        elseif row.tip then
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetText(row.tip, 1, 0.82, 0, 1, true); GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[index] = row
    return row
end
local function LayoutRows()
    if not host then return end
    local width = math.max(1, scroll:GetWidth())
    host:SetWidth(width)
    local offset = 0
    for i = 1, visibleRows do
        local row = rows[i]
        local reserve = (row.action:IsShown() or row.secondary:IsShown() or row.edit:IsShown()
            or row.amount:GetText() ~= "") and (row.edit:IsShown() and 312 or 180) or 20
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", row.kind == "step" and 24 or 10, -8)
        local quantityX = embedded and math.floor(width * 0.6)
            or math.min(width - 230, math.max(340, width * 0.62))
        row.amount:ClearAllPoints()
        row.amount:SetPoint("TOPLEFT", row, "TOPLEFT", quantityX, -8)
        row.amount:SetWidth(math.max(60, width - quantityX - 10))
        row.label:SetWidth(math.max(1, row.amount:GetText() ~= "" and quantityX - 40 or width - reserve))
        local height = math.max(row.kind == "section" and 32 or 36, row.label:GetStringHeight() + 16, row.amount:GetStringHeight() + 16)
        if embedded and row.kind == "plan" then
            row.label:SetWidth(math.max(1, width - 20))
            row.action:ClearAllPoints(); row.action:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 4)
            row.action:SetWidth(68)
            row.edit:ClearAllPoints(); row.edit:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 90, 5)
            height = row.label:GetStringHeight() + 46
        end
        if row.kind == "section" or row.kind == "plan" then offset = offset + (i > 1 and 14 or 0) end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -offset)
        row:SetPoint("RIGHT", host, "RIGHT")
        row:SetHeight(height)
        offset = offset + height
    end
    host:SetHeight(math.max(1, offset))
    scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, offset - scroll:GetHeight())))
end
function UI.Refresh()
    if not window or not window:IsShown() or busyRefresh then return end
    -- Inventory events must not recycle the row underneath a quantity draft.
    -- The next action commits the draft and then uses the newly rendered queue.
    if editing then return end
    busyRefresh = true
    local advanceToQueue = false
    local ok, err = pcall(function()
        local data, projection = Plan.GetData(), Plan.Project()
        if embedded and viewMode == "shopping" then
            local awaiting = #projection.buys > 0 or next(data.incoming) ~= nil
            if shoppingAwaitingMaterials and not awaiting and not Plan.IsBusy() then
                for _, task in ipairs(projection.tasks) do
                    if task.ready > 0 and not task.plan.needsReview then advanceToQueue = true; break end
                end
            end
            shoppingAwaitingMaterials = awaiting
        end
        local index = 0
        local function Add(label, amount, action, click, otherText, other, tip)
            index = index + 1
            local row = Row(index)
            row.kind = "item"
            row.bg:SetColorTexture(1, 1, 1, 0)
            row.label:SetText(label); row.amount:SetText(amount or "")
            row.click, row.other, row.tip, row.itemID, row.editPlan = click, other, tip, nil, nil
            row.purchaseItemID = nil
            row.action:SetWidth(100)
            row.action:ClearAllPoints(); row.action:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.action:SetText(action or ""); row.action:SetShown(action ~= nil)
            row.action:SetEnabled(click ~= nil and not Plan.IsBusy())
            row.secondary:SetText(otherText or ""); row.secondary:SetShown(otherText ~= nil)
            row.secondary:SetEnabled(other ~= nil and not Plan.IsBusy())
            row.edit:Hide(); row.editLabel:Hide(); row:Show()
            return row
        end
        local function Section(label, caption)
            local row = Add("|cffffdf70" .. label .. "|r", caption and "|cffaaaaaa" .. caption .. "|r")
            row.kind = "section"
            row.bg:SetColorTexture(1, 1, 1, 0.035)
            return row
        end
        title:SetText(#data.plans == 1 and L("WF_PLAN_TITLE_ONE", "Craft Plan · %d strategy", #data.plans)
            or L("WF_PLAN_TITLE_MANY", "Craft Plan · %d strategies", #data.plans))
        local empty = #data.plans == 0 and next(data.incoming) == nil
        if empty then
            Add("|cffffdf70" .. L("WF_QUEUE_EMPTY_TITLE", "Your craft queue is empty") .. "|r\n"
                .. L("WF_QUEUE_EMPTY_BODY", "Select a strategy, then choose Add to Queue in Details."))
        else

        if not embedded or viewMode == "shopping" then
        Section((GAM.L and GAM.L["WF_MATERIALS"] or "Materials to buy"), (GAM.L and GAM.L["WF_QUANTITY"] or "Quantity needed"))
        if #projection.buys > 0 then Add((GAM.L and GAM.L["WF_SELECT_MATERIAL"] or "Select a material below to buy it.")) end
        if #projection.buys == 0 then Add("|cff88cc99" .. L("WF_ACCOUNTED", "All materials accounted for") .. "|r") end
        -- Gold guard: warn before a shopping trip the player cannot finish,
        -- and offer craft counts that fit while keeping the reserve.
        local budget = GAM.CraftPlanBudget and GAM.CraftPlanBudget.Check(projection)
        if budget then
            local basis = L("WF_BUDGET_BASIS", "You can spend %s (keeping %d%% of %s).",
                Price(budget.spendable), budget.reserve, Price(budget.money))
            local unpriced = budget.unpriced > 0
                and ("\n" .. L("WF_BUDGET_UNPRICED", "%d materials have no price yet; the total may be higher.", budget.unpriced)) or ""
            if not budget.short then
                Add("|cffaaaaaa" .. L("WF_BUDGET_OK", "Estimated cost %s.", Price(budget.cost)) .. " " .. basis .. unpriced .. "|r")
            else
                local label = "|cffffaa55" .. L("WF_BUDGET_SHORT", "Not enough gold: these materials cost about %s.", Price(budget.cost))
                    .. "|r\n" .. basis .. unpriced
                local action, click
                local suggestions = budget.affordable and budget.suggestions or nil
                if suggestions then
                    if #suggestions == 1 then
                        action = L("WF_BUDGET_USE", "Use %d crafts", suggestions[1].target)
                        label = label .. "\n" .. L("WF_BUDGET_SUGGEST_ONE", "%d total crafts fit your budget.", suggestions[1].target)
                    else
                        local parts = {}
                        for _, entry in ipairs(suggestions) do parts[#parts + 1] = entry.plan.name .. " " .. entry.target end
                        action = L("WF_BUDGET_REDUCE", "Reduce crafts")
                        label = label .. "\n" .. L("WF_BUDGET_SUGGEST_MANY", "Fits your budget: %s.", table.concat(parts, ", "))
                    end
                    click = function()
                        GAM.CraftPlanBudget.Apply(suggestions)
                        UI.Refresh()
                    end
                else
                    label = label .. "\n" .. L("WF_BUDGET_NONE", "Not even one more craft fits. Lower the gold reserve in Settings > Pricing, or sell items first.")
                end
                local row = Add(label, "", action, click)
                row.tip = L("WF_BUDGET_TIP", "Compares the shopping list with your gold, keeping the reserve set in Settings > Pricing. Suggested crafts use each plan's saved setup and the materials you already own.")
            end
        end
        for _, buy in ipairs(projection.buys) do
            local source = GAM.VendorPrices.ResolvePurchase(buy.itemID, buy.quantity)
            local row = Add(Name(buy.itemID, buy.name) .. "\n|cffaaaaaa" .. (source == "vendor" and (GAM.L and GAM.L["WF_VENDOR"] or "Vendor") or (GAM.L and GAM.L["WF_AH"] or "Auction House")) .. "|r",
                tostring(buy.quantity))
            row.itemID = buy.itemID
            row.purchaseItemID = buy.itemID
            row.tip = (GAM.L and GAM.L["WF_BUY_MATERIAL_TIP"] or "Click to buy this material. Other shortages stay on your shopping list.")
            if source ~= "vendor" and GAM.AHScan and GAM.AHScan.ComputePriceForQty then
                local _, _, _, _, _, depth = GAM.AHScan.ComputePriceForQty(buy.itemID, buy.quantity)
                if depth and depth.incomplete then
                    row.tip = row.tip .. "\n" .. L("WF_SHORT_MARKET", "Only %d listed on the Auction House; %d needed. The rest may cost more or be unavailable.", depth.filled, depth.requested)
                    row.label:SetText(row.label:GetText() .. " |cffffaa55!|r")
                end
            end
        end
        for id, incoming in pairs(data.incoming) do
            local row = Add(Name(id) .. "\n|cffcccc88" .. L("WF_MAIL_ROW", "Purchased; collect from mailbox before crafting.") .. "|r", tostring(incoming.quantity))
            row.itemID = id
            if Plan.ConfirmDelivery then
                local itemID, quantity = id, incoming.quantity
                Add((GAM.L and GAM.L["WF_COLLECT_CONFIRM"] or "Already collected? Confirm only after receiving this delivery."), "", (GAM.L and GAM.L["WF_COLLECTED"] or "Collected"), function()
                    Plan.ConfirmDelivery(itemID, quantity)
                end)
            end
        end
        end -- shopping
        if not embedded or viewMode == "queue" then
        Section((GAM.L and GAM.L["WF_QUEUE_CONCENTRATION_OFF"] or "Craft queue · Concentration off"), (GAM.L and GAM.L["WF_READY"] or "Remaining / Ready"))
        for _, plan in ipairs(data.plans) do
            local saved = plan
            local row = Add("|cffffdf70" .. plan.name .. "|r\n" .. L("WF_PLAN_PROGRESS", "%d crafts completed · Saved setup · %s", plan.completed,
                plan.vi and L("WF_VI_ON", "VI on") or L("WF_VI_OFF", "VI off")),
                "", (GAM.L and GAM.L["WF_REMOVE"] or "Remove"), function() rankProposal = nil; Plan.Remove(saved); UI.Refresh() end)
            row.kind = "plan"
            row.bg:SetColorTexture(1, 0.82, 0.35, 0.055)
            row.tip = L("WF_SAVED_SETUP_TIP", "Total final recipe crafts. Enter or click away applies; Escape cancels. Quantities follow your saved setup. New scans and global rank/VI settings affect new entries, not this plan's saved choices.")
            row.editPlan = saved
            row.edit:ClearAllPoints(); row.edit:SetPoint("RIGHT", row.action, "LEFT", -16, 0)
            row.edit:SetText(tostring(plan.target)); row.edit:Show(); row.editLabel:Show()
            row.edit:SetEnabled(not Plan.IsBusy() and not plan.needsReview)
            if rankProposal and rankProposal.plan == plan then
                local proposal = rankProposal
                Add(proposal.summary, "", (GAM.L and GAM.L["WF_ACCEPT_RANKS"] or "Accept ranks"), function()
                    local ok, err = Plan.AcceptRankChange(proposal)
                    rankProposal = nil
                    Report(ok, err); UI.Refresh()
                end, (GAM.L and GAM.L["WF_CANCEL"] or "Cancel"), function() rankProposal = nil; UI.Refresh() end)
            end
            if plan.needsReview then
                local review = Add("|cffffaa55" .. L("WF_VERIFY_PROGRESS_TITLE", "Verify completed final crafts.") .. "|r\n"
                    .. L("WF_VERIFY_PROGRESS_BODY", "Enter the total completed count, including crafts outside GAM, then Confirm."), "", (GAM.L and GAM.L["WF_CONFIRM"] or "Confirm"), nil)
                review.edit:Show(); review.edit:SetEnabled(not Plan.IsBusy())
                if not review.edit:HasFocus() then review.edit:SetText(tostring(plan.completed)) end
                review.click = function() Report(Plan.ReviewProgress(saved, review.edit:GetText())) end
                review.action:SetEnabled(not Plan.IsBusy())
            end
            local stepNumber = 0
            for _, task in ipairs(projection.tasks) do
                if task.plan == plan then
                    stepNumber = stepNumber + 1
                    local node = task.node
                    local parts = { task.final and L("WF_FINAL_RECIPE", "%s · final recipe", node.name)
                        or L("WF_INTERMEDIATE_RECIPE", "%s · intermediate", node.name), L("WF_EXACT_MATERIALS", "Exact materials per craft:") }
                    local gearText
                    if node.gearMode and node.gearMode ~= "current" then
                        local name = node.gearMode == "multicraft" and L("GEAR_MODE_MC", "Multicraft") or L("GEAR_MODE_RES", "Resourcefulness")
                        if node.gearMode == "legacy" then name = L("WF_UNKNOWN", "unknown") end
                        local equipped = GAM.CraftingStatsGear and GAM.CraftingStatsGear.IsEquipped(node.gearRequirement, node.recipeID, node.statProfileKey)
                        gearText = L("VI_GEAR_FORMAT", "Gear: %s", name) .. (equipped and " |cff88dd99\226\156\147|r" or " |cffffaa55!|r")
                        for _, slot in ipairs(node.gearRequirement and node.gearRequirement.slots or {}) do
                            if slot.link then parts[#parts + 1] = slot.link end
                        end
                    end
                    for _, reagent in ipairs(node.reagents) do
                        parts[#parts + 1] = reagent.quantity .. " x " .. Name(reagent.itemID, reagent.name)
                    end
                    local row = Add("|cff999999" .. stepNumber .. ".|r " .. node.name .. RankIcon(node.outputItemID) .. (task.final and " |cffaaaaaa" .. L("WF_FINAL_TAG", "(final)") .. "|r" or ""),
                        L("WF_STEP_COUNTS", "%d remaining  ·  %s ready", task.crafts,
                            (task.ready > 0 and "|cff88dd99" or "|cffccaa77") .. task.ready .. "|r"),
                        nil, nil, nil, nil, table.concat(parts, "\n"))
                    row.kind = "step"
                    if gearText then row.label:SetText(row.label:GetText() .. "\n" .. gearText) end
                    row.itemID = nil
                end
            end
            if plan.completed >= plan.target then
                Add("|cff88ee99" .. L("WF_REQUESTED_COMPLETE", "Requested crafts completed.") .. "|r")
                local extra = Plan.ExtraCapacity and Plan.ExtraCapacity(plan) or 0
                if extra > 0 then
                    Add(string.format(GAM.L and GAM.L["WF_EXTRA_AVAILABLE"] or "%d additional crafts from unreserved materials in your bags and banks.", extra),
                        "", string.format(GAM.L and GAM.L["WF_QUEUE_MORE"] or "Queue %d more", extra),
                        function() Report(Plan.QueueExtras(saved, extra)) end)
                end
            elseif plan.optionalExtra then
                Add(L("WF_EXTRA_POLICY", "Optional: uses surplus after all regular jobs. No additional materials will be purchased."))
                local estimate = Plan.OutputBreakEven and Plan.OutputBreakEven(plan, plan.root)
                Add(L("WF_EXTRA_BREAK_EVEN", "Est. break-even / extra item: %s", estimate and Price(estimate) or L("WF_ESTIMATE_UNAVAILABLE", "unavailable"))
                    .. "\n" .. L("WF_ESTIMATE_BASIS", "Current material prices and base yield; includes AH cut."))
            end
        end
        if #data.plans == 0 then Add((GAM.L and GAM.L["WF_EMPTY_QUEUE"] or "Select a strategy and use Add to Queue in Details.")) end

        local outputRows = Plan.OutputSummary(projection)
        if #outputRows > 0 then Section((GAM.L and GAM.L["WF_OUTPUTS"] or "Crafted outputs and leftovers"), (GAM.L and GAM.L["WF_OUTPUT_COUNTS"] or "Recorded / Free (bags + banks)")) end
        for _, output in ipairs(outputRows) do
            local estimate = output.breakEven and Price(output.breakEven) or L("WF_ESTIMATE_MISSING", "unavailable (missing or differing costs)")
            local row = Add(Name(output.itemID) .. "\n" .. L("WF_OUTPUT_BREAK_EVEN", "Est. break-even / item: %s", estimate),
                L("WF_RECORDED_COUNT", "%d recorded", output.produced) .. "\n" .. L("WF_FREE_COUNT", "%d free (bags + banks)", output.free), nil, nil, nil, nil,
                (output.currentEstimate and L("WF_CURRENT_ESTIMATE_TIP", "Break-even uses current material prices and base yield, including the AH cut; bonus procs are excluded.")
                    or L("WF_SAVED_ESTIMATE_TIP", "Break-even from the strategy's pricing estimate, including expected bonus procs; recalculated when you change the craft count.")) .. "\n"
                .. L("WF_OUTPUT_TIP", "These are estimates, not actual acquisition costs. Recorded includes GAM batches only. Free counts your bags, bank, reagent bank and Warband bank, excludes all queue reservations, and may include previously owned stock. Free items may be sold or kept."))
            row.itemID = output.itemID
        end
        local hasHistory = false
        for _, saved in ipairs(data.plans) do if next(saved.history) then hasHistory = true; break end end
        if hasHistory then
        Add("|cffffdf70" .. L("WF_HISTORY", "Completed steps") .. "|r", "", showHistory and (GAM.L and GAM.L["WF_HIDE"] or "Hide") or (GAM.L and GAM.L["WF_SHOW"] or "Show"), function() showHistory = not showHistory; UI.Refresh() end)
        if showHistory then
            for _, plan in ipairs(data.plans) do
                for key, count in pairs(plan.history) do
                    Add((plan.nodes[key] and plan.nodes[key].name or key) .. "\n" .. plan.name, L("WF_DONE_COUNT", "%d done", count))
                end
            end
        end
        end -- history
        end -- queue
        end -- populated plan
        for i = index + 1, #rows do rows[i]:Hide() end
        visibleRows = index
        LayoutRows()
        local message = Plan.message
        if Plan.messageKind == "summary" then
            local remaining = 0
            for _, saved in ipairs(data.plans) do remaining = remaining + math.max(0, saved.target - saved.completed) end
            message = L("WF_QUEUE_SUMMARY", "%d final crafts remaining  ·  %d materials to buy", remaining, #projection.buys)
        end
        status:SetText(empty and "" or message)
        local busy = Plan.IsBusy()
        stopButton:SetShown(busy); stopButton:SetEnabled(busy)
        local nextTask, allocation, amount, reason = Plan.NextTask(projection)
        -- Lead with the combined shopping trip before offering early batches.
        if #projection.buys > 0 or next(data.incoming) ~= nil then nextTask = nil end
        local needsReview = false
        for _, saved in ipairs(data.plans) do if saved.needsReview and not saved.paused then needsReview = true; break end end
        local label, action = (GAM.L and GAM.L["WF_PLAN_COMPLETE"] or "Plan complete"), nil
        if busy then
            label = (GAM.L and GAM.L["WF_CRAFTING"] or "Crafting...")
        elseif #data.plans == 0 then
            label = (GAM.L and GAM.L["WF_ADD_FROM_DETAILS"] or "Add strategies from Details")
        elseif #projection.buys > 0 then
            label, action = (GAM.L and GAM.L["WF_BUY_MISSING"] or "Buy missing materials"), function() Plan.Buy() end
            if embedded then label, action = (GAM.L and GAM.L["WF_VIEW_SHOPPING"] or "View shopping list"), function() GAM.UI.MainWindow.OpenWorkspace("shopping") end end
        elseif needsReview and not nextTask then
            label = (GAM.L and GAM.L["WF_CONFIRM_PROGRESS"] or "Confirm progress above")
        elseif nextTask then
            local opened = ProfessionsFrame and ProfessionsFrame:IsShown()
            if allocation then
                label = string.format(GAM.L and GAM.L["WF_CRAFT_NEXT_FORMAT"] or "Craft next: %s x%d", nextTask.node.name, amount)
                action = function() rankProposal = nil; Plan.Craft(nextTask) end
            elseif reason == "rank-mismatch" then
                label = (GAM.L and GAM.L["WF_REVIEW_RANK"] or "Review output rank")
                status:SetText(amount)
                action = function()
                    local preview, err = Plan.PreviewRankChange(nextTask)
                    if preview then rankProposal = preview; UI.Refresh()
                    else Report(false, err) end
                end
            elseif reason == "gear-required" then
                label = L("WF_EQUIP_SAVED_SET", "Equip saved profession set")
                status:SetText(amount)
            elseif reason == "setup-mismatch" then
                label, action = (GAM.L and GAM.L["WF_USE_SETUP"] or "Use current setup"), function() Report(Plan.RefreshStrategy(nextTask.plan)) end
                status:SetText(amount)
            elseif reason == "manual" then
                label, action = (GAM.L and GAM.L["WF_REVIEW_MANUAL"] or "Review manual progress"), function() Plan.BeginProgressReview(nextTask.plan) end
                status:SetText(amount)
            elseif not opened or reason == "open-recipe" then
                label, action = string.format(GAM.L and GAM.L["WF_OPEN_RECIPE_FORMAT"] or "Open recipe: %s", nextTask.node.name), function() Plan.OpenRecipe(nextTask) end
            else
                label = (GAM.L and GAM.L["WF_UNAVAILABLE"] or "Craft unavailable")
                status:SetText(tostring(amount))
            end
        elseif #projection.tasks > 0 then
            label = next(data.incoming) and (GAM.L and GAM.L["WF_COLLECT_MAIL"] or "Collect materials from mailbox") or (GAM.L and GAM.L["WF_WAIT_MATERIALS"] or "Waiting for materials")
        else
            for _, saved in ipairs(data.plans) do
                if saved.optionalExtra and saved.completed < saved.target then
                    label = (GAM.L and GAM.L["WF_EXTRA_WAITING"] or "Extra crafts waiting for unreserved materials")
                    break
                end
            end
        end
        if embedded and viewMode == "shopping" then
            action = nil
            if #projection.buys > 0 then
                local context = GAM.QuickBuy and GAM.QuickBuy.GetContext and GAM.QuickBuy.GetContext()
                label = context == "vendor" and (GAM.L and GAM.L["WF_BUY_VENDOR"] or "Buy at vendor") or context == "auction" and (GAM.L and GAM.L["WF_BUY_AH"] or "Buy at Auction House")
                    or (GAM.L and GAM.L["WF_VISIT"] or "Visit a vendor or the Auction House")
                local available = false
                for _, buy in ipairs(projection.buys) do
                    if context == "vendor" and GAM.VendorPrices.GetMerchantOffer then
                        local offer = GAM.VendorPrices.GetMerchantOffer(buy.itemID)
                        local policy = GAM.VendorPrices.ShouldBuyAtMerchant
                        if offer and (not policy or policy(buy.itemID, buy.quantity, offer)) then available = true end
                    end
                    if context == "auction" and GAM.VendorPrices.ResolvePurchase(buy.itemID, buy.quantity) ~= "vendor" then
                        available = true
                    end
                end
                if context and not available then label = (GAM.L and GAM.L["WF_NONE_HERE"] or "No materials to buy here") end
                if available and not busy then action = function() Plan.Buy() end end
            else
                label = next(data.incoming) and (GAM.L and GAM.L["WF_COLLECT_MAIL"] or "Collect materials from mailbox") or (GAM.L and GAM.L["WF_ACCOUNTED"] or "All materials accounted for")
                for _, task in ipairs(projection.tasks) do
                    if task.ready > 0 and not task.plan.needsReview then
                        label, action = (GAM.L and GAM.L["WF_VIEW_QUEUE"] or "View craft queue"), function() GAM.UI.MainWindow.OpenWorkspace("queue") end
                        break
                    end
                end
            end
        end
        if embedded and viewMode == "shopping" and GAM.QuickBuy and GAM.QuickBuy.GetPresentation then
            local purchase = GAM.QuickBuy.GetPresentation()
            if purchase and purchase.entry and GAM.QuickBuy.GetContext() then
                status:SetText(purchase.item .. " · " .. purchase.quantity .. "\n" .. purchase.message)
                label = purchase.label
                action = purchase.enabled and function() GAM.QuickBuy.Buy() end or nil
            end
        end
        if embedded then
            nextButton:ClearAllPoints(); nextButton:SetPoint("BOTTOMLEFT", 6, 4)
            nextButton:SetPoint("BOTTOMRIGHT", busy and -88 or -6, 4)
        end
        nextButton:SetShown(not empty)
        nextButton:SetText(label)
        nextButton:SetEnabled(action ~= nil)
        nextAction = action

    end)
    busyRefresh = false
    if ok and advanceToQueue then
        GAM.UI.MainWindow.OpenWorkspace("queue")
        return
    end
    if not ok then
        status:SetText(L("WF_PLAN_ERROR", "Craft Plan: %s", tostring(err)))
        nextAction = nil
        nextButton:SetEnabled(false)
        if GAM.Log and GAM.Log.Error then GAM.Log.Error("Craft Plan render failed: %s", tostring(err)) end
    end
end
local function Build(parent)
    if window then return end
    Plan.Init()
    embedded = parent ~= nil
    window = CreateFrame("Frame", GAM.RuntimeName("GAMCraftPlanWindow"), parent or UIParent, "BackdropTemplate")
    if embedded then
        window:SetAllPoints(parent)
        window:SetClipsChildren(true)
    else
    local size = Plan.GetData().windowSize or {}
    window:SetSize(math.max(760, math.min(1600, tonumber(size.width) or 960)),
        math.max(460, math.min(1200, tonumber(size.height) or 720)))
    window:SetPoint("CENTER"); window:SetClampedToScreen(true)
    window:SetResizable(true)
    window:SetResizeBounds(760, 460, 1600, 1200)
    window._gamOpaqueBackground = true
    window:SetFrameStrata("DIALOG"); window:SetMovable(true); window:EnableMouse(true)
    window:RegisterForDrag("LeftButton"); window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnMouseDown", function() FinishEditing() end)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    window:SetBackdropColor(0.18, 0.18, 0.20, 1); window:SetBackdropBorderColor(0.65, 0.59, 0.3, 1)
    end
    window:Hide()
    title = Text(window, "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 16, -16)
    if embedded then title:Hide() end
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -1, -1)
    if embedded then close:Hide() end
    close:SetScript("OnClick", function() window:Hide() end)
    scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", embedded and 0 or 12, embedded and 0 or -52)
    scroll:SetPoint("BOTTOMRIGHT", embedded and -22 or -32, embedded and 86 or 110)
    host = CreateFrame("Frame", nil, scroll); host:SetWidth(824); host:SetHeight(1); scroll:SetScrollChild(host)
    scroll:SetScript("OnSizeChanged", LayoutRows)
    status = Text(window); status:SetPoint("BOTTOMLEFT", 16, 54); status:SetPoint("RIGHT", window, "RIGHT", -20, 0); status:SetHeight(48)
    nextButton = Button(window, L("WF_CRAFT_NEXT", "Craft next"), 420, function() if nextAction then nextAction() end end); nextButton:SetPoint("BOTTOMRIGHT", -24, 18)
    stopButton = Button(window, (GAM.L and GAM.L["WF_STOP"] or "Stop"), 74, Plan.Stop); stopButton:SetPoint("RIGHT", nextButton, "LEFT", -8, 0)
    if embedded then
        status:ClearAllPoints(); status:SetPoint("BOTTOMLEFT", 6, 36)
        status:SetPoint("RIGHT", window, "RIGHT", -6, 0); status:SetHeight(44)
        nextButton:ClearAllPoints(); nextButton:SetPoint("BOTTOMLEFT", 6, 4)
        nextButton:SetPoint("BOTTOMRIGHT", -6, 4)
        stopButton:ClearAllPoints(); stopButton:SetPoint("BOTTOMRIGHT", -6, 4)
        window:SetScript("OnShow", function()
            if GAM.QuickBuy and GAM.QuickBuy.RefreshPresentation then GAM.QuickBuy.RefreshPresentation() end
            UI.Refresh()
        end)
        window:SetScript("OnHide", function()
            FinishEditing()
            if GAM.QuickBuy and GAM.QuickBuy.RefreshPresentation then GAM.QuickBuy.RefreshPresentation() end
        end)
        return
    end
    local grip = CreateFrame("Button", nil, window)
    grip:SetSize(20, 20); grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then window:StartSizing("BOTTOMRIGHT") end
    end)
    local function SaveSize()
        window:StopMovingOrSizing()
        Plan.GetData().windowSize = { width = window:GetWidth(), height = window:GetHeight() }
    end
    grip:SetScript("OnMouseUp", SaveSize)
    window:SetScript("OnHide", function() FinishEditing(); SaveSize(); Plan.Stop() end)
    local manager = GAM.UI.WindowManager
    if manager and manager.Register then manager.Register(window, "dialog") end
    if UISpecialFrames then table.insert(UISpecialFrames, window:GetName()) end
end
function UI.Show(strat, patchTag)
    if GAM.UI.MainWindow and GAM.UI.MainWindow.OpenWorkspace then
        return GAM.UI.MainWindow.OpenWorkspace("queue")
    end
    Build()

    window:SetScale((GAM.GetOption and GAM:GetOption("uiScale", 1)) or 1)
    window:Show(); window:Raise(); UI.Refresh()
end
function UI.Hide() if window then window:Hide() end end
function UI.IsShown() return window and window:IsShown() or false end
function UI.IsShoppingVisible() return embedded and viewMode == "shopping" and UI.IsShown() end
function UI.Add(strat, patchTag)
    local workspace = GAM.UI.MainWindow and GAM.UI.MainWindow.OpenWorkspace
    if not workspace then Build() end
    if not FinishEditing() then return false end
    local ok, err = Plan.Add(strat, patchTag)
    Report(ok, err)
    -- Adding intentionally keeps the selected tab. Report the result outside
    -- the queue as well, so a hidden tab cannot swallow success or failure.
    print("|cffffd100[GAM]|r " .. Plan.message)
    if GAM.Log and GAM.Log.Info then GAM.Log.Info("Craft Queue: %s", Plan.message) end
    if workspace then UI.Refresh() else UI.Show(strat, patchTag) end
    return ok, err
end
function UI.Embed(parent) Build(parent) end
function UI.SetEmbeddedTab(tab)
    if viewMode ~= tab then shoppingAwaitingMaterials = nil end
    viewMode = tab
    if window then window:Show(); UI.Refresh() end
    if GAM.QuickBuy and GAM.QuickBuy.RefreshPresentation then GAM.QuickBuy.RefreshPresentation() end
end
function UI.FinishEditing() return FinishEditing() end

-- The Shopping budget depends on the player's gold, which changes outside
-- inventory events (sales, repairs, mail).
local moneyWatcher = CreateFrame("Frame")
if moneyWatcher.RegisterEvent then
    moneyWatcher:RegisterEvent("PLAYER_MONEY")
    moneyWatcher:SetScript("OnEvent", function()
        if UI.IsShoppingVisible() then UI.Refresh() end
    end)
end
