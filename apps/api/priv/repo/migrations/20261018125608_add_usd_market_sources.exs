defmodule CryptoDecisionLab.Repo.Migrations.AddUsdMarketSources do
  use Ecto.Migration

  def change do
    alter table(:market_symbols) do
      add :provider_symbol, :text
    end

    alter table(:market_latest_prices) do
      add :data_at, :utc_datetime_usec
    end

    alter table(:market_ticker_stats) do
      modify :quote_volume, :decimal, null: true, from: {:decimal, null: false}
      modify :trade_count, :bigint, null: true, from: {:bigint, null: false}
    end

    alter table(:market_candles) do
      for field <- [:quote_volume, :taker_buy_base_volume, :taker_buy_quote_volume] do
        modify field, :decimal, null: true, from: {:decimal, null: false}
      end

      modify :trade_count, :bigint, null: true, from: {:bigint, null: false}
    end
  end
end
