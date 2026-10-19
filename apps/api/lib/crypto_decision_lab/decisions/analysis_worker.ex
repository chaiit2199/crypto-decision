defmodule CryptoDecisionLab.Decisions.AnalysisWorker do
  @moduledoc "Schedules configured UTC research slots separately from market collection."
  use Oban.Worker,
    queue: :analysis,
    max_attempts: 1,
    unique: [
      period: 55,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable, :completed]
    ]

  alias CryptoDecisionLab.Decisions

  @impl true
  def perform(%Oban.Job{args: args}) do
    result =
      case args do
        %{"symbol_id" => id, "slot" => slot} -> Decisions.analyze(id, slot)
        %{} -> Decisions.enqueue_due()
      end

    case result do
      {:ok, result} -> if Decisions.awaiting_data?(result), do: {:snooze, 30}, else: :ok
      {:error, :busy} -> {:snooze, 2}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def timeout(_job), do: 35_000
end
