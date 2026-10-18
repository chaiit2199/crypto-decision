defmodule CryptoDecisionLab.TradingKnowledge.Policy do
  @moduledoc "Deterministic research decision gates; model classification can never authorize execution."
  alias CryptoDecisionLab.TradingKnowledge.{ContextBuilder, Matcher, Snapshot}
  alias CryptoDecisionLab.Decisions.JevProvider
  alias Decimal, as: D

  @spec decide(map(), map(), map() | nil, map(), DateTime.t()) :: map()
  def decide(candidate, snapshot, response, risk_input, now) do
    with {:ok, match} <- Matcher.match(candidate.version.document, snapshot, now),
         true <- match["data_valid"] do
      cond do
        not ContextBuilder.verified?(candidate, now) -> result("WAIT", "strategy_ineligible")
        not match["matched"] -> result("WAIT", "conditions_not_matched")
        true -> decide_matched(candidate.version.document, response, risk_input, now)
      end
    else
      _ -> result("NO_DATA", "invalid_snapshot_or_strategy")
    end
  end

  defp decide_matched(strategy, response, risk, now) do
    with {:ok, risk_result} <- assess_risk(strategy, risk, now),
         {:ok, response} <- JevProvider.decode({:ok, %{status: 200, body: response}}),
         true <- agrees?(strategy["action"], response["answers"]) do
      Map.merge(result(strategy["action"], "eligible_research_signal"), risk_result)
    else
      {:error, reason} -> result("WAIT", to_string(reason))
      {:error, _, _} -> result("NO_DATA", "invalid_model_classification")
      false -> result("WAIT", "model_disagrees")
    end
  end

  @spec assess_risk(map(), map(), DateTime.t()) :: {:ok, map()} | {:error, atom()}
  def assess_risk(strategy, input, now) do
    constraints = strategy["risk_constraints"]

    with {:ok, at} <- Snapshot.time(input["observed_at"]),
         {:ok, available} <- Snapshot.time(input["available_at"]),
         true <-
           DateTime.compare(at, available) != :gt and DateTime.compare(available, now) != :gt,
         true <- DateTime.diff(now, at, :microsecond) in 0..90_000_000,
         {:ok, equity} <- Snapshot.decimal(input["equity"]),
         {:ok, price} <- Snapshot.decimal(input["price"]),
         {:ok, volume} <- Snapshot.decimal(input["quote_volume_24h"]),
         {:ok, volatility} <- Snapshot.decimal(input["absolute_return_1h_percent"]),
         {:ok, position} <- Snapshot.decimal(input["position_quantity"]),
         true <-
           D.compare(equity, 0) == :gt and D.compare(price, 0) == :gt and
             D.compare(position, 0) != :lt,
         true <- D.compare(volume, constraints["min_quote_volume"]) != :lt,
         true <-
           D.compare(volatility, 0) != :lt and
             D.compare(volatility, constraints["max_absolute_return_1h_percent"]) != :gt,
         true <- strategy["action"] != "SELL" or D.compare(position, 0) == :gt do
      limits = Application.get_env(:crypto_decision_lab, :knowledge_risk_limits, [])

      max_risk =
        D.min(constraints["max_risk_fraction"], Keyword.get(limits, :max_risk_fraction, "0.01"))

      max_allocation =
        D.min(
          constraints["max_allocation_fraction"],
          Keyword.get(limits, :max_allocation_fraction, "0.1")
        )

      loss_budget = D.mult(equity, max_risk)

      notional =
        D.min(
          D.div(loss_budget, constraints["stop_loss_fraction"]),
          D.mult(equity, max_allocation)
        )

      quantity = D.div(notional, price)
      quantity = if strategy["action"] == "SELL", do: D.min(quantity, position), else: quantity

      {:ok,
       %{
         "quantity" => decimal(quantity),
         "max_loss" =>
           decimal(D.mult(D.mult(quantity, price), constraints["stop_loss_fraction"])),
         "stop_price" => decimal(D.mult(price, D.sub(1, constraints["stop_loss_fraction"]))),
         "take_profit_price" =>
           decimal(D.mult(price, D.add(1, constraints["take_profit_fraction"])))
       }}
    else
      _ -> {:error, :risk_constraints_failed}
    end
  end

  defp agrees?("BUY", answers),
    do:
      answers["trend"]["choice"] == "BULLISH" and answers["momentum"]["choice"] == "STRENGTHENING" and
        answers["volatility"]["choice"] == "NORMAL"

  defp agrees?("SELL", answers),
    do:
      answers["trend"]["choice"] == "BEARISH" and answers["momentum"]["choice"] == "WEAKENING" and
        answers["volatility"]["choice"] == "NORMAL"

  defp result(decision, reason),
    do: %{
      "decision" => decision,
      "reason" => reason,
      "policy_version" => "knowledge-policy-v1",
      "execution_allowed" => false
    }

  defp decimal(value), do: D.to_string(value, :normal)
end
