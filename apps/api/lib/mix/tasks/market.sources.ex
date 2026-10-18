defmodule Mix.Tasks.Market.Sources do
  use Mix.Task
  @shortdoc "Sync public Coinbase USD and XAU/USD reference data without placing orders"
  @moduledoc "Run with MARKET_SYNC_ENABLED=false JEV_ENABLED=false mix market.sources for a manual pass."

  def run([]) do
    Mix.Task.run("app.start")
    alias CryptoDecisionLab.MarketData.SourceSync

    for source <- ["coinbase", "gold_api"] do
      case SourceSync.metadata(source, force: true) do
        {:ok, _} ->
          for symbol <- SourceSync.active_symbols(source) do
            Mix.shell().info(
              "#{source} #{symbol.symbol}: #{inspect(SourceSync.sync(source, symbol.id))}"
            )
          end

        {:error, reason} ->
          Mix.raise("#{source} metadata failed: #{inspect(reason)}")
      end
    end
  end

  def run(_), do: Mix.raise("Usage: mix market.sources")
end
