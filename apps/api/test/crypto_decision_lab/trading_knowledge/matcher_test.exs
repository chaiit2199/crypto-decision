defmodule CryptoDecisionLab.TradingKnowledge.MatcherTest do
  use ExUnit.Case, async: true
  alias CryptoDecisionLab.KnowledgeFixtures, as: F
  alias CryptoDecisionLab.TradingKnowledge.Matcher

  test "matches rules and explains all conditions without granting eligibility" do
    assert {:ok, result} = Matcher.match(F.strategy(), F.snapshot(), F.now())
    assert result["matched"]
    refute result["eligible"]
    assert result["validation_status"] == "unvalidated"
    assert [%{"result" => "unmatched"}] = result["conditions"]["invalidation_conditions"]
  end

  test "future observation or availability, stale data, gaps and bad decimals fail closed" do
    for snapshot <- [
          put_in(F.snapshot(), ["features", "close", "observed_at"], "2026-10-18T13:00:00Z"),
          put_in(F.snapshot(), ["features", "ema20", "available_at"], "2026-10-18T13:00:00Z"),
          put_in(F.snapshot(), ["features", "ema50", "observed_at"], "2026-10-18T09:00:00Z"),
          put_in(F.snapshot(), ["features", "rsi14", "value"], "NaN"),
          update_in(F.snapshot(), ["features"], &Map.delete(&1, "ema50")),
          Map.put(F.snapshot(), "regime", "downtrend"),
          Map.put(F.snapshot(), "feature_version", "unknown")
        ] do
      assert {:ok, result} = Matcher.match(F.strategy(), snapshot, F.now())
      refute result["data_valid"]
      refute result["matched"]
    end
  end

  test "comparison preserves precision beyond binary float" do
    snapshot = put_in(F.snapshot(), ["features", "close", "value"], "105.000000000000000001")
    assert {:ok, %{"matched" => true}} = Matcher.match(F.strategy(), snapshot, F.now())
    snapshot = put_in(snapshot, ["features", "close", "value"], "105")
    assert {:ok, %{"matched" => false}} = Matcher.match(F.strategy(), snapshot, F.now())
  end

  test "unknown invalidation blocks a candidate" do
    strategy =
      Map.update!(F.strategy(), "invalidation_conditions", fn [c] ->
        [put_in(c, ["left", "feature"], "return_24h_percent")]
      end)

    strategy =
      put_in(strategy, ["invalidation_conditions", Access.at(0), "right"], %{"value" => "-5"})

    snapshot = update_in(F.snapshot(), ["features"], &Map.delete(&1, "return_24h_percent"))
    assert {:ok, result} = Matcher.match(strategy, snapshot, F.now())
    assert [%{"result" => "unknown"}] = result["conditions"]["invalidation_conditions"]
    refute result["matched"]
  end

  test "malformed feature containers fail closed rather than raising" do
    for features <- [nil, [], "invalid", 42] do
      assert {:ok, %{"matched" => false}} =
               Matcher.match(F.strategy(), Map.put(F.snapshot(), "features", features), F.now())
    end
  end

  test "snapshot construction requires archived availability and closed consecutive candles" do
    alias CryptoDecisionLab.{AnalysisFixtures, MarketFixtures}
    alias CryptoDecisionLab.TradingKnowledge.Snapshot
    now = MarketFixtures.now()

    records =
      Enum.map(
        AnalysisFixtures.candles(),
        &%{candle: &1, available_at: DateTime.add(&1.close_time, 5)}
      )

    assert {:ok, snapshot} = Snapshot.from_candles(records, "BTCUSDT", now)
    assert snapshot["features"]["close"]["value"] == "300"

    assert {:error, :unavailable_candle} =
             Snapshot.from_candles(
               List.update_at(records, 0, &%{&1 | available_at: DateTime.add(now, 1)}),
               "BTCUSDT",
               now
             )

    assert {:error, :insufficient_candles} = Snapshot.from_candles(tl(records), "BTCUSDT", now)
  end
end
