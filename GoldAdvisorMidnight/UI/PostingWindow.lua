-- GoldAdvisorMidnight/UI/PostingWindow.lua
-- The Posting workspace tab: tick rows, edit price or quantity, one button.
-- Rules are in Settings; details are in tooltips.
local ADDON_NAME, GAM = ...
local function L(key, fallback, ...)
    local value = (GAM.L and GAM.L[key]) or fallback
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end
GAM.UI = GAM.UI or {}
local UI = {}
GAM.UI.PostingWindow = UI

local host, scroll, content, hint, status, button, header, settingsButton
local itemRows, auctionRows = {}, {}
local ahSection, emptyText, otherSection
local focusBox
local themed = {}   -- font strings recolored from the theme on each refresh
local Common = GAM.UI.MainWindowCommon

-- Row status -> the shared status dot (green ready, amber check, red problem, grey waiting).
local DOT_KIND = {
    ok = "ok", warn = "warn", bad = "bad", bank = "neutral", mail = "neutral", noprice = "neutral",
    top = "ok", higher = "warn", matched = "warn", under = "bad", leave = "neutral", unknown = "neutral",
}
local function DotTexture(status) return Common.STATUS_TEXTURES[DOT_KIND[status] or "neutral"] end
local function Themed(fs, role) themed[#themed + 1] = { fs, role }; return fs end
local function ApplyThemeColors()
    for _, entry in ipairs(themed) do entry[1]:SetTextColor(unpack(Common.ThemeColor(entry[2]))) end
end

local function Money(copper)
    if not copper then return "—" end
    return GAM.Pricing and GAM.Pricing.FormatPrice and GAM.Pricing.FormatPrice(copper) or tostring(copper)
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
local function Age(ts)
    if not ts then return L("PT_AGE_UNKNOWN", "unknown") end
    local seconds = math.max(0, (time and time() or 0) - ts)
    if seconds < 120 then return L("PT_AGE_NOW", "just now") end
    if seconds < 7200 then return L("PT_AGE_MIN", "%dm ago", math.floor(seconds / 60)) end
    return L("PT_AGE_HOURS", "%dh ago", math.floor(seconds / 3600))
end
local function Percent(value) return string.format("%d%%", math.floor((value or 0) * 100 + 0.5)) end

local function Text(parent, size, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    local face, _, flags = fs:GetFont()
    if face then fs:SetFont(face, size or 11, flags) end
    fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    return fs
end

-- Parses "52.40", "52", "52g 40s" or "40s" into copper.
function UI.ParseMoney(text)
    text = tostring(text or ""):lower():gsub(",", ".")
    local g, s = text:match("^%s*(%d+)%s*g%s*(%d*)%s*s?%s*$")
    if g then return tonumber(g) * 10000 + (tonumber(s) or 0) * 100 end
    s = text:match("^%s*(%d+)%s*s%s*$")
    if s then return tonumber(s) * 100 end
    local value = tonumber(text)
    return value and math.floor(value * 10000 + 0.5) or nil
end

-- ===== Tooltips =====

local function Tip(owner, title, lines, note)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 0.82, 0, 1, true)
    for _, line in ipairs(lines or {}) do
        GameTooltip:AddDoubleLine(line[1], line[2], 0.8, 0.8, 0.85, 1, 1, 1)
    end
    if note then GameTooltip:AddLine(note, 0.85, 0.85, 0.85, true) end
    GameTooltip:Show()
end

local function StatusTip(owner, row)
    local opts = GAM.Posting.Options()
    local s, f = row.status, row.flags or {}
    if s == "bank" then
        return Tip(owner, L("PT_TIP_BANK", "In your bank"), { { L("PT_BANK", "Bank"), row.bank } },
            L("PT_TIP_BANK_NOTE", "Take them out of the bank to post. GAM only posts from bags."))
    elseif s == "mail" then
        return Tip(owner, L("PT_TIP_MAIL", "In your mailbox"), { { L("PT_RETURNED", "Returned"), row.mail } },
            L("PT_TIP_MAIL_NOTE", "Expired or cancelled items. Collect them from a mailbox, then post them here."))
    elseif s == "noprice" then
        return Tip(owner, L("PT_TIP_NOPRICE", "No price yet"), nil,
            L("PT_TIP_NOPRICE_NOTE", "Open the Auction House so GAM can check the price, or type one."))
    elseif s == "bad" then
        local loss = (row.breakEven - row.price) * (1 - opts.ahCut)
        local next = row.tiers[2] and row.tiers[2].price >= row.breakEven and row.tiers[2].price
        return Tip(owner, L("PT_TIP_BELOW", "Below break-even"), {
            { L("PT_LOSS_EACH", "Loss each"), Money(loss) },
            { L("PT_LOSS_FOR", "Loss for %d", row.qty), Money(loss * row.qty) },
        }, (next and L("PT_TIP_NEXT_ABOVE", "The next price, %s, is above break-even. Type it to match. ", Money(next)) or "")
            .. (row.on and L("PT_TIP_TICKED_MARKET", "Ticked: it will post at this price.")
                or L("PT_TIP_TICK_MARKET", "Tick the row to post at market anyway.")))
    end
    local notes = {}
    if f.unreliable then
        notes[#notes + 1] = row.normal and L("PT_TIP_UNRELIABLE", "The only listings are far above this item's usual price (%s) in a very thin market, so GAM does not match them. It starts unticked at the usual price.", Money(row.normal))
            or L("PT_TIP_UNRELIABLE_NONE", "The only listings look far above this item's usual price, and GAM has no usual price yet. Type a price to post it.")
    end
    if f.covered then
        local opts = GAM.Posting.Options()
        notes[#notes + 1] = L("PT_TIP_COVERED", "Already listed: %d, about %s sell in %dh. It starts unticked so listings do not pile up; tick it to post more.",
            row.listed or 0, tostring(math.max(1, math.ceil((row.soldPerDay or 0) * opts.duration / 24))), opts.duration)
    end
    if f.streak then
        local opts = GAM.Posting.Options()
        if opts.streakLimit > 0 and (row.streak or 0) >= opts.streakLimit then
            notes[#notes + 1] = L("PT_TIP_STREAK", "Expired %d times in a row, so it starts unticked. Try a lower price or a smaller quantity.", row.streak)
        else
            notes[#notes + 1] = L("PT_TIP_MAX_EXPIRES", "Expired %d times in the last 14 days, so it starts unticked. Try a lower price or a smaller quantity.", row.recentExpires or 0)
        end
    end
    if f.noCompetition then notes[#notes + 1] = L("PT_TIP_NO_COMPETITION", "No competing listings.") end
    if f.thin then notes[#notes + 1] = L("PT_TIP_THIN", "Only %d listed at %s; the next price is %s. Type it to match instead.", row.tiers[1].qty, Money(row.tiers[1].price), Money(row.tiers[2].price)) end
    if f.lowMargin then notes[#notes + 1] = L("PT_TIP_LOW_MARGIN", "Only %s over break-even (warning under %s).", Percent(row.price / row.breakEven - 1), Percent(opts.marginWarn)) end
    if row.refreshing then notes[#notes + 1] = L("PT_TIP_REFRESHING", "Still checking the price. You can post now at the last price (%s).", Age(row.ts)) end
    if #notes == 0 then
        return Tip(owner, L("PT_TIP_READY", "Ready"), nil,
            row.breakEven and L("PT_TIP_OVER_BE", "%s over break-even.", Percent(row.price / row.breakEven - 1)) or nil)
    end
    Tip(owner, L("PT_TIP_CHECK", "Check before posting"), nil, table.concat(notes, " "))
end

local function RowTip(owner, row, part)
    local opts = GAM.Posting.Options()
    if part == "item" then
        local lines = {
            { L("PT_BREAK_EVEN", "Break-even"), Money(row.breakEven) },
            { L("PT_YOUR_COST", "Your cost"), row.cost and (Money(row.cost) .. " (" .. L("PT_RECORDED", "%s recorded", Percent(row.costShare)) .. ")")
                or L("PT_NO_PURCHASES", "no purchases recorded") },
            { L("PT_IN_BAGS", "In bags"), row.bags },
        }
        if row.bank > 0 then lines[#lines + 1] = { L("PT_BANK", "Bank"), row.bank } end
        if row.mail > 0 then lines[#lines + 1] = { L("PT_MAIL", "Mail"), row.mail } end
        if row.paid then lines[#lines + 1] = { L("PT_PAID", "You paid"), Money(math.floor(row.paid)) } end
        return Tip(owner, ItemName(row.itemID), lines, row.other
            and (row.fromPaid and L("PT_TIP_OTHER_PAID", "Found in your bags or bank; not from your Craft Queue. You bought these, so break-even is what you paid plus the Auction House cut. It starts unticked in case it is one of your materials.")
                or L("PT_TIP_OTHER_NOTE", "Found in your bags or bank; not from your Craft Queue. Break-even is the current estimate of the strategy that makes it. It starts unticked in case it is one of your materials."))
            or L("PT_TIP_ITEM_NOTE", "Made by your Craft Queue. Units reserved for a queued step are not offered."))
    elseif part == "price" then
        local t1, t2 = row.tiers[1], row.tiers[2]
        if not t1 then
            return Tip(owner, L("PT_TIP_NO_COMPETITION", "No competing listings."), nil,
                L("PT_TIP_EMPTY_PRICE", "Starting price is the higher of the last market price and break-even + %s.", Percent(opts.marginWarn)))
        end
        local lines = { { L("PT_LOWEST", "Lowest listing"), Money(t1.price) .. (t1.unknown and "" or (" · " .. L("PT_LISTED", "%d listed", t1.qty))) } }
        if t2 then lines[#lines + 1] = { L("PT_NEXT_PRICE", "Next price"), Money(t2.price) .. " · " .. L("PT_LISTED", "%d listed", t2.qty) } end
        lines[#lines + 1] = { L("PT_PRICES_FROM", "Prices from"), Age(row.ts) .. (row.refreshing and (" " .. L("PT_REFRESHING", "(refreshing)")) or "") }
        return Tip(owner, L("PT_PRICE_EACH", "Price each"), lines,
            L("PT_TIP_PRICE_NOTE", "Starts at the lowest listing; GAM never undercuts. At an equal price the newest listing sells first. Type gold, e.g. 52.40."))
    elseif part == "qty" then
        return Tip(owner, L("PT_QUANTITY", "Quantity"), {
            { L("PT_IN_BAGS", "In bags"), row.bags },
            { L("PT_TSM_SOLD", "TSM sold/day"), row.soldPerDay and string.format("%.1f", row.soldPerDay) or L("PT_UNAVAILABLE", "unavailable") },
            { L("PT_STARTING_QTY", "Starting quantity"), row.recQty },
        }, L("PT_TIP_QTY_NOTE", "Type any amount up to what is in your bags."))
    elseif part == "max" then
        return Tip(owner, L("PT_MAX", "Max"), { { L("PT_IN_BAGS", "In bags"), row.bags } },
            L("PT_TIP_MAX_NOTE", "Post everything in your bags. Posting more than sells before the auction ends risks losing deposits."))
    elseif part == "profit" then
        local lines = {
            { L("PT_AFTER_CUT", "After AH cut"), Money(row.price * (1 - opts.ahCut) * row.qty) },
        }
        if row.breakEven then lines[#lines + 1] = { L("PT_BE_COST", "Break-even cost"), Money(row.breakEven * (1 - opts.ahCut) * row.qty) } end
        local deposit = GAM.Posting.Deposit(row.itemID, row.qty, opts.duration)
        if deposit then lines[#lines + 1] = { L("PT_DEPOSIT_H", "Deposit (%dh)", opts.duration), Money(deposit) } end
        if row.cost then lines[#lines + 1] = { L("PT_VS_PAID", "vs. what you paid"), Money((row.price * (1 - opts.ahCut) - row.cost) * row.qty) } end
        return Tip(owner, L("PT_EST_PROFIT", "Est. profit"), lines,
            L("PT_TIP_PROFIT_NOTE", "(price − break-even) × quantity, after the AH cut. The deposit is refunded if it sells."))
    elseif part == "tick" then
        return Tip(owner, row.on and L("PT_WILL_POST", "Will be posted") or L("PT_NOT_POSTING", "Not posting"), nil,
            row.status == "bad" and L("PT_TIP_TICK_MARKET", "Tick the row to post at market anyway.")
                or L("PT_TIP_UNTICK", "Untick to skip this item for now."))
    end
    return StatusTip(owner, row)
end

local function AuctionTip(owner, auction)
    local opts = GAM.Posting.Options()
    local lines = {
        { L("PT_YOUR_PRICE", "Your price"), Money(auction.price) },
        { L("PT_LOWEST_NOW", "Lowest now"), auction.alone and L("PT_ONLY_SELLER", "only you") or Money(auction.lowest) },
        { L("PT_DEPOSIT_LOST", "Deposit lost if cancelled"), Money(GAM.PostingModel.CancelCost(auction)) },
    }
    local afford = auction.cantAfford and (" " .. L("PT_TIP_CANT_AFFORD", "You need %s to cancel it.", Money(auction.cancelCost))) or ""
    if auction.breakEven then lines[#lines + 1] = { L("PT_BREAK_EVEN", "Break-even"), Money(auction.breakEven) } end
    if auction.ahead then lines[#lines + 1] = { L("PT_UNITS_AHEAD", "Units ahead of yours"), auction.ahead .. (auction.aheadExact and "" or "+") } end
    local s = auction.state
    if s == "unknown" then
        return Tip(owner, L("PT_CHECKING_LOWEST", "Checking the lowest price"), lines,
            GAM.ahOpen and L("PT_TIP_CHECKING_LOWEST", "GAM is checking the current lowest listing for this item.")
                or L("PT_TIP_LOWEST_AH", "Open the Auction House so GAM can check the current lowest listing."))
    end
    if s == "top" then
        return Tip(owner, L("PT_FIRST", "You are first in line"), lines, auction.alone
            and L("PT_TIP_ALONE", "No other seller lists this item right now. Nothing to do.")
            or L("PT_NOTHING_TO_DO", "Nothing to do."))
    end
    if s == "higher" then
        local worth = GAM.PostingModel.CancelWorthIt(auction, opts)
        return Tip(owner, L("PT_HIGHER", "Room to sell higher"), lines,
            L("PT_TIP_HIGHER", "You are the cheapest by %s: the next seller is at %s.", Money(auction.lowest - auction.price), Money(auction.lowest)) .. " "
            .. (worth and L("PT_TIP_HIGHER_CANCEL", "Cancel and repost at %s; the extra gold beats the lost and new deposits.", Money(auction.lowest))
                or L("PT_TIP_HIGHER_SMALL", "The extra gold would not cover the lost and new deposits, so it is not ticked."))
            .. afford)
    end
    if s == "leave" then
        return Tip(owner, L("PT_LEAVE", "Leave it"), lines,
            L("PT_TIP_LEAVE", "Reposting at the new lowest price would be below break-even. It may still sell, or it expires and comes back by mail."))
    end
    local why = s == "matched" and L("PT_TIP_MATCHED", "Someone listed at your price after you, so theirs sells first.")
        or L("PT_TIP_UNDER", "Undercut by %s.", Money(auction.price - auction.lowest))
    local worth = GAM.PostingModel.CancelWorthIt(auction, opts)
    if s == "matched" and GAM.PostingModel.MatchedWorthIt(auction) and GAM.PostingModel.RecentlyCancelled(auction, auction.now) then
        local minutes = math.max(1, math.floor(((auction.now or 0) - auction.lastCancel) / 60))
        local ago = minutes >= 60 and L("PT_HOURS_AGO", "%dh", math.floor(minutes / 60)) or L("PT_MINUTES_AGO", "%dm", minutes)
        return Tip(owner, L("PT_MATCHED", "Posted after you"), lines, why .. " "
            .. L("PT_TIP_RECANCEL", "You already cancelled and reposted this %s ago and others keep matching your price, so it is not ticked again for an hour (each round loses a deposit). You can still tick it.", ago)
            .. afford)
    end
    if s == "matched" and not GAM.PostingModel.MatchedWorthIt(auction) then
        return Tip(owner, L("PT_MATCHED", "Posted after you"), lines, why .. " "
            .. L("PT_TIP_MATCHED_SMALL", "Only %d ahead of your %d: they should sell soon, so it is not ticked. You can still tick it.",
                auction.ahead or 0, auction.qty or 0) .. afford)
    end
    Tip(owner, s == "matched" and L("PT_MATCHED", "Posted after you") or L("PT_UNDERCUT", "Undercut"), lines,
        why .. " " .. (worth and L("PT_TIP_CANCEL", "Cancel and repost at %s; the items come back by mail first.", Money(auction.lowest))
            or L("PT_TIP_CANCEL_COST", "The lost deposit is over %s of the auction's value, so it is not ticked. You can still tick it.", Percent(opts.cancelDepositPct)))
        .. afford)
end

-- ===== Rows =====

local function Hover(frame, show)
    frame:SetScript("OnEnter", show)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function SectionHeader(parent, label, tipTitle, tipBody)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(22)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND"); frame.bg:SetAllPoints()
    frame.label = Themed(Text(frame, 11), "accent"); frame.label:SetPoint("LEFT", 6, 0); frame.label:SetText(label)
    frame.caption = Themed(Text(frame, 10), "muted"); frame.caption:SetPoint("RIGHT", -6, 0); frame.caption:SetJustifyH("RIGHT")
    frame.caption:SetPoint("LEFT", frame.label, "RIGHT", 8, 0)
    if tipBody then
        frame:EnableMouse(true)
        Hover(frame, function(self) Tip(self, tipTitle or label, nil, tipBody) end)
    end
    return frame
end

local function EditBox(parent, width, numeric)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 20); box:SetAutoFocus(false); box:SetJustifyH("RIGHT")
    if numeric then box:SetNumeric(true) end
    local face, _, flags = box:GetFont()
    if face then box:SetFont(face, 11, flags) end
    box:SetScript("OnEditFocusGained", function(self) focusBox = self; self:HighlightText() end)
    box:SetScript("OnEscapePressed", function(self) self.cancel = true; self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local function ItemRow(index)
    if itemRows[index] then return itemRows[index] end
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(26)
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
    row.band = index % 2 == 1
    row.tick = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.tick:SetSize(22, 22); row.tick:SetPoint("LEFT", 0, 0)
    row.tick:SetScript("OnClick", function(self)
        GAM.Posting.SetEdit(row.data.itemID, "on", self:GetChecked() and true or false)
    end)
    Hover(row.tick, function(self) RowTip(self, row.data, "tick") end)
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(16, 16); row.icon:SetPoint("LEFT", 24, 0)
    row.name = Themed(Text(row), "body"); row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.nameHit = CreateFrame("Frame", nil, row); row.nameHit:SetPoint("TOPLEFT", row.icon, "TOPLEFT")
    row.nameHit:SetPoint("BOTTOMRIGHT", row.name, "BOTTOMRIGHT")
    Hover(row.nameHit, function(self) RowTip(self, row.data, "item") end)
    row.dot = row:CreateTexture(nil, "ARTWORK"); row.dot:SetSize(12, 12); row.dot:SetPoint("RIGHT", -4, 0)
    row.dotHit = CreateFrame("Frame", nil, row); row.dotHit:SetAllPoints(row.dot)
    Hover(row.dotHit, function(self) RowTip(self, row.data, "status") end)
    row.profit = Text(row); row.profit:SetJustifyH("RIGHT"); row.profit:SetWidth(82)
    row.profit:SetPoint("RIGHT", row.dot, "LEFT", -6, 0)
    row.profitHit = CreateFrame("Frame", nil, row); row.profitHit:SetAllPoints(row.profit)
    Hover(row.profitHit, function(self) RowTip(self, row.data, "profit") end)
    row.max = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.max:SetSize(34, 18); row.max:SetText(L("PT_MAX", "Max")); row.max:SetPoint("RIGHT", row.profit, "LEFT", -6, 0)
    local maxFont = row.max:GetFontString()
    if maxFont then local face, _, flags = maxFont:GetFont(); if face then maxFont:SetFont(face, 10, flags) end end
    if Common.StyleComfortableButton then Common.StyleComfortableButton(row.max, false) end
    row.max:SetScript("OnClick", function() GAM.Posting.SetEdit(row.data.itemID, "qty", row.data.bags) end)
    Hover(row.max, function(self) RowTip(self, row.data, "max") end)
    row.qty = EditBox(row, 38, true); row.qty:SetPoint("RIGHT", row.max, "LEFT", -4, 0)
    row.qty:SetScript("OnEditFocusLost", function(self)
        focusBox = nil
        if not self.cancel then
            local value = tonumber(self:GetText())
            if value and value > 0 then GAM.Posting.SetEdit(row.data.itemID, "qty", math.floor(value)) end
        end
        self.cancel = nil
        UI.Refresh()
    end)
    Hover(row.qty, function(self) RowTip(self, row.data, "qty") end)
    row.price = EditBox(row, 62, false); row.price:SetPoint("RIGHT", row.qty, "LEFT", -8, 0)
    row.price:SetScript("OnEditFocusLost", function(self)
        focusBox = nil
        if not self.cancel then
            local copper = UI.ParseMoney(self:GetText())
            if copper and copper > 0 then GAM.Posting.SetEdit(row.data.itemID, "price", GAM.Posting.RoundPrice(copper)) end
        end
        self.cancel = nil
        UI.Refresh()
    end)
    Hover(row.price, function(self) RowTip(self, row.data, "price") end)
    row.name:SetPoint("RIGHT", row.price, "LEFT", -6, 0)
    itemRows[index] = row
    return row
end

local function AuctionRow(index)
    if auctionRows[index] then return auctionRows[index] end
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(32)
    row.tick = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.tick:SetSize(22, 22); row.tick:SetPoint("LEFT", 0, 0)
    row.tick:SetScript("OnClick", function(self) GAM.Posting.SetCancel(row.data.auctionID, self:GetChecked()) end)
    Hover(row.tick, function(self) AuctionTip(self, row.data) end)
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(16, 16); row.icon:SetPoint("TOPLEFT", 24, -2)
    row.name = Themed(Text(row), "body"); row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 4, 0); row.name:SetPoint("RIGHT", -24, 0)
    row.detail = Themed(Text(row, 10), "muted"); row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2); row.detail:SetPoint("RIGHT", -24, 0)
    row.dot = row:CreateTexture(nil, "ARTWORK"); row.dot:SetSize(12, 12); row.dot:SetPoint("RIGHT", -4, 0)
    row:EnableMouse(true)
    Hover(row, function(self) AuctionTip(self, row.data) end)
    auctionRows[index] = row
    return row
end

-- ===== Refresh =====

local function Place(frame, y, height)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    frame:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    if height then frame:SetHeight(height) end
    return y + (height or frame:GetHeight())
end

function UI.Refresh()
    -- Visible, not just shown: the tab stays shown inside a closed window.
    if not host or not host:IsVisible() then return end
    if focusBox then return end
    local posting = GAM.Posting
    local opts = posting.Options()
    local rows = posting.Rows()
    local auctions, loaded = posting.Auctions()
    content:SetWidth(math.max(1, scroll:GetWidth()))
    ApplyThemeColors()
    -- Auctions keep expiring while the player is away: point to the setting.
    local suggest, usual, expires = posting.DurationHint()
    settingsButton.info = suggest and { suggest = suggest, usual = usual, expires = expires, current = opts.duration }
    if suggest then
        hint:SetText(Common.ThemeHex("accent") .. L("PT_DURATION_HINT",
            "Your auctions often expire before you're back. Try %dh auctions in Settings › Posting.", suggest) .. "|r")
        settingsButton:Show()
        hint:SetPoint("RIGHT", settingsButton, "LEFT", -6, 0)
    else
        hint:SetText(L("PT_HINT", "Tick what to post or cancel, change price or quantity if you like, then press the button."))
        settingsButton:Hide()
        hint:SetPoint("RIGHT", host, "RIGHT", -6, 0)
    end
    local band = Common.ThemeColor("band")
    local function Band(texture, on) texture:SetColorTexture(band[1], band[2], band[3], on and (band[4] or 1) or 0) end
    Band(otherSection.bg, true); Band(ahSection.bg, true)
    local y = 0
    otherSection:Hide()
    for index, data in ipairs(rows) do
        if data.other and not otherSection:IsShown() then
            otherSection:Show()
            y = Place(otherSection, y + 8, 22)
        end
        local row = ItemRow(index)
        row.data = data
        row:Show()
        y = Place(row, y, 26)
        Band(row.bg, row.band)
        -- Nothing to tick for bank-only or mail-only rows; the dot explains why.
        row.tick:SetShown(data.bags > 0); row.tick:SetChecked(data.on)
        row.icon:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(data.itemID) or 134400)
        local muted = Common.ThemeHex("muted")
        local extra = ""
        if data.mail > 0 then extra = extra .. " " .. muted .. "+" .. data.mail .. " " .. L("PT_MAIL_SHORT", "mail") .. "|r" end
        if data.bank > 0 then extra = extra .. " " .. muted .. "+" .. data.bank .. " " .. L("PT_BANK_SHORT", "bank") .. "|r" end
        row.name:SetText(ItemName(data.itemID) .. " " .. muted .. "(" .. data.bags .. ")|r" .. extra)
        row.name:SetAlpha((data.on or data.bags == 0) and 1 or 0.6)
        local editable = data.bags > 0
        row.price:SetShown(editable); row.qty:SetShown(editable); row.max:SetShown(editable)
        if editable then
            row.price:SetText(data.price and string.format("%.2f", data.price / 10000) or "")
            row.qty:SetText(tostring(data.qty))
            row.max:SetEnabled(data.qty ~= data.bags)
        end
        local profit = editable and data.price and data.breakEven and GAM.PostingModel.Profit(data.price, data.breakEven, data.qty, opts)
        row.profit:SetText(profit and Common.SignedMoney(profit, true) or "—")
        row.dot:SetTexture(DotTexture(data.status))
    end
    for index = #rows + 1, #itemRows do itemRows[index]:Hide() end

    emptyText:SetShown(#rows == 0)
    if #rows == 0 then
        y = Place(emptyText, y + 4, 36)
    end

    y = y + 12
    y = Place(ahSection, y, 22)
    local counts = { under = 0 }
    for _, auction in ipairs(auctions) do
        if auction.state == "under" or auction.state == "matched" then counts.under = counts.under + 1 end
    end
    ahSection.recheck:SetEnabled(GAM.ahOpen and true or false)
    ahSection.caption:SetText(not opts.checkAuctions and L("PT_AUCTIONS_OFF", "Checking your auctions is off (Settings › Posting).")
        or not GAM.ahOpen and not loaded and L("PT_AUCTIONS_OPEN_AH", "Open the Auction House to check your auctions.")
        or GAM.ahOpen and (GAM.Posting.session.auctionsReading or not loaded)
            and L("PT_AUCTIONS_READING", "Reading your auctions...")
        or #auctions == 0 and L("PT_AUCTIONS_NONE", "No auctions of these items.")
        or L("PT_AUCTIONS_SUMMARY", "%d active · %d undercut · tick to cancel and repost", #auctions, counts.under))
    local showAuctions = opts.checkAuctions
    for index, auction in ipairs(showAuctions and auctions or {}) do
        local row = AuctionRow(index)
        row.data = auction
        row:Show()
        y = Place(row, y, 32)
        -- Only auctions worth acting on (and affordable to cancel) show the box.
        local tickable = GAM.PostingModel.Cancellable(auction)
        row.tick:SetShown(tickable); row.tick:SetChecked(auction.on)
        row.icon:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(auction.itemID) or 134400)
        row.name:SetText(ItemName(auction.itemID) .. " |cff999999×" .. auction.qty .. "|r")
        local lowest = auction.lowest and (auction.state == "matched" and ("|cffffc46b" .. L("PT_POSTED_AFTER", "posted after you") .. "|r")
            or auction.state == "top" and ("|cff83e896" .. L("PT_YOURE_FIRST", "you're first") .. "|r")
            or auction.state == "higher" and ("|cffffc46b" .. L("PT_NEXT_HIGHER", "next seller %s higher", Money(auction.lowest - auction.price)) .. "|r")
            or L("PT_LOWER_BY", "%s lower", Common.SignedMoney(auction.lowest - auction.price)))
            or auction.alone and ("|cff83e896" .. L("PT_ONLY_SELLER_ROW", "only seller") .. "|r")
            or (GAM.ahOpen and L("PT_CHECKING_PRICE", "checking price") or L("PT_UNKNOWN_LOWEST", "lowest unknown"))
        local left = auction.timeLeft and (math.floor(auction.timeLeft / 3600) .. "h") or ""
        local aheadText = auction.ahead and ((BreakUpLargeNumbers and BreakUpLargeNumbers(auction.ahead) or tostring(auction.ahead))
            .. (auction.aheadExact and "" or "+")) or nil
        local ahead = auction.ahead and auction.ahead > 0 and (" · " .. L("PT_AHEAD", "%s ahead", aheadText)) or ""
        row.detail:SetText(Money(auction.price) .. " · " .. lowest .. ahead .. (left ~= "" and (" · " .. left) or ""))
        row.dot:SetTexture(DotTexture(auction.state))
    end
    for index = (showAuctions and #auctions or 0) + 1, #auctionRows do auctionRows[index]:Hide() end
    content:SetHeight(math.max(1, y + 6))
    if scroll.ScrollBar then scroll.ScrollBar:SetShown(content:GetHeight() > scroll:GetHeight()) end

    -- Summary and the one button.
    local toPost, toCancel, profit, deposits, lost = 0, 0, 0, 0, 0
    for _, row in ipairs(rows) do
        if row.on and row.bags > 0 and row.qty > 0 and row.price then
            toPost = toPost + 1
            profit = profit + (row.breakEven and GAM.PostingModel.Profit(row.price, row.breakEven, row.qty, opts) or 0)
            deposits = deposits + (posting.Deposit(row.itemID, row.qty, opts.duration) or 0)
        end
    end
    for _, auction in ipairs(showAuctions and auctions or {}) do
        if auction.on then toCancel = toCancel + 1; lost = lost + GAM.PostingModel.CancelCost(auction) end
    end
    local parts = {}
    if toCancel > 0 then parts[#parts + 1] = L("PT_SUMMARY_CANCEL", "%d to cancel (deposits lost %s)", toCancel, Common.SignedMoney(-lost)) end
    if toPost > 0 then parts[#parts + 1] = L("PT_SUMMARY_POST", "%d to post · est. profit %s · deposits %s · %dh", toPost, Common.SignedMoney(profit), Money(deposits), opts.duration) end
    local message = posting.session.message
    status:SetText((message and (Common.ThemeHex("accent") .. message .. "|r\n") or "") .. (#parts > 0 and table.concat(parts, "\n") or (#rows > 0 and L("PT_NOTHING_TICKED", "Nothing ticked.") or "")))
    local total = toPost + toCancel
    local kind, target = posting.NextAction(rows, showAuctions and auctions or {})
    local label
    if posting.IsBusy() then label = L("PT_WAITING", "Waiting for the Auction House...")
    elseif not GAM.ahOpen then label = L("PT_OPEN_AH_BUTTON", "Open the Auction House")
    elseif kind == "confirm" then label = L("PT_CONFIRM_POST", "Confirm post: %s ×%d", ItemName(target.itemID), target.qty)
    elseif kind == "cancel" then label = L("PT_CANCEL_NEXT", "Cancel %s ×%d  (1 of %d)", ItemName(target.itemID), target.qty, total)
    elseif kind == "post" then label = total > 1 and L("PT_POST_NEXT_OF", "Post %s ×%d  (1 of %d)", ItemName(target.itemID), target.qty, total)
        or L("PT_POST_NEXT", "Post %s ×%d", ItemName(target.itemID), target.qty)
    else label = L("PT_NOTHING_TO_POST", "Nothing to post") end
    button:SetText(label)
    button:SetEnabled(kind ~= nil and GAM.ahOpen and not posting.IsBusy())
end

-- Verbose reports slow redraws (Settings: Debug log > Capture level).
if GAM.Log and GAM.Log.Timed then UI.Refresh = GAM.Log.Timed("Posting tab redraw", UI.Refresh) end

function UI.Embed(parent)
    if host then return end
    host = CreateFrame("Frame", nil, parent)
    host:SetAllPoints(parent)
    hint = Themed(Text(host, 11), "muted"); hint:SetPoint("TOPLEFT", 6, -2); hint:SetPoint("RIGHT", -6, 0); hint:SetWordWrap(true)
    hint:SetText(L("PT_HINT", "Tick what to post or cancel, change price or quantity if you like, then press the button."))
    settingsButton = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
    settingsButton:SetSize(70, 18); settingsButton:SetPoint("TOPRIGHT", -6, 0)
    settingsButton:SetText(L("PT_SETTINGS", "Settings"))
    local settingsFont = settingsButton:GetFontString()
    if settingsFont then local face, _, flags = settingsFont:GetFont(); if face then settingsFont:SetFont(face, 10, flags) end end
    if Common.StyleComfortableButton then Common.StyleComfortableButton(settingsButton, false) end
    settingsButton:Hide()
    settingsButton:SetScript("OnClick", function()
        -- Opened once: the prompt rests for a week whatever is chosen.
        GAM.Stock.SnoozeDurationHint()
        if GAM.Settings and GAM.Settings.ShowSection then GAM.Settings.ShowSection("posting") end
        UI.Refresh()
    end)
    Hover(settingsButton, function(self)
        local info = self.info
        if not info then return end
        Tip(self, L("OPT_POST_DURATION", "Auction duration"), nil, L("PT_TIP_DURATION_HINT",
            "In the last 14 days you were usually away about %dh between Auction House visits, longer than your %dh auctions, and %d auctions expired. Longer auctions cost a bigger deposit, but you only lose it if they expire. Opens Settings › Posting; this note then rests for a week.",
            math.floor(info.usual + 0.5), info.current, info.expires))
    end)
    header = CreateFrame("Frame", nil, host); header:SetHeight(16)
    header:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6); header:SetPoint("RIGHT", host, "RIGHT", -28, 0)
    local function Head(text, anchorX, width, justify)
        local fs = Themed(Text(header, 10), "accent"); fs:SetText(text)
        fs:SetJustifyH(justify or "RIGHT"); fs:SetWidth(width); fs:SetPoint("RIGHT", header, "RIGHT", anchorX, 0)
        return fs
    end
    local item = Themed(Text(header, 10), "accent"); item:SetText(L("PT_ITEM", "Item")); item:SetPoint("LEFT", 24, 0)
    Head(L("PT_EST_PROFIT", "Est. profit"), -22, 82)
    Head(L("PT_QTY", "Qty"), -114, 80, "CENTER")
    Head(L("PT_PRICE", "Price"), -200, 62)
    scroll = CreateFrame("ScrollFrame", nil, host, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -24, 76)
    content = CreateFrame("Frame", nil, scroll); content:SetSize(400, 1); scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function() UI.Refresh() end)
    emptyText = Themed(Text(content, 11), "muted"); emptyText:SetWordWrap(true)
    emptyText:SetText(L("PT_EMPTY", "Nothing to post yet. Items your Craft Queue makes appear here."))
    otherSection = SectionHeader(content, L("PT_OTHER_ITEMS", "Other items GAM strategies make"), nil,
        L("PT_TIP_OTHER_SECTION", "Items in your bags or bank that a GAM strategy makes, including ones crafted before tracking. They start unticked. Turn this list off in Settings > Posting."))
    otherSection.caption:SetText(L("PT_OTHER_CAPTION", "tick to post"))
    ahSection = SectionHeader(content, L("PT_ON_AH", "On the Auction House"))
    -- Recheck: re-read your auctions and re-check prices now.
    local recheck = CreateFrame("Button", nil, ahSection, "UIPanelButtonTemplate")
    recheck:SetSize(64, 18); recheck:SetPoint("RIGHT", -4, 0); recheck:SetText(L("PT_RECHECK", "Recheck"))
    local recheckFont = recheck:GetFontString()
    if recheckFont then local face, _, flags = recheckFont:GetFont(); if face then recheckFont:SetFont(face, 10, flags) end end
    if Common.StyleComfortableButton then Common.StyleComfortableButton(recheck, false) end
    recheck:SetScript("OnClick", function() GAM.Posting.Recheck() end)
    Hover(recheck, function(self)
        Tip(self, L("PT_RECHECK", "Recheck"), nil, L("PT_TIP_RECHECK",
            "Re-read your auctions and check the current prices of every item here. Prices are also checked automatically when the Auction House opens."))
    end)
    ahSection.caption:ClearAllPoints()
    ahSection.caption:SetPoint("RIGHT", recheck, "LEFT", -8, 0)
    ahSection.caption:SetPoint("LEFT", ahSection.label, "RIGHT", 8, 0)
    ahSection.recheck = recheck
    status = Themed(Text(host, 11), "body"); status:SetWordWrap(true)
    status:SetPoint("BOTTOMLEFT", 6, 36); status:SetPoint("RIGHT", host, "RIGHT", -6, 0); status:SetHeight(36)
    status:SetJustifyV("BOTTOM")
    button = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
    button:SetHeight(28); button:SetPoint("BOTTOMLEFT", 6, 4); button:SetPoint("BOTTOMRIGHT", -6, 4)
    local common = GAM.UI.MainWindowCommon
    if common and common.StyleComfortableButton then common.StyleComfortableButton(button, true) end
    button:SetScript("OnClick", function()
        if focusBox then focusBox:ClearFocus() end
        GAM.Posting.session.message = nil
        GAM.Posting.DoNext()
        UI.Refresh()
    end)
    host:SetScript("OnShow", function()
        if GAM.ahOpen then
            -- Prices are re-checked on opening only when automatic checks are on.
            if GAM.Posting.AutoScanAllowed() then
                local ids = {}
                for _, row in ipairs(GAM.Posting.Rows()) do ids[#ids + 1] = row.itemID end
                GAM.Posting.RefreshPrices(ids)
            end
            GAM.Posting.QueryOwned()
        end
        UI.Refresh()
    end)
    GAM.Posting.OnChange(UI.Refresh)
end
