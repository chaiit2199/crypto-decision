defmodule CryptoDecisionLab.Repo.Migrations.CreateMarketData do
  use Ecto.Migration

  def change do
    create table(:market_assets) do
      add :symbol, :text, null: false
      add :name, :text, null: false
      add :category, :text, null: false
      add :enabled, :boolean, null: false, default: true
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:market_assets, [:symbol])

    create table(:market_symbols) do
      add :asset_id, references(:market_assets, on_delete: :restrict), null: false
      add :exchange, :text, null: false
      add :symbol, :text, null: false
      add :base_asset, :text, null: false
      add :quote_asset, :text, null: false
      add :trading_status, :text, null: false
      add :enabled, :boolean, null: false, default: true
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:market_symbols, [:exchange, :symbol])
    create index(:market_symbols, [:asset_id])

    create table(:market_latest_prices, primary_key: false) do
      add :market_symbol_id, references(:market_symbols, on_delete: :restrict), primary_key: true
      add :price, :decimal, null: false
      add :fetched_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create constraint(:market_latest_prices, :positive_price,
             check: "price > 0 AND price != 'NaN'::numeric"
           )

    create table(:market_ticker_stats, primary_key: false) do
      add :market_symbol_id, references(:market_symbols, on_delete: :restrict), primary_key: true

      for field <- [
            :price_change,
            :price_change_percent,
            :high_price,
            :low_price,
            :base_volume,
            :quote_volume
          ] do
        add field, :decimal, null: false
      end

      add :trade_count, :bigint, null: false
      add :data_at, :utc_datetime_usec, null: false
      add :fetched_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create constraint(:market_ticker_stats, :valid_stats,
             check:
               "low_price > 0 AND high_price >= low_price AND base_volume >= 0 AND quote_volume >= 0 AND trade_count >= 0"
           )

    create table(:market_candles) do
      add :market_symbol_id, references(:market_symbols, on_delete: :restrict), null: false
      add :timeframe, :text, null: false, default: "1h"
      add :open_time, :utc_datetime_usec, null: false
      add :close_time, :utc_datetime_usec, null: false

      for field <- [
            :open,
            :high,
            :low,
            :close,
            :base_volume,
            :quote_volume,
            :taker_buy_base_volume,
            :taker_buy_quote_volume
          ] do
        add field, :decimal, null: false
      end

      add :trade_count, :bigint, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:market_candles, [:market_symbol_id, :timeframe, :open_time])

    create constraint(:market_candles, :valid_ohlcv,
             check:
               "open > 0 AND low > 0 AND high >= open AND high >= close AND low <= open AND low <= close AND high >= low AND base_volume >= 0 AND quote_volume >= 0 AND taker_buy_base_volume >= 0 AND taker_buy_quote_volume >= 0 AND trade_count >= 0"
           )

    create constraint(:market_candles, :valid_interval,
             check:
               "timeframe = '1h' AND close_time = open_time + interval '1 hour' - interval '1 millisecond' AND mod(extract(epoch from open_time)::numeric, 3600) = 0"
           )

    for field <- [
          :open,
          :high,
          :low,
          :close,
          :base_volume,
          :quote_volume,
          :taker_buy_base_volume,
          :taker_buy_quote_volume
        ] do
      create constraint(:market_candles, String.to_atom("finite_#{field}"),
               check:
                 "#{field} NOT IN ('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)"
             )
    end

    create table(:market_sync_states) do
      add :market_symbol_id, references(:market_symbols, on_delete: :restrict), null: false
      add :timeframe, :text, null: false, default: "1h"
      add :sync_type, :text, null: false
      add :last_synced_open_time, :utc_datetime_usec
      add :range_start, :utc_datetime_usec
      add :status, :text, null: false, default: "pending"
      add :last_attempt_at, :utc_datetime_usec
      add :last_success_at, :utc_datetime_usec
      add :last_error, :text
      add :missing_count, :integer
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:market_sync_states, [:market_symbol_id, :timeframe, :sync_type])

    create table(:market_collector_states, primary_key: false) do
      add :key, :text, primary_key: true
      add :next_poll_at, :utc_datetime_usec
      add :blocked_until, :utc_datetime_usec
      add :weight_window, :bigint, null: false, default: 0
      add :used_weight, :integer, null: false, default: 0
      add :weight_limit, :integer, null: false, default: 1200
      add :last_error, :text
      add :metadata_at, :utc_datetime_usec
      add :prices_at, :utc_datetime_usec
      add :stats_at, :utc_datetime_usec
      add :updated_at, :utc_datetime_usec, null: false
    end
  end
end
