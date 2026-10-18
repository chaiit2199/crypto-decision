defmodule CryptoDecisionLab.TradingKnowledge.Evaluation do
  @moduledoc "Paired, non-overlapping fixed-horizon Spot research. Synthetic inputs never constitute verified evidence."
  alias CryptoDecisionLab.TradingKnowledge.{
    Canonical,
    ContextBuilder,
    Matcher,
    Snapshot,
    Validator
  }

  alias CryptoDecisionLab.Decisions.JevProvider
  alias Decimal, as: D
  @arms ~w(indicator_only knowledge_rules jev_assisted)

  @doc "All arms share samples and costs. A provider gets only the point-in-time snapshot and rule explanations, never outcomes."
  @spec run([map()], map(), map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(samples, strategy, splits, costs, options \\ []) do
    with :ok <- Validator.validate(strategy),
         {:ok, boundaries} <- boundaries(splits),
         {:ok, cost} <- cost_fraction(costs),
         :ok <- validate_samples(samples, boundaries, strategy),
         true <- Keyword.get(options, :data_kind, "synthetic") in ~w(synthetic observed),
         provider when is_function(provider, 1) <- options[:provider] do
      rows = Enum.map(samples, &evaluate(&1, strategy, boundaries, cost, provider, options))

      if Enum.any?(rows, &match?({:error, _}, &1)) do
        {:error, :provider_failed_comparison_incomplete}
      else
        rows = Enum.map(rows, fn {:ok, row} -> row end)

        metrics =
          Map.new(~w(train validation test), fn split ->
            subset = Enum.filter(rows, &(&1["split"] == split))
            {split, Map.new(@arms, &{&1, summarize(subset, &1)})}
          end)

        {:ok,
         %{
           "engine_version" => "paired-fixed-horizon-v1",
           "status" => "unvalidated",
           "data_kind" => Keyword.get(options, :data_kind, "synthetic"),
           "strategy_hash" => Canonical.hash(strategy),
           "strategy_id" => strategy["strategy_id"],
           "strategy_version" => strategy["version"],
           "dataset_hash" => Canonical.hash(samples),
           "split_hash" => Canonical.hash(splits),
           "configuration_hash" =>
             Canonical.hash(%{
               "costs" => costs,
               "splits" => splits,
               "strategy_hash" => Canonical.hash(strategy)
             }),
           "feature_version" => "hourly-v1",
           "costs" => costs,
           "splits" => splits,
           "sample_count" => length(rows),
           "metrics" => metrics,
           "rows" => rows,
           "calibration" => nil,
           "calibration_reason" =>
             "No held-out calibrated profit probabilities supplied; model classification confidence is not a profit probability.",
           "limitations" => [
             "Fixed-horizon long-only research; no intrabar stop fill or portfolio execution simulation.",
             "Historical model training contamination is unknown.",
             "Rules must be frozen before test inspection; synthetic data cannot validate profitability."
           ]
         }}
      end
    else
      false -> {:error, :invalid_data_kind}
      nil -> {:error, :provider_required}
      error -> error
    end
  end

  defp boundaries(splits) do
    with {:ok, start} <- Snapshot.time(splits["train_start"]),
         {:ok, train_end} <- Snapshot.time(splits["train_end"]),
         {:ok, validation_end} <- Snapshot.time(splits["validation_end"]),
         {:ok, test_end} <- Snapshot.time(splits["test_end"]),
         true <-
           DateTime.compare(start, train_end) == :lt and
             DateTime.compare(train_end, validation_end) == :lt and
             DateTime.compare(validation_end, test_end) == :lt do
      {:ok, [start, train_end, validation_end, test_end]}
    else
      _ -> {:error, :invalid_chronological_splits}
    end
  end

  defp cost_fraction(costs) do
    with {:ok, fee} <- Snapshot.decimal(costs["fee_bps_per_side"]),
         {:ok, slip} <- Snapshot.decimal(costs["slippage_bps_per_side"]),
         true <- D.compare(fee, 0) != :lt and D.compare(slip, 0) != :lt,
         cost = D.div(D.add(fee, slip), 10_000),
         true <- D.compare(cost, 1) == :lt do
      {:ok, cost}
    else
      _ -> {:error, :invalid_costs}
    end
  end

  defp validate_samples([], _, _), do: {:error, :empty_samples}

  defp validate_samples(samples, boundaries, strategy) do
    ids = Enum.map(samples, & &1["id"])

    valid =
      Enum.all?(samples, fn sample ->
        with {:ok, at} <- Snapshot.time(sample["decision_at"]),
             {:ok, entry_at} <- Snapshot.time(sample["entry_at"]),
             {:ok, exit_at} <- Snapshot.time(sample["exit_at"]),
             {:ok, observed_at} <- Snapshot.time(sample["observed_at"]),
             {:ok, entry} <- Snapshot.decimal(sample["entry_price"]),
             {:ok, exit} <- Snapshot.decimal(sample["exit_price"]),
             true <- D.compare(entry, 0) == :gt and D.compare(exit, 0) == :gt,
             true <-
               DateTime.compare(at, entry_at) == :lt and
                 DateTime.compare(entry_at, exit_at) == :lt and
                 DateTime.compare(exit_at, observed_at) != :gt,
             true <- not is_nil(split(at, observed_at, boundaries)),
             :ok <-
               Snapshot.validate(
                 sample["snapshot"],
                 at,
                 strategy["risk_constraints"]["max_data_age_seconds"]
               ) do
          is_binary(sample["id"]) and sample["id"] != ""
        else
          _ -> false
        end
      end)

    nonoverlapping =
      samples
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.all?(fn [a, b] ->
        with {:ok, exit} <- Snapshot.time(a["exit_at"]),
             {:ok, at} <- Snapshot.time(b["decision_at"]) do
          DateTime.compare(exit, at) == :lt
        else
          _ -> false
        end
      end)

    if valid and nonoverlapping and length(ids) == length(Enum.uniq(ids)),
      do: :ok,
      else: {:error, :invalid_or_leaking_samples}
  end

  defp split(at, exit_at, [start, train_end, validation_end, test_end]) do
    [
      {"train", start, train_end},
      {"validation", train_end, validation_end},
      {"test", validation_end, test_end}
    ]
    |> Enum.find_value(fn {name, lower, upper} ->
      if DateTime.compare(at, lower) != :lt and DateTime.compare(exit_at, upper) == :lt, do: name
    end)
  end

  defp evaluate(sample, strategy, boundaries, cost, provider, options) do
    {:ok, now} = Snapshot.time(sample["decision_at"])
    {:ok, exit_at} = Snapshot.time(sample["exit_at"])
    snapshot = sample["snapshot"]
    {:ok, match} = Matcher.match(strategy, snapshot, now)
    # Unvalidated rules stay in the deterministic baseline and are never sent to Jev.
    input =
      case ContextBuilder.build(Keyword.get(options, :candidates, []), snapshot, now, options) do
        {:ok, context} -> context
        {:error, _} -> %{"snapshot" => snapshot, "mode" => "indicator_only_classification"}
      end

    with {:ok, response} <- provider.(input),
         {:ok, response} <- JevProvider.decode({:ok, %{status: 200, body: response}}) do
      features = snapshot["features"]
      selling = strategy["action"] == "SELL"

      indicator =
        D.compare(features["ema20"]["value"], features["ema50"]["value"]) ==
          if(selling, do: :lt, else: :gt)

      knowledge = match["matched"]
      answers = response["answers"]
      trend = if selling, do: "BEARISH", else: "BULLISH"
      momentum = if selling, do: "WEAKENING", else: "STRENGTHENING"

      assisted =
        knowledge and answers["trend"]["choice"] == trend and
          answers["momentum"]["choice"] == momentum and
          answers["volatility"]["choice"] == "NORMAL"

      net =
        D.sub(
          D.div(
            D.mult(sample["exit_price"], D.sub(1, cost)),
            D.mult(sample["entry_price"], D.add(1, cost))
          ),
          1
        )

      arms =
        Map.new(Enum.zip(@arms, [indicator, knowledge, assisted]), fn {arm, active} ->
          # SELL experiments begin with a common existing holding valued at entry_price.
          # Immediate liquidation pays one exit cost; WAIT holds until the common horizon.
          arm_return =
            cond do
              selling and active ->
                D.negate(cost)

              selling ->
                D.sub(
                  D.div(D.mult(sample["exit_price"], D.sub(1, cost)), sample["entry_price"]),
                  1
                )

              active ->
                net

              true ->
                D.new(0)
            end

          {arm,
           %{
             "decision" => if(active, do: strategy["action"], else: "WAIT"),
             "net_return" => decimal(arm_return)
           }}
        end)

      {:ok,
       %{
         "id" => sample["id"],
         "split" => split(now, exit_at, boundaries),
         "decision_at" => sample["decision_at"],
         "input" => input,
         "rule_match" => match,
         "knowledge_context_used" => Map.has_key?(input, "strategies"),
         "requested_model" => Keyword.get(options, :requested_model),
         "initial_position" => if(selling, do: "existing_spot_holding", else: "cash"),
         "input_hash" => Canonical.hash(input),
         "model" => response["model"],
         "classification" => response["answers"],
         "raw_response" => response,
         "outcome" => Map.take(sample, ~w(entry_at exit_at observed_at entry_price exit_price)),
         "arms" => arms
       }}
    else
      _ -> {:error, :invalid_provider_response}
    end
  end

  defp summarize(rows, arm) do
    trades = Enum.filter(rows, &(get_in(&1, ["arms", arm, "decision"]) in ["BUY", "SELL"]))
    entry_experiment = Enum.all?(rows, &(&1["initial_position"] == "cash"))

    {equity, _, drawdown} =
      Enum.reduce(rows, {D.new(1), D.new(1), D.new(0)}, fn row, {equity, peak, drawdown} ->
        equity = D.mult(equity, D.add(1, get_in(row, ["arms", arm, "net_return"])))
        peak = D.max(peak, equity)
        drawdown = D.max(drawdown, D.div(D.sub(peak, equity), peak))
        {equity, peak, drawdown}
      end)

    wins = Enum.count(trades, &(D.compare(get_in(&1, ["arms", arm, "net_return"]), 0) == :gt))

    %{
      "sample_count" => length(rows),
      "trade_count" => length(trades),
      "net_return" => decimal(D.sub(equity, 1)),
      "max_drawdown" => decimal(drawdown),
      "win_rate" =>
        if(trades == [] or not entry_experiment,
          do: nil,
          else: decimal(D.div(wins, length(trades)))
        )
    }
  end

  @doc "Brier and fixed reliability bins for separately calibrated held-out profit probabilities, never Jev choice confidence."
  @spec calibration([map()]) :: {:ok, map()} | {:error, atom()}
  def calibration([]), do: {:error, :no_calibration_samples}

  def calibration(samples) do
    valid =
      Enum.all?(samples, fn row ->
        with {:ok, p} <- Snapshot.decimal(row["profit_probability"]),
             true <- D.compare(p, 0) != :lt and D.compare(p, 1) != :gt,
             true <- row["profitable"] in [true, false],
             true <- row["split"] == "test",
             {:ok, fitted} <- Snapshot.time(row["calibrator_fitted_at"]),
             {:ok, decision} <- Snapshot.time(row["decision_at"]),
             true <- DateTime.compare(fitted, decision) == :lt do
          true
        else
          _ -> false
        end
      end)

    if valid do
      score =
        Enum.reduce(samples, D.new(0), fn row, sum ->
          delta = D.sub(row["profit_probability"], if(row["profitable"], do: 1, else: 0))
          D.add(sum, D.mult(delta, delta))
        end)
        |> D.div(length(samples))

      bins =
        for index <- 0..9 do
          rows =
            Enum.filter(samples, fn row ->
              min(D.to_integer(D.round(D.mult(row["profit_probability"], 10), 0, :floor)), 9) ==
                index
            end)

          %{
            "lower" => decimal(D.div(index, 10)),
            "count" => length(rows),
            "mean_probability" =>
              if(rows == [],
                do: nil,
                else:
                  decimal(
                    D.div(
                      Enum.reduce(rows, D.new(0), &D.add(&1["profit_probability"], &2)),
                      length(rows)
                    )
                  )
              ),
            "observed_frequency" =>
              if(rows == [],
                do: nil,
                else: decimal(D.div(Enum.count(rows, & &1["profitable"]), length(rows)))
              )
          }
        end

      {:ok,
       %{
         "sample_count" => length(samples),
         "brier_score" => decimal(score),
         "reliability_bins" => bins
       }}
    else
      {:error, :invalid_or_in_sample_calibration}
    end
  end

  defp decimal(value), do: D.to_string(value, :normal)
end
