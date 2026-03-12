-- GoldAdvisorMidnight/Locale/frFR.lua
-- French (frFR) translations for Gold Advisor Midnight.
-- To contribute: replace each English value on the RIGHT side of = with your translation.
-- Do NOT modify keys (the quoted text on the LEFT side of =).
-- See TRANSLATING.md at the project root for full contributor guidelines.
-- After making changes, reload the addon in-game with /reload to test.

if GetLocale() ~= "frFR" then return end
local _, GAM = ...
local L = GAM.L  -- base table already created by Locale.lua; override keys below

-- ── General ──────────────────────────────────────────────────────────────
-- L["ADDON_TITLE"]           = "Gold Advisor Midnight"  -- addon name, keep in English
L["LOADED_MSG"]            = "Gold Advisor Midnight v%s chargé. /gam pour afficher/masquer."

-- ── Main Window ──────────────────────────────────────────────────────────
-- L["MAIN_TITLE"]            = "Gold Advisor Midnight"  -- addon name, keep in English
L["FILTER_PATCH"]          = "Patch :"
L["FILTER_PROFESSION"]     = "Profession :"
L["FILTER_SEARCH"]         = "Rechercher..."
L["COL_STRAT"]             = "Stratégie"
L["COL_PROF"]              = "Profession"
L["COL_PROFIT"]            = "Profit"
L["COL_ROI"]               = "ROI%"
L["COL_STATUS"]            = "Statut"
L["BTN_SCAN_ALL"]          = "Tout scanner"
L["BTN_SCAN_STOP"]         = "Arrêter"
L["BTN_SHOPPING"]          = "Liste d'achats"
L["BTN_LOG"]               = "Journal"
L["BTN_CLOSE"]             = "Fermer"
L["NO_STRATS"]             = "Aucune stratégie ne correspond aux filtres."
L["MISSING_PRICES"]        = "! Prix manquants"
L["STATUS_STALE"]          = "Obsolète"
L["STATUS_FRESH"]          = "Récent"
L["STATUS_NEVER"]          = "Jamais scanné"
L["STATUS_STRAT_COUNT"]    = "%d stratégies"
L["STATUS_SCANNING_PROG"]  = "scan en cours..."
L["STATUS_QUEUING"]        = "Mise en file d'attente..."

-- ── Strat Detail ─────────────────────────────────────────────────────────
L["DETAIL_TITLE"]          = "Détail de la stratégie"
L["DETAIL_OUTPUT"]         = "Production :"
L["DETAIL_REAGENTS"]       = "Réactifs :"
L["DETAIL_INPUT_HDR"]      = "Articles en entrée"
L["DETAIL_OUTPUT_HDR"]     = "Articles en sortie"
L["COL_ITEM"]              = "Article"
L["COL_QTY_CRAFT"]         = "Qté totale"
L["COL_HAVE"]              = "Dans les sacs"
L["COL_NEED_BUY"]          = "À acheter"
L["COL_UNIT_PRICE"]        = "Prix unitaire"
L["COL_TOTAL_COST"]        = "Coût total"
L["COL_REVENUE"]           = "Revenu net"
L["BTN_SCAN_ITEM"]         = "Scanner"
L["BTN_SCAN_ALL_ITEMS"]    = "Scanner tout"
L["BTN_PUSH_CRAFTSIM"]     = "Envoyer à CraftSim"
L["TT_CRAFTSIM_TITLE"]     = "Envoyer les substitutions de prix à CraftSim"
L["TT_CRAFTSIM_WARN"]      = "Avertissement : Cela écrasera toutes les substitutions de prix manuelles existantes dans CraftSim pour tous les réactifs de cette stratégie."
L["LBL_COST"]              = "Coût total :"
L["LBL_REVENUE"]           = "Revenu net :"
L["LBL_PROFIT"]            = "Profit :"
L["LBL_ROI"]               = "ROI :"
L["LBL_BREAKEVEN"]         = "Seuil de rentabilité :"
L["RANK_SELECT"]           = "Rang :"
L["RANK_BTN_R1"]           = "Matériaux R1"
L["RANK_BTN_R2"]           = "Matériaux R2"
L["NO_PRICE"]              = "—"
L["CONFIRM_DELETE_BODY"]   = "Supprimer la stratégie :\n\"|cffffffff%s|r\"\n\nCette action est irréversible."

-- ── Shopping List ─────────────────────────────────────────────────────────
L["SHOP_TITLE"]            = "Liste d'achats"
L["SHOP_ITEM"]             = "Article"
L["SHOP_NEED"]             = "À acheter"
L["SHOP_HAVE"]             = "Disponible"
L["BTN_COPY_LIST"]         = "Copier"
L["BTN_AUCTIONATOR"]       = "Liste Auctionator"
L["SHOP_EMPTY"]            = "Aucun article nécessaire."
L["AUCTIONATOR_LIST_NAME"] = "GAM Shopping List"  -- internal ID, keep in English
L["MSG_AUCTIONATOR_CREATED"]   = "Liste Auctionator '%s' créée (%d articles). Ouvrez l'onglet Achats pour acheter."
L["MSG_AUCTIONATOR_NO_ITEMS"]  = "Rien de nécessaire — la liste d'achats est vide."
L["MSG_AUCTIONATOR_NOT_FOUND"] = "Auctionator non installé. Installez-le pour utiliser cette fonctionnalité."

-- ── Debug Log ────────────────────────────────────────────────────────────
L["LOG_TITLE"]             = "Journal de débogage"
L["BTN_CLEAR_LOG"]         = "Effacer"
L["BTN_COPY_LOG"]          = "Tout copier"
L["BTN_PAUSE_LOG"]         = "Pause"
L["BTN_RESUME_LOG"]        = "Reprendre"
L["BTN_DUMP_IDS"]          = "Exporter les ID"
L["BTN_ARP_EXPORT"]        = "ARP Export"
L["LOG_PAUSED"]            = "[Journal en pause]"
L["LOG_CLEARED"]           = "[Journal effacé]"

-- ── Settings ─────────────────────────────────────────────────────────────
-- L["SETTINGS_NAME"]         = "Gold Advisor Midnight"  -- addon name, keep in English
L["OPT_SCAN_DELAY"]        = "Délai de scan (sec)"
L["OPT_SCAN_DELAY_TIP"]    = "Secondes entre les requêtes AH. Plus bas = plus rapide mais risque de limitation."
L["OPT_VERBOSITY"]         = "Verbosité du débogage"
L["OPT_VERBOSITY_TIP"]     = "0=désactivé, 1=info, 2=debug, 3=verbeux"
L["OPT_MINIMAP"]           = "Afficher le bouton minimap"
L["OPT_RANK_POLICY"]       = "Politique de sélection des rangs"
L["OPT_RANK_HIGHEST"]      = "Rang le plus élevé"
L["OPT_RANK_LOWEST"]       = "Rang le plus bas"
L["BTN_RELOAD_DATA"]       = "Recharger"
L["BTN_CLEAR_CACHE"]       = "Vider le cache"
L["BTN_OPEN_LOG"]          = "Voir journal"
L["BTN_APPLY_CLOSE"]       = "Appliquer"
L["OPT_SHALLOW_FILL_TIP"]  = "Les prix sont calculés en simulant l'achat de ce nombre d'unités dans le carnet d'ordres de l'HV. Des valeurs basses reflètent le coût de petites quantités ; des valeurs élevées moyennent sur plus d'offre. Plage : 10–10 000."
L["OPT_SHALLOW_FILL_QTY"]  = "Qté de remplissage :"
L["OPT_SHALLOW_FILL_RANGE"] = "(10 - 10 000)"
L["FILL_QTY_ACTIVE"]       = "Qté de remplissage : %s unités"

-- ── Strategy Creator ─────────────────────────────────────────────────────
L["BTN_CREATE_STRAT"]      = "Créer une stratégie"
L["BTN_IMPORT_STRAT"]      = "Importer"
L["BTN_EXPORT_STRAT"]      = "Exporter"
L["BTN_EDIT_STRAT"]        = "Modifier"
L["BTN_DELETE_STRAT"]      = "Supprimer"
L["BTN_REMOVE"]            = "x"
L["CREATOR_TITLE"]         = "Créer une stratégie"
L["CREATOR_EDIT_TITLE"]    = "Modifier la stratégie"
L["CREATOR_PROFESSION"]    = "Profession :"
L["CREATOR_NAME"]          = "Nom de la stratégie :"
L["CREATOR_INPUT_QTY"]     = "Quantité d'entrée :"
L["CREATOR_INPUT_QTY_TIP"] = "La quantité de base pour le calcul des ratios (ex. 1000 herbes à moudre)"
L["CREATOR_INPUT_HINT"]    = "(toutes les qtés ci-dessous sont pour cette quantité d'entrée)"
L["CREATOR_OUTPUTS"]       = "Productions"
L["CREATOR_REAGENTS"]      = "Réactifs"
L["CREATOR_NOTES"]         = "Notes :"
L["CREATOR_COL_NAME"]      = "Nom de l'article"
L["CREATOR_COL_ITEMID"]    = "ID de l'article"
L["CREATOR_COL_QTY"]       = "Qté"
L["BTN_CREATOR_SAVE"]      = "Enregistrer"
L["BTN_CREATOR_DELETE"]    = "Supprimer"
L["BTN_CREATOR_ADD_OUT"]   = "+ Production"
L["BTN_CREATOR_ADD_REAG"]  = "+ Réactif"
L["CREATOR_CUSTOM_PROF"]   = "(Personnalisé...)"
L["MSG_STRAT_SAVED"]       = "Stratégie '%s' enregistrée."
L["MSG_STRAT_DELETED"]     = "Stratégie '%s' supprimée."
L["EXPORT_POPUP_TITLE"]    = "Exporter la stratégie"
L["EXPORT_ENCODED_LBL"]    = "Encodé — partagez avec d'autres utilisateurs GAM :"
L["EXPORT_LUA_LBL"]        = "Édition de fichier — collez dans Data/StratsManual.lua :"
L["IMPORT_POPUP_TITLE"]    = "Importer une stratégie"
L["IMPORT_ENCODED_LBL"]    = "Collez la chaîne encodée (GAM1:...) :"
L["MSG_STRAT_IMPORTED"]    = "Stratégie '%s' importée."
L["ERR_IMPORT_INVALID"]    = "Chaîne d'importation invalide ou non reconnue."
L["ERR_PROF_REQUIRED"]     = "La profession est obligatoire."
L["ERR_NAME_REQUIRED"]     = "Le nom de la stratégie est obligatoire."
L["ERR_QTY_REQUIRED"]      = "La quantité d'entrée doit être supérieure à 0."
L["ERR_OUTPUT_REQUIRED"]   = "Au moins une production est requise."

-- ── Minimap ──────────────────────────────────────────────────────────────
L["MINIMAP_TIP"]           = "Gold Advisor Midnight\nClic gauche : Afficher/masquer\nClic droit : Paramètres\nGlisser : Déplacer le bouton"

-- ── Scanning ─────────────────────────────────────────────────────────────
L["SCAN_STARTED"]          = "Scan de %d articles..."
L["SCAN_COMPLETE"]         = "Scan terminé. %d OK, %d échecs."
L["SCAN_AH_CLOSED"]        = "MdV fermée — scan arrêté."
L["SCAN_THROTTLED"]        = "MdV limitée, nouvelle tentative..."
L["PRICE_UPDATED"]         = "Prix mis à jour : %s = %s"

-- ── Errors / Warnings ────────────────────────────────────────────────────
L["ERR_NO_AH"]             = "Ouvrez d'abord la Maison des ventes."
L["ERR_STRAT_INVALID"]     = "Stratégie invalide : %s"
L["WARN_PRICE_STALE"]      = "Les prix peuvent être obsolètes (>%d min)."
