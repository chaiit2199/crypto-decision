import { z } from "zod";

const decimal = z.string().regex(/^-?\d+(\.\d+)?$/);
const timestamp = z.iso.datetime({ offset: true });
export const tradingStyleSchema = z.enum(["scalping", "intraday", "swing"]);
export type TradingStyle = z.infer<typeof tradingStyleSchema>;

export const planSchema = z.object({
    entry: decimal,
    stop_loss: decimal,
    take_profit: decimal,
    equity: decimal,
    risk_percent: decimal,
    fee_percent: decimal,
    slippage_percent: decimal,
    risk_budget: decimal,
    notional: decimal,
    quantity: decimal,
    net_loss: decimal,
    net_profit: decimal,
    estimated_total_cost_pct: decimal,
    estimated_cost: decimal,
    risk_reward_ratio: decimal,
    execution_allowed: z.literal(false),
    cost_model: z.literal("constant-notional-v1"),
});
export type TradePlan = z.infer<typeof planSchema>;
export type PlanInput = Pick<TradePlan,
    "equity" | "risk_percent" | "entry" | "stop_loss" | "take_profit" | "fee_percent" | "slippage_percent"
>;

export const workbenchSchema = z.object({
    symbol: z.string(),
    exchange: z.string(),
    quote_asset: z.string(),
    market: z.enum(["spot", "reference"]),
    style: tradingStyleSchema,
    as_of: timestamp,
    valid_until: timestamp,
    configuration_version: z.string(),
    timeframes: z.object({ trend: z.string(), setup: z.string(), entry: z.string() }),
    frames: z.record(z.string(), z.object({
        status: z.enum(["ready", "no_data"]),
        reason: z.string().nullable(),
        features: z.object({
            ema9: decimal.optional(),
            ema21: decimal.optional(),
            ema20: decimal.optional(),
            ema50: decimal.optional(),
            ema200: decimal.optional(),
            rsi14: decimal.optional(),
            macd: decimal.optional(),
            macd_signal: decimal.optional(),
            macd_histogram: decimal.optional(),
            atr14: decimal.optional(),
            adx14: decimal.optional(),
            atr_percent: decimal.optional(),
            vwap: decimal.nullable().optional(),
            support: decimal.optional(),
            resistance: decimal.optional(),
            relative_volume20: decimal.nullable().optional(),
            volume_delta: decimal.nullable().optional(),
            last_close_time: timestamp.optional(),
        }),
    })),
    liquidity: z.object({
        status: z.enum(["fresh", "stale", "missing", "unsupported"]),
        reason: z.string().nullable(),
        data_at: timestamp.optional(),
        fetched_at: timestamp.optional(),
        bid: decimal.optional(),
        ask: decimal.optional(),
        spread_percent: decimal.optional(),
        bid_depth: decimal.optional(),
        ask_depth: decimal.optional(),
        imbalance: decimal.optional(),
    }),
    market_regime: z.enum(["BULLISH", "BEARISH", "RANGING_OR_MIXED", "UNKNOWN"]),
    setup: z.string().nullable(),
    setup_quality: z.enum(["CONFIRMED", "UNCONFIRMED"]),
    ai_signal: z.enum(["BUY_CANDIDATE", "EXIT_CANDIDATE", "WAIT", "NO_DATA"]),
    ai_analyzed_at: timestamp.nullable(),
    direction_assessment: z.string().nullable(),
    uncertainty: z.literal("UNCALIBRATED"),
    expected_move: z.null(),
    profit_probability: z.null(),
    strategy_validation: z.literal("UNVALIDATED"),
    execution_allowed: z.literal(false),
    trade_eligibility: z.enum(["WAIT_CONFIRMATION", "NO_DATA"]),
    technical_candidate: z.boolean(),
    risk_flags: z.array(z.string()),
    plan: planSchema.nullable(),
    depth_estimate: z.object({
        buy_average: decimal,
        sell_average: decimal,
        round_trip_slippage_percent: decimal,
    }).nullable(),
    simulations: z.array(z.object({
        id: z.number(),
        kind: z.enum(["replay", "paper"]),
        created_at: timestamp,
        event: z.string().nullable(),
        trade_count: z.number().nullable(),
        net_return_percent: decimal.nullable(),
        net_pnl: decimal.nullable(),
        validation: z.literal("UNVALIDATED"),
    })),
    knowledge_matches: z.array(z.object({
        strategy_id: z.string(),
        version: z.number(),
        matched: z.boolean(),
        data_valid: z.boolean(),
        validation_status: z.string(),
        eligible: z.literal(false),
    })),
});
export type WorkbenchData = z.infer<typeof workbenchSchema>;
export type TradingResult<T> = { ok: true; data: T } | { ok: false; message: string };
