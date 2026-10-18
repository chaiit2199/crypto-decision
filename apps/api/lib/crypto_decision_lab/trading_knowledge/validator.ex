defmodule CryptoDecisionLab.TradingKnowledge.Validator do
  @moduledoc "Structural and semantic validation; untrusted imports cannot self-certify performance."
  alias CryptoDecisionLab.TradingKnowledge.Schema
  alias Decimal, as: D
  @groups ~w(entry_conditions confirmation_conditions invalidation_conditions)
  @units %{
    "close" => :price,
    "ema20" => :price,
    "ema50" => :price,
    "rsi14" => :rsi,
    "return_1h_percent" => :percent,
    "return_24h_percent" => :percent
  }

  @spec validate(term()) :: :ok | {:error, term()}
  def validate(document) do
    with :ok <- Schema.validate(document) do
      conditions = Enum.flat_map(@groups, &document[&1])
      ids = Enum.map(conditions, & &1["id"])
      risk = document["risk_constraints"]

      errors =
        []
        |> check(length(ids) == length(Enum.uniq(ids)), :duplicate_condition_ids)
        |> check(Enum.all?(conditions, &compatible?/1), :incompatible_operands)
        |> check(
          Enum.all?(
            ~w(max_risk_fraction max_allocation_fraction stop_loss_fraction take_profit_fraction),
            &(D.compare(risk[&1], 0) == :gt and D.compare(risk[&1], 1) != :gt)
          ),
          :invalid_risk_fraction
        )
        |> check(D.compare(risk["stop_loss_fraction"], 1) == :lt, :invalid_stop_distance)
        |> check(D.compare(risk["min_reward_risk"], 1) != :lt, :invalid_reward_risk)
        |> check(
          D.compare(
            risk["take_profit_fraction"],
            D.mult(risk["stop_loss_fraction"], risk["min_reward_risk"])
          ) != :lt,
          :insufficient_reward_risk
        )
        |> check(D.compare(risk["min_quote_volume"], 0) == :gt, :invalid_liquidity)
        |> check(
          D.compare(risk["max_absolute_return_1h_percent"], 0) == :gt,
          :invalid_volatility_limit
        )
        |> check(
          document["validation"] == %{
            "status" => "unvalidated",
            "eligibility" => "research_only",
            "evidence_ids" => []
          },
          :unsupported_validation_claim
        )

      if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
    end
  end

  defp check(errors, true, _), do: errors
  defp check(errors, false, reason), do: [reason | errors]

  defp compatible?(%{"left" => %{"feature" => left}, "right" => %{"feature" => right}}),
    do: @units[left] == @units[right] and left != right

  defp compatible?(%{"left" => %{"feature" => left}, "right" => %{"value" => value}}) do
    case @units[left] do
      :price -> D.compare(value, 0) == :gt
      :rsi -> D.compare(value, 0) != :lt and D.compare(value, 100) != :gt
      :percent -> true
    end
  end
end
