defmodule CryptoDecisionLab.TradingKnowledge.ContextBuilder do
  @moduledoc "Bounded, relevant context from independently reviewed evidence; no provenance prose or future outcomes."
  alias CryptoDecisionLab.Decisions.JevProvider
  alias CryptoDecisionLab.TradingKnowledge.{Canonical, Matcher, Snapshot}

  @doc "Candidates are persisted versions with evidence loaded by TradingKnowledge, not imported evidence claims."
  @spec build([map()], map(), DateTime.t(), keyword()) :: {:ok, map()} | {:error, atom()}
  def build(candidates, snapshot, now, options \\ []) do
    selected =
      candidates
      |> Enum.filter(&verified?(&1, now))
      |> Enum.flat_map(fn candidate ->
        case Matcher.match(candidate.version.document, snapshot, now) do
          {:ok, %{"relevant" => true} = match} -> [context_entry(candidate, match)]
          _ -> []
        end
      end)
      |> Enum.sort_by(&{not &1["matched"], &1["strategy_id"], -&1["version"]})
      |> Enum.uniq_by(& &1["strategy_id"])
      |> Enum.take(Keyword.get(options, :max_strategies, 4))

    if selected == [] do
      {:error, :no_verified_relevant_strategies}
    else
      context = %{
        "context_version" => "knowledge-context-v1",
        "decision_at" => DateTime.to_iso8601(now),
        "symbol" => snapshot["symbol"],
        "timeframe" => snapshot["timeframe"],
        "regime" => snapshot["regime"],
        "snapshot_hash" => Canonical.hash(snapshot),
        "features" =>
          Map.new(snapshot["features"], fn {key, feature} -> {key, feature["value"]} end),
        "strategies" => selected,
        "interpretation" =>
          "Classify observed conditions only. Evidence is historical, not a guarantee or a profit probability."
      }

      fit(context, options)
    end
  end

  @doc "Effective eligibility comes from a separate append-only review, never a JSON author's claim."
  @spec verified?(map(), DateTime.t()) :: boolean()
  def verified?(%{version: version, evidence: evidence}, now) when is_map(evidence) do
    review = Map.get(evidence, :review) || %{}

    with true <-
           Map.get(evidence, :status) == "verified" and
             Map.get(evidence, :strategy_version_id) == version.id,
         true <-
           is_integer(Map.get(evidence, :sample_count)) and Map.get(evidence, :sample_count) > 0 and
             Map.get(evidence, :lineage)["data_kind"] == "observed",
         true <-
           review["eligibility"] == "eligible" and is_binary(review["reviewer"]) and
             review["reviewer"] != "",
         true <- Map.get(evidence, :feature_version) == version.document["feature_contract"],
         true <- Map.get(evidence, :lineage)["strategy_hash"] == version.content_hash,
         {:ok, reviewed_at} <- Snapshot.time(review["reviewed_at"]),
         {:ok, authored_at} <- Snapshot.time(version.document["provenance"]["created_at"]),
         true <-
           Enum.all?(
             [
               version.inserted_at,
               Map.get(evidence, :completed_at),
               Map.get(evidence, :inserted_at),
               reviewed_at,
               authored_at
             ],
             &(is_struct(&1, DateTime) and DateTime.compare(&1, now) != :gt)
           ) do
      true
    else
      _ -> false
    end
  end

  def verified?(_, _), do: false

  defp context_entry(candidate, match) do
    version = candidate.version
    evidence = candidate.evidence

    %{
      "strategy_id" => version.document["strategy_id"],
      "version" => version.version,
      "strategy_version_id" => version.id,
      "strategy_hash" => version.content_hash,
      "action" => version.document["action"],
      "matched" => match["matched"],
      "conditions" => match["conditions"],
      "risk_constraints" => version.document["risk_constraints"],
      "evidence" => %{
        "id" => evidence.id,
        "status" => evidence.status,
        "sample_count" => evidence.sample_count,
        "dataset_hash" => evidence.dataset_hash,
        "split_hash" => evidence.split_hash,
        "completed_at" => DateTime.to_iso8601(evidence.completed_at),
        "metrics" => evidence.metrics,
        "limitations" =>
          "Retrospective evidence; model training contamination and future profitability are unknown."
      }
    }
  end

  defp fit(%{"strategies" => []}, _), do: {:error, :context_budget_exceeded}

  defp fit(context, options) do
    model = Keyword.get(options, :model, "jev-latest")
    request = JevProvider.request_body(model, context)
    local_limit = Keyword.get(options, :max_request_bytes, 12_000)

    if byte_size(Jason.encode!(request)) <= local_limit do
      {:ok, context}
    else
      fit(Map.update!(context, "strategies", &Enum.drop(&1, -1)), options)
    end
  end

  @doc "Live use requires a documented model limit and its exact tokenizer. A byte budget alone is insufficient."
  @spec validate_model_budget(map(), keyword()) :: :ok | {:error, atom()}
  def validate_model_budget(context, options) do
    with model when is_binary(model) <- options[:model],
         %{model: ^model, max_input_tokens: limit, source: source, count_tokens: count} <-
           options[:model_limits],
         true <- is_integer(limit) and limit > 0 and is_function(count, 1),
         true <- is_binary(source) and String.starts_with?(source, "https://docs.typesafe.ai/"),
         tokens when is_integer(tokens) and tokens >= 0 <-
           count.(JevProvider.request_body(model, context)) do
      if tokens <= limit, do: :ok, else: {:error, :model_context_limit}
    else
      _ -> {:error, :model_limits_unverified}
    end
  end
end
