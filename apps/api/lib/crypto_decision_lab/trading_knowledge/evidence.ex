defmodule CryptoDecisionLab.TradingKnowledge.Evidence do
  @moduledoc "Append-only knowledge_backtest_evidence audit record, written through the TradingKnowledge context."
  use Ecto.Schema

  schema "knowledge_backtest_evidence" do
    field :strategy_version_id, :id
    field :status, :string
    field :dataset_hash, :string
    field :split_hash, :string
    field :configuration_hash, :string
    field :feature_version, :string
    field :engine_version, :string
    field :train_end, :utc_datetime_usec
    field :validation_end, :utc_datetime_usec
    field :test_end, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :sample_count, :integer
    field :costs, :map
    field :metrics, :map
    field :lineage, :map
    field :review, :map
    field :inserted_at, :utc_datetime_usec
  end
end
