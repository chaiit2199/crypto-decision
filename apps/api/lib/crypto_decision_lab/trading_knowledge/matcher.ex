defmodule CryptoDecisionLab.TradingKnowledge.Matcher do
  @moduledoc "Deterministic AND entry/confirmation and OR invalidation; unknown data never matches."
  alias CryptoDecisionLab.TradingKnowledge.{Canonical, Snapshot, Validator}
  alias Decimal, as: D
  @groups ~w(entry_conditions confirmation_conditions invalidation_conditions)
  @version "strategy-matcher-v1"

  @spec match(map(), map(), DateTime.t()) :: {:ok, map()} | {:error, term()}
  def match(strategy, snapshot, now) do
    with :ok <- Validator.validate(strategy) do
      max_age = strategy["risk_constraints"]["max_data_age_seconds"]
      valid = Snapshot.validate(snapshot, now, max_age) == :ok

      relevant =
        valid and snapshot["timeframe"] == strategy["timeframe"] and
          snapshot["regime"] in strategy["regimes"]

      conditions =
        Map.new(@groups, fn group ->
          {group, Enum.map(strategy[group], &evaluate(&1, snapshot, now, max_age))}
        end)

      matched =
        relevant and
          Enum.all?(
            conditions["entry_conditions"] ++ conditions["confirmation_conditions"],
            &(&1["result"] == "matched")
          ) and
          Enum.all?(conditions["invalidation_conditions"], &(&1["result"] == "unmatched"))

      {:ok,
       %{
         "strategy_id" => strategy["strategy_id"],
         "version" => strategy["version"],
         "engine_version" => @version,
         "decision_at" => DateTime.to_iso8601(now),
         "snapshot_hash" => Canonical.hash(snapshot),
         "data_valid" => valid,
         "relevant" => relevant,
         "matched" => matched,
         "conditions" => conditions,
         "validation_status" => strategy["validation"]["status"],
         "eligible" => false
       }}
    end
  end

  defp evaluate(condition, snapshot, now, max_age) do
    left = Snapshot.feature(snapshot, condition["left"]["feature"], now, max_age)

    right =
      case condition["right"] do
        %{"feature" => name} -> Snapshot.feature(snapshot, name, now, max_age)
        %{"value" => value} -> Snapshot.decimal(value)
      end

    result =
      case {left, right} do
        {{:ok, left}, {:ok, right}} ->
          comparison = D.compare(left, right)

          matches =
            case condition["operator"] do
              "gt" -> comparison == :gt
              "gte" -> comparison != :lt
              "lt" -> comparison == :lt
              "lte" -> comparison != :gt
              "eq" -> comparison == :eq
            end

          if matches, do: "matched", else: "unmatched"

        _ ->
          "unknown"
      end

    Map.merge(condition, %{
      "result" => result,
      "actual_left" => value(left),
      "actual_right" => value(right)
    })
  end

  defp value({:ok, value}), do: D.to_string(value, :normal)
  defp value(_), do: nil
end
