defmodule CryptoDecisionLab.TradingKnowledge.StrategyVersion do
  @moduledoc "Append-only strategy document; its database ID pins every downstream reference."
  use Ecto.Schema
  import Ecto.Changeset

  schema "knowledge_strategy_versions" do
    field :strategy_id, :id
    field :version, :integer
    field :schema_version, :string
    field :document, :map
    field :content_hash, :string
    field :inserted_at, :utc_datetime_usec
  end

  @spec changeset(t :: struct(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:version, :schema_version, :document, :content_hash, :inserted_at])
    |> validate_required([:version, :schema_version, :document, :content_hash, :inserted_at])
    |> validate_number(:version, greater_than: 0)
    |> unique_constraint([:strategy_id, :version])
    |> foreign_key_constraint(:strategy_id)
  end
end
