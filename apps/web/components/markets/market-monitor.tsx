"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

import { refreshMarketMonitor } from "@/lib/api/monitor-client";
import type { MarketMonitorResult } from "@/lib/api/types";
import { formatTime, priceStatus } from "@/lib/format/market";
import { selectedMarket } from "@/lib/markets/selected-market";
import type { QuoteAsset } from "@/lib/markets/selected-market";

import { MarketRow } from "./market-row";
import { MarketDetails } from "./market-details";

type MarketMonitorProps = {
    initialResult: MarketMonitorResult;
    initialTime: number;
};

export function MarketMonitor({ initialResult, initialTime }: MarketMonitorProps) {
    const [data, setData] = useState(initialResult.ok ? initialResult.data : null);
    const [error, setError] = useState(initialResult.ok ? null : initialResult.message);
    const [query, setQuery] = useState("");
    const [selectedSymbol, setSelectedSymbol] = useState("BTC");
    const [quoteAsset, setQuoteAsset] = useState<QuoteAsset>("USD");
    const [now, setNow] = useState(initialTime);
    const [refreshVersion, setRefreshVersion] = useState(0);
    const [isRefreshing, setIsRefreshing] = useState(false);

    useEffect(() => {
        const controller = new AbortController();
        let timer: ReturnType<typeof setTimeout>;

        async function refresh() {
            const result = await refreshMarketMonitor(controller.signal);

            if (controller.signal.aborted) {
                return;
            }

            if (result.ok) {
                setData(result.data);
                setError(null);
            } else {
                setError(result.message);
            }

            setNow(Date.now());
            setIsRefreshing(false);
            // Schedule after completion so slow requests never accumulate.
            timer = setTimeout(refresh, 300_000);
        }

        timer = setTimeout(refresh, 0);
        return () => {
            clearTimeout(timer);
            controller.abort();
        };
    }, [refreshVersion]);

    const assets = data?.assets ?? [];
    const selectedAsset = assets.find((asset) => asset.symbol === selectedSymbol);
    const market = selectedAsset ? selectedMarket(selectedAsset, quoteAsset) : undefined;
    const search = query.trim().toLowerCase();
    const visibleAssets = assets.filter((asset) =>
        `${asset.symbol} ${asset.name} ${asset.markets.map((market) => market.symbol).join(" ")}`
            .toLowerCase()
            .includes(search),
    );
    const availableAssets = assets.filter((asset) => asset.enabled && selectedMarket(asset, quoteAsset));
    const freshCount = availableAssets.filter(
        (asset) => priceStatus(selectedMarket(asset, quoteAsset), now) === "fresh",
    ).length;
    const collector = quoteAsset === "USD" ? data?.status.sources.coinbase : data?.status.collector;
    const jobs = data?.status.jobs;
    const pendingJobs = (jobs?.available ?? 0) + (jobs?.scheduled ?? 0) + (jobs?.retryable ?? 0);
    const blocked = collector?.blocked_until && Date.parse(collector.blocked_until) > now;
    let connectionLabel = "Đang kết nối";

    if (error) {
        connectionLabel = "Mất kết nối API";
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
            behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth",
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
                <Link className="market-monitor__brand" href="/" aria-label="Crypto Decision Lab, trang chủ">
                    <span className="market-monitor__logo" aria-hidden="true">
                        C<span>↗</span>
                    </span>
                    <span>
                        CRYPTO<span className="market-monitor__brand-sub">DECISION LAB</span>
                    </span>
                </Link>
                <span className="market-monitor__environment">LOCAL / MARKET DATA</span>
            </header>

            <section className="market-monitor__intro" aria-labelledby="market-title">
                <div>
                    <p className="market-monitor__eyebrow">THỊ TRƯỜNG · {quoteAsset}</p>
                    <h1 id="market-title">
                        Thị trường<span>.</span>
                    </h1>
                    <p>Theo dõi giá, biến động và nhịp cập nhật của danh mục.</p>
                </div>
                <div className="market-monitor__live">
                    <span
                        className="market-monitor__connection"
                        data-live={!error && freshCount > 0 && data?.status.enabled}
                    >
                        <span aria-hidden="true" />
                        {connectionLabel}
                    </span>
                    <span>
                        Giá mỗi {(data?.status.price_poll_interval_seconds ?? 300) / 60} phút
                        {" · "}Jev mỗi {(market?.analysis_interval_seconds ?? 900) / 60} phút
                        {" · "}Trang làm mới mỗi 5 phút
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
                    Backend đang tắt đồng bộ tự động. Bật đồng bộ và khởi động lại API để nhận giá mới.
                </p>
            )}
            {blocked && (
                <p className="market-monitor__notice">
                    Nguồn dữ liệu đang chờ đến {formatTime(collector.blocked_until)} do giới hạn từ nhà cung cấp.
                </p>
            )}
            {collector?.last_error && (
                <p className="market-monitor__notice">Lần đồng bộ gần nhất gặp lỗi: {collector.last_error}</p>
            )}

            <section className="market-monitor__metrics" aria-label="Trạng thái dữ liệu">
                <article>
                    <span>Giá còn mới</span>
                    <p>
                        {freshCount}
                        <small> / {data?.status.configured_assets ?? "—"} tài sản</small>
                    </p>
                    <span>{availableAssets.length} tài sản có cặp {quoteAsset} khả dụng</span>
                </article>
                <article>
                    <span>Snapshot giá gần nhất</span>
                    <p className="market-monitor__clock">{formatTime(collector?.prices_at)}</p>
                    <span>Giờ Việt Nam · UTC+7</span>
                </article>
                <article>
                    <span>Hàng đợi đồng bộ</span>
                    <p>
                        {pendingJobs}
                        <small> job đang chờ</small>
                    </p>
                    <span>
                        {jobs?.executing ?? 0} đang chạy · {jobs?.retryable ?? 0} chờ thử lại · {jobs?.discarded ?? 0}{" "}
                        lỗi
                    </span>
                </article>
            </section>

            <div className="market-monitor__market-selection">
                <label className="market-monitor__quote">
                    Đồng tiền của cặp giao dịch
                    <select
                        value={quoteAsset}
                        onChange={(event) => {
                            if (event.target.value === "USD" || event.target.value === "USDT") {
                                setQuoteAsset(event.target.value);
                            }
                        }}
                    >
                        <option value="USDT">USDT</option>
                        <option value="USD">USD</option>
                    </select>
                </label>
                <p>Giá, biểu đồ và Jev theo cặp được chọn.</p>
            </div>
            {data && availableAssets.length === 0 && (
                <p className="market-monitor__notice" role="status">
                    Chưa có thị trường {quoteAsset} khả dụng trong danh mục.
                    {quoteAsset === "USD" && " Coinbase đang xác minh cặp USD và đồng bộ dữ liệu. Một số mã có thể không được nguồn này hỗ trợ."}
                </p>
            )}
            {selectedAsset && (
                <MarketDetails
                    key={`${selectedAsset.id}:${quoteAsset}`}
                    asset={selectedAsset}
                    quoteAsset={quoteAsset}
                    now={now}
                />
            )}

            <section className="market-monitor__panel" aria-labelledby="watchlist-title">
                <div className="market-monitor__toolbar">
                    <div>
                        <h2 id="watchlist-title">
                            Danh mục theo dõi <span>{assets.length}</span>
                        </h2>
                        <p>Bấm vào mã để xem chi tiết · Giá theo {quoteAsset} · Khối lượng ghi rõ đơn vị</p>
                    </div>
                    <div className="market-monitor__actions">
                        <label className="market-monitor__search">
                            <span className="sr-only">Tìm tài sản hoặc cặp giao dịch</span>
                            <span aria-hidden="true">⌕</span>
                            <input
                                type="search"
                                placeholder="Tìm BTC, ETH…"
                                value={query}
                                onChange={(event) => setQuery(event.target.value)}
                            />
                        </label>
                        <button type="button" onClick={handleRefresh} disabled={isRefreshing}>
                            <span aria-hidden="true">↻</span> {isRefreshing ? "Đang tải…" : "Làm mới"}
                        </button>
                    </div>
                </div>

                <div className="market-monitor__table-scroll" tabIndex={0} aria-label="Bảng giá có thể cuộn ngang">
                    <table>
                        <thead>
                            <tr>
                                <th scope="col">Tài sản</th>
                                <th scope="col">Cặp giao dịch</th>
                                <th scope="col" className="market-monitor__numeric">
                                    Giá / {quoteAsset}
                                </th>
                                <th scope="col" className="market-monitor__numeric">
                                    Thay đổi 24h
                                </th>
                                <th scope="col" className="market-monitor__numeric">
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
                                    metadataReady={Boolean(collector?.metadata_at)}
                                    selected={asset.symbol === selectedSymbol}
                                    onSelect={handleSelectSymbol}
                                />
                            ))}
                            {visibleAssets.length === 0 && (
                                <tr>
                                    <td colSpan={6} className="market-monitor__empty">
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
                        Hiển thị {visibleAssets.length} / {assets.length} tài sản
                    </span>
                    <span>Giá quá chu kỳ đồng bộ + 60 giây được đánh dấu dữ liệu cũ</span>
                </footer>
            </section>
            <footer className="market-monitor__footer">
                <span>CRYPTO DECISION LAB</span>
                <span>Nguồn: Coinbase (USD) · Binance (USDT) · Gold API (XAU/USD)</span>
            </footer>
        </main>
    );
}
