-- GoldAdvisorMidnight/Data/StratsManual.lua
-- Manual strat overrides and itemID assignments for Midnight items.
-- Loaded AFTER StratsGenerated.lua.
-- Entries here can:
--   1. Override itemIDs for existing generated strats (matched by profession+stratName+patchTag)
--   2. Add entirely new strats not captured by the Python parser
--
-- HOW TO USE:
--   Add item IDs as you discover them in-game or from Wowhead.
--   patchTag must match the generated strat you want to override.
--   itemIDs = { Q1_id, Q2_id, Q3_id } — lowest to highest quality/rank.

--[[
  ═══════════════════════════════════════════════════════════════════
  CREATING A NEW CUSTOM STRATEGY  (file-edit method)
  ═══════════════════════════════════════════════════════════════════

  EASIER WAY: use the in-game creator!
    Minimap icon → right-click → Settings → "Create Strategy"
    Then open the strategy and click "Export" to get a snippet to paste here.

  MANUAL WAY: copy the template below, fill it in, and paste it at the
  BOTTOM of this file. Then type /reload in WoW.

  ─────────────────────────────────────────────────────────────────
  TEMPLATE — copy from here ↓
  ─────────────────────────────────────────────────────────────────

  GAM_STRATS_MANUAL[#GAM_STRATS_MANUAL + 1] = {
      profession  = "Alchemy",      -- Alchemy / Inscription / Enchanting / Engineering / etc.
      stratName   = "My Strategy",  -- unique name shown in the list
      patchTag    = "midnight-1",   -- leave as-is for the current patch

      defaultStartingAmount = 1000, -- the "per N inputs" base; all qtys below scale to this

      output = {
          name          = "Output Item Name",
          itemIDs       = { 123456 },   -- WoW item ID(s) [Q1, Q2, ...]; use {} if unknown
          qtyMultiplier = 0.85,         -- expected output qty ÷ defaultStartingAmount
                                        -- e.g. 850 outputs from 1000 inputs → 850/1000 = 0.85
      },

      reagents = {
          { name = "Reagent One",  itemIDs = { 111111 }, qtyMultiplier = 1.0 },
          { name = "Reagent Two",  itemIDs = { 222222 }, qtyMultiplier = 2.5 },
          -- add more rows as needed
      },

      notes = "",   -- optional free text
  }

  ─────────────────────────────────────────────────────────────────
  FINDING ITEM IDs
  ─────────────────────────────────────────────────────────────────
  • Wowhead URL:  wowhead.com/item=245867  → the number is the item ID (245867)
  • In-game:      scan with Gold Advisor, then /gam log → "Dump IDs"
  • Rank order:   itemIDs = { Q1_id, Q2_id }  — lowest quality first

  KEY FORMULA:
    qtyMultiplier = (expected output qty) ÷ defaultStartingAmount
    e.g. 850 pigment from 1000 herbs  →  850 / 1000 = 0.85
    e.g. 1500 ore needed per 1000 crafts  →  1500 / 1000 = 1.5

  ─────────────────────────────────────────────────────────────────
  MULTI-OUTPUT STRATS  (prospecting, shattering, etc.)
  ─────────────────────────────────────────────────────────────────
  Replace "output = {...}" with both an "output" stub AND an "outputs" array:

      output  = { name = "Primary Output", itemIDs = {}, qtyMultiplier = 0 },
      outputs = {
          { name = "Q2 Result", itemIDs = { 243603 }, qtyMultiplier = 2.395 },
          { name = "Q1 Result", itemIDs = { 243602 }, qtyMultiplier = 0.946 },
      },

  See "Dawn Shatter Q2" in this file for a live example.
--]]
--
-- EXAMPLE OVERRIDE (uncomment and fill in real IDs):
--[[
GAM_STRATS_MANUAL[#GAM_STRATS_MANUAL+1] = {
    patchTag   = "midnight-1",
    profession = "Alchemy",
    stratName  = "Composite Flora",
    output = {
        name    = "Composite Flora",
        itemIDs = { 999001, 999002 },  -- Q1, Q2 item IDs
    },
    reagents = {
        { name = "Mote of Wild Magic",    itemIDs = { 888001, 888002, 888003 } },
        { name = "Mote of Primal Energy", itemIDs = { 888004, 888005, 888006 } },
        { name = "Tranquility Bloom",     itemIDs = { 888007, 888008, 888009 } },
        { name = "Argentleaf",            itemIDs = { 888010, 888011, 888012 } },
    },
}
--]]

GAM_STRATS_MANUAL = GAM_STRATS_MANUAL or {}

-- ─── Item IDs ─────────────────────────────────────────────────────────────
-- Raw material itemIDs are now embedded directly in StratsGenerated.lua via
-- references/goldadvisor_mats_ranked.json (run build/generate_strats.py to refresh).
--
-- Use this file only for:
--   1. New strats not captured by the Python parser
--   2. Hotfixes that haven't yet been folded back into StratsGenerated.lua
-- ──────────────────────────────────────────────────────────────────────────

