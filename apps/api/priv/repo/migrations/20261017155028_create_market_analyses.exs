defmodule CryptoDecisionLab.Repo.Migrations.CreateMarketAnalyses do
  use Ecto.Migration

  def change do
    create table(:market_analyses) do
      add :market_symbol_id, references(:market_symbols, on_delete: :delete_all), null: false
      add :slot, :utc_datetime_usec, null: false
      add :status, :string, null: false
      add :signal, :string, null: false
      add :requested_model, :string, null: false
      add :model, :string
      add :configuration_version, :string, null: false
      add :features, :map, null: false, default: %{}
      add :answers, :map, null: false, default: %{}
      add :raw_response, :map, null: false, default: %{}
      add :risk_result, :map, null: false, default: %{}
      add :reason, :string
      add :data_at, :utc_datetime_usec
      add :analyzed_at, :utc_datetime_usec, null: false
      add :valid_until, :utc_datetime_usec, null: false
    end

    create unique_index(:market_analyses, [:market_symbol_id, :slot])

    create constraint(:market_analyses, :analysis_status,
             check: "status IN ('ready', 'no_data', 'error')"
           )

    create constraint(:market_analyses, :analysis_signal,
             check: "signal IN ('BUY', 'SELL', 'WAIT', 'NO_DATA')"
           )

    create table(:jev_provider_states, primary_key: false) do
      add :id, :integer, primary_key: true
      add :blocked_until, :utc_datetime_usec
      add :last_error, :string
    end

    create constraint(:jev_provider_states, :jev_singleton, check: "id = 1")
  end
end
