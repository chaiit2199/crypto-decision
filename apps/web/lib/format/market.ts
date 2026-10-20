import type { Market } from "@/lib/api/types";

const indicatorFormat = new Intl.NumberFormat("en-US", {
    maximumSignificantDigits: 8,
});
const percentageFormat = new Intl.NumberFormat("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
});

/** Rounded display only; preserve the original Decimal value in the response and tooltip. */
export function formatPercentage(value: string | undefined): string {
    return value === undefined ? "-" : percentageFormat.format(Number(value));
}

/** Display only; the original Decimal string remains available in the API and title. */
export function formatIndicator(value: string | null | undefined): string {
    if (value == null) {
        return "-";
    }

    return indicatorFormat.format(Number(value));
}

/** Group digits without converting financial decimal strings through a float. */
export function formatDecimal(value: string | null | undefined): string {
    if (value == null) {
        return "-";
    }

    const [whole, fraction = ""] = value.split(".");
    const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    const significant = fraction.replace(/0+$/, "");
    return significant ? `${grouped}.${significant}` : grouped;
}

export function formatTime(value: string | null | undefined): string {
    if (!value) {
        return "Chưa cập nhật";
    }

    return new Intl.DateTimeFormat("vi-VN", {
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        timeZone: "Asia/Ho_Chi_Minh",
        hour12: false,
    }).format(new Date(value));
}

export function priceStatus(
    market: Market | undefined,
    now: number,
): "fresh" | "stale" | "missing" {
    if (!market?.latest_price) {
        return "missing";
    }

    // Gold API updatedAt can freeze while polls still refresh fetched_at.
    const pricedAt =
        market.exchange === "gold_api"
            ? (market.latest_price.fetched_at ?? market.latest_price.data_at)
            : (market.latest_price.data_at ?? market.latest_price.fetched_at);

    if (now - Date.parse(pricedAt) > market.price_max_age_seconds * 1000) {
        return "stale";
    }

    return market.price_freshness.status;
}
