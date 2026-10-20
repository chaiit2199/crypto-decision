"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";

import { refreshMarketMonitor } from "@/lib/api/monitor-client";
import type { Asset, MarketMonitorResult } from "@/lib/api/types";
import {
    formatDecimal,
    formatPercentage,
    formatTime,
    priceStatus,
} from "@/lib/format/market";
import { resolveResearchStance } from "@/lib/markets/indicator-readings";
import { selectedMarket } from "@/lib/markets/selected-market";

import { MarketHistory } from "./market-history";
import { MarketAnalysis } from "./market-analysis";
import { TechnicalIndicators } from "./technical-indicators";
import { PriceFlash } from "./price-flash";

type GoldDeskProps = {
    asset: Asset;
    now: number;
    refreshIntervalMs: number;
    refreshVersion: number;
};

export function GoldDesk({
    asset,
    now,
    refreshIntervalMs,
    refreshVersion,
}: GoldDeskProps) {
    const market = selectedMarket(asset, "USD");
    const freshness = priceStatus(market, now);
    const stats = market?.ticker_stats;
    const analysis = market?.analysis;
    const analysisActive =
        Boolean(market?.analysis_enabled) &&
        analysis?.status === "ready" &&
        analysis.freshness === "fresh" &&
        now < Date.parse(analysis.valid_until);
    const stance = resolveResearchStance(
        analysisActive ? analysis?.signal : null,
    );
    const historyReady =
        market &&
        market.analysis_unavailable_reason !== "gold_history_unavailable";

    return (
        <section className="gold-desk" aria-labelledby="gold-desk-title">
            <header className="gold-desk__header">
                <div>
                    <p className="market-monitor__eyebrow">
                        VÀNG · ĐẦU TƯ DÀI HẠN · USD
                    </p>
                    <h1 id="gold-desk-title">
                        XAU/USD <span>Vàng thế giới</span>
                    </h1>
                    <p>
                        Giá tham chiếu ~15 phút · Jev theo lịch 15 phút trên nến
                        ngày XAUS (miễn phí). Không khớp pip/spread XM · không
                        đặt lệnh thật.
                    </p>
                </div>
                <Link href="/" className="gold-desk__back">
                    ← Crypto spot
                </Link>
            </header>

            <div className="gold-desk__quote" data-freshness={freshness}>
                <strong>
                    <PriceFlash value={market?.latest_price?.price} />
                </strong>
                <span> USD / oz</span>
                <p>
                    {formatTime(
                        market?.latest_price?.fetched_at ??
                            market?.latest_price?.data_at,
                    )}{" "}
                    · giờ Việt Nam
                    {freshness === "stale" && " · Dữ liệu giá cũ"}
                    {freshness === "missing" && " · Chưa có giá"}
                </p>
            </div>

            <dl className="gold-desk__stats">
                <div>
                    <dt>Thay đổi gần đây</dt>
                    <dd
                        data-direction={
                            stats?.price_change_percent?.startsWith("-")
                                ? "down"
                                : "up"
                        }
                    >
                        {formatPercentage(stats?.price_change_percent)}
                        {stats && "%"}
                    </dd>
                </div>
                <div>
                    <dt>Cao gần đây / USD</dt>
                    <dd>{formatDecimal(stats?.high_price)}</dd>
                </div>
                <div>
                    <dt>Thấp gần đây / USD</dt>
                    <dd>{formatDecimal(stats?.low_price)}</dd>
                </div>
            </dl>

            <div className="gold-desk__workspace">
                <div className="gold-desk__history">
                    {!historyReady && (
                        <p className="market-chart__empty" role="status">
                            Đang chờ đồng bộ lịch sử nến ngày miễn phí (XAUS).
                            Giá live vẫn lấy từ Gold API.
                        </p>
                    )}
                    {historyReady && market && (
                        <>
                            <div className="market-details__chart-header">
                                <h2>Lịch sử giá · nến 1 ngày</h2>
                                <p className="gold-desk__frame">1D</p>
                            </div>
                            <MarketHistory
                                key={`${market.exchange}:${market.symbol}:1d:${refreshVersion}`}
                                symbol={market.symbol}
                                exchange={market.exchange}
                                timeframe="1d"
                                snapshotPrice={market.latest_price?.price}
                                refreshIntervalMs={refreshIntervalMs}
                                refreshVersion={refreshVersion}
                            />
                            <TechnicalIndicators
                                market={market}
                                stance={stance}
                                now={now}
                                candleLabel="nến 1 ngày đã đóng"
                            />
                        </>
                    )}
                </div>
                <MarketAnalysis
                    market={market}
                    assetEnabled={asset.enabled}
                    now={now}
                    candleFrameLabel="1 ngày"
                />
            </div>

            <p className="gold-desk__caption">
                Nguồn giá: Gold API hoặc XAUS spot (~15 phút) · lịch sử/Jev: nến
                1 ngày XAUS (miễn phí). Khung ngắn hơn 1 ngày cần nguồn nến giờ
                trả phí. Không dùng để scalp.
            </p>
        </section>
    );
}

type GoldDeskShellProps = {
    initialResult: MarketMonitorResult;
    initialTime: number;
};

function goldAsset(result: MarketMonitorResult): Asset | undefined {
    if (!result.ok) {
        return undefined;
    }

    return result.data.assets.find((row) => row.symbol === "XAU");
}

function goldPollMs(result: MarketMonitorResult): number {
    if (!result.ok) {
        return 900_000;
    }

    const seconds =
        result.data.status.gold_price_poll_interval_seconds ??
        result.data.status.price_poll_interval_seconds ??
        900;

    return seconds * 1000;
}

export function GoldDeskShell({
    initialResult,
    initialTime,
}: GoldDeskShellProps) {
    const [asset, setAsset] = useState(() => goldAsset(initialResult));
    const [error, setError] = useState(
        initialResult.ok ? null : initialResult.message,
    );
    const [now, setNow] = useState(initialTime);
    const pollInterval = useRef(goldPollMs(initialResult));

    useEffect(() => {
        const timer = setInterval(() => setNow(Date.now()), 1000);
        return () => clearInterval(timer);
    }, []);

    useEffect(() => {
        const controller = new AbortController();
        let timer: ReturnType<typeof setTimeout>;

        async function refresh() {
            const result = await refreshMarketMonitor(controller.signal);

            if (controller.signal.aborted) {
                return;
            }

            if (result.ok) {
                pollInterval.current = goldPollMs(result);
                setAsset(goldAsset(result));
                setError(null);
            } else {
                setError(result.message);
            }

            timer = setTimeout(refresh, pollInterval.current);
        }

        timer = setTimeout(refresh, 0);
        return () => {
            clearTimeout(timer);
            controller.abort();
        };
    }, []);

    if (!asset) {
        return (
            <section className="gold-desk">
                {error && (
                    <p className="market-monitor__notice" role="alert">
                        {error}
                    </p>
                )}
                <p className="market-chart__empty" role="status">
                    Chưa đăng ký XAU/USD. Đồng bộ nguồn vàng trên API rồi tải
                    lại trang.
                </p>
                <Link href="/">← Về bảng crypto</Link>
            </section>
        );
    }

    return (
        <GoldDesk
            asset={asset}
            now={now}
            refreshIntervalMs={pollInterval.current}
            refreshVersion={0}
        />
    );
}
