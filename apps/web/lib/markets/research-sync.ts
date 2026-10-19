import type { Timeframe } from "@/lib/api/types";
import type { TradingStyle } from "@/lib/api/trading-types";

/** Chart timeframe that matches the research holding horizon. */
export function chartTimeframeForStyle(
    style: TradingStyle,
    exchange: string,
): Timeframe {
    if (style === "scalping") {
        return exchange === "binance" ? "5m" : "1h";
    }
    if (style === "swing") {
        return "4h";
    }
    return "1h";
}

export function styleForChartTimeframe(timeframe: Timeframe): TradingStyle {
    if (timeframe === "5m" || timeframe === "15m") {
        return "scalping";
    }
    if (timeframe === "4h" || timeframe === "1d") {
        return "swing";
    }
    return "intraday";
}
