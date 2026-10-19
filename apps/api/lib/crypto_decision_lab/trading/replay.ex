defmodule CryptoDecisionLab.Trading.Replay do
  @moduledoc "Bounded chronological Spot baseline replay, conservative intrabar exits and explicit costs."
  alias CryptoDecisionLab.{TechnicalAnalysis, Repo}
  alias CryptoDecisionLab.Trading.{Plan, Simulation}
  alias CryptoDecisionLab.TradingKnowledge.Canonical
  alias Decimal, as: D

  @doc "Replay ordered closed candles. Entry uses a later bar after the feature cutoff and closure margin."
  @spec run([map()], map()) :: {:ok, map()} | {:error, atom()}
  def run(candles, config) when is_list(candles) and length(candles) in 302..10_000 do
    with {:ok, start_at, 0} <- DateTime.from_iso8601(config["test_from"] || ""),
         {:ok, end_at, 0} <- DateTime.from_iso8601(config["test_to"] || ""),
         {:ok, frozen_at, 0} <- DateTime.from_iso8601(config["parameters_frozen_at"] || ""),
         true <-
           DateTime.compare(frozen_at, start_at) == :lt and
             DateTime.compare(start_at, end_at) == :lt,
         true <- DateTime.compare(end_at, CryptoDecisionLab.MarketData.Collector.now()) != :gt,
         {:ok, _} <- plan(config, D.new(100)),
         true <- valid_series?(candles) do
      state =
        Enum.reduce(
          301..(length(candles) - 1),
          %{position: nil, trades: [], cash: D.new(config["equity"])},
          fn index, state ->
            candle = Enum.at(candles, index)

            if DateTime.compare(candle.open_time, start_at) != :lt and
                 DateTime.compare(candle.close_time, end_at) == :lt do
              window = Enum.slice(candles, index - 301, 300)
              decision_at = DateTime.add(List.last(window).close_time, 5001, :millisecond)

              case state.position do
                nil ->
                  with {:ok, f} <-
                         TechnicalAnalysis.features(window, decision_at, candle.timeframe),
                       true <- D.compare(f["ema9"], f["ema21"]) == :gt,
                       {:ok, plan} <-
                         plan(Map.put(config, "equity", decimal(state.cash)), candle.open) do
                    position =
                      Map.merge(plan, %{
                        "entry_at" => DateTime.to_iso8601(candle.open_time),
                        "decision_at" => DateTime.to_iso8601(decision_at),
                        "features" => f
                      })

                    settle(%{state | position: position}, candle)
                  else
                    _ -> state
                  end

                _ ->
                  settle(state, candle)
              end
            else
              state
            end
          end
        )

      eligible =
        Enum.filter(
          candles,
          &(DateTime.compare(&1.open_time, start_at) != :lt and
              DateTime.compare(&1.close_time, end_at) == :lt)
        )

      if eligible == [] do
        {:error, :empty_test_window}
      else
        state =
          if state.position,
            do: close(state, List.last(eligible), List.last(eligible).close, "HORIZON"),
            else: state

        trades = Enum.reverse(state.trades)
        profits = Enum.map(trades, &D.new(&1["net_pnl"]))

        {_, _, drawdown} =
          Enum.reduce(
            profits,
            {D.new(config["equity"]), D.new(config["equity"]), D.new(0)},
            fn pnl, {cash, peak, dd} ->
              cash = D.add(cash, pnl)
              peak = D.max(peak, cash)
              {cash, peak, D.max(dd, D.mult(D.div(D.sub(peak, cash), peak), 100))}
            end
          )

        cost = D.div(D.mult(D.add(config["fee_percent"], config["slippage_percent"]), 2), 100)

        hold =
          D.sub(
            D.div(D.sub(List.last(eligible).close, hd(eligible).open), hd(eligible).open),
            cost
          )

        {:ok,
         %{
           "mode" => "replay",
           "strategy" => "EMA9_ABOVE_EMA21",
           "version" => "spot-replay-v1",
           "configuration" => config,
           "dataset_hash" => Canonical.hash(Enum.map(candles, &candle_input/1)),
           "trades" => trades,
           "trade_count" => length(trades),
           "final_equity" => decimal(state.cash),
           "net_return_percent" =>
             decimal(D.mult(D.sub(D.div(state.cash, config["equity"]), 1), 100)),
           "expectancy" =>
             if(profits == [],
               do: nil,
               else: decimal(D.div(Enum.reduce(profits, D.new(0), &D.add/2), length(profits)))
             ),
           "win_rate" =>
             if(profits == [],
               do: nil,
               else: decimal(D.div(Enum.count(profits, &D.positive?/1), length(profits)))
             ),
           "closed_trade_drawdown_percent" => decimal(drawdown),
           "buy_hold_net_return_percent" => decimal(D.mult(hold, 100)),
           "validation" => "UNVALIDATED",
           "execution_allowed" => false,
           "cost_model" => "constant-notional-v1",
           "limitations" => [
             "CURRENT_CANDLE_REVISIONS",
             "ASSUMED_COSTS",
             "NO_HISTORICAL_DEPTH",
             "NO_INTRABAR_PATH",
             "NOT_JEV_EVALUATION"
           ]
         }}
      end
    else
      _ -> {:error, :invalid_replay}
    end
  end

  def run(_, _), do: {:error, :invalid_replay}

  @doc "Persist a caller-reviewed research run; never promotes strategy evidence."
  @spec save(integer(), [map()], map()) :: {:ok, Simulation.t()} | {:error, term()}
  def save(symbol_id, candles, config) do
    if Enum.all?(candles, &(&1.market_symbol_id == symbol_id)) do
      with {:ok, report} <- run(candles, config) do
        Repo.insert(%Simulation{market_symbol_id: symbol_id, kind: "replay", report: report})
      end
    else
      {:error, :market_mismatch}
    end
  end

  defp plan(config, entry) do
    with {:ok, stop} <- CryptoDecisionLab.MarketData.Parser.decimal(config["stop_percent"]),
         {:ok, target} <- CryptoDecisionLab.MarketData.Parser.decimal(config["target_percent"]),
         true <- D.positive?(stop) and D.compare(stop, 100) == :lt and D.positive?(target) do
      Plan.calculate(
        Map.merge(config, %{
          "entry" => decimal(entry),
          "stop_loss" => decimal(D.mult(entry, D.sub(1, D.div(stop, 100)))),
          "take_profit" => decimal(D.mult(entry, D.add(1, D.div(target, 100))))
        })
      )
    else
      _ -> {:error, :invalid_replay}
    end
  end

  defp valid_series?(candles) do
    frame = hd(candles).timeframe
    width = %{"5m" => 300, "15m" => 900, "1h" => 3600}[frame]
    now = CryptoDecisionLab.MarketData.Collector.now()

    not is_nil(width) and
      Enum.all?(candles, fn c ->
        c.timeframe == frame and DateTime.compare(c.close_time, DateTime.add(now, -5)) == :lt and
          D.positive?(c.low) and D.compare(c.high, c.open) != :lt and
          D.compare(c.high, c.close) != :lt and
          D.compare(c.low, c.open) != :gt and D.compare(c.low, c.close) != :gt and
          D.compare(c.base_volume, 0) != :lt and
          c.market_symbol_id == hd(candles).market_symbol_id and
          rem(DateTime.to_unix(c.open_time), width) == 0 and
          DateTime.diff(c.close_time, c.open_time, :millisecond) == width * 1000 - 1
      end) and
      Enum.all?(Enum.chunk_every(candles, 2, 1, :discard), fn [a, b] ->
        DateTime.diff(b.open_time, a.open_time) == width
      end)
  end

  defp settle(state, candle) do
    p = state.position

    cond do
      D.compare(candle.open, p["stop_loss"]) != :gt ->
        close(state, candle, candle.open, "GAP_STOP")

      D.compare(candle.low, p["stop_loss"]) != :gt ->
        close(state, candle, D.new(p["stop_loss"]), "STOP")

      D.compare(candle.high, p["take_profit"]) != :lt ->
        close(state, candle, D.new(p["take_profit"]), "TARGET")

      true ->
        state
    end
  end

  defp close(state, candle, exit, reason) do
    p = state.position
    pnl = D.sub(D.mult(D.sub(exit, p["entry"]), p["quantity"]), p["estimated_cost"])

    trade =
      Map.merge(p, %{
        "exit_at" => DateTime.to_iso8601(candle.close_time),
        "exit" => decimal(exit),
        "exit_reason" => reason,
        "net_pnl" => decimal(pnl)
      })

    %{state | position: nil, cash: D.add(state.cash, pnl), trades: [trade | state.trades]}
  end

  defp candle_input(c),
    do:
      Map.new(
        [
          :open_time,
          :close_time,
          :open,
          :high,
          :low,
          :close,
          :base_volume,
          :quote_volume,
          :taker_buy_base_volume
        ],
        fn key ->
          value = Map.fetch!(c, key)

          {Atom.to_string(key),
           cond do
             is_nil(value) -> nil
             is_struct(value, DateTime) -> DateTime.to_iso8601(value)
             true -> decimal(value)
           end}
        end
      )

  defp decimal(value), do: value |> D.normalize() |> D.to_string(:normal)
end
