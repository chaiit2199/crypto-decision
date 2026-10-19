"use client";

import { useState } from "react";

import type { WorkbenchData } from "@/lib/api/trading-types";
import { formatIndicator, formatTime } from "@/lib/format/market";

type WorkbenchIndicatorsProps = {
    report: WorkbenchData;
    unavailable: boolean;
};

type IndicatorFrame = WorkbenchData["frames"][string];

const MAIN_INDICATORS = [
    { key: "ema9", name: "EMA9", description: "Giá trung bình có trọng số của 9 nến, nhạy với biến động gần đây." },
    { key: "ema21", name: "EMA21", description: "Giá trung bình có trọng số của 21 nến, dùng so sánh với EMA9." },
    { key: "rsi14", name: "RSI14", description: "Động lượng 14 nến trên thang 0–100; không bảo đảm đảo chiều." },
    { key: "atr_percent", name: "ATR (%)", description: "Biên độ biến động trung bình 14 nến tính theo phần trăm giá đóng cửa." },
    { key: "support", name: "Hỗ trợ", description: "Đáy thấp nhất của 20 nến trước, không gồm nến tín hiệu." },
    { key: "resistance", name: "Kháng cự", description: "Đỉnh cao nhất của 20 nến trước, không gồm nến tín hiệu." },
] as const;

const OTHER_INDICATORS = [
    { key: "ema20", name: "EMA20", description: "Giá trung bình có trọng số của 20 nến, theo dõi xu hướng ngắn hạn." },
    { key: "ema50", name: "EMA50", description: "Giá trung bình có trọng số của 50 nến, ít nhạy hơn EMA20." },
    { key: "ema200", name: "EMA200", description: "Giá trung bình có trọng số của 200 nến, làm mốc xu hướng dài hơn." },
    { key: "macd", name: "MACD", description: "Chênh lệch EMA12 và EMA26, dùng quan sát động lượng giá." },
    { key: "macd_signal", name: "MACD Signal", description: "EMA9 của MACD, làm đường tham chiếu cho động lượng." },
    { key: "macd_histogram", name: "MACD Histogram", description: "MACD trừ Signal; dương khi MACD ở trên đường Signal." },
    { key: "atr14", name: "ATR14", description: "Biên độ biến động trung bình 14 nến, theo đơn vị giá của cặp." },
    { key: "adx14", name: "ADX14", description: "Sức mạnh xu hướng trên thang 0–100, không cho biết hướng tăng hay giảm." },
    { key: "relative_volume20", name: "Khối lượng tương đối", description: "Khối lượng nến cuối chia trung bình 20 nến trước; trên 1 là cao hơn trung bình." },
    { key: "vwap", name: "VWAP phiên UTC", description: "Giá bình quân theo khối lượng từ 00:00 UTC; cần đủ nến và khối lượng định giá." },
    { key: "volume_delta", name: "Volume Delta", description: "Khối lượng mua chủ động trừ bán chủ động; cần dữ liệu taker từ nguồn." },
] as const;

const FRAME_REASONS: Record<string, string> = {
    insufficient_candles: "Cần 300 nến liên tiếp đã đóng ở khung này. Lịch sử hiện chưa đủ.",
    candle_gap: "Lịch sử nến có khoảng trống. Cần đồng bộ bù để tính chỉ báo.",
    stale_candles: "Lịch sử nến chưa cập nhật đến kỳ đóng gần nhất.",
    invalid_candles: "Dữ liệu nến chưa đạt kiểm tra chất lượng để tính chỉ báo.",
};

function IndicatorValues({ frame, expanded = false }: { frame: IndicatorFrame; expanded?: boolean }) {
    const indicators = expanded ? OTHER_INDICATORS : MAIN_INDICATORS;

    return (
        <dl className="trading-workbench__metrics">
            {indicators.map(({ key, name, description }) => (
                <div key={key}>
                    <dt>{name}</dt>
                    <dd title={frame.features[key] ?? undefined}>
                        {frame.features[key] == null ? "Chưa có dữ liệu" : formatIndicator(frame.features[key])}
                    </dd>
                    <dd>{description}</dd>
                </div>
            ))}
        </dl>
    );
}

export function WorkbenchIndicators({ report, unavailable }: WorkbenchIndicatorsProps) {
    const [selectedFrame, setSelectedFrame] = useState<string | null>(null);
    const frames = Object.entries(report.frames);
    const defaultFrame = frames.find(([, frame]) => frame.status === "ready")?.[0] ?? frames[0]?.[0];
    const timeframe = selectedFrame && report.frames[selectedFrame] ? selectedFrame : defaultFrame;
    const frame = timeframe ? report.frames[timeframe] : undefined;
    const referenceOnly = timeframe && !Object.values(report.timeframes).includes(timeframe);
    const unsupported = report.exchange === "coinbase" && ["5m", "15m"].includes(timeframe ?? "");

    return (
        <section className="workbench-indicators" aria-label="Chỉ báo kỹ thuật theo khung">
            <header className="trading-workbench__header">
                <div>
                    <h3>Chỉ báo kỹ thuật</h3>
                    <p>{report.symbol} · {report.quote_asset} · Tính từ nến đã đóng, độc lập với Jev.</p>
                </div>
                {timeframe && (
                    <label>
                        <span>Khung chỉ báo</span>
                        <select value={timeframe} onChange={(event) => setSelectedFrame(event.target.value)}>
                            {frames.map(([name, value]) => (
                                <option key={name} value={name}>
                                    {name.toUpperCase()} · {value.status === "ready" ? "Có dữ liệu" : "Chưa có dữ liệu"}
                                </option>
                            ))}
                        </select>
                    </label>
                )}
            </header>
            {report.exchange === "coinbase" && (
                <p>Coinbase hiện chỉ đồng bộ nến 1H; chỉ báo 5M/15M chưa được hỗ trợ.</p>
            )}
            {unavailable && <p role="status">Báo cáo chưa cập nhật; các giá trị dưới đây là lần tính trước.</p>}
            {referenceOnly && <p>Khung {timeframe.toUpperCase()} để tham khảo, chưa đủ đánh giá phong cách đang chọn.</p>}
            {!frame && <p role="status">Chưa nhận được dữ liệu chỉ báo cho thị trường này.</p>}
            {frame && frame.status !== "ready" && (
                <p className="trading-workbench__status" role="status">
                    {unsupported
                        ? "Chưa có bộ đồng bộ nến Coinbase cho khung này. Chọn 1H để xem dữ liệu hiện có."
                        : FRAME_REASONS[frame.reason ?? ""] ?? "Chưa đủ nến hợp lệ để tính chỉ báo ở khung này."}
                </p>
            )}
            {frame?.status === "ready" && (
                <>
                    <IndicatorValues frame={frame} />
                    <details className="trading-workbench__frame">
                        <summary>Xem thêm chỉ báo xu hướng & khối lượng</summary>
                        <IndicatorValues frame={frame} expanded />
                    </details>
                    {frame.features.last_close_time && (
                        <p>Nến nguồn {timeframe?.toUpperCase()} đóng lúc {formatTime(frame.features.last_close_time)} (UTC+7).</p>
                    )}
                </>
            )}
        </section>
    );
}
