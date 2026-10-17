defmodule CryptoDecisionLab.MarketFixtures do
  @moduledoc "Synthetic fixtures, not a claim of current exchange listings or prices."
  alias CryptoDecisionLab.{Repo, MarketData}
  alias MarketData.{Asset, Symbol, Universe}
  def now, do: ~U[2026-10-17 12:00:10.000000Z]
  def hour, do: 3_600_000
  def start, do: DateTime.to_unix(~U[2026-10-17 00:00:00Z], :millisecond)

  def kline(time \\ start()) do
    [
      time,
      "100.12345678901234567890",
      "110",
      "90",
      "105",
      "12.5",
      time + hour() - 1,
      "1250",
      3,
      "6",
      "600",
      "0"
    ]
  end

  def response(body, status \\ 200, headers \\ %{}) do
    {:ok,
     %{
       status: status,
       body: Jason.encode!(body),
       headers:
         Map.merge(
           %{
             "date" => [Calendar.strftime(now(), "%a, %d %b %Y %H:%M:%S GMT")],
             "x-mbx-used-weight-1m" => ["4"]
           },
           headers
         )
     }}
  end

  def queue(responses), do: Process.put(:http_responses, responses)

  def symbol(code \\ "BTC") do
    Universe.seed()
    asset = Repo.get_by!(Asset, symbol: code)

    Repo.insert!(%Symbol{
      asset_id: asset.id,
      exchange: "binance",
      symbol: code <> "USDT",
      base_asset: code,
      quote_asset: "USDT",
      trading_status: "TRADING",
      enabled: true
    })
  end

  def exchange(codes \\ ["BTC"]) do
    %{
      "rateLimits" => [
        %{
          "rateLimitType" => "REQUEST_WEIGHT",
          "interval" => "MINUTE",
          "intervalNum" => 1,
          "limit" => 6000
        }
      ],
      "symbols" =>
        Enum.map(
          codes,
          &%{
            "symbol" => &1 <> "USDT",
            "baseAsset" => &1,
            "quoteAsset" => "USDT",
            "status" => "TRADING",
            "isSpotTradingAllowed" => true
          }
        )
    }
  end

  def stats(code \\ "BTCUSDT") do
    %{
      "symbol" => code,
      "priceChange" => "-2",
      "priceChangePercent" => "-1.2",
      "highPrice" => "110",
      "lowPrice" => "90",
      "volume" => "12.5",
      "quoteVolume" => "1250",
      "count" => 3,
      "closeTime" => DateTime.to_unix(now(), :millisecond)
    }
  end

  def configure do
    old_transport = Application.fetch_env!(:crypto_decision_lab, :binance_transport)
    old_clock = Application.fetch_env!(:crypto_decision_lab, :clock)

    Application.put_env(
      :crypto_decision_lab,
      :binance_transport,
      CryptoDecisionLab.FixtureTransport
    )

    Application.put_env(:crypto_decision_lab, :clock, CryptoDecisionLab.FixtureClock)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:crypto_decision_lab, :binance_transport, old_transport)
      Application.put_env(:crypto_decision_lab, :clock, old_clock)
    end)

    :ok
  end
end
