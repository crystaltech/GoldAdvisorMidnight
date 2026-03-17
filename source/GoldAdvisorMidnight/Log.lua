-- GoldAdvisorMidnight/Log.lua
-- Ring-buffer debug log. Zero garbage in hot path when verbosity disabled.
-- Module: GAM.Log

local ADDON_NAME, GAM = ...
local Log = {}
GAM.Log = Log

-- Ring buffer state (populated after Constants load)
local buf    = {}  -- fixed-size array
local head   = 0   -- next write index (0-based)
local count  = 0   -- total entries ever written
local SIZE   = 500 -- overwritten by Init()
local paused = false

-- Verbosity level (0=off,1=info,2=debug,3=verbose)
local level  = 1

-- Listeners: frames that want to receive new entries
local listeners = {}

local function timestamp()
    return date("%H:%M:%S")
end

local function emit(entry)
    if paused then return end
    -- Write to ring buffer
    local idx = (head % SIZE) + 1
    buf[idx]  = entry
    head      = head + 1
    count     = count + 1
    -- Notify listeners (DebugLog frame)
    for i = 1, #listeners do
        local ok, err = pcall(listeners[i], entry)
        if not ok then
            -- Don't recurse; listeners must be safe
        end
    end
end

function Log.Init(ringSize, verbosity)
    SIZE  = ringSize or 500
    level = verbosity or 1
    buf   = {}
end

function Log.SetLevel(v)
    level = v or 1
end

function Log.SetPaused(p)
    paused = p
end

function Log.IsPaused()
    return paused
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

-- Core write methods — string.format only when level passes
function Log.Warn(msg, ...)
    local s = (select('#', ...) > 0) and msg:format(...) or msg
    emit(string.format("[%s][WARN] %s", timestamp(), s))
end

function Log.Info(msg, ...)
    if level < 1 then return end
    local s = (select('#', ...) > 0) and msg:format(...) or msg
    emit(string.format("[%s][INFO] %s", timestamp(), s))
end

function Log.Debug(msg, ...)
    if level < 2 then return end
    local s = (select('#', ...) > 0) and msg:format(...) or msg
    emit(string.format("[%s][DBG]  %s", timestamp(), s))
end

function Log.Verbose(msg, ...)
    if level < 3 then return end
    local s = (select('#', ...) > 0) and msg:format(...) or msg
    emit(string.format("[%s][VRB]  %s", timestamp(), s))
end

-- Returns ordered list of current buffer entries (oldest → newest)
function Log.GetEntries()
    local out = {}
    if count == 0 then return out end
    local stored = math.min(count, SIZE)
    local startIdx
    if count <= SIZE then
        startIdx = 1
    else
        startIdx = (head % SIZE) + 1
    end
    for i = 0, stored - 1 do
        local idx = ((startIdx - 1 + i) % SIZE) + 1
        if buf[idx] then
            out[#out + 1] = buf[idx]
        end
    end
    return out
end

function Log.GetAllText()
    return table.concat(Log.GetEntries(), "\n")
end

function Log.Clear()
    buf   = {}
    head  = 0
    count = 0
    emit("[" .. timestamp() .. "][INFO] " .. (GAM.L and GAM.L["LOG_CLEARED"] or "[Log cleared]"))
end

GAM._ls = "Gold"   -- log-sink identifier
