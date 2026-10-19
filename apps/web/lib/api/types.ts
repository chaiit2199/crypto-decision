import { z } from "zod";

const decimal = z.string().regex(/^-?\d+(\.\d+)?$/);
const timestamp = z.iso.datetime({ offset: true });
const freshnessSchema = z.object({
    status: z.enum(["fresh", "stale", "missing"]),
    age_seconds: z.number().nullable(),
    timestamp: timestamp.optional(),
});

const choiceAnswer = <T extends readonly [string, ...string[]]>(choices: T) =>
    z.object({
        type: z.literal("choice"),
        choice: z.enum(choices),
        confidence: z.number().min(0).max(1),
        probabilities: z.record(z.string(), z.number().min(0).max(1)),
    });

const analysisSchema = z.object({
    id: z.number(),
    status: z.enum(["ready", "no_data", "error"]),
    signal: z.enum(["BUY", "SELL", "WAIT", "NO_DATA"]),
    model: z.string().nullable(),
    reason: z.string().nullable(),
    analyzed_at: timestamp,
    valid_until: timestamp,
    data_at: timestamp.nullable(),
    freshness: z.enum(["fresh", "stale"]),
    features: z.object({
        ema20: decimal.optional(),
        ema50: decimal.optional(),
        ema200: decimal.optional(),
        macd: decimal.optional(),
        macd_signal: decimal.optional(),
        macd_histogram: decimal.optional(),
        atr14: decimal.optional(),
        adx14: decimal.optional(),
        relative_volume20: decimal.nullable().optional(),
        return_1h_percent: decimal.optional(),
        return_24h_percent: decimal.optional(),
        rsi14: decimal.optional(),
        last_close_time: timestamp.optional(),
        price_at: timestamp.optional(),
    }),
    answers: z.object({
        trend: choiceAnswer(["BULLISH", "BEARISH", "SIDEWAYS"]).optional(),
        momentum: choiceAnswer(["STRENGTHENING", "WEAKENING", "MIXED"]).optional(),
        volatility: choiceAnswer(["ELEVATED", "NORMAL"]).optional(),
    }),
    risk_result: z.object({ execution_allowed: z.literal(false), mode: z.literal("research_only") }),
}).refine(
    (analysis) => analysis.status !== "ready" ||
        Boolean(analysis.answers.trend && analysis.answers.momentum && analysis.answers.volatility),
    "Ready analysis must include all answers",
);

export type MarketAnalysisData = z.infer<typeof analysisSchema>;

const marketSchema = z.object({
    id: z.number(),
    symbol: z.string(),
    exchange: z.string(),
    base_asset: z.string(),
    quote_asset: z.string(),
    enabled: z.boolean(),
    trading_status: z.string(),
    analysis_enabled: z.boolean(),
    analysis_unavailable_reason: z.string().nullable(),
    price_max_age_seconds: z.number().positive(),
    analysis_interval_seconds: z.number().int().positive(),
    analysis: analysisSchema.nullable(),
    latest_price: z
        .object({
            price: decimal,
            data_at: timestamp.nullable(),
            fetched_at: timestamp,
        })
        .nullable(),
    ticker_stats: z
        .object({
            price_change_percent: decimal,
            high_price: decimal,
            low_price: decimal,
            quote_volume: decimal.nullable(),
            base_volume: decimal,
            fetched_at: timestamp,
        })
        .nullable(),
    price_freshness: freshnessSchema,
    stats_freshness: freshnessSchema,
});

export const marketsSchema = z.object({
    data: z.array(
        z.object({
            id: z.number(),
            symbol: z.string(),
            name: z.string(),
            enabled: z.boolean(),
            availability: z.string(),
            markets: z.array(marketSchema),
        }),
    ),
});

export const statusSchema = z.object({
    data: z.object({
        enabled: z.boolean(),
        price_poll_interval_seconds: z.number().positive(),
        sources: z.record(z.string(), z.object({
            prices_at: timestamp.nullable(),
            stats_at: timestamp.nullable(),
            metadata_at: timestamp.nullable(),
            blocked_until: timestamp.nullable(),
            last_error: z.string().nullable(),
        })),
        configured_assets: z.number(),
        active_symbols: z.number(),
        collector: z
            .object({
                prices_at: timestamp.nullable(),
                stats_at: timestamp.nullable(),
                metadata_at: timestamp.nullable(),
                blocked_until: timestamp.nullable(),
                last_error: z.string().nullable(),
            })
            .nullable(),
        jobs: z.record(z.string(), z.number()),
    }),
});

export type Asset = z.infer<typeof marketsSchema>["data"][number];
export type Market = Asset["markets"][number];
export type MarketStatus = z.infer<typeof statusSchema>["data"];
export type MarketMonitorData = {
    assets: Asset[];
    status: MarketStatus;
};
export type MarketMonitorResult =
    { ok: true; data: MarketMonitorData; checked_at: number } | { ok: false; message: string; checked_at: number };

export const timeframeSchema = z.enum(["5m", "15m", "1h", "4h", "1d"]);
// Canvas rendering needs finite numbers. Keep the original strings in the contract.
const chartDecimal = decimal.refine((value) => Number.isFinite(Number(value)));
const candleSchema = z.object({
    open_time: timestamp,
    close_time: timestamp,
    open: chartDecimal,
    high: chartDecimal,
    low: chartDecimal,
    close: chartDecimal,
    base_volume: chartDecimal,
});

export const candlesSchema = z.object({
    data: z
        .array(candleSchema)
        .refine(
            (candles) =>
                candles.every(
                    (candle, index) =>
                        index === 0 || Date.parse(candle.open_time) > Date.parse(candles[index - 1].open_time),
                ),
            "Chart timestamps must be unique and increasing",
        ),
    meta: z.object({
        timeframe: timeframeSchema,
        count: z.number(),
        availability: z.enum(["available", "missing"]),
        last_close_time: timestamp.nullable(),
        freshness: freshnessSchema,
    }),
});

export type Timeframe = z.infer<typeof timeframeSchema>;
export type Candle = z.infer<typeof candleSchema>;
export type CandlesData = z.infer<typeof candlesSchema>;
export type CandlesResult = { ok: true; data: CandlesData } | { ok: false; message: string };
