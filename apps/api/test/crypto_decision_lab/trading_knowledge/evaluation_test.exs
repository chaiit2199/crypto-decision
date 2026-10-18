defmodule CryptoDecisionLab.TradingKnowledge.EvaluationTest do
  use ExUnit.Case, async: true
  alias CryptoDecisionLab.{KnowledgeFixtures, MockDecisionProvider}
  alias CryptoDecisionLab.TradingKnowledge.Evaluation
  alias KnowledgeFixtures, as: F

  defp splits do
    %{
      "train_start" => "2026-10-01T00:00:00Z",
      "train_end" => "2026-10-06T00:00:00Z",
      "validation_end" => "2026-10-12T00:00:00Z",
      "test_end" => "2026-10-19T00:00:00Z"
    }
  end

  defp costs, do: %{"fee_bps_per_side" => "10", "slippage_bps_per_side" => "5"}

  defp sample(day) do
    day = String.pad_leading(to_string(day), 2, "0")
    shift = fn timestamp -> String.replace(timestamp, "2026-10-18", "2026-10-#{day}") end

    snapshot =
      F.snapshot()
      |> Map.update!("as_of", shift)
      |> Map.update!("available_at", shift)
      |> Map.update!("features", fn features ->
        Map.new(features, fn {name, feature} ->
          {name,
           feature |> Map.update!("observed_at", shift) |> Map.update!("available_at", shift)}
        end)
      end)

    %{
      "id" => day,
      "snapshot" => snapshot,
      "decision_at" => "2026-10-#{day}T12:00:10Z",
      "entry_at" => "2026-10-#{day}T13:00:00Z",
      "exit_at" => "2026-10-#{day}T14:00:00Z",
      "observed_at" => "2026-10-#{day}T14:00:01Z",
      "entry_price" => "100",
      "exit_price" => "110"
    }
  end

  defp provider(input) do
    assert Map.keys(input) |> Enum.sort() == ~w(mode snapshot)
    refute Map.has_key?(input, "outcome")
    {:ok, MockDecisionProvider.response()}
  end

  test "all arms use identical chronological splits, real costs and model lineage" do
    assert {:ok, report} =
             Evaluation.run([sample(2), sample(8), sample(18)], F.strategy(), splits(), costs(),
               provider: &provider/1
             )

    assert report["status"] == "unvalidated"
    assert report["data_kind"] == "synthetic"
    assert is_nil(report["calibration"])

    for split <- ~w(train validation test) do
      assert report["metrics"][split]["indicator_only"] ==
               report["metrics"][split]["knowledge_rules"]

      assert report["metrics"][split]["knowledge_rules"] ==
               report["metrics"][split]["jev_assisted"]

      assert Decimal.compare(report["metrics"][split]["knowledge_rules"]["net_return"], "0.1") ==
               :lt
    end

    assert Enum.all?(report["rows"], &(&1["model"] == "fixture-jev"))
  end

  test "boundary-crossing outcomes, overlapping samples and same-bar entries are rejected" do
    for samples <- [
          [sample(8), sample(2)],
          [sample(2), sample(2)],
          [Map.put(sample(2), "exit_at", "2026-10-07T00:00:00Z")],
          [Map.put(sample(2), "entry_at", sample(2)["decision_at"])]
        ] do
      assert {:error, :invalid_or_leaking_samples} =
               Evaluation.run(samples, F.strategy(), splits(), costs(), provider: &provider/1)
    end
  end

  test "missing provider result fails comparison rather than fabricating an AI baseline" do
    assert {:error, :provider_failed_comparison_incomplete} =
             Evaluation.run([sample(2)], F.strategy(), splits(), costs(),
               provider: fn _ -> {:error, :unavailable} end
             )
  end

  test "calibration is separate from classification confidence and rejects future fitting" do
    sample = %{
      "profit_probability" => "0.75",
      "profitable" => true,
      "split" => "test",
      "calibrator_fitted_at" => "2026-09-01T00:00:00Z",
      "decision_at" => "2026-10-01T00:00:00Z"
    }

    assert {:ok, metrics} = Evaluation.calibration([sample])
    assert Decimal.equal?(metrics["brier_score"], "0.0625")

    assert {:error, :invalid_or_in_sample_calibration} =
             Evaluation.calibration([
               Map.put(sample, "calibrator_fitted_at", "2027-01-01T00:00:00Z")
             ])

    assert {:error, :invalid_or_in_sample_calibration} =
             Evaluation.calibration([Map.delete(sample, "profit_probability")])
  end

  test "SELL experiments liquidate an existing holding and never simulate short exposure" do
    strategy = Map.put(F.strategy(), "action", "SELL")

    assert {:ok, report} =
             Evaluation.run([sample(2)], strategy, splits(), costs(), provider: &provider/1)

    [row] = report["rows"]
    assert row["initial_position"] == "existing_spot_holding"
    assert row["arms"]["knowledge_rules"]["decision"] == "SELL"
    assert Decimal.equal?(row["arms"]["knowledge_rules"]["net_return"], "-0.0015")
    assert is_nil(report["metrics"]["train"]["knowledge_rules"]["win_rate"])
  end

  test "labels unavailable until after the split are purged" do
    late = Map.put(sample(2), "observed_at", "2026-10-07T00:00:00Z")

    assert {:error, :invalid_or_leaking_samples} =
             Evaluation.run([late], F.strategy(), splits(), costs(), provider: &provider/1)
  end
end
