defmodule CryptoDecisionLab.MarketData.Universe do
  @moduledoc "Configured assets; availability is discovered, never inferred from this list."
  alias CryptoDecisionLab.{Repo, MarketData.Asset}

  @groups [
    {"core",
     [
       {"BTC", "Bitcoin"},
       {"ETH", "Ethereum"},
       {"SOL", "Solana"},
       {"BNB", "BNB"},
       {"XRP", "XRP"},
       {"ADA", "Cardano"},
       {"AVAX", "Avalanche"},
       {"TON", "Toncoin"},
       {"SUI", "Sui"},
       {"NEAR", "NEAR Protocol"}
     ]},
    {"infrastructure",
     [
       {"LINK", "Chainlink"},
       {"ONDO", "Ondo"},
       {"RENDER", "Render"},
       {"GRT", "The Graph"},
       {"XLM", "Stellar"},
       {"ALGO", "Algorand"},
       {"ZEC", "Zcash"},
       {"INJ", "Injective"},
       {"KAS", "Kaspa"},
       {"QNT", "Quant"}
     ]},
    {"defi",
     [
       {"ARB", "Arbitrum"},
       {"HYPE", "Hyperliquid"},
       {"AAVE", "Aave"},
       {"UNI", "Uniswap"},
       {"ALT", "AltLayer"},
       {"OP", "Optimism"},
       {"SEI", "Sei"},
       {"HNT", "Helium"}
     ]},
    {"meme",
     [
       {"DOGE", "Dogecoin"},
       {"SHIB", "Shiba Inu"},
       {"PEPE", "Pepe"},
       {"MEW", "cat in a dogs world"}
     ]}
  ]
  def assets do
    for {category, assets} <- @groups,
        {symbol, name} <- assets,
        do: %{symbol: symbol, name: name, category: category, enabled: true}
  end

  def seed do
    now = DateTime.utc_now()
    rows = Enum.map(assets(), &Map.merge(&1, %{inserted_at: now, updated_at: now}))
    Repo.insert_all(Asset, rows, on_conflict: :nothing, conflict_target: [:symbol])
    :ok
  end
end
