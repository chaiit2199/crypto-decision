# Strategy library v1

Schema: [strategy.schema.json](strategy.schema.json). Every file in `strategies/` is an original, illustrative **unvalidated research hypothesis**. None has a measured success rate or confidence estimate. Thresholds are not fitted or recommended. All operate on Binance Spot USDT, closed 1H features; SELL means exiting an existing holding.

| Strategy file | Hypothesis | Principal limitation |
| --- | --- | --- |
| [ema_trend_continuation.v1.json](strategies/ema_trend_continuation.v1.json) | Price above aligned EMA20/50 with RSI ≥ 50 | Trend lag and whipsaws |
| [ema_pullback_recovery.v1.json](strategies/ema_pullback_recovery.v1.json) | Pullback below EMA20 but above EMA50 | Does not prove recovery or a crossover |
| [rsi_range_rebound.v1.json](strategies/rsi_range_rebound.v1.json) | RSI below 35 and positive hourly return in a range | Range breakdown |
| [rsi_range_exit.v1.json](strategies/rsi_range_exit.v1.json) | RSI above 65 and a negative hour | Can exit a persistent trend early |
| [positive_return_continuation.v1.json](strategies/positive_return_continuation.v1.json) | Positive daily and hourly returns | Reversal after momentum extremes |
| [bearish_trend_exit.v1.json](strategies/bearish_trend_exit.v1.json) | Price below a bearish EMA structure | Exit after losses have already occurred |
| [momentum_fade_exit.v1.json](strategies/momentum_fade_exit.v1.json) | Weakening RSI and negative hour within an uptrend | Regime lag and temporary pullbacks |
| [range_mean_reversion.v1.json](strategies/range_mean_reversion.v1.json) | Below-average price with RSI 25–45 in a range | No guarantee of mean reversion |
| [moderate_momentum_entry.v1.json](strategies/moderate_momentum_entry.v1.json) | RSI 50–65 and bullish EMA structure | Arbitrary thresholds and lag |
| [daily_drawdown_exit.v1.json](strategies/daily_drawdown_exit.v1.json) | Daily return below −4% and price below EMA50 | Asset-specific volatility differs |

Each file documents provenance, rationale, entry/confirmation/invalidation conditions, risk constraints and limitations. Conditions have globally unique IDs within each document. Entry and confirmation are AND groups; invalidation is OR. Unknown input blocks a match. The regime definition and internal API are documented in [Trading Knowledge Engine](../../../../docs/trading-knowledge-engine.md).

Import through `CryptoDecisionLab.TradingKnowledge.import_directory/0`; duplicate identical versions are idempotent, conflicting edits are rejected. Put changed content in a new version/file. Effective reviewed eligibility lives in append-only evidence records; imported author status is never silently rewritten.
