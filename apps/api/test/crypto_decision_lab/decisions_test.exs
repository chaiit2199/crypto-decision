defmodule CryptoDecisionLab.DecisionsTest do
  use CryptoDecisionLab.DataCase

  alias CryptoDecisionLab.{
    Decisions,
    MarketData,
    MarketFixtures,
    AnalysisFixtures,
    MockDecisionProvider
  }

  alias CryptoDecisionLab.Decisions.{Analysis, AnalysisWorker, JevProvider}

  setup do
    MarketFixtures.configure()

    previous =
      Map.new(
        [:jev, :decision_provider, :jev_request, :analysis_interval_seconds],
        &{&1, Application.get_env(:crypto_decision_lab, &1)}
      )

    Application.put_env(:crypto_decision_lab, :jev,
      enabled: true,
      api_key: "fixture-only",
      model: "fixture-jev"
    )

    Application.put_env(:crypto_decision_lab, :decision_provider, MockDecisionProvider)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:crypto_decision_lab, key)
        {key, value} -> Application.put_env(:crypto_decision_lab, key, value)
      end)
    end)

    symbol = MarketFixtures.symbol()

    slot =
      div(DateTime.to_unix(MarketFixtures.now()), Decisions.interval_seconds()) *
        Decisions.interval_seconds()

    %{symbol: symbol, slot: slot}
  end

  test "persists real provider contract once per slot and reads never call it", %{
    symbol: symbol,
    slot: slot
  } do
    AnalysisFixtures.seed(symbol)

    assert {:ok, %Analysis{status: "ready", signal: "BUY", model: "fixture-jev"} = row} =
             Decisions.analyze(symbol.id, slot)

    assert_receive {:jev_called, features}
    assert features["symbol"] == "BTCUSDT"
    assert features["ema20"]
    assert is_map(features["context_timeframes"]["1h"])
    assert features["context_timeframes"]["1h"]["status"] in ["ready", "no_data"]
    assert row.answers["holding_horizon"]["choice"] == "INTRADAY"
    assert row.configuration_version == "hourly-research-v4-horizon"
    assert {:ok, %{id: id}} = Decisions.analyze(symbol.id, slot)
    assert id == row.id

    assert {:ok, %{analysis: %{signal: "BUY", risk_result: %{"execution_allowed" => false}}}, _} =
             MarketData.analysis("BTCUSDT")

    refute_receive {:jev_called, _}
    assert Repo.aggregate(Analysis, :count) == 1
    assert {:ok, :expired} = Decisions.analyze(symbol.id, slot - Decisions.interval_seconds())
  end

  test "missing and stale inputs skip paid analysis", %{symbol: symbol, slot: slot} do
    assert {:ok, %{status: "no_data", signal: "NO_DATA", reason: "missing_snapshots"}} =
             Decisions.analyze(symbol.id, slot)

    other = MarketFixtures.symbol("ARB")
    AnalysisFixtures.seed(other)

    stale_at =
      DateTime.add(MarketFixtures.now(), -(MarketData.price_max_age_seconds() + 30))

    Repo.update_all(CryptoDecisionLab.MarketData.LatestPrice,
      set: [fetched_at: stale_at, data_at: stale_at]
    )

    assert {:ok, %{reason: "stale_price"}} = Decisions.analyze(other.id, slot)
    refute_receive {:jev_called, _}
  end

  test "stale data is retried within the same slot, then calls Jev once after refresh", %{
    symbol: symbol,
    slot: slot
  } do
    AnalysisFixtures.seed(symbol)
    now = MarketFixtures.now()
    stale = DateTime.add(now, -(MarketData.price_max_age_seconds() + 1))
    Repo.update_all(MarketData.LatestPrice, set: [data_at: stale, fetched_at: stale])
    job = %Oban.Job{args: %{"symbol_id" => symbol.id, "slot" => slot}}
    assert {:snooze, 30} = AnalysisWorker.perform(job)
    row = Repo.one!(Analysis)
    assert row.reason == "stale_price"
    assert {:snooze, 30} = AnalysisWorker.perform(job)
    refute_receive {:jev_called, _}
    Repo.update_all(MarketData.LatestPrice, set: [data_at: now, fetched_at: now])
    assert :ok = AnalysisWorker.perform(job)
    assert_receive {:jev_called, _}
    updated = Repo.one!(Analysis)
    assert updated.id == row.id
    assert updated.status == "ready"
    assert updated.reason == nil
    assert updated.valid_until == row.valid_until
    assert :ok = AnalysisWorker.perform(job)
    refute_receive {:jev_called, _}
  end

  test "pending input stops retrying when the slot expires or the asset is disabled", %{
    symbol: symbol,
    slot: slot
  } do
    job = %Oban.Job{args: %{"symbol_id" => symbol.id, "slot" => slot}}
    assert {:snooze, 30} = AnalysisWorker.perform(job)
    Process.put(:now, DateTime.from_unix!(slot + Decisions.interval_seconds()))
    assert :ok = AnalysisWorker.perform(job)
    Process.put(:now, MarketFixtures.now())
    Repo.update_all(MarketData.Asset, set: [enabled: false])
    assert :ok = AnalysisWorker.perform(job)
    assert Repo.one!(Analysis).reason == "symbol_unavailable"
    refute_receive {:jev_called, _}
  end

  test "Binance statistics with a 41-second clock lead reach Jev after synchronization", %{
    symbol: symbol,
    slot: slot
  } do
    AnalysisFixtures.seed(symbol)
    Repo.delete_all(MarketData.TickerStats)
    now = MarketFixtures.now()
    source_time = DateTime.add(now, 41)
    date = Calendar.strftime(source_time, "%a, %d %b %Y %H:%M:%S GMT")

    stats =
      Map.put(MarketFixtures.stats(), "closeTime", DateTime.to_unix(source_time, :millisecond))

    MarketFixtures.queue([MarketFixtures.response([stats], 200, %{"date" => [date]})])

    assert {:ok, 1} = MarketData.Sync.stats()
    assert Repo.get!(MarketData.TickerStats, symbol.id).data_at == source_time
    assert {:ok, %{status: "ready"}} = Decisions.analyze(symbol.id, slot)
    assert_receive {:jev_called, %{"stats_at" => stats_at}}
    assert stats_at == DateTime.to_iso8601(source_time)
  end

  test "Coinbase snapshot clock lead is consistent in market reads and Jev", %{
    symbol: symbol,
    slot: slot
  } do
    symbol =
      symbol
      |> Ecto.Changeset.change(exchange: "coinbase", symbol: "BTCUSD", quote_asset: "USD")
      |> Repo.update!()

    AnalysisFixtures.seed(symbol)
    time = DateTime.add(MarketFixtures.now(), 60)
    Repo.update_all(MarketData.LatestPrice, set: [data_at: time])
    Repo.update_all(MarketData.TickerStats, set: [data_at: time])

    assert {:ok, market, _} = MarketData.get_market("BTCUSD", %{"exchange" => "coinbase"})
    assert market.price_freshness.status == "fresh"
    assert market.stats_freshness.status == "fresh"
    assert {:ok, %{status: "ready"}} = Decisions.analyze(symbol.id, slot)
    assert_receive {:jev_called, %{"symbol" => "BTCUSD", "quote_asset" => "USD"}}
  end

  test "snapshots beyond the skew limit or stale stats still block Jev", %{
    symbol: symbol,
    slot: slot
  } do
    AnalysisFixtures.seed(symbol)
    now = MarketFixtures.now()
    future = DateTime.add(now, 61)
    Repo.update_all(MarketData.LatestPrice, set: [data_at: future])
    assert {:error, :stale_price} = MarketData.analysis_inputs(symbol.id, now)
    assert MarketData.freshness(future, 600).status == "stale"
    Repo.update_all(MarketData.LatestPrice, set: [data_at: now])

    for time <- [future, DateTime.add(now, -601)] do
      Repo.update_all(MarketData.TickerStats, set: [data_at: time])
      assert {:error, :stale_stats} = MarketData.analysis_inputs(symbol.id, now)
    end

    assert {:ok, %{status: "no_data", reason: "stale_stats"}} = Decisions.analyze(symbol.id, slot)
    refute_receive {:jev_called, _}
  end

  test "auth failure sets shared cooldown and cannot become a trading signal", %{
    symbol: symbol,
    slot: slot
  } do
    AnalysisFixtures.seed(symbol)
    Process.put(:jev_result, {:error, "authentication_failed", 900})
    assert {:ok, %{status: "error", signal: "NO_DATA"}} = Decisions.analyze(symbol.id, slot)
    assert_receive {:jev_called, _}
    other = MarketFixtures.symbol("ARB")
    AnalysisFixtures.seed(other)

    assert {:ok, %{status: "error", reason: "authentication_failed"}} =
             Decisions.analyze(other.id, slot)

    refute_receive {:jev_called, _}
  end

  test "dispatcher is idempotent in the same slot", %{symbol: symbol, slot: slot} do
    assert {:ok, 1} = Decisions.enqueue_all()
    assert {:ok, 1} = Decisions.enqueue_all()
    jobs = Repo.all(from j in Oban.Job, where: j.queue == "analysis")

    assert [%{args: %{"symbol_id" => id, "slot" => ^slot}}] = jobs
    assert id == symbol.id
  end

  test "adapter sends verified schema and sanitizes errors" do
    Application.put_env(:crypto_decision_lab, :jev_request, fn options ->
      assert options[:auth] == {:bearer, "fixture-only"}
      assert options[:redirect] == false
      assert options[:retry] == false
      assert options[:json].questions.trend.type == "choice"
      assert options[:json].questions.holding_horizon.type == "choice"

      assert options[:json].questions.holding_horizon.criteria
             |> Map.keys()
             |> Enum.map(&to_string/1)
             |> Enum.sort() == ~w(INTRADAY SCALP SWING UNSUITABLE)

      {:ok, %{status: 401, body: %{"sensitive" => "do not propagate"}}}
    end)

    assert {:error, "authentication_failed", 900} = JevProvider.analyze(%{})

    assert {:error, "rate_limited", 90} =
             JevProvider.decode({:ok, %{status: 429, headers: %{"retry-after" => ["90"]}}})

    assert {:error, "transport_error", 60} = JevProvider.decode({:error, :timeout})
    assert {:error, "upstream_unavailable", 60} = JevProvider.decode({:ok, %{status: 503}})
  end

  test "independent connections cannot call Jev concurrently", %{symbol: symbol, slot: slot} do
    options = Repo.config() |> Keyword.take([:hostname, :port, :username, :password, :database])
    connection = start_supervised!({Postgrex, options})
    Postgrex.query!(connection, "SELECT pg_advisory_lock(764218, 1)", [])
    assert {:error, :busy} = Decisions.analyze(symbol.id, slot)
    refute_receive {:jev_called, _}
    Postgrex.query!(connection, "SELECT pg_advisory_unlock(764218, 1)", [])
    assert {:ok, %{status: "no_data"}} = Decisions.analyze(symbol.id, slot)
  end

  test "invalid choices, missing answers and invalid probabilities are rejected" do
    body = MockDecisionProvider.response()
    assert {:ok, ^body} = JevProvider.decode({:ok, %{status: 200, body: body}})

    for invalid <- [
          put_in(body, ["answers", "trend", "choice"], "BUY_NOW"),
          put_in(body, ["answers", "trend", "confidence"], 2),
          put_in(body, ["answers", "trend", "probabilities", "BULLISH"], 0.1),
          put_in(body, ["answers", "trend"], nil),
          put_in(body, ["answers", "holding_horizon", "choice"], "LONG_TERM"),
          Map.update!(body, "answers", &Map.delete(&1, "holding_horizon"))
        ] do
      assert {:error, "invalid_response", 60} =
               JevProvider.decode({:ok, %{status: 200, body: invalid}})
    end
  end

  test "a recovered local key bypasses only the old missing-key cooldown", %{
    symbol: symbol,
    slot: slot
  } do
    AnalysisFixtures.seed(symbol)

    Repo.query!(
      "INSERT INTO jev_provider_states (id, blocked_until, last_error) VALUES (1, $1, $2)",
      [DateTime.to_naive(DateTime.add(MarketFixtures.now(), 900)), "missing_api_key"]
    )

    assert {:ok, %{status: "ready"}} = Decisions.analyze(symbol.id, slot)
    assert_receive {:jev_called, _}
  end

  test "an actually missing key retains its cooldown", %{symbol: symbol, slot: slot} do
    AnalysisFixtures.seed(symbol)

    Application.put_env(:crypto_decision_lab, :jev,
      enabled: true,
      api_key: nil,
      model: "fixture-jev"
    )

    Repo.query!(
      "INSERT INTO jev_provider_states (id, blocked_until, last_error) VALUES (1, $1, $2)",
      [DateTime.to_naive(DateTime.add(MarketFixtures.now(), 900)), "missing_api_key"]
    )

    assert {:ok, %{status: "error", reason: "missing_api_key"}} =
             Decisions.analyze(symbol.id, slot)

    refute_receive {:jev_called, _}
  end

  test "fifteen-minute slots drive dispatch, expiry and successive jobs", %{
    symbol: symbol,
    slot: slot
  } do
    Application.put_env(:crypto_decision_lab, :analysis_interval_seconds, 900)
    AnalysisFixtures.seed(symbol)
    assert {:ok, row} = Decisions.analyze(symbol.id, slot)
    assert DateTime.diff(row.valid_until, row.slot) == 900
    assert {:ok, :expired} = Decisions.analyze(symbol.id, slot - 900)
    assert {:ok, 1} = Decisions.enqueue_due()
    Process.put(:now, DateTime.add(MarketFixtures.now(), 60))
    assert {:ok, 0} = Decisions.enqueue_due()
    Process.put(:now, DateTime.add(MarketFixtures.now(), 900))
    assert {:ok, 1} = Decisions.enqueue_due()
    assert Repo.aggregate(from(j in Oban.Job, where: j.queue == "analysis"), :count) == 2
  end

  test "the adapter distinguishes a configured credential from an empty value" do
    assert JevProvider.configured?()
    Application.put_env(:crypto_decision_lab, :jev, api_key: "  ")
    refute JevProvider.configured?()
    assert {:error, "missing_api_key", 900} = JevProvider.analyze(%{})
  end
end
