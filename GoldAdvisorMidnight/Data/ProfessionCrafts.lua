-- GoldAdvisorMidnight/Data/ProfessionCrafts.lua
-- Shared table for compact per-profession craft fact files.

GAM_PROFESSION_CRAFTS = GAM_PROFESSION_CRAFTS or {}
GAM_RUNTIME_PROFESSION_CRAFTS = GAM_RUNTIME_PROFESSION_CRAFTS or {}

local function CopyItemIDs(itemIDs)
    local copy = {}
    for index, itemID in ipairs(itemIDs or {}) do
        copy[index] = itemID
    end
    return copy
end

local function BuildOutputs(outputs)
    local built = {}
    for index, output in ipairs(outputs or {}) do
        built[index] = {
            itemRef = output.itemRef,
            itemIDs = CopyItemIDs(output.itemIDs),
            baseYieldPerCraft = output.baseAmount,
        }
    end
    return built
end

local function BuildReagents(inputs)
    local built = {}
    for index, input in ipairs(inputs or {}) do
        built[index] = {
            itemRef = input.itemRef,
            itemIDs = CopyItemIDs(input.itemIDs),
            qtyPerCraft = input.amount,
        }
    end
    return built
end

-- Convert reviewed compact craft facts into the canonical runtime strategy
-- shape. Patch facts are authored once and appended after RecipesGenerated.lua.
function GAM_APPEND_RUNTIME_PROFESSION_CRAFTS()
    GAM_RECIPES_GENERATED = GAM_RECIPES_GENERATED or {}

    for _, entry in ipairs(GAM_RUNTIME_PROFESSION_CRAFTS) do
        local profession = assert(entry.profession, "runtime craft profession is required")
        local craft = assert(entry.craft, "runtime craft facts are required")
        local firstInput = assert(craft.inputs and craft.inputs[1],
            tostring(craft.id) .. ": runtime craft requires a primary input")
        local defaultCrafts = craft.defaultCrafts or 1000

        GAM_RECIPES_GENERATED[#GAM_RECIPES_GENERATED + 1] = {
            id = assert(craft.id, "runtime craft id is required"),
            profession = profession,
            stratName = assert(craft.name, tostring(craft.id) .. ": runtime craft name is required"),
            recipeID = craft.recipeID,
            recipeName = craft.recipeName or craft.name,
            patchTag = craft.patchTag,
            defaultStartingAmount = craft.defaultStartingAmount
                or (assert(firstInput.amount, tostring(craft.id) .. ": primary input amount is required")
                    * defaultCrafts),
            defaultCrafts = defaultCrafts,
            formulaProfile = craft.formulaProfile,
            outputs = BuildOutputs(craft.outputs),
            reagents = BuildReagents(craft.inputs),
            sourceTab = craft.sourceTab or profession,
            sourceBlock = craft.sourceBlock,
            calcMode = craft.calcMode or "formula",
            qualityPolicy = craft.qualityPolicy or "normal",
            outputQualityMode = craft.outputQualityMode or "rank_policy",
            notes = craft.notes,
        }
    end
end
