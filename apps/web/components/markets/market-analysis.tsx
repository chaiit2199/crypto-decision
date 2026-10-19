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
    SCALP: "Scalp · Vài phút",
    INTRADAY: "Intraday · Trong ngày",
    SWING: "Swing · Nhiều ngày",
    UNSUITABLE: "Chưa phù hợp giữ lệnh",
};

const SIGNAL_LABELS = {
    BUY: "Cơ hội mua",
    SELL: "Cơ hội bán",
    WAIT: "Chờ tín hiệu rõ hơn",
    NO_DATA: "Chưa đủ dữ liệu",
};

const ANSWER_NAMES: Record<string, string> = {
    trend: "Xu hướng",
    momentum: "Động lượng",
    volatility: "Biến động",
    holding_horizon: "Khung giữ (nghiên cứu)",
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
        name: "MACD Signal (9)",
        description:
            "Đường trung bình hàm mũ 9 kỳ của MACD, dùng làm mốc so sánh để nhận biết thay đổi động lượng.",
    },
    {
        key: "macd_histogram",
        name: "MACD Histogram",
        description:
            "MACD trừ đường Signal; dương khi MACD nằm trên Signal, âm khi nằm dưới.",
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
        "Jev từ chối API key (401). Cần cập nhật key ở backend.",
    access_denied: "Tài khoản chưa có quyền truy cập Jev.",
    quota_exhausted: "Tài khoản Jev đã hết quota hoặc cần kiểm tra billing.",
    missing_api_key:
        "Lần phân tích trước chưa có API key Jev; chờ kết quả mới sau khi cập nhật cấu hình.",
    rate_limited:
        "Jev đang giới hạn lượt gọi; hệ thống tạm dừng và sẽ thử lại.",
    upstream_unavailable: "Jev tạm thời không sẵn sàng.",
    transport_error: "Không kết nối được Jev; hệ thống sẽ thử ở kỳ tiếp theo.",
    request_rejected:
        "Jev không chấp nhận request; cần kiểm tra model và cấu hình backend.",
    invalid_response:
        "Phản hồi Jev không đúng định dạng; chưa thể dùng để phân tích.",
    insufficient_candles: "Cần ít nhất 300 nến 1H đã đóng để tính chỉ báo.",
    candle_gap: "Lịch sử nến có khoảng trống; đang chờ đồng bộ.",
    stale_candles: "Lịch sử nến chưa cập nhật đến giờ gần nhất.",
    invalid_candles: "Nến chưa đủ điều kiện chất lượng để phân tích.",
    stale_price: "Snapshot giá đã cũ; chưa gọi Jev.",
    stale_stats: "Thống kê 24h đã cũ; chưa gọi Jev.",
    missing_snapshots: "Chưa có đủ giá và thống kê 24h.",
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
                <span>Chỉ báo 1H</span>
            </header>
            {notice && (
                <p className="market-analysis__notice" role="status">
                    {notice}
                </p>
            )}
            {analysis && (
                <p className="market-analysis__time">
                    Lần đánh giá: {formatChartTime(analysis.analyzed_at)}{" "}
                    (UTC+7)
                    {stale && " · Đã hết hạn - chờ kết quả mới"}
                </p>
            )}
            {analysis?.status === "ready" && (
                <>
                    <p className="market-analysis__signal" data-signal={signal}>
                        {!active
                            ? "WAIT · Kết quả cũ, chờ đánh giá mới"
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
                                            Mức tự tin phân loại của mô hình:{" "}
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
                        Chỉ báo kỹ thuật <span>{market?.quote_asset} · 1H</span>
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
                    {formatChartTime(analysis.features.last_close_time)} (UTC+7)
                    {analysis.model && ` · Model ${analysis.model}`}
                </p>
            )}
            <p className="market-analysis__caption">
                Tín hiệu nghiên cứu, chưa kiểm chứng bằng backtest. Độ tin cậy
                mô hình không phải xác suất có lãi.
            </p>
        </section>
    );
}
