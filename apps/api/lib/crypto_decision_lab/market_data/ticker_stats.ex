defmodule CryptoDecisionLab.MarketData.TickerStats do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false

  schema "market_ticker_stats" do
    field :market_symbol_id, :id, primary_key: true
    field :price_change, :decimal
    field :price_change_percent, :decimal
    field :high_price, :decimal
    field :low_price, :decimal
    field :base_volume, :decimal
    field :quote_volume, :decimal
    field :trade_count, :integer
    field :data_at, :utc_datetime_usec
    field :fetched_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end

  def changeset(record, attrs) do
    record
    |> cast(
      attrs,
      __schema__(:fields) -- [:id, :asset_id, :market_symbol_id, :inserted_at, :updated_at]
    )
    |> validate_required([
      :market_symbol_id,
      :price_change,
      :price_change_percent,
      :high_price,
      :low_price,
      :base_volume,
      :data_at,
      :fetched_at,
      :updated_at
    ])
  end
end
