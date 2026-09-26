-- Selected targets are persisted as item identities, never stale bag slots.
local _, GAM = ...
local function L(key, fallback, ...)
    local value = (GAM.L and GAM.L[key]) or fallback
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end
local Plan = GAM.CraftPlan
local VELLUM = 38682

function Plan.PrepareRecipeType(node)
    local api = C_TradeSkillUI
    local info = api and api.GetRecipeInfo and api.GetRecipeInfo(node.recipeID)
    if not info then return true end
    if info.isRecraft then return false, L("WF_RECRAFT_MANUAL", "Recrafting requires an existing equipment target; use the profession window.") end
    if info.isSalvageRecipe then
        local ids = api.GetSalvagableItemIDs and api.GetSalvagableItemIDs(node.recipeID)
        local schematic = api.GetRecipeSchematic and api.GetRecipeSchematic(node.recipeID, false)
        local target
        for _, reagent in ipairs(node.reagents) do
            for _, id in ipairs(ids or {}) do
                if reagent.itemID == id then
                    if target then return false, L("WF_SALVAGE_ONE_INPUT", "Choose one exact input item and rank for this salvage job.") end
                    target = reagent
                end
            end
        end
        if not target or not schematic or target.quantity ~= schematic.quantityMax then
            return false, L("WF_SALVAGE_SELECT_INPUT", "Open this salvage recipe and select a valid input in Details before queuing.")
        end
        node.craftType, node.targetItemID, node.targetQuantity = "salvage", target.itemID, target.quantity
    elseif info.isEnchantingRecipe then
        node.craftType, node.targetItemID, node.targetQuantity = "enchant", VELLUM, 1
        local found
        for _, reagent in ipairs(node.reagents) do if reagent.itemID == VELLUM then found = reagent end end
        if found and found.quantity ~= 1 then return false, L("WF_VELLUM_REQUIRED", "Enchanting requires one vellum per craft.") end
        if not found then node.reagents[#node.reagents + 1] = {itemID = VELLUM, quantity = 1, name = L("WF_VELLUM", "Enchanting Vellum")} end
    end
    return true
end

function Plan.FindCraftTarget(node)
    if not (C_Container and ItemLocation and C_Item) then return nil end
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if item and item.itemID == node.targetItemID and not item.isLocked
                and item.stackCount >= node.targetQuantity then
                local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if node.craftType ~= "enchant" or (C_TradeSkillUI.CanStoreEnchantInItem
                    and C_TradeSkillUI.CanStoreEnchantInItem(C_Item.GetItemGUID(location))) then
                    return location, math.floor(item.stackCount / node.targetQuantity)
                end
            end
        end
    end
end
