defmodule CryptoDecisionLab.MarketData.Universe do
  @moduledoc "Configured assets; availability is discovered, never inferred from this list."
  import Ecto.Query
  alias CryptoDecisionLab.{Repo, MarketData.Asset}

  # Personal research universe aligned with liquid spot / common CFD names.
  # Binance exchangeInfo still verifies Spot USDT; Coinbase verifies USD separately.
  @groups [
    {"core",
     [
       {"BTC", "Bitcoin"},
       {"ETH", "Ethereum"},
       {"SOL", "Solana"},
       {"XRP", "XRP"},
       {"BNB", "BNB"},
       {"LTC", "Litecoin"}
     ]},
    {"high_potential",
     [
       {"ADA", "Cardano"},
       {"DOGE", "Dogecoin"},
       {"LINK", "Chainlink"},
       {"AVAX", "Avalanche"},
       {"DOT", "Polkadot"},
       {"UNI", "Uniswap"}
     ]},
    {"mid_cap",
     [
       {"ARB", "Arbitrum"},
       {"OP", "Optimism"},
       {"APT", "Aptos"},
       {"RENDER", "Render"}
     ]},
    {"extended",
     [
       {"FET", "Fetch.ai"},
       {"IMX", "Immutable"}
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

    from(a in Asset, where: a.symbol not in ^wanted and a.category != "precious_metals")
    |> Repo.update_all(set: [enabled: false, updated_at: now])

    :ok
  end
end
