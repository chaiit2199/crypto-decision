import type { TickMarkType, Time } from "lightweight-charts";

const TIME_ZONE = "Asia/Ho_Chi_Minh";
const dateTimeFormatter = new Intl.DateTimeFormat("vi-VN", {
    timeZone: TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
});
// Indexed by TickMarkType: Year, Month, DayOfMonth, Time, TimeWithSeconds.
const tickFormatters = [
    new Intl.DateTimeFormat("vi-VN", { timeZone: TIME_ZONE, year: "numeric" }),
    new Intl.DateTimeFormat("vi-VN", { timeZone: TIME_ZONE, month: "2-digit", year: "2-digit" }),
    new Intl.DateTimeFormat("vi-VN", {
        timeZone: TIME_ZONE,
        day: "2-digit",
        month: "2-digit",
    }),
    new Intl.DateTimeFormat("vi-VN", {
        timeZone: TIME_ZONE,
        hour: "2-digit",
        minute: "2-digit",
        hourCycle: "h23",
    }),
    new Intl.DateTimeFormat("vi-VN", {
        timeZone: TIME_ZONE,
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        hourCycle: "h23",
    }),
] as const;

function chartDate(time: Time): Date {
    if (typeof time === "number") {
        return new Date(time * 1000);
    }
    if (typeof time === "string") {
        return new Date(time);
    }
    return new Date(Date.UTC(time.year, time.month - 1, time.day));
}

/** Display-only timezone conversion: preserve the original UTC candle timestamps. */
export function formatChartTime(time: Time): string {
    return dateTimeFormatter.format(chartDate(time));
}

export function formatChartTick(time: Time, tickMarkType: TickMarkType): string {
    const parts = Object.fromEntries(
        tickFormatters[tickMarkType].formatToParts(chartDate(time)).map(({ type, value }) => [type, value]),
    );

    // Keep axis labels short and consistent across browser/Node locale databases.
    if (parts.hour) {
        const seconds = parts.second ? `:${parts.second}` : "";
        return `${parts.hour}:${parts.minute}${seconds}`;
    }
    if (parts.day) {
        return `${parts.day}/${parts.month}`;
    }
    if (parts.month) {
        return `${parts.month}/${parts.year}`;
    }
    return parts.year;
}
