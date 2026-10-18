import type { CandlesResult, MarketMonitorResult, Timeframe } from "./types";

export async function refreshMarketMonitor(signal: AbortSignal): Promise<MarketMonitorResult> {
    try {
        const response = await fetch("/api/market-monitor", {
            cache: "no-store",
            signal: AbortSignal.any([signal, AbortSignal.timeout(10_000)]),
        });
        // This same-origin route returns the already validated application contract.
        return (await response.json()) as MarketMonitorResult;
    } catch {
        return {
            checked_at: Date.now(),
            ok: false,
            message: "Mất kết nối. Dữ liệu đang hiển thị là lần nhận gần nhất.",
        };
    }
}

export async function refreshMarketCandles(
    symbol: string,
    exchange: string,
    timeframe: Timeframe,
    signal: AbortSignal,
): Promise<CandlesResult> {
    const query = new URLSearchParams({ symbol, exchange, timeframe });

    try {
        const response = await fetch(`/api/market-candles?${query}`, {
            cache: "no-store",
            signal: AbortSignal.any([signal, AbortSignal.timeout(10_000)]),
        });
        return (await response.json()) as CandlesResult;
    } catch {
        return { ok: false, message: "Mất kết nối lịch sử giá. Trang sẽ tự thử lại." };
    }
}
