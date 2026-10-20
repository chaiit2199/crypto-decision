defmodule CryptoDecisionLab.Repo.Migrations.AllowDailyGoldCandles do
  use Ecto.Migration

  def up do
    drop constraint(:market_candles, :valid_interval)

    create constraint(:market_candles, :valid_interval,
             check: """
             timeframe IN ('5m','15m','1h','1d') AND
             close_time = open_time + (CASE timeframe
               WHEN '5m' THEN 300
               WHEN '15m' THEN 900
               WHEN '1h' THEN 3600
               WHEN '1d' THEN 86400
             END) * interval '1 second' - interval '1 millisecond' AND
             mod(extract(epoch from open_time)::numeric, CASE timeframe
               WHEN '5m' THEN 300
               WHEN '15m' THEN 900
               WHEN '1h' THEN 3600
               WHEN '1d' THEN 86400
             END) = 0
             """
           )
  end

  def down do
    # Refuse rollback while daily candles exist; never delete market history implicitly.
    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM market_candles WHERE timeframe = '1d' LIMIT 1) THEN
        RAISE EXCEPTION 'cannot restore valid_interval while 1d candles exist';
      END IF;
    END $$;
    """)

    drop constraint(:market_candles, :valid_interval)

    create constraint(:market_candles, :valid_interval,
             check: """
             timeframe IN ('5m','15m','1h') AND
             close_time = open_time + (CASE timeframe WHEN '5m' THEN 300 WHEN '15m' THEN 900 ELSE 3600 END) * interval '1 second' - interval '1 millisecond' AND
             mod(extract(epoch from open_time)::numeric, CASE timeframe WHEN '5m' THEN 300 WHEN '15m' THEN 900 ELSE 3600 END) = 0
             """
           )
  end
end
