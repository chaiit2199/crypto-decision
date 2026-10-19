defmodule CryptoDecisionLab.Trading.WorkbenchTest do
  use CryptoDecisionLab.DataCase, async: false

  alias CryptoDecisionLab.{
    MarketFixtures,
    AnalysisFixtures,
    Trading,
    TechnicalAnalysis,
    MarketData
  }

  alias CryptoDecisionLab.MarketData.{Parser, Liquidity, LiquiditySnapshot, Sync, Candle}
  alias CryptoDecisionLab.Trading.{Plan, Assessment, Replay, Paper}
  alias Decimal, as: D

  setup do
    MarketFixtures.configure()
  end

  defp input do
    %{
      "equity" => "1000",
      "risk_percent" => "0.5",
      "entry" => "100",
      "stop_loss" => "99",
      "take_profit" => "102",
      "fee_percent" => "0.1",
      "slippage_percent" => "0.05"
    }
  end

  defp book do
    %{
      "lastUpdateId" => 1,
      "bids" => [["99.99", "1000"], ["99.98", "1000"]],
      "asks" => [["100", "1000"], ["100.01", "1000"]]
    }
  end

  defp store_book(symbol, at \\ MarketFixtures.now()) do
    Repo.insert!(%LiquiditySnapshot{
      market_symbol_id: symbol.id,
      book: book(),
      data_at: at,
      fetched_at: at
    })
  end

  defp short(time, width) do
    MarketFixtures.kline(time) |> List.replace_at(6, time + width - 1)
  end

  defp candles(frame, count \\ 300) do
    width = %{"5m" => 300, "15m" => 900, "1h" => 3600}[frame]
    last_open = div(DateTime.to_unix(MarketFixtures.now()) - 5, width) * width - width
    template = hd(AnalysisFixtures.candles())

    for i <- 1..count do
      at =
        DateTime.from_unix!(last_open - (count - i) * width, :second)
        |> Map.put(:microsecond, {0, 6})

      price = D.new(100 + i)

      %{
        template
        | timeframe: frame,
          open_time: at,
          close_time: DateTime.add(at, width * 1000 - 1, :millisecond),
          open: price,
          close: price,
          high: D.add(price, 1),
          low: D.sub(price, 1),
          quote_volume: D.mult(price, 10)
      }
    end
  end

  test "cost-aware sizing reproduces the audit scenario without float loss" do
    assert {:ok, p} = Plan.calculate(input())
    assert D.equal?(p["risk_budget"], 5)
    assert D.equal?(D.round(D.new(p["notional"]), 2), "384.62")
    assert D.equal?(D.round(D.new(p["net_profit"]), 2), "6.54")
    assert D.equal?(D.round(D.new(p["risk_reward_ratio"]), 2), "1.31")
    assert D.equal?(D.round(D.new(p["net_loss"]), 20), 5)
    refute p["execution_allowed"]
  end

  test "invalid numbers, ordering and unsafe risk inputs fail closed" do
    for {key, value} <- [
          {"entry", "NaN"},
          {"equity", "-1"},
          {"risk_percent", "6"},
          {"stop_loss", "100"},
          {"take_profit", "99"},
          {"fee_percent", "-0.1"},
          {"entry", 100}
        ] do
      assert {:error, :invalid_plan} = Plan.calculate(Map.put(input(), key, value))
    end

    assert {:ok, p} =
             Plan.calculate(
               Map.merge(input(), %{
                 "equity" => "1",
                 "risk_percent" => "5",
                 "stop_loss" => "99.99"
               })
             )

    assert D.compare(D.mult(p["notional"], "1.0015"), 1) != :gt
    assert {:ok, p} = Plan.calculate(Map.put(input(), "take_profit", "100.1"))
    assert D.negative?(D.new(p["net_profit"]))
  end

  test "depth is sorted, uncrossed, finite and requires a full fill" do
    assert {:ok, parsed} = Liquidity.parse(book())
    assert D.positive?(parsed.spread_percent)
    assert {:ok, avg} = Liquidity.fill(parsed.asks, D.new(1500))
    assert D.compare(avg, 100) == :gt
    assert {:error, :insufficient_depth} = Liquidity.fill(parsed.asks, D.new(2001))

    for bad <- [
          Map.put(book(), "bids", [["101", "1"]]),
          Map.put(book(), "asks", []),
          Map.put(book(), "asks", [["100", "1"], ["100", "2"]]),
          Map.put(book(), "asks", [["NaN", "2"]])
        ] do
      assert {:error, :invalid_order_book} = Liquidity.parse(bad)
    end
  end

  test "depth sync shares budget and cooldown and does not repeatedly fetch within a minute" do
    symbol = MarketFixtures.symbol()
    MarketFixtures.queue([MarketFixtures.response(book())])
    assert {:ok, :stored} = Liquidity.sync(symbol.id)
    assert {:ok, :not_due} = Liquidity.sync(symbol.id)
    Repo.delete_all(LiquiditySnapshot)
    MarketFixtures.queue([MarketFixtures.response(%{}, 429, %{"retry-after" => ["45"]})])
    assert {:error, {:cooldown, 45}} = Liquidity.sync(symbol.id)
    assert {:error, {:cooldown, _}} = Liquidity.sync(symbol.id)
  end

  test "5m parser rejects wrong alignment and skips still-open bars" do
    time = MarketFixtures.start()

    assert {:ok, %{timeframe: "5m"}} =
             Parser.candle(short(time, 300_000), MarketFixtures.now(), "5m")

    assert {:error, :invalid_candle} =
             Parser.candle(short(time + 1, 300_000), MarketFixtures.now(), "5m")

    current = DateTime.to_unix(MarketFixtures.now(), :millisecond) - 10_000

    assert {:skip, :incomplete} =
             Parser.candle(short(current, 300_000), MarketFixtures.now(), "5m")
  end

  test "timeframe checkpoints resume independently and never jump an internal gap" do
    symbol = MarketFixtures.symbol()
    time = MarketFixtures.start()

    MarketFixtures.queue([
      MarketFixtures.response([short(time, 300_000), short(time + 300_000, 300_000)])
    ])

    assert {:ok, :complete} = Sync.candles(symbol.id, :backfill, timeframe: "5m", from: time)
    assert Sync.state(symbol.id, "backfill", "1h") == nil
    MarketFixtures.queue([MarketFixtures.response([short(time + 900_000, 300_000)])])
    assert {:error, :candle_gap} = Sync.candles(symbol.id, :backfill, timeframe: "5m", from: time)

    assert DateTime.to_unix(
             Sync.state(symbol.id, "backfill", "5m").last_synced_open_time,
             :millisecond
           ) == time + 300_000

    MarketFixtures.queue([MarketFixtures.response([short(time + 600_000, 300_000)])])
    assert {:ok, :complete} = Sync.candles(symbol.id, :backfill, timeframe: "5m", from: time)
    assert Repo.aggregate(Candle, :count) == 3
    MarketFixtures.queue([MarketFixtures.response([short(time + 600_000, 300_000)])])
    assert {:ok, :complete} = Sync.candles(symbol.id, :incremental, timeframe: "5m")
    assert Repo.aggregate(Candle, :count) == 3

    assert {:ok, rows, %{timeframe: "5m"}} =
             MarketData.candles(symbol.symbol, %{
               "timeframe" => "5m",
               "from" => "2026-10-17T00:00:00Z",
               "to" => "2026-10-17T00:15:00Z"
             })

    assert length(rows) == 3
  end

  test "short features use real session volume and reject gaps and open bars" do
    rows = candles("5m")
    assert {:ok, f} = TechnicalAnalysis.features(rows, MarketFixtures.now(), "5m")
    session = Enum.filter(rows, &(DateTime.to_date(&1.open_time) == ~D[2026-10-17]))

    expected =
      D.div(
        Enum.reduce(session, D.new(0), &D.add(&2, &1.quote_volume)),
        Enum.reduce(session, D.new(0), &D.add(&2, &1.base_volume))
      )

    assert D.equal?(f["vwap"], expected)
    assert D.equal?(f["volume_delta"], 0)
    assert f["return_1h_percent"] == nil
    assert f["return_1bar_percent"] != nil
    broken = List.replace_at(rows, 100, Enum.at(rows, 99))
    assert {:error, :candle_gap} = TechnicalAnalysis.features(broken, MarketFixtures.now(), "5m")

    assert {:error, :invalid_candles} =
             TechnicalAnalysis.features(rows, List.last(rows).close_time, "5m")

    assert {:ok, f} =
             TechnicalAnalysis.features(
               Enum.map(rows, &%{&1 | base_volume: D.new(0)}),
               MarketFixtures.now(),
               "5m"
             )

    assert is_nil(f["vwap"])
  end

  test "mixed EMA ordering is not bullish even if a model says BUY" do
    assert Assessment.regime(%{"ema20" => "81652", "ema50" => "81591", "ema200" => "82115"}) ==
             "RANGING_OR_MIXED"
  end

  test "missing data report is explicit, bounded and never implies execution eligibility" do
    symbol = MarketFixtures.symbol()
    assert {:ok, report, _} = Trading.workbench(symbol.symbol, %{})
    assert report["trade_eligibility"] == "NO_DATA"
    assert report["plan"] == nil
    refute report["execution_allowed"]
    assert report["expected_move"] == nil
    assert "LIQUIDITY_MISSING" in report["risk_flags"]
    assert {:error, :invalid_style} = Trading.workbench(symbol.symbol, %{"style" => "unknown"})
    assert {:ok, [_], _} = Trading.opportunities(%{})
  end

  test "intraday keeps hourly reference indicators without Jev or Coinbase short candles" do
    symbol =
      MarketFixtures.symbol()
      |> Ecto.Changeset.change(exchange: "coinbase", symbol: "BTCUSD", quote_asset: "USD")
      |> Repo.update!()

    AnalysisFixtures.seed(symbol)
    params = %{"exchange" => "coinbase", "style" => "intraday"}

    assert {:ok, report, _} = Trading.workbench(symbol.symbol, params)
    assert report["frames"]["1h"]["status"] == "ready"
    assert report["frames"]["1h"]["features"]["rsi14"] != nil
    assert report["frames"]["1h"]["features"]["ema9"] != nil
    assert report["frames"]["4h"]["status"] == "no_data"
    assert report["frames"]["5m"]["status"] == "no_data"
    assert report["liquidity"]["status"] == "unsupported"
    assert report["trade_eligibility"] == "NO_DATA"
    assert report["ai_signal"] == "NO_DATA"
    refute report["execution_allowed"]

    assert {:ok, [row], _} = Trading.opportunities(params)
    refute Map.has_key?(row["frames"], "1h")
  end

  test "fresh depth and short frames remain research only and never borrow another market's book" do
    symbol = MarketFixtures.symbol()
    AnalysisFixtures.seed(symbol)

    for frame <- ["5m", "15m"],
        row <- candles(frame),
        do: Repo.insert!(%{row | market_symbol_id: symbol.id})

    store_book(symbol)
    assert {:ok, report, _} = Trading.workbench(symbol.symbol, %{"style" => "scalping"})
    assert report["frames"]["5m"]["status"] == "ready"
    assert report["liquidity"]["status"] == "fresh"
    assert report["plan"] != nil
    assert "STRATEGY_UNVALIDATED" in report["risk_flags"]
    other = MarketFixtures.symbol("ETH")
    assert {:ok, report, _} = Trading.workbench(other.symbol, %{})
    assert report["liquidity"]["status"] == "missing"
    Repo.update_all(LiquiditySnapshot, set: [fetched_at: DateTime.add(MarketFixtures.now(), -91)])
    assert {:ok, report, _} = Trading.workbench(symbol.symbol, %{"style" => "scalping"})
    assert report["liquidity"]["status"] == "stale"
    assert report["plan"] == nil
  end

  test "paper scenarios require fresh depth and can only close once with a newer snapshot" do
    symbol = MarketFixtures.symbol()
    assert {:error, :fresh_liquidity_required} = Paper.open(symbol.id, input())
    store_book(symbol, DateTime.add(MarketFixtures.now(), -10))
    assert {:ok, position} = Paper.open(symbol.id, input())
    assert {:error, :new_snapshot_required} = Paper.close(position.id)

    Repo.update_all(LiquiditySnapshot,
      set: [fetched_at: MarketFixtures.now(), data_at: MarketFixtures.now()]
    )

    assert {:ok, exit} = Paper.close(position.id)
    assert exit.report["open_id"] == position.id
    assert D.negative?(D.new(exit.report["net_pnl"]))
    assert {:error, :already_closed} = Paper.close(position.id)
  end

  test "replay enters strictly after features, charges costs and rejects future or gapped datasets" do
    rows = candles("5m", 310)
    first = Enum.at(rows, 301).open_time

    config =
      Map.merge(input(), %{
        "stop_percent" => "0.1",
        "target_percent" => "0.1",
        "test_from" => DateTime.to_iso8601(first),
        "test_to" => DateTime.to_iso8601(MarketFixtures.now()),
        "parameters_frozen_at" => DateTime.to_iso8601(DateTime.add(first, -1))
      })

    assert {:ok, report} = Replay.run(rows, config)
    assert report["trade_count"] > 0

    assert Enum.all?(report["trades"], fn trade ->
             trade["exit_reason"] == "STOP" and D.negative?(D.new(trade["net_pnl"])) and
               DateTime.compare(
                 DateTime.from_iso8601(trade["entry_at"]) |> elem(1),
                 DateTime.from_iso8601(trade["decision_at"]) |> elem(1)
               ) == :gt
           end)

    assert {:error, :invalid_replay} =
             Replay.run(List.replace_at(rows, 305, Enum.at(rows, 304)), config)

    assert {:error, :invalid_replay} =
             Replay.run(rows, Map.put(config, "test_to", "2099-01-01T00:00:00Z"))
  end
end
