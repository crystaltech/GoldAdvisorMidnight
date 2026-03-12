-- GoldAdvisorMidnight/Locale/zhCN.lua
-- Simplified Chinese (zhCN) translations for Gold Advisor Midnight.
-- To contribute: replace each English value on the RIGHT side of = with your translation.
-- Do NOT modify keys (the quoted text on the LEFT side of =).
-- See TRANSLATING.md at the project root for full contributor guidelines.
-- After making changes, reload the addon in-game with /reload to test.

if GetLocale() ~= "zhCN" then return end
local _, GAM = ...
local L = GAM.L  -- base table already created by Locale.lua; override keys below

-- ── General ──────────────────────────────────────────────────────────────
-- L["ADDON_TITLE"]           = "Gold Advisor Midnight"  -- addon name, keep in English
L["LOADED_MSG"]            = "Gold Advisor Midnight v%s 已加载。/gam 切换显示。"

-- ── Main Window ──────────────────────────────────────────────────────────
-- L["MAIN_TITLE"]            = "Gold Advisor Midnight"  -- addon name, keep in English
L["FILTER_PATCH"]          = "版本："
L["FILTER_PROFESSION"]     = "专业："
L["FILTER_SEARCH"]         = "搜索..."
L["COL_STRAT"]             = "策略"
L["COL_PROF"]              = "专业"
L["COL_PROFIT"]            = "利润"
L["COL_ROI"]               = "ROI%"
L["COL_STATUS"]            = "状态"
L["BTN_SCAN_ALL"]          = "扫描全部"
L["BTN_SCAN_STOP"]         = "停止扫描"
L["BTN_SHOPPING"]          = "购物清单"
L["BTN_LOG"]               = "调试日志"
L["BTN_CLOSE"]             = "关闭"
L["NO_STRATS"]             = "没有匹配筛选条件的策略。"
L["MISSING_PRICES"]        = "! 价格缺失"
L["STATUS_STALE"]          = "已过时"
L["STATUS_FRESH"]          = "最新"
L["STATUS_NEVER"]          = "从未扫描"
L["STATUS_STRAT_COUNT"]    = "%d 个策略"
L["STATUS_SCANNING_PROG"]  = "扫描中..."
L["STATUS_QUEUING"]        = "正在准备物品..."

-- ── Strat Detail ─────────────────────────────────────────────────────────
L["DETAIL_TITLE"]          = "策略详情"
L["DETAIL_OUTPUT"]         = "产出："
L["DETAIL_REAGENTS"]       = "材料："
L["DETAIL_INPUT_HDR"]      = "输入物品"
L["DETAIL_OUTPUT_HDR"]     = "输出物品"
L["COL_ITEM"]              = "物品"
L["COL_QTY_CRAFT"]         = "总数量"
L["COL_HAVE"]              = "已有"
L["COL_NEED_BUY"]          = "需购买"
L["COL_UNIT_PRICE"]        = "单价"
L["COL_TOTAL_COST"]        = "总费用"
L["COL_REVENUE"]           = "净收入"
L["BTN_SCAN_ITEM"]         = "扫描"
L["BTN_SCAN_ALL_ITEMS"]    = "扫描全部"
L["BTN_PUSH_CRAFTSIM"]     = "推送至CraftSim"
L["TT_CRAFTSIM_TITLE"]     = "将价格覆盖推送至CraftSim"
L["TT_CRAFTSIM_WARN"]      = "警告：这将覆盖CraftSim中该策略所有材料的现有手动价格覆盖。"
L["LBL_COST"]              = "总费用："
L["LBL_REVENUE"]           = "净收入："
L["LBL_PROFIT"]            = "利润："
L["LBL_ROI"]               = "ROI："
L["LBL_BREAKEVEN"]         = "保本售价："
L["RANK_SELECT"]           = "品质："
L["RANK_BTN_R1"]           = "R1 材料"
L["RANK_BTN_R2"]           = "R2 材料"
L["NO_PRICE"]              = "—"
L["CONFIRM_DELETE_BODY"]   = "删除策略：\n\"|cffffffff%s|r\"\n\n此操作无法撤销。"

-- ── Shopping List ─────────────────────────────────────────────────────────
L["SHOP_TITLE"]            = "购物清单"
L["SHOP_ITEM"]             = "物品"
L["SHOP_NEED"]             = "需购买"
L["SHOP_HAVE"]             = "已有"
L["BTN_COPY_LIST"]         = "复制"
L["BTN_AUCTIONATOR"]       = "Auctionator清单"
L["SHOP_EMPTY"]            = "无需购买物品。"
L["AUCTIONATOR_LIST_NAME"] = "GAM Shopping List"  -- internal ID, keep in English
L["MSG_AUCTIONATOR_CREATED"]   = "Auctionator清单 '%s' 已创建（%d 件物品）。打开购物标签进行购买。"
L["MSG_AUCTIONATOR_NO_ITEMS"]  = "无需购买 — 购物清单为空。"
L["MSG_AUCTIONATOR_NOT_FOUND"] = "未安装Auctionator。请安装后使用此功能。"

-- ── Debug Log ────────────────────────────────────────────────────────────
L["LOG_TITLE"]             = "调试日志"
L["BTN_CLEAR_LOG"]         = "清除"
L["BTN_COPY_LOG"]          = "全部复制"
L["BTN_PAUSE_LOG"]         = "暂停"
L["BTN_RESUME_LOG"]        = "继续"
L["BTN_DUMP_IDS"]          = "导出ID"
L["BTN_ARP_EXPORT"]        = "ARP Export"
L["LOG_PAUSED"]            = "[日志已暂停]"
L["LOG_CLEARED"]           = "[日志已清除]"

-- ── Settings ─────────────────────────────────────────────────────────────
-- L["SETTINGS_NAME"]         = "Gold Advisor Midnight"  -- addon name, keep in English
L["OPT_SCAN_DELAY"]        = "扫描延迟（秒）"
L["OPT_SCAN_DELAY_TIP"]    = "拍卖行查询间隔秒数。越低越快，但限速风险越高。"
L["OPT_VERBOSITY"]         = "调试级别"
L["OPT_VERBOSITY_TIP"]     = "0=关闭, 1=信息, 2=调试, 3=详细"
L["OPT_MINIMAP"]           = "显示小地图按钮"
L["OPT_RANK_POLICY"]       = "品质选择策略"
L["OPT_RANK_HIGHEST"]      = "最高品质"
L["OPT_RANK_LOWEST"]       = "最低品质"
L["BTN_RELOAD_DATA"]       = "重新加载"
L["BTN_CLEAR_CACHE"]       = "清除缓存"
L["BTN_OPEN_LOG"]          = "打开日志"
L["BTN_APPLY_CLOSE"]       = "确认"
L["OPT_SHALLOW_FILL_TIP"]  = "通过模拟从拍卖行订单簿购买此数量的物品来计算价格。较低的值反映小批量购买的成本；较高的值对更多供应取平均。范围：10–10,000。"
L["OPT_SHALLOW_FILL_QTY"]  = "填充数量："
L["OPT_SHALLOW_FILL_RANGE"] = "（10 - 10,000）"
L["FILL_QTY_ACTIVE"]       = "填充数量：%s 件"

-- ── Strategy Creator ─────────────────────────────────────────────────────
L["BTN_CREATE_STRAT"]      = "创建策略"
L["BTN_IMPORT_STRAT"]      = "导入"
L["BTN_EXPORT_STRAT"]      = "导出"
L["BTN_EDIT_STRAT"]        = "编辑"
L["BTN_DELETE_STRAT"]      = "删除"
L["BTN_REMOVE"]            = "x"
L["CREATOR_TITLE"]         = "创建策略"
L["CREATOR_EDIT_TITLE"]    = "编辑策略"
L["CREATOR_PROFESSION"]    = "专业："
L["CREATOR_NAME"]          = "策略名称："
L["CREATOR_INPUT_QTY"]     = "输入数量："
L["CREATOR_INPUT_QTY_TIP"] = "所有比率计算的基准数量（例如1000草药用于研磨）"
L["CREATOR_INPUT_HINT"]    = "（以下所有数量均基于此输入数量）"
L["CREATOR_OUTPUTS"]       = "产出"
L["CREATOR_REAGENTS"]      = "材料"
L["CREATOR_NOTES"]         = "备注："
L["CREATOR_COL_NAME"]      = "物品名称"
L["CREATOR_COL_ITEMID"]    = "物品ID"
L["CREATOR_COL_QTY"]       = "数量"
L["BTN_CREATOR_SAVE"]      = "保存"
L["BTN_CREATOR_DELETE"]    = "删除"
L["BTN_CREATOR_ADD_OUT"]   = "+ 产出"
L["BTN_CREATOR_ADD_REAG"]  = "+ 材料"
L["CREATOR_CUSTOM_PROF"]   = "（自定义...）"
L["MSG_STRAT_SAVED"]       = "策略 '%s' 已保存。"
L["MSG_STRAT_DELETED"]     = "策略 '%s' 已删除。"
L["EXPORT_POPUP_TITLE"]    = "导出策略"
L["EXPORT_ENCODED_LBL"]    = "已编码 — 分享给其他GAM用户："
L["EXPORT_LUA_LBL"]        = "文件编辑 — 粘贴至 Data/StratsManual.lua："
L["IMPORT_POPUP_TITLE"]    = "导入策略"
L["IMPORT_ENCODED_LBL"]    = "粘贴编码字符串（GAM1:...）："
L["MSG_STRAT_IMPORTED"]    = "策略 '%s' 已导入。"
L["ERR_IMPORT_INVALID"]    = "无效或无法识别的导入字符串。"
L["ERR_PROF_REQUIRED"]     = "专业为必填项。"
L["ERR_NAME_REQUIRED"]     = "策略名称为必填项。"
L["ERR_QTY_REQUIRED"]      = "输入数量必须大于0。"
L["ERR_OUTPUT_REQUIRED"]   = "至少需要一个产出。"

-- ── Minimap ──────────────────────────────────────────────────────────────
L["MINIMAP_TIP"]           = "Gold Advisor Midnight\n左键：切换窗口\n右键：设置\n拖动：移动按钮"

-- ── Scanning ─────────────────────────────────────────────────────────────
L["SCAN_STARTED"]          = "正在扫描 %d 件物品..."
L["SCAN_COMPLETE"]         = "扫描完成。%d 成功，%d 失败。"
L["SCAN_AH_CLOSED"]        = "拍卖行已关闭 — 扫描停止。"
L["SCAN_THROTTLED"]        = "拍卖行受限，重试中..."
L["PRICE_UPDATED"]         = "价格已更新：%s = %s"

-- ── Errors / Warnings ────────────────────────────────────────────────────
L["ERR_NO_AH"]             = "请先打开拍卖行。"
L["ERR_STRAT_INVALID"]     = "无效策略：%s"
L["WARN_PRICE_STALE"]      = "价格可能已过时（>%d 分钟）。"
