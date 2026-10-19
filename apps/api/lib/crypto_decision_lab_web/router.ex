defmodule CryptoDecisionLabWeb.Router do
  use CryptoDecisionLabWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", CryptoDecisionLabWeb do
    pipe_through :api
    get "/health", MarketController, :health
    get "/markets", MarketController, :index
    get "/markets/:symbol", MarketController, :show
    get "/markets/:symbol/candles", MarketController, :candles
    get "/markets/:symbol/analysis", MarketController, :analysis
    get "/markets/:symbol/workbench", MarketController, :workbench
    post "/markets/:symbol/plan", MarketController, :plan
    get "/opportunities", MarketController, :opportunities
    get "/system/market-data-status", MarketController, :status
  end
end
