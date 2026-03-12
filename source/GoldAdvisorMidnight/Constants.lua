-- GoldAdvisorMidnight/Constants.lua
-- Central configuration. All tunable values live here.
-- Module: GAM.C

local ADDON_NAME, GAM = ...
GAM.C = {
    ADDON_VERSION        = "1.2.0",
    DATA_VERSION         = 4,
    DEFAULT_PATCH        = "midnight-1",

    -- Economy
    AH_CUT               = 0.05,   -- 5% AH fee

    -- AH scanning throttle (seconds)
    SCAN_DELAY           = 1.0,    -- between successive queries
    RESULT_WAIT          = 10.0,   -- timeout waiting for results
    RESULT_RETRY_DELAY   = 0.5,    -- between retry attempts
    MAX_RETRY            = 5,
    EVENT_PROCESS_DELAY  = 0.8,    -- wait after event before reading results
    DEBOUNCE_DELAY       = 1.0,    -- suppress duplicate events within window

    -- Pricing
    PRICE_STALE_SECONDS  = 600,    -- 10-minute cache freshness

    -- Debug log
    LOG_RING_SIZE        = 500,

    -- Default options (mirrors DB.options defaults)
    DEFAULT_AH_CUT       = 0.05,
    DEFAULT_SCAN_DELAY   = 1.0,
    DEFAULT_VERBOSITY    = 1,      -- 0=off,1=info,2=debug,3=verbose
    DEFAULT_RANK_POLICY  = "lowest",
    DEFAULT_PRICE_SOURCE = "ah",

    -- UI scale
    DEFAULT_UI_SCALE     = 1.0,    -- frame scale applied to non-settings addon windows/popups
    MIN_UI_SCALE         = 0.7,
    MAX_UI_SCALE         = 1.5,

    -- Fill-price simulation quantities
    DEFAULT_FILL_QTY = 50,     -- default fill qty for AH price simulation
    MIN_FILL_QTY     = 10,     -- minimum configurable fill qty
    MAX_FILL_QTY     = 10000,  -- maximum configurable fill qty

    -- Price trimming: ARP-style percentage trim from the expensive end
    -- After filling to targetQty, the top TRIM_PCT% most expensive units are dropped.
    -- Matches ARP Tracker default (Trim: 2). Range 0–100; 0 = no trim.
    TRIM_PCT                 = 2,
}
