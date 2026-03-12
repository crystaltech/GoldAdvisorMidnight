-- GoldAdvisorMidnight/Locale/koKR.lua
-- Korean (koKR) translations for Gold Advisor Midnight.
-- To contribute: replace each English value on the RIGHT side of = with your translation.
-- Do NOT modify keys (the quoted text on the LEFT side of =).
-- See TRANSLATING.md at the project root for full contributor guidelines.
-- After making changes, reload the addon in-game with /reload to test.

if GetLocale() ~= "koKR" then return end
local _, GAM = ...
local L = GAM.L  -- base table already created by Locale.lua; override keys below

-- ── General ──────────────────────────────────────────────────────────────
-- L["ADDON_TITLE"]           = "Gold Advisor Midnight"  -- addon name, keep in English
L["LOADED_MSG"]            = "Gold Advisor Midnight v%s 로드됨. /gam 으로 표시/숨기기."

-- ── Main Window ──────────────────────────────────────────────────────────
-- L["MAIN_TITLE"]            = "Gold Advisor Midnight"  -- addon name, keep in English
L["FILTER_PATCH"]          = "패치:"
L["FILTER_PROFESSION"]     = "전문기술:"
L["FILTER_SEARCH"]         = "검색..."
L["COL_STRAT"]             = "전략"
L["COL_PROF"]              = "전문기술"
L["COL_PROFIT"]            = "수익"
L["COL_ROI"]               = "ROI%"
L["COL_STATUS"]            = "상태"
L["BTN_SCAN_ALL"]          = "전체 스캔"
L["BTN_SCAN_STOP"]         = "스캔 중지"
L["BTN_SHOPPING"]          = "구매 목록"
L["BTN_LOG"]               = "디버그 로그"
L["BTN_CLOSE"]             = "닫기"
L["NO_STRATS"]             = "필터에 맞는 전략이 없습니다."
L["MISSING_PRICES"]        = "! 가격 없음"
L["STATUS_STALE"]          = "오래됨"
L["STATUS_FRESH"]          = "최신"
L["STATUS_NEVER"]          = "미스캔"
L["STATUS_STRAT_COUNT"]    = "%d개 전략"
L["STATUS_SCANNING_PROG"]  = "스캔 중..."
L["STATUS_QUEUING"]        = "아이템 준비 중..."

-- ── Strat Detail ─────────────────────────────────────────────────────────
L["DETAIL_TITLE"]          = "전략 상세"
L["DETAIL_OUTPUT"]         = "출력:"
L["DETAIL_REAGENTS"]       = "재료:"
L["DETAIL_INPUT_HDR"]      = "입력 아이템"
L["DETAIL_OUTPUT_HDR"]     = "출력 아이템"
L["COL_ITEM"]              = "아이템"
L["COL_QTY_CRAFT"]         = "총 수량"
L["COL_HAVE"]              = "보유"
L["COL_NEED_BUY"]          = "구매 필요"
L["COL_UNIT_PRICE"]        = "단가"
L["COL_TOTAL_COST"]        = "총 비용"
L["COL_REVENUE"]           = "순수익"
L["BTN_SCAN_ITEM"]         = "스캔"
L["BTN_SCAN_ALL_ITEMS"]    = "전체 스캔"
L["BTN_PUSH_CRAFTSIM"]     = "CraftSim 전송"
L["TT_CRAFTSIM_TITLE"]     = "CraftSim에 가격 덮어쓰기 전송"
L["TT_CRAFTSIM_WARN"]      = "경고: 이 전략의 모든 재료에 대한 CraftSim의 기존 수동 가격 덮어쓰기가 모두 대체됩니다."
L["LBL_COST"]              = "총 비용:"
L["LBL_REVENUE"]           = "순수익:"
L["LBL_PROFIT"]            = "수익:"
L["LBL_ROI"]               = "ROI:"
L["LBL_BREAKEVEN"]         = "손익분기 판매가:"
L["RANK_SELECT"]           = "등급:"
L["RANK_BTN_R1"]           = "R1 재료"
L["RANK_BTN_R2"]           = "R2 재료"
L["NO_PRICE"]              = "—"
L["CONFIRM_DELETE_BODY"]   = "전략 삭제:\n\"|cffffffff%s|r\"\n\n이 작업은 취소할 수 없습니다."

-- ── Shopping List ─────────────────────────────────────────────────────────
L["SHOP_TITLE"]            = "구매 목록"
L["SHOP_ITEM"]             = "아이템"
L["SHOP_NEED"]             = "구매 필요"
L["SHOP_HAVE"]             = "보유"
L["BTN_COPY_LIST"]         = "복사"
L["BTN_AUCTIONATOR"]       = "Auctionator 목록"
L["SHOP_EMPTY"]            = "구매할 아이템이 없습니다."
L["AUCTIONATOR_LIST_NAME"] = "GAM Shopping List"  -- internal ID, keep in English
L["MSG_AUCTIONATOR_CREATED"]   = "Auctionator 목록 '%s' 생성됨 (%d개 아이템). 구매탭을 열어 구매하세요."
L["MSG_AUCTIONATOR_NO_ITEMS"]  = "구매할 것 없음 — 구매 목록이 비어 있습니다."
L["MSG_AUCTIONATOR_NOT_FOUND"] = "Auctionator가 설치되지 않았습니다. 이 기능을 사용하려면 설치하세요."

-- ── Debug Log ────────────────────────────────────────────────────────────
L["LOG_TITLE"]             = "디버그 로그"
L["BTN_CLEAR_LOG"]         = "지우기"
L["BTN_COPY_LOG"]          = "전체 복사"
L["BTN_PAUSE_LOG"]         = "일시정지"
L["BTN_RESUME_LOG"]        = "재개"
L["BTN_DUMP_IDS"]          = "ID 내보내기"
L["BTN_ARP_EXPORT"]        = "ARP Export"
L["LOG_PAUSED"]            = "[로그 일시정지]"
L["LOG_CLEARED"]           = "[로그 지워짐]"

-- ── Settings ─────────────────────────────────────────────────────────────
-- L["SETTINGS_NAME"]         = "Gold Advisor Midnight"  -- addon name, keep in English
L["OPT_SCAN_DELAY"]        = "스캔 지연 (초)"
L["OPT_SCAN_DELAY_TIP"]    = "경매장 조회 간격(초). 낮을수록 빠르지만 제한 위험 증가."
L["OPT_VERBOSITY"]         = "디버그 수준"
L["OPT_VERBOSITY_TIP"]     = "0=끔, 1=정보, 2=디버그, 3=상세"
L["OPT_MINIMAP"]           = "미니맵 버튼 표시"
L["OPT_RANK_POLICY"]       = "등급 선택 정책"
L["OPT_RANK_HIGHEST"]      = "최고 등급"
L["OPT_RANK_LOWEST"]       = "최저 등급"
L["BTN_RELOAD_DATA"]       = "새로고침"
L["BTN_CLEAR_CACHE"]       = "캐시 지우기"
L["BTN_OPEN_LOG"]          = "로그 열기"
L["BTN_APPLY_CLOSE"]       = "확인"
L["OPT_SHALLOW_FILL_TIP"]  = "경매장 주문서에서 이 수량만큼 구매하는 시뮬레이션으로 가격을 계산합니다. 낮은 값은 소량 구매 비용을, 높은 값은 더 많은 공급량을 평균합니다. 범위: 10–10,000."
L["OPT_SHALLOW_FILL_QTY"]  = "채움 수량:"
L["OPT_SHALLOW_FILL_RANGE"] = "(10 - 10,000)"
L["FILL_QTY_ACTIVE"]       = "채움 수량: %s개"

-- ── Strategy Creator ─────────────────────────────────────────────────────
L["BTN_CREATE_STRAT"]      = "전략 생성"
L["BTN_IMPORT_STRAT"]      = "가져오기"
L["BTN_EXPORT_STRAT"]      = "내보내기"
L["BTN_EDIT_STRAT"]        = "편집"
L["BTN_DELETE_STRAT"]      = "삭제"
L["BTN_REMOVE"]            = "x"
L["CREATOR_TITLE"]         = "전략 생성"
L["CREATOR_EDIT_TITLE"]    = "전략 편집"
L["CREATOR_PROFESSION"]    = "전문기술:"
L["CREATOR_NAME"]          = "전략 이름:"
L["CREATOR_INPUT_QTY"]     = "입력 수량:"
L["CREATOR_INPUT_QTY_TIP"] = "모든 비율 계산의 기준 수량 (예: 분쇄할 1000개 약초)"
L["CREATOR_INPUT_HINT"]    = "(아래 모든 수량은 이 입력 수량 기준)"
L["CREATOR_OUTPUTS"]       = "출력"
L["CREATOR_REAGENTS"]      = "재료"
L["CREATOR_NOTES"]         = "메모:"
L["CREATOR_COL_NAME"]      = "아이템 이름"
L["CREATOR_COL_ITEMID"]    = "아이템 ID"
L["CREATOR_COL_QTY"]       = "수량"
L["BTN_CREATOR_SAVE"]      = "저장"
L["BTN_CREATOR_DELETE"]    = "삭제"
L["BTN_CREATOR_ADD_OUT"]   = "+ 출력"
L["BTN_CREATOR_ADD_REAG"]  = "+ 재료"
L["CREATOR_CUSTOM_PROF"]   = "(사용자 지정...)"
L["MSG_STRAT_SAVED"]       = "전략 '%s' 저장됨."
L["MSG_STRAT_DELETED"]     = "전략 '%s' 삭제됨."
L["EXPORT_POPUP_TITLE"]    = "전략 내보내기"
L["EXPORT_ENCODED_LBL"]    = "인코딩됨 — 다른 GAM 사용자와 공유:"
L["EXPORT_LUA_LBL"]        = "파일 편집 — Data/StratsManual.lua 에 붙여넣기:"
L["IMPORT_POPUP_TITLE"]    = "전략 가져오기"
L["IMPORT_ENCODED_LBL"]    = "인코딩된 문자열 붙여넣기 (GAM1:...):"
L["MSG_STRAT_IMPORTED"]    = "전략 '%s' 가져옴."
L["ERR_IMPORT_INVALID"]    = "유효하지 않거나 인식할 수 없는 가져오기 문자열."
L["ERR_PROF_REQUIRED"]     = "전문기술은 필수입니다."
L["ERR_NAME_REQUIRED"]     = "전략 이름은 필수입니다."
L["ERR_QTY_REQUIRED"]      = "입력 수량은 0보다 커야 합니다."
L["ERR_OUTPUT_REQUIRED"]   = "최소 하나의 출력이 필요합니다."

-- ── Minimap ──────────────────────────────────────────────────────────────
L["MINIMAP_TIP"]           = "Gold Advisor Midnight\n좌클릭: 창 전환\n우클릭: 설정\n드래그: 버튼 이동"

-- ── Scanning ─────────────────────────────────────────────────────────────
L["SCAN_STARTED"]          = "%d개 아이템 스캔 중..."
L["SCAN_COMPLETE"]         = "스캔 완료. %d 성공, %d 실패."
L["SCAN_AH_CLOSED"]        = "경매장 닫힘 — 스캔 중단됨."
L["SCAN_THROTTLED"]        = "경매장 제한됨, 재시도 중..."
L["PRICE_UPDATED"]         = "가격 업데이트: %s = %s"

-- ── Errors / Warnings ────────────────────────────────────────────────────
L["ERR_NO_AH"]             = "먼저 경매장을 여세요."
L["ERR_STRAT_INVALID"]     = "유효하지 않은 전략: %s"
L["WARN_PRICE_STALE"]      = "가격이 오래되었을 수 있습니다 (>%d분)."
