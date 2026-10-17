defmodule CryptoDecisionLabWeb.MarketController do
  use CryptoDecisionLabWeb, :controller
  alias CryptoDecisionLab.MarketData
  alias CryptoDecisionLabWeb.Response

  def index(conn, params), do: Response.send(conn, MarketData.list_markets(params))
  def show(conn, %{"symbol" => symbol}), do: Response.send(conn, MarketData.get_market(symbol))
  def analysis(conn, %{"symbol" => symbol}), do: Response.send(conn, MarketData.analysis(symbol))

  def candles(conn, %{"symbol" => symbol} = params),
    do: Response.send(conn, MarketData.candles(symbol, params))

  def status(conn, _params), do: Response.send(conn, MarketData.status())
  def health(conn, _params), do: Response.send(conn, MarketData.health())
end
