defmodule CryptoDecisionLab.TechnicalAnalysisTest do
  use ExUnit.Case, async: true
  alias CryptoDecisionLab.{TechnicalAnalysis, AnalysisFixtures, MarketFixtures}

  test "linear ramp matches analytical EMA reference and RSI limits with Decimal precision" do
    assert {:ok, result} =
             TechnicalAnalysis.features(AnalysisFixtures.candles(), MarketFixtures.now())

    # For a unit ramp with SMA initialization: EMA(N) = last - (N - 1)/2 exactly.
    assert Decimal.equal?(result["ema20"], "290.5")
    assert Decimal.equal?(result["ema50"], "275.5")
    assert Decimal.equal?(result["rsi14"], "100")
    # Unit ramp: EMA200 = last - 199/2; EMA12 - EMA26 = 7,
    # all true ranges are 1, directional movement only positive, constant volume.
    for {key, value} <- [
          {"ema200", "200.5"},
          {"macd", "7"},
          {"macd_signal", "7"},
          {"macd_histogram", "0"},
          {"atr14", "1"},
          {"adx14", "100"},
          {"relative_volume20", "1"}
        ] do
      assert Decimal.equal?(result[key], value)
    end

    assert Decimal.compare(
             Decimal.abs(Decimal.sub(result["return_24h_percent"], "8.695652173913")),
             "0.000000000001"
           ) != :gt
  end

  test "alternating gains/losses match closed-form EMA and Wilder smoothing references" do
    candles =
      AnalysisFixtures.candles()
      |> Enum.with_index()
      |> Enum.map(fn {candle, index} ->
        price = Decimal.new(100 + rem(index, 2))
        %{candle | open: price, high: price, low: price, close: price}
      end)

    assert {:ok, result} = TechnicalAnalysis.features(candles, MarketFixtures.now())
    # Independent closed-form references for the alternating 100/101 series:
    # EMA50 = 100.51 - .01*(49/51)^250; EMA20 = 100.525 - .025*(19/21)^280.
    # RSI = 100*(14/27 + (1/54)*(13/14)^285), after the SMA seed of 14 changes.
    for {name, reference} <- [
          {"ema20", "100.524999999999983"},
          {"ema50", "100.509999546605777"},
          {"rsi14", "51.851851853096285"}
        ] do
      assert Decimal.compare(Decimal.abs(Decimal.sub(result[name], reference)), "0.000000001") ==
               :lt
    end
  end

  test "flat series defines RSI50 and preserves small decimal prices" do
    price = Decimal.new("0.000000000123")

    candles =
      Enum.map(
        AnalysisFixtures.candles(),
        &%{&1 | open: price, close: price, high: price, low: price}
      )

    assert {:ok, result} = TechnicalAnalysis.features(candles, MarketFixtures.now())
    assert Decimal.equal?(result["ema20"], price)
    assert Decimal.equal?(result["rsi14"], 50)
    assert Decimal.equal?(result["atr14"], 0)
    assert Decimal.equal?(result["adx14"], 0)
    assert Decimal.equal?(result["macd_histogram"], 0)
  end

  test "relative volume excludes the current bar and has no invented zero-denominator value" do
    candles =
      AnalysisFixtures.candles() |> List.update_at(-1, &%{&1 | base_volume: Decimal.new(20)})

    assert {:ok, features} = TechnicalAnalysis.features(candles, MarketFixtures.now())
    assert Decimal.equal?(features["relative_volume20"], 2)
    empty_volume = Enum.map(candles, &%{&1 | base_volume: Decimal.new(0)})
    assert {:ok, features} = TechnicalAnalysis.features(empty_volume, MarketFixtures.now())
    assert is_nil(features["relative_volume20"])
  end

  test "missing history, gaps, future candles and stale history cannot produce features" do
    candles = AnalysisFixtures.candles()

    assert {:error, :insufficient_candles} =
             TechnicalAnalysis.features(tl(candles), MarketFixtures.now())

    gap =
      List.update_at(candles, 2, fn candle ->
        %{
          candle
          | open_time: DateTime.add(candle.open_time, -3600),
            close_time: DateTime.add(candle.close_time, -3600)
        }
      end)

    assert {:error, :candle_gap} = TechnicalAnalysis.features(gap, MarketFixtures.now())

    assert {:error, :invalid_candles} =
             TechnicalAnalysis.features(candles, DateTime.add(MarketFixtures.now(), -20))

    assert {:error, :stale_candles} =
             TechnicalAnalysis.features(candles, DateTime.add(MarketFixtures.now(), 7200))
  end
end
