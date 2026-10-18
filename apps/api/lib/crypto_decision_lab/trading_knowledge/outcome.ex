defmodule CryptoDecisionLab.TradingKnowledge.Outcome do
  @moduledoc "Append-only knowledge_realized_outcomes audit record, written through the TradingKnowledge context."
  use Ecto.Schema

  schema "knowledge_realized_outcomes" do
    field :decision_id, :id
    field :horizon_seconds, :integer
    field :decision_at, :utc_datetime_usec
    field :entry_at, :utc_datetime_usec
    field :exit_at, :utc_datetime_usec
    field :observed_at, :utc_datetime_usec
    field :entry_price, :decimal
    field :exit_price, :decimal
    field :net_return, :decimal
    field :costs, :map
    field :lineage, :map
  end
end
