import type { Market } from "@/lib/api/types";

const indicatorFormat = new Intl.NumberFormat("en-US", { maximumSignificantDigits: 8 });

/** Display only; the original Decimal string remains available in the API and title. */
export function formatIndicator(value: string | undefined): string {
    if (value === undefined) {
        return "—";
    }

    return indicatorFormat.format(Number(value));
}

/** Group digits without converting financial decimal strings through a float. */
export function formatDecimal(value: string | undefined): string {
    if (value === undefined) {
        return "—";
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

export function priceStatus(market: Market | undefined, now: number): "fresh" | "stale" | "missing" {
    if (!market?.latest_price) {
        return "missing";
    }

    if (now - Date.parse(market.latest_price.fetched_at) > 90_000) {
        return "stale";
    }

    return market.price_freshness.status;
}
