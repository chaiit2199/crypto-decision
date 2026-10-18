defmodule CryptoDecisionLab.TradingKnowledge.Match do
  @moduledoc "Append-only knowledge_matches audit record, written through the TradingKnowledge context."
  use Ecto.Schema

  schema "knowledge_matches" do
    field :strategy_version_id, :id
    field :market_symbol_id, :id
    field :decision_at, :utc_datetime_usec
    field :data_at, :utc_datetime_usec
    field :available_at, :utc_datetime_usec
    field :snapshot, :map
    field :snapshot_hash, :string
    field :result, :map
    field :engine_version, :string
    field :inserted_at, :utc_datetime_usec
  end
end
