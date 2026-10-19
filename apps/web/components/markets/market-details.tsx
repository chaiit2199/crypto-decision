"use client";

import { useState } from "react";

import type { Asset, Timeframe } from "@/lib/api/types";
import type { TradingStyle } from "@/lib/api/trading-types";
import {
    formatDecimal,
    formatPercentage,
    formatTime,
    priceStatus,
} from "@/lib/format/market";
import { selectedMarket } from "@/lib/markets/selected-market";
import type { QuoteAsset } from "@/lib/markets/selected-market";
import {
    researchStanceLabel,
    resolveResearchStance,
    type ResearchStance,
} from "@/lib/markets/indicator-readings";
import {
    chartTimeframeForStyle,
    stanceSyncNote,
    styleForChartTimeframe,
} from "@/lib/markets/research-sync";

import { MarketHistory } from "./market-history";
import { MarketAnalysis } from "./market-analysis";
import { TechnicalIndicators } from "./technical-indicators";
import { TradingWorkbench } from "./trading-workbench";
import { PriceFlash } from "./price-flash";

type MarketDetailsProps = {
    asset: Asset;
    quoteAsset: QuoteAsset;
    now: number;
    refreshIntervalMs: number;
    refreshVersion: number;
};

const TIMEFRAMES: Timeframe[] = ["5m", "15m", "1h", "4h", "1d"];

const STANCE_OPTIONS: { value: ResearchStance; label: string }[] = [
    { value: "auto", label: "Tự động theo Jev" },
    { value: "long", label: "Long · mua / giữ" },
    { value: "short", label: "Short · bán / giảm" },
];

export function MarketDetails({
    asset,
    quoteAsset,
    now,
    refreshIntervalMs,
    refreshVersion,
}: MarketDetailsProps) {
    const [style, setStyle] = useState<TradingStyle>("intraday");
    const [timeframe, setTimeframe] = useState<Timeframe>("1h");
    const [stance, setStance] = useState<ResearchStance>("auto");
    const market = selectedMarket(asset, quoteAsset);
    const stats = market?.ticker_stats;
    const freshness = priceStatus(market, now);
    const statsStale =
        stats &&
        (now - Date.parse(stats.fetched_at) > 600_000 ||
            market.stats_freshness.status !== "fresh");

    const analysis = market?.analysis;
    const analysisActive =
        Boolean(market?.analysis_enabled) &&
        analysis?.status === "ready" &&
        analysis.freshness === "fresh" &&
        now < Date.parse(analysis.valid_until);
    const jevSignal = analysisActive ? analysis?.signal : null;
    const resolvedStance = resolveResearchStance(stance, jevSignal);

    function handleStyleChange(next: TradingStyle) {
        setStyle(next);
        if (market) {
            setTimeframe(chartTimeframeForStyle(next, market.exchange));
        }
    }

    function handleTimeframeChange(next: Timeframe) {
        setTimeframe(next);
        setStyle(styleForChartTimeframe(next));
    }

    return (
        <section
            id="market-details"
            className="market-details"
            aria-labelledby="market-details-title"
        >
            <header className="market-details__header">
                <div>
                    <p className="market-monitor__eyebrow">
                        THỊ TRƯỜNG
                        {market && ` · ${market.exchange.toUpperCase()}`}
                    </p>
                    <h2 id="market-details-title">
                        {asset.symbol} <span>{asset.name}</span>
                    </h2>
                    <p className="market-details__pair">
                        {market?.symbol ?? `Chưa có cặp ${quoteAsset} khả dụng`}
                    </p>
                </div>
                <div
                    className="market-details__quote"
                    data-freshness={freshness}
                >
                    <strong>
                        <PriceFlash value={market?.latest_price?.price} />
                    </strong>
                    <span> {quoteAsset}</span>
                    <p>
                        {formatTime(
                            market?.latest_price?.data_at ??
                                market?.latest_price?.fetched_at,
                        )}{" "}
                        · giờ Việt Nam
                        {freshness === "stale" && " · Dữ liệu giá cũ"}
                        {freshness === "missing" && " · Chưa có giá"}
                        {!asset.enabled && " · Tài sản đã tắt đồng bộ"}
                    </p>
                </div>
            </header>

            <div
                className="market-details__research-sync"
                role="group"
                aria-label="Đồng bộ hướng và khung thời gian nghiên cứu"
            >
                <label>
                    <span>Hướng nghiên cứu</span>
                    <select
                        value={stance}
                        onChange={(event) =>
                            setStance(event.target.value as ResearchStance)
                        }
                    >
                        {STANCE_OPTIONS.map((option) => (
                            <option key={option.value} value={option.value}>
                                {option.label}
                            </option>
                        ))}
                    </select>
                </label>
                <p>
                    {stanceSyncNote(stance, resolvedStance, jevSignal, null)}{" "}
                    Đổi khung biểu đồ hoặc “Khung thời gian nghiên cứu” sẽ khớp
                    horizon giữ lệnh (
                    <strong>{researchStanceLabel(resolvedStance)}</strong>).
                </p>
            </div>

            <dl className="market-details__stats">
                <div>
                    <dt>Thay đổi 24h</dt>
                    <dd
                        title={stats?.price_change_percent}
                        data-direction={
                            stats?.price_change_percent.startsWith("-")
                                ? "down"
                                : "up"
                        }
                    >
                        {formatPercentage(stats?.price_change_percent)}
                        {stats && "%"}
                    </dd>
                </div>
                <div>
                    <dt>Cao nhất 24h / {quoteAsset}</dt>
                    <dd>{formatDecimal(stats?.high_price)}</dd>
                </div>
                <div>
                    <dt>Thấp nhất 24h / {quoteAsset}</dt>
                    <dd>{formatDecimal(stats?.low_price)}</dd>
                </div>
                <div>
                    <dt>
                        Khối lượng 24h /{" "}
                        {stats?.quote_volume == null
                            ? asset.symbol
                            : quoteAsset}
                    </dt>
                    <dd>
                        {formatDecimal(
                            stats?.quote_volume ?? stats?.base_volume,
                        )}
                    </dd>
                </div>
            </dl>
            {statsStale && (
                <p className="market-chart__notice">
                    Thống kê 24h đã cũ; đang chờ lần đồng bộ tiếp theo.
                </p>
            )}
            {!stats && (
                <p className="market-details__hint">Chưa có thống kê 24h.</p>
            )}
            {market && market.exchange !== "gold_api" && (
                <TradingWorkbench
                    key={`${market.exchange}:${market.symbol}`}
                    market={market}
                    now={now}
                    refreshVersion={refreshVersion}
                    style={style}
                    onStyleChange={handleStyleChange}
                    researchStance={stance}
                    resolvedStance={resolvedStance}
                />
            )}
            <div className="market-details__workspace">
                <div className="market-details__history">
                    {market?.exchange === "gold_api" && (
                        <p className="market-chart__empty">
                            XAU/USD là giá vàng tham chiếu. Chưa có lịch sử nến
                            vàng để vẽ biểu đồ và tính chỉ báo; nguồn lịch sử
                            cần API key riêng.
                        </p>
                    )}
                    {market && market.exchange !== "gold_api" && (
                        <>
                            <div className="market-details__chart-header">
                                <h3>Lịch sử giá</h3>
                                <div
                                    className="market-details__timeframes"
                                    role="group"
                                    aria-label="Khung thời gian biểu đồ"
                                >
                                    {TIMEFRAMES.filter(
                                        (value) =>
                                            market.exchange === "binance" ||
                                            !["5m", "15m"].includes(value),
                                    ).map((value) => (
                                        <button
                                            key={value}
                                            type="button"
                                            aria-pressed={timeframe === value}
                                            onClick={() =>
                                                handleTimeframeChange(value)
                                            }
                                        >
                                            {value.toUpperCase()}
                                        </button>
                                    ))}
                                </div>
                            </div>
                            <MarketHistory
                                key={`${market.exchange}:${market.symbol}:${timeframe}`}
                                symbol={market.symbol}
                                exchange={market.exchange}
                                timeframe={timeframe}
                                snapshotPrice={market.latest_price?.price}
                                refreshIntervalMs={refreshIntervalMs}
                                refreshVersion={refreshVersion}
                            />
                            <TechnicalIndicators
                                market={market}
                                stance={resolvedStance}
                                now={now}
                            />
                        </>
                    )}
                    {!market && (
                        <p className="market-chart__empty">
                            Chưa có thị trường khả dụng để tải lịch sử của{" "}
                            {asset.symbol}.
                        </p>
                    )}
                </div>
                <MarketAnalysis market={market} now={now} />
            </div>
        </section>
    );
}
