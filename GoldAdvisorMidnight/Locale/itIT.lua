-- GoldAdvisorMidnight/Locale/itIT.lua
-- Italian (itIT) translations for Gold Advisor Midnight.
-- To contribute: replace each English value on the RIGHT side of = with your translation.
-- Do NOT modify keys (the quoted text on the LEFT side of =).
-- See TRANSLATING.md at the project root for full contributor guidelines.
-- After making changes, reload the addon in-game with /reload to test.

if GetLocale() ~= "itIT" then return end
local _, GAM = ...
local L = GAM.L  -- base table already created by Locale.lua; override keys below

-- ── General ──────────────────────────────────────────────────────────────
-- L["ADDON_TITLE"]           = "Gold Advisor Midnight"  -- addon name, keep in English
L["LOADED_MSG"]            = "Gold Advisor Midnight v%s caricato. /gam per mostrare/nascondere."

-- ── Main Window ──────────────────────────────────────────────────────────
-- L["MAIN_TITLE"]            = "Gold Advisor Midnight"  -- addon name, keep in English
L["FILTER_PATCH"]          = "Patch:"
L["FILTER_PROFESSION"]     = "Professione:"
L["FILTER_SEARCH"]         = "Cerca..."
L["COL_STRAT"]             = "Strategia"
L["COL_PROF"]              = "Professione"
L["COL_PROFIT"]            = "Profitto"
L["COL_ROI"]               = "ROI%"
L["COL_STATUS"]            = "Stato"
L["BTN_SCAN_ALL"]          = "Scansiona tutto"
L["BTN_SCAN_STOP"]         = "Ferma"
L["BTN_SHOPPING"]          = "Lista acquisti"
L["BTN_LOG"]               = "Log"
L["BTN_CLOSE"]             = "Chiudi"
L["NO_STRATS"]             = "Nessuna strategia corrisponde ai filtri."
L["MISSING_PRICES"]        = "! Prezzi mancanti"
L["STATUS_STALE"]          = "Non aggiornato"
L["STATUS_FRESH"]          = "Aggiornato"
L["STATUS_NEVER"]          = "Mai scansionato"
L["STATUS_STRAT_COUNT"]    = "%d strategie"
L["STATUS_SCANNING_PROG"]  = "scansione..."
L["STATUS_QUEUING"]        = "Preparazione oggetti..."

-- ── Strat Detail ─────────────────────────────────────────────────────────
L["DETAIL_TITLE"]          = "Dettaglio strategia"
L["DETAIL_OUTPUT"]         = "Produzione:"
L["DETAIL_REAGENTS"]       = "Reagenti:"
L["DETAIL_INPUT_HDR"]      = "Oggetti in ingresso"
L["DETAIL_OUTPUT_HDR"]     = "Oggetti in uscita"
L["COL_ITEM"]              = "Oggetto"
L["COL_QTY_CRAFT"]         = "Qt. totale"
L["COL_HAVE"]              = "In borsa"
L["COL_NEED_BUY"]          = "Da comprare"
L["COL_UNIT_PRICE"]        = "Prezzo unitario"
L["COL_TOTAL_COST"]        = "Costo totale"
L["COL_REVENUE"]           = "Ricavo netto"
L["BTN_SCAN_ITEM"]         = "Scansiona"
L["BTN_SCAN_ALL_ITEMS"]    = "Scansiona tutto"
L["BTN_PUSH_CRAFTSIM"]     = "Invia a CraftSim"
L["TT_CRAFTSIM_TITLE"]     = "Invia sostituzioni prezzi a CraftSim"
L["TT_CRAFTSIM_WARN"]      = "Avviso: Questo sovrascriverà tutte le sostituzioni di prezzo manuali esistenti in CraftSim per tutti i reagenti di questa strategia."
L["LBL_COST"]              = "Costo totale:"
L["LBL_REVENUE"]           = "Ricavo netto:"
L["LBL_PROFIT"]            = "Profitto:"
L["LBL_ROI"]               = "ROI:"
L["LBL_BREAKEVEN"]         = "Prezzo pareggio:"
L["RANK_SELECT"]           = "Grado:"
L["RANK_BTN_R1"]           = "Mat. G1"
L["RANK_BTN_R2"]           = "Mat. G2"
L["NO_PRICE"]              = "—"
L["CONFIRM_DELETE_BODY"]   = "Elimina strategia:\n\"|cffffffff%s|r\"\n\nQuesta azione non può essere annullata."

-- ── Shopping List ─────────────────────────────────────────────────────────
L["SHOP_TITLE"]            = "Lista acquisti"
L["SHOP_ITEM"]             = "Oggetto"
L["SHOP_NEED"]             = "Da comprare"
L["SHOP_HAVE"]             = "Disponibile"
L["BTN_COPY_LIST"]         = "Copia"
L["BTN_AUCTIONATOR"]       = "Lista Auctionator"
L["SHOP_EMPTY"]            = "Nessun oggetto necessario."
L["AUCTIONATOR_LIST_NAME"] = "GAM Shopping List"  -- internal ID, keep in English
L["MSG_AUCTIONATOR_CREATED"]   = "Lista Auctionator '%s' creata (%d oggetti). Apri la scheda Acquisti per comprare."
L["MSG_AUCTIONATOR_NO_ITEMS"]  = "Niente da comprare — la lista acquisti è vuota."
L["MSG_AUCTIONATOR_NOT_FOUND"] = "Auctionator non installato. Installalo per usare questa funzione."

-- ── Debug Log ────────────────────────────────────────────────────────────
L["LOG_TITLE"]             = "Log di debug"
L["BTN_CLEAR_LOG"]         = "Cancella"
L["BTN_COPY_LOG"]          = "Copia tutto"
L["BTN_PAUSE_LOG"]         = "Pausa"
L["BTN_RESUME_LOG"]        = "Riprendi"
L["BTN_DUMP_IDS"]          = "Esporta ID"
L["LOG_PAUSED"]            = "[Log in pausa]"
L["LOG_CLEARED"]           = "[Log cancellato]"

-- ── Settings ─────────────────────────────────────────────────────────────
-- L["SETTINGS_NAME"]         = "Gold Advisor Midnight"  -- addon name, keep in English
L["OPT_SCAN_DELAY"]        = "Ritardo scansione (sec)"
L["OPT_SCAN_DELAY_TIP"]    = "Secondi tra le query AH. Meno = più veloce ma rischio di limitazione."
L["OPT_VERBOSITY"]         = "Verbosità debug"
L["OPT_VERBOSITY_TIP"]     = "0=disattivo, 1=info, 2=debug, 3=dettagliato"
L["OPT_MINIMAP"]           = "Mostra pulsante minimappa"
L["OPT_RANK_POLICY"]       = "Politica selezione grado"
L["OPT_RANK_HIGHEST"]      = "Grado più alto"
L["OPT_RANK_LOWEST"]       = "Grado più basso"
L["BTN_RELOAD_DATA"]       = "Ricarica"
L["BTN_CLEAR_CACHE"]       = "Svuota cache"
L["BTN_OPEN_LOG"]          = "Apri log"
L["BTN_APPLY_CLOSE"]       = "Applica"
L["OPT_SHALLOW_FILL"]      = "Modalità riempimento superficiale (Sperimentale)"
L["OPT_SHALLOW_FILL_TIP"]  = "I prezzi vengono calcolati acquistando la quantità di riempimento indicata sotto, invece del riempimento profondo standard di 50.000 unità. Può mostrare prezzi più bassi per sessioni di piccole quantità ma è meno stabile su mercati sottili. Usare per confronto — non è un sostituto generale della modalità predefinita."
L["OPT_SHALLOW_FILL_QTY"]  = "Qt. riempimento:"
L["OPT_SHALLOW_FILL_RANGE"] = "(250 - 50.000)"
L["SHALLOW_FILL_ACTIVE"]   = "[Riemp. superficiale] Prezzo AH %s unità (sperimentale)"

-- ── Strategy Creator ─────────────────────────────────────────────────────
L["BTN_CREATE_STRAT"]      = "Crea strategia"
L["BTN_IMPORT_STRAT"]      = "Importa"
L["BTN_EXPORT_STRAT"]      = "Esporta"
L["BTN_EDIT_STRAT"]        = "Modifica"
L["BTN_DELETE_STRAT"]      = "Elimina"
L["BTN_REMOVE"]            = "x"
L["CREATOR_TITLE"]         = "Crea strategia"
L["CREATOR_EDIT_TITLE"]    = "Modifica strategia"
L["CREATOR_PROFESSION"]    = "Professione:"
L["CREATOR_NAME"]          = "Nome strategia:"
L["CREATOR_INPUT_QTY"]     = "Quantità input:"
L["CREATOR_INPUT_QTY_TIP"] = "La quantità base rispetto a cui vengono calcolati tutti i rapporti (es. 1000 erbe da macinare)"
L["CREATOR_INPUT_HINT"]    = "(tutte le qt. sotto sono per questa quantità di input)"
L["CREATOR_OUTPUTS"]       = "Produzioni"
L["CREATOR_REAGENTS"]      = "Reagenti"
L["CREATOR_NOTES"]         = "Note:"
L["CREATOR_COL_NAME"]      = "Nome oggetto"
L["CREATOR_COL_ITEMID"]    = "ID oggetto"
L["CREATOR_COL_QTY"]       = "Qt."
L["BTN_CREATOR_SAVE"]      = "Salva"
L["BTN_CREATOR_DELETE"]    = "Elimina"
L["BTN_CREATOR_ADD_OUT"]   = "+ Produzione"
L["BTN_CREATOR_ADD_REAG"]  = "+ Reagente"
L["CREATOR_CUSTOM_PROF"]   = "(Personalizzato...)"
L["MSG_STRAT_SAVED"]       = "Strategia '%s' salvata."
L["MSG_STRAT_DELETED"]     = "Strategia '%s' eliminata."
L["EXPORT_POPUP_TITLE"]    = "Esporta strategia"
L["EXPORT_ENCODED_LBL"]    = "Codificato — condividi con altri utenti GAM:"
L["EXPORT_LUA_LBL"]        = "Modifica file — incolla in Data/StratsManual.lua:"
L["IMPORT_POPUP_TITLE"]    = "Importa strategia"
L["IMPORT_ENCODED_LBL"]    = "Incolla la stringa codificata (GAM1:...):"
L["MSG_STRAT_IMPORTED"]    = "Strategia '%s' importata."
L["ERR_IMPORT_INVALID"]    = "Stringa di importazione non valida o non riconosciuta."
L["ERR_PROF_REQUIRED"]     = "La professione è obbligatoria."
L["ERR_NAME_REQUIRED"]     = "Il nome della strategia è obbligatorio."
L["ERR_QTY_REQUIRED"]      = "La quantità di input deve essere maggiore di 0."
L["ERR_OUTPUT_REQUIRED"]   = "È richiesta almeno una produzione."

-- ── Minimap ──────────────────────────────────────────────────────────────
L["MINIMAP_TIP"]           = "Gold Advisor Midnight\nClic sinistro: Mostra/nascondi\nClic destro: Impostazioni\nTrascina: Sposta pulsante"

-- ── Scanning ─────────────────────────────────────────────────────────────
L["SCAN_STARTED"]          = "Scansione di %d oggetti..."
L["SCAN_COMPLETE"]         = "Scansione completata. %d OK, %d falliti."
L["SCAN_AH_CLOSED"]        = "CdA chiusa — scansione interrotta."
L["SCAN_THROTTLED"]        = "CdA limitata, nuovo tentativo..."
L["PRICE_UPDATED"]         = "Prezzo aggiornato: %s = %s"

-- ── Errors / Warnings ────────────────────────────────────────────────────
L["ERR_NO_AH"]             = "Apri prima la Casa d'aste."
L["ERR_STRAT_INVALID"]     = "Strategia non valida: %s"
L["WARN_PRICE_STALE"]      = "I prezzi potrebbero non essere aggiornati (>%d min)."
