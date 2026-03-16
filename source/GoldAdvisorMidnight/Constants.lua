-- GoldAdvisorMidnight/Constants.lua
-- Central configuration. All tunable values live here.
-- Module: GAM.C

local ADDON_NAME, GAM = ...
GAM.C = {
    ADDON_VERSION        = "1.2.8",
    DATA_VERSION         = 5,
    DEFAULT_PATCH        = "midnight-1",

    -- Base crafting-stat multipliers (game-level, before talent/spec node bonuses)
    BASE_MCM             = 1.25,   -- Multicraft multiplier base (MCm before any node bonus)
    BASE_RS              = 0.30,   -- Resourcefulness saved fraction base (Rs before any node bonus)

    -- Economy
    AH_CUT               = 0.05,   -- 5% AH fee (also used as the DB default)

    -- AH scanning throttle (seconds)
    SCAN_DELAY           = 1.0,    -- between successive queries
    RESULT_WAIT          = 10.0,   -- timeout waiting for results
    RESULT_RETRY_DELAY   = 0.5,    -- between retry attempts
    MAX_RETRY            = 5,
    EVENT_PROCESS_DELAY  = 0.8,    -- wait after event before reading results

    -- Pricing
    PRICE_STALE_SECONDS  = 600,    -- 10-minute cache freshness

    -- Debug log
    LOG_RING_SIZE        = 500,

    -- Default options (mirrors DB.options defaults)
    DEFAULT_SCAN_DELAY   = 1.0,
    DEFAULT_VERBOSITY    = 1,      -- 0=off,1=info,2=debug,3=verbose
    DEFAULT_RANK_POLICY  = "lowest",
    DEFAULT_PRICE_SOURCE         = "ah",
    DEFAULT_PIGMENT_COST_SOURCE  = "ah",  -- "ah" | "mill"

    -- Crafting stat defaults (integer %; match baked spreadsheet baseline values)
    -- Milling, Prospecting, Crushing, Shattering: no Multicraft stat (profession window doesn't show it).
    -- Inscription
    DEFAULT_INSC_MILLING_RES   = 32,   -- Resourcefulness % for Inscription milling
    DEFAULT_INSC_INK_MULTI     = 26,   -- Multicraft % for Inscription ink crafting
    DEFAULT_INSC_INK_RES       = 17,   -- Resourcefulness % for Inscription ink crafting
    -- Jewelcrafting
    DEFAULT_JC_PROSPECT_RES    = 33,   -- Resourcefulness % for JC prospecting
    DEFAULT_JC_CRUSH_RES       = 35,   -- Resourcefulness % for JC crushing
    DEFAULT_JC_CRAFT_MULTI     = 30,   -- Multicraft % for JC gem crafting
    DEFAULT_JC_CRAFT_RES       = 18,   -- Resourcefulness % for JC gem crafting
    -- Enchanting
    DEFAULT_ENCH_SHATTER_RES   = 30,   -- Resourcefulness % for Enchanting shattering
    DEFAULT_ENCH_CRAFT_MULTI   = 25,   -- Multicraft % for Enchanting oil/edge crafting
    DEFAULT_ENCH_CRAFT_RES     = 16,   -- Resourcefulness % for Enchanting oil/edge crafting
    -- Alchemy
    DEFAULT_ALCH_MULTI         = 30,   -- Multicraft % for Alchemy
    DEFAULT_ALCH_RES           = 15,   -- Resourcefulness % for Alchemy
    -- Tailoring
    DEFAULT_TAIL_MULTI         = 25,   -- Multicraft % for Tailoring
    DEFAULT_TAIL_RES           = 15,   -- Resourcefulness % for Tailoring
    -- Blacksmithing
    DEFAULT_BS_MULTI           = 28,   -- Multicraft % for Blacksmithing
    DEFAULT_BS_RES             = 19,   -- Resourcefulness % for Blacksmithing
    -- Leatherworking
    DEFAULT_LW_MULTI           = 29,   -- Multicraft % for Leatherworking
    DEFAULT_LW_RES             = 17,   -- Resourcefulness % for Leatherworking
    -- Engineering
    DEFAULT_ENG_MULTI          = 0,    -- * Multicraft % for Engineering (baseline: 0%)
    DEFAULT_ENG_RES            = 38,   -- Resourcefulness % for Engineering

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

    -- ── New UI (MainWindowV2) layout constants ────────────────────────────
    MAIN_WIN_W              = 960,   -- total frame width
    MAIN_WIN_H              = 580,   -- total frame height
    LEFT_PANEL_W            = 190,   -- left panel (tools/scan)
    RIGHT_PANEL_W           = 340,   -- right panel (inline detail); center = remainder
    HEADER_H                = 34,    -- title bar height
    STATUS_BAR_H            = 22,    -- bottom status bar height

    -- Best Strategy scoring thresholds
    BEST_STRAT_MIN_PROFIT   = 50000, -- 5g minimum profit to qualify (copper)
    BEST_STRAT_MIN_ROI      = 5,     -- 5% minimum ROI to qualify
}
