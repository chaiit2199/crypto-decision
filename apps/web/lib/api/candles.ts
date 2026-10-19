import "server-only";

import { candlesSchema } from "./types";
import type { CandlesResult, Timeframe } from "./types";

export async function getMarketCandles(symbol: string, exchange: string, timeframe: Timeframe): Promise<CandlesResult> {
    const url = new URL(
        `/api/markets/${encodeURIComponent(symbol)}/candles`,
        process.env.API_BASE_URL ?? "http://127.0.0.1:4000",
    );
    url.searchParams.set("exchange", exchange);
    url.searchParams.set("timeframe", timeframe);
    const limit = exchange === "coinbase" ? { "5m": "120", "15m": "120", "1h": "120", "4h": "60", "1d": "10" }[timeframe] : "120";
    url.searchParams.set("limit", limit);

    try {
        const response = await fetch(url, { cache: "no-store", signal: AbortSignal.timeout(8_000) });

        if (response.status === 422) {
            return {
                ok: false,
                message: "Chưa đủ nến 1H liên tiếp để tổng hợp khung này. Hãy thử 1H hoặc chờ đồng bộ.",
            };
        }

        if (response.status === 404) {
            return { ok: false, message: "Chưa có cặp giao dịch này trong dữ liệu thị trường." };
        }

        if (!response.ok) {
            return { ok: false, message: "Không tải được lịch sử giá. Vui lòng thử lại." };
        }

        const parsed = candlesSchema.safeParse(await response.json());

        if (!parsed.success) {
            return { ok: false, message: "Dữ liệu nến không đúng định dạng để vẽ biểu đồ." };
        }

        return { ok: true, data: parsed.data };
    } catch {
        return { ok: false, message: "Không kết nối được API lịch sử giá. Trang sẽ tự thử lại." };
    }
}
