defmodule CryptoDecisionLab.TradingKnowledge.Research do
  @moduledoc false
  import Ecto.Query
  alias CryptoDecisionLab.Repo
  alias CryptoDecisionLab.TradingKnowledge.{Canonical, Evidence, Evaluation, StrategyVersion}

  def evaluate(version_id, samples, splits, costs, options) do
    with %StrategyVersion{} = version <- Repo.get(StrategyVersion, version_id),
         {:ok, report} <-
           Evaluation.run(
             samples,
             version.document,
             splits,
             costs,
             Keyword.put(options, :candidates, candidates([version.id], DateTime.utc_now()))
           ) do
      now = DateTime.utc_now()
      {:ok, test_end, 0} = DateTime.from_iso8601(splits["test_end"])

      if DateTime.compare(test_end, now) == :gt do
        {:error, :future_evaluation}
      else
        attrs = %Evidence{
          strategy_version_id: version.id,
          status: "unvalidated",
          dataset_hash: report["dataset_hash"],
          split_hash: report["split_hash"],
          configuration_hash: report["configuration_hash"],
          feature_version: report["feature_version"],
          engine_version: report["engine_version"],
          train_end: parse(splits["train_end"]),
          validation_end: parse(splits["validation_end"]),
          test_end: test_end,
          completed_at: now,
          inserted_at: now,
          sample_count: report["sample_count"],
          costs: costs,
          metrics: report["metrics"],
          review: %{},
          lineage: %{
            "data_kind" => report["data_kind"],
            "strategy_hash" => version.content_hash,
            "report_hash" => Canonical.hash(report),
            "report" => report,
            "requested_model" => Keyword.get(options, :requested_model),
            "calibration" => report["calibration"],
            "limitations" => report["limitations"]
          }
        }

        Repo.insert(attrs)
      end
    else
      nil -> {:error, :strategy_not_found}
      error -> error
    end
  end

  # This is an explicit operator review, never invoked by imports or evaluation.
  def review(evidence_id, reviewer, eligibility)
      when eligibility in ~w(eligible disabled) and is_binary(reviewer) do
    with %Evidence{} = evidence <- Repo.get(Evidence, evidence_id),
         true <- String.trim(reviewer) != "" and evidence.status == "unvalidated",
         true <- evidence.lineage["data_kind"] == "observed",
         count when is_integer(count) and count >= 30 <-
           get_in(evidence.metrics, ["test", "knowledge_rules", "sample_count"]),
         trades when is_integer(trades) and trades > 0 <-
           get_in(evidence.metrics, ["test", "knowledge_rules", "trade_count"]),
         true <-
           is_binary(evidence.lineage["requested_model"]) and
             evidence.lineage["requested_model"] != "" do
      now = DateTime.utc_now()

      row = %{
        evidence
        | id: nil,
          status: "verified",
          inserted_at: now,
          review: %{
            "reviewer" => reviewer,
            "reviewed_at" => DateTime.to_iso8601(now),
            "eligibility" => eligibility,
            "source_evidence_id" => evidence.id,
            "meaning" =>
              "Operator reviewed reproducibility and limitations; no guarantee of success."
          }
      }

      Repo.insert(row)
    else
      _ -> {:error, :evidence_not_reviewable}
    end
  end

  def review(_, _, _), do: {:error, :evidence_not_reviewable}

  def record_calibration(evidence_id, samples) when is_list(samples) do
    with %Evidence{} = evidence <- Repo.get(Evidence, evidence_id),
         rows when is_list(rows) <- get_in(evidence.lineage, ["report", "rows"]) do
      targets =
        rows
        |> Enum.filter(
          &(&1["split"] == "test" and get_in(&1, ["arms", "jev_assisted", "decision"]) == "BUY")
        )
        |> Map.new(&{&1["id"], &1})

      ids = Enum.map(samples, & &1["sample_id"])

      valid =
        ids != [] and Enum.sort(ids) == Enum.sort(Map.keys(targets)) and
          Enum.all?(
            samples,
            &(is_binary(&1["calibrator_version"]) and &1["calibrator_version"] != "")
          )

      if valid do
        labeled =
          Enum.map(samples, fn sample ->
            target = targets[sample["sample_id"]]

            sample
            |> Map.put("split", "test")
            |> Map.put("decision_at", target["decision_at"])
            |> Map.put(
              "profitable",
              Decimal.compare(get_in(target, ["arms", "jev_assisted", "net_return"]), 0) == :gt
            )
          end)

        with {:ok, metrics} <- Evaluation.calibration(labeled) do
          report =
            evidence.lineage["report"]
            |> Map.put("calibration", metrics)
            |> Map.put("calibration_reason", nil)

          lineage =
            evidence.lineage
            |> Map.put("report", report)
            |> Map.put("report_hash", Canonical.hash(report))
            |> Map.put("calibration", metrics)
            |> Map.put("calibration_samples", labeled)
            |> Map.put("source_evidence_id", evidence.id)

          now = DateTime.utc_now()

          Repo.insert(%{
            evidence
            | id: nil,
              status: "unvalidated",
              review: %{},
              lineage: lineage,
              configuration_hash:
                Canonical.hash(%{"base" => evidence.configuration_hash, "calibration" => labeled}),
              completed_at: now,
              inserted_at: now
          })
        end
      else
        {:error, :calibration_coverage_or_version_invalid}
      end
    else
      _ -> {:error, :evidence_not_found}
    end
  end

  def candidates(version_ids, now) do
    Repo.all(from v in StrategyVersion, where: v.id in ^version_ids)
    |> Enum.map(fn version ->
      evidence =
        Repo.one(
          from e in Evidence,
            where:
              e.strategy_version_id == ^version.id and e.status == "verified" and
                e.inserted_at <= ^now,
            order_by: [desc: e.inserted_at, desc: e.id],
            limit: 1
        )

      %{version: version, evidence: evidence}
    end)
  end

  defp parse(value) do
    {:ok, time, 0} = DateTime.from_iso8601(value)
    time
  end
end
