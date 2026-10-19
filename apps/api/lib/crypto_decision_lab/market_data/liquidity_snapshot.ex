defmodule CryptoDecisionLab.MarketData.LiquiditySnapshot do
  use Ecto.Schema
  @primary_key {:market_symbol_id, :id, autogenerate: false}
  schema "market_liquidity_snapshots" do
    field :book, :map
    field :data_at, :utc_datetime_usec
    field :fetched_at, :utc_datetime_usec
  end
end
