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

  test "seeds the configured universe idempotently, disables removed assets, and preserves preferences" do
    Universe.seed()
    assert length(Universe.assets()) == 18
    assert Repo.aggregate(Asset, :count) == 18
    asset = Repo.get_by!(Asset, symbol: "BTC")
    Repo.update!(Ecto.Changeset.change(asset, enabled: false))
    # Legacy row no longer in @groups must be disabled on the next seed.
    Repo.insert!(%Asset{
      symbol: "SUI",
      name: "Sui",
      category: "core",
      enabled: true
    })

    Universe.seed()
    assert Repo.aggregate(Asset, :count) == 19
    refute Repo.get!(Asset, asset.id).enabled
    refute Repo.get_by!(Asset, symbol: "SUI").enabled
    assert Repo.get_by!(Asset, symbol: "ARB").enabled
    assert Repo.get_by!(Asset, symbol: "ETH").enabled
  end

  test "discovers actual spot symbols without inventing unavailable pairs" do
    F.queue([F.response(F.exchange(["BTC", "ARB"]))])
    assert {:ok, 2} = Sync.metadata()
    assert Repo.aggregate(from(a in Asset, where: a.enabled), :count) == 18
    assert Repo.aggregate(Symbol, :count) == 2
    refute Repo.get_by(Symbol, symbol: "KASUSDT")
    F.queue([F.response(F.exchange(["BTC"]))])
    assert {:ok, 1} = Sync.metadata()
    assert Repo.get_by!(Symbol, symbol: "ARBUSDT").trading_status == "UNAVAILABLE"
  end

  test "keeps valid partial prices and reports the missing response" do
    btc = F.symbol()
    F.symbol("ARB")
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
    assert {:ok, {:not_due, delay}} = Sync.poll()
    assert delay > 0
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
    assert {:error, :candle_gap} = Sync.candles(symbol.id, :backfill, from: F.start())
    assert Repo.aggregate(Candle, :count) == 0
    assert Sync.state(symbol.id, "backfill").last_synced_open_time == nil

    F.queue([
      F.response([
        F.kline(),
        F.kline(F.start() + F.hour()),
        F.kline(F.start() + 2 * F.hour()),
        F.kline(current)
      ])
    ])

    assert {:ok, :complete} = Sync.candles(symbol.id, :backfill, from: F.start())
    assert Repo.aggregate(Candle, :count) == 3
    # Simulate a later missing stored row; daily integrity still schedules its repair.
    missing = DateTime.from_unix!(F.start() + F.hour(), :millisecond)
    Repo.delete_all(from c in Candle, where: c.open_time == ^missing)
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

    assert {:ok, 21} = Sync.stats()
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

  test "price polling waits for the configured poll interval" do
    interval_s = div(Application.fetch_env!(:crypto_decision_lab, :price_poll_interval_ms), 1000)
    F.symbol()
    F.queue([F.response([%{"symbol" => "BTCUSDT", "price" => "100"}])])
    assert {:ok, 1} = Sync.poll()
    Process.put(:now, DateTime.add(F.now(), max(div(interval_s, 2), 1)))
    assert {:ok, {:not_due, delay}} = Sync.poll()
    assert delay > 0
    Process.put(:now, DateTime.add(F.now(), interval_s))

    F.queue([
      F.response([%{"symbol" => "BTCUSDT", "price" => "101"}], 200, %{
        "date" => [
          Calendar.strftime(DateTime.add(F.now(), interval_s), "%a, %d %b %Y %H:%M:%S GMT")
        ]
      })
    ])

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

  test "the shared price deadline follows the configured 60-second interval" do
    previous = Application.fetch_env!(:crypto_decision_lab, :price_poll_interval_ms)
    Application.put_env(:crypto_decision_lab, :price_poll_interval_ms, 60_000)

    on_exit(fn ->
      Application.put_env(:crypto_decision_lab, :price_poll_interval_ms, previous)
    end)

    F.symbol()
    F.queue([F.response([%{"symbol" => "BTCUSDT", "price" => "100"}])])
    assert {:ok, 1} = Sync.poll()
    Process.put(:now, DateTime.add(F.now(), 30))
    assert {:ok, {:not_due, delay}} = Sync.poll()
    assert delay > 0
    Process.put(:now, DateTime.add(F.now(), 60))
    F.queue([F.response([%{"symbol" => "BTCUSDT", "price" => "101"}])])
    assert {:ok, 1} = Sync.poll()
    assert length(Process.get(:http_calls)) == 2
  end

  test "a price poll one millisecond before the deadline returns only the remaining delay" do
    F.symbol()
    F.queue([F.response([%{"symbol" => "BTCUSDT", "price" => "100"}])])
    assert {:ok, 1} = Sync.poll()
    interval = Application.fetch_env!(:crypto_decision_lab, :price_poll_interval_ms)
    Process.put(:now, DateTime.add(F.now(), interval - 1, :millisecond))
    assert {:ok, {:not_due, 1}} = Sync.poll()
    assert length(Process.get(:http_calls)) == 1
  end
end
