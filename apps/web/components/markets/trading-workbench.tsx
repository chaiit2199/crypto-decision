"use client";

import { useEffect, useState } from "react";

import type { Market } from "@/lib/api/types";
import type { TradingResult, TradingStyle, WorkbenchData } from "@/lib/api/trading-types";
import {
    SIMULATION_KIND_LABELS,
    TRADING_STYLE_LABELS,
} from "@/lib/markets/trading-labels";
import { stanceSyncNote } from "@/lib/markets/research-sync";
import type { ResearchStance, ResolvedStance } from "@/lib/markets/indicator-readings";

import { OrderBookPanel } from "./order-book-panel";
import { TradeSetupPanel } from "./trade-setup-panel";
import { WorkbenchIndicators } from "./workbench-indicators";

type TradingWorkbenchProps = {
    market: Market;
    now: number;
    refreshVersion: number;
    style: TradingStyle;
    onStyleChange: (style: TradingStyle) => void;
    researchStance: ResearchStance;
    resolvedStance: ResolvedStance;
};

export function TradingWorkbench({
    market,
    now,
    refreshVersion,
    style,
    onStyleChange,
    researchStance,
    resolvedStance,
}: TradingWorkbenchProps) {
    const [data, setData] = useState<WorkbenchData | null>(null);
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        const controller = new AbortController();
        let timer: ReturnType<typeof setTimeout>;
        async function refresh() {
            try {
                const query = new URLSearchParams({
                    symbol: market.symbol,
                    exchange: market.exchange,
                    style,
                });
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

    const current =
        data?.style === style &&
        data.symbol === market.symbol &&
        data.exchange === market.exchange
            ? data
            : null;
    const expired = Boolean(current && now >= Date.parse(current.valid_until));

    return (
        <section className="trading-workbench" aria-label="Nghiên cứu cơ hội giao dịch">
            <header className="trading-workbench__header">
                <div>
                    <h2>Bàn nghiên cứu lệnh</h2>
                    <p>
                        {market.exchange.toUpperCase()} · {market.symbol} ·{" "}
                        {market.quote_asset} · giao ngay · không đặt lệnh thật
                    </p>
                </div>
                <label>
                    <span>Khung thời gian nghiên cứu</span>
                    <select
                        value={style}
                        onChange={(event) =>
                            onStyleChange(event.target.value as TradingStyle)
                        }
                    >
                        {Object.entries(TRADING_STYLE_LABELS).map(([value, label]) => (
                            <option key={value} value={value}>{label}</option>
                        ))}
                    </select>
                </label>
            </header>

            <p className="trading-workbench__stance" role="status">
                {stanceSyncNote(
                    researchStance,
                    resolvedStance,
                    market.analysis?.status === "ready" &&
                        market.analysis.freshness === "fresh" &&
                        now < Date.parse(market.analysis.valid_until)
                        ? market.analysis.signal
                        : null,
                    current?.market_regime,
                )}
            </p>

            {error && <p role="alert">{error}</p>}
            {!current && !error && (
                <p role="status">Đang kiểm tra dữ liệu, mẫu hình và chi phí…</p>
            )}

            {current && (
                <div className="trading-workbench__desk">
                    <TradeSetupPanel
                        report={current}
                        quoteAsset={market.quote_asset}
                        expired={expired}
                    />
                    <OrderBookPanel
                        liquidity={current.liquidity}
                        quoteAsset={market.quote_asset}
                    />
                </div>
            )}

            {current && (
                <details className="trading-workbench__diagnostics">
                    <summary>Chỉ báo theo khung giờ và lịch sử mô phỏng</summary>
                    <WorkbenchIndicators report={current} unavailable={Boolean(error)} />
                    {current.simulations.length > 0 && (
                        <div>
                            <h3>Mô phỏng đã lưu</h3>
                            {current.simulations.map((simulation) => (
                                <p key={simulation.id}>
                                    #{simulation.id} ·{" "}
                                    {SIMULATION_KIND_LABELS[simulation.kind] ??
                                        simulation.kind}
                                    {simulation.trade_count !== null &&
                                        ` · ${simulation.trade_count} lệnh`}
                                </p>
                            ))}
                            <p>
                                Kết quả mô phỏng không xác nhận mẫu hình hiện
                                tại.
                            </p>
                        </div>
                    )}
                    {current.knowledge_matches.length > 0 && (
                        <p>
                            Quy tắc kiến thức:{" "}
                            {
                                current.knowledge_matches.filter(
                                    (match) => match.matched,
                                ).length
                            }
                            {" / "}
                            {current.knowledge_matches.length} khớp khung giờ ·
                            chưa phải bằng chứng lãi.
                        </p>
                    )}
                </details>
            )}
        </section>
    );
}
