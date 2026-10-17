defmodule CryptoDecisionLab.MarketData.ParserTest do
  use ExUnit.Case, async: true
  alias CryptoDecisionLab.MarketData.{Parser, Integrity}
  alias CryptoDecisionLab.MarketFixtures, as: F

  test "preserves financial precision and rejects nonfinite or numeric JSON values" do
    assert {:ok, value} = Parser.decimal("0.0000000000000000000001234")
    assert Decimal.to_string(value, :normal) == "0.0000000000000000000001234"

    for value <- [1.2, 1, nil, "NaN", "Infinity", "1foo"] do
      assert {:error, _} = Parser.decimal(value)
    end
  end

  test "rejects inconsistent OHLC, intervals and negative volume" do
    for {index, value} <- [
          {2, "99"},
          {3, "106"},
          {1, "0"},
          {5, "-1"},
          {6, F.start() + 10},
          {0, F.start() + 1}
        ] do
      assert {:error, :invalid_candle} =
               Parser.candle(List.replace_at(F.kline(), index, value), F.now())
    end
  end

  test "excludes incomplete candles even with a future planned close timestamp" do
    open = DateTime.to_unix(~U[2026-10-17 12:00:00Z], :millisecond)
    assert {:skip, :incomplete} = Parser.candle(F.kline(open), F.now())
    assert {:ok, _} = Parser.candle(F.kline(open - F.hour()), F.now())
  end

  test "aggregates complete UTC windows exactly and refuses missing constituent candles" do
    rows =
      for n <- 0..3 do
        {:ok, row} = Parser.candle(F.kline(F.start() + n * F.hour()), F.now())
        Map.put(row, :market_symbol_id, 1)
      end

    assert {:ok, [bar]} = Integrity.aggregate(rows, "4h")
    assert Decimal.equal?(bar.base_volume, "50")
    assert bar.trade_count == 12
    assert bar.close_time == List.last(rows).close_time
    assert {:error, :incomplete_aggregation} = Integrity.aggregate(Enum.drop(rows, 1), "4h")
    assert {:error, :incomplete_aggregation} = Integrity.aggregate(List.delete_at(rows, 2), "4h")
  end

  test "rejects stale ticker data and invalid JSON shapes" do
    assert {:ok, _} = Parser.stats(F.stats(), F.now())
    assert {:error, _} = Parser.stats(Map.put(F.stats(), "closeTime", 0), F.now())
    assert {:error, _} = Parser.price(%{"symbol" => "BTCUSDT", "price" => "-1"})
    assert {:error, _} = Parser.candle(%{}, F.now())
  end

  test "aggregation rejects an entirely missing window between valid windows" do
    now = DateTime.add(F.now(), 86_400)

    rows =
      for n <- Enum.to_list(0..3) ++ Enum.to_list(8..11) do
        {:ok, row} = Parser.candle(F.kline(F.start() + n * F.hour()), now)
        Map.put(row, :market_symbol_id, 1)
      end

    assert {:error, :incomplete_aggregation} = Integrity.aggregate(rows, "4h")
  end

  test "24-hour aggregation preserves a full UTC day" do
    now = DateTime.add(F.now(), 86_400)

    rows =
      for n <- 0..23 do
        {:ok, row} = Parser.candle(F.kline(F.start() + n * F.hour()), now)
        Map.put(row, :market_symbol_id, 1)
      end

    assert {:ok, [day]} = Integrity.aggregate(rows, "1d")
    assert day.trade_count == 72
    assert Decimal.equal?(day.base_volume, "300")
  end
end
