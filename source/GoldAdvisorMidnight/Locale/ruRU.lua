-- GoldAdvisorMidnight/Locale/ruRU.lua
-- Russian (ruRU) translations for Gold Advisor Midnight.
-- To contribute: replace each English value on the RIGHT side of = with your translation.
-- Do NOT modify keys (the quoted text on the LEFT side of =).
-- See TRANSLATING.md at the project root for full contributor guidelines.
-- After making changes, reload the addon in-game with /reload to test.

if GetLocale() ~= "ruRU" then return end
local _, GAM = ...
local L = GAM.L  -- base table already created by Locale.lua; override keys below

-- ── General ──────────────────────────────────────────────────────────────
-- L["ADDON_TITLE"]           = "Gold Advisor Midnight"  -- addon name, keep in English
L["LOADED_MSG"]            = "Gold Advisor Midnight v%s загружен. /gam для открытия/закрытия."

-- ── Main Window ──────────────────────────────────────────────────────────
-- L["MAIN_TITLE"]            = "Gold Advisor Midnight"  -- addon name, keep in English
L["FILTER_PATCH"]          = "Патч:"
L["FILTER_PROFESSION"]     = "Профессия:"
L["FILTER_SEARCH"]         = "Поиск..."
L["COL_STRAT"]             = "Стратегия"
L["COL_PROF"]              = "Профессия"
L["COL_PROFIT"]            = "Прибыль"
L["COL_ROI"]               = "ROI%"
L["COL_STATUS"]            = "Статус"
L["BTN_SCAN_ALL"]          = "Сканировать"
L["BTN_SCAN_STOP"]         = "Остановить"
L["BTN_SHOPPING"]          = "Список покупок"
L["BTN_LOG"]               = "Журнал"
L["BTN_CLOSE"]             = "Закрыть"
L["NO_STRATS"]             = "Нет стратегий, соответствующих фильтрам."
L["MISSING_PRICES"]        = "! Цены отсутствуют"
L["STATUS_STALE"]          = "Устарело"
L["STATUS_FRESH"]          = "Актуально"
L["STATUS_NEVER"]          = "Не сканировалось"
L["STATUS_STRAT_COUNT"]    = "%d стратегий"
L["STATUS_SCANNING_PROG"]  = "сканирование..."
L["STATUS_QUEUING"]        = "Подготовка предметов..."

-- ── Strat Detail ─────────────────────────────────────────────────────────
L["DETAIL_TITLE"]          = "Детали стратегии"
L["DETAIL_OUTPUT"]         = "Выход:"
L["DETAIL_REAGENTS"]       = "Реагенты:"
L["DETAIL_INPUT_HDR"]      = "Входные предметы"
L["DETAIL_OUTPUT_HDR"]     = "Выходные предметы"
L["COL_ITEM"]              = "Предмет"
L["COL_QTY_CRAFT"]         = "Кол-во"
L["COL_HAVE"]              = "В инвентаре"
L["COL_NEED_BUY"]          = "Купить"
L["COL_UNIT_PRICE"]        = "Цена за ед."
L["COL_TOTAL_COST"]        = "Общая стоимость"
L["COL_REVENUE"]           = "Чистая выручка"
L["BTN_SCAN_ITEM"]         = "Скан"
L["BTN_SCAN_ALL_ITEMS"]    = "Скан. всё"
L["BTN_PUSH_CRAFTSIM"]     = "В CraftSim"
L["TT_CRAFTSIM_TITLE"]     = "Отправить замены цен в CraftSim"
L["TT_CRAFTSIM_WARN"]      = "Предупреждение: Это перезапишет все существующие ручные замены цен в CraftSim для всех реагентов этой стратегии."
L["LBL_COST"]              = "Общая стоимость:"
L["LBL_REVENUE"]           = "Чистая выручка:"
L["LBL_PROFIT"]            = "Прибыль:"
L["LBL_ROI"]               = "ROI:"
L["LBL_BREAKEVEN"]         = "Точка безубыточности:"
L["RANK_SELECT"]           = "Ранг:"
L["RANK_BTN_R1"]           = "Мат. R1"
L["RANK_BTN_R2"]           = "Мат. R2"
L["NO_PRICE"]              = "—"
L["CONFIRM_DELETE_BODY"]   = "Удалить стратегию:\n\"|cffffffff%s|r\"\n\nЭто действие нельзя отменить."

-- ── Shopping List ─────────────────────────────────────────────────────────
L["SHOP_TITLE"]            = "Список покупок"
L["SHOP_ITEM"]             = "Предмет"
L["SHOP_NEED"]             = "Купить"
L["SHOP_HAVE"]             = "Есть"
L["BTN_COPY_LIST"]         = "Копировать"
L["BTN_AUCTIONATOR"]       = "Список Auctionator"
L["SHOP_EMPTY"]            = "Предметы не нужны."
L["AUCTIONATOR_LIST_NAME"] = "GAM Shopping List"  -- internal ID, keep in English
L["MSG_AUCTIONATOR_CREATED"]   = "Список Auctionator '%s' создан (%d предм.). Откройте вкладку Покупки для приобретения."
L["MSG_AUCTIONATOR_NO_ITEMS"]  = "Ничего не нужно — список покупок пуст."
L["MSG_AUCTIONATOR_NOT_FOUND"] = "Auctionator не установлен. Установите его для использования этой функции."

-- ── Debug Log ────────────────────────────────────────────────────────────
L["LOG_TITLE"]             = "Журнал отладки"
L["BTN_CLEAR_LOG"]         = "Очистить"
L["BTN_COPY_LOG"]          = "Копировать всё"
L["BTN_PAUSE_LOG"]         = "Пауза"
L["BTN_RESUME_LOG"]        = "Продолжить"
L["BTN_DUMP_IDS"]          = "Экспорт ID"
L["BTN_ARP_EXPORT"]        = "ARP Export"
L["LOG_PAUSED"]            = "[Журнал на паузе]"
L["LOG_CLEARED"]           = "[Журнал очищен]"

-- ── Settings ─────────────────────────────────────────────────────────────
-- L["SETTINGS_NAME"]         = "Gold Advisor Midnight"  -- addon name, keep in English
L["OPT_SCAN_DELAY"]        = "Задержка скана (сек)"
L["OPT_SCAN_DELAY_TIP"]    = "Секунды между запросами АД. Меньше = быстрее, но риск ограничения."
L["OPT_VERBOSITY"]         = "Уровень отладки"
L["OPT_VERBOSITY_TIP"]     = "0=выкл., 1=инфо, 2=отладка, 3=подробно"
L["OPT_MINIMAP"]           = "Показать кнопку на миникарте"
L["OPT_RANK_POLICY"]       = "Политика выбора ранга"
L["OPT_RANK_HIGHEST"]      = "Высший ранг"
L["OPT_RANK_LOWEST"]       = "Низший ранг"
L["BTN_RELOAD_DATA"]       = "Перезагрузить"
L["BTN_CLEAR_CACHE"]       = "Очистить кэш"
L["BTN_OPEN_LOG"]          = "Открыть журнал"
L["BTN_APPLY_CLOSE"]       = "Принять"
L["OPT_SHALLOW_FILL_TIP"]  = "Цены рассчитываются путём симуляции покупки указанного количества единиц из книги заявок АД. Низкие значения отражают стоимость небольших партий; высокие усредняют по большему предложению. Диапазон: 10–10 000."
L["OPT_SHALLOW_FILL_QTY"]  = "Кол-во заполнения:"
L["OPT_SHALLOW_FILL_RANGE"] = "(10 - 10 000)"
L["FILL_QTY_ACTIVE"]       = "Кол-во заполнения: %s ед."

-- ── Strategy Creator ─────────────────────────────────────────────────────
L["BTN_CREATE_STRAT"]      = "Создать стратегию"
L["BTN_IMPORT_STRAT"]      = "Импорт"
L["BTN_EXPORT_STRAT"]      = "Экспорт"
L["BTN_EDIT_STRAT"]        = "Правка"
L["BTN_DELETE_STRAT"]      = "Удалить"
L["BTN_REMOVE"]            = "x"
L["CREATOR_TITLE"]         = "Создать стратегию"
L["CREATOR_EDIT_TITLE"]    = "Изменить стратегию"
L["CREATOR_PROFESSION"]    = "Профессия:"
L["CREATOR_NAME"]          = "Название стратегии:"
L["CREATOR_INPUT_QTY"]     = "Входное количество:"
L["CREATOR_INPUT_QTY_TIP"] = "Базовое количество, против которого рассчитываются все коэффициенты (напр. 1000 трав для перемола)"
L["CREATOR_INPUT_HINT"]    = "(все кол-ва ниже — на это входное количество)"
L["CREATOR_OUTPUTS"]       = "Выходы"
L["CREATOR_REAGENTS"]      = "Реагенты"
L["CREATOR_NOTES"]         = "Заметки:"
L["CREATOR_COL_NAME"]      = "Название предмета"
L["CREATOR_COL_ITEMID"]    = "ID предмета"
L["CREATOR_COL_QTY"]       = "Кол."
L["BTN_CREATOR_SAVE"]      = "Сохранить"
L["BTN_CREATOR_DELETE"]    = "Удалить"
L["BTN_CREATOR_ADD_OUT"]   = "+ Выход"
L["BTN_CREATOR_ADD_REAG"]  = "+ Реагент"
L["CREATOR_CUSTOM_PROF"]   = "(Пользовательский...)"
L["MSG_STRAT_SAVED"]       = "Стратегия '%s' сохранена."
L["MSG_STRAT_DELETED"]     = "Стратегия '%s' удалена."
L["EXPORT_POPUP_TITLE"]    = "Экспорт стратегии"
L["EXPORT_ENCODED_LBL"]    = "Закодировано — поделитесь с другими пользователями GAM:"
L["EXPORT_LUA_LBL"]        = "Редактирование файла — вставьте в Data/StratsManual.lua:"
L["IMPORT_POPUP_TITLE"]    = "Импорт стратегии"
L["IMPORT_ENCODED_LBL"]    = "Вставьте закодированную строку (GAM1:...):"
L["MSG_STRAT_IMPORTED"]    = "Стратегия '%s' импортирована."
L["ERR_IMPORT_INVALID"]    = "Неверная или нераспознанная строка импорта."
L["ERR_PROF_REQUIRED"]     = "Профессия обязательна."
L["ERR_NAME_REQUIRED"]     = "Название стратегии обязательно."
L["ERR_QTY_REQUIRED"]      = "Входное количество должно быть больше 0."
L["ERR_OUTPUT_REQUIRED"]   = "Требуется хотя бы один выход."

-- ── Minimap ──────────────────────────────────────────────────────────────
L["MINIMAP_TIP"]           = "Gold Advisor Midnight\nЛКМ: Открыть/закрыть\nПКМ: Настройки\nТащить: Переместить кнопку"

-- ── Scanning ─────────────────────────────────────────────────────────────
L["SCAN_STARTED"]          = "Сканирование %d предм...."
L["SCAN_COMPLETE"]         = "Скан завершён. %d OK, %d ошибок."
L["SCAN_AH_CLOSED"]        = "АД закрыт — скан остановлен."
L["SCAN_THROTTLED"]        = "АД ограничен, повтор..."
L["PRICE_UPDATED"]         = "Цена обновлена: %s = %s"

-- ── Errors / Warnings ────────────────────────────────────────────────────
L["ERR_NO_AH"]             = "Сначала откройте Аукционный дом."
L["ERR_STRAT_INVALID"]     = "Неверная стратегия: %s"
L["WARN_PRICE_STALE"]      = "Цены могут быть устаревшими (>%d мин)."
