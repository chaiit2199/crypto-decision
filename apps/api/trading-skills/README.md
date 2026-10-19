# Crypto Decision - 200 Trading Skills (Research Candidates)

**200 distinct structured candidate configurations** = 20 setup archetypes x 10 confirmation variants. They are synthesized technical-analysis hypotheses, NOT 200 independently validated profitable skills. No backtest or historic outcomes have been run. **All evidence.status = unvalidated**.

## Contents

- `trading_skills_200.json`: consolidated catalog with exactly 200 strategies.
- `skills/TS-XX-YY.json`: each individual strategy.
- `condition_registry.json`: mapping from condition labels to feature/operator/threshold.

## Data & feature contract

Feature inputs come from completed Binance spot 1H/4H candles. Calculate all features without look-ahead. `previous` and `_previous` refer to completed bars before the signal bar. For crossing operators, compare current vs preceding completed bars. Values of `volume_ratio20` use current complete bar volume divided by mean of **previous 20 completed bars**. `return_minus_btc_20bars_pct` = 20-bar close-to-close percentage return of asset less BTC for same completed interval (meaningless for BTCUSDT itself, so mark unavailable). `atr_pct14` = 100*ATR14/close. `close_to_ema20_abs_pct` = 100*abs(close-ema20)/ema20. Bollinger: 20 period SMA +/- 2 standard deviations. Donchian/resistance20/support20 previous: extrema of prior 20 complete bars, excluding current. `htf_regime` is a precomputed bullish/bearish/sideways descriptor using **fully closed** higher-timeframe candles only. `bullish_rejection`/`bearish_rejection` and confirmed swings must be precisely formalized, versioned, and tested before enabling these rules. OBV uses close and volume; ADX14 uses Wilder smoothing.

## Critical deployment rules

1. Do NOT feed all 200 records to Jev. Evaluate numeric conditions in code and select a small relevant subset (e.g. 3-5) to summarize into the Jev state.
2. Missing/incomplete features => NO_DATA, not false/true. Unvalidated skills should NOT trigger real-money trading.
3. Rules in `short` direction are observations to avoid/exit spot long positions, not exchange order instructions. No margin/short execution is implied.
4. Market-regime labels are contextual, not hard-filters unless separately configured.
5. `invalidation` should be checked on future completed candles, not used as a tautological immediate entry condition.
6. Backtest chronologically, include fees/slippage, compare with simple baselines, out-of-sample/walk-forward, account for multiple testing and correlated strategies.
7. You may want to prune near-equivalent strategies once empirically measured. The 10 variants per setup intentionally test different confirmations, not 200 unrelated trading philosophies.
8. Entry/stop/target fields are **templates**, and `1.5 ATR` and `2R` are arbitrary research defaults, not optimal values.
9. `source_type: synthesized_rule_hypothesis` means these records are an original, normalized catalog of common concepts, not verified statements by a named professional trader.

## Sources for concepts (not proofs of effectiveness)

- https://www.fidelity.com/learning-center/trading-investing/technical-analysis/what-is-technical-analysis
- https://www.fidelity.com/learning-center/trading-investing/technical-analysis/technical-indicator-guide
- https://github.com/binance/binance-spot-api-docs

## Suggested Jev workflow

Price OHLCV -> feature engine -> deterministic rule matcher -> summary of matched candidates + contradictory evidence -> Jev structured choice/score/noul -> deterministic risk policy -> backtest + outcome logging.
