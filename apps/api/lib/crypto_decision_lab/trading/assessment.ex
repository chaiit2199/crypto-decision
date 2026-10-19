defmodule CryptoDecisionLab.Trading.Assessment do
  @moduledoc "Versioned deterministic setup and risk gates, separate from Jev classification."
  alias CryptoDecisionLab.Trading.Plan
  alias CryptoDecisionLab.MarketData.{Liquidity, SnapshotTime}
  alias Decimal, as: D

  @defaults [
    equity: "1000",
    risk_percent: "0.5",
    fee_percent: "0.1",
    slippage_percent: "0.05",
    max_spread_percent: "0.1",
    max_atr_percent: "5",
    min_reward_risk: "1.5"
  ]

  @spec evaluate(map(), map(), map(), map(), DateTime.t()) :: map()
  def evaluate(market, frames, series, liquidity, now) do
    config =
      Keyword.merge(@defaults, Application.get_env(:crypto_decision_lab, :trading_limits, []))

    trend = series[frames["trend"]]
    setup = series[frames["setup"]]
    entry = series[frames["entry"]]
    ready = Enum.all?(Map.values(series), &(&1["status"] == "ready"))
    regime = regime(trend["features"])
    setup_name = if ready, do: setup(setup), else: nil
    confirmed = ready and not is_nil(setup_name) and entry_confirmation(entry["features"])
    plan = build_plan(entry["features"], liquidity, config)
    depth = depth_cost(plan, liquidity)
    price = market.latest_price

    price_fresh =
      not is_nil(price) and SnapshotTime.fresh?(price.data_at || price.fetched_at, now, 90)

    ai = classification(market, now)

    flags =
      []
      |> flag(not market.enabled or market.trading_status != "TRADING", "MARKET_UNAVAILABLE")
      |> flag(not ready, "TIMEFRAME_DATA_MISSING")
      |> flag(not price_fresh, "PRICE_STALE_OR_MISSING")
      |> flag(market.stats_freshness.status != "fresh", "STATS_STALE_OR_MISSING")
      |> flag(liquidity["status"] != "fresh", liquidity["reason"] || "LIQUIDITY_MISSING")
      |> flag(regime != "BULLISH", "TREND_NOT_ALIGNED")
      |> flag(not confirmed, "ENTRY_NOT_CONFIRMED")
      |> flag(is_nil(plan), "PLAN_UNAVAILABLE")
      |> flag(is_nil(depth), "DEPTH_INSUFFICIENT")
      |> flag(
        greater?(liquidity["spread_percent"], config[:max_spread_percent]),
        "SPREAD_TOO_WIDE"
      )
      |> flag(
        greater?(entry["features"]["atr_percent"], config[:max_atr_percent]),
        "VOLATILITY_TOO_HIGH"
      )
      |> flag(
        plan != nil and D.compare(plan["risk_reward_ratio"], config[:min_reward_risk]) == :lt,
        "NET_REWARD_RISK_TOO_LOW"
      )
      |> flag(
        depth != nil and
          greater?(depth["round_trip_slippage_percent"], D.mult(config[:slippage_percent], 2)),
        "SLIPPAGE_EXCEEDS_ASSUMPTION"
      )

    technical_candidate = flags == []
    flags = flags ++ ["BACKTEST_NOT_AVAILABLE", "STRATEGY_UNVALIDATED"]

    %{
      "market_regime" => regime,
      "setup" => setup_name,
      "setup_quality" => if(confirmed, do: "CONFIRMED", else: "UNCONFIRMED"),
      "ai_signal" => ai["signal"],
      "direction_assessment" => ai["direction"],
      "uncertainty" => "UNCALIBRATED",
      "ai_analyzed_at" => ai["analyzed_at"],
      "trade_eligibility" => if(ready and price_fresh, do: "WAIT_CONFIRMATION", else: "NO_DATA"),
      "technical_candidate" => technical_candidate,
      "risk_flags" => flags,
      "plan" => plan,
      "depth_estimate" => depth,
      "configuration" => Map.new(config, fn {k, v} -> {Atom.to_string(k), v} end)
    }
  end

  @doc "Full EMA20 > EMA50 > EMA200 ordering, or its inverse; mixed ordering is not a trend confirmation."
  def regime(%{"ema20" => a, "ema50" => b, "ema200" => c}) do
    cond do
      D.compare(a, b) == :gt and D.compare(b, c) == :gt -> "BULLISH"
      D.compare(a, b) == :lt and D.compare(b, c) == :lt -> "BEARISH"
      true -> "RANGING_OR_MIXED"
    end
  end

  def regime(_), do: "UNKNOWN"

  defp setup(row) do
    f = row["features"]

    cond do
      D.compare(row["previous_close"], row["previous_resistance"]) == :gt and
        D.compare(row["last_low"], row["previous_resistance"]) != :gt and
          D.compare(f["close"], row["previous_resistance"]) == :gt ->
        "RETEST"

      D.compare(f["close"], f["resistance"]) == :gt ->
        "BREAKOUT"

      D.compare(f["ema9"], f["ema21"]) == :gt and D.compare(row["last_low"], f["ema21"]) != :gt and
          D.compare(f["close"], f["ema21"]) == :gt ->
        "PULLBACK"

      true ->
        nil
    end
  end

  defp entry_confirmation(f) do
    f["relative_volume20"] != nil and D.compare(f["relative_volume20"], 1) != :lt and
      D.compare(f["ema9"], f["ema21"]) == :gt and D.compare(f["close"], f["ema9"]) == :gt
  end

  defp build_plan(%{"atr14" => atr}, %{"status" => "fresh", "ask" => ask}, config) do
    if D.positive?(D.new(atr)) do
      input =
        Map.new(
          Keyword.take(config, [:equity, :risk_percent, :fee_percent, :slippage_percent]),
          fn {k, v} -> {Atom.to_string(k), v} end
        )

      input =
        Map.merge(input, %{
          "entry" => ask,
          "stop_loss" => decimal(D.sub(ask, D.mult(atr, "1.5"))),
          "take_profit" => decimal(D.add(ask, D.mult(atr, 3)))
        })

      case Plan.calculate(input) do
        {:ok, plan} -> Map.put(plan, "basis", "ATR_1_5_STOP_3_TARGET_UNVALIDATED")
        _ -> nil
      end
    end
  end

  defp build_plan(_, _, _), do: nil

  defp depth_cost(%{"quantity" => qty}, %{"parsed" => book}) do
    with {:ok, buy} <- Liquidity.fill(book.asks, D.new(qty)),
         {:ok, sell} <- Liquidity.fill(book.bids, D.new(qty)) do
      # Includes spread plus walking impact, to be compared against the explicit slippage budget.
      %{
        "buy_average" => decimal(buy),
        "sell_average" => decimal(sell),
        "round_trip_slippage_percent" => decimal(D.mult(D.div(D.sub(buy, sell), buy), 100))
      }
    else
      _ -> nil
    end
  end

  defp depth_cost(_, _), do: nil

  defp classification(%{analysis_enabled: true, analysis: analysis}, now) when is_map(analysis) do
    if analysis.status == "ready" and DateTime.compare(now, analysis.valid_until) == :lt do
      signal =
        %{
          "BUY" => "BUY_CANDIDATE",
          "SELL" => "EXIT_CANDIDATE",
          "WAIT" => "WAIT",
          "NO_DATA" => "NO_DATA"
        }[analysis.signal]

      %{
        "signal" => signal,
        "direction" => analysis.answers["trend"]["choice"],
        "analyzed_at" => DateTime.to_iso8601(analysis.analyzed_at)
      }
    else
      %{"signal" => "NO_DATA", "direction" => nil, "analyzed_at" => nil}
    end
  end

  defp classification(_, _),
    do: %{"signal" => "NO_DATA", "direction" => nil, "analyzed_at" => nil}

  defp greater?(nil, _), do: false
  defp greater?(value, limit), do: D.compare(value, limit) == :gt
  defp flag(flags, true, reason), do: flags ++ [reason]
  defp flag(flags, _, _), do: flags
  defp decimal(value), do: value |> D.round(30) |> D.normalize() |> D.to_string(:normal)
end
