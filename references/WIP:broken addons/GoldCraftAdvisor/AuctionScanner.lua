-- GoldCraft Advisor - AuctionScanner.lua
-- C_AuctionHouse wrapper for scanning commodity prices

local _, GCA = ...

-- ================= Configuration =================
local SCAN_DELAY = 3.0  -- Delay between queries to respect throttling (Blizzard is aggressive)
local RESULT_WAIT = 5.0  -- How long to wait for results before moving on
local BATCH_SIZE = 10   -- Process this many items before yielding
local DEBOUNCE_DELAY = 1.0  -- Ignore duplicate results within this time
local EVENT_PROCESS_DELAY = 0.8  -- Delay after event before reading results
local RESULT_RETRY_DELAY = 0.5  -- Delay between result read attempts
local MAX_RESULT_ATTEMPTS = 5  -- Number of times to try reading results

-- ================= State =================
local scanning = false
local scanQueue = {}
local currentIndex = 0
local totalItems = 0
local lastItemID = nil
local lastQueryTime = 0
local pendingItemID = nil  -- Track which item we're waiting for results
local waitingForResults = false  -- Are we waiting for a query to return?
local scanSuccessCount = 0  -- Track successful scans
local scanFailCount = 0  -- Track failed scans
local failedItems = {}  -- Track which items failed to scan
local isRetryPass = false  -- Are we in the retry pass?

-- ================= ItemKey Cache =================
GCA.ItemKeyCache = {}

function GCA:GetCachedItemKey(itemID)
    if not itemID then return nil end

    if self.ItemKeyCache[itemID] then
        return self.ItemKeyCache[itemID]
    end

    local itemKey = C_AuctionHouse.MakeItemKey(itemID, 0, 0)
    self.ItemKeyCache[itemID] = itemKey
    return itemKey
end

-- ================= Commodity Cache =================
-- Runtime cache for current AH session
GCA.commodityCache = GCA.commodityCache or {}

function GCA:ClearCommodityCache()
    self.commodityCache = {}
end

-- ================= Price Computation =================

-- Expand commodity results to individual unit prices
local function ExpandResultsToUnitPrices(results, targetQuantity)
    local unitPrices = {}
    if not results or #results == 0 then return unitPrices end

    -- Sort ascending to pick cheapest units first
    table.sort(results, function(a, b) return a.unitPrice < b.unitPrice end)

    local collected = 0
    for _, r in ipairs(results) do
        local take = math.min(r.quantity or 0, targetQuantity - collected)
        if take <= 0 then break end
        for i = 1, take do
            unitPrices[#unitPrices + 1] = r.unitPrice
        end
        collected = collected + take
        if collected >= targetQuantity then break end
    end

    return unitPrices
end

-- Compute stats from unit prices with trim
local function ComputeStatsFromResults(results, targetQuantity, trimPercent)
    if not results or #results == 0 then return nil end

    local selectedUnits = ExpandResultsToUnitPrices(results, targetQuantity)
    local n = #selectedUnits
    if n == 0 then return nil end

    -- Sort descending so most expensive are at the front
    table.sort(selectedUnits, function(a, b) return a > b end)

    -- Apply trim
    local trimPercentNum = tonumber(trimPercent) or 0
    if trimPercentNum < 0 then trimPercentNum = 0 end
    if trimPercentNum > 100 then trimPercentNum = 100 end

    local trimCount = math.floor(n * (trimPercentNum / 100))

    -- If trimming removes all units, return zero-stats
    if trimCount >= n then
        return 0, 0, 0, 0
    end

    -- Build list of units to use (skip first trimCount entries)
    local unitsToUse = {}
    for i = trimCount + 1, n do
        unitsToUse[#unitsToUse + 1] = selectedUnits[i]
    end

    if #unitsToUse == 0 then
        return 0, 0, 0, 0
    end

    local sum = 0
    local minUnit, maxUnit = unitsToUse[1], unitsToUse[1]
    for _, price in ipairs(unitsToUse) do
        sum = sum + price
        if price < minUnit then minUnit = price end
        if price > maxUnit then maxUnit = price end
    end

    local avg = sum / #unitsToUse
    return avg, minUnit, maxUnit, #unitsToUse
end

-- ================= Get Commodity Stats =================

function GCA:GetCommodityStats(itemID)
    if not itemID then return nil end
    if not C_AuctionHouse or not C_AuctionHouse.GetNumCommoditySearchResults then return nil end

    -- Use pcall to catch any API errors
    local success, numResults = pcall(function()
        return C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    end)

    if not success then
        GCA:Debug("GetNumCommoditySearchResults error for", itemID)
        return nil
    end

    if not numResults or numResults == 0 then
        return nil
    end

    local results = {}
    local minPrice, fullMaxPrice = nil, nil
    local totalAvailable = 0

    for i = 1, numResults do
        local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if not result then break end
        results[#results + 1] = { unitPrice = result.unitPrice, quantity = result.quantity or 0 }
        totalAvailable = totalAvailable + (result.quantity or 0)
        if not minPrice or result.unitPrice < minPrice then minPrice = result.unitPrice end
        if not fullMaxPrice or result.unitPrice > fullMaxPrice then fullMaxPrice = result.unitPrice end
    end

    if #results == 0 then
        return nil
    end

    -- Cache raw snapshot
    self.commodityCache[itemID] = self.commodityCache[itemID] or {}
    self.commodityCache[itemID].prices = results
    self.commodityCache[itemID].minPrice = minPrice
    self.commodityCache[itemID].maxPrice = fullMaxPrice
    self.commodityCache[itemID].totalAvailable = totalAvailable
    self.commodityCache[itemID].timestamp = time()

    -- Compute according to current settings
    local targetQuantity = tonumber(self.db.settings.quantity) or 10000
    local trimPercent = tonumber(self.db.settings.trim) or 3

    local avg, minP, maxP, count = ComputeStatsFromResults(results, targetQuantity, trimPercent)
    if not avg then
        return nil
    end

    -- Store computed result
    self.commodityCache[itemID].lastComputed = {
        avg = avg,
        min = minP,
        max = maxP,
        count = count,
        targetQuantity = targetQuantity,
        trimPercent = trimPercent
    }

    return avg, minP, maxP, count
end

-- ================= Send AH Query =================

local function SendAHQuery(itemID)
    if not C_AuctionHouse or not C_AuctionHouse.SendSearchQuery then return false end

    -- Verify AH is still open
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        return false
    end

    -- Track which item we're querying
    pendingItemID = itemID

    -- Create itemKey - for commodities, use 0 for itemLevel and itemSuffix
    local itemKey = C_AuctionHouse.MakeItemKey(itemID, 0, 0, 0)
    if not itemKey then
        GCA:Debug("Failed to create itemKey for", itemID)
        return false
    end

    -- Cache the key
    GCA.ItemKeyCache[itemID] = itemKey

    -- Send the search query
    local success = pcall(function()
        C_AuctionHouse.SendSearchQuery(itemKey, {}, false)
    end)

    if not success then
        GCA:Debug("SendSearchQuery failed for", itemID)
        return false
    end

    return true
end

-- ================= Scan Management =================

function GCA:StartScan(filterName)
    if scanning then
        print("|cffff0000[GCA]|r Scan already in progress.")
        return
    end

    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        print("|cffff0000[GCA]|r Auction House must be open to scan.")
        return
    end

    -- Get items to scan
    local items
    if filterName then
        items = self:GetFilterItems(filterName)
    else
        -- Use all strategy items
        items = {}
        local allItemIDs = self:GetAllStrategyItemIDs()
        for _, itemID in ipairs(allItemIDs) do
            items[itemID] = { itemID = itemID }
        end
    end

    -- Build scan queue
    scanQueue = {}
    for itemID in pairs(items) do
        scanQueue[#scanQueue + 1] = itemID
    end

    if #scanQueue == 0 then
        print("|cff00ff00[GCA]|r No items to scan.")
        return
    end

    scanning = true
    currentIndex = 0
    totalItems = #scanQueue
    scanSuccessCount = 0
    scanFailCount = 0
    failedItems = {}  -- Clear failed items list
    waitingForResults = false
    pendingItemID = nil
    isRetryPass = false  -- This is the main scan

    print(string.format("|cff00ff00[GCA]|r Starting scan of %d items...", totalItems))

    -- Start the scan
    self:ProcessNextScanBatch()
end

function GCA:ProcessNextScanBatch()
    if not scanning then return end

    -- Check if AH is still open
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        self:StopScan()
        return
    end

    if currentIndex >= totalItems then
        self:FinishScan()
        return
    end

    -- Don't send next query if we're still waiting for results
    if waitingForResults then
        -- Check again in a moment
        C_Timer.After(0.2, function()
            self:ProcessNextScanBatch()
        end)
        return
    end

    -- Ensure previous query state is fully cleared
    pendingItemID = nil

    currentIndex = currentIndex + 1
    local itemID = scanQueue[currentIndex]

    -- Update progress first
    if self.UpdateScanProgress then
        self:UpdateScanProgress(currentIndex, totalItems)
    end

    -- Verify item ID is valid
    if not itemID or type(itemID) ~= "number" then
        GCA:Debug("Invalid itemID in scan queue:", tostring(itemID))
        C_Timer.After(0.1, function()
            self:ProcessNextScanBatch()
        end)
        return
    end

    -- Log which item we're scanning
    local itemName = GCA:GetItemName(itemID) or tostring(itemID)
    GCA:Debug(string.format("Querying [%d/%d]: %s (ID: %d)", currentIndex, totalItems, itemName, itemID))

    -- Send query
    waitingForResults = true
    local querySuccess = SendAHQuery(itemID)

    if not querySuccess then
        -- Query failed to send
        scanFailCount = scanFailCount + 1
        failedItems[#failedItems + 1] = { id = itemID, name = itemName, reason = "Query failed" }
        waitingForResults = false
        pendingItemID = nil
        C_Timer.After(SCAN_DELAY, function()
            self:ProcessNextScanBatch()
        end)
        return
    end

    -- Set up timeout for this query
    -- The event handler will clear waitingForResults when results arrive
    local queryStartTime = GetTime()
    local capturedItemID = itemID  -- Capture for closure

    local function CheckAndContinue()
        -- If not scanning anymore, stop
        if not scanning then return end

        -- If already processed by event handler, proceed after delay
        if not waitingForResults then
            C_Timer.After(SCAN_DELAY, function()
                self:ProcessNextScanBatch()
            end)
            return
        end

        -- If pending item changed, this query was processed
        if pendingItemID ~= capturedItemID then
            C_Timer.After(SCAN_DELAY, function()
                self:ProcessNextScanBatch()
            end)
            return
        end

        -- Check if we've exceeded timeout
        local elapsed = GetTime() - queryStartTime
        if elapsed >= RESULT_WAIT then
            -- Timeout - item might not be on AH or query failed
            scanFailCount = scanFailCount + 1
            local name = GCA:GetItemName(capturedItemID) or tostring(capturedItemID)
            failedItems[#failedItems + 1] = { id = capturedItemID, name = name, reason = "Timeout" }
            GCA:Debug(string.format("Timeout waiting for %s (ID: %d) after %.1fs", name, capturedItemID, elapsed))
            waitingForResults = false
            pendingItemID = nil
            C_Timer.After(SCAN_DELAY, function()
                self:ProcessNextScanBatch()
            end)
        else
            -- Check again in 0.3s
            C_Timer.After(0.3, CheckAndContinue)
        end
    end

    -- Start checking after a short delay
    C_Timer.After(0.5, CheckAndContinue)
end

function GCA:FinishScan()
    local successCount = scanSuccessCount
    local failCount = scanFailCount
    local failedItemsCopy = {}
    for i, item in ipairs(failedItems) do
        failedItemsCopy[i] = item
    end
    local wasRetryPass = isRetryPass

    scanning = false
    scanQueue = {}
    currentIndex = 0
    totalItems = 0
    scanSuccessCount = 0
    scanFailCount = 0
    failedItems = {}
    waitingForResults = false
    pendingItemID = nil

    if wasRetryPass then
        print(string.format("|cff00ff00[GCA]|r Retry complete! %d items recovered, %d still missing",
            successCount, failCount))
    else
        print(string.format("|cff00ff00[GCA]|r Scan complete! %d items priced, %d not on AH",
            successCount, failCount))
    end

    -- Log failed items summary to debug panel
    if #failedItemsCopy > 0 then
        if wasRetryPass then
            self:Log("--- Final Failed Items (after retry) ---", false)
        else
            self:Log("--- Failed Items Summary ---", false)
        end
        for _, item in ipairs(failedItemsCopy) do
            self:Log(string.format("  [%d] %s - %s", item.id, item.name, item.reason), false)
        end
        self:Log(string.format("Total failed: %d items", #failedItemsCopy), false)
    end

    -- If this was the main scan and we have failed items, start retry pass
    if not wasRetryPass and #failedItemsCopy > 0 then
        self:StartRetryPass(failedItemsCopy)
        return  -- Don't calculate ROI yet, wait for retry to finish
    end

    -- Calculate and display ROI
    if self.CalculateAllROI then
        C_Timer.After(1.0, function()
            self:CalculateAllROI()
        end)
    end

    -- Update UI
    if self.UpdateResults then
        self:UpdateResults()
    end
end

function GCA:StartRetryPass(failedItemsList)
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        self:Log("Retry cancelled - Auction House closed", false)
        return
    end

    -- Build retry queue from failed items
    scanQueue = {}
    for _, item in ipairs(failedItemsList) do
        scanQueue[#scanQueue + 1] = item.id
    end

    if #scanQueue == 0 then
        return
    end

    scanning = true
    currentIndex = 0
    totalItems = #scanQueue
    scanSuccessCount = 0
    scanFailCount = 0
    failedItems = {}
    waitingForResults = false
    pendingItemID = nil
    isRetryPass = true  -- Mark this as a retry pass

    self:Log(string.format("Retrying %d failed items (with slower timing)...", totalItems), false)
    print(string.format("|cff00ff00[GCA]|r Retrying %d failed items...", totalItems))

    -- Start the retry scan after a longer delay to let AH settle
    C_Timer.After(4.0, function()
        if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
            self:Log("Retry cancelled - Auction House closed", false)
            scanning = false
            return
        end
        self:ProcessNextScanBatch()
    end)
end

function GCA:StopScan()
    if scanning then
        scanning = false
        scanQueue = {}
        currentIndex = 0
        totalItems = 0
        pendingItemID = nil
        waitingForResults = false
        isRetryPass = false
        print("|cff00ff00[GCA]|r Scan stopped.")
    end
end

function GCA:IsScanInProgress()
    return scanning
end

function GCA:GetScanProgress()
    if not scanning then return 0, 0, 0 end
    local percent = totalItems > 0 and (currentIndex / totalItems * 100) or 0
    return currentIndex, totalItems, percent
end

-- ================= Event Handler =================

function GCA:OnCommoditySearchResults()
    -- Longer delay to ensure AH API has fully populated results
    C_Timer.After(EVENT_PROCESS_DELAY, function()
        if not C_AuctionHouse then return end
        if not scanning then return end  -- Ignore events if not scanning

        -- Use pending item from our scan
        local itemID = pendingItemID
        if not itemID then
            -- Not our query, ignore
            return
        end

        -- Capture the item ID for this closure (in case it changes)
        local capturedItemID = itemID

        -- Try multiple times to get results (sometimes takes a moment)
        local function TryGetResults(attempts)
            -- Verify we're still waiting for this item
            if pendingItemID ~= capturedItemID then
                -- We've moved on, this is a late result
                return
            end

            -- Check if AH is still open
            if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
                waitingForResults = false
                pendingItemID = nil
                return
            end

            -- Try to verify results are for our item by checking if we get data
            local numResults = C_AuctionHouse.GetNumCommoditySearchResults(capturedItemID)

            if numResults and numResults > 0 then
                local avg, minP, maxP, collected = self:GetCommodityStats(capturedItemID)

                if avg then
                    -- Success! Store in persistent price database
                    self:StorePrice(capturedItemID, avg, minP, maxP, collected)
                    scanSuccessCount = scanSuccessCount + 1

                    -- Debug output (only in debug mode)
                    local itemName = GCA:GetItemName(capturedItemID) or tostring(capturedItemID)
                    GCA:Debug(string.format("Scanned %s: %.2fg (%d units)", itemName, avg/10000, collected))

                    -- Clear pending and waiting flag
                    if pendingItemID == capturedItemID then
                        pendingItemID = nil
                        waitingForResults = false
                    end
                    return
                end
            end

            -- No results yet
            if attempts > 0 then
                -- Retry after a delay
                C_Timer.After(RESULT_RETRY_DELAY, function()
                    TryGetResults(attempts - 1)
                end)
            else
                -- All attempts failed - item not listed on AH or no results
                scanFailCount = scanFailCount + 1
                local itemName = GCA:GetItemName(capturedItemID) or tostring(capturedItemID)
                failedItems[#failedItems + 1] = { id = capturedItemID, name = itemName, reason = "No listings" }
                GCA:Debug(string.format("No AH data for %s (ID: %d)", itemName, capturedItemID))

                -- Clear pending and waiting flag
                if pendingItemID == capturedItemID then
                    pendingItemID = nil
                    waitingForResults = false
                end
            end
        end

        -- Try up to MAX_RESULT_ATTEMPTS times to get results
        TryGetResults(MAX_RESULT_ATTEMPTS - 1)
    end)
end

-- ================= Price Storage =================

function GCA:StorePrice(itemID, avg, minPrice, maxPrice, collected)
    if not itemID or not avg then return end

    -- Ensure price table exists
    self.db.prices = self.db.prices or {}
    self.db.prices[itemID] = self.db.prices[itemID] or {}

    -- Determine rank from item info (simplified - use rank 2 as default)
    local rank = 2  -- Most common rank in the spreadsheet

    -- Store price
    self.db.prices[itemID][rank] = {
        price = avg,
        minPrice = minPrice,
        maxPrice = maxPrice,
        collected = collected,
        timestamp = time(),
    }
end

function GCA:GetPrice(itemID, rank)
    if not itemID then return nil end

    -- Check runtime cache first (commodities don't have ranks in AH)
    if self.commodityCache[itemID] and self.commodityCache[itemID].lastComputed then
        return self.commodityCache[itemID].lastComputed.avg
    end

    -- Check persistent storage
    if self.db.prices and self.db.prices[itemID] then
        -- Try specific rank first
        if rank and self.db.prices[itemID][rank] then
            return self.db.prices[itemID][rank].price
        end
        -- Fall back to any available rank (commodities are same price regardless of "rank")
        for r, data in pairs(self.db.prices[itemID]) do
            if data.price then
                return data.price
            end
        end
    end

    return nil
end

function GCA:GetPriceInfo(itemID, rank)
    if not itemID then return nil end

    -- Check runtime cache first
    if self.commodityCache[itemID] and self.commodityCache[itemID].lastComputed then
        return self.commodityCache[itemID].lastComputed
    end

    -- Check persistent storage
    if self.db.prices and self.db.prices[itemID] then
        -- Try specific rank first
        if rank and self.db.prices[itemID][rank] then
            return self.db.prices[itemID][rank]
        end
        -- Fall back to any available rank
        for r, data in pairs(self.db.prices[itemID]) do
            return data
        end
    end

    return nil
end

-- ================= Recalculation =================

function GCA:RecalculatePrices()
    local targetQuantity = tonumber(self.db.settings.quantity) or 10000
    local trimPercent = tonumber(self.db.settings.trim) or 3

    for itemID, cache in pairs(self.commodityCache) do
        if cache.prices and #cache.prices > 0 then
            local avg, minP, maxP, count = ComputeStatsFromResults(cache.prices, targetQuantity, trimPercent)
            if avg then
                cache.lastComputed = {
                    avg = avg,
                    min = minP,
                    max = maxP,
                    count = count,
                    targetQuantity = targetQuantity,
                    trimPercent = trimPercent
                }

                -- Update persistent storage
                self:StorePrice(itemID, avg, minP, maxP, count)
            end
        end
    end

    print("|cff00ff00[GCA]|r Prices recalculated with new settings.")

    -- Update UI
    if self.UpdateResults then
        self:UpdateResults()
    end
end

-- ================= Manual Single Item Scan =================
-- For debugging: /gca scanitem 210796

function GCA:ScanSingleItem(itemID)
    if not itemID or type(itemID) ~= "number" then
        print("|cffff0000[GCA]|r Invalid item ID")
        return
    end

    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        print("|cffff0000[GCA]|r Auction House must be open")
        return
    end

    if scanning then
        print("|cffff0000[GCA]|r Scan already in progress")
        return
    end

    local itemName = self:GetItemName(itemID) or tostring(itemID)
    print(string.format("|cff00ff00[GCA]|r Scanning single item: %s (ID: %d)", itemName, itemID))
    self:Log(string.format("Manual scan: %s (ID: %d)", itemName, itemID), false)

    -- Create itemKey
    local itemKey = C_AuctionHouse.MakeItemKey(itemID, 0, 0, 0)
    if not itemKey then
        print("|cffff0000[GCA]|r Failed to create itemKey")
        return
    end

    -- Send query
    local success = pcall(function()
        C_AuctionHouse.SendSearchQuery(itemKey, {}, false)
    end)

    if not success then
        print("|cffff0000[GCA]|r SendSearchQuery failed")
        return
    end

    -- Set up to capture results
    local capturedItemID = itemID
    pendingItemID = itemID

    -- Check for results after a delay
    C_Timer.After(1.5, function()
        local numResults = C_AuctionHouse.GetNumCommoditySearchResults(capturedItemID)
        self:Log(string.format("  GetNumCommoditySearchResults: %s", tostring(numResults)), false)

        if numResults and numResults > 0 then
            local avg, minP, maxP, collected = self:GetCommodityStats(capturedItemID)
            if avg then
                self:StorePrice(capturedItemID, avg, minP, maxP, collected)
                print(string.format("|cff00ff00[GCA]|r %s: %.2fg avg (min: %.2fg, max: %.2fg, qty: %d)",
                    itemName, avg/10000, minP/10000, maxP/10000, collected))
                self:Log(string.format("  SUCCESS: %.2fg avg", avg/10000), false)
            else
                print(string.format("|cffff0000[GCA]|r %s: Results found but stats failed", itemName))
                self:Log("  FAILED: Stats calculation failed", false)
            end
        else
            print(string.format("|cffff0000[GCA]|r %s: No listings found", itemName))
            self:Log("  FAILED: No listings", false)
        end

        pendingItemID = nil
    end)
end
