import Link from "next/link";

import { GoldDeskShell } from "@/components/markets/gold-desk";
import { getMarketMonitor } from "@/lib/api/markets";

export const dynamic = "force-dynamic";

export default async function GoldPage() {
    const result = await getMarketMonitor();

    return (
        <main className="page-shell">
            <header className="page-shell__nav">
                <Link href="/">Crypto Decision</Link>
                <span aria-current="page">Vàng USD</span>
            </header>
            <GoldDeskShell
                initialResult={result}
                initialTime={result.checked_at}
            />
        </main>
    );
}
