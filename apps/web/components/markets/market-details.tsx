"use client";

import { useState } from "react";

import type { Asset, Timeframe } from "@/lib/api/types";
import { formatDecimal, formatTime, priceStatus } from "@/lib/format/market";

import { MarketHistory } from "./market-history";
import { MarketAnalysis } from "./market-analysis";
import { PriceFlash } from "./price-flash";

type MarketDetailsProps = {
    asset: Asset;
    now: number;
};

const TIMEFRAMES: Timeframe[] = ["1h", "4h", "1d"];

export function MarketDetails({ asset, now }: MarketDetailsProps) {
    const [timeframe, setTimeframe] = useState<Timeframe>("1h");
    const market = asset.markets.find((item) => item.enabled && item.trading_status === "TRADING");
    const stats = market?.ticker_stats;
    const freshness = priceStatus(market, now);
    const statsStale =
        stats && (now - Date.parse(stats.fetched_at) > 600_000 || market.stats_freshness.status !== "fresh");

    return (
        <section id="market-details" className="market-details" aria-labelledby="market-details-title">
            <header className="market-details__header">
                <div>
                    <p className="market-monitor__eyebrow">CHI TIẾT TÀI SẢN · BINANCE SPOT</p>
                    <h2 id="market-details-title">
                        {asset.symbol} <span>{asset.name}</span>
                    </h2>
                    <p className="market-details__pair">{market?.symbol ?? "Chưa có cặp Spot USDT khả dụng"}</p>
                </div>
                <div className="market-details__quote" data-freshness={freshness}>
                    <strong>
                        <PriceFlash value={market?.latest_price?.price} />
                    </strong>
                    <span> USDT</span>
                    <p>
                        {formatTime(market?.latest_price?.fetched_at)} · UTC+7
                        {freshness === "stale" && " · Dữ liệu giá cũ"}
                        {freshness === "missing" && " · Chưa có giá"}
                        {!asset.enabled && " · Tài sản đã tắt đồng bộ"}
                    </p>
                </div>
            </header>
            <dl className="market-details__stats">
                <div>
                    <dt>Thay đổi 24h</dt>
                    <dd>
                        {formatDecimal(stats?.price_change_percent)}
                        {stats && "%"}
                    </dd>
                </div>
                <div>
                    <dt>Cao nhất 24h / USDT</dt>
                    <dd>{formatDecimal(stats?.high_price)}</dd>
                </div>
                <div>
                    <dt>Thấp nhất 24h / USDT</dt>
                    <dd>{formatDecimal(stats?.low_price)}</dd>
                </div>
                <div>
                    <dt>Khối lượng 24h / USDT</dt>
                    <dd>{formatDecimal(stats?.quote_volume)}</dd>
                </div>
            </dl>
            {statsStale && <p className="market-chart__notice">Thống kê 24h đã cũ; đang chờ lần đồng bộ tiếp theo.</p>}
            {!stats && <p className="market-details__hint">Chưa có thống kê 24h.</p>}
            <MarketAnalysis market={market} now={now} />
            {market ? (
                <>
                    <div className="market-details__chart-header">
                        <div>
                            <h3>Lịch sử giá</h3>
                            <p>Kéo để di chuyển · Cuộn để phóng to</p>
                        </div>
                        <div className="market-details__timeframes" role="group" aria-label="Khung thời gian biểu đồ">
                            {TIMEFRAMES.map((value) => (
                                <button
                                    key={value}
                                    type="button"
                                    aria-pressed={timeframe === value}
                                    onClick={() => setTimeframe(value)}
                                >
                                    {value.toUpperCase()}
                                </button>
                            ))}
                        </div>
                    </div>
                    <MarketHistory
                        key={`${market.symbol}:${timeframe}`}
                        symbol={market.symbol}
                        timeframe={timeframe}
                        snapshotPrice={market.latest_price?.price}
                    />
                </>
            ) : (
                <p className="market-chart__empty">Chưa có thị trường khả dụng để tải lịch sử của {asset.symbol}.</p>
            )}
        </section>
    );
}
