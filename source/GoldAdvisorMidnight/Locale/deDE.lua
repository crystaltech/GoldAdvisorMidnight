-- GoldAdvisorMidnight/Locale/deDE.lua
-- German (deDE) translations for Gold Advisor Midnight.
-- To contribute: replace each English value on the RIGHT side of = with your translation.
-- Do NOT modify keys (the quoted text on the LEFT side of =).
-- See TRANSLATING.md at the project root for full contributor guidelines.
-- After making changes, reload the addon in-game with /reload to test.

if GetLocale() ~= "deDE" then return end
local _, GAM = ...
local L = GAM.L  -- base table already created by Locale.lua; override keys below

-- ── General ──────────────────────────────────────────────────────────────
-- L["ADDON_TITLE"]           = "Gold Advisor Midnight"  -- addon name, keep in English
L["LOADED_MSG"]            = "Gold Advisor Midnight v%s geladen. /gam zum Ein-/Ausblenden."

-- ── Main Window ──────────────────────────────────────────────────────────
-- L["MAIN_TITLE"]            = "Gold Advisor Midnight"  -- addon name, keep in English
L["FILTER_PATCH"]          = "Patch:"
L["FILTER_PROFESSION"]     = "Beruf:"
L["FILTER_SEARCH"]         = "Suchen..."
L["COL_STRAT"]             = "Strategie"
L["COL_PROF"]              = "Beruf"
L["COL_PROFIT"]            = "Gewinn"
L["COL_ROI"]               = "ROI%"
L["COL_STATUS"]            = "Status"
L["BTN_SCAN_ALL"]          = "Alle scannen"
L["BTN_SCAN_STOP"]         = "Scan stoppen"
L["BTN_SHOPPING"]          = "Einkaufsliste"
L["BTN_LOG"]               = "Protokoll"
L["BTN_CLOSE"]             = "Schließen"
L["NO_STRATS"]             = "Keine Strategien entsprechen den Filtern."
L["MISSING_PRICES"]        = "! Preise fehlen"
L["STATUS_STALE"]          = "Veraltet"
L["STATUS_FRESH"]          = "Aktuell"
L["STATUS_NEVER"]          = "Noch nie gescannt"
L["STATUS_STRAT_COUNT"]    = "%d Strategien"
L["STATUS_SCANNING_PROG"]  = "scannt..."
L["STATUS_QUEUING"]        = "Artikel werden vorbereitet..."

-- ── Strat Detail ─────────────────────────────────────────────────────────
L["DETAIL_TITLE"]          = "Strategie-Details"
L["DETAIL_OUTPUT"]         = "Ausgabe:"
L["DETAIL_REAGENTS"]       = "Reagenzien:"
L["DETAIL_INPUT_HDR"]      = "Eingabe-Artikel"
L["DETAIL_OUTPUT_HDR"]     = "Ausgabe-Artikel"
L["COL_ITEM"]              = "Artikel"
L["COL_QTY_CRAFT"]         = "Ges. Menge"
L["COL_HAVE"]              = "Im Inventar"
L["COL_NEED_BUY"]          = "Zu kaufen"
L["COL_UNIT_PRICE"]        = "Stückpreis"
L["COL_TOTAL_COST"]        = "Ges. Kosten"
L["COL_REVENUE"]           = "Nettoerlös"
L["BTN_SCAN_ITEM"]         = "Scan"
L["BTN_SCAN_ALL_ITEMS"]    = "Alle Artikel scannen"
L["BTN_PUSH_CRAFTSIM"]     = "An CraftSim senden"
L["TT_CRAFTSIM_TITLE"]     = "Preisüberschreibungen an CraftSim senden"
L["TT_CRAFTSIM_WARN"]      = "Warnung: Dies überschreibt alle vorhandenen manuellen Preisüberschreibungen in CraftSim für alle Reagenzien dieser Strategie."
L["LBL_COST"]              = "Gesamtkosten:"
L["LBL_REVENUE"]           = "Nettoerlös:"
L["LBL_PROFIT"]            = "Gewinn:"
L["LBL_ROI"]               = "ROI:"
L["LBL_BREAKEVEN"]         = "Gewinnschwelle:"
L["RANK_SELECT"]           = "Rang:"
L["RANK_BTN_R1"]           = "R1 Material"
L["RANK_BTN_R2"]           = "R2 Material"
L["NO_PRICE"]              = "—"
L["CONFIRM_DELETE_BODY"]   = "Strategie löschen:\n\"|cffffffff%s|r\"\n\nDies kann nicht rückgängig gemacht werden."

-- ── Shopping List ─────────────────────────────────────────────────────────
L["SHOP_TITLE"]            = "Einkaufsliste"
L["SHOP_ITEM"]             = "Artikel"
L["SHOP_NEED"]             = "Zu kaufen"
L["SHOP_HAVE"]             = "Vorhanden"
L["BTN_COPY_LIST"]         = "Kopieren"
L["BTN_AUCTIONATOR"]       = "Auctionator-Liste"
L["SHOP_EMPTY"]            = "Keine Artikel benötigt."
L["AUCTIONATOR_LIST_NAME"] = "GAM Shopping List"  -- internal ID, keep in English
L["MSG_AUCTIONATOR_CREATED"]   = "Auctionator-Liste '%s' erstellt (%d Artikel). Öffne den Einkaufs-Tab zum Kaufen."
L["MSG_AUCTIONATOR_NO_ITEMS"]  = "Nichts benötigt — Einkaufsliste ist leer."
L["MSG_AUCTIONATOR_NOT_FOUND"] = "Auctionator nicht installiert. Installiere es, um diese Funktion zu nutzen."

-- ── Debug Log ────────────────────────────────────────────────────────────
L["LOG_TITLE"]             = "Debug-Protokoll"
L["BTN_CLEAR_LOG"]         = "Leeren"
L["BTN_COPY_LOG"]          = "Alles kopieren"
L["BTN_PAUSE_LOG"]         = "Pause"
L["BTN_RESUME_LOG"]        = "Fortsetzen"
L["BTN_DUMP_IDS"]          = "IDs ausgeben"
L["BTN_ARP_EXPORT"]        = "ARP Export"
L["LOG_PAUSED"]            = "[Protokoll pausiert]"
L["LOG_CLEARED"]           = "[Protokoll geleert]"

-- ── Settings ─────────────────────────────────────────────────────────────
-- L["SETTINGS_NAME"]         = "Gold Advisor Midnight"  -- addon name, keep in English
L["OPT_SCAN_DELAY"]        = "Scan-Verzögerung (Sek.)"
L["OPT_SCAN_DELAY_TIP"]    = "Sekunden zwischen AH-Abfragen. Niedriger = schneller, erhöht aber Drosselungsgefahr."
L["OPT_VERBOSITY"]         = "Debug-Ausführlichkeit"
L["OPT_VERBOSITY_TIP"]     = "0=aus, 1=info, 2=debug, 3=ausführlich"
L["OPT_MINIMAP"]           = "Minimap-Schaltfläche anzeigen"
L["OPT_RANK_POLICY"]       = "Rang-Auswahlregel"
L["OPT_RANK_HIGHEST"]      = "Höchster Rang"
L["OPT_RANK_LOWEST"]       = "Niedrigster Rang"
L["BTN_RELOAD_DATA"]       = "Neu laden"
L["BTN_CLEAR_CACHE"]       = "Cache leeren"
L["BTN_OPEN_LOG"]          = "Protokoll öffnen"
L["BTN_APPLY_CLOSE"]       = "Übernehmen"
L["OPT_SHALLOW_FILL_TIP"]  = "Preise werden berechnet, indem der Kauf dieser Menge Einheiten aus dem AH-Auftragsbuch simuliert wird. Niedrigere Werte spiegeln die Kosten kleiner Mengen wider; höhere Werte mitteln über mehr Angebot. Bereich: 10–10.000."
L["OPT_SHALLOW_FILL_QTY"]  = "Füllmenge:"
L["OPT_SHALLOW_FILL_RANGE"] = "(10 - 10.000)"
L["FILL_QTY_ACTIVE"]       = "Füllmenge: %s Einheiten"

-- ── Strategy Creator ─────────────────────────────────────────────────────
L["BTN_CREATE_STRAT"]      = "Strategie erstellen"
L["BTN_IMPORT_STRAT"]      = "Strategie importieren"
L["BTN_EXPORT_STRAT"]      = "Export"
L["BTN_EDIT_STRAT"]        = "Bearbeiten"
L["BTN_DELETE_STRAT"]      = "Löschen"
L["BTN_REMOVE"]            = "x"
L["CREATOR_TITLE"]         = "Strategie erstellen"
L["CREATOR_EDIT_TITLE"]    = "Strategie bearbeiten"
L["CREATOR_PROFESSION"]    = "Beruf:"
L["CREATOR_NAME"]          = "Strategiename:"
L["CREATOR_INPUT_QTY"]     = "Eingabemenge:"
L["CREATOR_INPUT_QTY_TIP"] = "Die Basismenge, gegen die alle Verhältnisse berechnet werden (z.B. 1000 Kräuter zum Mahlen)"
L["CREATOR_INPUT_HINT"]    = "(alle Mengen unten gelten für diese Eingabemenge)"
L["CREATOR_OUTPUTS"]       = "Ausgaben"
L["CREATOR_REAGENTS"]      = "Reagenzien"
L["CREATOR_NOTES"]         = "Notizen:"
L["CREATOR_COL_NAME"]      = "Artikelname"
L["CREATOR_COL_ITEMID"]    = "Artikel-ID"
L["CREATOR_COL_QTY"]       = "Menge"
L["BTN_CREATOR_SAVE"]      = "Speichern"
L["BTN_CREATOR_DELETE"]    = "Löschen"
L["BTN_CREATOR_ADD_OUT"]   = "+ Ausgabe"
L["BTN_CREATOR_ADD_REAG"]  = "+ Reagens"
L["CREATOR_CUSTOM_PROF"]   = "(Benutzerdefiniert...)"
L["MSG_STRAT_SAVED"]       = "Strategie '%s' gespeichert."
L["MSG_STRAT_DELETED"]     = "Strategie '%s' gelöscht."
L["EXPORT_POPUP_TITLE"]    = "Strategie exportieren"
L["EXPORT_ENCODED_LBL"]    = "Kodiert — mit anderen GAM-Nutzern teilen:"
L["EXPORT_LUA_LBL"]        = "Datei-Bearbeitung — in Data/StratsManual.lua einfügen:"
L["IMPORT_POPUP_TITLE"]    = "Strategie importieren"
L["IMPORT_ENCODED_LBL"]    = "Kodierten String einfügen (GAM1:...):"
L["MSG_STRAT_IMPORTED"]    = "Strategie '%s' importiert."
L["ERR_IMPORT_INVALID"]    = "Ungültiger oder unbekannter Import-String."
L["ERR_PROF_REQUIRED"]     = "Beruf ist erforderlich."
L["ERR_NAME_REQUIRED"]     = "Strategiename ist erforderlich."
L["ERR_QTY_REQUIRED"]      = "Eingabemenge muss größer als 0 sein."
L["ERR_OUTPUT_REQUIRED"]   = "Mindestens eine Ausgabe ist erforderlich."

-- ── Minimap ──────────────────────────────────────────────────────────────
L["MINIMAP_TIP"]           = "Gold Advisor Midnight\nLinksklick: Fenster umschalten\nRechtsklick: Einstellungen\nZiehen: Schaltfläche verschieben"

-- ── Scanning ─────────────────────────────────────────────────────────────
L["SCAN_STARTED"]          = "%d Artikel werden gescannt..."
L["SCAN_COMPLETE"]         = "Scan abgeschlossen. %d OK, %d fehlgeschlagen."
L["SCAN_AH_CLOSED"]        = "AH geschlossen — Scan gestoppt."
L["SCAN_THROTTLED"]        = "AH gedrosselt, erneuter Versuch..."
L["PRICE_UPDATED"]         = "Preis aktualisiert: %s = %s"

-- ── Errors / Warnings ────────────────────────────────────────────────────
L["ERR_NO_AH"]             = "Öffne zuerst das Auktionshaus."
L["ERR_STRAT_INVALID"]     = "Ungültige Strategie: %s"
L["WARN_PRICE_STALE"]      = "Preise könnten veraltet sein (>%d Min.)."
