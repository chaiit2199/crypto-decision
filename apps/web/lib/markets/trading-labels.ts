export const TRADING_STYLE_LABELS = {
    scalping: "Giao nhanh · vài phút",
    intraday: "Trong ngày",
    swing: "Nhiều ngày",
};

export const ELIGIBILITY_LABELS: Record<string, string> = {
    NO_DATA: "Chưa đủ dữ liệu",
    WAIT: "Đang chờ điều kiện",
    RESEARCH_CANDIDATE: "Đáng theo dõi · chưa kiểm chứng",
};

export const SETUP_LABELS: Record<string, string> = {
    BREAKOUT: "Phá kháng cự",
    RETEST: "Chạm lại kháng cự",
    PULLBACK: "Hiệu chỉnh về hỗ trợ",
};

export const SETUP_QUALITY_LABELS: Record<string, string> = {
    CONFIRMED: "đã xác nhận",
    UNCONFIRMED: "chưa xác nhận",
};

export const HOLDING_HORIZON_LABELS: Record<string, string> = {
    SCALP: "Vài phút",
    INTRADAY: "Trong ngày",
    SWING: "Nhiều ngày",
    UNSUITABLE: "Chưa phù hợp giữ lệnh",
};

export const AI_SIGNAL_LABELS: Record<string, string> = {
    BUY_CANDIDATE: "Theo dõi mua",
    EXIT_CANDIDATE: "Theo dõi bán / giảm vị thế",
    WAIT: "Chờ tín hiệu rõ hơn",
    NO_DATA: "Chưa có nhận định",
};

export const RISK_FLAG_LABELS: Record<string, string> = {
    MARKET_UNAVAILABLE: "Thị trường không khả dụng",
    TIMEFRAME_DATA_MISSING: "Thiếu nến hoặc nến đã cũ",
    PRICE_STALE_OR_MISSING: "Giá thiếu hoặc quá cũ",
    STATS_STALE_OR_MISSING: "Thống kê 24 giờ chưa đủ mới",
    LIQUIDITY_SOURCE_UNSUPPORTED: "Nguồn này chưa có sổ lệnh",
    LIQUIDITY_MISSING: "Chưa có sổ lệnh",
    LIQUIDITY_STALE: "Sổ lệnh đã cũ",
    TREND_NOT_ALIGNED: "Xu hướng trung bình chưa đồng thuận tăng",
    ENTRY_NOT_CONFIRMED: "Chưa xác nhận mẫu hình và nến vào",
    PLAN_UNAVAILABLE: "Chưa đủ dữ liệu tính kế hoạch",
    DEPTH_INSUFFICIENT: "Sổ lệnh chưa đủ sâu cho vị thế giả định",
    SPREAD_TOO_WIDE: "Chênh mua/bán quá rộng",
    VOLATILITY_TOO_HIGH: "Biến động vượt ngưỡng nghiên cứu",
    NET_REWARD_RISK_TOO_LOW: "Tỷ lệ lãi/rủi ro sau phí chưa đạt",
    SLIPPAGE_EXCEEDS_ASSUMPTION: "Chi phí trượt giá từ sổ lệnh quá cao",
    BACKTEST_NOT_AVAILABLE: "Chưa có kiểm chứng lịch sử cho mẫu hình này",
    STRATEGY_UNVALIDATED: "Chiến lược chưa được kiểm chứng",
};

export const REGIME_LABELS: Record<string, string> = {
    BULLISH: "Xu hướng tăng",
    BEARISH: "Xu hướng giảm",
    RANGING_OR_MIXED: "Đi ngang / xung đột",
    UNKNOWN: "Chưa đủ dữ liệu",
};

export const AI_REASON_LABELS: Record<string, string> = {
    jev_disabled: "Phân tích Jev đang tắt",
    analysis_not_run: "Chưa có lần phân tích nào",
    analysis_expired: "Bản phân tích đã hết hạn",
    analysis_unavailable: "Không đọc được phân tích",
    missing_snapshots: "Thiếu giá hoặc thống kê 24 giờ",
    stale_price: "Giá quá cũ",
    stale_stats: "Thống kê 24 giờ quá cũ",
    insufficient_candles: "Chưa đủ 300 nến giờ đã đóng",
    candle_gap: "Lịch sử nến bị thiếu khoảng",
    stale_candles: "Nến giờ đã cũ",
    missing_api_key: "Chưa cấu hình khóa API Jev",
    authentication_failed: "Khóa API Jev không hợp lệ",
    rate_limited: "Jev đang giới hạn số lần gọi",
    upstream_unavailable: "Jev tạm thời không sẵn sàng",
};

export const SIMULATION_KIND_LABELS: Record<string, string> = {
    replay: "Phát lại lịch sử",
    paper: "Lệnh giả lập",
};
