import type { Market } from "@/lib/api/types";
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
            {analysis?.model && (
                <p className="market-analysis__time">
                    Mô hình {analysis.model}
                    {analysis.features.last_close_time &&
                        ` · nến nguồn ${formatChartTime(analysis.features.last_close_time)} (giờ Việt Nam)`}
                </p>
            )}
            <p className="market-analysis__caption">
                Chỉ phục vụ nghiên cứu · độ tin cậy mô hình không phải xác suất
                có lãi. Chỉ báo số nằm dưới biểu đồ.
            </p>
        </section>
    );
}
