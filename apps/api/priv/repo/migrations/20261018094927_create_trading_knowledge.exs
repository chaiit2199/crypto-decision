defmodule CryptoDecisionLab.Repo.Migrations.CreateTradingKnowledge do
  use Ecto.Migration

  @audit_tables ~w(knowledge_strategies knowledge_strategy_versions knowledge_backtest_evidence knowledge_matches knowledge_ai_decisions knowledge_realized_outcomes)

  def up do
    create table(:knowledge_strategies) do
      add :key, :string, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:knowledge_strategies, [:key])

    create table(:knowledge_strategy_versions) do
      add :strategy_id, references(:knowledge_strategies, on_delete: :restrict), null: false
      add :version, :integer, null: false
      add :schema_version, :string, null: false
      add :document, :map, null: false
      add :content_hash, :string, size: 64, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:knowledge_strategy_versions, [:strategy_id, :version])

    create constraint(:knowledge_strategy_versions, :knowledge_version_valid,
             check:
               "version > 0 AND schema_version = '1.0.0' AND content_hash ~ '^[a-f0-9]{64}$' AND jsonb_typeof(document) = 'object'"
           )

    create table(:knowledge_backtest_evidence) do
      add :strategy_version_id, references(:knowledge_strategy_versions, on_delete: :restrict),
        null: false

      add :status, :string, null: false
      add :dataset_hash, :string, size: 64, null: false
      add :split_hash, :string, size: 64, null: false
      add :configuration_hash, :string, size: 64, null: false
      add :feature_version, :string, null: false
      add :engine_version, :string, null: false
      add :train_end, :utc_datetime_usec, null: false
      add :validation_end, :utc_datetime_usec, null: false
      add :test_end, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec, null: false
      add :sample_count, :integer, null: false
      add :costs, :map, null: false
      add :metrics, :map, null: false
      add :lineage, :map, null: false
      add :review, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:knowledge_backtest_evidence, [:strategy_version_id, :completed_at],
             name: :knowledge_evidence_version_completed
           )

    create constraint(:knowledge_backtest_evidence, :knowledge_evidence_valid,
             check:
               "status IN ('unvalidated', 'verified', 'rejected') AND sample_count > 0 AND train_end < validation_end AND validation_end < test_end AND test_end <= completed_at AND completed_at <= inserted_at AND dataset_hash ~ '^[a-f0-9]{64}$' AND split_hash ~ '^[a-f0-9]{64}$' AND configuration_hash ~ '^[a-f0-9]{64}$' AND (status <> 'verified' OR (review ? 'reviewer' AND review ? 'reviewed_at'))"
           )

    create table(:knowledge_matches) do
      add :strategy_version_id, references(:knowledge_strategy_versions, on_delete: :restrict),
        null: false

      add :market_symbol_id, references(:market_symbols, on_delete: :restrict), null: false
      add :decision_at, :utc_datetime_usec, null: false
      add :data_at, :utc_datetime_usec, null: false
      add :available_at, :utc_datetime_usec, null: false
      add :snapshot, :map, null: false
      add :snapshot_hash, :string, size: 64, null: false
      add :result, :map, null: false
      add :engine_version, :string, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(
             :knowledge_matches,
             [:strategy_version_id, :market_symbol_id, :decision_at, :snapshot_hash],
             name: :knowledge_match_identity
           )

    create index(:knowledge_matches, [:market_symbol_id, :decision_at])

    create constraint(:knowledge_matches, :knowledge_match_chronology,
             check:
               "data_at <= available_at AND available_at <= decision_at AND decision_at <= inserted_at AND snapshot_hash ~ '^[a-f0-9]{64}$'"
           )

    create table(:knowledge_ai_decisions) do
      add :match_id, references(:knowledge_matches, on_delete: :restrict), null: false
      add :evidence_id, references(:knowledge_backtest_evidence, on_delete: :restrict)
      add :provider, :string, null: false
      add :requested_model, :string
      add :model, :string
      add :policy_version, :string, null: false
      add :context, :map, null: false
      add :context_hash, :string, size: 64, null: false
      add :classification, :map, null: false
      add :raw_response, :map, null: false
      add :decision, :string, null: false
      add :risk_result, :map, null: false
      add :decision_at, :utc_datetime_usec, null: false
      add :recorded_at, :utc_datetime_usec, null: false
      add :execution_allowed, :boolean, null: false, default: false
    end

    create index(:knowledge_ai_decisions, [:match_id, :decision_at])

    create constraint(:knowledge_ai_decisions, :knowledge_decision_valid,
             check:
               "decision IN ('BUY', 'SELL', 'WAIT', 'NO_DATA') AND NOT execution_allowed AND decision_at <= recorded_at AND context_hash ~ '^[a-f0-9]{64}$' AND (decision NOT IN ('BUY', 'SELL') OR evidence_id IS NOT NULL)"
           )

    create table(:knowledge_realized_outcomes) do
      add :decision_id, references(:knowledge_ai_decisions, on_delete: :restrict), null: false
      add :horizon_seconds, :integer, null: false
      add :decision_at, :utc_datetime_usec, null: false
      add :entry_at, :utc_datetime_usec, null: false
      add :exit_at, :utc_datetime_usec, null: false
      add :observed_at, :utc_datetime_usec, null: false
      add :entry_price, :decimal, precision: 38, scale: 18, null: false
      add :exit_price, :decimal, precision: 38, scale: 18, null: false
      add :net_return, :decimal, precision: 38, scale: 18, null: false
      add :costs, :map, null: false
      add :lineage, :map, null: false
    end

    create unique_index(:knowledge_realized_outcomes, [:decision_id, :horizon_seconds])

    create constraint(:knowledge_realized_outcomes, :knowledge_outcome_valid,
             check:
               "horizon_seconds > 0 AND decision_at < entry_at AND entry_at < exit_at AND exit_at <= observed_at AND entry_price > 0 AND entry_price <> 'NaN'::numeric AND exit_price > 0 AND exit_price <> 'NaN'::numeric AND net_return <> 'NaN'::numeric AND EXTRACT(EPOCH FROM (exit_at - entry_at)) = horizon_seconds"
           )

    execute """
    CREATE FUNCTION knowledge_reject_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'knowledge audit records are immutable' USING ERRCODE = '23514';
    END;
    $$;
    """

    for table <- @audit_tables do
      execute "CREATE TRIGGER #{table}_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON #{table} FOR EACH STATEMENT EXECUTE FUNCTION knowledge_reject_mutation()"
    end

    execute """
    CREATE FUNCTION knowledge_check_decision() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE matched knowledge_matches; evidence knowledge_backtest_evidence;
    BEGIN
      SELECT * INTO STRICT matched FROM knowledge_matches WHERE id = NEW.match_id;
      IF NEW.decision_at <> matched.decision_at THEN
        RAISE EXCEPTION 'decision timestamp must match its input' USING ERRCODE = '23514';
      END IF;
      IF NEW.evidence_id IS NOT NULL THEN
        SELECT * INTO STRICT evidence FROM knowledge_backtest_evidence WHERE id = NEW.evidence_id;
        IF evidence.strategy_version_id <> matched.strategy_version_id OR evidence.status <> 'verified'
           OR evidence.inserted_at > NEW.decision_at THEN
          RAISE EXCEPTION 'evidence must be verified, exact-version and available' USING ERRCODE = '23514';
        END IF;
      END IF;
      RETURN NEW;
    END;
    $$;
    """

    execute """
    CREATE TRIGGER knowledge_decision_lineage BEFORE INSERT ON knowledge_ai_decisions
    FOR EACH ROW EXECUTE FUNCTION knowledge_check_decision();
    """

    execute """
    CREATE FUNCTION knowledge_check_outcome() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.decision_at <> (SELECT decision_at FROM knowledge_ai_decisions WHERE id = NEW.decision_id) THEN
        RAISE EXCEPTION 'outcome timestamp must match its decision' USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
    END;
    $$;
    """

    execute """
    CREATE TRIGGER knowledge_outcome_lineage BEFORE INSERT ON knowledge_realized_outcomes
    FOR EACH ROW EXECUTE FUNCTION knowledge_check_outcome();
    """
  end

  def down do
    for table <- Enum.reverse(@audit_tables), do: drop(table(String.to_atom(table)))
    execute "DROP FUNCTION knowledge_check_outcome()"
    execute "DROP FUNCTION knowledge_check_decision()"
    execute "DROP FUNCTION knowledge_reject_mutation()"
  end
end
