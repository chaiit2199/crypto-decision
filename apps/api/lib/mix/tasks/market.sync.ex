defmodule Mix.Tasks.Market.Sync do
  use Mix.Task
  @shortdoc "Run an internal sync, or enqueue durable historical backfill"
  @moduledoc "Usage: mix market.sync bootstrap|metadata|prices|stats|candles|integrity|backfill [SYMBOL]"
  alias CryptoDecisionLab.{MarketData, Repo}
  alias CryptoDecisionLab.MarketData.{Symbol, SyncWorker}

  def run(args) do
    Mix.Task.run("app.start")

    result =
      case args do
        ["backfill", symbol] ->
          case Repo.get_by(Symbol, exchange: "binance", symbol: symbol) do
            nil -> {:error, :not_found}
            record -> SyncWorker.enqueue(%{kind: "backfill", symbol_id: record.id})
          end

        [kind] when kind in ~w(bootstrap metadata prices stats candles integrity) ->
          MarketData.execute_sync(%{"kind" => kind})

        _ ->
          Mix.raise(
            "Usage: mix market.sync bootstrap|metadata|prices|stats|candles|integrity|backfill [SYMBOL]"
          )
      end

    case result do
      {:ok, %Oban.Job{id: id}} ->
        Mix.shell().info(
          "Queued job #{id}; run server with MARKET_SYNC_ENABLED=true to process it"
        )

      {:ok, value} ->
        Mix.shell().info("Sync result: #{inspect(value)}")

      {:error, reason} ->
        Mix.raise("Sync failed: #{inspect(reason)}")
    end
  end
end
