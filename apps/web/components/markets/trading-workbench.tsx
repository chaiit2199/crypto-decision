"use client";

import { useEffect, useState } from "react";

import type { Market } from "@/lib/api/types";
import type { TradingResult, TradingStyle, WorkbenchData } from "@/lib/api/trading-types";
import { formatIndicator, formatTime, priceStatus } from "@/lib/format/market";
import { REGIME_LABELS, RISK_FLAG_LABELS, TRADING_STYLE_LABELS } from "@/lib/markets/trading-labels";

import { PlanSummary, TradePlanner } from "./trade-planner";
import { WorkbenchIndicators } from "./workbench-indicators";

type TradingWorkbenchProps = { market: Market; now: number; refreshVersion: number };

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
    const expired = Boolean(current && now >= Date.parse(current.valid_until));
    let status = "Chưa đủ điều kiện giao dịch";
    if (error) {
        status = "Chưa cập nhật được báo cáo";
    } else if (current?.trade_eligibility === "NO_DATA") {
        status = "Chưa đủ dữ liệu đánh giá";
    } else if (expired) {
        status = "Dữ liệu đã cũ · chờ cập nhật";
    }

    return (
        <section className="trading-workbench" aria-label="Nghiên cứu cơ hội giao dịch">
            <header className="trading-workbench__header">
                <div>
                    <h2>Chỉ báo & mô phỏng</h2>
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
                    <p className="trading-workbench__status" role="status">{status}</p>
                    <WorkbenchIndicators report={current} unavailable={Boolean(error)} />
                </>
            )}
            <TradePlanner
                key={`${market.exchange}:${market.symbol}`}
                symbol={market.symbol}
                exchange={market.exchange}
                quoteAsset={market.quote_asset}
                currentPrice={priceStatus(market, now) === "fresh" ? market.latest_price?.price ?? null : null}
                suggestedPlan={!expired && !error ? current?.plan ?? null : null}
            />
            {current && (
                <details className="trading-workbench__diagnostics">
                    <summary>Điều kiện giao dịch & dữ liệu chi tiết</summary>
                    <p>
                        Xu hướng {current.timeframes.trend.toUpperCase()} · Setup {current.timeframes.setup.toUpperCase()}
                        {" · "}Entry {current.timeframes.entry.toUpperCase()} · Cập nhật {formatTime(current.as_of)} (UTC+7)
                    </p>
                    <p>{REGIME_LABELS[current.market_regime]} · {current.setup ?? "Chưa có setup"}</p>
                    <p>Jev: {current.ai_signal} · Xác suất có lãi chưa được hiệu chuẩn.</p>
                    <ul className="trading-workbench__flags">
                        {current.risk_flags.map((flag) => <li key={flag}>{RISK_FLAG_LABELS[flag] ?? flag}</li>)}
                    </ul>
                    <h3>Spread & thanh khoản</h3>
                    {current.liquidity.status === "unsupported" && <p>Nguồn này chưa hỗ trợ sổ lệnh.</p>}
                    {current.liquidity.status === "missing" && <p>Chưa đồng bộ sổ lệnh.</p>}
                    {current.liquidity.status === "stale" && <p>Sổ lệnh đã cũ; số liệu chỉ để tham khảo.</p>}
                    {["fresh", "stale"].includes(current.liquidity.status) && (
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
                    )}
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
                    {current.knowledge_matches.length > 0 && (
                        <p>
                            Trading Skills: {current.knowledge_matches.filter((match) => match.matched).length}
                            {" / "}{current.knowledge_matches.length} quy tắc khớp dữ liệu 1H.
                            {" "}Khớp quy tắc chưa phải bằng chứng có lãi.
                        </p>
                    )}
                </details>
            )}
        </section>
    );
}
