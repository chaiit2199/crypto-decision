defmodule CryptoDecisionLab.MarketData.BinanceTest do
  use ExUnit.Case, async: true
  alias CryptoDecisionLab.MarketData.Binance
  alias CryptoDecisionLab.MarketFixtures, as: F

  @opts [
    transport: CryptoDecisionLab.FixtureTransport,
    budget: CryptoDecisionLab.FixtureBudget,
    now: &F.now/0,
    sleep: &__MODULE__.no_sleep/1
  ]
  def no_sleep(_), do: :ok

  test "batches symbols using the documented JSON parameter" do
    F.queue([F.response([%{"symbol" => "BTCUSDT", "price" => "100"}])])
    assert {:ok, _} = Binance.prices(["BTCUSDT", "ETHUSDT"], @opts)
    assert [{"/ticker/price", params}] = Process.get(:http_calls)
    assert Jason.decode!(params[:symbols]) == ["BTCUSDT", "ETHUSDT"]
  end

  test "retries 5xx and network errors at most twice" do
    F.queue([F.response(%{}, 503), {:error, :timeout}, F.response([])])
    assert {:ok, _} = Binance.prices(["BTCUSDT"], @opts)
    assert length(Process.get(:http_calls)) == 3
    F.queue(List.duplicate({:error, :timeout}, 3))
    assert {:error, :network_error} = Binance.prices(["BTCUSDT"], @opts)
    assert length(Process.get(:http_calls)) == 6
  end

  test "timestamps snapshots on receipt so request latency does not consume clock tolerance" do
    received_at = DateTime.add(F.now(), 8)
    server_time = DateTime.add(received_at, 60)
    date = Calendar.strftime(server_time, "%a, %d %b %Y %H:%M:%S GMT")
    Process.put(:received_at, F.now())

    F.queue([
      fn _, _ ->
        Process.put(:received_at, received_at)
        F.response([], 200, %{"date" => [date]})
      end
    ])

    opts = Keyword.put(@opts, :now, fn -> Process.get(:received_at) end)

    assert {:ok, %{fetched_at: ^received_at, server_time: actual_server_time}} =
             Binance.prices(["BTCUSDT"], opts)

    assert DateTime.compare(actual_server_time, server_time) == :eq
  end

  test "HTTP clock skew beyond 60 seconds is rejected" do
    for offset <- [-61, 61] do
      date = F.now() |> DateTime.add(offset) |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
      F.queue([F.response([], 200, %{"date" => [date]})])
      assert {:error, :stale_response} = Binance.prices(["BTCUSDT"], @opts)
    end
  end

  test "429 and 418 use shared cooldown with no immediate retry" do
    for status <- [429, 418] do
      F.queue([F.response(%{}, status, %{"retry-after" => ["120"]})])
      assert {:error, {:cooldown, 120}} = Binance.prices(["BTCUSDT"], @opts)
      assert Process.get(:blocked) == {120, status}
    end

    assert length(Process.get(:http_calls)) == 2
  end

  test "safe error codes, malformed JSON, stale and missing Date headers" do
    F.queue([F.response(%{"code" => -1121, "msg" => "Invalid symbol"}, 400)])
    assert {:error, {:upstream_http, 400, -1121}} = Binance.prices(["BAD"], @opts)
    {:ok, response} = F.response([])

    for response <- [
          %{response | body: "invalid"},
          %{response | headers: %{}},
          %{response | headers: %{"date" => ["Fri, 16 Oct 2026 12:00:10 GMT"]}}
        ] do
      F.queue([{:ok, response}])
      assert {:error, _} = Binance.prices(["BTCUSDT"], @opts)
    end
  end
end
