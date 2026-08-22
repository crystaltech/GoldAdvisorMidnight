-- GoldAdvisorMidnight/UI/StrategyDetailModel.lua
-- Pure projection from the canonical pricing result into base-detail UI values.
-- Module: GAM.UI.StrategyDetailModel

local ADDON_NAME, GAM = ...
GAM.UI = GAM.UI or {}

local Model = {}
GAM.UI.StrategyDetailModel = Model

local function AddThousandsSeparators(text)
    local sign, digits, fraction = tostring(text or ""):match("^([%-]?)(%d+)(%.%d+)?$")
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
        auto = "Auto",
        multicraft = "Multicraft",
        resourcefulness = "Resourcefulness",
        current = "Current setup",
    }
    if result and result.gearPresetMissing then
        return (labels[requested] or requested) .. " setup not saved"
    end
    if requested == "auto" then
        if resolved == "current" then
            return "Auto (current gear)"
        end
        return "Auto: " .. (labels[resolved] or resolved)
    end
    return labels[resolved] or resolved
end

local function BuildGearTooltip(result)
    if result and result.gearPresetMissing then
        return "This gear setup has not been saved for the recipe. Equip it, open the recipe, and use Stat Gear to save it. Current saved stats are used until then."
    end
    if result and result.gearModeRequested == "auto" then
        return "Auto compares the saved Multicraft and Resourcefulness setups and uses the one with more profit."
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

function Model.GetRankMixNotice(projection)
    if not projection then return nil end
    local reason = tostring(projection.rankMixReason or "live recipe data unavailable")
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
        gearPresetMissing = result.gearPresetMissing and true or false,
    }
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
