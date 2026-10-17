defmodule CryptoDecisionLab.MarketData.LatestPrice do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false

  schema "market_latest_prices" do
    field :market_symbol_id, :id, primary_key: true
    field :price, :decimal
    field :fetched_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end

  def changeset(record, attrs) do
    record
    |> cast(
      attrs,
      __schema__(:fields) -- [:id, :asset_id, :market_symbol_id, :inserted_at, :updated_at]
    )
    |> validate_required([:market_symbol_id, :price, :fetched_at, :updated_at])
  end
end
