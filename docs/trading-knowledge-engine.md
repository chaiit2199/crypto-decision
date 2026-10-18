# Trading Knowledge Engine

## Scope and architecture

This user-requested extension adds research infrastructure beyond Phase 1. It does not submit orders. Binance collection and the existing five-minute research monitor remain independent. Existing monitor labels are not strategy-eligible policy decisions.

Implementation order: (1) schema, examples, immutable storage; (2) point-in-time matching; (3) bounded verified context and deterministic policy; (4) chronological evaluation and lineage. Each increment requires offline ExUnit coverage. Examples are hypotheses, not trading recommendations or evidence of profitability.

| Boundary                                              | Responsibility                                                                                                   |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `TradingKnowledge`                                    | Import, version history, evidence and decision persistence; public context                                       |
| `TradingKnowledge.Schema` / `Validator`               | Strict JSON shape and semantic contracts                                                                         |
| `TradingKnowledge.Matcher`                            | Decimal comparisons against point-in-time snapshots, with per-condition explanations                             |
| `TradingKnowledge.ContextBuilder`                     | Select relevant, explicitly eligible versions with verified evidence available at decision time; bounded payload |
| `TradingKnowledge.Policy`                             | Data, eligibility, risk and model agreement gates; never execution permission                                    |
| `TradingKnowledge.Evaluation`                         | Same chronological samples and costs for indicator, knowledge and Jev arms; outcome/calibration reporting        |
| Existing `Decisions.DecisionProvider` / `JevProvider` | Official TypeSafe choice classification contract; injected mock in tests                                         |

No strategy text is executable code. No `eval`, SQL expressions, arbitrary functions, remote schema references or dynamic atoms. DSL v1 uses AND for entry and confirmation conditions, OR for invalidation. Missing operands produce `unknown`, which blocks eligibility including unknown invalidation. Numeric values are finite decimal strings; thresholds and feature comparisons share units. All examples use only existing hourly EMA20/50, RSI14, close and returns. SELL means exit an existing Spot position, never short.

## Storage relationships (ERD)

| Parent                        | Child                         | Cardinality / invariant                                                                    |
| ----------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------ |
| `knowledge_strategies`        | `knowledge_strategy_versions` | 1:N; unique strategy/version, immutable JSON and SHA-256                                   |
| `knowledge_strategy_versions` | `knowledge_backtest_evidence` | 1:N; immutable evidence bound to exact version and dataset/split/config hashes             |
| `market_symbols`              | `knowledge_matches`           | 1:N; snapshot, evaluation time, condition results and version FK                           |
| `knowledge_strategy_versions` | `knowledge_matches`           | 1:N; no floating latest-version references                                                 |
| `knowledge_matches`           | `knowledge_ai_decisions`      | 1:N; model classification separate from policy decision, context and raw response retained |
| `knowledge_ai_decisions`      | `knowledge_realized_outcomes` | 1:N; unique horizon; strictly future, observation time and costs retained                  |

Audit tables are append-only via PostgreSQL triggers (UPDATE/DELETE/TRUNCATE rejected). Referential deletion is restricted. Import is atomic and idempotent for identical canonical JSON; reuse of a version with changed content fails. Canonical representation recursively sorts object keys; arrays retain order. It is an application encoding, not RFC 8785. Content changes create a new version; evidence cannot silently alter a document. Import accepts only `unvalidated` status, `research_only` eligibility and no evidence claims. Effective eligibility is a separate append-only operator review of exact-version evidence; callers cannot self-certify an imported file.

## Snapshot / internal API contract v1

No new public HTTP endpoints. `TradingKnowledge.import_file/1`, `import_directory/1` and `history/1` are manual operations. `Matcher.match/3` takes a validated strategy, snapshot and UTC decision time. Snapshot fields: `symbol`, `timeframe`, `regime`, `as_of`, `available_at`, `feature_version`, `dataset_hash`, `features`. Each feature is `{value: decimal-string, observed_at: UTC, available_at: UTC}`. Both observation and availability must be no later than decision time and no later than the snapshot envelope. Freshness is checked against the strategy limit; an unknown regime, timeframe mismatch, future or missing data fails closed. Historical replay must use archived availability timestamps, never today's rolling ticker or latest-price snapshots.

Matching preserves entry, confirmation and invalidation results, including unknown/matched/unmatched states, separately from strategy eligibility. No look-ahead: future outcomes never enter the input snapshot or Jev state. Strategy publication/import and evidence completion times also constrain live eligibility. Retrospective research on newly authored hypotheses is explicitly not a historical deployment simulation.

## Jev and policy

Reuse the existing provider abstraction and response validation. Official references: [OpenAPI](https://api.typesafe.ai/openapi.json), [quick start](https://docs.typesafe.ai/introduction/quickstart), checked 2026-10-18. Bearer authorization, GET `/v1/models`, POST `/v1/systemone`, JSON `model/state/questions`, named choice answers and model/usage metadata are the boundary. No OpenAI API or credentials are involved.

Context contains only necessary feature values, condition results and verified evidence metadata, not prose from provenance or entire library documents. Versions without reviewed evidence, disabled versions, future, irrelevant and unknown-feature strategies are excluded. An empty verified selection returns a structured error and does not call the model. Input size is a conservative local UTF-8 byte budget over the complete serialized request, not an asserted token count. Model limits must be checked against the official contract; long-context/image opt-in is not enabled. Record requested and returned model identity. Model confidence is classification confidence only, not probability of profit.

Policy independently requires valid fresh inputs, fully matched entry/confirmation, no invalidation, verified exact-version evidence, explicit research eligibility and allowed risk parameters. Enforce stop distance, reward/risk, maximum loss, allocation, liquidity and volatility using Decimal; SELL additionally requires an existing position. Any failed gate produces WAIT or NO_DATA. All results remain `execution_allowed=false`.

## Evaluation protocol

Chronological train/validation/test boundaries are explicit UTC instants with non-overlap and purging: a sample's exit/outcome must lie inside its split. Strategies/parameters are frozen before test evaluation. All three arms use identical sample IDs, entry/exit observations, missing-data exclusions, fees and slippage. Entry occurs strictly after decision time; long Spot trades only. SELL exits, never creates a short. A basic fixed-horizon non-overlapping experiment reports net returns, trade count, drawdown and sample coverage. No production execution or intrabar fill accuracy is implied.

Record dataset hash, feature version, strategy IDs/versions/hashes, split/config hashes, requested/returned model versions, exact inputs, decisions, costs and future labels. For historical Jev evaluation, model training contamination is unknown; label results retrospective, not proof of out-of-sample model training. Calibrate explicitly supplied held-out profit probabilities separately using Brier score and reliability bins; absent calibrated probabilities remain null. Model choice confidence is never used as the calibration input. Test fixtures are synthetic and cannot promote evidence or imply strategy success.

## Acceptance and limits

- Ten separate JSON documents validate structurally and semantically; all `unvalidated`, no win rate or confidence claims.
- Invalid operators, fields, units, dates, duplicate condition IDs, unsupported versions, unsafe risk limits and status promotions are rejected.
- Import preserves immutable version history under concurrent conflict; DB constraints and rollback are exercised on a separate test database.
- Matching is deterministic with exact decimals; missing/stale/future observations and availability block use.
- Context and policy cannot turn an unvalidated rule or model-only label into an eligible decision.
- Evaluation cannot leak future outcomes to providers and uses equal splits/costs across arms.
- Run format, warnings-as-errors compile, ExUnit and migration smoke checks. Report any unavailable checks; never report synthetic backtest results as real evidence.

## Implemented increment and operation

The code provides the library, matcher, context/policy gates, manual decision persistence, paired evaluator, outcome storage, and calibration metric calculation. It reuses the existing Jev provider and test mock. It does not automatically change the five-minute monitor or schedule new model calls. The existing monitor's BUY/SELL labels retain their earlier research-only meaning.

### Import and version history

From `apps/api` with the target database environment configured:

```sh
MARKET_SYNC_ENABLED=false JEV_ENABLED=true mix ecto.migrate
MARKET_SYNC_ENABLED=false JEV_ENABLED=true mix run -e 'IO.inspect(CryptoDecisionLab.TradingKnowledge.import_directory())'
```

Call `TradingKnowledge.history("ema_trend_continuation")` to inspect immutable versions. Changing a rule requires a new positive integer `version` and a new JSON file; never edit an already imported version. The schema uses JSON Schema 2020-12. The local validator implements only the closed vocabulary used by this schema and rejects unknown schema keywords; it is not a general-purpose JSON Schema package. Duplicate JSON keys and files over 64 KiB are rejected. Decimal threshold strings support 18 fractional places; computed feature strings allow 38 to retain existing Decimal indicator precision.

The initial JSON's `validation` is the author's status at import and stays `unvalidated` forever for that version. Effective status is derived from separate append-only evidence and operator review records. `TradingKnowledge.evaluate/5` writes an unvalidated report. `review_evidence(id, reviewer, "eligible" | "disabled")` appends an attestation; it does not rewrite the authored document. It requires observed-data lineage, at least 30 test samples, at least one knowledge-rule action and a recorded requested model. Those minimums are review prerequisites, **not statistical proof of success**. Synthetic evidence cannot be reviewed into eligibility. Review means an operator inspected reproducibility and limitations; it does not assert that returns will persist. A later disabled review takes precedence. Operators must verify source-data authenticity; a caller-supplied `data_kind` string cannot establish authenticity on its own.

### Snapshot, context and policy calls

`Snapshot.from_candles(records, symbol, decision_at)` requires 300 entries shaped `%{candle: candle, available_at: archived_timestamp}`. It uses existing indicator code and rejects gaps, open candles and observations unavailable at decision time. It hashes the exact price/volume inputs and archived availability. Existing mutable Binance candles do not themselves provide historical availability or revision history; supply a preserved dataset. Do not infer it from current database contents.

Regime v1: compute `(EMA20 / EMA50 - 1) * 100`. Absolute separation at most 0.5% means `range`; otherwise EMA20 above/below EMA50 means `uptrend`/`downtrend`. This deterministic convention is versioned, illustrative and unvalidated.

`TradingKnowledge.analyze(symbol_id, version_ids, snapshot, risk_input, options)` runs manually. Risk input requires decimal strings for `equity`, `price`, `quote_volume_24h`, `absolute_return_1h_percent`, `position_quantity`, plus UTC `observed_at`/`available_at`. Risk observations expire after 90 seconds. Application defaults cap loss fraction at 0.01 and allocation at 0.1; `:knowledge_risk_limits` can configure tighter/different explicit limits. Strategy limits are also enforced. Position sizing is research arithmetic; exchange lot size and actual fills are outside this increment.

By default context selects at most four relevant reviewed versions, ordered with fully matched candidates first, and caps the **complete request** at 12,000 UTF-8 bytes. It trims whole strategies, never individual conditions. Live analysis additionally requires `model_limits: %{model: model_name, max_input_tokens: verified_limit, source: official_documentation_url, count_tokens: exact_tokenizer_function}`. The application does **not** supply a made-up limit or approximate tokenizer. The official OpenAPI checked on 2026-10-18 exposes no numeric context window or tokenizer; live knowledge requests therefore return a persisted WAIT with `model_limits_unverified` until this contract is supplied. No danger-zone headers are sent. Tests inject clearly labelled synthetic budgets.

Manual knowledge calls share the existing Jev advisory lock and provider cooldown, preventing simultaneous requests from this path and the monitor. Provider failure persists NO_DATA and sanitized error metadata. Repeated manual calls are separate decision attempts; matches are idempotent by version/symbol/time/snapshot. A crash after an upstream response but before commit can cause a paid request to repeat; exactly-once external calls are not claimed.

### Evaluation and outcomes

`TradingKnowledge.evaluate(version_id, samples, splits, costs, options)` accepts chronological non-overlapping samples containing `id`, `snapshot`, `decision_at`, `entry_at`, `exit_at`, `observed_at`, `entry_price`, `exit_price`. Splits require `train_start`, `train_end`, `validation_end`, `test_end`. Entry is strictly after decision time, and label availability must precede the split's end. Invalid samples reject the run instead of silently changing coverage between arms. Supply `fee_bps_per_side` and `slippage_bps_per_side` as decimal strings; costs are assumptions to be estimated from the intended market, not measured liquidity or guaranteed fill costs.

Options require a `provider: fn point_in_time_context -> {:ok, official_choice_response} end`, for example a lookup of archived classifications, and should include `requested_model` and `data_kind`. No default provider or network call is made. A missing/invalid classification rejects the comparison. Unvalidated rules are evaluated locally; they are **never sent as knowledge context**. When no version was independently reviewed and available as of a sample, the callback receives only the feature snapshot and `indicator_only_classification` mode. Reports flag `knowledge_context_used` for each sample, so a feature-only Jev baseline cannot be mistaken for a test of knowledge augmentation. Validated candidates must pass the same point-in-time context selection. A callback that performs live calls must additionally enforce the model budget; prefer archived responses for repeatable offline comparisons.

BUY experiments start in cash. EMA20 above EMA50 is the indicator baseline; matched knowledge conditions are the rule baseline; Jev agreement adds the assisted gate. A selected long return is `exit*(1-cost)/(entry*(1+cost))-1`; WAIT remains cash. SELL experiments start with the same existing Spot holding valued at the sample's entry price: the indicator baseline exits on EMA20 below EMA50, the rule baseline exits on a match, and the assisted baseline requires bearish agreement. Immediate exit pays one exit cost; WAIT holds until the common horizon and then pays that exit cost. SELL experiments do not report a trade win rate because original acquisition basis is unavailable. These normalized, fixed-horizon exposure experiments do not simulate portfolio sizing, intrabar stops, order-book depth, funding or partial fills. They cannot establish live-policy profitability.

Each stored evidence record retains the full paired report: exact inputs, condition results, requested/returned model IDs, raw classifications, chronological split identifiers, assumed costs and future price labels. The evaluator reports compounding return, maximum drawdown, coverage and action counts; entry-experiment win rates are calculated from actual supplied samples. It never writes these results back into strategy JSON or auto-promotes a rule. No observed-market evaluation has been run as part of this implementation.

`TradingKnowledge.record_outcome(decision_id, attrs)` records a unique forward-return label per horizon, rejects future/unobserved data and computes the net label from explicit prices/costs. It is not an executed P&L record. `Evaluation.calibration/1` computes Brier score and reliability bins from separately supplied held-out profit probabilities with a calibrator fitted before the decision. It does not train a calibrator, accept model classification confidence as a substitute, or claim observed calibration when labels/probabilities are absent.

`TradingKnowledge.record_calibration(evidence_id, samples)` appends a new unvalidated evidence record with stored calibration metrics and calibrator versions. Samples require `sample_id`, `profit_probability`, `calibrator_version`, and `calibrator_fitted_at`. Coverage must include every held-out assisted BUY exactly once; labels are derived from the stored net outcomes rather than accepted from the caller. The prior report remains immutable. This records evaluation of an externally fitted calibrator; it does not create one or grant eligibility.

## Verification performed on 2026-10-18

- `mix precommit`: 88 tests, 0 failures, including 29 new knowledge-engine tests; no live HTTP calls.
- `mix format --check-formatted` and `mix compile --warnings-as-errors`: passed.
- New migration applied, rolled back, and reapplied successfully on an isolated temporary PostgreSQL 14 instance using `crypto_knowledge_test`; development database and existing volumes were not modified.
- Coverage includes ten-file import, duplicate JSON keys, semantic/risk rejection, immutable version conflicts, database mutation protection, Decimal matching, missing/stale/future features, archived candle availability, context eligibility/budgets, risk/model separation, shared cooldown, paired costs/splits, exit-only SELL semantics, outcome uniqueness, and persisted calibration labels.
- Live Jev knowledge requests, real-market backtest results and empirical strategy validation were not run. No example was promoted.
