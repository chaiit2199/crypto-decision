defmodule CryptoDecisionLab.MarketData.Symbol do
  use Ecto.Schema
  import Ecto.Changeset

  schema "market_symbols" do
    field :asset_id, :id
    field :exchange, :string
    field :symbol, :string
    field :base_asset, :string
    field :quote_asset, :string
    field :trading_status, :string
    field :enabled, :boolean, default: true
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(
      attrs,
      __schema__(:fields) -- [:id, :asset_id, :market_symbol_id, :inserted_at, :updated_at]
    )
    |> validate_required([
      :asset_id,
      :exchange,
      :symbol,
      :base_asset,
      :quote_asset,
      :trading_status,
      :enabled
    ])
  end
end
