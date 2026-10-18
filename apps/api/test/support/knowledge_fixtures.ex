defmodule CryptoDecisionLab.KnowledgeFixtures do
  @moduledoc "Synthetic inputs for knowledge tests; these are not market evidence."
  alias CryptoDecisionLab.TradingKnowledge

  def strategy do
    TradingKnowledge.library_path()
    |> Path.join("ema_trend_continuation.v1.json")
    |> File.read!()
    |> Jason.decode!()
  end

  def now, do: ~U[2026-10-18 12:00:10.000000Z]

  def snapshot do
    features = %{
      "close" => "110",
      "ema20" => "105",
      "ema50" => "100",
      "rsi14" => "55",
      "return_1h_percent" => "1",
      "return_24h_percent" => "3"
    }

    %{
      "symbol" => "BTCUSDT",
      "timeframe" => "1h",
      "regime" => "uptrend",
      "as_of" => "2026-10-18T11:59:59.999000Z",
      "available_at" => "2026-10-18T12:00:05Z",
      "feature_version" => "hourly-v1",
      "dataset_hash" => String.duplicate("a", 64),
      "features" =>
        Map.new(features, fn {name, value} ->
          {name,
           %{
             "value" => value,
             "observed_at" => "2026-10-18T11:59:59.999000Z",
             "available_at" => "2026-10-18T12:00:05Z"
           }}
        end)
    }
  end
end
