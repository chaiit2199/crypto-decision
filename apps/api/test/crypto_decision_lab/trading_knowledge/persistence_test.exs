defmodule CryptoDecisionLab.TradingKnowledge.PersistenceTest do
  use CryptoDecisionLab.DataCase

  alias CryptoDecisionLab.{
    KnowledgeFixtures,
    MarketFixtures,
    MockDecisionProvider,
    TradingKnowledge
  }

  alias CryptoDecisionLab.TradingKnowledge.{AIDecision, Evidence, Match}
  alias KnowledgeFixtures, as: F

  setup do
    MarketFixtures.configure()
    symbol = MarketFixtures.symbol()
    {:ok, version} = TradingKnowledge.import_document(F.strategy())
    %{symbol: symbol, version: version}
  end

  defp snapshot(now) do
    observed = DateTime.add(now, -10) |> DateTime.to_iso8601()
    available = DateTime.add(now, -5) |> DateTime.to_iso8601()

    F.snapshot()
    |> Map.put("as_of", observed)
    |> Map.put("available_at", available)
    |> Map.update!("features", fn features ->
      Map.new(features, fn {name, feature} ->
        {name, %{feature | "observed_at" => observed, "available_at" => available}}
      end)
    end)
  end

  defp evidence(version) do
    now = DateTime.utc_now()

    Repo.insert!(%Evidence{
      strategy_version_id: version.id,
      status: "verified",
      dataset_hash: String.duplicate("a", 64),
      split_hash: String.duplicate("b", 64),
      configuration_hash: String.duplicate("c", 64),
      feature_version: "hourly-v1",
      engine_version: "synthetic-fixture",
      train_end: DateTime.add(now, -400),
      validation_end: DateTime.add(now, -300),
      test_end: DateTime.add(now, -200),
      completed_at: DateTime.add(now, -100),
      inserted_at: now,
      sample_count: 100,
      costs: %{"fee_bps_per_side" => "10", "slippage_bps_per_side" => "5"},
      metrics: %{"fixture" => "synthetic tests only"},
      lineage: %{"data_kind" => "observed", "strategy_hash" => version.content_hash},
      review: %{
        "reviewer" => "synthetic test fixture",
        "eligibility" => "eligible",
        "reviewed_at" => DateTime.to_iso8601(now)
      }
    })
  end

  defp options(now) do
    [
      now: now,
      provider: MockDecisionProvider,
      model: "fixture-jev",
      model_limits: %{
        model: "fixture-jev",
        max_input_tokens: 8000,
        source: "https://docs.typesafe.ai/fixture-only",
        count_tokens: fn _ -> 100 end
      }
    ]
  end

  test "unvalidated imports persist WAIT with snapshot lineage and never call a provider", %{
    symbol: symbol,
    version: version
  } do
    now = DateTime.utc_now()

    assert {:ok, [%AIDecision{decision: "WAIT", provider: "none"} = decision]} =
             TradingKnowledge.analyze(symbol.id, [version.id], snapshot(now), %{}, options(now))

    refute_receive {:jev_called, _}
    match = Repo.get!(Match, decision.match_id)
    assert match.strategy_version_id == version.id
    assert match.snapshot_hash == CryptoDecisionLab.TradingKnowledge.Canonical.hash(snapshot(now))
    assert decision.risk_result["reason"] == "no_verified_relevant_strategies"
  end

  test "verified evidence retains model classification but failed risk independently prevents BUY",
       %{symbol: symbol, version: version} do
    evidence = evidence(version)
    now = DateTime.utc_now()

    assert {:ok, [decision]} =
             TradingKnowledge.analyze(symbol.id, [version.id], snapshot(now), %{}, options(now))

    assert_receive {:jev_called, %{"strategies" => [_]}}
    assert decision.decision == "WAIT"
    assert decision.model == "fixture-jev"
    assert decision.evidence_id == evidence.id
    assert decision.classification["trend"]["choice"] == "BULLISH"
    refute decision.execution_allowed
  end

  test "provider error is persisted and shared cooldown prevents another request", %{
    symbol: symbol,
    version: version
  } do
    evidence(version)
    Process.put(:jev_result, {:error, "rate_limited", 90})
    now = DateTime.utc_now()

    assert {:ok, [%{decision: "NO_DATA"}]} =
             TradingKnowledge.analyze(symbol.id, [version.id], snapshot(now), %{}, options(now))

    assert_receive {:jev_called, _}
    later = DateTime.utc_now()

    assert {:ok, [%{decision: "NO_DATA"}]} =
             TradingKnowledge.analyze(
               symbol.id,
               [version.id],
               snapshot(later),
               %{},
               options(later)
             )

    refute_receive {:jev_called, _}
  end

  test "future outcome labels are unique and cannot precede their decision", %{
    symbol: symbol,
    version: version
  } do
    now = DateTime.add(DateTime.utc_now(), -7200)

    {:ok, [decision]} =
      TradingKnowledge.analyze(symbol.id, [version.id], snapshot(now), %{}, options(now))

    attrs = %{
      "entry_at" => DateTime.to_iso8601(DateTime.add(now, 10)),
      "exit_at" => DateTime.to_iso8601(DateTime.add(now, 3610)),
      "observed_at" => DateTime.to_iso8601(DateTime.add(now, 3611)),
      "entry_price" => "100",
      "exit_price" => "110",
      "costs" => %{"fee_bps_per_side" => "10", "slippage_bps_per_side" => "5"},
      "lineage" => %{"dataset_hash" => String.duplicate("d", 64)}
    }

    assert {:ok, outcome} = TradingKnowledge.record_outcome(decision.id, attrs)
    assert Decimal.compare(outcome.net_return, "0.1") == :lt
    assert {:error, %Ecto.Changeset{}} = TradingKnowledge.record_outcome(decision.id, attrs)

    assert {:error, :invalid_outcome} =
             TradingKnowledge.record_outcome(
               decision.id,
               Map.put(attrs, "entry_at", DateTime.to_iso8601(now))
             )
  end

  test "synthetic and incomplete evaluation records cannot be reviewed as verified", %{
    version: version
  } do
    source = evidence(version)

    source = %{
      source
      | id: nil,
        status: "unvalidated",
        review: %{},
        lineage: Map.put(source.lineage, "data_kind", "synthetic")
    }

    source = Repo.insert!(source)

    assert {:error, :evidence_not_reviewable} =
             TradingKnowledge.review_evidence(source.id, "reviewer", "eligible")

    assert {:error, :evidence_not_reviewable} =
             TradingKnowledge.review_evidence(source.id, "", "eligible")
  end

  test "paired report and later calibration append exact-version evidence without promoting it",
       %{version: version} do
    base = DateTime.add(DateTime.utc_now(), -72_000)
    stamp = fn offset -> DateTime.add(base, offset) |> DateTime.to_iso8601() end

    splits = %{
      "train_start" => stamp.(-60),
      "train_end" => stamp.(7200),
      "validation_end" => stamp.(21_600),
      "test_end" => stamp.(36_000)
    }

    samples =
      for index <- 0..2 do
        at = DateTime.add(base, index * 14_400)

        %{
          "id" => to_string(index),
          "snapshot" => snapshot(at),
          "decision_at" => DateTime.to_iso8601(at),
          "entry_at" => DateTime.to_iso8601(DateTime.add(at, 60)),
          "exit_at" => DateTime.to_iso8601(DateTime.add(at, 3660)),
          "observed_at" => DateTime.to_iso8601(DateTime.add(at, 3661)),
          "entry_price" => "100",
          "exit_price" => "110"
        }
      end

    costs = %{"fee_bps_per_side" => "10", "slippage_bps_per_side" => "5"}

    options = [
      provider: fn input ->
        refute Map.has_key?(input, "rule_match")
        {:ok, MockDecisionProvider.response()}
      end,
      requested_model: "fixture-jev",
      data_kind: "synthetic"
    ]

    assert {:ok, evidence} =
             TradingKnowledge.evaluate(version.id, samples, splits, costs, options)

    assert evidence.status == "unvalidated"
    assert evidence.sample_count == 3
    assert evidence.lineage["report"]["rows"] |> length() == 3

    assert {:error, :evidence_not_reviewable} =
             TradingKnowledge.review_evidence(evidence.id, "fixture reviewer", "eligible")

    calibration = [
      %{
        "sample_id" => "2",
        "profit_probability" => "0.75",
        "calibrator_version" => "synthetic-v1",
        "calibrator_fitted_at" => stamp.(20_000)
      }
    ]

    assert {:ok, calibrated} = TradingKnowledge.record_calibration(evidence.id, calibration)
    assert calibrated.status == "unvalidated"
    assert calibrated.id != evidence.id
    assert Decimal.equal?(calibrated.lineage["calibration"]["brier_score"], "0.0625")
    assert is_nil(Repo.get!(Evidence, evidence.id).lineage["calibration"])

    assert {:error, :calibration_coverage_or_version_invalid} =
             TradingKnowledge.record_calibration(evidence.id, [])
  end
end
