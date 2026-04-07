-- GoldAdvisorMidnight/Constants.lua
-- Central configuration. All tunable values live here.
-- Module: GAM.C

local ADDON_NAME, GAM = ...
local workbookProfiles = (GAM_WORKBOOK_GENERATED and GAM_WORKBOOK_GENERATED.formulaProfiles) or {}

local function ProfileDefault(profileKey, field, fallback)
    local profile = workbookProfiles[profileKey]
    local value = profile and profile[field]
    if value == nil then
        return fallback
    end
    return value
end

GAM.C = {
    ADDON_VERSION        = "1.7.22",
    DATA_VERSION         = 12,
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
    DEFAULT_BOLT_COST_SOURCE     = "ah",  -- "ah" | "craft"
    DEFAULT_INGOT_COST_SOURCE    = "ah",  -- "ah" | "craft"

    -- Crafting stat defaults (percent values; decimals allowed; match workbook baseline values)
    -- Milling, Prospecting, Crushing, Shattering: no Multicraft stat (profession window doesn't show it).
    -- Inscription
    DEFAULT_INSC_MILLING_RES   = ProfileDefault("insc_milling", "defaultRes", 30.1),
    DEFAULT_INSC_INK_MULTI     = ProfileDefault("insc_ink", "defaultMulti", 29.7),
    DEFAULT_INSC_INK_RES       = ProfileDefault("insc_ink", "defaultRes", 16.1),
    -- Jewelcrafting
    DEFAULT_JC_PROSPECT_RES    = ProfileDefault("jc_prospect", "defaultRes", 33),
    DEFAULT_JC_CRUSH_RES       = ProfileDefault("jc_crush", "defaultRes", 33.0),
    DEFAULT_JC_CRAFT_MULTI     = ProfileDefault("jc_craft", "defaultMulti", 29.5),
    DEFAULT_JC_CRAFT_RES       = ProfileDefault("jc_craft", "defaultRes", 33.0),
    -- Enchanting
    DEFAULT_ENCH_SHATTER_RES   = ProfileDefault("ench_shatter", "defaultRes", 7.8),
    DEFAULT_ENCH_CRAFT_MULTI   = ProfileDefault("ench_craft", "defaultMulti", 24.5),
    DEFAULT_ENCH_CRAFT_RES     = ProfileDefault("ench_craft", "defaultRes", 16),
    -- Alchemy
    DEFAULT_ALCH_MULTI         = ProfileDefault("alchemy", "defaultMulti", 30),
    DEFAULT_ALCH_RES           = ProfileDefault("alchemy", "defaultRes", 15),
    -- Tailoring
    DEFAULT_TAIL_MULTI         = ProfileDefault("tailoring", "defaultMulti", 21.4),
    DEFAULT_TAIL_RES           = ProfileDefault("tailoring", "defaultRes", 12.1),
    -- Blacksmithing
    DEFAULT_BS_MULTI           = ProfileDefault("blacksmithing", "defaultMulti", 27.9),
    DEFAULT_BS_RES             = ProfileDefault("blacksmithing", "defaultRes", 18.7),
    -- Leatherworking
    DEFAULT_LW_MULTI           = ProfileDefault("leatherworking", "defaultMulti", 32.0),
    DEFAULT_LW_RES             = ProfileDefault("leatherworking", "defaultRes", 14.9),
    -- Engineering (split: recycling has no multi; crafting has separate multi/res)
    DEFAULT_ENG_RECYCLE_RES    = ProfileDefault("engineering_recycling", "defaultRes", 36.0),
    DEFAULT_ENG_CRAFT_MULTI    = ProfileDefault("engineering_craft", "defaultMulti", 31.1),
    DEFAULT_ENG_CRAFT_RES      = ProfileDefault("engineering_craft", "defaultRes", 20.4),

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
    MAIN_WIN_W              = 1080,  -- total frame width
    MAIN_WIN_H              = 680,   -- total frame height (increased to fit profession dropdown + ticker)
    LEFT_PANEL_W            = 190,   -- left panel (tools/scan)
    RIGHT_PANEL_W           = 420,   -- right panel (inline detail); center = remainder
    HEADER_H                = 34,    -- title bar height
    STATUS_BAR_H            = 22,    -- bottom status bar height
    TICKER_H                = 18,    -- community info scrolling ticker height

    -- Best Strategy scoring thresholds
    BEST_STRAT_MIN_PROFIT   = 50000, -- 5g minimum profit to qualify (copper)
    BEST_STRAT_MIN_ROI      = 5,     -- 5% minimum ROI to qualify

    -- Vendor-purchasable items: static buy prices in copper.
    -- Checked in GetEffectivePrice after manual overrides — no AH scan needed.
    VENDOR_PRICES = {
        [245881] = 2105,   -- Lexicologist's Vellum (21s 5c)
        [245882] = 3595,   -- Thalassian Songwater  (35s 95c)
        [243060] = 5000,   -- Luminant Flux         (50s)
        [251665] = 5000,   -- Silverleaf Thread     (50s)
    },
}
