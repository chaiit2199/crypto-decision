defmodule CryptoDecisionLab.MarketData.SyncWorker do
  @moduledoc "Durable dispatch only; synchronization logic lives in context services."
  use Oban.Worker,
    queue: :market,
    max_attempts: 10,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias CryptoDecisionLab.MarketData

  @doc "Queue historical work behind current market snapshots."
  @spec enqueue(map()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def enqueue(args) do
    kind = Map.get(args, :kind) || Map.get(args, "kind")
    priority = if kind in ["backfill", "repair", "short_candles"], do: 3, else: 0
    args |> new(priority: priority) |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: args}) do
    case MarketData.execute_sync(args) do
      {:ok, :more} -> {:snooze, 1}
      {:ok, _} -> :ok
      {:error, :collector_busy} -> {:snooze, 5}
      {:error, {:cooldown, seconds}} -> {:snooze, seconds}
      {:error, :symbol_unavailable} -> {:cancel, :symbol_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end
end
