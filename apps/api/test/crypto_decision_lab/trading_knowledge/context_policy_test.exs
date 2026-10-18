defmodule CryptoDecisionLab.TradingKnowledge.ContextPolicyTest do
  use ExUnit.Case, async: true
  alias CryptoDecisionLab.{KnowledgeFixtures, MockDecisionProvider}
  alias CryptoDecisionLab.TradingKnowledge.{Canonical, ContextBuilder, Policy, StrategyVersion}
  alias KnowledgeFixtures, as: F

  defp candidate do
    strategy = F.strategy()
    past = DateTime.add(F.now(), -3600)

    version = %StrategyVersion{
      id: 1,
      version: 1,
      document: strategy,
      content_hash: Canonical.hash(strategy),
      inserted_at: past
    }

    %{
      version: version,
      evidence: %{
        id: 1,
        strategy_version_id: 1,
        status: "verified",
        sample_count: 100,
        feature_version: "hourly-v1",
        inserted_at: past,
        completed_at: past,
        dataset_hash: String.duplicate("a", 64),
        split_hash: String.duplicate("b", 64),
        metrics: %{"fixture" => "synthetic test only"},
        lineage: %{"data_kind" => "observed", "strategy_hash" => version.content_hash},
        review: %{
          "reviewer" => "synthetic test fixture",
          "reviewed_at" => DateTime.to_iso8601(past),
          "eligibility" => "eligible"
        }
      }
    }
  end

  defp risk do
    %{
      "observed_at" => DateTime.to_iso8601(F.now()),
      "available_at" => DateTime.to_iso8601(F.now()),
      "equity" => "10000",
      "price" => "110",
      "quote_volume_24h" => "2000000",
      "absolute_return_1h_percent" => "1",
      "position_quantity" => "0"
    }
  end

  test "context includes condition failures and evidence; drops prose and unverified candidates" do
    eligible = candidate()
    invalid = put_in(eligible, [:evidence, :status], "unvalidated")
    assert {:ok, context} = ContextBuilder.build([eligible, invalid], F.snapshot(), F.now())

    assert [%{"conditions" => conditions, "evidence" => %{"sample_count" => 100}} = entry] =
             context["strategies"]

    assert conditions["invalidation_conditions"] != []
    refute Map.has_key?(entry, "provenance")

    assert {:error, :no_verified_relevant_strategies} =
             ContextBuilder.build([invalid], F.snapshot(), F.now())
  end

  test "future or wrong-version evidence and future authored strategies are excluded" do
    for invalid <- [
          put_in(candidate(), [:evidence, :strategy_version_id], 2),
          put_in(candidate(), [:evidence, :inserted_at], DateTime.add(F.now(), 1)),
          put_in(candidate(), [:evidence, :review, "eligibility"], "disabled"),
          put_in(candidate(), [:evidence, :lineage, "data_kind"], "synthetic"),
          put_in(
            candidate(),
            [:version, Access.key(:document), "provenance", "created_at"],
            "2027-01-01T00:00:00Z"
          )
        ] do
      refute ContextBuilder.verified?(invalid, F.now())
    end
  end

  test "budget uses full request and requires documented tokenizer limits for live use" do
    assert {:error, :context_budget_exceeded} =
             ContextBuilder.build([candidate()], F.snapshot(), F.now(), max_request_bytes: 20)

    assert {:ok, context} = ContextBuilder.build([candidate()], F.snapshot(), F.now())

    assert {:error, :model_limits_unverified} =
             ContextBuilder.validate_model_budget(context, model: "fixture")

    limits = %{
      model: "fixture",
      max_input_tokens: 10,
      source: "https://docs.typesafe.ai/fixture-only",
      count_tokens: fn request ->
        assert Map.has_key?(request, :questions)
        11
      end
    }

    assert {:error, :model_context_limit} =
             ContextBuilder.validate_model_budget(context, model: "fixture", model_limits: limits)
  end

  test "verified evidence plus matching model still needs fresh data and risk checks" do
    response = MockDecisionProvider.response()

    assert %{"decision" => "BUY", "execution_allowed" => false, "quantity" => quantity} =
             Policy.decide(candidate(), F.snapshot(), response, risk(), F.now())

    assert Decimal.compare(Decimal.mult(quantity, 110), 1000) != :gt

    assert %{"decision" => "WAIT"} =
             Policy.decide(
               put_in(candidate(), [:evidence, :status], "unvalidated"),
               F.snapshot(),
               response,
               risk(),
               F.now()
             )

    for bad_risk <- [
          Map.put(risk(), "quote_volume_24h", "1"),
          Map.put(risk(), "absolute_return_1h_percent", "10"),
          Map.put(risk(), "observed_at", "2026-10-18T10:00:00Z")
        ] do
      assert %{"decision" => "WAIT", "reason" => "risk_constraints_failed"} =
               Policy.decide(candidate(), F.snapshot(), response, bad_risk, F.now())
    end

    assert %{"decision" => "NO_DATA"} =
             Policy.decide(candidate(), F.snapshot(), %{}, risk(), F.now())
  end
end
