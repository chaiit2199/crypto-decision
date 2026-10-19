defmodule CryptoDecisionLabWeb.TradingControllerTest do
  use CryptoDecisionLabWeb.ConnCase, async: false
  alias CryptoDecisionLab.{MarketFixtures, Repo}
  alias CryptoDecisionLab.Trading.Simulation

  setup do
    MarketFixtures.configure()
    %{symbol: MarketFixtures.symbol()}
  end

  test "workbench reports no-data and scanner includes blocked markets without provider calls", %{
    conn: conn,
    symbol: symbol
  } do
    response =
      conn
      |> get("/api/markets/#{symbol.symbol}/workbench", %{style: "scalping"})
      |> json_response(200)

    assert response["data"]["exchange"] == "binance"
    assert response["data"]["market"] == "spot"
    assert response["data"]["timeframes"] == %{"trend" => "1h", "setup" => "15m", "entry" => "5m"}
    assert response["data"]["trade_eligibility"] == "NO_DATA"
    assert response["data"]["execution_allowed"] == false
    assert response["data"]["simulations"] == []
    assert [_] = conn |> get("/api/opportunities") |> json_response(200) |> Map.fetch!("data")
    assert conn |> get("/api/opportunities", %{style: "bad"}) |> json_response(400)
  end

  test "plan is decimal JSON, identity-bound, and never persists a paper order", %{
    conn: conn,
    symbol: symbol
  } do
    input = %{
      equity: "1000",
      risk_percent: "0.5",
      entry: "100",
      stop_loss: "99",
      take_profit: "102",
      fee_percent: "0.1",
      slippage_percent: "0.05"
    }

    response = conn |> post("/api/markets/#{symbol.symbol}/plan", input) |> json_response(200)
    assert response["data"]["symbol"] == symbol.symbol
    assert response["data"]["risk_budget"] == "5"
    assert response["data"]["mode"] == "hypothetical"
    assert Repo.aggregate(Simulation, :count) == 0

    assert conn
           |> post("/api/markets/#{symbol.symbol}/plan", %{input | stop_loss: "101"})
           |> json_response(400)

    assert conn
           |> post("/api/markets/#{symbol.symbol}/plan", Map.put(input, :exchange, "coinbase"))
           |> json_response(404)
  end
end
