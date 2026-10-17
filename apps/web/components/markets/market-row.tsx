import type { Asset } from "@/lib/api/types";
import { formatDecimal, formatTime, priceStatus } from "@/lib/format/market";

import { PriceFlash } from "./price-flash";

type MarketRowProps = {
    asset: Asset;
    now: number;
    metadataReady: boolean;
    selected: boolean;
    onSelect: (symbol: string) => void;
};

const STATUS_LABEL = {
    fresh: "Mới nhất",
    stale: "Dữ liệu cũ",
    missing: "Chờ dữ liệu",
};

export function MarketRow({ asset, now, metadataReady, selected, onSelect }: MarketRowProps) {
    const market = asset.markets.find((item) => item.enabled && item.trading_status === "TRADING");
    const freshness = priceStatus(market, now);
    const change = market?.ticker_stats?.price_change_percent;
    const negative = change?.startsWith("-");
    let changeLabel = "—";

    if (change !== undefined) {
        const sign = negative ? "" : "+";
        changeLabel = `${sign}${formatDecimal(change)}%`;
    }

    const statsStale =
        market?.stats_freshness.status !== "fresh" ||
        (market.ticker_stats !== null && now - Date.parse(market.ticker_stats.fetched_at) > 600_000);
    let label = STATUS_LABEL[freshness];

    if (!asset.enabled) {
        label = "Đã tắt";
    } else if (!market && metadataReady) {
        label = "Không có Spot USDT";
    }

    return (
        <tr className="market-row" data-selected={selected} onClick={() => onSelect(asset.symbol)}>
            <td>
                <div className="market-row__asset">
                    <span className="market-row__monogram" aria-hidden="true">
                        {asset.symbol.slice(0, 2)}
                    </span>
                    <div>
                        <button
                            type="button"
                            className="market-row__select"
                            aria-label={`Xem chi tiết ${asset.symbol}`}
                            aria-pressed={selected}
                            aria-controls="market-details"
                        >
                            {asset.symbol}
                        </button>
                        <span className="market-row__name">{asset.name}</span>
                    </div>
                </div>
            </td>
            <td className="market-row__pair">{market?.symbol ?? "—"}</td>
            <td className="market-row__number market-row__price" data-freshness={freshness}>
                <PriceFlash value={market?.latest_price?.price} />
            </td>
            <td className="market-row__number">
                <span className="market-row__change" data-direction={negative ? "down" : "up"}>
                    {changeLabel}
                </span>
                {market?.ticker_stats && statsStale && <span className="market-row__old">Số liệu cũ</span>}
            </td>
            <td className="market-row__number market-row__volume">
                {formatDecimal(market?.ticker_stats?.quote_volume)}
            </td>
            <td>
                <span className="market-row__status" data-status={freshness}>
                    {label}
                </span>
                <time className="market-row__time" dateTime={market?.latest_price?.fetched_at}>
                    {formatTime(market?.latest_price?.fetched_at)}
                </time>
            </td>
        </tr>
    );
}
