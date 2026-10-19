defmodule CryptoDecisionLab.Repo.Migrations.AddTradingWorkbench do
  use Ecto.Migration

  def up do
    drop constraint(:market_candles, :valid_interval)

    create constraint(:market_candles, :valid_interval,
             check: """
             timeframe IN ('5m','15m','1h') AND
             close_time = open_time + (CASE timeframe WHEN '5m' THEN 300 WHEN '15m' THEN 900 ELSE 3600 END) * interval '1 second' - interval '1 millisecond' AND
             mod(extract(epoch from open_time)::numeric, CASE timeframe WHEN '5m' THEN 300 WHEN '15m' THEN 900 ELSE 3600 END) = 0
             """
           )

    create table(:market_liquidity_snapshots, primary_key: false) do
      add :market_symbol_id, references(:market_symbols, on_delete: :restrict), primary_key: true
      add :book, :map, null: false
      add :data_at, :utc_datetime_usec, null: false
      add :fetched_at, :utc_datetime_usec, null: false
    end

    create table(:trading_simulations) do
      add :market_symbol_id, references(:market_symbols, on_delete: :restrict), null: false
      add :kind, :text, null: false
      add :report, :map, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute """
    CREATE FUNCTION trading_reject_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'simulation reports are immutable' USING ERRCODE = '23514';
    END;
    $$;
    """

    execute "CREATE TRIGGER trading_simulations_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON trading_simulations FOR EACH STATEMENT EXECUTE FUNCTION trading_reject_mutation()"

    execute "CREATE UNIQUE INDEX trading_paper_single_close ON trading_simulations ((report->>'open_id')) WHERE kind = 'paper' AND report->>'event' = 'CLOSE'"

    create index(:trading_simulations, [:market_symbol_id, :inserted_at])

    create constraint(:trading_simulations, :simulation_kind,
             check: "kind IN ('replay', 'paper')"
           )
  end

  def down do
    # Refuse rollback while short candles exist; never delete market history implicitly.
    drop table(:trading_simulations)
    execute "DROP FUNCTION trading_reject_mutation()"
    drop table(:market_liquidity_snapshots)
    drop constraint(:market_candles, :valid_interval)

    create constraint(:market_candles, :valid_interval,
             check:
               "timeframe = '1h' AND close_time = open_time + interval '1 hour' - interval '1 millisecond' AND mod(extract(epoch from open_time)::numeric, 3600) = 0"
           )
  end
end
