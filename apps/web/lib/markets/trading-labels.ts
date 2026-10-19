export const TRADING_STYLE_LABELS = {
    scalping: "Scalping · Vài phút",
    intraday: "Intraday · Trong ngày",
    swing: "Swing · Nhiều ngày",
};

export const RISK_FLAG_LABELS: Record<string, string> = {
    MARKET_UNAVAILABLE: "Thị trường không khả dụng",
    TIMEFRAME_DATA_MISSING: "Thiếu nến liên tiếp hoặc nến đã cũ",
    PRICE_STALE_OR_MISSING: "Giá thiếu hoặc quá 90 giây",
    STATS_STALE_OR_MISSING: "Thống kê 24h chưa đủ mới",
    LIQUIDITY_SOURCE_UNSUPPORTED: "Nguồn này chưa có dữ liệu sổ lệnh",
    LIQUIDITY_MISSING: "Chưa đồng bộ sổ lệnh",
    LIQUIDITY_STALE: "Sổ lệnh đã cũ hoặc không hợp lệ",
    TREND_NOT_ALIGNED: "EMA20/50/200 chưa đồng thuận xu hướng tăng",
    ENTRY_NOT_CONFIRMED: "Chưa xác nhận setup và nến vào lệnh",
    PLAN_UNAVAILABLE: "Chưa đủ dữ liệu tính kế hoạch",
    DEPTH_INSUFFICIENT: "Chưa đủ độ sâu để mô phỏng toàn bộ vị thế",
    SPREAD_TOO_WIDE: "Spread vượt giới hạn nghiên cứu",
    VOLATILITY_TOO_HIGH: "ATR% vượt giới hạn nghiên cứu",
    NET_REWARD_RISK_TOO_LOW: "Lợi nhuận/rủi ro sau phí chưa đạt ngưỡng",
    SLIPPAGE_EXCEEDS_ASSUMPTION: "Chi phí từ sổ lệnh vượt giả định trượt giá",
    BACKTEST_NOT_AVAILABLE: "Chưa có backtest cho phiên bản setup này",
    STRATEGY_UNVALIDATED: "Chiến lược chưa được kiểm chứng",
};

export const REGIME_LABELS: Record<string, string> = {
    BULLISH: "Xu hướng tăng",
    BEARISH: "Xu hướng giảm",
    RANGING_OR_MIXED: "Đi ngang / xung đột",
    UNKNOWN: "Chưa đủ dữ liệu",
};
