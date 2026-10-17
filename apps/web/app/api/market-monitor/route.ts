import { getMarketMonitor } from "@/lib/api/markets";

export const dynamic = "force-dynamic";

export async function GET() {
    const result = await getMarketMonitor();
    return Response.json(result, {
        status: result.ok ? 200 : 503,
        headers: { "Cache-Control": "no-store" },
    });
}
