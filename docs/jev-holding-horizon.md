# Jev holding-horizon classification

Extends the existing hourly Jev research slot. Remains decision-support only: no order placement and no calibrated profit probability.

## Intent

Ask System One to classify which **research holding style** best matches the observable multi-timeframe structure already computed by the backend:

| Choice | Intended research use |
| --- | --- |
| `SCALP` | Minutes; 15m/5m structure dominates |
| `INTRADAY` | Roughly 30 minutes to several hours; 4H context with 15m/5m setup |
| `SWING` | Multi-day; 1D and 4H structure aligned |
| `UNSUITABLE` | Conflict, elevated volatility, or insufficient higher-timeframe data |

This is **not** a forecast that long-term or short-term investing will be profitable.

## Contract changes

- New choice question `holding_horizon` alongside `trend`, `momentum`, `volatility`.
- Signal policy for BUY/SELL/WAIT is unchanged and still ignores `holding_horizon`.
- Feature state may include `context_timeframes` with per-frame status, regime, ATR%, and EMA structure. Missing frames stay explicit (`no_data`); never invented.
- Workbench exposes:
  - `holding_horizon` from a fresh ready Jev answer when present
  - `horizon_deterministic` from closed-candle gates (independent of Jev)
- Model confidence is never shown as win probability.
- Configuration version: `hourly-research-v4-horizon`

## Deterministic gate (independent of Jev)

Evaluated from stored closed candles only:

1. Elevated ATR% on the candidate frame → `UNSUITABLE`
2. Complete 1D + 4H with bullish EMA alignment → `SWING`
3. Complete 4H + 15m with bullish 4H alignment → `INTRADAY`
4. Complete 15m + 5m only → `SCALP`
5. Otherwise → `UNSUITABLE`

Jev may disagree; UI shows both. Eligibility / execution permission is never granted by either label.

## Out of scope

- Changing Cron frequency solely for horizon
- Promoting styles from historical expectancy without separate validation
- Using Coinbase short candles as if they were Binance 5m/15m books

## Verification (2026-10-19)

- `mix format`, `mix compile --warnings-as-errors`
- `mix test` workbench + decisions: 28 tests, 0 failures (`DB_PORT=5432`)
- Covers question contract, decode rejection without `holding_horizon`,
  deterministic SCALP/INTRADAY/SWING/UNSUITABLE gates, and `context_timeframes` enrichment
- `npx tsc --noEmit` and ESLint on changed web files passed
- Signal BUY/SELL/WAIT policy remains independent of horizon
- Do not claim observed-market edge from horizon labels
