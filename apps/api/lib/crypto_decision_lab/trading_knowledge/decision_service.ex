defmodule CryptoDecisionLab.TradingKnowledge.DecisionService do
  @moduledoc false
  alias CryptoDecisionLab.Repo
  alias CryptoDecisionLab.Decisions.JevProvider
  alias CryptoDecisionLab.MarketData.Symbol

  alias CryptoDecisionLab.TradingKnowledge.{
    AIDecision,
    Canonical,
    ContextBuilder,
    Match,
    Matcher,
    Policy,
    Research,
    Snapshot
  }

  def analyze(symbol_id, version_ids, snapshot, risk_input, options) do
    Repo.transaction(
      fn ->
        case Repo.query!("SELECT pg_try_advisory_xact_lock(764218, 1)").rows do
          [[true]] ->
            case analyze_locked(symbol_id, version_ids, snapshot, risk_input, options) do
              {:ok, rows} -> rows
              {:error, reason} -> Repo.rollback(reason)
            end

          _ ->
            Repo.rollback(:busy)
        end
      end,
      timeout: 30_000
    )
  end

  defp analyze_locked(symbol_id, version_ids, snapshot, risk_input, options) do
    now = Keyword.get(options, :now, DateTime.utc_now())

    with %Symbol{symbol: symbol} <- Repo.get(Symbol, symbol_id),
         true <- symbol == snapshot["symbol"],
         :ok <- Snapshot.validate(snapshot, now, 3660),
         candidates when candidates != [] <- Research.candidates(version_ids, now) do
      config = Application.get_env(:crypto_decision_lab, :jev, [])
      model = Keyword.get(options, :model, config[:model] || "jev-latest")
      options = Keyword.put(options, :model, model)
      provider = Keyword.get(options, :provider, JevProvider)

      with {:ok, context} <- ContextBuilder.build(candidates, snapshot, now, options),
           :ok <- ContextBuilder.validate_model_budget(context, options),
           :ok <- model_matches_config(provider, model, config),
           :ok <- available(now),
           {:ok, raw} <- provider.analyze(context),
           {:ok, raw} <- JevProvider.decode({:ok, %{status: 200, body: raw}}) do
        selected_ids = Enum.map(context["strategies"], & &1["strategy_version_id"])
        selected = Enum.filter(candidates, &(&1.version.id in selected_ids))
        persist(symbol_id, selected, snapshot, risk_input, context, raw, now, model, provider)
      else
        {:error, reason}
        when reason in [
               :no_verified_relevant_strategies,
               :model_limits_unverified,
               :model_context_limit,
               :context_budget_exceeded
             ] ->
          persist_skipped(symbol_id, candidates, snapshot, now, reason)

        {:error, reason, cooldown} ->
          block(reason, cooldown, now)
          persist_skipped(symbol_id, candidates, snapshot, now, reason, "NO_DATA")

        {:blocked, reason} ->
          persist_skipped(symbol_id, candidates, snapshot, now, reason, "NO_DATA")

        error ->
          error
      end
    else
      nil -> {:error, :symbol_not_found}
      false -> {:error, :symbol_mismatch}
      [] -> {:error, :strategy_not_found}
      error -> error
    end
  end

  defp available(now) do
    case Repo.query!("SELECT blocked_until, last_error FROM jev_provider_states WHERE id = 1").rows do
      [[%NaiveDateTime{} = until, reason]] ->
        if NaiveDateTime.compare(until, DateTime.to_naive(now)) == :gt,
          do: {:blocked, reason},
          else: :ok

      _ ->
        :ok
    end
  end

  defp block(reason, seconds, now) do
    Repo.query!(
      """
      INSERT INTO jev_provider_states (id, blocked_until, last_error) VALUES (1, $1, $2)
      ON CONFLICT (id) DO UPDATE SET blocked_until = EXCLUDED.blocked_until, last_error = EXCLUDED.last_error
      """,
      [DateTime.to_naive(DateTime.add(now, max(seconds, 1))), reason]
    )
  end

  defp model_matches_config(JevProvider, model, config) do
    if config[:model] == model, do: :ok, else: {:error, :requested_model_mismatch}
  end

  defp model_matches_config(_, _, _), do: :ok

  defp persist(symbol_id, candidates, snapshot, risk, context, raw, now, model, provider) do
    Repo.transaction(fn ->
      Enum.map(candidates, fn candidate ->
        policy = Policy.decide(candidate, snapshot, raw, risk, now)
        match = insert_match(symbol_id, candidate, snapshot, now)

        Repo.insert!(%AIDecision{
          match_id: match.id,
          evidence_id: candidate.evidence.id,
          provider: inspect(provider),
          requested_model: model,
          model: raw["model"],
          policy_version: policy["policy_version"],
          context: context,
          context_hash: Canonical.hash(context),
          classification: raw["answers"],
          raw_response: raw,
          decision: policy["decision"],
          risk_result: Map.put(policy, "input", risk),
          decision_at: now,
          recorded_at: DateTime.utc_now(),
          execution_allowed: false
        })
      end)
    end)
  end

  defp persist_skipped(symbol_id, candidates, snapshot, now, reason, decision \\ "WAIT") do
    Repo.transaction(fn ->
      Enum.map(candidates, fn candidate ->
        match = insert_match(symbol_id, candidate, snapshot, now)

        Repo.insert!(%AIDecision{
          match_id: match.id,
          provider: "none",
          policy_version: "knowledge-policy-v1",
          context: %{},
          context_hash: Canonical.hash(%{}),
          classification: %{},
          raw_response: %{},
          decision: decision,
          risk_result: %{"reason" => to_string(reason), "execution_allowed" => false},
          decision_at: now,
          recorded_at: DateTime.utc_now(),
          execution_allowed: false
        })
      end)
    end)
  end

  defp insert_match(symbol_id, candidate, snapshot, now) do
    {:ok, result} = Matcher.match(candidate.version.document, snapshot, now)
    {:ok, data_at} = Snapshot.time(snapshot["as_of"])
    {:ok, available_at} = Snapshot.time(snapshot["available_at"])

    attrs = %{
      strategy_version_id: candidate.version.id,
      market_symbol_id: symbol_id,
      decision_at: now,
      data_at: data_at,
      available_at: available_at,
      snapshot: snapshot,
      snapshot_hash: Canonical.hash(snapshot),
      result: result,
      engine_version: result["engine_version"],
      inserted_at: DateTime.utc_now()
    }

    Repo.insert_all(Match, [attrs],
      on_conflict: :nothing,
      conflict_target: [:strategy_version_id, :market_symbol_id, :decision_at, :snapshot_hash]
    )

    Repo.get_by!(
      Match,
      Map.take(attrs, [:strategy_version_id, :market_symbol_id, :decision_at, :snapshot_hash])
    )
  end
end
