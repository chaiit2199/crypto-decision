import { z } from "zod";

import { getTradingResult } from "@/lib/api/trading";
import { planSchema, tradingStyleSchema, workbenchSchema } from "@/lib/api/trading-types";

export const dynamic = "force-dynamic";
const headers = { "Cache-Control": "no-store" };
const requestSchema = z.object({
    symbol: z.string().regex(/^[A-Z0-9]{1,30}$/),
    exchange: z.enum(["binance", "coinbase", "gold_api"]),
    style: tradingStyleSchema.default("intraday"),
});

export async function GET(request: Request) {
    const params = new URL(request.url).searchParams;
    const parsed = requestSchema.safeParse({
        symbol: params.get("symbol") ?? "BTCUSDT",
        exchange: params.get("exchange") ?? "binance",
        style: params.get("style") ?? "intraday",
    });
    if (!parsed.success) {
        return Response.json({ ok: false, message: "Thị trường hoặc phong cách không hợp lệ." }, { status: 400, headers });
    }
    const { symbol, exchange, style } = parsed.data;
    const query = new URLSearchParams({ exchange, style });
    const result = params.get("view") === "scanner"
        ? await getTradingResult(`/api/opportunities?${query}`, z.array(workbenchSchema))
        : await getTradingResult(`/api/markets/${symbol}/workbench?${query}`, workbenchSchema);
    return Response.json(result, { status: result.ok ? 200 : 503, headers });
}

export async function POST(request: Request) {
    let body: unknown;
    try {
        body = await request.json();
    } catch {
        return Response.json({ ok: false, message: "Nội dung không hợp lệ." }, { status: 400, headers });
    }
    const parsed = requestSchema.extend({
        equity: z.string().max(72),
        risk_percent: z.string().max(72),
        entry: z.string().max(72),
        stop_loss: z.string().max(72),
        take_profit: z.string().max(72),
        fee_percent: z.string().max(72),
        slippage_percent: z.string().max(72),
    }).safeParse(body);
    if (!parsed.success) {
        return Response.json({ ok: false, message: "Vui lòng điền đủ thông số mô phỏng." }, { status: 400, headers });
    }
    const result = await getTradingResult(`/api/markets/${parsed.data.symbol}/plan`, planSchema, parsed.data);
    return Response.json(result, { status: result.ok ? 200 : 400, headers });
}
