"use client";

import { useEffect, useState } from "react";

import { refreshMarketCandles } from "@/lib/api/monitor-client";
import type { CandlesData, Timeframe } from "@/lib/api/types";
import { formatDecimal } from "@/lib/format/market";
import { formatChartTime } from "@/lib/format/chart-time";

import { CandleChart } from "./candle-chart";

type MarketHistoryProps = {
    symbol: string;
    exchange: string;
    timeframe: Timeframe;
    snapshotPrice: string | undefined;
    refreshIntervalMs: number;
    refreshVersion: number;
};

export function MarketHistory({
    symbol,
    exchange,
    timeframe,
    snapshotPrice,
    refreshIntervalMs,
    refreshVersion,
}: MarketHistoryProps) {
    const [data, setData] = useState<CandlesData | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [retry, setRetry] = useState(0);

    useEffect(() => {
        const controller = new AbortController();
        let timer: ReturnType<typeof setTimeout>;

        async function refresh() {
            const result = await refreshMarketCandles(symbol, exchange, timeframe, controller.signal);

            if (controller.signal.aborted) {
                return;
            }

            if (result.ok) {
                setData(result.data);
                setError(null);
            } else {
                setError(result.message);
            }

            timer = setTimeout(refresh, refreshIntervalMs);
        }

        timer = setTimeout(refresh, 0);
        return () => {
            clearTimeout(timer);
            controller.abort();
        };
    }, [symbol, exchange, timeframe, retry, refreshIntervalMs, refreshVersion]);

    function handleRetry() {
        setError(null);
        setRetry((value) => value + 1);
    }

    const lastCandle = data?.data.at(-1);

    return (
        <div className="market-chart" aria-busy={!data && !error}>
            {error && (
                <p className="market-chart__notice" role="alert">
                    {error} {data && "Đang giữ biểu đồ của lần tải thành công trước."}
                    <button type="button" onClick={handleRetry}>
                        Thử lại
                    </button>
                </p>
            )}
            {!data && !error && (
                <p className="market-chart__empty" role="status">
                    Đang tải lịch sử giá…
                </p>
            )}
            {data && data.data.length === 0 && (
                <p className="market-chart__empty">Chưa có nến đã đóng trong khoảng này. Lịch sử đang được đồng bộ.</p>
            )}
            {data && data.data.length > 0 && (
                <>
                    <div className="market-chart__summary">
                        <span>
                            Nến gần nhất ·{" "}
                            {lastCandle &&
                                formatChartTime(lastCandle.open_time)}{" "}
                            (giờ Việt Nam)
                        </span>
                        <span>O {formatDecimal(lastCandle?.open)}</span>
                        <span>H {formatDecimal(lastCandle?.high)}</span>
                        <span>L {formatDecimal(lastCandle?.low)}</span>
                        <span>C {formatDecimal(lastCandle?.close)}</span>
                    </div>
                    <CandleChart candles={data.data} symbol={symbol} snapshotPrice={snapshotPrice} />
                    <p className="market-chart__caption">
                        {data.data.length} nến đã đóng · khối lượng theo tài sản
                        gốc · giờ Việt Nam
                        {data.meta.freshness.status === "stale" && " · Lịch sử chưa cập nhật đến hiện tại"}
                    </p>
                </>
            )}
            <p className="market-chart__attribution">
                Chart:{" "}
                <a href="https://www.tradingview.com/" target="_blank" rel="noreferrer">
                    TradingView Lightweight Charts™
                </a>
            </p>
        </div>
    );
}
