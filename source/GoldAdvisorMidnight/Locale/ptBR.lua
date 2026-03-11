-- GoldAdvisorMidnight/Locale/ptBR.lua
-- Portuguese Brazil (ptBR) translations for Gold Advisor Midnight.
-- To contribute: replace each English value on the RIGHT side of = with your translation.
-- Do NOT modify keys (the quoted text on the LEFT side of =).
-- See TRANSLATING.md at the project root for full contributor guidelines.
-- After making changes, reload the addon in-game with /reload to test.

if GetLocale() ~= "ptBR" then return end
local _, GAM = ...
local L = GAM.L  -- base table already created by Locale.lua; override keys below

-- ── General ──────────────────────────────────────────────────────────────
-- L["ADDON_TITLE"]           = "Gold Advisor Midnight"  -- addon name, keep in English
L["LOADED_MSG"]            = "Gold Advisor Midnight v%s carregado. /gam para mostrar/ocultar."

-- ── Main Window ──────────────────────────────────────────────────────────
-- L["MAIN_TITLE"]            = "Gold Advisor Midnight"  -- addon name, keep in English
L["FILTER_PATCH"]          = "Patch:"
L["FILTER_PROFESSION"]     = "Profissão:"
L["FILTER_SEARCH"]         = "Buscar..."
L["COL_STRAT"]             = "Estratégia"
L["COL_PROF"]              = "Profissão"
L["COL_PROFIT"]            = "Lucro"
L["COL_ROI"]               = "ROI%"
L["COL_STATUS"]            = "Status"
L["BTN_SCAN_ALL"]          = "Escanear tudo"
L["BTN_SCAN_STOP"]         = "Parar"
L["BTN_SHOPPING"]          = "Lista de compras"
L["BTN_LOG"]               = "Log"
L["BTN_CLOSE"]             = "Fechar"
L["NO_STRATS"]             = "Nenhuma estratégia corresponde aos filtros."
L["MISSING_PRICES"]        = "! Preços ausentes"
L["STATUS_STALE"]          = "Desatualizado"
L["STATUS_FRESH"]          = "Atualizado"
L["STATUS_NEVER"]          = "Nunca escaneado"
L["STATUS_STRAT_COUNT"]    = "%d estratégias"
L["STATUS_SCANNING_PROG"]  = "escaneando..."
L["STATUS_QUEUING"]        = "Preparando itens..."

-- ── Strat Detail ─────────────────────────────────────────────────────────
L["DETAIL_TITLE"]          = "Detalhe da estratégia"
L["DETAIL_OUTPUT"]         = "Produção:"
L["DETAIL_REAGENTS"]       = "Reagentes:"
L["DETAIL_INPUT_HDR"]      = "Itens de entrada"
L["DETAIL_OUTPUT_HDR"]     = "Itens de saída"
L["COL_ITEM"]              = "Item"
L["COL_QTY_CRAFT"]         = "Qt. total"
L["COL_HAVE"]              = "No inventário"
L["COL_NEED_BUY"]          = "Comprar"
L["COL_UNIT_PRICE"]        = "Preço unitário"
L["COL_TOTAL_COST"]        = "Custo total"
L["COL_REVENUE"]           = "Receita líquida"
L["BTN_SCAN_ITEM"]         = "Escanear"
L["BTN_SCAN_ALL_ITEMS"]    = "Escanear tudo"
L["BTN_PUSH_CRAFTSIM"]     = "Enviar ao CraftSim"
L["TT_CRAFTSIM_TITLE"]     = "Enviar substituições de preço ao CraftSim"
L["TT_CRAFTSIM_WARN"]      = "Aviso: Isso substituirá todas as substituições de preço manuais existentes no CraftSim para todos os reagentes desta estratégia."
L["LBL_COST"]              = "Custo total:"
L["LBL_REVENUE"]           = "Receita líquida:"
L["LBL_PROFIT"]            = "Lucro:"
L["LBL_ROI"]               = "ROI:"
L["LBL_BREAKEVEN"]         = "Preço de equilíbrio:"
L["RANK_SELECT"]           = "Nível:"
L["RANK_BTN_R1"]           = "Mat. N1"
L["RANK_BTN_R2"]           = "Mat. N2"
L["NO_PRICE"]              = "—"
L["CONFIRM_DELETE_BODY"]   = "Excluir estratégia:\n\"|cffffffff%s|r\"\n\nEsta ação não pode ser desfeita."

-- ── Shopping List ─────────────────────────────────────────────────────────
L["SHOP_TITLE"]            = "Lista de compras"
L["SHOP_ITEM"]             = "Item"
L["SHOP_NEED"]             = "Comprar"
L["SHOP_HAVE"]             = "Disponível"
L["BTN_COPY_LIST"]         = "Copiar"
L["BTN_AUCTIONATOR"]       = "Lista Auctionator"
L["SHOP_EMPTY"]            = "Nenhum item necessário."
L["AUCTIONATOR_LIST_NAME"] = "GAM Shopping List"  -- internal ID, keep in English
L["MSG_AUCTIONATOR_CREATED"]   = "Lista Auctionator '%s' criada (%d itens). Abra a aba de Compras para comprar."
L["MSG_AUCTIONATOR_NO_ITEMS"]  = "Nada necessário — a lista de compras está vazia."
L["MSG_AUCTIONATOR_NOT_FOUND"] = "Auctionator não instalado. Instale-o para usar esta função."

-- ── Debug Log ────────────────────────────────────────────────────────────
L["LOG_TITLE"]             = "Log de depuração"
L["BTN_CLEAR_LOG"]         = "Limpar"
L["BTN_COPY_LOG"]          = "Copiar tudo"
L["BTN_PAUSE_LOG"]         = "Pausar"
L["BTN_RESUME_LOG"]        = "Retomar"
L["BTN_DUMP_IDS"]          = "Exportar IDs"
L["BTN_ARP_EXPORT"]        = "ARP Export"
L["LOG_PAUSED"]            = "[Log pausado]"
L["LOG_CLEARED"]           = "[Log limpo]"

-- ── Settings ─────────────────────────────────────────────────────────────
-- L["SETTINGS_NAME"]         = "Gold Advisor Midnight"  -- addon name, keep in English
L["OPT_SCAN_DELAY"]        = "Atraso de escaneamento (seg)"
L["OPT_SCAN_DELAY_TIP"]    = "Segundos entre consultas AH. Menor = mais rápido mas aumenta risco de limitação."
L["OPT_VERBOSITY"]         = "Nível de depuração"
L["OPT_VERBOSITY_TIP"]     = "0=desativado, 1=info, 2=debug, 3=detalhado"
L["OPT_MINIMAP"]           = "Mostrar botão do minimapa"
L["OPT_RANK_POLICY"]       = "Política de seleção de nível"
L["OPT_RANK_HIGHEST"]      = "Nível mais alto"
L["OPT_RANK_LOWEST"]       = "Nível mais baixo"
L["BTN_RELOAD_DATA"]       = "Recarregar"
L["BTN_CLEAR_CACHE"]       = "Limpar cache"
L["BTN_OPEN_LOG"]          = "Abrir log"
L["BTN_APPLY_CLOSE"]       = "Aplicar"
L["OPT_SHALLOW_FILL"]      = "Modo preenchimento superficial (Experimental)"
L["OPT_SHALLOW_FILL_TIP"]  = "Os preços são calculados comprando a quantidade de preenchimento abaixo, em vez do preenchimento profundo padrão de 50.000 unidades. Pode mostrar preços mais baratos para sessões pequenas, mas é menos estável em mercados escassos. Use para comparação — não substitui o modo padrão."
L["OPT_SHALLOW_FILL_QTY"]  = "Qt. preenchimento:"
L["OPT_SHALLOW_FILL_RANGE"] = "(250 - 50.000)"
L["SHALLOW_FILL_ACTIVE"]   = "[Preench. superficial] Preço AH de %s unidades (experimental)"

-- ── Strategy Creator ─────────────────────────────────────────────────────
L["BTN_CREATE_STRAT"]      = "Criar estratégia"
L["BTN_IMPORT_STRAT"]      = "Importar"
L["BTN_EXPORT_STRAT"]      = "Exportar"
L["BTN_EDIT_STRAT"]        = "Editar"
L["BTN_DELETE_STRAT"]      = "Excluir"
L["BTN_REMOVE"]            = "x"
L["CREATOR_TITLE"]         = "Criar estratégia"
L["CREATOR_EDIT_TITLE"]    = "Editar estratégia"
L["CREATOR_PROFESSION"]    = "Profissão:"
L["CREATOR_NAME"]          = "Nome da estratégia:"
L["CREATOR_INPUT_QTY"]     = "Quantidade de entrada:"
L["CREATOR_INPUT_QTY_TIP"] = "A quantidade base para calcular todas as proporções (ex.: 1000 ervas para moer)"
L["CREATOR_INPUT_HINT"]    = "(todas as qt. abaixo são por esta quantidade de entrada)"
L["CREATOR_OUTPUTS"]       = "Produções"
L["CREATOR_REAGENTS"]      = "Reagentes"
L["CREATOR_NOTES"]         = "Notas:"
L["CREATOR_COL_NAME"]      = "Nome do item"
L["CREATOR_COL_ITEMID"]    = "ID do item"
L["CREATOR_COL_QTY"]       = "Qt."
L["BTN_CREATOR_SAVE"]      = "Salvar"
L["BTN_CREATOR_DELETE"]    = "Excluir"
L["BTN_CREATOR_ADD_OUT"]   = "+ Produção"
L["BTN_CREATOR_ADD_REAG"]  = "+ Reagente"
L["CREATOR_CUSTOM_PROF"]   = "(Personalizado...)"
L["MSG_STRAT_SAVED"]       = "Estratégia '%s' salva."
L["MSG_STRAT_DELETED"]     = "Estratégia '%s' excluída."
L["EXPORT_POPUP_TITLE"]    = "Exportar estratégia"
L["EXPORT_ENCODED_LBL"]    = "Codificado — compartilhe com outros usuários GAM:"
L["EXPORT_LUA_LBL"]        = "Edição de arquivo — cole em Data/StratsManual.lua:"
L["IMPORT_POPUP_TITLE"]    = "Importar estratégia"
L["IMPORT_ENCODED_LBL"]    = "Cole a string codificada (GAM1:...):"
L["MSG_STRAT_IMPORTED"]    = "Estratégia '%s' importada."
L["ERR_IMPORT_INVALID"]    = "String de importação inválida ou não reconhecida."
L["ERR_PROF_REQUIRED"]     = "A profissão é obrigatória."
L["ERR_NAME_REQUIRED"]     = "O nome da estratégia é obrigatório."
L["ERR_QTY_REQUIRED"]      = "A quantidade de entrada deve ser maior que 0."
L["ERR_OUTPUT_REQUIRED"]   = "Pelo menos uma produção é necessária."

-- ── Minimap ──────────────────────────────────────────────────────────────
L["MINIMAP_TIP"]           = "Gold Advisor Midnight\nClique esquerdo: Mostrar/ocultar\nClique direito: Configurações\nArrastar: Mover botão"

-- ── Scanning ─────────────────────────────────────────────────────────────
L["SCAN_STARTED"]          = "Escaneando %d itens..."
L["SCAN_COMPLETE"]         = "Escaneamento concluído. %d OK, %d falhas."
L["SCAN_AH_CLOSED"]        = "CL fechada — escaneamento parado."
L["SCAN_THROTTLED"]        = "CL limitada, tentando novamente..."
L["PRICE_UPDATED"]         = "Preço atualizado: %s = %s"

-- ── Errors / Warnings ────────────────────────────────────────────────────
L["ERR_NO_AH"]             = "Abra a Casa de Leilões primeiro."
L["ERR_STRAT_INVALID"]     = "Estratégia inválida: %s"
L["WARN_PRICE_STALE"]      = "Os preços podem estar desatualizados (>%d min)."
