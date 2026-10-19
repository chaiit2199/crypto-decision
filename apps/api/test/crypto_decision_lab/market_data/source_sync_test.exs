defmodule CryptoDecisionLab.MarketData.SourceSyncTest do
  use CryptoDecisionLab.DataCase
  alias CryptoDecisionLab.{MarketData, MarketFixtures, AnalysisFixtures, TechnicalAnalysis}

  alias CryptoDecisionLab.MarketData.{
    SourceSync,
    SourceHTTP,
    SourceParser,
    Symbol,
    LatestPrice,
    TickerStats,
    Candle,
    CollectorState,
    Sync
  }

  setup do
    MarketFixtures.configure()

    previous =
      Map.new(
        [:source_request, :source_sleep],
        &{&1, Application.get_env(:crypto_decision_lab, &1)}
      )

    Application.put_env(:crypto_decision_lab, :source_sleep, fn _ -> :ok end)

    Application.put_env(:crypto_decision_lab, :source_request, fn options ->
      send(self(), {:source_request, options[:url]})
      [result | rest] = Process.get(:source_responses, [])
      Process.put(:source_responses, rest)
      result
    end)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:crypto_decision_lab, key)
        {key, value} -> Application.put_env(:crypto_decision_lab, key, value)
      end)
    end)

    :ok
  end

  defp queue(bodies),
    do: Process.put(:source_responses, Enum.map(bodies, &MarketFixtures.response/1))

  defp coinbase do
    queue([
      [
        %{
          "id" => "BTC-USD",
          "base_currency" => "BTC",
          "quote_currency" => "USD",
          "status" => "online"
        }
      ]
    ])

    assert {:ok, :discovered} = SourceSync.metadata("coinbase")
    Repo.get_by!(Symbol, exchange: "coinbase", symbol: "BTCUSD")
  end

  defp ticker(price \\ "300", time \\ MarketFixtures.now()),
    do: %{"price" => price, "time" => DateTime.to_iso8601(time)}

  defp stats,
    do: %{
      "open" => "250",
      "last" => "300",
      "high" => "310",
      "low" => "240",
      "volume" => "123.456"
    }

  defp candles do
    Enum.map(AnalysisFixtures.candles(), fn c ->
      [DateTime.to_unix(c.open_time), c.low, c.high, c.open, c.close, c.base_volume]
    end)
  end

  test "USD metadata, nullable volumes, closed candles and independent market reads" do
    binance = MarketFixtures.symbol()
    symbol = coinbase()
    assert SourceSync.active_symbols("coinbase") |> Enum.map(& &1.id) == [symbol.id]
    assert Sync.active_symbols() |> Enum.map(& &1.id) == [binance.id]
    queue([ticker(), stats(), candles()])
    assert {:ok, 300} = SourceSync.sync("coinbase", symbol.id)
    assert Repo.get!(TickerStats, symbol.id).quote_volume == nil
    assert Repo.get!(TickerStats, symbol.id).trade_count == nil

    assert Repo.aggregate(from(c in Candle, where: c.market_symbol_id == ^symbol.id), :count) ==
             300

    assert {:ok, :not_due} = SourceSync.sync("coinbase", symbol.id)
    assert {:error, :not_found} = MarketData.get_market("BTCUSD")
    assert {:ok, market, _} = MarketData.get_market("BTCUSD", %{"exchange" => "coinbase"})
    assert market.quote_asset == "USD"
    assert market.price_freshness.status == "fresh"
    assert market.price_max_age_seconds == 180
    assert {:ok, input} = MarketData.analysis_inputs(symbol.id, MarketFixtures.now())
    assert input.snapshot["exchange"] == "coinbase"
    assert input.snapshot["quote_volume_24h"] == nil
    assert {:ok, features} = TechnicalAnalysis.features(input.candles, MarketFixtures.now())
    assert features["ema200"] != nil

    assert {:ok, rows, _} =
             MarketData.candles("BTCUSD", %{
               "exchange" => "coinbase",
               "timeframe" => "4h",
               "limit" => "2"
             })

    assert length(rows) == 2
    assert Enum.all?(rows, &is_nil(&1.quote_volume))
    # Binance metadata only updates its own symbols.
    MarketFixtures.queue([MarketFixtures.response(MarketFixtures.exchange())])
    assert {:ok, _} = Sync.metadata()
    assert Repo.get!(Symbol, symbol.id).trading_status == "TRADING"
  end

  test "gold persists its source timestamp and has no invented candles or Jev eligibility" do
    queue([[%{"symbol" => "XAU", "name" => "Gold"}]])
    assert {:ok, :discovered} = SourceSync.metadata("gold_api")
    symbol = Repo.get_by!(Symbol, exchange: "gold_api", symbol: "XAUUSD")
    old = DateTime.add(MarketFixtures.now(), -86_400)

    queue([
      %{
        "symbol" => "XAU",
        "currency" => "USD",
        "price" => "4100.123456789",
        "updatedAt" => DateTime.to_iso8601(old)
      }
    ])

    assert {:ok, :snapshot_only} = SourceSync.sync("gold_api", symbol.id)
    assert {:ok, market, _} = MarketData.get_market("XAUUSD", %{"exchange" => "gold_api"})
    assert market.price_freshness.status == "stale"
    assert market.analysis_unavailable_reason == "gold_history_unavailable"
    assert market.ticker_stats == nil
    assert Repo.aggregate(Candle, :count) == 0
    assert SourceSync.active_symbols("coinbase") == []
  end

  test "41-second source clock lead permits USD discovery, snapshots and analysis inputs" do
    now = MarketFixtures.now()
    source_time = DateTime.add(now, 41)
    date = Calendar.strftime(source_time, "%a, %d %b %Y %H:%M:%S GMT")

    products = [
      %{
        "id" => "BTC-USD",
        "base_currency" => "BTC",
        "quote_currency" => "USD",
        "status" => "online"
      }
    ]

    Process.put(
      :source_responses,
      Enum.map([products, ticker("300", source_time), stats(), candles()], fn body ->
        MarketFixtures.response(body, 200, %{"date" => [date]})
      end)
    )

    assert {:ok, :discovered} = SourceSync.metadata("coinbase")
    symbol = Repo.get_by!(Symbol, exchange: "coinbase", symbol: "BTCUSD")
    assert {:ok, 300} = SourceSync.sync("coinbase", symbol.id)
    assert Repo.get!(LatestPrice, symbol.id).data_at == source_time
    assert Repo.get!(LatestPrice, symbol.id).fetched_at == now
    assert Repo.get!(TickerStats, symbol.id).data_at == source_time
    assert {:ok, market, _} = MarketData.get_market("BTCUSD", %{"exchange" => "coinbase"})
    assert market.price_freshness.status == "fresh"
    assert market.stats_freshness.status == "fresh"
    assert {:ok, inputs} = MarketData.analysis_inputs(symbol.id, now)
    assert {:ok, _} = TechnicalAnalysis.features(inputs.candles, now)
  end

  test "Coinbase excludes candles not yet closed by the HTTP server clock" do
    symbol = coinbase()

    date =
      MarketFixtures.now() |> DateTime.add(-41) |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")

    Process.put(:source_responses, [
      MarketFixtures.response(ticker()),
      MarketFixtures.response(stats()),
      MarketFixtures.response(candles(), 200, %{"date" => [date]})
    ])

    assert {:ok, 299} = SourceSync.sync("coinbase", symbol.id)
    assert Sync.state(symbol.id, "source_candles").missing_count == 1
    last_close = Repo.one(from c in Candle, select: max(c.close_time))
    assert DateTime.compare(last_close, DateTime.add(MarketFixtures.now(), -46)) == :lt
  end

  test "incomplete Coinbase history records gaps and cannot produce model features" do
    symbol = coinbase()
    queue([ticker(), stats(), tl(candles())])
    assert {:ok, 299} = SourceSync.sync("coinbase", symbol.id)
    state = Sync.state(symbol.id, "source_candles")
    assert state.status == "gaps"
    assert state.missing_count == 1
    assert {:ok, input} = MarketData.analysis_inputs(symbol.id, MarketFixtures.now())

    assert {:error, :insufficient_candles} =
             TechnicalAnalysis.features(input.candles, MarketFixtures.now())
  end

  test "429 is shared across source jobs and never triggers immediate retries" do
    symbol = coinbase()

    Process.put(:source_responses, [
      MarketFixtures.response(%{}, 429, %{"retry-after" => ["240"]})
    ])

    assert {:error, {:rate_limited, 240}} = SourceSync.sync("coinbase", symbol.id)

    assert DateTime.diff(
             Repo.get!(CollectorState, "coinbase").blocked_until,
             MarketFixtures.now()
           ) == 240

    assert {:error, :source_cooldown} = SourceSync.metadata("coinbase")
    assert Process.get(:source_responses) == []
  end

  test "forced metadata refresh repairs source availability without changing user preferences" do
    symbol = coinbase()

    Repo.update_all(from(s in Symbol, where: s.id == ^symbol.id),
      set: [trading_status: "UNAVAILABLE", enabled: false]
    )

    queue([
      [
        %{
          "id" => "BTC-USD",
          "base_currency" => "BTC",
          "quote_currency" => "USD",
          "status" => "online"
        }
      ]
    ])

    assert {:ok, :discovered} = SourceSync.metadata("coinbase", force: true)
    assert Repo.get!(Symbol, symbol.id).trading_status == "TRADING"
    refute Repo.get!(Symbol, symbol.id).enabled
  end

  test "older snapshots cannot replace newer prices and partial fetch failure is explicit" do
    symbol = coinbase()
    now = MarketFixtures.now()

    Repo.insert!(%LatestPrice{
      market_symbol_id: symbol.id,
      price: Decimal.new("400"),
      data_at: now,
      fetched_at: now,
      updated_at: now
    })

    Process.put(:source_responses, [
      MarketFixtures.response(ticker("200", DateTime.add(now, -30))),
      {:error, :timeout}
    ])

    assert {:error, :transport_error} = SourceSync.sync("coinbase", symbol.id)
    assert Decimal.equal?(Repo.get!(LatestPrice, symbol.id).price, "400")
    assert Sync.state(symbol.id, "snapshot").status == "error"
  end

  test "parser rejects malformed, future and non-finite prices; excludes open candles" do
    now = MarketFixtures.now()
    assert {:error, _} = SourceParser.price(ticker("NaN"), "coinbase", now)
    assert {:error, _} = SourceParser.price(ticker("0"), "coinbase", now)
    assert {:ok, _} = SourceParser.price(ticker("10", DateTime.add(now, 60)), "coinbase", now)
    assert {:error, _} = SourceParser.price(ticker("10", DateTime.add(now, 61)), "coinbase", now)
    assert {:error, _} = SourceParser.price(%{"price" => "10"}, "coinbase", now)
    assert {:error, _} = SourceParser.candles([[1, "10", "20", "15", "16", "1"]], now)
    assert {:error, _} = SourceParser.candles([[0, "20", "10", "15", "16", "1"]], now)
    open = div(DateTime.to_unix(now), 3600) * 3600
    assert {:ok, []} = SourceParser.candles([[open, "10", "20", "15", "16", "1"]], now)
  end

  test "JSON numeric prices retain decimal precision and stale HTTP responses are rejected" do
    {:ok, response} = MarketFixtures.response(%{})

    body =
      ~s({"symbol":"XAU","currency":"USD","price":0.1234567890123456789,"updatedAt":"2026-10-17T12:00:00Z"})

    Process.put(:source_responses, [{:ok, %{response | body: body}}])
    assert {:ok, decoded, _} = SourceHTTP.get("gold_api", "/price/XAU/USD")
    assert Decimal.equal?(decoded["price"], "0.1234567890123456789")

    Process.put(:source_responses, [
      MarketFixtures.response(%{}, 200, %{"date" => ["Thu, 01 Jan 2026 00:00:00 GMT"]})
    ])

    assert {:error, {:stale_response, age}} = SourceHTTP.get("coinbase", "/products")
    assert age > 120
  end

  test "invalid JSON and missing or malformed HTTP dates remain distinct" do
    {:ok, response} = MarketFixtures.response([])

    for {body, headers, reason} <- [
          {"<html>upstream error</html>", response.headers, :invalid_json},
          {"[]", %{}, :missing_response_date},
          {"[]", %{"date" => []}, :invalid_response_date},
          {"[]", %{"date" => ["invalid"]}, :invalid_response_date},
          {"[]", %{"date" => ["Sat, 32 Oct 2026 12:00:00 GMT"]}, :invalid_response_date}
        ] do
      Process.put(:source_responses, [{:ok, %{response | body: body, headers: headers}}])
      assert {:error, ^reason} = SourceHTTP.get("coinbase", "/products")
    end
  end

  test "HTTP dates keep the freshness boundaries and report clock offset in seconds" do
    now = MarketFixtures.now()

    for {offset, expected} <- [
          {-121, {:error, {:stale_response, 121}}},
          {-120, :ok},
          {5, :ok},
          {41, :ok},
          {60, :ok},
          {61, {:error, {:future_response, 61}}}
        ] do
      date = now |> DateTime.add(offset) |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
      Process.put(:source_responses, [MarketFixtures.response([], 200, %{"date" => [date]})])
      result = SourceHTTP.get("coinbase", "/products")

      if expected == :ok do
        assert {:ok, [], data_at} = result
        assert DateTime.diff(data_at, now) == offset
      else
        assert result == expected
      end
    end
  end

  test "metadata preserves the specific response error without registering USD symbols" do
    date =
      MarketFixtures.now() |> DateTime.add(600) |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")

    Process.put(:source_responses, [MarketFixtures.response([], 200, %{"date" => [date]})])

    assert {:error, {:future_response, 600}} = SourceSync.metadata("coinbase")
    assert SourceSync.active_symbols("coinbase") == []
    assert Repo.get!(CollectorState, "coinbase").last_error == "{:future_response, 600}"
  end
end
