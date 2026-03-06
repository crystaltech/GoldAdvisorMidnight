-- GoldCraft Advisor - Filters.lua
-- Import/export filter management

local _, GCA = ...

-- ================= Filter Storage =================
GCA.Filters = GCA.Filters or {}

-- ================= Parse Import String =================
-- Format: "ListName:name;Items:itemID:quantity,itemID:quantity,..."

function GCA:ParseImportString(importString)
    if not importString or importString == "" then
        return nil, "Empty import string"
    end

    local filter = {
        name = "Imported",
        items = {},
    }

    -- Parse ListName
    local listName = importString:match("ListName:([^;]+)")
    if listName then
        filter.name = listName:gsub("^%s*(.-)%s*$", "%1")  -- Trim whitespace
    end

    -- Parse Items section
    local itemsSection = importString:match("Items:(.+)$")
    if not itemsSection then
        return nil, "No items section found"
    end

    -- Parse each item entry
    for entry in itemsSection:gmatch("([^,]+)") do
        local itemID, quantity = entry:match("(%d+):([^,]+)")
        if itemID then
            itemID = tonumber(itemID)
            if itemID then
                -- Handle DEFAULT or numeric quantity
                if quantity == "DEFAULT" then
                    quantity = 1
                else
                    quantity = tonumber(quantity) or 1
                end

                filter.items[itemID] = {
                    itemID = itemID,
                    quantity = quantity,
                }
            end
        end
    end

    local itemCount = 0
    for _ in pairs(filter.items) do
        itemCount = itemCount + 1
    end

    if itemCount == 0 then
        return nil, "No valid items parsed"
    end

    return filter
end

-- ================= Import Filter =================

function GCA:ImportFilter(importString, filterName)
    local filter, err = self:ParseImportString(importString)
    if not filter then
        print("|cffff0000[GCA]|r Import failed: " .. (err or "Unknown error"))
        return false
    end

    -- Use provided name or parsed name
    local name = filterName or filter.name
    if not name or name == "" then
        name = "Imported_" .. time()
    end

    -- Store in database
    self.db.filters = self.db.filters or {}
    self.db.filters[name] = {
        name = name,
        items = filter.items,
        timestamp = time(),
    }

    local count = 0
    for _ in pairs(filter.items) do count = count + 1 end

    print(string.format("|cff00ff00[GCA]|r Imported filter '%s' with %d items", name, count))
    return true, name
end

-- ================= Get Filter Items =================

function GCA:GetFilterItems(filterName)
    if not filterName then
        return nil
    end

    -- Check built-in filters first
    if self.ImportLists and self.ImportLists[filterName] then
        local filter, err = self:ParseImportString(self.ImportLists[filterName])
        if filter then
            return filter.items
        end
    end

    -- Check user-defined filters
    if self.db.filters and self.db.filters[filterName] then
        return self.db.filters[filterName].items
    end

    return nil
end

-- ================= Get All Strategy Item IDs =================

function GCA:GetAllStrategyItemIDs()
    local itemIDs = {}
    local seen = {}

    if not self.Strategies then
        return itemIDs
    end

    for _, strategy in pairs(self.Strategies) do
        -- Collect input items
        if strategy.inputs then
            for _, input in ipairs(strategy.inputs) do
                if input.itemID and not seen[input.itemID] then
                    seen[input.itemID] = true
                    itemIDs[#itemIDs + 1] = input.itemID
                end
            end
        end

        -- Collect output items
        if strategy.outputs then
            for _, output in ipairs(strategy.outputs) do
                if output.itemID and not seen[output.itemID] then
                    seen[output.itemID] = true
                    itemIDs[#itemIDs + 1] = output.itemID
                end
            end
        end
    end

    return itemIDs
end

-- ================= Get Filter Names =================

function GCA:GetFilterNames()
    local names = { "All" }

    -- Add built-in filters
    if self.ImportLists then
        for name in pairs(self.ImportLists) do
            names[#names + 1] = name
        end
    end

    -- Add user-defined filters
    if self.db.filters then
        for name in pairs(self.db.filters) do
            -- Avoid duplicates
            local found = false
            for _, n in ipairs(names) do
                if n == name then found = true break end
            end
            if not found then
                names[#names + 1] = name
            end
        end
    end

    -- Sort alphabetically (keeping "All" first)
    table.sort(names, function(a, b)
        if a == "All" then return true end
        if b == "All" then return false end
        return a < b
    end)

    return names
end

-- ================= Get Category Names =================

function GCA:GetCategoryNames()
    local categories = { "All" }
    local seen = { ["All"] = true }

    if self.Strategies then
        for _, strategy in pairs(self.Strategies) do
            if strategy.category and not seen[strategy.category] then
                seen[strategy.category] = true
                categories[#categories + 1] = strategy.category
            end
        end
    end

    -- Sort alphabetically (keeping "All" first)
    table.sort(categories, function(a, b)
        if a == "All" then return true end
        if b == "All" then return false end
        return a < b
    end)

    return categories
end

-- ================= Delete Filter =================

function GCA:DeleteFilter(filterName)
    if not filterName or filterName == "All" then
        return false
    end

    -- Can't delete built-in filters
    if self.ImportLists and self.ImportLists[filterName] then
        print("|cffff0000[GCA]|r Cannot delete built-in filter: " .. filterName)
        return false
    end

    -- Delete user-defined filter
    if self.db.filters and self.db.filters[filterName] then
        self.db.filters[filterName] = nil
        print("|cff00ff00[GCA]|r Deleted filter: " .. filterName)
        return true
    end

    return false
end

-- ================= Export Prices =================

function GCA:ExportPrices()
    if not self.db.prices then
        print("|cffff0000[GCA]|r No price data to export")
        return nil
    end

    -- Use Codec to pack price data
    if self.Codec and self.Codec.PackPriceData then
        local encoded = self.Codec:PackPriceData(self.db.prices)
        if encoded and #encoded > 0 then
            print(string.format("|cff00ff00[GCA]|r Exported %d price entries", #encoded))
            return encoded
        end
    end

    -- Fallback: return raw data
    return self.db.prices
end

-- ================= Import Prices =================

function GCA:ImportPrices(encodedList)
    if not encodedList then
        print("|cffff0000[GCA]|r No price data to import")
        return false
    end

    -- Use Codec to unpack price data
    if self.Codec and self.Codec.UnpackPriceData then
        local prices = self.Codec:UnpackPriceData(encodedList)
        if prices then
            -- Merge with existing prices
            self.db.prices = self.db.prices or {}
            local count = 0
            for itemID, ranks in pairs(prices) do
                self.db.prices[itemID] = self.db.prices[itemID] or {}
                for rank, data in pairs(ranks) do
                    self.db.prices[itemID][rank] = data
                    count = count + 1
                end
            end
            print(string.format("|cff00ff00[GCA]|r Imported %d price entries", count))
            return true
        end
    end

    return false
end

-- ================= Clear Price Data =================

function GCA:ClearPrices()
    self.db.prices = {}
    if self.ClearCommodityCache then
        self:ClearCommodityCache()
    end
    print("|cff00ff00[GCA]|r Price data cleared")
end

-- ================= Get Item Count for Filter =================

function GCA:GetFilterItemCount(filterName)
    local items = self:GetFilterItems(filterName)
    if not items then
        -- If "All", return all strategy items count
        if filterName == "All" or not filterName then
            return #self:GetAllStrategyItemIDs()
        end
        return 0
    end

    local count = 0
    for _ in pairs(items) do
        count = count + 1
    end
    return count
end

-- ================= Print Filter Info =================

function GCA:PrintFilterInfo(filterName)
    if not filterName then
        print("|cff00ff00[GCA]|r Available filters:")
        for _, name in ipairs(self:GetFilterNames()) do
            local count = self:GetFilterItemCount(name)
            print(string.format("  %s (%d items)", name, count))
        end
        return
    end

    local items = self:GetFilterItems(filterName)
    if not items then
        print("|cffff0000[GCA]|r Filter not found: " .. filterName)
        return
    end

    print(string.format("|cff00ff00[GCA]|r Filter: %s", filterName))
    local count = 0
    for itemID, data in pairs(items) do
        count = count + 1
        if count <= 10 then
            local name = self:GetItemName(itemID) or tostring(itemID)
            print(string.format("  %s (ID: %d)", name, itemID))
        end
    end
    if count > 10 then
        print(string.format("  ... and %d more items", count - 10))
    end
end
