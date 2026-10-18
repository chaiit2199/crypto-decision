defmodule CryptoDecisionLab.MarketData.SourceWorker do
  @moduledoc "Bounded public-source jobs; errors are retained by Oban and retried next scheduled interval."
  use Oban.Worker,
    queue: :sources,
    max_attempts: 1,
    unique: [period: 110, fields: [:worker, :args], states: [:available, :scheduled, :executing]]

  @impl true
  def perform(%Oban.Job{args: %{"source" => source, "symbol_id" => id}}),
    do: CryptoDecisionLab.MarketData.SourceSync.sync(source, id)

  def perform(%Oban.Job{args: %{"source" => source}}),
    do: CryptoDecisionLab.MarketData.SourceSync.metadata(source)
end
