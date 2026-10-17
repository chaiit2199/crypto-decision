import type { Market } from "@/lib/api/types";
import { formatIndicator } from "@/lib/format/market";
import { formatChartTime } from "@/lib/format/chart-time";

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
};

const SIGNAL_LABELS = {
    BUY: "BUY · Theo dõi cơ hội mua",
    SELL: "SELL · Theo dõi áp lực bán",
    WAIT: "WAIT · Chờ tín hiệu rõ hơn",
    NO_DATA: "NO_DATA · Chưa đủ dữ liệu",
};

const REASON_LABELS: Record<string, string> = {
    authentication_failed: "Jev từ chối API key (401). Cần cập nhật key ở backend.",
    access_denied: "Tài khoản chưa có quyền truy cập Jev.",
    quota_exhausted: "Tài khoản Jev đã hết quota hoặc cần kiểm tra billing.",
    missing_api_key: "Backend chưa cấu hình API key Jev.",
    rate_limited: "Jev đang giới hạn lượt gọi; hệ thống tạm dừng và sẽ thử lại.",
    upstream_unavailable: "Jev tạm thời không sẵn sàng.",
    transport_error: "Không kết nối được Jev; hệ thống sẽ thử ở kỳ tiếp theo.",
    request_rejected: "Jev không chấp nhận request; cần kiểm tra model và cấu hình backend.",
    invalid_response: "Phản hồi Jev không đúng định dạng; chưa thể dùng để phân tích.",
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
    const stale = analysis && (analysis.freshness === "stale" || now >= Date.parse(analysis.valid_until));
    let notice: string | null = null;

    if (!market) {
        notice = "Không có cặp Spot USDT khả dụng để phân tích.";
    } else if (!market.analysis_enabled) {
        notice = "Phân tích Jev đang tắt.";
    } else if (!analysis) {
        notice = "Đang chờ lần phân tích Jev đầu tiên; lịch chạy mỗi 5 phút.";
    } else if (analysis.status !== "ready") {
        notice = REASON_LABELS[analysis.reason ?? ""] ?? "Chưa có kết quả phân tích khả dụng.";
    }

    return (
        <section className="market-analysis" aria-label="Phân tích Jev">
            <header className="market-analysis__header">
                <h3>Phân tích Jev · {market?.symbol ?? "Chưa có thị trường"}</h3>
                <span>Mỗi 5 phút · Chỉ báo 1H</span>
            </header>
            {notice && <p className="market-analysis__notice" role="status">{notice}</p>}
            {analysis && (
                <p className="market-analysis__time">
                    Lần đánh giá: {formatChartTime(analysis.analyzed_at)} (UTC+7)
                    {stale && " · Đã hết hạn — chờ kết quả mới"}
                </p>
            )}
            {analysis?.status === "ready" && (
                <>
                    <p className="market-analysis__signal" data-signal={stale || !market?.analysis_enabled ? "WAIT" : analysis.signal}>
                        {stale || !market?.analysis_enabled ? "Kết quả cũ · " : ""}
                        {SIGNAL_LABELS[analysis.signal]}
                    </p>
                    <dl className="market-analysis__answers">
                        {Object.entries(analysis.answers).map(([name, answer]) => answer && (
                            <div key={name}>
                                <dt>{CHOICE_LABELS[answer.choice]}</dt>
                                <dd>Độ tin cậy mô hình: {Math.round(answer.confidence * 100)}%</dd>
                            </div>
                        ))}
                    </dl>
                </>
            )}
            {analysis?.features.rsi14 !== undefined && (
                <dl className="market-analysis__features">
                    <div>
                        <dt>EMA20 · USDT</dt>
                        <dd title={analysis.features.ema20}>{formatIndicator(analysis.features.ema20)}</dd>
                    </div>
                    <div>
                        <dt>EMA50 · USDT</dt>
                        <dd title={analysis.features.ema50}>{formatIndicator(analysis.features.ema50)}</dd>
                    </div>
                    <div>
                        <dt>RSI14</dt>
                        <dd title={analysis.features.rsi14}>{formatIndicator(analysis.features.rsi14)}</dd>
                    </div>
                </dl>
            )}
            {analysis?.features.last_close_time && (
                <p className="market-analysis__time">
                    Nến nguồn đóng lúc {formatChartTime(analysis.features.last_close_time)} (UTC+7)
                    {analysis.model && ` · Model ${analysis.model}`}
                </p>
            )}
            <p className="market-analysis__caption">
                Tín hiệu nghiên cứu, chưa kiểm chứng bằng backtest. Độ tin cậy mô hình không phải xác suất có lãi.
                SELL thể hiện áp lực bán, không phải lệnh mở short. Ứng dụng không đặt lệnh.
            </p>
        </section>
    );
}
