defmodule CryptoDecisionLab.Trading.Plan do
  @moduledoc "Decimal-only long Spot scenario arithmetic, with explicit constant-notional cost assumptions."
  alias CryptoDecisionLab.MarketData.Parser
  alias Decimal, as: D
  @fields ~w(equity risk_percent entry stop_loss take_profit fee_percent slippage_percent)

  @spec calculate(map()) :: {:ok, map()} | {:error, atom()}
  def calculate(input) when is_map(input) do
    with {:ok, values} <- parse(input), :ok <- validate(values) do
      %{
        "equity" => equity,
        "risk_percent" => risk,
        "entry" => entry,
        "stop_loss" => stop,
        "take_profit" => target,
        "fee_percent" => fee,
        "slippage_percent" => slip
      } = values

      side_cost = D.div(D.add(fee, slip), 100)
      total_cost = D.mult(side_cost, 2)
      loss_fraction = D.add(D.div(D.sub(entry, stop), entry), total_cost)
      profit_fraction = D.sub(D.div(D.sub(target, entry), entry), total_cost)
      budget = D.div(D.mult(equity, risk), 100)
      notional = D.min(D.div(budget, loss_fraction), D.div(equity, D.add(1, side_cost)))

      {:ok,
       %{
         "equity" => decimal(equity),
         "risk_percent" => decimal(risk),
         "entry" => decimal(entry),
         "stop_loss" => decimal(stop),
         "take_profit" => decimal(target),
         "fee_percent" => decimal(fee),
         "slippage_percent" => decimal(slip),
         "risk_budget" => decimal(budget),
         "notional" => decimal(notional),
         "quantity" => decimal(D.div(notional, entry)),
         "net_loss" => decimal(D.mult(notional, loss_fraction)),
         "net_profit" => decimal(D.mult(notional, profit_fraction)),
         "estimated_total_cost_pct" => decimal(D.mult(total_cost, 100)),
         "estimated_cost" => decimal(D.mult(notional, total_cost)),
         "risk_reward_ratio" => decimal(D.div(profit_fraction, loss_fraction)),
         "execution_allowed" => false,
         "cost_model" => "constant-notional-v1"
       }}
    end
  end

  def calculate(_), do: {:error, :invalid_plan}

  defp parse(input) do
    Enum.reduce_while(@fields, {:ok, %{}}, fn field, {:ok, acc} ->
      case Parser.decimal(input[field]) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
        _ -> {:halt, {:error, :invalid_plan}}
      end
    end)
  end

  defp validate(v) do
    if D.positive?(v["equity"]) and D.compare(v["equity"], "1000000000") != :gt and
         D.positive?(v["risk_percent"]) and D.compare(v["risk_percent"], 5) != :gt and
         D.positive?(v["stop_loss"]) and D.compare(v["entry"], v["stop_loss"]) == :gt and
         D.compare(v["take_profit"], v["entry"]) == :gt and
         Enum.all?(
           ~w(fee_percent slippage_percent),
           &(D.compare(v[&1], 0) != :lt and D.compare(v[&1], 5) != :gt)
         ),
       do: :ok,
       else: {:error, :invalid_plan}
  end

  defp decimal(value), do: value |> D.normalize() |> D.to_string(:normal)
end
