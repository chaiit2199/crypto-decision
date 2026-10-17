import { MarketMonitor } from "@/components/markets/market-monitor";
import { getMarketMonitor } from "@/lib/api/markets";

export const dynamic = "force-dynamic";

export default async function HomePage() {
    const result = await getMarketMonitor();
    return <MarketMonitor initialResult={result} initialTime={result.checked_at} />;
}
