import type { Asset, Market } from "@/lib/api/types";

export type QuoteAsset = "USD" | "USDT";

/** Select the actual quoted market; never substitute another currency's price. */
export function selectedMarket(asset: Asset, quoteAsset: QuoteAsset): Market | undefined {
    return asset.markets.find(
        (market) => market.quote_asset === quoteAsset && market.enabled && market.trading_status === "TRADING",
    );
}
