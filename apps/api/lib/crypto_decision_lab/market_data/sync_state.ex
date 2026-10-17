defmodule CryptoDecisionLab.MarketData.SyncState do
  use Ecto.Schema
  import Ecto.Changeset

  schema "market_sync_states" do
    field :market_symbol_id, :id
    field :timeframe, :string
    field :sync_type, :string
    field :last_synced_open_time, :utc_datetime_usec
    field :range_start, :utc_datetime_usec
    field :status, :string
    field :last_attempt_at, :utc_datetime_usec
    field :last_success_at, :utc_datetime_usec
    field :last_error, :string
    field :missing_count, :integer
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(
      attrs,
      __schema__(:fields) -- [:id, :asset_id, :market_symbol_id, :inserted_at, :updated_at]
    )
    |> validate_required([:market_symbol_id, :timeframe, :sync_type, :status])
  end
end
