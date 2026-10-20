defmodule CryptoDecisionLab.Decisions do
  @moduledoc "Research analysis on configured UTC slots. Reads never trigger paid provider calls."
  import Ecto.Query
  require Logger
  alias CryptoDecisionLab.{Repo, MarketData, TechnicalAnalysis, Trading}
  alias CryptoDecisionLab.MarketData.Collector
  alias CryptoDecisionLab.Decisions.{Analysis, AnalysisWorker, JevProvider}
  alias CryptoDecisionLab.Trading.Assessment

  @version "hourly-research-v4-horizon"
  @pending_data_reasons ~w(missing_snapshots stale_price stale_stats insufficient_candles candle_gap stale_candles)
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:crypto_decision_lab, :jev, [])[:enabled] == true

  @doc "Research interval in seconds; whole-minute slots match the Cron dispatcher."
  @spec interval_seconds() :: pos_integer()
  def interval_seconds do
    interval = Application.fetch_env!(:crypto_decision_lab, :analysis_interval_seconds)

    if is_integer(interval) and interval >= 60 and rem(interval, 60) == 0 do
      interval
    else
      raise ArgumentError, "analysis_interval_seconds must be a positive multiple of 60"
    end
  end

  @doc "Cron checks each minute but only dispatches in the first minute of the configured slot."
  @spec enqueue_due() :: {:ok, non_neg_integer()} | {:error, term()}
  def enqueue_due do
    if rem(DateTime.to_unix(Collector.now()), interval_seconds()) < 60,
      do: enqueue_all(),
      else: {:ok, 0}
  end

  @spec enqueue_all() :: {:ok, non_neg_integer()} | {:error, term()}
  def enqueue_all do
    if enabled?() do
      interval = interval_seconds()
      slot = div(DateTime.to_unix(Collector.now()), interval) * interval

      Repo.transaction(fn ->
        (MarketData.Sync.active_symbols() ++
           MarketData.SourceSync.active_symbols("coinbase") ++
           MarketData.SourceSync.active_symbols("gold_api"))
        |> Enum.map(fn symbol ->
          case %{symbol_id: symbol.id, slot: slot} |> AnalysisWorker.new() |> Oban.insert() do
            {:ok, job} -> job.id
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
        |> length()
      end)
    else
      {:ok, 0}
    end
  end

  @doc "Call the provider at most once per symbol/slot; recheck pending inputs under the DB lock."
  @spec analyze(integer(), integer()) :: {:ok, term()} | {:error, term()}
  def analyze(symbol_id, unix_slot) do
    now = Collector.now()
    slot = DateTime.from_unix!(unix_slot * 1_000_000, :microsecond)

    cond do
      not enabled?() ->
        {:ok, :disabled}

      rem(unix_slot, interval_seconds()) != 0 or
          DateTime.diff(now, slot) not in 0..(interval_seconds() - 1) ->
        {:ok, :expired}

      true ->
        Repo.transaction(
          fn ->
            case Repo.query!("SELECT pg_try_advisory_xact_lock(764218, 1)").rows do
              [[true]] -> analyze_locked(symbol_id, slot, now)
              _ -> Repo.rollback(:busy)
            end
          end,
          timeout: 30_000
        )
    end
  end

  @doc "Only missing/stale input is retried; never repeat a completed provider call."
  @spec awaiting_data?(term()) :: boolean()
  def awaiting_data?(%Analysis{status: "no_data", reason: reason}),
    do: reason in @pending_data_reasons

  def awaiting_data?(_), do: false

  defp analyze_locked(symbol_id, slot, now) do
    existing = Repo.get_by(Analysis, market_symbol_id: symbol_id, slot: slot)

    if existing && not awaiting_data?(existing) do
      existing
    else
      config = Application.fetch_env!(:crypto_decision_lab, :jev)

      attrs = %{
        slot: slot,
        status: "no_data",
        signal: "NO_DATA",
        requested_model: config[:model],
        configuration_version: @version,
        analyzed_at: now,
        valid_until: DateTime.add(slot, interval_seconds()),
        risk_result: %{mode: "research_only", execution_allowed: false}
      }

      result =
        with {:ok, inputs} <- MarketData.analysis_inputs(symbol_id, now),
             {:ok, features} <- TechnicalAnalysis.features(inputs.candles, now) do
          features =
            features
            |> Map.merge(inputs.snapshot)
            |> Map.put("context_timeframes", context_timeframes(symbol_id, now))

          attrs = Map.merge(attrs, %{features: features, data_at: inputs.price_at})
          evaluate(attrs, features, now)
        else
          {:error, reason} -> Map.put(attrs, :reason, to_string(reason))
        end

      record =
        (existing || %Analysis{market_symbol_id: symbol_id})
        |> Analysis.changeset(Map.put_new(result, :reason, nil))
        |> Repo.insert_or_update!()

      Logger.info("jev_analysis",
        symbol_id: symbol_id,
        status: record.status,
        reason: record.reason
      )

      record
    end
  end

  defp evaluate(attrs, features, now) do
    with :ok <- available(now),
         {:ok, response} <- provider().analyze(features) do
      # Validate even injected providers before accepting a persisted successful response.
      case JevProvider.decode({:ok, %{status: 200, body: response}}) do
        {:ok, response} ->
          answers = response["answers"]

          Map.merge(attrs, %{
            status: "ready",
            signal: signal(answers),
            model: response["model"],
            answers: answers,
            raw_response: response
          })

        {:error, reason, cooldown} ->
          failure(attrs, reason, cooldown, now)
      end
    else
      {:error, reason, cooldown} -> failure(attrs, reason, cooldown, now)
      {:blocked, reason} -> Map.merge(attrs, %{status: "error", reason: reason})
    end
  end

  defp provider, do: Application.get_env(:crypto_decision_lab, :decision_provider, JevProvider)

  defp available(now) do
    case Repo.query!("SELECT blocked_until, last_error FROM jev_provider_states WHERE id = 1").rows do
      [[%NaiveDateTime{} = until, reason]] ->
        if NaiveDateTime.compare(until, DateTime.to_naive(now)) == :gt and
             not (reason == "missing_api_key" and JevProvider.configured?()),
           do: {:blocked, reason},
           else: :ok

      _ ->
        :ok
    end
  end

  defp failure(attrs, reason, seconds, now) do
    Repo.query!(
      """
      INSERT INTO jev_provider_states (id, blocked_until, last_error) VALUES (1, $1, $2)
      ON CONFLICT (id) DO UPDATE SET blocked_until = EXCLUDED.blocked_until, last_error = EXCLUDED.last_error
      """,
      [DateTime.to_naive(DateTime.add(now, seconds)), reason]
    )

    Map.merge(attrs, %{status: "error", reason: reason})
  end

  # Research labels only: confidence is deliberately not treated as expected trading profit.
  defp signal(answers) do
    case {answers["trend"]["choice"], answers["momentum"]["choice"],
          answers["volatility"]["choice"]} do
      {"BULLISH", "STRENGTHENING", "NORMAL"} -> "BUY"
      {"BEARISH", "WEAKENING", "NORMAL"} -> "SELL"
      _ -> "WAIT"
    end
  end

  # Bounded multi-timeframe summary for horizon classification; missing frames stay explicit.
  defp context_timeframes(symbol_id, now) do
    Map.new(["5m", "15m", "1h", "4h", "1d"], fn timeframe ->
      frame = Trading.frame(symbol_id, timeframe, now)
      features = frame["features"] || %{}

      {timeframe,
       %{
         "status" => frame["status"],
         "reason" => frame["reason"],
         "regime" => Assessment.regime(features),
         "atr_percent" => features["atr_percent"],
         "ema20" => features["ema20"],
         "ema50" => features["ema50"],
         "ema200" => features["ema200"],
         "last_close_time" => features["last_close_time"]
       }}
    end)
  end

  @doc "Latest analysis per symbol, with expiry calculated at read time; no provider I/O."
  @spec latest([integer()]) :: map()
  def latest(ids) do
    Repo.all(
      from a in Analysis,
        where: a.market_symbol_id in ^ids,
        distinct: a.market_symbol_id,
        order_by: [asc: a.market_symbol_id, desc: a.slot]
    )
    |> Map.new(fn row ->
      fresh = DateTime.compare(Collector.now(), row.valid_until) == :lt

      data =
        Map.take(row, [
          :id,
          :status,
          :signal,
          :model,
          :configuration_version,
          :features,
          :answers,
          :risk_result,
          :reason,
          :data_at,
          :analyzed_at,
          :valid_until
        ])

      {row.market_symbol_id, Map.put(data, :freshness, if(fresh, do: "fresh", else: "stale"))}
    end)
  end
end
