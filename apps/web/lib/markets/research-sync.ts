import type { Timeframe } from "@/lib/api/types";
import type { TradingStyle } from "@/lib/api/trading-types";
import type { MarketAnalysisData } from "@/lib/api/types";
import type { ResearchStance, ResolvedStance } from "@/lib/markets/indicator-readings";

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

export function stanceSyncNote(
    stance: ResearchStance,
    resolved: ResolvedStance,
    jevSignal: MarketAnalysisData["signal"] | null | undefined,
    regime: string | null | undefined,
): string {
    const jevSide =
        jevSignal === "BUY" ? "long" : jevSignal === "SELL" ? "short" : "neutral";
    const regimeSide =
        regime === "BULLISH" ? "long" : regime === "BEARISH" ? "short" : "neutral";

    if (stance === "auto") {
        if (resolved === "neutral") {
            return "Hướng theo thời gian: đang chờ Jev hoặc điều kiện đủ rõ (Long/Short).";
        }
        if (regimeSide !== "neutral" && regimeSide !== resolved) {
            return `Đang theo Jev (${resolved === "long" ? "Long" : "Short"}) · phiếu lệnh EMA khung lớn đang ${regimeSide === "long" ? "nghiêng tăng" : "nghiêng giảm"} — chưa đồng bộ hoàn toàn.`;
        }
        return `Đang theo Jev theo khung giờ đã chọn: ${resolved === "long" ? "Long / giữ mua" : "Short / giảm vị thế"}.`;
    }

    if (jevSide !== "neutral" && jevSide !== resolved) {
        return `Bạn chọn ${resolved === "long" ? "Long" : "Short"} thủ công · Jev đang ${jevSide === "long" ? "Long" : "Short"} — diễn giải chỉ báo theo lựa chọn của bạn.`;
    }
    return `Bạn chọn ${resolved === "long" ? "Long / giữ mua" : "Short / giảm vị thế"} · chỉ báo bên dưới diễn giải theo hướng này.`;
}
