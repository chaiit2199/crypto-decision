defmodule CryptoDecisionLab.TradingKnowledge do
  @moduledoc "Public boundary for versioned strategy imports. All files are hypotheses until independently evaluated."
  import Ecto.Query
  alias CryptoDecisionLab.Repo
  alias CryptoDecisionLab.TradingKnowledge.{Canonical, StrategyVersion, Validator}
  @max_file_bytes 65_536

  @spec library_path() :: binary()
  def library_path, do: Application.app_dir(:crypto_decision_lab, "priv/knowledge/strategies")

  @doc "Validate and import all files atomically, sorted by name. Any conflict rolls back the batch."
  @spec import_directory(binary()) :: {:ok, list()} | {:error, term()}
  def import_directory(path \\ library_path()) do
    files = path |> Path.join("*.json") |> Path.wildcard() |> Enum.sort()

    if files == [] do
      {:error, :empty_library}
    else
      Repo.transaction(fn ->
        Enum.map(files, fn file ->
          case import_file(file) do
            {:ok, record} -> record
            {:error, reason} -> Repo.rollback({file, reason})
          end
        end)
      end)
    end
  end

  @spec import_file(binary()) :: {:ok, StrategyVersion.t()} | {:error, term()}
  def import_file(path) do
    with {:ok, stat} <- File.stat(path),
         true <- stat.type == :regular and stat.size <= @max_file_bytes,
         {:ok, bytes} <- File.read(path),
         true <- byte_size(bytes) <= @max_file_bytes,
         {:ok, document} <- decode(bytes) do
      import_document(document)
    else
      false -> {:error, :invalid_file_size_or_type}
      error -> error
    end
  end

  @doc "Decode JSON while rejecting duplicate keys instead of silently overwriting conditions."
  @spec decode(binary()) :: {:ok, map()} | {:error, term()}
  def decode(bytes) do
    with {:ok, ordered} <- Jason.decode(bytes, objects: :ordered_objects) do
      normalize(ordered)
    end
  end

  defp normalize(%Jason.OrderedObject{values: pairs}) do
    if length(pairs) != length(Enum.uniq_by(pairs, &elem(&1, 0))) do
      {:error, :duplicate_json_key}
    else
      Enum.reduce_while(pairs, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
        case normalize(value) do
          {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp normalize(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case normalize(value) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp normalize(value), do: {:ok, value}

  @spec import_document(map()) :: {:ok, StrategyVersion.t()} | {:error, term()}
  def import_document(document) do
    with :ok <- Validator.validate(document) do
      Repo.transaction(fn ->
        key = document["strategy_id"]
        now = DateTime.utc_now()

        Repo.insert_all("knowledge_strategies", [%{key: key, inserted_at: now}],
          on_conflict: :nothing,
          conflict_target: [:key]
        )

        strategy_id =
          Repo.one!(from s in "knowledge_strategies", where: s.key == ^key, select: s.id)

        attrs = %{
          strategy_id: strategy_id,
          version: document["version"],
          schema_version: document["schema_version"],
          document: document,
          content_hash: Canonical.hash(document),
          inserted_at: now
        }

        Repo.insert_all(StrategyVersion, [attrs],
          on_conflict: :nothing,
          conflict_target: [:strategy_id, :version]
        )

        row =
          Repo.get_by!(StrategyVersion, strategy_id: strategy_id, version: document["version"])

        if row.content_hash == attrs.content_hash,
          do: row,
          else: Repo.rollback(:immutable_version_conflict)
      end)
    end
  end

  @spec history(binary()) :: [StrategyVersion.t()]
  def history(key) do
    Repo.all(
      from v in StrategyVersion,
        join: s in "knowledge_strategies",
        on: s.id == v.strategy_id,
        where: s.key == ^key,
        order_by: [asc: v.version],
        select: v
    )
  end

  @doc "Paired offline evaluation; results are unvalidated until separately reviewed."
  @spec evaluate(integer(), [map()], map(), map(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def evaluate(version_id, samples, splits, costs, options),
    do:
      CryptoDecisionLab.TradingKnowledge.Research.evaluate(
        version_id,
        samples,
        splits,
        costs,
        options
      )

  @doc "Explicit operator attestation of observed-data evidence; never an automatic success claim."
  @spec review_evidence(integer(), binary(), binary()) :: {:ok, struct()} | {:error, term()}
  def review_evidence(evidence_id, reviewer, eligibility),
    do: CryptoDecisionLab.TradingKnowledge.Research.review(evidence_id, reviewer, eligibility)

  @doc "Manual knowledge-assisted research, with deterministic policy and append-only lineage."
  @spec analyze(integer(), [integer()], map(), map(), keyword()) ::
          {:ok, [struct()]} | {:error, term()}
  def analyze(symbol_id, version_ids, snapshot, risk_input, options \\ []),
    do:
      CryptoDecisionLab.TradingKnowledge.DecisionService.analyze(
        symbol_id,
        version_ids,
        snapshot,
        risk_input,
        options
      )

  @doc "Record a future observed return label with explicit fees and slippage, without implying an executed trade."
  @spec record_outcome(integer(), map()) :: {:ok, struct()} | {:error, term()}
  def record_outcome(decision_id, attrs),
    do: CryptoDecisionLab.TradingKnowledge.Outcomes.record(decision_id, attrs)

  @doc "Append calibration metrics for every held-out assisted BUY, deriving labels from stored outcomes."
  @spec record_calibration(integer(), [map()]) :: {:ok, struct()} | {:error, term()}
  def record_calibration(evidence_id, samples),
    do: CryptoDecisionLab.TradingKnowledge.Research.record_calibration(evidence_id, samples)
end
