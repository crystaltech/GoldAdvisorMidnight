-- GoldAdvisorMidnight/Locale.lua
-- Localization-ready string table. All UI strings go through L[].
-- Module: GAM.L

local ADDON_NAME, GAM = ...
local L = {}
GAM.L = L

-- General
L["ADDON_TITLE"]           = "Gold Advisor Midnight"
L["LOADED_MSG"]            = "Gold Advisor Midnight v%s loaded. /gam to toggle."

-- Main Window
L["MAIN_TITLE"]            = "Gold Advisor Midnight"
L["FILTER_PATCH"]          = "Patch:"
L["FILTER_PROFESSION"]     = "Profession:"
L["FILTER_SEARCH"]         = "Search..."
L["COL_STRAT"]             = "Strategy"
L["COL_PROF"]              = "Profession"
L["COL_PROFIT"]            = "Profit"
L["COL_ROI"]               = "ROI%"
L["COL_STATUS"]            = "Status"
L["BTN_SCAN_ALL"]          = "Scan All"
L["BTN_SCAN_STOP"]         = "Stop Scan"
L["BTN_SHOPPING"]          = "Shopping List"
L["BTN_LOG"]               = "Debug Log"
L["BTN_CLOSE"]             = "Close"
L["NO_STRATS"]             = "No strategies match filters."
L["MISSING_PRICES"]        = "! Missing prices"
L["STATUS_STALE"]          = "Stale"
L["STATUS_FRESH"]          = "Fresh"
L["STATUS_NEVER"]          = "Never scanned"

-- Strat Detail
L["DETAIL_TITLE"]          = "Strategy Detail"
L["DETAIL_OUTPUT"]         = "Output:"
L["DETAIL_REAGENTS"]       = "Reagents:"
L["COL_ITEM"]              = "Item"
L["COL_QTY_CRAFT"]         = "Total Qty"
L["COL_HAVE"]              = "In Bags"
L["COL_NEED_BUY"]          = "Need to Buy"
L["COL_UNIT_PRICE"]        = "Unit Price"
L["COL_TOTAL_COST"]        = "Total Cost"
L["BTN_SCAN_ITEM"]         = "Scan"
L["BTN_SCAN_ALL_ITEMS"]    = "Scan All Items"
L["BTN_PUSH_CRAFTSIM"]     = "Push to CraftSim"
L["TT_CRAFTSIM_TITLE"]     = "Push Price Overrides to CraftSim"
L["LBL_COST"]              = "Total Cost:"
L["LBL_REVENUE"]           = "Net Revenue:"
L["LBL_PROFIT"]            = "Profit:"
L["LBL_ROI"]               = "ROI:"
L["LBL_BREAKEVEN"]         = "Break-Even Sell:"
L["RANK_SELECT"]           = "Rank:"
L["NO_PRICE"]              = "—"
L["COL_REVENUE"]           = "Net Revenue"
L["TT_CRAFTSIM_WARN"]      = "Warning: This will overwrite any existing manual price overrides in CraftSim for all reagents in this strategy."
L["TT_SHOPPING_TITLE"]     = "Create Auctionator Shopping List"
L["TT_SHOPPING_BODY"]      = "Creates an Auctionator shopping list for the selected strategy's missing input items and keeps it synced as your bag counts change."

-- Shopping List
L["SHOP_TITLE"]            = "Shopping List"
L["SHOP_ITEM"]             = "Item"
L["SHOP_NEED"]             = "Need to Buy"
L["SHOP_HAVE"]             = "Have"
L["BTN_COPY_LIST"]         = "Copy"
L["BTN_AUCTIONATOR"]       = "Auctionator List"
L["SHOP_EMPTY"]            = "No items needed."
L["AUCTIONATOR_LIST_NAME"] = "GAM Shopping List"
L["MSG_AUCTIONATOR_CREATED"]   = "Auctionator list '%s' created (%d items). Open the Shopping tab to buy."
L["MSG_AUCTIONATOR_NO_ITEMS"]  = "Nothing needed — shopping list is empty."
L["MSG_AUCTIONATOR_NOT_FOUND"] = "Auctionator not installed. Install it to use this feature."

-- Debug Log
L["LOG_TITLE"]             = "Debug Log"
L["BTN_CLEAR_LOG"]         = "Clear"
L["BTN_COPY_LOG"]          = "Copy All"
L["BTN_PAUSE_LOG"]         = "Pause"
L["BTN_RESUME_LOG"]        = "Resume"
L["BTN_DUMP_IDS"]          = "Dump IDs"
L["BTN_ARP_EXPORT"]        = "Spreadsheet Export"
L["LOG_PAUSED"]            = "[Log paused]"
L["LOG_CLEARED"]           = "[Log cleared]"

-- Settings
L["SETTINGS_NAME"]         = "Gold Advisor Midnight"
-- Settings section headers (English only; other locales fall back to these)
L["SETTINGS_SECTION_SCAN"]     = "Scan Settings"
L["SETTINGS_SECTION_DISPLAY"]  = "Display"
L["SETTINGS_SECTION_PRICING"]  = "Pricing"
L["SETTINGS_SECTION_ACTIONS"]  = "Actions"
L["SETTINGS_SECTION_CREDITS"]  = "Credits & Thanks"
L["OPT_SCAN_DELAY"]       = "Scan Delay (sec)"
L["OPT_SCAN_DELAY_TIP"]   = "Seconds between AH queries. Lower = faster but risks throttling."
L["OPT_VERBOSITY"]        = "Debug Verbosity"
L["OPT_VERBOSITY_TIP"]    = "0=off, 1=info, 2=debug, 3=verbose"
L["OPT_MINIMAP"]          = "Show Minimap Button"
L["OPT_UI_SCALE"]         = "UI Scale"
L["OPT_UI_SCALE_TIP"]     = "Scales all Gold Advisor frames. 1.0 = default size."
L["OPT_UI_SCALE_RANGE"]   = "(0.7 - 1.5)"
L["OPT_RANK_POLICY"]      = "Rank Selection Policy"
L["OPT_RANK_HIGHEST"]     = "Highest Rank"
L["OPT_RANK_LOWEST"]      = "Lowest Rank"
L["BTN_RELOAD_DATA"]      = "Reload Data"
L["BTN_CLEAR_CACHE"]      = "Clear Price Cache"
L["BTN_OPEN_LOG"]         = "Open Debug Log"
L["BTN_APPLY_CLOSE"]      = "Apply & Close"

-- Strategy Creator
L["BTN_CREATE_STRAT"]      = "Create Strategy"
L["BTN_IMPORT_STRAT"]      = "Import Strategy"
L["BTN_EXPORT_STRAT"]      = "Export"
L["BTN_EDIT_STRAT"]        = "Edit"
L["BTN_DELETE_STRAT"]      = "Delete"
L["CREATOR_TITLE"]         = "Create Strategy"
L["CREATOR_PROFESSION"]    = "Profession:"
L["CREATOR_NAME"]          = "Strategy Name:"
L["CREATOR_INPUT_QTY"]     = "Input Quantity:"
L["CREATOR_INPUT_QTY_TIP"] = "The base quantity all ratios are calculated against (e.g. 1000 herbs to mill)"
L["CREATOR_OUTPUTS"]       = "Outputs"
L["CREATOR_REAGENTS"]      = "Reagents"
L["CREATOR_NOTES"]         = "Notes:"
L["CREATOR_COL_NAME"]      = "Item Name"
L["CREATOR_COL_ITEMID"]    = "Item ID"
L["CREATOR_COL_QTY"]       = "Qty"
L["BTN_CREATOR_SAVE"]      = "Save"
L["BTN_CREATOR_DELETE"]    = "Delete"
L["BTN_CREATOR_ADD_OUT"]   = "+ Output"
L["BTN_CREATOR_ADD_REAG"]  = "+ Reagent"
L["CREATOR_CUSTOM_PROF"]   = "(Custom...)"
L["MSG_STRAT_SAVED"]       = "Strategy '%s' saved."
L["MSG_STRAT_DELETED"]     = "Strategy '%s' deleted."
L["EXPORT_POPUP_TITLE"]    = "Export Strategy"
L["EXPORT_ENCODED_LBL"]    = "Encoded — share with other GAM users:"
L["EXPORT_LUA_LBL"]        = "File-edit — paste into Data/StratsManual.lua:"
L["IMPORT_POPUP_TITLE"]    = "Import Strategy"
L["IMPORT_ENCODED_LBL"]    = "Paste encoded string (GAM1:...):"
L["MSG_STRAT_IMPORTED"]    = "Strategy '%s' imported."
L["ERR_IMPORT_INVALID"]    = "Invalid or unrecognized import string."

-- Minimap
L["MINIMAP_TIP"]           = "Gold Advisor Midnight\nLeft-click: Toggle window\nRight-click: Settings\nDrag: Move button"

-- Scanning
L["SCAN_STARTED"]          = "Scanning %d items..."
L["SCAN_COMPLETE"]         = "Scan complete. %d OK, %d failed."
L["SCAN_AH_CLOSED"]        = "AH closed — scan stopped."
L["SCAN_THROTTLED"]        = "AH throttled, retrying..."
L["PRICE_UPDATED"]         = "Price updated: %s = %s"

-- Errors / Warnings
L["ERR_NO_AH"]             = "Open the Auction House first."
L["ERR_STRAT_INVALID"]     = "Invalid strategy: %s"
L["WARN_PRICE_STALE"]      = "Prices may be stale (>%d min)."

-- Fill Qty setting
L["OPT_SHALLOW_FILL_TIP"]  = "Prices are calculated by simulating the purchase of this many units from the AH order book. Lower values reflect the cost of smaller batches; higher values average across more supply. Range: 10–10,000."
L["OPT_SHALLOW_FILL_QTY"]  = "Fill Qty:"
L["OPT_SHALLOW_FILL_RANGE"] = "(10 - 10,000)"
L["FILL_QTY_ACTIVE"]       = "Fill Qty: %s units"

-- Strat Detail (section headers / rank toggle)
L["DETAIL_INPUT_HDR"]      = "Input Items"
L["DETAIL_OUTPUT_HDR"]     = "Output Items"
L["RANK_BTN_R1"]           = "R1 Mats"
L["RANK_BTN_R2"]           = "R2 Mats"

-- Strategy Creator (edit mode title / validation errors)
L["CREATOR_EDIT_TITLE"]    = "Edit Strategy"
L["CONFIRM_DELETE_BODY"]   = "Delete strategy:\n\"|cffffffff%s|r\"\n\nThis cannot be undone."
L["BTN_REMOVE"]            = "x"
L["CREATOR_INPUT_HINT"]    = "(all qtys below are per this many inputs)"
L["ERR_PROF_REQUIRED"]     = "Profession is required."
L["ERR_NAME_REQUIRED"]     = "Strategy name is required."
L["ERR_QTY_REQUIRED"]      = "Input quantity must be greater than 0."
L["ERR_OUTPUT_REQUIRED"]   = "At least one output is required."

-- Main Window (scan progress / strat count status)
L["STATUS_SCANNING_PROG"]  = "scanning..."
L["STATUS_QUEUING"]        = "Queuing items..."
L["STATUS_STRAT_COUNT"]    = "%d strategies"

-- V2 / additional UI labels
L["V2_TOOLS_TITLE"]        = "Strategy Tools"
L["V2_BEST_TITLE"]         = "Best Strategy"
L["V2_ALL_STRATS"]         = "All Strategies"
L["V2_MY_PROFS"]           = "My Profs"
L["V2_ALL_FILTER"]         = "All"
L["V2_FILL_QTY"]           = "Fill Qty"
L["V2_MILL_OWN_HERBS"]     = "Mill own herbs"
L["V2_CRAFT_OWN_BOLTS"]    = "Craft own bolts"
L["V2_CRAFT_OWN_INGOTS"]   = "Craft own ingots"
L["V2_CRAFT_STATS"]        = "Craft Stats"
L["V2_MATERIAL_RANK"]      = "Material Rank"
L["V2_SELECT_FORMULA"]     = "Select a formula strategy"
L["BTN_SCAN_SELECTED"]     = "Scan Selected Strat"
L["BTN_OPEN_STRAT"]        = "Open Strategy"
L["BTN_CRAFTSIM_SHORT"]    = "CraftSim"
L["BTN_SHOPPING_SHORT"]    = "Shopping"
L["V2_COL_TOTAL"]          = "Total"
L["V2_COL_NEED"]           = "Need"
L["V2_COL_PRICE"]          = "Price"
L["V2_COL_NET"]            = "Net"

GAM._ea = "QRSTUVWXYZabcdefvutsrqponmlkjihg"   -- encoding alphabet part A
