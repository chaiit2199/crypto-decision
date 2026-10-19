"use client";

import { useEffect, useState } from "react";

import type { TradingResult, TradingStyle, WorkbenchData } from "@/lib/api/trading-types";
import { formatIndicator } from "@/lib/format/market";
import {
    ELIGIBILITY_LABELS,
    REGIME_LABELS,
    RISK_FLAG_LABELS,
    TRADING_STYLE_LABELS,
} from "@/lib/markets/trading-labels";

type OpportunityScannerProps = { exchange: string; now: number; refreshVersion: number };

export function OpportunityScanner({ exchange, now, refreshVersion }: OpportunityScannerProps) {
    const [style, setStyle] = useState<TradingStyle>("intraday");
    const [rows, setRows] = useState<WorkbenchData[] | null>(null);
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        const controller = new AbortController();
        let timer: ReturnType<typeof setTimeout>;
        async function refresh() {
            try {
                const query = new URLSearchParams({ exchange, style, view: "scanner" });
                const response = await fetch(`/api/trading?${query}`, {
                    cache: "no-store",
                    signal: AbortSignal.any([controller.signal, AbortSignal.timeout(25_000)]),
                });
                const result = await response.json() as TradingResult<WorkbenchData[]>;
                if (controller.signal.aborted) {
                    return;
                }
                if (result.ok) {
                    setRows(result.data);
                    setError(null);
                } else {
                    setError(result.message);
                }
            } catch {
                if (!controller.signal.aborted) {
                    setError("Không tải được bảng quét. Hệ thống sẽ thử lại.");
                }
            }
            if (!controller.signal.aborted) {
                timer = setTimeout(refresh, 60_000);
            }
        }
        timer = setTimeout(refresh, 0);
        return () => {
            clearTimeout(timer);
            controller.abort();
        };
    }, [exchange, style, refreshVersion]);

    const currentRows = rows?.filter((row) => row.exchange === exchange && row.style === style);

    return (
        <section className="trading-workbench" aria-label="Bảng quét cơ hội nghiên cứu">
            <header className="trading-workbench__header">
                <div>
                    <h2>Trading Opportunity Scanner</h2>
                    <p>Xếp theo điều kiện kỹ thuật và R:R sau phí · {exchange.toUpperCase()} Spot</p>
                </div>
                <label>
                    <span>Phong cách quét</span>
                    <select value={style} onChange={(event) => setStyle(event.target.value as TradingStyle)}>
                        {Object.entries(TRADING_STYLE_LABELS).map(([value, label]) => (
                            <option key={value} value={value}>{label}</option>
                        ))}
                    </select>
                </label>
            </header>
            {error && <p role="alert">{error}</p>}
            {!rows && !error && <p role="status">Đang quét các thị trường đã đồng bộ…</p>}
            {currentRows?.length === 0 && <p>Chưa có thị trường khả dụng cho lựa chọn này.</p>}
            {currentRows && currentRows.length > 0 && (
                <div className="trading-workbench__table" tabIndex={0} aria-label="Bảng quét có thể cuộn ngang">
                    <table>
                        <thead>
                            <tr>
                                <th scope="col">Cặp</th>
                                <th scope="col">Setup</th>
                                <th scope="col">Xu hướng</th>
                                <th scope="col">Volume tương đối</th>
                                <th scope="col">R:R sau phí</th>
                                <th scope="col">Trạng thái / điều kiện còn thiếu</th>
                            </tr>
                        </thead>
                        <tbody>
                            {currentRows.map((row) => (
                                <tr key={`${row.exchange}:${row.symbol}`}>
                                    <th scope="row">{row.symbol}</th>
                                    <td>{row.setup ?? "—"}</td>
                                    <td>{REGIME_LABELS[row.market_regime]} · {row.timeframes.trend.toUpperCase()}</td>
                                    <td>{formatIndicator(row.frames[row.timeframes.entry]?.features.relative_volume20)}</td>
                                    <td>{row.plan ? `1 : ${formatIndicator(row.plan.risk_reward_ratio)}` : "Chưa tính"}</td>
                                    <td>
                                        <p>
                                            {error || now >= Date.parse(row.valid_until)
                                                ? "Dữ liệu cũ"
                                                : ELIGIBILITY_LABELS[row.trade_eligibility]}
                                        </p>
                                        <small>
                                            {(row.missing_requirements?.length
                                                ? row.missing_requirements
                                                : row.risk_flags
                                            ).map((flag) => RISK_FLAG_LABELS[flag] ?? flag).join(" · ")}
                                        </small>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}
        </section>
    );
}
