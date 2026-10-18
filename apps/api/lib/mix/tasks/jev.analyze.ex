defmodule Mix.Tasks.Jev.Analyze do
  @shortdoc "Enqueue the current configured analysis slot for every active symbol"
  use Mix.Task

  @impl true
  def run(_) do
    Mix.Task.run("app.start")

    case CryptoDecisionLab.Decisions.enqueue_all() do
      {:ok, count} -> Mix.shell().info("Queued #{count} Jev analysis jobs")
      {:error, _} -> Mix.raise("Unable to enqueue Jev analysis jobs")
    end
  end
end
