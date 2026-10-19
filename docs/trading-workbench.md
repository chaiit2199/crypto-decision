# Trading workbench - Spot research v1

Requested expansion on 2026-10-19 follows the supplied audit (P0–P3). Existing Phase 1, hourly Jev and Trading Knowledge remain the foundations. No order execution or Futures integration is introduced.

## Architecture and delivery order

1. P0: identity-bound Binance liquidity snapshots; deterministic cost-aware Spot planning and risk gates.
2. P1: durable 5m/15m candles, UTC session VWAP, EMA9/21, ATR%, levels, volume delta and multi-timeframe setups.
3. P2: read-only workbench and opportunity scanner combining these facts with existing Jev classifications and JSON strategy matches. Model confidence is not a profit probability. Missing forecasts remain null.
4. P3: chronological replay and paper simulation sharing the same stop/target/cost arithmetic; persist reports and simulated trades for inspection. Synthetic tests do not validate strategies.

Backend modules: `MarketData` owns collection; `TechnicalAnalysis` owns candle mathematics; `Trading` owns reports, planning, scanner and simulations. HTTP controllers only validate/dispatch. Frontend fetches through Next server routes, validates with Zod, and displays status, assumptions and one-line indicator descriptions.

## Storage / ERD

- `market_symbols` 1:N `market_candles`, unique symbol/timeframe/open time; add 5m and 15m to interval constraints.
- `market_symbols` 1:N `market_sync_states`, independent checkpoint per timeframe/type.
- `market_symbols` 1:1 `market_liquidity_snapshots`: latest bounded order book, server/fetched timestamps and update ID. No historical liquidity is invented for replay.
- `market_symbols` 1:N `trading_simulations`: immutable report JSON with exact inputs, configuration, trades and dataset hash; simulation only, no execution.

## Synchronization

Existing hourly history stays unchanged. Short candles bootstrap 30 days (5m) / 90 days (15m), 1000 rows per job batch with durable resume. Jobs dispatch every minute, fetch closed bars with five-second margin and overlap, validate spacing, and never advance a checkpoint past a detected internal gap. Short-history requests share the existing collector lock, cooldown and weight budget. Reads never trigger upstream calls.

Liquidity jobs collect 100 depth levels per active Binance symbol at most once per minute, with a 90-second freshness limit. Spread and imbalance use the same depth response, avoiding a bookTicker/depth race. A 100-level book can be insufficient for sizing; partial fills are rejected. USD/Coinbase and XAU do not borrow Binance liquidity. UTC server response time is a freshness proxy; REST depth has no matching-engine timestamp and is not a guaranteed executable quote.

Official contract checked: [Binance public market data](https://developers.binance.com/docs/binance-spot-api-docs/rest-api/market-data-endpoints). Depth limit 100 costs weight 5; klines support 5m/15m with limit 1000 and weight 2. Existing transport handles HTTP errors, 418/429, Retry-After and shared cooldown.

## Contracts

### Workbench usability update

The detail workbench always includes a same-market `1h` reference in `frames`, even
when the selected style uses 4h/15m/5m. It is computed from stored closed candles,
independently of Jev; adding this reference does not change the style's risk gates
or the scanner workload. No storage changes or migrations are needed.

The UI shows one indicator timeframe at a time, initially choosing an available
frame, with values and one-line explanations visible. Missing, stale and unsupported
data have explicit explanations. Coinbase short candles and order books remain
unsupported by the current collectors; hourly reference indicators do not substitute
for missing entry/setup data. Diagnostic flags and simulation history are collapsed.

The hypothetical Spot calculator separates capital/risk from entry/stop/target;
fees and slippage are editable in a collapsed section with the assumptions visible
in its summary. Copying a fresh current price is an explicit action; refreshes never
overwrite user inputs. Changing research style preserves the form, while changing
market resets it. Results prioritize position value and net loss/profit; further
calculation details remain expandable. Acceptance covers unavailable data, visible
hourly indicators with Jev disabled, cost editing, result invalidation, market
identity and form persistence across style changes.

Verification for this usability update: TypeScript and targeted ESLint passed;
both Playwright workbench tests passed using synthetic responses, including the
390px layout and Coinbase hourly indicators with Jev disabled. Backend compile
with warnings-as-errors passed. The related backend suite ran 15 tests with one
failure in existing liquidity timestamp storage (`:utc_datetime_usec` rejects the
HTTP date's second precision); the new hourly-reference test passed. Full
`mix precommit` ran 135 tests with eight failures: that liquidity error plus seven
asset-count, polling-interval and freshness expectation mismatches already noted
below. Tests ran on isolated PostgreSQL at port 55439; no VPS data was accessed.

`GET /api/markets/:symbol/workbench?exchange=binance&style=intraday`: bounded stored-data report; styles scalping (1h/15m/5m), intraday (4h/15m/5m), swing (1d/4h/1h). Explicit exchange/symbol/quote/spot identity, cutoff, per-timeframe status/features, liquidity, setup, Jev assessment, null uncalibrated forecasts, research-only eligibility and risk flags.

`GET /api/opportunities?exchange=binance&style=intraday`: bounded active universe sorted by readiness and net reward/risk; missing/stale rows remain visible with reasons. These are research candidates, never execution approval.

`POST /api/markets/:symbol/plan`: pure simulation with decimal-string equity, risk percent, entry, stop, target, fee and slippage per side. No database mutation or upstream call. Enforce finite decimals, positive capital, stop < entry < target, caps and net reward/risk. Return risk budget, quantity/notional, fees, net loss/profit and cost-adjusted ratio. These inputs are assumptions, not live fills.

Replay/paper operations are internal context functions, not public write endpoints. Existing Trading Knowledge paired evaluator remains the path for archived Jev/baseline comparisons and evidence review. No live inference is triggered by UI reads.

## Mathematics and gates

Long Spot only. Risk = position notional × (stop distance percent + two-sided fee/slippage percent). Reward = notional × (target distance percent − two-sided fee/slippage percent). This conservative constant-notional cost approximation matches the audit calculator; position notional also respects available cash including entry cost. Configuration is returned in reports. Spread/depth walk is reported separately; do not silently mix it into user-entered slippage or double count it.

VWAP uses summed quote/base volume from a complete UTC session of closed candles; absent/zero volume or gaps produce null. Levels use prior 20 candles excluding the signal candle. Breakout/retest/pullback conditions are deterministic research heuristics, versioned and unvalidated. Higher timeframe windows require all source candles. EMA/RSI warmup needs 300 bars. No synthetic prices fill holes.

Eligibility requires fresh same-market observations, full timeframes, trend agreement, confirmed setup, adequate book depth, bounded spread/volatility and net reward/risk. Unvalidated strategy always blocks execution. Expected move and profit probability remain null until independently estimated and calibrated.

## Acceptance

Verify decimal arithmetic (including the audit's 1000 / 0.5% / 1% / 2% / 0.1% / 0.05% example), invalid plans, depth exhaustion, stale/future snapshots, missing candles, closed-bar confirmation, checkpoint resume, independent timeframes, idempotency, same-market isolation, no model-confidence promotion, no look-ahead, stop-first ambiguous bars and net fees. Run backend format/compile/ExUnit, migration smoke on isolated test PostgreSQL, frontend TypeScript/lint and relevant UI checks. Record actual results and any unimplemented portions below at completion.

## Implemented operation

Apply migrations before starting the revised API. Existing `MARKET_SYNC_ENABLED=true` now schedules a minute dispatcher for Binance depth and short candles; historical short-candle jobs have lower priority than snapshots. They share the existing rate budget. Workbench price freshness and report `valid_until` follow `MarketData.price_max_age_seconds/0` (poll interval + 60s, currently ~360s with a five-minute poll). Liquidity depth still uses a 90-second freshness window because depth jobs run about once per minute. Jev on the workbench only shows a live signal when `JEV_ENABLED=true` and the latest `market_analyses` row is `ready` within the analysis slot; otherwise `ai_signal` is `NO_DATA` with an `ai_reason` such as `jev_disabled`, `insufficient_candles`, or `analysis_not_run`.

The UI now includes the workbench, style selection, 5m/15m Binance chart choices, scanner, one-line explanations, decimal calculator and summaries of the last 20 stored simulations. Jev labels identify research candidates; they do not imply eligibility. Depth is limited to 100 price levels. Coinbase/XAU cannot use a Binance snapshot. Calculator requests are pure computations and do not open paper positions.

Research assumptions are configured with `config :crypto_decision_lab, :trading_limits`: `equity`, `risk_percent`, `fee_percent`, `slippage_percent`, `max_spread_percent`, `max_atr_percent`, `min_reward_risk` as finite decimal strings. Defaults are illustrative, not optimized. ATR scenario uses a 1.5 ATR stop and 3 ATR target. Forecast move/profit probability remain null. The deterministic setup remains UNVALIDATED even when its technical filters pass; baseline replay does not validate this different setup.

### Manual replay and paper scenarios

Use an authenticated local IEx session (`iex -S mix` with the intended database config). No public mutation endpoint exists for these operations. Import the existing JSON library with `CryptoDecisionLab.TradingKnowledge.import_directory()` to display its hourly matches; imported examples remain research-only and unvalidated.

```elixir
config = %{
  "equity" => "1000", "risk_percent" => "0.5",
  "stop_percent" => "1", "target_percent" => "2",
  "fee_percent" => "0.1", "slippage_percent" => "0.05",
  "parameters_frozen_at" => "2026-10-01T00:00:00Z",
  "test_from" => "2026-10-02T00:00:00Z", "test_to" => "2026-10-10T00:00:00Z"
}
CryptoDecisionLab.Trading.replay("BTCUSDT", %{"exchange" => "binance", "timeframe" => "5m"}, config)
```

Dates are examples; choose an available dataset and genuinely frozen parameters. Replay requires warmup plus 302–10,000 consecutive bars, strict pre-test parameter freeze, closed historical bars, one position at a time and entry strictly after the decision cutoff. Both stop/target touched in a bar resolves stop first; gap below a stop uses the worse opening price. Output includes each trade, fees, net return, expectancy, win rate, closed-trade drawdown and an equal-period buy-and-hold benchmark. Drawdown excludes intratrade mark-to-market losses and is labelled accordingly. Current candle revisions are not an archived point-in-time dataset. No observed-market evaluation or strategy promotion has been run.

For chronological train/validation/test comparison of rule-only, indicator-only and Jev-assisted arms, use the existing `TradingKnowledge.evaluate/5` protocol documented in `trading-knowledge-engine.md`; the new simple EMA9/21 replay is explicitly not a Jev evaluation. Walk-forward research requires separate frozen configurations and non-overlapping test windows; there is no automatic parameter optimizer.

```elixir
# Obtain the exact Binance market ID; never reuse a Coinbase ID or quote currency.
{:ok, market, _} = CryptoDecisionLab.MarketData.get_market("BTCUSDT", %{"exchange" => "binance"})
# Replace illustrative price levels with your explicit research scenario.
input = %{"equity" => "1000", "risk_percent" => "0.5", "stop_loss" => "99",
  "take_profit" => "102", "fee_percent" => "0.1", "slippage_percent" => "0.05"}
{:ok, position} = CryptoDecisionLab.Trading.Paper.open(market.id, input)
# After a newer fresh book arrives:
CryptoDecisionLab.Trading.Paper.close(position.id)
```

Paper open derives entry from the current ask, requires full depth and checks slippage. Manual close uses a newer fresh bid snapshot, rejects duplicate closes and records net P&L under stated cost assumptions. It does not run automatic stops, model fills while offline, or manage a shared portfolio balance across independent scenarios. Reports are append-only; this is research arithmetic, not an execution simulator. No UI write controls are exposed without access protection.

### Verification state

- Earlier intermediate backend compile with warnings-as-errors passed; initial migration applied on isolated `crypto_workbench_test` at localhost:55439.
- Initial full ExUnit run: 120 tests, 8 failures. One gap test asserted the previous behavior (saving across a gap); updated to assert atomic rejection followed by repair. Seven other failures concern existing assumptions: 32 versus current 31 assets, two-minute versus configured five-minute polling, and 180 versus 360 seconds freshness. Baseline execution was not permitted, so these are source-inspected mismatches, not a verified clean baseline comparison.
- New offline tests cover the calculator example, invalid inputs, depth exhaustion/cooldown, short-candle checkpoints, gaps/closure, VWAP, market isolation, research gates, paper lifecycle, replay timing/costs and REST contracts. Execution of the new tests was declined at the permission prompt. Latest backend changes and append-only migration additions therefore remain unverified at runtime.
- No live Binance/Jev verification, observed-market backtest, empirical calibration or strategy validation is claimed.
- Latest static verification: `mix format --check-formatted`, `npx tsc --noEmit`, targeted ESLint and `git diff --check` passed. Browser tests were authored but not run. Full `mix precommit`, final warnings-as-errors compile and migration rollback/reapply were not completed after test execution permission was declined; do not treat the current increment as runtime-verified.

- SCSS compilation and Tailwind utility expansion also passed using the installed local toolchain; generated CSS was written only to `/tmp`.
