import type { Market } from "@/lib/api/types";
import { formatIndicator } from "@/lib/format/market";
import { formatChartTime } from "@/lib/format/chart-time";
import {
    ANSWER_EXPLANATIONS,
    SIGNAL_EXPLANATIONS,
} from "@/lib/markets/analysis-explanation";

type MarketAnalysisProps = {
    market: Market | undefined;
    now: number;
};

const CHOICE_LABELS: Record<string, string> = {
    BULLISH: "Xu hướng tăng",
    BEARISH: "Xu hướng giảm",
    SIDEWAYS: "Đi ngang / chưa rõ",
    STRENGTHENING: "Lực mua tích cực",
    WEAKENING: "Lực mua suy yếu",
    MIXED: "Tín hiệu xung đột",
    ELEVATED: "Biến động cao",
    NORMAL: "Chưa thấy biến động cao",
    SCALP: "Vài phút",
    INTRADAY: "Trong ngày",
    SWING: "Nhiều ngày",
    UNSUITABLE: "Chưa phù hợp giữ lệnh",
};

const SIGNAL_LABELS = {
    BUY: "Theo dõi mua",
    SELL: "Theo dõi bán",
    WAIT: "Chờ tín hiệu rõ hơn",
    NO_DATA: "Chưa đủ dữ liệu",
};

const ANSWER_NAMES: Record<string, string> = {
    trend: "Xu hướng",
    momentum: "Động lượng",
    volatility: "Biến động",
    holding_horizon: "Thời gian giữ gợi ý",
};

const INDICATORS = [
    {
        key: "ema20",
        name: "EMA20",
        description:
            "Trung bình giá hàm mũ chu kỳ 20 nến 1H, ưu tiên giá gần đây để theo dõi xu hướng ngắn hạn.",
    },
    {
        key: "ema50",
        name: "EMA50",
        description:
            "Trung bình giá hàm mũ chu kỳ 50 nến 1H, giúp quan sát xu hướng ít nhạy hơn EMA20.",
    },
    {
        key: "ema200",
        name: "EMA200",
        description:
            "Trung bình giá hàm mũ chu kỳ 200 nến 1H, dùng làm mốc tham chiếu xu hướng dài hơn.",
    },
    {
        key: "rsi14",
        name: "RSI14",
        description:
            "Đo động lượng giá chu kỳ 14 nến trên thang 0–100; giá trị cao cho thấy mức tăng chiếm ưu thế.",
    },
    {
        key: "macd",
        name: "MACD (12/26)",
        description:
            "Chênh lệch EMA12 và EMA26, cho biết đường trung bình nhanh đang cao hay thấp hơn đường chậm.",
    },
    {
        key: "macd_signal",
        name: "Đường tín hiệu MACD (9)",
        description:
            "Trung bình hàm mũ 9 kỳ của MACD, dùng làm mốc so sánh động lượng.",
    },
    {
        key: "macd_histogram",
        name: "Cột MACD",
        description:
            "MACD trừ đường tín hiệu; dương khi MACD nằm trên đường tín hiệu.",
    },
    {
        key: "atr14",
        name: "ATR14",
        description:
            "Đo biên độ biến động giá chu kỳ 14 nến, theo đơn vị giá của cặp; không cho biết hướng tăng/giảm.",
    },
    {
        key: "adx14",
        name: "ADX14",
        description:
            "Đo sức mạnh xu hướng chu kỳ 14 nến trên thang 0–100; càng cao, xu hướng càng mạnh, bất kể hướng.",
    },
    {
        key: "relative_volume20",
        name: "Khối lượng tương đối (20)",
        description:
            "Khối lượng nến đã đóng gần nhất chia trung bình 20 nến trước; trên 1 là cao hơn trung bình.",
    },
    {
        key: "return_1h_percent",
        name: "Biến động 1H (%)",
        description:
            "Phần trăm thay đổi giữa hai giá đóng cửa 1H gần nhất; dương là tăng, âm là giảm.",
    },
    {
        key: "return_24h_percent",
        name: "Biến động 24H (%)",
        description:
            "Phần trăm thay đổi của giá đóng cửa gần nhất so với 24 nến 1H trước; dương là tăng, âm là giảm.",
    },
] as const;

const REASON_LABELS: Record<string, string> = {
    authentication_failed:
        "Khóa API Jev bị từ chối. Cần cập nhật khóa ở máy chủ.",
    access_denied: "Tài khoản chưa có quyền truy cập Jev.",
    quota_exhausted: "Tài khoản Jev đã hết hạn mức gọi.",
    missing_api_key:
        "Chưa cấu hình khóa API Jev; chờ kết quả mới sau khi cập nhật.",
    rate_limited:
        "Jev đang giới hạn lượt gọi; hệ thống tạm dừng và sẽ thử lại.",
    upstream_unavailable: "Jev tạm thời không sẵn sàng.",
    transport_error: "Không kết nối được Jev; hệ thống sẽ thử ở kỳ tiếp theo.",
    request_rejected:
        "Jev không chấp nhận yêu cầu; cần kiểm tra cấu hình máy chủ.",
    invalid_response:
        "Phản hồi Jev không đúng định dạng; chưa thể dùng để phân tích.",
    insufficient_candles: "Cần ít nhất 300 nến giờ đã đóng để tính chỉ báo.",
    candle_gap: "Lịch sử nến có khoảng trống; đang chờ đồng bộ.",
    stale_candles: "Lịch sử nến chưa cập nhật đến giờ gần nhất.",
    invalid_candles: "Nến chưa đủ chất lượng để phân tích.",
    stale_price: "Giá đã cũ; chưa gọi Jev.",
    stale_stats: "Thống kê 24 giờ đã cũ; chưa gọi Jev.",
    missing_snapshots: "Chưa có đủ giá và thống kê 24 giờ.",
    symbol_unavailable: "Cặp giao dịch không khả dụng.",
};

export function MarketAnalysis({ market, now }: MarketAnalysisProps) {
    const analysis = market?.analysis;
    const stale =
        analysis &&
        (analysis.freshness === "stale" ||
            now >= Date.parse(analysis.valid_until));
    const active = Boolean(
        market?.analysis_enabled && !stale && analysis?.status === "ready",
    );
    const signal = active && analysis ? analysis.signal : "WAIT";
    let notice: string | null = null;

    if (!market) {
        notice = "Không có cặp giao dịch khả dụng để phân tích.";
    } else if (
        market.analysis_unavailable_reason === "gold_history_unavailable"
    ) {
        notice =
            "Hiện chỉ có giá vàng tham chiếu. Chưa có lịch sử nến vàng đã xác minh để tính chỉ báo và phân tích Jev.";
    } else if (!market.analysis_enabled) {
        notice = "Phân tích Jev đang tắt.";
    } else if (!analysis) {
        notice = "Đang chờ lần phân tích Jev đầu tiên.";
    } else if (analysis.status !== "ready") {
        notice =
            REASON_LABELS[analysis.reason ?? ""] ??
            "Chưa có kết quả phân tích khả dụng.";
    }

    return (
        <section className="market-analysis" aria-label="Phân tích Jev">
            <header className="market-analysis__header">
                <h3>
                    Phân tích Jev · {market?.symbol ?? "Chưa có thị trường"}
                </h3>
                <span>Chỉ báo 1 giờ</span>
            </header>
            {notice && (
                <p className="market-analysis__notice" role="status">
                    {notice}
                </p>
            )}
            {analysis && (
                <p className="market-analysis__time">
                    Lần đánh giá: {formatChartTime(analysis.analyzed_at)}{" "}
                    (giờ Việt Nam)
                    {stale && " · Đã hết hạn · chờ kết quả mới"}
                </p>
            )}
            {analysis?.status === "ready" && (
                <>
                    <p className="market-analysis__signal" data-signal={signal}>
                        {!active
                            ? "Kết quả cũ · chờ đánh giá mới"
                            : SIGNAL_LABELS[signal]}
                    </p>
                    {active && (
                        <p className="market-analysis__explanation">
                            {SIGNAL_EXPLANATIONS[signal]}
                        </p>
                    )}
                    <dl className="market-analysis__answers">
                        {Object.entries(analysis.answers).map(
                            ([name, answer]) =>
                                answer && (
                                    <div key={name}>
                                        <dt>
                                            {ANSWER_NAMES[name]} ·{" "}
                                            {CHOICE_LABELS[answer.choice]}
                                        </dt>
                                        <dd>
                                            {ANSWER_EXPLANATIONS[answer.choice]}
                                        </dd>
                                        <dd className="market-analysis__confidence">
                                            Độ tin cậy mô hình:{" "}
                                            {Math.round(
                                                answer.confidence * 100,
                                            )}
                                            %
                                        </dd>
                                    </div>
                                ),
                        )}
                    </dl>
                </>
            )}
            {analysis?.features.rsi14 !== undefined && (
                <details className="market-analysis__indicators">
                    <summary>
                        Chỉ báo kỹ thuật{" "}
                        <span>{market?.quote_asset} · 1 giờ</span>
                    </summary>
                    <dl className="market-analysis__features">
                        {INDICATORS.map(({ key, name, description }) => (
                            <div key={key}>
                                <dt>{name}</dt>
                                <dd
                                    className="market-analysis__value"
                                    title={analysis.features[key] ?? undefined}
                                >
                                    {formatIndicator(analysis.features[key])}
                                </dd>
                                <dd>{description}</dd>
                            </div>
                        ))}
                    </dl>
                </details>
            )}
            {analysis?.features.last_close_time && (
                <p className="market-analysis__time">
                    Nến nguồn đóng lúc{" "}
                    {formatChartTime(analysis.features.last_close_time)} (giờ
                    Việt Nam)
                    {analysis.model && ` · mô hình ${analysis.model}`}
                </p>
            )}
            <p className="market-analysis__caption">
                Chỉ phục vụ nghiên cứu · độ tin cậy mô hình không phải xác suất
                có lãi.
            </p>
        </section>
    );
}
