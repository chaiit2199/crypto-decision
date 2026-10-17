defmodule CryptoDecisionLab.MarketData.CollectorState do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false

  schema "market_collector_states" do
    field :key, :string, primary_key: true
    field :next_poll_at, :utc_datetime_usec
    field :blocked_until, :utc_datetime_usec
    field :weight_window, :integer
    field :used_weight, :integer
    field :weight_limit, :integer
    field :last_error, :string
    field :metadata_at, :utc_datetime_usec
    field :prices_at, :utc_datetime_usec
    field :stats_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end

  def changeset(record, attrs) do
    record
    |> cast(
      attrs,
      __schema__(:fields) -- [:id, :asset_id, :market_symbol_id, :inserted_at, :updated_at]
    )
    |> validate_required([:key, :weight_window, :used_weight, :weight_limit, :updated_at])
  end
end
