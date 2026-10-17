import { expect, test } from "@playwright/test";
import type { UTCTimestamp } from "lightweight-charts";

import { formatChartTick, formatChartTime } from "../lib/format/chart-time";

test("Vietnam axis and crosshair formatting handles day and year rollover without mutating timestamps", () => {
    const timestamp = (Date.parse("2026-12-31T18:30:00Z") / 1000) as UTCTimestamp;
    expect(formatChartTick(timestamp, 3)).toBe("01:30");
    expect(formatChartTick(timestamp, 2)).toMatch(/^01[-/]01$/);
    expect(formatChartTick(timestamp, 0)).toBe("2027");
    expect(formatChartTick(timestamp, 1)).toBe("01/27");
    expect(formatChartTime(timestamp)).toContain("01:30");
    expect(formatChartTime(timestamp)).toContain("01/01/2027");
    expect(timestamp).toBe(Date.parse("2026-12-31T18:30:00Z") / 1000);
    expect(formatChartTick("2026-10-17T17:00:00Z", 4)).toBe("00:00:00");
    expect(formatChartTime({ year: 2026, month: 10, day: 17 })).toContain("07:00");
});
