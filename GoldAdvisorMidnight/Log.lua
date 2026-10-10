-- GoldAdvisorMidnight/Log.lua
-- Ring-buffer debug log of structured entries. Zero garbage in the hot path
-- when a message is below the capture level.
-- Module: GAM.Log

local ADDON_NAME, GAM = ...
local Log = {}
GAM.Log = Log

-- Most to least severe. Warnings and errors are always captured; the
-- capture level (0=off, 1=info, 2=debug, 3=verbose) gates the rest.
Log.LEVELS = { "ERROR", "WARN", "INFO", "DEBUG", "VERBOSE" }
local CAPTURE_LEVEL = { INFO = 1, DEBUG = 2, VERBOSE = 3 }

-- Existing "Prefix: message" conventions become filterable areas. Unknown
-- prefixes stay part of the message under General.
local AREAS = {
    AHScan = "Scan", AHQuery = "Scan", Scan = "Scan",
    CraftSimBridge = "CraftSim", CraftSim = "CraftSim",
    Importer = "Data", StrategyModel = "Data", Migration = "Data",
    RecipeAudit = "Recipes", Recipe = "Recipes",
    Gear = "Gear", Stats = "Stats",
    Settings = "Settings",
    ["Craft Queue"] = "Queue", ["Craft Plan"] = "Queue",
    Diagnostics = "Diagnostics",
    Posting = "Posting", Perf = "Performance",
}
Log.GENERAL_AREA = "General"

-- Ring buffer state (sized by Init)
local buf   = {}
local head  = 0   -- next write index (0-based)
local count = 0   -- total entries ever written
local SIZE  = 500
local level = 1

-- Listeners: frames that want to receive new entries
local listeners = {}

local function timestamp()
    return date("%H:%M:%S")
end

local function Classify(text)
    local prefix, rest = text:match("^([%a][%w ]-):%s+(.+)$")
    local area = prefix and AREAS[prefix]
    if area then return area, rest end
    return Log.GENERAL_AREA, text
end

local function emit(levelName, msg, ...)
    local text = (select('#', ...) > 0) and msg:format(...) or tostring(msg)
    local area, body = Classify(text)
    count = count + 1
    local entry = { seq = count, time = timestamp(), level = levelName, area = area, text = body }
    buf[(head % SIZE) + 1] = entry
    head = head + 1
    for i = 1, #listeners do
        -- Intentionally isolate listener failures without recursing into Log.
        pcall(listeners[i], entry)
    end
end

function Log.Init(ringSize, verbosity)
    SIZE  = ringSize or 500
    level = verbosity or 1
    buf, head, count = {}, 0, 0
end

function Log.SetLevel(v)
    level = v or 1
end

function Log.GetLevel()
    return level
end

function Log.AddListener(fn)
    listeners[#listeners + 1] = fn
end

function Log.RemoveListener(fn)
    for i = #listeners, 1, -1 do
        if listeners[i] == fn then
            table.remove(listeners, i)
            return
        end
    end
end

function Log.Warn(msg, ...) emit("WARN", msg, ...) end
function Log.Error(msg, ...) emit("ERROR", msg, ...) end

function Log.Info(msg, ...)
    if level < CAPTURE_LEVEL.INFO then return end
    emit("INFO", msg, ...)
end

function Log.Debug(msg, ...)
    if level < CAPTURE_LEVEL.DEBUG then return end
    emit("DEBUG", msg, ...)
end

function Log.Verbose(msg, ...)
    if level < CAPTURE_LEVEL.VERBOSE then return end
    emit("VERBOSE", msg, ...)
end

-- True when messages of this level ("DEBUG", "VERBOSE") are captured: check
-- before building a costly message.
function Log.Enabled(levelName)
    return level >= (CAPTURE_LEVEL[levelName] or 0)
end

-- Plain-text gold for log lines: 183g 05s 00c (no colour codes).
function Log.Money(copper)
    copper = tonumber(copper)
    if not copper then return "?" end
    local sign = copper < 0 and "-" or ""
    copper = math.floor(math.abs(copper) + 0.5)
    return string.format("%s%dg %02ds %02dc", sign, math.floor(copper / 10000),
        math.floor(copper % 10000 / 100), copper % 100)
end

-- "Weighted Boomshots R2 (257752)": name when the client has it, rank when known.
function Log.Item(itemID)
    if not itemID then return "?" end
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    local rank = GAM.ItemRanks and GAM.ItemRanks[itemID]
    return string.format("%s%s (%s)", name or "item", rank and (" R" .. rank) or "", tostring(itemID))
end

-- Verbose only: report work that took longer than a frame should. `started`
-- is a debugprofilestop() value taken before the work.
local SLOW_MS = 50
function Log.Slow(label, started)
    if level < CAPTURE_LEVEL.VERBOSE or not started or not debugprofilestop then return end
    local ms = debugprofilestop() - started
    if ms >= SLOW_MS then emit("VERBOSE", "Perf: %s took %d ms", label, math.floor(ms + 0.5)) end
end

-- Wraps a function that returns nothing so Verbose reports slow calls.
-- Below Verbose it is a plain call.
function Log.Timed(label, fn)
    return function(...)
        if level < CAPTURE_LEVEL.VERBOSE or not debugprofilestop then return fn(...) end
        local started = debugprofilestop()
        fn(...)
        Log.Slow(label, started)
    end
end

-- Ordered list of current entries (oldest → newest).
function Log.GetEntries()
    local out = {}
    local stored = math.min(count, SIZE)
    local startIdx = (count <= SIZE) and 1 or ((head % SIZE) + 1)
    for i = 0, stored - 1 do
        local entry = buf[((startIdx - 1 + i) % SIZE) + 1]
        if entry then out[#out + 1] = entry end
    end
    return out
end

function Log.FormatEntry(entry)
    local area = entry.area ~= Log.GENERAL_AREA and ("[" .. entry.area .. "]") or ""
    return string.format("[%s][%s]%s %s", entry.time, entry.level, area, entry.text)
end

-- Plain text of the entries accepted by `filter` (all when nil), for copying.
function Log.GetAllText(filter)
    local lines = {}
    for _, entry in ipairs(Log.GetEntries()) do
        if not filter or filter(entry) then lines[#lines + 1] = Log.FormatEntry(entry) end
    end
    return table.concat(lines, "\n")
end

-- Entry counts by level and the areas present, for the log filters.
function Log.GetSummary()
    local levels, areaSet, areas = {}, {}, {}
    for _, entry in ipairs(Log.GetEntries()) do
        levels[entry.level] = (levels[entry.level] or 0) + 1
        if not areaSet[entry.area] then
            areaSet[entry.area] = true
            areas[#areas + 1] = entry.area
        end
    end
    table.sort(areas)
    return { levels = levels, areas = areas }
end

function Log.Clear()
    buf, head, count = {}, 0, 0
    emit("INFO", (GAM.L and GAM.L["LOG_CLEARED"]) or "[Log cleared]")
end
