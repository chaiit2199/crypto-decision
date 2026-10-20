"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";

import { refreshMarketMonitor } from "@/lib/api/monitor-client";
import type { MarketMonitorResult } from "@/lib/api/types";
import { formatTime, priceStatus } from "@/lib/format/market";
import { selectedMarket } from "@/lib/markets/selected-market";
import type { QuoteAsset } from "@/lib/markets/selected-market";

import { OpportunityScanner } from "./opportunity-scanner";
import { MarketRow } from "./market-row";
import { MarketDetails } from "./market-details";
import { WatchlistPicker } from "./watchlist-picker";

type MarketMonitorProps = {
    initialResult: MarketMonitorResult;
    initialTime: number;
};

export function MarketMonitor({
    initialResult,
    initialTime,
}: MarketMonitorProps) {
    const [data, setData] = useState(
        initialResult.ok ? initialResult.data : null,
    );
    const [error, setError] = useState(
        initialResult.ok ? null : initialResult.message,
    );
    const [query, setQuery] = useState("");
    const [selectedSymbol, setSelectedSymbol] = useState("BTC");
    const [quoteAsset, setQuoteAsset] = useState<QuoteAsset>("USD");
    const [now, setNow] = useState(initialTime);
    const [refreshVersion, setRefreshVersion] = useState(0);
    const [isRefreshing, setIsRefreshing] = useState(false);

    const pollInterval = useRef(
        initialResult.ok
            ? initialResult.data.status.price_poll_interval_seconds * 1000
            : 300_000,
    );

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
                pollInterval.current =
                    result.data.status.price_poll_interval_seconds * 1000;
                setData(result.data);
                setError(null);
            } else {
                setError(result.message);
            }

            setNow(Date.now());
            setIsRefreshing(false);
            // Schedule after completion so slow requests never accumulate.
            timer = setTimeout(refresh, pollInterval.current);
        }

        timer = setTimeout(refresh, 0);
        return () => {
            clearTimeout(timer);
            controller.abort();
        };
    }, [refreshVersion]);

    const assets = (data?.assets ?? []).filter(
        (asset) => asset.symbol !== "XAU",
    );
    const selectedAsset = assets.find(
        (asset) => asset.symbol === selectedSymbol,
    );
    const search = query.trim().toLowerCase();
    const visibleAssets = assets.filter((asset) =>
        `${asset.symbol} ${asset.name} ${asset.markets.map((market) => market.symbol).join(" ")}`
            .toLowerCase()
            .includes(search),
    );
    const availableAssets = assets.filter(
        (asset) => asset.enabled && selectedMarket(asset, quoteAsset),
    );
    const freshCount = availableAssets.filter(
        (asset) =>
            priceStatus(selectedMarket(asset, quoteAsset), now) === "fresh",
    ).length;
    const collector =
        quoteAsset === "USD"
            ? data?.status.sources.coinbase
            : data?.status.collector;
    const currentStats = availableAssets.flatMap((asset) => {
        const market = selectedMarket(asset, quoteAsset);
        const stats = market?.ticker_stats;
        if (
            !stats ||
            market.stats_freshness.status !== "fresh" ||
            now - Date.parse(stats.fetched_at) > 600_000
        ) {
            return [];
        }
        return [stats];
    });
    const risingCount = currentStats.filter(
        (stats) => Number(stats.price_change_percent) > 0,
    ).length;
    const fallingCount = currentStats.filter(
        (stats) => Number(stats.price_change_percent) < 0,
    ).length;
    const refreshIntervalMs =
        (data?.status.price_poll_interval_seconds ?? 300) * 1000;
    const blocked =
        collector?.blocked_until && Date.parse(collector.blocked_until) > now;
    let connectionLabel = "Đang kết nối";

    if (error) {
        connectionLabel = "Mất kết nối máy chủ";
    } else if (data && !data.status.enabled) {
        connectionLabel = "Đồng bộ đang tắt";
    } else if (blocked) {
        connectionLabel = "Tạm chờ nguồn giá";
    } else if (data && freshCount > 0) {
        connectionLabel = "Đang đồng bộ";
    } else if (data) {
        connectionLabel = "Đang chờ giá mới";
    }

    function handleSelectSymbol(symbol: string) {
        setSelectedSymbol(symbol);
        document.getElementById("market-details")?.scrollIntoView({
            behavior: window.matchMedia("(prefers-reduced-motion: reduce)")
                .matches
                ? "auto"
                : "smooth",
            block: "start",
        });
    }

    function handleRefresh() {
        setIsRefreshing(true);
        setRefreshVersion((version) => version + 1);
    }

    return (
        <main className="market-monitor">
            <header className="market-monitor__header">
                <Link
                    className="market-monitor__brand"
                    href="/"
                    aria-label="Crypto Decision, trang chủ"
                >
                    <Image
                        className="market-monitor__logo"
                        src="/logo.png"
                        alt=""
                        width={40}
                        height={40}
                        priority
                    />
                    <span>
                        CRYPTO
                        <span className="market-monitor__brand-sub">
                            DECISION
                        </span>
                    </span>
                </Link>
                <div className="market-monitor__header-actions">
                    <Link href="/gold" className="market-monitor__gold-link">
                        Vàng USD · dài hạn
                    </Link>
                    <WatchlistPicker
                        assets={assets}
                        quoteAsset={quoteAsset}
                        selectedSymbol={selectedSymbol}
                        now={now}
                        onSelect={handleSelectSymbol}
                    />
                </div>
            </header>

            <section
                className="market-monitor__intro"
                aria-labelledby="market-title"
            >
                <div>
                    <p className="market-monitor__eyebrow">
                        BÀN NGHIÊN CỨU · BINANCE GIAO NGAY
                    </p>
                    <h1 id="market-title">
                        Quyết định có kỷ luật<span>.</span>
                    </h1>
                    <p>
                        Checklist trước khi vào. Không hứa lợi nhuận. Không đặt
                        lệnh tự động.
                    </p>
                </div>
                <div className="market-monitor__live">
                    <span
                        className="market-monitor__connection"
                        data-live={
                            !error &&
                            !blocked &&
                            freshCount > 0 &&
                            data?.status.enabled
                        }
                    >
                        <span aria-hidden="true" />
                        {connectionLabel}
                    </span>
                </div>
            </section>

            {error && (
                <p className="market-monitor__notice" role="alert">
                    {error}
                </p>
            )}
            {data && !data.status.enabled && (
                <p className="market-monitor__notice">
                    Máy chủ đang tắt đồng bộ tự động. Bật đồng bộ và khởi động
                    lại dịch vụ để nhận giá mới.
                </p>
            )}
            {blocked && (
                <p className="market-monitor__notice">
                    Nguồn dữ liệu đang chờ đến{" "}
                    {formatTime(collector.blocked_until)} do giới hạn từ nhà
                    cung cấp.
                </p>
            )}
            {collector?.last_error && (
                <p className="market-monitor__notice">
                    Lần đồng bộ gần nhất gặp lỗi: {collector.last_error}
                </p>
            )}

            <section
                className="market-monitor__metrics"
                aria-label="Tổng quan danh mục"
            >
                <article>
                    <span>
                        Danh mục theo dõi <span aria-hidden="true">◈</span>
                    </span>
                    <p>
                        {data ? assets.length : "-"}
                        <small> tài sản</small>
                    </p>
                    <span>
                        {freshCount} / {availableAssets.length} giá đang cập
                        nhật
                    </span>
                </article>
                <article data-tone="positive">
                    <span>
                        Tăng trong 24h <span aria-hidden="true">↗</span>
                    </span>
                    <p>
                        {currentStats.length > 0 ? risingCount : "-"}
                        <small> tài sản</small>
                    </p>
                    <span>Trong {currentStats.length} mã có thống kê mới</span>
                </article>
                <article data-tone="negative">
                    <span>
                        Giảm trong 24h <span aria-hidden="true">↘</span>
                    </span>
                    <p>
                        {currentStats.length > 0 ? fallingCount : "-"}
                        <small> tài sản</small>
                    </p>
                    <span>Theo cặp {quoteAsset}</span>
                </article>
                <article>
                    <span>
                        Cập nhật gần nhất <span aria-hidden="true">◷</span>
                    </span>
                    <p className="market-monitor__clock">
                        {formatTime(collector?.prices_at)}
                    </p>
                    <span>Giờ Việt Nam</span>
                </article>
            </section>

            <div className="market-monitor__market-selection">
                <h2>Khu vực phân tích</h2>
                <label className="market-monitor__quote">
                    <span>Thị trường</span>
                    <select
                        aria-label="Đồng tiền của cặp giao dịch"
                        value={quoteAsset}
                        onChange={(event) => {
                            if (
                                event.target.value === "USD" ||
                                event.target.value === "USDT"
                            ) {
                                setQuoteAsset(event.target.value);
                            }
                        }}
                    >
                        <option value="USD">USD · Coinbase</option>
                        <option value="USDT">USDT · Binance Spot</option>
                    </select>
                </label>
            </div>
            {data && availableAssets.length === 0 && (
                <p className="market-monitor__notice" role="status">
                    Chưa có thị trường {quoteAsset} khả dụng trong danh mục.
                    {quoteAsset === "USD" &&
                        " USD crypto lấy từ Coinbase (không quy đổi từ USDT). Vàng XAU/USD nằm ở trang Vàng dài hạn. Một số mã chỉ có trên Binance USDT."}
                </p>
            )}
            {data && quoteAsset === "USD" && availableAssets.length > 0 && (
                <p className="market-monitor__notice" role="status">
                    Đang xem giá USD crypto qua Coinbase. Nghiên cứu vàng theo
                    ngày:{" "}
                    <Link href="/gold">trang Vàng USD</Link>.
                </p>
            )}
            {selectedAsset && (
                <MarketDetails
                    key={`${selectedAsset.id}:${quoteAsset}`}
                    asset={selectedAsset}
                    quoteAsset={quoteAsset}
                    now={now}
                    refreshIntervalMs={refreshIntervalMs}
                    refreshVersion={refreshVersion}
                />
            )}

            <OpportunityScanner
                key={quoteAsset}
                exchange={quoteAsset === "USDT" ? "binance" : "coinbase"}
                now={now}
                refreshVersion={refreshVersion}
            />
            <section
                className="market-monitor__panel"
                aria-labelledby="watchlist-title"
            >
                <div className="market-monitor__toolbar">
                    <div>
                        <h2 id="watchlist-title">
                            Danh mục theo dõi <span>{assets.length}</span>
                        </h2>
                    </div>
                    <div className="market-monitor__actions">
                        <label className="market-monitor__search">
                            <span className="sr-only">
                                Tìm tài sản hoặc cặp giao dịch
                            </span>
                            <span aria-hidden="true">⌕</span>
                            <input
                                type="search"
                                placeholder="Tìm BTC, ETH…"
                                value={query}
                                onChange={(event) =>
                                    setQuery(event.target.value)
                                }
                            />
                        </label>
                        <button
                            type="button"
                            onClick={handleRefresh}
                            disabled={isRefreshing}
                        >
                            <span aria-hidden="true">↻</span>{" "}
                            {isRefreshing ? "Đang tải…" : "Làm mới"}
                        </button>
                    </div>
                </div>

                <div
                    className="market-monitor__table-scroll"
                    tabIndex={0}
                    aria-label="Bảng giá có thể cuộn ngang"
                >
                    <table>
                        <thead>
                            <tr>
                                <th scope="col">Tài sản</th>
                                <th scope="col">Cặp giao dịch</th>
                                <th
                                    scope="col"
                                    className="market-monitor__numeric"
                                >
                                    Giá / {quoteAsset}
                                </th>
                                <th
                                    scope="col"
                                    className="market-monitor__numeric"
                                >
                                    Thay đổi 24h
                                </th>
                                <th
                                    scope="col"
                                    className="market-monitor__numeric"
                                >
                                    Khối lượng 24h
                                </th>
                                <th scope="col">Cập nhật</th>
                            </tr>
                        </thead>
                        <tbody>
                            {visibleAssets.map((asset) => (
                                <MarketRow
                                    key={asset.id}
                                    asset={asset}
                                    quoteAsset={quoteAsset}
                                    now={now}
                                    metadataReady={Boolean(
                                        collector?.metadata_at,
                                    )}
                                    selected={asset.symbol === selectedSymbol}
                                    onSelect={handleSelectSymbol}
                                />
                            ))}
                            {visibleAssets.length === 0 && (
                                <tr>
                                    <td
                                        colSpan={6}
                                        className="market-monitor__empty"
                                    >
                                        {search
                                            ? "Không tìm thấy tài sản phù hợp."
                                            : "Chưa có dữ liệu thị trường. Đang chờ backend đồng bộ…"}
                                    </td>
                                </tr>
                            )}
                        </tbody>
                    </table>
                </div>
                <footer className="market-monitor__table-footer">
                    <span>
                        Hiển thị {visibleAssets.length} / {assets.length} tài
                        sản
                    </span>
                    <span>{quoteAsset} · Thị trường giao ngay</span>
                </footer>
            </section>
            <footer className="market-monitor__footer">
                <span className="market-monitor__footer-brand">
                    <Image
                        src="/logo.png"
                        alt=""
                        width={24}
                        height={24}
                    />
                    CRYPTO DECISION
                </span>
                <span>
                    Nguồn: Coinbase (USD) · Binance (USDT) · giá vàng tham chiếu
                    (XAU/USD)
                </span>
            </footer>
        </main>
    );
}
