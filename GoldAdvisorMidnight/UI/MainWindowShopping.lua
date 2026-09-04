-- GoldAdvisorMidnight/UI/MainWindowShopping.lua
-- Auctionator shopping-list creation and bag-driven synchronization.
-- Module: GAM.UI.MainWindowShopping

local ADDON_NAME, GAM = ...
local Shopping = {}
GAM.UI.MainWindowShopping = Shopping
GAM.UI.MainWindowV2Shopping = Shopping -- Compatibility alias for pre-refocus callers.

function Shopping.Create(deps)
    deps = deps or {}
    local shoppingSync = {
        active = false,
        stratID = nil,
        patchTag = nil,
        lastSignature = nil,
        pending = false,
    }
    local shoppingSyncFrame

local function BuildAuctionatorShoppingPayload(strat, patchTag)
    if not (Auctionator and Auctionator.API and Auctionator.API.v1 and
            type(Auctionator.API.v1.CreateShoppingList) == "function") then
        print("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_NOT_FOUND"])
        return nil
    end
    if not strat then return nil end
    local canonicalResult = GAM.PricingFacade.CalculateCurrent(
        strat,
        patchTag or GAM.C.DEFAULT_PATCH)
    if not canonicalResult then return nil end

    local addonName  = "GoldAdvisorMidnight"
    local hasConvert = type(Auctionator.API.v1.ConvertToSearchString) == "function"
    local searchStrings = {}
    local signatureParts = {}
    local items = {}

    for _, rm in ipairs(canonicalResult.shoppingReagents or {}) do
        local qty = math.floor(rm.needToBuy or 0)
        if qty > 0 then
            local entry
            local searchData = GAM.Pricing.GetShoppingSearchData(rm.itemID, rm.name)
            if hasConvert then
                local qualityID = (rm.itemID and C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo)
                    and C_TradeSkillUI.GetItemReagentQualityByItemInfo(rm.itemID) or nil
                local searchTerm = {
                    searchString = searchData.searchName or rm.name,
                    quantity = qty,
                    isExact = true,
                }
                if qualityID and qualityID > 0 then searchTerm.tier = qualityID end
                entry = Auctionator.API.v1.ConvertToSearchString(addonName, searchTerm)
            else
                entry = searchData.searchString
            end
            if entry then
                searchStrings[#searchStrings + 1] = entry
                signatureParts[#signatureParts + 1] = entry
                items[#items + 1] = {
                    searchString = entry,
                    itemID = rm.itemID,
                    name = searchData.displayName,
                    quantity = qty,
                    unitPrice = rm.unitPrice,
                }
            end
        end
    end

    table.sort(signatureParts)
    local signature = table.concat(signatureParts, "\031")
    return {
        addonName = addonName,
        listName = GAM.L["AUCTIONATOR_LIST_NAME"],
        canonicalResult = canonicalResult,
        searchStrings = searchStrings,
        items = items,
        signature = signature,
    }
end

local function CreateAuctionatorShoppingList(strat, patchTag, quiet)
    local payload = BuildAuctionatorShoppingPayload(strat, patchTag)
    if not payload then return nil end

    if #payload.searchStrings == 0 and not quiet then
        print("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_NO_ITEMS"])
    end

    Auctionator.API.v1.CreateShoppingList(payload.addonName, payload.listName, payload.searchStrings)
    local quickBuyList = {
        listName = payload.listName,
        entries = payload.items,
        signature = payload.signature,
    }
    if GAM.QuickBuy and GAM.QuickBuy.SetList then
        GAM.QuickBuy.SetList(quickBuyList)
    else
        GAM.quickBuyList = quickBuyList
    end
    if not quiet then
        print(string.format("|cffff8800[GAM]|r " .. GAM.L["MSG_AUCTIONATOR_CREATED"], payload.listName, #payload.searchStrings))
    end
    return payload
end

local function DisableShoppingSync(silent)
    shoppingSync.active = false
    shoppingSync.stratID = nil
    shoppingSync.patchTag = nil
    shoppingSync.lastSignature = nil
    shoppingSync.pending = false
    if shoppingSyncFrame then
        shoppingSyncFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
        shoppingSyncFrame:UnregisterEvent("AUCTION_HOUSE_CLOSED")
    end
    if not silent then
        print("|cffff8800[GAM]|r " .. GAM.L["MSG_SHOPPING_SYNC_STOPPED"])
    end
end

local function RefreshShoppingSync()
    if not shoppingSync.active then return end
    local strat = shoppingSync.stratID and GAM.Importer.GetStratByID(shoppingSync.stratID) or nil
    if not strat then
        DisableShoppingSync(true)
        return
    end

    local payload = BuildAuctionatorShoppingPayload(strat, shoppingSync.patchTag)
    if not payload then
        DisableShoppingSync(true)
        return
    end
    if payload.signature == shoppingSync.lastSignature then
        return
    end

    Auctionator.API.v1.CreateShoppingList(payload.addonName, payload.listName, payload.searchStrings)
    local quickBuyList = {
        listName = payload.listName,
        entries = payload.items,
        signature = payload.signature,
    }
    if GAM.QuickBuy and GAM.QuickBuy.SetList then
        GAM.QuickBuy.SetList(quickBuyList)
    else
        GAM.quickBuyList = quickBuyList
    end
    shoppingSync.lastSignature = payload.signature
    if type(deps.OnRefresh) == "function" then
        deps.OnRefresh()
    end
end

local function EnsureShoppingSyncFrame()
    if shoppingSyncFrame then return end
    shoppingSyncFrame = CreateFrame("Frame")
    shoppingSyncFrame:SetScript("OnEvent", function(_, event)
        if event == "BAG_UPDATE_DELAYED" then
            if shoppingSync.pending then return end
            shoppingSync.pending = true
            C_Timer.After(0.15, function()
                shoppingSync.pending = false
                RefreshShoppingSync()
            end)
        elseif event == "AUCTION_HOUSE_CLOSED" then
            DisableShoppingSync(true)
        end
    end)
end

local function ToggleShoppingSync(strat, patchTag)
    if not strat then return end
    if shoppingSync.active and shoppingSync.stratID == strat.id and shoppingSync.patchTag == (patchTag or GAM.C.DEFAULT_PATCH) then
        DisableShoppingSync()
        return
    end

    local payload = CreateAuctionatorShoppingList(strat, patchTag)
    if not payload then return end

    EnsureShoppingSyncFrame()
    shoppingSync.active = true
    shoppingSync.stratID = strat.id
    shoppingSync.patchTag = patchTag or GAM.C.DEFAULT_PATCH
    shoppingSync.lastSignature = payload.signature
    shoppingSync.pending = false
    shoppingSyncFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    shoppingSyncFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
    print(string.format("|cffff8800[GAM]|r Auctionator shopping sync armed for '%s'.", strat.stratName or "strategy"))
end

    return {
        CreateShoppingList = CreateAuctionatorShoppingList,
        ToggleSync = ToggleShoppingSync,
        DisableSync = DisableShoppingSync,
    }
end
