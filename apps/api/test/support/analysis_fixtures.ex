defmodule CryptoDecisionLab.AnalysisFixtures do
  @moduledoc "Synthetic hourly ramp candles for deterministic indicator and integration tests."
  alias CryptoDecisionLab.{Repo, MarketFixtures}
  alias CryptoDecisionLab.MarketData.{Candle, LatestPrice, TickerStats}

  def candles do
    cutoff = DateTime.from_unix!(div(DateTime.to_unix(MarketFixtures.now()), 3600) * 3600)

    for value <- 1..300 do
      open_time = DateTime.add(cutoff, (value - 301) * 3600) |> Map.put(:microsecond, {0, 6})
      price = Decimal.new(value)

      %Candle{
        timeframe: "1h",
        open_time: open_time,
        close_time: DateTime.add(open_time, 3_599_999, :millisecond),
        open: price,
        close: price,
        high: price,
        low: price,
        base_volume: Decimal.new(10),
        quote_volume: Decimal.new(100),
        trade_count: 1,
        taker_buy_base_volume: Decimal.new(5),
        taker_buy_quote_volume: Decimal.new(50)
      }
    end
  end

  def seed(symbol) do
    now = MarketFixtures.now()

    Repo.insert!(%LatestPrice{
      market_symbol_id: symbol.id,
      price: Decimal.new(300),
      fetched_at: now,
      updated_at: now
    })

    Repo.insert!(%TickerStats{
      market_symbol_id: symbol.id,
      price_change: Decimal.new(10),
      price_change_percent: Decimal.new(3),
      high_price: Decimal.new(310),
      low_price: Decimal.new(290),
      base_volume: Decimal.new(100),
      quote_volume: Decimal.new(30_000),
      trade_count: 50,
      data_at: now,
      fetched_at: now,
      updated_at: now
    })

    Enum.each(candles(), &Repo.insert!(%{&1 | market_symbol_id: symbol.id}))
  end
end
