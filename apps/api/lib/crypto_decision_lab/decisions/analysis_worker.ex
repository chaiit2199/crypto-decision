defmodule CryptoDecisionLab.Decisions.AnalysisWorker do
  @moduledoc "Schedules five-minute research runs separately from market collection."
  use Oban.Worker,
    queue: :analysis,
    max_attempts: 1,
    unique: [
      period: 240,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable, :completed]
    ]

  alias CryptoDecisionLab.Decisions

  @impl true
  def perform(%Oban.Job{args: args}) do
    result =
      case args do
        %{"symbol_id" => id, "slot" => slot} -> Decisions.analyze(id, slot)
        %{} -> Decisions.enqueue_all()
      end

    case result do
      {:ok, _} -> :ok
      {:error, :busy} -> {:snooze, 2}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def timeout(_job), do: 35_000
end
