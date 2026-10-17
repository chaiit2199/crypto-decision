defmodule CryptoDecisionLab.Decisions.Analysis do
  use Ecto.Schema
  import Ecto.Changeset

  schema "market_analyses" do
    field :market_symbol_id, :id
    field :slot, :utc_datetime_usec
    field :status, :string
    field :signal, :string
    field :requested_model, :string
    field :model, :string
    field :configuration_version, :string
    field :features, :map, default: %{}
    field :answers, :map, default: %{}
    field :raw_response, :map, default: %{}
    field :risk_result, :map, default: %{}
    field :reason, :string
    field :data_at, :utc_datetime_usec
    field :analyzed_at, :utc_datetime_usec
    field :valid_until, :utc_datetime_usec
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, __schema__(:fields) -- [:id, :market_symbol_id])
    |> validate_required([
      :slot,
      :status,
      :signal,
      :requested_model,
      :configuration_version,
      :analyzed_at,
      :valid_until
    ])
    |> validate_inclusion(:status, ~w(ready no_data error))
    |> validate_inclusion(:signal, ~w(BUY SELL WAIT NO_DATA))
    |> foreign_key_constraint(:market_symbol_id)
    |> unique_constraint([:market_symbol_id, :slot])
  end
end
