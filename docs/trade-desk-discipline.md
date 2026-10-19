# Trade Desk Discipline — Priority 1

Personal Spot research desk for discretionary holds of roughly 30 minutes to several hours. Extends the existing Trading Workbench. No order execution.

## Goals

1. One Binance Spot USDT decision surface by default.
2. Explicit checklist before any entry / stop / target levels are treated as actionable research.
3. Cost-aware plan with entry zone and TP1 / TP2 / TP3 from observable ATR and book levels.
4. Order-book metrics that distinguish visible depth bands from price-action zones.
5. Keep `execution_allowed=false`, `profit_probability=null`, `strategy_validation=UNVALIDATED`.

## Reused modules

- `MarketData.Liquidity` / `LiquiditySnapshot` — same-snapshot depth; no Coinbase book.
- `Trading.Plan` — Decimal sizing; primary `take_profit` remains the R:R gate target (TP2).
- `Trading.Assessment` — deterministic gates and ATR scenario plan.
- `Trading.workbench` / opportunities / Next `TradingWorkbench` UI.

## Contract additions (additive)

Workbench / opportunity reports add:

- `trade_eligibility`: `NO_DATA` | `WAIT` | `RESEARCH_CANDIDATE`
- `missing_requirements`: gate codes that still block research candidacy (excludes permanent research labels)
- `liquidity.spread_bps`, `liquidity.mid_price`, `liquidity.bands` (0.1 / 0.25 / 0.5 / 1.0 % around mid)
- Suggested `plan` fields: `entry_min`, `entry_max`, `take_profit_1`, `take_profit_2`, `take_profit_3` (plus existing `take_profit` = TP2 for calculator compatibility)

A large bid wall is not labelled support. Bands use quote notional. Zero denominator imbalance stays unavailable.

## Out of scope for this increment

- `aggTrades` persistence, historical depth tables, BOS/CHoCH/order-block engines
- Live Jev question redesign, strategy promotion, calibrated probabilities
- Public mutation endpoints or exchange order placement

## Acceptance

- Offline ExUnit for band math, eligibility labels, multi-TP plan fields
- Frontend Zod accepts additive fields; desk defaults to USDT
- Format / compile / targeted tests; do not claim observed-market edge

## Verification (2026-10-19)

- `mix format --check-formatted` and `mix compile --warnings-as-errors` passed.
- `mix test test/crypto_decision_lab/trading/workbench_test.exs`: 13 tests, 0 failures (local Postgres `DB_PORT=5432`; Compose port 5433 was not running). Includes depth band math, multi-TP plan fields, eligibility labels, and liquidity insert microsecond coercion.
- `npx tsc --noEmit` and targeted ESLint on changed web files passed.
- Playwright trading-workbench specs were not executed successfully in this environment (Chrome launch aborted). Do not treat UI browser behaviour as runtime-verified here.
