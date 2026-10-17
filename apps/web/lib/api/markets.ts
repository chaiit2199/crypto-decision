import "server-only";

import { marketsSchema, statusSchema } from "./types";
import type { MarketMonitorResult } from "./types";

export async function getMarketMonitor(): Promise<MarketMonitorResult> {
    const checked_at = Date.now();
    const baseUrl = process.env.API_BASE_URL ?? "http://127.0.0.1:4000";

    try {
        const responses = await Promise.all([
            fetch(new URL("/api/markets?page_size=100", baseUrl), {
                cache: "no-store",
                signal: AbortSignal.timeout(8_000),
            }),
            fetch(new URL("/api/system/market-data-status", baseUrl), {
                cache: "no-store",
                signal: AbortSignal.timeout(8_000),
            }),
        ]);

        if (responses.some((response) => !response.ok)) {
            return { checked_at, ok: false, message: "API thị trường chưa sẵn sàng. Trang sẽ tự kết nối lại." };
        }

        const [markets, status] = await Promise.all(responses.map((response) => response.json()));
        const parsedMarkets = marketsSchema.safeParse(markets);
        const parsedStatus = statusSchema.safeParse(status);

        if (!parsedMarkets.success || !parsedStatus.success) {
            return { checked_at, ok: false, message: "Dữ liệu API không đúng định dạng. Vui lòng kiểm tra backend." };
        }

        return { checked_at, ok: true, data: { assets: parsedMarkets.data.data, status: parsedStatus.data.data } };
    } catch {
        return { checked_at, ok: false, message: "Không kết nối được API. Trang sẽ tự thử lại sau 5 giây." };
    }
}
