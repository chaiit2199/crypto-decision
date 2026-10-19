defmodule CryptoDecisionLab.Trading.Simulation do
  @moduledoc "Append-only simulation reports; never exchange orders."
  use Ecto.Schema

  schema "trading_simulations" do
    field :market_symbol_id, :id
    field :kind, :string
    field :report, :map
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @type t :: %__MODULE__{}
end
