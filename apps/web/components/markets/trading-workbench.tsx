"use client";

import { useEffect, useState } from "react";

import type { Market } from "@/lib/api/types";
import type { TradingResult, TradingStyle, WorkbenchData } from "@/lib/api/trading-types";
import { formatIndicator, formatTime } from "@/lib/format/market";
import { REGIME_LABELS, RISK_FLAG_LABELS, TRADING_STYLE_LABELS } from "@/lib/markets/trading-labels";

import { PlanSummary, TradePlanner } from "./trade-planner";

type TradingWorkbenchProps = { market: Market; now: number; refreshVersion: number };

const FEATURES = [
    { key: "ema9", name: "EMA9", description: "Trung bình hàm mũ 9 nến, phản ứng nhanh với thay đổi giá." },
    { key: "ema21", name: "EMA21", description: "Trung bình hàm mũ 21 nến, dùng đối chiếu xu hướng với EMA9." },
    { key: "rsi14", name: "RSI14", description: "Động lượng 14 nến trên thang 0–100; không bảo đảm đảo chiều." },
    { key: "atr_percent", name: "ATR (%)", description: "ATR14 chia giá đóng cửa, giúp so sánh biên độ giữa các tài sản." },
    { key: "vwap", name: "VWAP phiên UTC", description: "Tổng khối lượng định giá chia khối lượng gốc từ 00:00 UTC; thiếu nến thì không tính." },
    { key: "support", name: "Hỗ trợ 20 nến", description: "Đáy thấp nhất của 20 nến trước, không gồm nến tín hiệu." },
    { key: "resistance", name: "Kháng cự 20 nến", description: "Đỉnh cao nhất của 20 nến trước, không gồm nến tín hiệu." },
    { key: "relative_volume20", name: "Khối lượng tương đối", description: "Khối lượng nến cuối chia trung bình 20 nến trước; trên 1 là cao hơn trung bình." },
    { key: "volume_delta", name: "Volume Delta", description: "Mua chủ động trừ bán chủ động theo tài sản gốc, suy ra từ khối lượng taker." },
] as const;

export function TradingWorkbench({ market, now, refreshVersion }: TradingWorkbenchProps) {
    const [style, setStyle] = useState<TradingStyle>("intraday");
    const [data, setData] = useState<WorkbenchData | null>(null);
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        const controller = new AbortController();
        let timer: ReturnType<typeof setTimeout>;
        async function refresh() {
            try {
                const query = new URLSearchParams({ symbol: market.symbol, exchange: market.exchange, style });
                const response = await fetch(`/api/trading?${query}`, {
                    cache: "no-store",
                    signal: AbortSignal.any([controller.signal, AbortSignal.timeout(25_000)]),
                });
                const result = await response.json() as TradingResult<WorkbenchData>;
                if (controller.signal.aborted) {
                    return;
                }
                if (result.ok) {
                    setData(result.data);
                    setError(null);
                } else {
                    setError(result.message);
                }
            } catch {
                if (!controller.signal.aborted) {
                    setError("Không tải được báo cáo nghiên cứu. Hệ thống sẽ thử lại.");
                }
            }
            if (!controller.signal.aborted) {
                timer = setTimeout(refresh, 30_000);
            }
        }
        timer = setTimeout(refresh, 0);
        return () => {
            clearTimeout(timer);
            controller.abort();
        };
    }, [market.symbol, market.exchange, style, refreshVersion]);

    const current = data?.style === style && data.symbol === market.symbol && data.exchange === market.exchange ? data : null;
    const expired = current && now >= Date.parse(current.valid_until);

    return (
        <section className="trading-workbench" aria-label="Nghiên cứu cơ hội giao dịch">
            <header className="trading-workbench__header">
                <div>
                    <h2>Kế hoạch & điều kiện giao dịch</h2>
                    <p>{market.exchange.toUpperCase()} · {market.symbol} · Spot · {market.quote_asset}</p>
                </div>
                <label>
                    <span>Phong cách nghiên cứu</span>
                    <select value={style} onChange={(event) => setStyle(event.target.value as TradingStyle)}>
                        {Object.entries(TRADING_STYLE_LABELS).map(([value, label]) => (
                            <option key={value} value={value}>{label}</option>
                        ))}
                    </select>
                </label>
            </header>
            {error && <p role="alert">{error}</p>}
            {!current && !error && <p role="status">Đang kiểm tra dữ liệu, setup và chi phí…</p>}
            {current && (
                <>
                    <p>
                        Xu hướng {current.timeframes.trend.toUpperCase()} · Setup {current.timeframes.setup.toUpperCase()}
                        {" · "}Entry {current.timeframes.entry.toUpperCase()} · Cập nhật {formatTime(current.as_of)} (UTC+7)
                    </p>
                    <p className="trading-workbench__status" role="status">
                        {expired || error ? "Dữ liệu đã cũ — chờ cập nhật" : "Chưa đủ điều kiện giao dịch"}
                        {" · "}{REGIME_LABELS[current.market_regime]} · {current.setup ?? "Chưa có setup"}
                    </p>
                    <p>
                        Jev: {current.ai_signal} · Dự báo biên độ / xác suất có lãi: chưa được hiệu chuẩn.
                    </p>
                    <ul className="trading-workbench__flags">
                        {current.risk_flags.map((flag) => <li key={flag}>{RISK_FLAG_LABELS[flag] ?? flag}</li>)}
                    </ul>
                    <h3>Spread & thanh khoản</h3>
                    <dl className="trading-workbench__metrics">
                        <div>
                            <dt>Bid / Ask</dt>
                            <dd>{formatIndicator(current.liquidity.bid)} / {formatIndicator(current.liquidity.ask)}</dd>
                            <dd>Giá mua/bán tốt nhất trong cùng ảnh chụp sổ lệnh.</dd>
                        </div>
                        <div>
                            <dt>Spread (%)</dt>
                            <dd>{formatIndicator(current.liquidity.spread_percent)}</dd>
                            <dd>Chênh lệch bid–ask chia giá giữa; một phần chi phí vào/thoát lệnh.</dd>
                        </div>
                        <div>
                            <dt>Độ sâu bid / ask · {market.quote_asset}</dt>
                            <dd>{formatIndicator(current.liquidity.bid_depth)} / {formatIndicator(current.liquidity.ask_depth)}</dd>
                            <dd>Tổng giá trị tối đa 100 mức mỗi bên; không phải toàn bộ sổ lệnh.</dd>
                        </div>
                        <div>
                            <dt>Mất cân bằng sổ lệnh</dt>
                            <dd>{formatIndicator(current.liquidity.imbalance)}</dd>
                            <dd>(Bid − Ask) / (Bid + Ask) theo giá trị; có thể thay đổi nhanh khi lệnh bị hủy.</dd>
                        </div>
                    </dl>
                    {Object.entries(current.frames).map(([timeframe, frame]) => (
                        <details key={timeframe} className="trading-workbench__frame">
                            <summary>Chỉ báo {timeframe.toUpperCase()} · {frame.status === "ready" ? "Đủ nến đã đóng" : "Thiếu dữ liệu"}</summary>
                            {frame.status !== "ready" && <p>Chưa đủ 300 nến liên tiếp đã đóng hoặc lịch sử chưa cập nhật.</p>}
                            {frame.status === "ready" && (
                                <dl className="trading-workbench__metrics">
                                    {FEATURES.map(({ key, name, description }) => (
                                        <div key={key}>
                                            <dt>{name}</dt>
                                            <dd>{formatIndicator(frame.features[key])}</dd>
                                            <dd>{description}</dd>
                                        </div>
                                    ))}
                                </dl>
                            )}
                        </details>
                    ))}
                    {current.plan && (
                        <details className="trading-workbench__frame">
                            <summary>Kịch bản ATR tham khảo · Chưa kiểm chứng</summary>
                            <p>
                                Vào {formatIndicator(current.plan.entry)} · SL {formatIndicator(current.plan.stop_loss)}
                                {" · "}TP {formatIndicator(current.plan.take_profit)} · {market.quote_asset}
                            </p>
                            <p>Dừng lỗ cách giá vào 1,5 ATR; chốt lời cách 3 ATR. Đây là quy tắc mô phỏng.</p>
                            <PlanSummary plan={current.plan} quoteAsset={market.quote_asset} />
                        </details>
                    )}
                    <details className="trading-workbench__frame">
                        <summary>Backtest & Paper Trading · Lịch sử mô phỏng</summary>
                        {current.simulations.length === 0 && <p>Chưa có lần mô phỏng được lưu cho thị trường này.</p>}
                        {current.simulations.map((simulation) => (
                            <p key={simulation.id}>
                                #{simulation.id} · {simulation.kind === "replay" ? "Replay" : "Paper"}
                                {" · "}{formatTime(simulation.created_at)} (UTC+7)
                                {simulation.trade_count !== null && ` · ${simulation.trade_count} lệnh`}
                                {simulation.event && ` · ${simulation.event}`}
                                {simulation.net_return_percent !== null && ` · ${formatIndicator(simulation.net_return_percent)}% sau phí`}
                                {simulation.net_pnl !== null && ` · P&L ${formatIndicator(simulation.net_pnl)} ${market.quote_asset}`}
                            </p>
                        ))}
                        <p>Kết quả mô phỏng không tự xác nhận hiệu quả của setup hiện tại.</p>
                    </details>
                    <p>
                        Trading Skills: {current.knowledge_matches.filter((match) => match.matched).length}
                        {" / "}{current.knowledge_matches.length} quy tắc đã nhập khớp dữ liệu 1H.
                        {" "}Khớp quy tắc chưa phải bằng chứng có lãi.
                    </p>
                </>
            )}
            <TradePlanner
                key={`${market.exchange}:${market.symbol}:${style}`}
                symbol={market.symbol}
                exchange={market.exchange}
                quoteAsset={market.quote_asset}
                suggestedPlan={!expired && !error ? current?.plan ?? null : null}
            />
        </section>
    );
}
