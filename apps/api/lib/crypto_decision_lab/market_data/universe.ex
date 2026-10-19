defmodule CryptoDecisionLab.MarketData.Universe do
  @moduledoc "Configured assets; availability is discovered, never inferred from this list."
  import Ecto.Query
  alias CryptoDecisionLab.{Repo, MarketData.Asset}

  # Personal research universe. Spot USDT availability is verified via exchangeInfo, not assumed.
  @groups [
    {"core",
     [
       {"BTC", "Bitcoin"},
       {"ARB", "Arbitrum"},
       {"OP", "Optimism"},
       {"SUI", "Sui"},
       {"APT", "Aptos"},
       {"RENDER", "Render"}
     ]},
    {"high_potential",
     [
       {"TIA", "Celestia"},
       {"ONDO", "Ondo"},
       {"PYTH", "Pyth Network"},
       {"EIGEN", "EigenLayer"},
       {"ASI", "Artificial Superintelligence Alliance"}
     ]},
    {"mid_cap",
     [
       {"TAO", "Bittensor"},
       {"IMX", "Immutable"},
       {"BEAM", "Beam"},
       {"AKT", "Akash Network"},
       {"HNT", "Helium"}
     ]},
    {"extended",
     [
       {"IO", "io.net"},
       {"MKR", "Maker"},
       {"CFG", "Centrifuge"},
       {"HONEY", "Hivemapper"},
       {"BONK", "Bonk"}
     ]}
  ]

  def assets do
    for {category, assets} <- @groups,
        {symbol, name} <- assets,
        do: %{symbol: symbol, name: name, category: category, enabled: true}
  end

  def symbols, do: Enum.map(assets(), & &1.symbol)

  @doc """
  Upserts the configured universe and disables assets removed from `@groups`.
  Historical candles/analyses for disabled assets are retained; collectors skip them.
  Enabled preferences for symbols still in the universe are preserved.
  """
  def seed do
    now = DateTime.utc_now(:microsecond)
    wanted = symbols()

    rows =
      Enum.map(assets(), fn asset ->
        Map.merge(asset, %{inserted_at: now, updated_at: now})
      end)

    Repo.insert_all(Asset, rows,
      on_conflict: {:replace, [:name, :category, :updated_at]},
      conflict_target: [:symbol]
    )

    from(a in Asset, where: a.symbol not in ^wanted)
    |> Repo.update_all(set: [enabled: false, updated_at: now])

    :ok
  end
end
