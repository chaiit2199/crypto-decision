defmodule CryptoDecisionLab.TradingKnowledge.AIDecision do
  @moduledoc "Append-only knowledge_ai_decisions audit record, written through the TradingKnowledge context."
  use Ecto.Schema

  schema "knowledge_ai_decisions" do
    field :match_id, :id
    field :evidence_id, :id
    field :provider, :string
    field :requested_model, :string
    field :model, :string
    field :policy_version, :string
    field :context, :map
    field :context_hash, :string
    field :classification, :map
    field :raw_response, :map
    field :decision, :string
    field :risk_result, :map
    field :decision_at, :utc_datetime_usec
    field :recorded_at, :utc_datetime_usec
    field :execution_allowed, :boolean
  end
end
