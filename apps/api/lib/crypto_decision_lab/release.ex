defmodule CryptoDecisionLab.Release do
  @moduledoc "Database migrations for releases without starting collectors or the HTTP server."
  @app :crypto_decision_lab

  @spec migrate() :: :ok
  def migrate do
    {:ok, _} = Application.ensure_all_started(:ssl)
    :ok = Application.ensure_loaded(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end
end
