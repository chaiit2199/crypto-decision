defmodule CryptoDecisionLab.Repo.Migrations.PruneXmUnfamiliarAssets do
  @moduledoc """
  Removes assets no longer in MarketData.Universe (SUI, NEAR, ONDO, INJ, SEI,
  TIA, PYTH, EIGEN, TAO, IO, BONK, WLD, and any other leftover symbols such as
  WIF). Keeps the current 18 crypto symbols plus XAU. Irreversible; reclaim
  space with VACUUM (ANALYZE) after deploy.
  """
  use Ecto.Migration

  # Must stay aligned with CryptoDecisionLab.MarketData.Universe.@groups + XAU.
  @keep ~w(
    BTC ETH SOL XRP BNB LTC
    ADA DOGE LINK AVAX DOT UNI
    ARB OP APT RENDER
    FET IMX
    XAU
  )

  @immutable_triggers [
    {"trading_simulations", "trading_simulations_immutable", "trading_reject_mutation"},
    {"knowledge_realized_outcomes", "knowledge_realized_outcomes_immutable",
     "knowledge_reject_mutation"},
    {"knowledge_ai_decisions", "knowledge_ai_decisions_immutable", "knowledge_reject_mutation"},
    {"knowledge_matches", "knowledge_matches_immutable", "knowledge_reject_mutation"}
  ]

  def up do
    keep_list = Enum.map_join(@keep, ", ", &"'#{&1}'")

    for {table, trigger, _fun} <- @immutable_triggers do
      execute "DROP TRIGGER IF EXISTS #{trigger} ON #{table}"
    end

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

    for {table, trigger, fun} <- @immutable_triggers do
      execute """
      CREATE TRIGGER #{trigger}
      BEFORE UPDATE OR DELETE OR TRUNCATE ON #{table}
      FOR EACH STATEMENT
      EXECUTE FUNCTION #{fun}()
      """
    end
  end

  def down do
    raise "irreversible: pruned market history cannot be restored"
  end
end
