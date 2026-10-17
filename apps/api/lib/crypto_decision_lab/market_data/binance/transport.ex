defmodule CryptoDecisionLab.MarketData.Binance.Transport do
  @moduledoc "Unauthenticated, read-only Binance HTTP boundary."
  def get(path, params) do
    Req.get(
      url: Application.fetch_env!(:crypto_decision_lab, :binance_base_url) <> path,
      params: params,
      receive_timeout: 10_000,
      connect_options: [timeout: 5_000],
      retry: false,
      redirect: false,
      decode_body: false
    )
  end
end
