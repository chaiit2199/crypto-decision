import type { Market } from "@/lib/api/types";
import { formatIndicator } from "@/lib/format/market";
import { formatChartTime } from "@/lib/format/chart-time";
import {
    CHART_INDICATORS,
    indicatorReading,
    researchStanceLabel,
    type ResolvedStance,
} from "@/lib/markets/indicator-readings";

type TechnicalIndicatorsProps = {
    market: Market;
    stance: ResolvedStance;
    now: number;
};

export function TechnicalIndicators({
    market,
    stance,
    now,
}: TechnicalIndicatorsProps) {
    const analysis = market.analysis;
    const ready =
        analysis?.status === "ready" &&
        analysis.features.rsi14 !== undefined;
    const stale =
        analysis &&
        (analysis.freshness === "stale" ||
            now >= Date.parse(analysis.valid_until));

    return (
        <section
            className="technical-indicators"
            aria-label="Chỉ báo kỹ thuật dưới biểu đồ"
        >
            <header className="technical-indicators__header">
                <div>
                    <h3>Chỉ báo kỹ thuật</h3>
                    <p>
                        {market.symbol} · {market.quote_asset} · nến 1 giờ đã
                        đóng · {researchStanceLabel(stance)}
                    </p>
                </div>
                {analysis?.features.last_close_time && (
                    <p>
                        Nến nguồn{" "}
                        {formatChartTime(analysis.features.last_close_time)}{" "}
                        (giờ Việt Nam)
                        {stale ? " · bản phân tích đã hết hạn" : ""}
                    </p>
                )}
            </header>

            {!ready && (
                <p className="technical-indicators__empty" role="status">
                    Chưa có chỉ báo 1 giờ từ phân tích. Cần Jev/đồng bộ nến đủ
                    lịch sử — không suy diễn giá trị giả.
                </p>
            )}

            {ready && analysis && (
                <dl className="technical-indicators__list">
                    {CHART_INDICATORS.map(({ key, name, description }) => (
                        <div key={key}>
                            <dt>{name}</dt>
                            <dd
                                className="technical-indicators__value"
                                title={analysis.features[key] ?? undefined}
                            >
                                {formatIndicator(analysis.features[key])}
                            </dd>
                            <dd>{description}</dd>
                            <dd className="technical-indicators__reading">
                                {indicatorReading(
                                    key,
                                    analysis.features,
                                    market.latest_price?.price,
                                    stance,
                                )}
                            </dd>
                        </div>
                    ))}
                </dl>
            )}
        </section>
    );
}
