defmodule CryptoDecisionLab.MarketData.Candle do
  use Ecto.Schema
  import Ecto.Changeset

  schema "market_candles" do
    field :market_symbol_id, :id
    field :timeframe, :string
    field :open_time, :utc_datetime_usec
    field :close_time, :utc_datetime_usec
    field :open, :decimal
    field :high, :decimal
    field :low, :decimal
    field :close, :decimal
    field :base_volume, :decimal
    field :quote_volume, :decimal
    field :taker_buy_base_volume, :decimal
    field :taker_buy_quote_volume, :decimal
    field :trade_count, :integer
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(record, attrs) do
    record
    |> cast(
      attrs,
      __schema__(:fields) -- [:id, :asset_id, :market_symbol_id, :inserted_at, :updated_at]
    )
    |> validate_required([
      :market_symbol_id,
      :timeframe,
      :open_time,
      :close_time,
      :open,
      :high,
      :low,
      :close,
      :base_volume,
      :quote_volume,
      :taker_buy_base_volume,
      :taker_buy_quote_volume,
      :trade_count
    ])
  end
end
