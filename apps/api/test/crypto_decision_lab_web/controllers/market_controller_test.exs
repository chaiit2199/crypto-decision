defmodule CryptoDecisionLabWeb.MarketControllerTest do
  use CryptoDecisionLabWeb.ConnCase
  alias CryptoDecisionLab.MarketData.{Universe, Sync}
  alias CryptoDecisionLab.MarketFixtures, as: F

  setup do
    F.configure()
  end

  test "market index includes unsupported assets with explicit missing data", %{conn: conn} do
    Universe.seed()
    body = conn |> get("/api/markets") |> json_response(200)
    assert length(body["data"]) == 32
    assert body["meta"]["total"] == 32
    assert Enum.all?(body["data"], &(&1["availability"] == "unavailable"))
  end

  test "returns decimal strings and freshness rather than floats", %{conn: conn} do
    F.symbol()
    F.queue([F.response([%{"symbol" => "BTCUSDT", "price" => "0.000000123456789"}])])
    assert {:ok, 1} = Sync.prices()
    body = conn |> get("/api/markets/BTCUSDT") |> json_response(200)
    assert body["data"]["latest_price"]["price"] == "0.000000123456789"
    assert body["data"]["price_freshness"]["status"] == "fresh"
    assert body["data"]["stats_freshness"]["status"] == "missing"
  end

  test "validates pagination, unknown symbols and bounded time queries", %{conn: conn} do
    assert conn |> get("/api/markets?page_size=10001") |> json_response(400)
    assert conn |> get("/api/markets/NOSYMBOL") |> json_response(404)
    F.symbol()
    assert conn |> get("/api/markets/BTCUSDT/candles?timeframe=1m") |> json_response(400)

    assert conn
           |> get("/api/markets/BTCUSDT/candles?from=2020-01-01T00:00:00Z")
           |> json_response(400)

    assert conn |> get("/api/markets/BTCUSDT/candles?limit=-1") |> json_response(400)

    assert conn
           |> get("/api/markets/BTCUSDT/candles?from=2026-10-17T01:00:00Z&timeframe=4h")
           |> json_response(400)
  end

  test "analysis endpoint is a read-only empty state until a worker stores a result", %{
    conn: conn
  } do
    F.symbol()

    assert %{"data" => %{"enabled" => false, "analysis" => nil}} =
             conn |> get("/api/markets/BTCUSDT/analysis") |> json_response(200)

    assert conn |> get("/api/markets/UNKNOWN/analysis") |> json_response(404)
  end

  test "health and synchronization endpoints return structured JSON", %{conn: conn} do
    assert %{"data" => %{"database" => "up"}} = conn |> get("/api/health") |> json_response(200)

    assert %{"data" => %{"enabled" => false}} =
             conn |> get("/api/system/market-data-status") |> json_response(200)
  end

  test "candles return chronological data and reject aggregation over gaps", %{conn: conn} do
    symbol = F.symbol()
    F.queue([F.response(for n <- 0..3, do: F.kline(F.start() + n * F.hour()))])
    assert {:ok, :complete} = Sync.candles(symbol.id, :backfill, from: F.start())
    path = "/api/markets/BTCUSDT/candles?from=2026-10-17T00:00:00Z&to=2026-10-17T04:00:00Z"
    body = conn |> get(path) |> json_response(200)
    assert length(body["data"]) == 4
    assert hd(body["data"])["open"] == "100.12345678901234567890"
    body = conn |> get(path <> "&timeframe=4h") |> json_response(200)
    assert length(body["data"]) == 1

    CryptoDecisionLab.Repo.query!(
      "DELETE FROM market_candles WHERE open_time = '2026-10-17 01:00:00'"
    )

    assert conn |> get(path <> "&timeframe=4h") |> json_response(422)
  end
end
