defmodule CryptoDecisionLab.MarketData.Asset do
  use Ecto.Schema
  import Ecto.Changeset

  schema "market_assets" do
    field :symbol, :string
    field :name, :string
    field :category, :string
    field :enabled, :boolean, default: true
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(
      attrs,
      __schema__(:fields) -- [:id, :asset_id, :market_symbol_id, :inserted_at, :updated_at]
    )
    |> validate_required([:symbol, :name, :category, :enabled])
  end
end
