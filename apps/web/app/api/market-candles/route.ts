import { getMarketCandles } from "@/lib/api/candles";
import { timeframeSchema } from "@/lib/api/types";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
    const params = new URL(request.url).searchParams;
    const symbol = params.get("symbol") ?? "";
    const exchange = params.get("exchange") ?? "binance";
    const timeframe = timeframeSchema.safeParse(params.get("timeframe") ?? "1h");
    const headers = { "Cache-Control": "no-store" };

    if (!/^[A-Z0-9]{1,30}$/.test(symbol) || !timeframe.success || !["binance", "coinbase", "gold_api"].includes(exchange)) {
        return Response.json({ ok: false, message: "Mã hoặc khung thời gian không hợp lệ." }, { status: 400, headers });
    }

    const result = await getMarketCandles(symbol, exchange, timeframe.data);
    return Response.json(result, { status: result.ok ? 200 : 503, headers });
}
