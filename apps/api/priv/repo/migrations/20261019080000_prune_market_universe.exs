defmodule CryptoDecisionLab.Repo.Migrations.PruneMarketUniverse do
  @moduledoc """
  One-shot purge of assets outside the configured research universe.

  Keeps the 20 symbols in MarketData.Universe (including BTC), all selected for
  Binance Spot USDT coverage. Deletes related candles, snapshots, analyses,
  knowledge matches and simulations so the DB can reclaim space after VACUUM.
  Irreversible.
  """
  use Ecto.Migration

  # Must stay aligned with CryptoDecisionLab.MarketData.Universe.@groups
  @keep ~w(
    BTC ARB OP SUI APT RENDER
    TIA ONDO PYTH EIGEN FET NEAR
    TAO IMX INJ SEI
    IO BONK WIF WLD
  )

  def up do
    keep_list = Enum.map_join(@keep, ", ", &"'#{&1}'")

    # Simulation rows are normally immutable; allow delete only for this prune.
    execute "DROP TRIGGER IF EXISTS trading_simulations_immutable ON trading_simulations"

    execute """
    WITH obsolete_symbols AS (
      SELECT s.id
      FROM market_symbols AS s
      INNER JOIN market_assets AS a ON a.id = s.asset_id
      WHERE a.symbol NOT IN (#{keep_list})
    )
    DELETE FROM knowledge_realized_outcomes
    WHERE decision_id IN (
      SELECT d.id
      FROM knowledge_ai_decisions AS d
      INNER JOIN knowledge_matches AS m ON m.id = d.match_id
      WHERE m.market_symbol_id IN (SELECT id FROM obsolete_symbols)
    )
    """

    execute """
    WITH obsolete_symbols AS (
      SELECT s.id
      FROM market_symbols AS s
      INNER JOIN market_assets AS a ON a.id = s.asset_id
      WHERE a.symbol NOT IN (#{keep_list})
    )
    DELETE FROM knowledge_ai_decisions
    WHERE match_id IN (
      SELECT m.id
      FROM knowledge_matches AS m
      WHERE m.market_symbol_id IN (SELECT id FROM obsolete_symbols)
    )
    """

    execute """
    WITH obsolete_symbols AS (
      SELECT s.id
      FROM market_symbols AS s
      INNER JOIN market_assets AS a ON a.id = s.asset_id
      WHERE a.symbol NOT IN (#{keep_list})
    )
    DELETE FROM knowledge_matches
    WHERE market_symbol_id IN (SELECT id FROM obsolete_symbols)
    """

    execute """
    WITH obsolete_symbols AS (
      SELECT s.id
      FROM market_symbols AS s
      INNER JOIN market_assets AS a ON a.id = s.asset_id
      WHERE a.symbol NOT IN (#{keep_list})
    )
    DELETE FROM trading_simulations
    WHERE market_symbol_id IN (SELECT id FROM obsolete_symbols)
    """

    execute """
    WITH obsolete_symbols AS (
      SELECT s.id
      FROM market_symbols AS s
      INNER JOIN market_assets AS a ON a.id = s.asset_id
      WHERE a.symbol NOT IN (#{keep_list})
    )
    DELETE FROM market_liquidity_snapshots
    WHERE market_symbol_id IN (SELECT id FROM obsolete_symbols)
    """

    execute """
    WITH obsolete_symbols AS (
      SELECT s.id
      FROM market_symbols AS s
      INNER JOIN market_assets AS a ON a.id = s.asset_id
      WHERE a.symbol NOT IN (#{keep_list})
    )
    DELETE FROM market_analyses
    WHERE market_symbol_id IN (SELECT id FROM obsolete_symbols)
    """

    execute """
    WITH obsolete_symbols AS (
      SELECT s.id
      FROM market_symbols AS s
      INNER JOIN market_assets AS a ON a.id = s.asset_id
      WHERE a.symbol NOT IN (#{keep_list})
    )
    DELETE FROM market_candles
    WHERE market_symbol_id IN (SELECT id FROM obsolete_symbols)
    """

    execute """
    WITH obsolete_symbols AS (
      SELECT s.id
      FROM market_symbols AS s
      INNER JOIN market_assets AS a ON a.id = s.asset_id
      WHERE a.symbol NOT IN (#{keep_list})
    )
    DELETE FROM market_sync_states
    WHERE market_symbol_id IN (SELECT id FROM obsolete_symbols)
    """

    execute """
    WITH obsolete_symbols AS (
      SELECT s.id
      FROM market_symbols AS s
      INNER JOIN market_assets AS a ON a.id = s.asset_id
      WHERE a.symbol NOT IN (#{keep_list})
    )
    DELETE FROM market_latest_prices
    WHERE market_symbol_id IN (SELECT id FROM obsolete_symbols)
    """

    execute """
    WITH obsolete_symbols AS (
      SELECT s.id
      FROM market_symbols AS s
      INNER JOIN market_assets AS a ON a.id = s.asset_id
      WHERE a.symbol NOT IN (#{keep_list})
    )
    DELETE FROM market_ticker_stats
    WHERE market_symbol_id IN (SELECT id FROM obsolete_symbols)
    """

    execute """
    DELETE FROM market_symbols AS s
    USING market_assets AS a
    WHERE s.asset_id = a.id
      AND a.symbol NOT IN (#{keep_list})
    """

    execute """
    DELETE FROM market_assets
    WHERE symbol NOT IN (#{keep_list})
    """

    execute """
    CREATE TRIGGER trading_simulations_immutable
    BEFORE UPDATE OR DELETE OR TRUNCATE ON trading_simulations
    FOR EACH STATEMENT
    EXECUTE FUNCTION trading_reject_mutation()
    """
  end

  def down do
    raise "irreversible: pruned market history cannot be restored"
  end
end
