defmodule CryptoDecisionLab.MarketData.SyncTest do
  use CryptoDecisionLab.DataCase

  alias CryptoDecisionLab.MarketData.{
    Universe,
    Asset,
    Symbol,
    LatestPrice,
    Candle,
    Sync,
    Collector,
    Integrity,
    SyncState
  }

  alias CryptoDecisionLab.MarketFixtures, as: F

  setup do
    F.configure()
  end

  test "seeds exactly 32 distinct assets idempotently and preserves preferences" do
    Universe.seed()
    asset = Repo.get_by!(Asset, symbol: "BTC")
    Repo.update!(Ecto.Changeset.change(asset, enabled: false))
    Universe.seed()
    assert Repo.aggregate(Asset, :count) == 32
    refute Repo.get!(Asset, asset.id).enabled
  end

  test "discovers actual spot symbols without inventing unavailable pairs" do
    F.queue([F.response(F.exchange(["BTC", "ETH"]))])
    assert {:ok, 2} = Sync.metadata()
    assert Repo.aggregate(Asset, :count) == 32
    assert Repo.aggregate(Symbol, :count) == 2
    refute Repo.get_by(Symbol, symbol: "KASUSDT")
    F.queue([F.response(F.exchange(["BTC"]))])
    assert {:ok, 1} = Sync.metadata()
    assert Repo.get_by!(Symbol, symbol: "ETHUSDT").trading_status == "UNAVAILABLE"
  end

  test "keeps valid partial prices and reports the missing response" do
    btc = F.symbol()
    F.symbol("ETH")
    F.queue([F.response([%{"symbol" => "BTCUSDT", "price" => "0.1234567890123456789"}])])
    assert {:error, :partial_response} = Sync.prices()
    assert Decimal.equal?(Repo.get!(LatestPrice, btc.id).price, "0.1234567890123456789")
    assert Collector.state().last_error == "partial_response"
  end

  test "rate limit cooldown survives a separate synchronization call" do
    F.symbol()
    F.queue([F.response(%{}, 429, %{"retry-after" => ["120"]})])
    assert {:error, {:cooldown, 120}} = Sync.prices()
    assert {:error, {:cooldown, _}} = Sync.prices()
    assert length(Process.get(:http_calls)) == 1
  end

  test "shared poll deadline prevents another collector polling immediately" do
    F.symbol()
    F.queue([F.response([%{"symbol" => "BTCUSDT", "price" => "100"}])])
    assert {:ok, 1} = Sync.poll()
    assert {:ok, :not_due} = Sync.poll()
    assert length(Process.get(:http_calls)) == 1
  end

  test "backfill resumes from committed checkpoint and incremental writes are idempotent" do
    symbol = F.symbol()
    F.queue([F.response([F.kline()])])
    assert {:ok, :complete} = Sync.candles(symbol.id, :backfill, from: F.start())

    F.queue([
      fn _, params ->
        assert params[:startTime] == F.start() + F.hour()
        F.response([F.kline(F.start() + F.hour())])
      end
    ])

    assert {:ok, :complete} = Sync.candles(symbol.id, :backfill)
    F.queue([F.response([F.kline(F.start() + F.hour())])])
    assert {:ok, :complete} = Sync.candles(symbol.id, :incremental)
    assert Repo.aggregate(Candle, :count) == 2

    assert Sync.state(symbol.id, "backfill").last_synced_open_time ==
             ~U[2026-10-17 01:00:00.000000Z]
  end

  test "a malformed batch does not partially save or advance progress" do
    symbol = F.symbol()
    F.queue([F.response([F.kline(), ["broken"]])])
    assert {:error, :invalid_candle} = Sync.candles(symbol.id, :backfill, from: F.start())
    assert Repo.aggregate(Candle, :count) == 0
    assert Sync.state(symbol.id, "backfill").last_synced_open_time == nil
    assert Sync.state(symbol.id, "backfill").status == "error"
  end

  test "does not persist an open candle, detects gaps, and queues repair" do
    symbol = F.symbol()
    current = DateTime.to_unix(~U[2026-10-17 12:00:00Z], :millisecond)
    F.queue([F.response([F.kline(), F.kline(F.start() + 2 * F.hour()), F.kline(current)])])
    assert {:ok, :complete} = Sync.candles(symbol.id, :backfill, from: F.start())
    assert Repo.aggregate(Candle, :count) == 2
    assert length(Integrity.gaps(symbol.id, ~U[2026-10-17 03:00:10Z])) == 1
    assert {:ok, 10} = Integrity.check()

    assert Repo.get_by!(SyncState, market_symbol_id: symbol.id, sync_type: "integrity").missing_count ==
             10

    assert Repo.aggregate(Oban.Job, :count) == 1
  end

  test "database uniqueness rejects duplicate candles independently of services" do
    symbol = F.symbol()
    {:ok, row} = CryptoDecisionLab.MarketData.Parser.candle(F.kline(), F.now())
    row = Map.merge(row, %{market_symbol_id: symbol.id, inserted_at: F.now()})
    Repo.insert_all(Candle, [row])
    assert_raise Postgrex.Error, fn -> Repo.insert_all(Candle, [row]) end
  end

  test "stats use cheap batches of at most 20 symbols" do
    for asset <- Universe.assets(), do: F.symbol(asset.symbol)

    F.queue(
      for _ <- 1..2 do
        fn path, params ->
          assert path == "/ticker/24hr"
          symbols = Jason.decode!(params[:symbols])
          assert length(symbols) <= 20
          F.response(Enum.map(symbols, &F.stats/1))
        end
      end
    )

    assert {:ok, 32} = Sync.stats()
    assert length(Process.get(:http_calls)) == 2
  end

  test "independent database connections cannot collect simultaneously and recover after release" do
    options = Repo.config() |> Keyword.take([:hostname, :port, :username, :password, :database])
    connection = start_supervised!({Postgrex, options})

    Postgrex.query!(connection, "SELECT pg_advisory_lock(7413201)", [])
    assert {:error, :collector_busy} = Collector.run(fn -> flunk("overlapping collection") end)
    Postgrex.query!(connection, "SELECT pg_advisory_unlock(7413201)", [])
    assert {:ok, :released} = Collector.run(fn -> {:ok, :released} end)

    assert %{rows: [[false]]} =
             Postgrex.query!(connection, "SELECT pg_try_advisory_lock(7413201)", [])
  end

  test "price polling is due at the next 30-second tick, not 60 seconds" do
    F.symbol()
    F.queue([F.response([%{"symbol" => "BTCUSDT", "price" => "100"}])])
    assert {:ok, 1} = Sync.poll()
    Process.put(:now, DateTime.add(F.now(), 30))
    F.queue([F.response([%{"symbol" => "BTCUSDT", "price" => "101"}])])
    assert {:ok, 1} = Sync.poll()
    assert length(Process.get(:http_calls)) == 2
  end

  test "older snapshots never replace a newer stored price" do
    symbol = F.symbol()

    Repo.insert!(%LatestPrice{
      market_symbol_id: symbol.id,
      price: Decimal.new("200"),
      fetched_at: DateTime.add(F.now(), 10),
      updated_at: F.now()
    })

    F.queue([F.response([%{"symbol" => "BTCUSDT", "price" => "100"}])])
    assert {:ok, 1} = Sync.prices()
    assert Decimal.equal?(Repo.get!(LatestPrice, symbol.id).price, "200")
  end

  test "request weight is budgeted before dispatch and resets with the minute" do
    Collector.run(fn ->
      Collector.update(%{
        used_weight: 1199,
        weight_window: div(DateTime.to_unix(F.now()), 60),
        weight_limit: 1200
      })

      assert {:error, {:cooldown, _}} = Collector.reserve(4, F.now())
      assert :ok = Collector.reserve(4, DateTime.add(F.now(), 60))
      assert Collector.state().used_weight == 4
    end)
  end

  test "1000-candle pages commit progress and continuation survives retry" do
    symbol = F.symbol()
    first = F.start() - 1001 * F.hour()
    F.queue([F.response(for n <- 0..999, do: F.kline(first + n * F.hour()))])
    assert {:ok, :more} = Sync.candles(symbol.id, :backfill, from: first)
    assert Repo.aggregate(Candle, :count) == 1000

    F.queue([
      fn _, params ->
        assert params[:startTime] == first + 1000 * F.hour()
        F.response([F.kline(first + 1000 * F.hour())])
      end
    ])

    assert {:ok, :complete} = Sync.candles(symbol.id, :backfill)
    assert Repo.aggregate(Candle, :count) == 1001
  end
end
