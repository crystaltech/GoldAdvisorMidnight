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
--   1. Overriding output names/itemIDs/multipliers for generated strats
--   2. Adjusting defaultStartingAmount for specific strats
--   3. Adding entirely new strats not captured by the Python parser
-- ──────────────────────────────────────────────────────────────────────────

-- ─── Inscription: output name fixes ──────────────────────────────────────
-- "Munsell Ink" — spreadsheet copy-paste error left the output price row
-- labelled "Sienna Ink" instead of "Munsell Ink", so the parser assigned the
-- wrong output.  Munsell Ink itemIDs confirmed from Engineering reagent data.
-- qtyMultiplier uses the generated value (0.18 = 3600 inks per 20000 powder, 17% res 26% multi).
GAM_STRATS_MANUAL[#GAM_STRATS_MANUAL+1] = {
    patchTag   = "midnight-1",
    profession = "Inscription",
    stratName  = "Munsell Ink",
    output = {
        name    = "Munsell Ink",
        itemIDs = { 245801, 245802 },  -- Q1=245801, Q2=245802
    },
}

-- ─── Leatherworking: output name fixes ───────────────────────────────────
-- The March 10, 2026 workbook keeps the same output-name layout ambiguity in
-- the LW craft blocks, so we pin the crafted output names/IDs here and also
-- match the workbook's default starting amounts.
--
-- Item IDs confirmed via ranked mats export.
GAM_STRATS_MANUAL[#GAM_STRATS_MANUAL+1] = {
    patchTag   = "midnight-1",
    profession = "Leatherworking",
    stratName  = "Scale Woven Hide",
    defaultStartingAmount = 2000,
}

GAM_STRATS_MANUAL[#GAM_STRATS_MANUAL+1] = {
    patchTag   = "midnight-1",
    profession = "Leatherworking",
    stratName  = "Sin'Dorei Armor Banding",
    defaultStartingAmount = 2000,
    output = {
        name          = "Sin'dorei Armor Banding",  -- WoW uses lowercase 'd'
        itemIDs       = { 244635, 244636 },
        qtyMultiplier = 0.85,
    },
}

GAM_STRATS_MANUAL[#GAM_STRATS_MANUAL+1] = {
    patchTag   = "midnight-1",
    profession = "Leatherworking",
    stratName  = "Silvermoon Weapon Wrap",
    defaultStartingAmount = 2000,
    output = {
        name          = "Silvermoon Weapon Wrap",
        itemIDs       = { 244637, 244638 },
        qtyMultiplier = 0.85,
    },
}

-- ─── Enchanting: Shatter strats ───────────────────────────────────────────
-- "Dawn Shatter Q2" — shatter rank-2 Dawn Crystals into Radiant Shards.
--   The spreadsheet strat name is not an item; the outputs are Q2 and Q1 Radiant Shards.
--   Reagent Dawn Crystal already has correct itemIDs from StratsGenerated.lua.
GAM_STRATS_MANUAL[#GAM_STRATS_MANUAL+1] = {
    patchTag   = "midnight-1",
    profession = "Enchanting",
    stratName  = "Dawn Shatter Q2",
    notes      = "Shatters rank-2 Dawn Crystals into Radiant Shards (Q1+Q2)",
    output = {
        name          = "Radiant Shard",
        itemIDs       = { 243602, 243603 },  -- Q1=243602, Q2=243603
        qtyMultiplier = 2.3955,              -- expected Q2 shards per start amount
    },
    -- Both outputs included so Pricing can sum Q1+Q2 revenue
    outputs = {
        { name = "Radiant Shard Q2", itemIDs = { 243603 }, qtyMultiplier = 2.3955 },
        { name = "Radiant Shard Q1", itemIDs = { 243602 }, qtyMultiplier = 0.9465 },
    },
    reagents = {},  -- reagent (Dawn Crystal) inherited from StratsGenerated.lua
}

-- "Radiant Shatter Q2" — shatter rank-2 Radiant Shards into Eversinging Dust.
--   "Radiant Shatter" is a profession spell requiring rank-2 Radiant Shards as input.
--   Reagent Radiant Shard already has correct itemIDs from StratsGenerated.lua.
GAM_STRATS_MANUAL[#GAM_STRATS_MANUAL+1] = {
    patchTag   = "midnight-1",
    profession = "Enchanting",
    stratName  = "Radiant Shatter Q2",
    notes      = "Shatters rank-2 Radiant Shards into Eversinging Dust (Q1+Q2)",
    output = {
        name          = "Eversinging Dust",
        itemIDs       = { 243599, 243600 },  -- Q1=243599, Q2=243600
        qtyMultiplier = 2.3334,              -- expected Q2 dust per start amount
    },
    outputs = {
        { name = "Eversinging Dust Q2", itemIDs = { 243600 }, qtyMultiplier = 2.3334 },
        { name = "Eversinging Dust Q1", itemIDs = { 243599 }, qtyMultiplier = 1.0000 },
    },
    reagents = {},  -- reagent (Radiant Shard) inherited from StratsGenerated.lua
}
