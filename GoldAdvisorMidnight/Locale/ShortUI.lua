-- GoldAdvisorMidnight/Locale/ShortUI.lua
-- Short, stable labels for constrained UI surfaces across all locales.

local ADDON_NAME, GAM = ...
local L = GAM and GAM.L
if not L then
    return
end

local SHORT_UI_OVERRIDES = {
    FILTER_SEARCH = "Search...",
    COL_STRAT = "Strat",
    COL_PROF = "Prof",
    COL_PROFIT = "Profit",
    COL_STATUS = "Status",
    BTN_SCAN_ALL = "Scan All",
    BTN_SCAN_STOP = "Stop",
    DETAIL_TITLE = "Strategy Detail",
    DETAIL_OUTPUT = "Output:",
    DETAIL_REAGENTS = "Reagents:",
    DETAIL_INPUT_HDR = "Input Items",
    DETAIL_OUTPUT_HDR = "Output Items",
    COL_ITEM = "Item",
    COL_QTY_CRAFT = "Total",
    COL_HAVE = "Own",
    COL_NEED_BUY = "Need",
    COL_UNIT_PRICE = "Price",
    COL_TOTAL_COST = "Cost",
    COL_REVENUE = "Net",
    COL_AH_SELL_PRICE = "AH Price",
    BTN_SCAN_ITEM = "Scan",
    BTN_SCAN_ALL_ITEMS = "Scan All",
    BTN_PUSH_CRAFTSIM = "Push CraftSim",
    BTN_AUCTIONATOR = "Auctionator",
    BTN_COPY_LOG = "Copy All",
    BTN_ARP_EXPORT = "ARP Export",
    OPT_SHALLOW_FILL_QTY = "Fill Qty:",
    LBL_COST = "Total Cost:",
    LBL_BUY_NOW_COST = "Buy Now Cost:",
    LBL_REVENUE = "Net Revenue:",
    LBL_PROFIT = "Profit:",
    LBL_BREAKEVEN = "Break-even:",
    RANK_SELECT = "Rank:",
    V2_TOOLS_TITLE = "Tools",
    V2_BEST_TITLE = "Best Strat",
    V2_ALL_STRATS = "All Strats",
    V2_MY_PROFS = "My Profs",
    V2_ALL_FILTER = "All",
    V2_FILL_QTY = "Fill Qty",
    V2_CRAFT_STATS = "Craft Stats",
    V2_MATERIAL_RANK = "Mat Rank",
    V2_SELECT_FORMULA = "Select formula",
    BTN_SCAN_SELECTED = "Scan Strat",
    BTN_SCAN_STRAT = "Scan Strat",
    BTN_OPEN_STRAT = "Open Strat",
    BTN_CRAFTSIM_SHORT = "CraftSim",
    BTN_SHOPPING_SHORT = "Shopping",
}

for key, value in pairs(SHORT_UI_OVERRIDES) do
    L[key] = value
end
