-- GoldAdvisorMidnight/UI/StrategyDetailModel.lua
-- Pure projection from the canonical pricing result into base-detail UI values.
-- Module: GAM.UI.StrategyDetailModel

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local Model = {}
GAM.UI.StrategyDetailModel = Model

local function AddThousandsSeparators(text)
    local sign, digits, fraction = tostring(text or ""):match("^([%-]?)(%d+)(%.?%d*)$")
    if not digits then
        return tostring(text or "")
    end
    return sign .. digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        .. (fraction or "")
end

local function FormatQuantity(value)
    local number = tonumber(value)
    if number == nil then
        return "0"
    end
    local rounded = math.floor(number + 0.5)
    if math.abs(number - rounded) < 0.05 then
        return AddThousandsSeparators(tostring(rounded))
    end
    local text = string.format("%.1f", number):gsub("0+$", ""):gsub("%.$", "")
    return AddThousandsSeparators(text)
end

local function FormatPercent(value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    if math.abs(number) <= 1.5 then
        number = number * 100
    end
    local rounded = math.floor(number + 0.5)
    if math.abs(number - rounded) < 0.05 then
        return tostring(rounded) .. "%"
    end
    return string.format("%.1f%%", number)
end

local function GetRootFormula(result)
    local diagnostics = result and result.diagnostics
    if type(diagnostics) ~= "table" then
        return nil
    end
    if type(diagnostics.formula) == "table" then
        return diagnostics.formula
    end
    if type(diagnostics.statUsages) == "table" then
        for _, usage in ipairs(diagnostics.statUsages) do
            if usage.role == "root" then
                return usage
            end
        end
        return diagnostics.statUsages[1]
    end
    return nil
end

local function BuildStatsCaption(result)
    local formula = GetRootFormula(result)
    if type(formula) ~= "table" then
        return nil
    end

    local parts = {}
    local multicraft = FormatPercent(formula.mcPercent)
    if multicraft and formula.supportsMulticraft ~= false then
        parts[#parts + 1] = "MC " .. multicraft
    end
    local resourcefulness = FormatPercent(formula.resPercent)
    if resourcefulness and formula.supportsResourcefulness ~= false then
        parts[#parts + 1] = "Res " .. resourcefulness
    end
    if #parts == 0 then
        return nil
    end

    local pricingMode = result.pricingMode or formula.pricingMode
    if pricingMode == "exhaust_materials" and result.effectiveCrafts ~= nil then
        parts[#parts + 1] = string.format("%s -> %s crafts",
            FormatQuantity(result.crafts or formula.crafts or 0),
            FormatQuantity(result.recommendedCrafts
                or math.floor(tonumber(result.effectiveCrafts) or 0)))
    elseif pricingMode == "fixed_crafts" then
        parts[#parts + 1] = "Fixed Crafts"
    end

    return table.concat(parts, ", ")
end

local function BuildStatsTooltip(result)
    local formula = GetRootFormula(result)
    if type(formula) ~= "table" then
        return nil
    end

    local source = tostring(formula.statSource or "")
    local lines = { "Craft stats used for this estimate." }
    if source == "workbook-default" or source == "manual" or formula.statFallbackReason then
        lines[#lines + 1] = "Live recipe stats were unavailable, so saved fallback values were used."
    elseif source ~= "" then
        lines[#lines + 1] = "Using stats captured from this recipe."
    end
    if formula.crafterUID then
        local crafter = formula.crafterName or formula.crafterUID
        local suffix = formula.crossCharacter and " (saved)" or " (current character)"
        lines[#lines + 1] = "Crafter: " .. tostring(crafter) .. suffix
    end
    if formula.supportsMulticraft ~= false and formula.mcPercent ~= nil then
        lines[#lines + 1] = "Multicraft " .. tostring(FormatPercent(formula.mcPercent) or "0%")
            .. "; extra items " .. tostring(FormatPercent(formula.mcExtra) or "0%")
    end
    if formula.supportsResourcefulness ~= false and formula.resPercent ~= nil then
        lines[#lines + 1] = "Resourcefulness " .. tostring(FormatPercent(formula.resPercent) or "0%")
            .. "; save bonus " .. tostring(FormatPercent(formula.resExtra) or "0%")
    end
    if result.pricingMode == "exhaust_materials" and result.effectiveCrafts ~= nil then
        lines[#lines + 1] = "Conservative whole-craft plan "
            .. FormatQuantity(result.recommendedCrafts
                or math.floor(tonumber(result.effectiveCrafts) or 0))
            .. "; expected-value attempts " .. FormatQuantity(result.effectiveCrafts)
    end
    return table.concat(lines, "\n")
end

local function BuildGearCaption(result)
    local requested = tostring(result and result.gearModeRequested or "auto")
    local resolved = tostring(result and result.gearModeResolved or "current")
    local labels = {
        auto = GAM.L and GAM.L["GEAR_MODE_AUTO"] or "Auto",
        multicraft = GAM.L and GAM.L["GEAR_MODE_MC"] or "Multicraft",
        resourcefulness = GAM.L and GAM.L["GEAR_MODE_RES"] or "Resourcefulness",
        current = "Current setup",
    }
    if result and (result.gearPresetMissing or result.gearStatValidity == "unobserved") then
        return string.format((GAM.L and GAM.L["UI_GEAR_FALLBACK"] or "%s (fallback stats)"), labels[requested] or requested)
    end
    if requested == "auto" then
        if resolved == "current" then
            return "Auto (current gear)"
        end
        return labels.auto .. " → " .. (labels[resolved] or resolved)
    end
    return labels[resolved] or resolved
end

local function BuildGearTooltip(result)
    if result and (result.gearPresetMissing or result.gearStatValidity == "unobserved") then
        return (GAM.L and GAM.L["UI_GEAR_FALLBACK_TIP"] or "No saved set for this profession and gear mode. Equip the set, open any recipe of this profession, and save it from Stat Gear. This estimate uses fallback stats until then.")
    end
    if result and result.gearStatValidity == "legacy" then
        return (GAM.L and GAM.L["UI_GEAR_LEGACY_TIP"] or "This estimate uses a legacy recipe capture whose equipment identity is unknown. Save the profession set before queue execution.")
    end
    if result and result.gearModeRequested == "auto" then
        return BuildGearCaption(result) .. "\n" .. (GAM.L and GAM.L["UI_GEAR_AUTO_TIP"] or "Auto compares the saved Multicraft and Resourcefulness setups and uses the one with more profit.")
    end
    return "This estimate uses the selected saved gear setup for this recipe."
end

local function BuildCrafterCaption(result)
    local formula = GetRootFormula(result)
    if type(formula) ~= "table" or not formula.crafterUID then
        return nil
    end
    local crafter = formula.crafterName or formula.crafterUID
    if formula.crossCharacter then
        return tostring(crafter) .. " (cached)"
    end
    return tostring(crafter)
end

local function DescribeNodeBonus(label, bucket)
    if type(bucket) ~= "table" then
        return nil
    end
    local extra = tonumber(bucket.extra) or 0
    if extra <= 0 then
        return label .. " unchanged"
    end
    return label .. " +" .. tostring(FormatPercent(extra) or "0%")
end

local function BuildNodeBonusCaption(result)
    local formula = GetRootFormula(result)
    local details = formula and formula.nodeBonusDetails
    if type(details) ~= "table" then
        return nil
    end

    if details.status == "not-captured" then
        return "Not updated yet — using saved defaults"
    end
    if details.status == "mapping-unavailable" then
        return "No saved recipe bonus data"
    end
    if details.status == "recipe-unavailable" then
        return "Recipe details unavailable"
    end

    local parts = {}
    local multicraft = DescribeNodeBonus("MC extra", details.multicraft)
    local resourcefulness = DescribeNodeBonus("Res save", details.resourcefulness)
    if multicraft then parts[#parts + 1] = multicraft end
    if resourcefulness then parts[#parts + 1] = resourcefulness end
    if #parts == 0 then
        return "No specialization bonuses apply"
    end
    return table.concat(parts, "; ")
end

local function AddNodeTooltipBucket(lines, label, bucket)
    if type(bucket) ~= "table" then
        return
    end
    local nodes = bucket.nodes or {}
    if #nodes == 0 then
        lines[#lines + 1] = label .. ": unchanged"
        return
    end

    lines[#lines + 1] = label .. " " .. tostring(FormatPercent(bucket.extra) or "0%") .. ":"
    for _, node in ipairs(nodes) do
        local nodeLabel = node.name and node.name ~= ""
            and tostring(node.name)
            or "Specialization bonus"
        nodeLabel = nodeLabel .. " (rank " .. tostring(node.rank or 0) .. ")"
            .. ": +" .. tostring(FormatPercent(node.extra) or "0%")
        lines[#lines + 1] = nodeLabel
    end
end

local function BuildNodeBonusTooltip(result)
    local formula = GetRootFormula(result)
    local details = formula and formula.nodeBonusDetails
    if type(details) ~= "table" then
        return nil
    end
    if details.status == "not-captured" then
        return "Open this recipe in the " .. tostring(details.profession or "profession")
            .. " window to update its specialization bonuses. Saved defaults are used until then."
    end
    if details.status == "mapping-unavailable" then
        return "No verified specialization bonus data is available for this recipe, so no extra bonus is guessed."
    end
    if details.status == "recipe-unavailable" then
        return "Recipe details are unavailable, so specialization bonuses cannot be applied safely."
    end
    if details.status ~= "resolved" then
        return BuildNodeBonusCaption(result)
    end

    local lines = { "Specialization bonuses applied to this recipe." }
    AddNodeTooltipBucket(lines, "Multicraft extra", details.multicraft)
    AddNodeTooltipBucket(lines, "Resourcefulness save", details.resourcefulness)
    if #lines == 1 then
        lines[#lines + 1] = "No specialization bonuses apply to this recipe."
    end
    return table.concat(lines, "\n")
end

-- Stale when any material or output price is older than the freshness window.
function Model.GetStalePriceNotice(projection)
    if not (projection and projection.hasStale) then return nil end
    local minutes = math.floor(((GAM.C and GAM.C.PRICE_STALE_SECONDS) or 600) / 60)
    local text = (GAM.L and GAM.L["WARN_PRICE_STALE"]) or "Prices may be stale (>%d min)."
    return string.format(text, minutes) .. " " .. ((GAM.L and GAM.L["UI_SCAN_TO_REFRESH"]) or "Scan to refresh.")
end

function Model.GetRankMixNotice(projection)
    if not projection then return nil end
    local reason = tostring(projection.rankMixReason or "live recipe data unavailable")
    if projection.rankMixMaterialPolicy == "highest" and projection.rankMixStatus then
        local reachable = tonumber(projection.rankMixOutputQuality)
        if reason == "target-quality-unreachable" and reachable then
            local deficit = tonumber(projection.rankMixSkillDeficit)
            local extra = deficit and deficit > 0 and string.format((GAM.L and GAM.L["UI_RANK_SKILL_NEEDED"] or " Needs %.0f more skill for max rank."), deficit) or ""
            return string.format((GAM.L and GAM.L["UI_RANK2_UNREACHABLE"] or "Rank 2 materials only produce rank %d without Concentration.%s Pricing uses rank %d output."), reachable, extra, reachable)
        end
        if projection.rankMixStatus == "verified" and reachable then
            return string.format((GAM.L and GAM.L["UI_RANK2_VERIFIED"] or "Rank 2 materials: rank %d output verified by Blizzard (no Concentration)."), reachable)
        end
        return string.format((GAM.L and GAM.L["UI_RANK2_UNVERIFIED"] or "Rank 2 output not verified (%s). Open the exact recipe and click Refresh Recipe."), reason)
    end
    if reason == "target-quality-unreachable" then
        local reachable = tonumber(projection.rankMixOutputQuality)
        if projection.rankMixStatus == "reachable" and reachable and reachable > 0 then
            local deficit = tonumber(projection.rankMixSkillDeficit)
            if deficit and deficit > 0 then
                return string.format(
                    "Max rank needs %.0f more skill without Concentration. Cheapest mix for reachable rank %d verified by Blizzard.",
                    deficit, reachable)
            end
            return string.format(
                "Max rank is not reachable without Concentration at the current skill. Cheapest mix for reachable rank %d verified by Blizzard.",
                reachable)
        end
        if reachable and reachable > 0 then
            return string.format(
                "Max rank is not reachable without Concentration at the current skill. Pricing uses reachable rank %d with all highest-rank reagents.",
                reachable)
        end
        return "Max rank is not reachable without Concentration at the current skill; pricing uses the highest reachable output."
    end
    if projection.rankMixStatus == "verified" then
        return "Best rank mix verified by Blizzard (no Concentration)."
    end
    if projection.rankMixStatus ~= "fallback" then return nil end

    return string.format(
        "Best mix not verified (%s). Open the exact recipe and click Refresh Recipe.",
        reason)
end

function Model.Project(result)
    if type(result) ~= "table" then
        return nil, "canonical detail result must be a table"
    end
    if result.engine ~= "commodity_expected_value" then
        return nil, "canonical detail result has an unsupported engine"
    end

    return {
        contractVersion = result.contractVersion,
        strategyID = result.strategyID,
        patchTag = result.patchTag,
        crafts = result.crafts,
        effectiveCrafts = result.effectiveCrafts,
        recommendedCrafts = result.recommendedCrafts,
        cost = result.requiredCostFull,
        expectedCost = result.expectedConsumedCostFull,
        buyNowCost = result.buyNowCost,
        revenue = result.netRevenue,
        profit = result.profit,
        roi = result.roi,
        breakEvenSell = result.breakEvenSell,
        reagents = result.shoppingReagents or {},
        outputs = result.outputs or {},
        missingPrices = result.missingPrices or {},
        hasStale = result.hasStale and true or false,
        selectionNotes = result.selectionNotes,
        rankMixStatus = result.rankMixStatus,
        rankMixReason = result.rankMixReason,
        rankMixMaterialPolicy = result.rankMixMaterialPolicy,
        rankMixTargetQuality = result.rankMixTargetQuality,
        rankMixOutputQuality = result.rankMixOutputQuality,
        rankMixHighSkill = result.rankMixHighSkill,
        rankMixRequiredSkill = result.rankMixRequiredSkill,
        rankMixSkillDeficit = result.rankMixSkillDeficit,
        rankMixConcentrationCost = result.rankMixConcentrationCost,
        crafterCaption = BuildCrafterCaption(result),
        statsCaption = BuildStatsCaption(result),
        statsTooltip = BuildStatsTooltip(result),
        nodeBonusCaption = BuildNodeBonusCaption(result),
        nodeBonusTooltip = BuildNodeBonusTooltip(result),
        gearCaption = BuildGearCaption(result),
        gearTooltip = BuildGearTooltip(result),
        gearPresetMissing = (result.gearPresetMissing or result.gearStatValidity == "unobserved") and true or false,
    }
end

-- Display a minimum whole-copper posting price, with an explicit full-stack
-- size. Never divide combined outputs into an artificial single-item price.
local pendingStackItems, stackItemEvents = {}, nil
local function RequestStackItem(itemID)
    if not (itemID and C_Item and C_Item.RequestLoadItemDataByID and CreateFrame) then return end
    if pendingStackItems[itemID] then return end
    if not stackItemEvents then
        stackItemEvents = CreateFrame("Frame")
        stackItemEvents:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        stackItemEvents:SetScript("OnEvent", function(_, _, loadedID, success)
            if not pendingStackItems[loadedID] then return end
            pendingStackItems[loadedID] = nil
            if not success then return end
            for _, view in ipairs({ GAM.UI.MainWindow or {}, GAM.UI.StrategyDetail or {} }) do
                if view.IsShown and view.IsShown() and view.Refresh then view.Refresh() end
            end
        end)
    end
    pendingStackItems[itemID] = true
    C_Item.RequestLoadItemDataByID(itemID)
end

function Model.FormatBreakEven(projection, formatPrice)
    local outputs = projection.outputs or {}
    if #outputs > 1 then
        local mixed = (GAM.L and GAM.L["UI_MIXED_OUTPUTS"] or "Mixed outputs")
        return mixed, mixed
    end
    local price = tonumber(projection.breakEvenSell)
    if not price or price ~= price or price < 0 or price == math.huge then return "—", "—" end
    price = math.ceil(price)
    local unitText = formatPrice(price)
    local itemID = outputs[1] and outputs[1].itemID
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    local stackSize
    if itemID and getInfo then stackSize = select(8, getInfo(itemID)) end
    stackSize = tonumber(stackSize)
    if not stackSize or stackSize <= 0 then
        RequestStackItem(itemID)
        return unitText, (GAM.L and GAM.L["UI_ITEM_DATA_UNAVAILABLE"] or "Item data unavailable")
    end
    stackSize = math.floor(stackSize)
    if stackSize == 1 then return unitText, (GAM.L and GAM.L["UI_NOT_STACKABLE"] or "Not stackable") end
    return unitText, string.format((GAM.L and GAM.L["UI_STACK_ITEMS"] or "%s (%d items)"), formatPrice(price * stackSize), stackSize)
end

function Model.FormatBatchBreakEven(projection, formatPrice)
    local outputs = projection.outputs or {}
    if #outputs > 1 then
        local mixed = (GAM.L and GAM.L["UI_MIXED_OUTPUTS"] or "Mixed outputs")
        return mixed, mixed
    end
    local price = tonumber(projection.breakEvenSell)
    if not price or price ~= price or price < 0 or price == math.huge then return "—", "—" end
    local unit = formatPrice(math.ceil(price))
    local output = outputs[1]
    local quantity = output and tonumber(output.expectedQtyRaw or output.expectedQty)
    if not quantity or quantity ~= quantity or quantity <= 0 or quantity == math.huge then return unit, "—" end
    return unit, string.format((GAM.L and GAM.L["UI_BATCH_EXPECTED"] or "%s (%s expected items)"),
        formatPrice(math.ceil(price * quantity)), string.format("%.2f", quantity):gsub("0+$", ""):gsub("%.$", ""))
end

function Model.CreateSnapshot(canonicalResult)
    local projection, err = Model.Project(canonicalResult)
    if not projection then
        return nil, err
    end
    return {
        canonicalResult = canonicalResult,
        projection = projection,
    }
end
