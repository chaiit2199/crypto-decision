defmodule CryptoDecisionLab.MarketData.Sync do
  @moduledoc "Idempotent market-data services. Each call holds the shared collector lock for one bounded batch."
  import Ecto.Query
  require Logger
  alias CryptoDecisionLab.Repo

  alias CryptoDecisionLab.MarketData.{
    Asset,
    Symbol,
    LatestPrice,
    TickerStats,
    Candle,
    SyncState,
    Universe,
    Collector,
    Binance,
    Parser
  }

  @hour 3_600_000
  @widths %{"5m" => 300_000, "15m" => 900_000, "1h" => @hour}

  def active_symbols do
    Repo.all(
      from s in Symbol,
        join: a in Asset,
        on: s.asset_id == a.id,
        where:
          s.exchange == "binance" and s.enabled and a.enabled and s.trading_status == "TRADING",
        order_by: s.id
    )
  end

  def metadata do
    Collector.run(fn ->
      Universe.seed()

      with {:ok, response} <- Binance.exchange_info(),
           {:ok, rows, limit} <- metadata_rows(response.body) do
        now = response.fetched_at

        assets =
          Map.new(
            Repo.all(from(a in Asset, where: a.category != "precious_metals")),
            &{&1.symbol, &1.id}
          )

        # Absence means unavailable, not a user preference change.
        Repo.update_all(from(s in Symbol, where: s.exchange == "binance"),
          set: [trading_status: "UNAVAILABLE", updated_at: now]
        )

        for row <- rows, Map.has_key?(assets, row["baseAsset"]), row["quoteAsset"] == "USDT" do
          attrs = %{
            asset_id: assets[row["baseAsset"]],
            exchange: "binance",
            symbol: row["symbol"],
            base_asset: row["baseAsset"],
            quote_asset: row["quoteAsset"],
            trading_status: if(row["isSpotTradingAllowed"], do: row["status"], else: "NOT_SPOT"),
            enabled: true,
            inserted_at: now,
            updated_at: now
          }

          Repo.insert_all(Symbol, [attrs],
            conflict_target: [:exchange, :symbol],
            on_conflict: {:replace, [:trading_status, :base_asset, :quote_asset, :updated_at]}
          )
        end

        Collector.update(%{metadata_at: now, weight_limit: min(limit, 1200), last_error: nil})
        {:ok, length(active_symbols())}
      else
        {:error, reason} -> failure(reason)
      end
    end)
  end

  defp metadata_rows(%{"symbols" => rows, "rateLimits" => limits})
       when is_list(rows) and is_list(limits) and rows != [] do
    valid =
      Enum.all?(rows, fn row ->
        is_map(row) and Enum.all?(~w(symbol baseAsset quoteAsset status), &is_binary(row[&1])) and
          is_boolean(row["isSpotTradingAllowed"])
      end)

    limit =
      Enum.find_value(limits, fn
        %{
          "rateLimitType" => "REQUEST_WEIGHT",
          "interval" => "MINUTE",
          "intervalNum" => 1,
          "limit" => n
        }
        when is_integer(n) and n > 0 ->
          n

        _ ->
          nil
      end)

    if valid and limit, do: {:ok, rows, limit}, else: {:error, :invalid_exchange_info}
  end

  defp metadata_rows(_), do: {:error, :invalid_exchange_info}

  def prices, do: Collector.run(&sync_prices/0)

  def poll do
    Collector.run(fn ->
      now = Collector.now()
      next = Collector.state().next_poll_at

      if next && DateTime.compare(next, now) == :gt do
        {:ok, :not_due}
      else
        result = sync_prices()
        # Shared deadline survives process restarts and prevents duplicate node polls.
        Collector.update(%{
          next_poll_at:
            DateTime.add(
              now,
              Application.fetch_env!(:crypto_decision_lab, :price_poll_interval_ms),
              :millisecond
            )
        })

        result
      end
    end)
  end

  defp sync_prices do
    symbols = active_symbols()

    if symbols == [] do
      {:error, :no_symbols}
    else
      with {:ok, response} <- Binance.prices(Enum.map(symbols, & &1.symbol)),
           {:ok, parsed, invalid} <- parse_rows(response.body, &Parser.price/1) do
        save_snapshots(symbols, parsed, invalid, LatestPrice, response.fetched_at, :prices_at)
      else
        {:error, reason} -> failure(reason)
      end
    end
  end

  def stats do
    Collector.run(fn ->
      batches = active_symbols() |> Enum.chunk_every(20)

      if batches == [] do
        {:error, :no_symbols}
      else
        Enum.reduce_while(batches, {:ok, 0}, fn symbols, {:ok, total} ->
          with {:ok, response} <- Binance.stats(Enum.map(symbols, & &1.symbol)),
               {:ok, parsed, invalid} <-
                 parse_rows(response.body, &Parser.stats(&1, response.fetched_at)),
               {:ok, count} <-
                 save_snapshots(symbols, parsed, invalid, TickerStats, response.fetched_at, nil) do
            {:cont, {:ok, total + count}}
          else
            {:error, reason} -> {:halt, failure(reason)}
          end
        end)
        |> case do
          {:ok, count} ->
            Collector.update(%{stats_at: Collector.now(), last_error: nil})
            {:ok, count}

          error ->
            error
        end
      end
    end)
  end

  defp parse_rows(rows, parser) when is_list(rows) do
    {values, invalid} =
      Enum.reduce(rows, {[], 0}, fn row, {values, invalid} ->
        case parser.(row) do
          {:ok, value} -> {[value | values], invalid}
          {:error, _} -> {values, invalid + 1}
        end
      end)

    {:ok, values, invalid}
  end

  defp parse_rows(_, _), do: {:error, :invalid_response}

  defp save_snapshots(symbols, parsed, invalid, schema, fetched_at, success_key) do
    ids = Map.new(symbols, &{&1.symbol, &1.id})
    selected = Enum.filter(parsed, &Map.has_key?(ids, &1.symbol))
    unique = Enum.uniq_by(selected, & &1.symbol)

    rows =
      Enum.map(unique, fn value ->
        value
        |> Map.delete(:symbol)
        |> Map.merge(%{
          market_symbol_id: ids[value.symbol],
          fetched_at: fetched_at,
          updated_at: fetched_at
        })
      end)

    if rows != [] do
      fields = Map.keys(hd(rows)) -- [:market_symbol_id]
      # All collection is serialized, so the locked read is sufficient to reject older snapshots.
      Enum.each(rows, fn row ->
        existing = Repo.get(schema, row.market_symbol_id)

        if is_nil(existing) or
             (DateTime.compare(existing.fetched_at, fetched_at) != :gt and
                (schema != TickerStats or DateTime.compare(existing.data_at, row.data_at) != :gt)) do
          Repo.insert_all(schema, [row],
            on_conflict: {:replace, fields},
            conflict_target: [:market_symbol_id]
          )
        end
      end)
    end

    if invalid == 0 and length(unique) == length(symbols) and length(unique) == length(selected) do
      if success_key, do: Collector.update(%{success_key => fetched_at, :last_error => nil})
      {:ok, length(rows)}
    else
      failure(:partial_response)
    end
  end

  @doc "Fetch and commit one historical batch. Returns :more for durable continuation."
  def candles(symbol_id, mode \\ :backfill, options \\ [])
      when mode in [:backfill, :incremental, :repair] do
    Collector.run(fn ->
      with %Symbol{exchange: "binance"} = symbol <- Repo.get(Symbol, symbol_id),
           true <-
             symbol.enabled and symbol.trading_status == "TRADING" and
               Repo.get!(Asset, symbol.asset_id).enabled do
        timeframe = Keyword.get(options, :timeframe, "1h")
        width = Map.fetch!(@widths, timeframe)
        state = state(symbol.id, Atom.to_string(mode), timeframe)
        now = Collector.now()
        start_ms = start_ms(symbol, state, mode, options, now, timeframe, width)
        end_ms = Keyword.get(options, :to, DateTime.to_unix(now, :millisecond) - 5001)
        mark_state(symbol.id, mode, %{status: "running", last_attempt_at: now}, timeframe)

        cond do
          start_ms > end_ms ->
            mark_state(
              symbol.id,
              mode,
              %{
                status: "complete",
                last_success_at: now,
                last_error: nil
              },
              timeframe
            )

            {:ok, :complete}

          true ->
            case Binance.klines(symbol.symbol, start_ms, end_ms, timeframe: timeframe) do
              {:ok, response} ->
                cutoff =
                  Enum.min_by([now, response.server_time], &DateTime.to_unix(&1, :microsecond))

                persist_batch(
                  symbol,
                  state,
                  mode,
                  response.body,
                  cutoff,
                  start_ms,
                  end_ms,
                  timeframe,
                  width
                )

              {:error, reason} ->
                mark_state(
                  symbol.id,
                  mode,
                  %{status: "error", last_error: safe_reason(reason)},
                  timeframe
                )

                failure(reason)
            end
        end
      else
        _ -> {:error, :symbol_unavailable}
      end
    end)
  end

  defp start_ms(_symbol, state, :backfill, opts, now, timeframe, width) do
    days = %{"5m" => 30, "15m" => 90, "1h" => 3 * 365}[timeframe]
    initial = Keyword.get(opts, :from, DateTime.to_unix(now, :millisecond) - days * 86_400_000)

    if state && state.last_synced_open_time,
      do: DateTime.to_unix(state.last_synced_open_time, :millisecond) + width,
      else: div(initial + width - 1, width) * width
  end

  defp start_ms(_symbol, _state, :repair, opts, _now, _timeframe, _width),
    do: Keyword.fetch!(opts, :from)

  defp start_ms(symbol, state, :incremental, _opts, now, timeframe, width) do
    latest =
      if state && state.last_synced_open_time do
        state.last_synced_open_time
      else
        Repo.one(
          from c in Candle,
            where: c.market_symbol_id == ^symbol.id and c.timeframe == ^timeframe,
            select: max(c.open_time)
        )
      end

    if latest,
      do: DateTime.to_unix(latest, :millisecond),
      else: div(DateTime.to_unix(now, :millisecond), width) * width - 300 * width
  end

  defp persist_batch(symbol, previous, mode, raw, cutoff, start_ms, end_ms, timeframe, width)
       when is_list(raw) do
    result =
      Enum.reduce_while(raw, {:ok, []}, fn row, {:ok, values} ->
        case Parser.candle(row, cutoff, timeframe) do
          {:ok, value} ->
            time = DateTime.to_unix(value.open_time, :millisecond)

            if time >= start_ms and time <= end_ms,
              do: {:cont, {:ok, [value | values]}},
              else: {:halt, {:error, :out_of_range_candle}}

          {:skip, :incomplete} ->
            {:cont, {:ok, values}}

          error ->
            {:halt, error}
        end
      end)

    case result do
      {:ok, values} ->
        values = Enum.reverse(values)
        times = Enum.map(values, &DateTime.to_unix(&1.open_time, :millisecond))

        if times != Enum.sort(Enum.uniq(times)) or
             Enum.any?(Enum.chunk_every(times, 2, 1, :discard), fn [a, b] -> b - a != width end) or
             (not is_nil(previous) and not is_nil(previous.last_synced_open_time) and times != [] and
                hd(times) > start_ms) do
          candle_failure(symbol.id, mode, :candle_gap, timeframe)
        else
          now = Collector.now()

          rows =
            Enum.map(values, &Map.merge(&1, %{market_symbol_id: symbol.id, inserted_at: now}))

          if rows != [] do
            fields =
              Map.keys(hd(rows)) -- [:market_symbol_id, :timeframe, :open_time, :inserted_at]

            Repo.insert_all(Candle, rows,
              conflict_target: [:market_symbol_id, :timeframe, :open_time],
              on_conflict: {:replace, fields}
            )
          end

          last = List.last(values)

          checkpoint =
            if last, do: last.open_time, else: previous && previous.last_synced_open_time

          more =
            length(raw) == 1000 and last != nil and
              DateTime.to_unix(last.open_time, :millisecond) + width <= end_ms

          mark_state(
            symbol.id,
            mode,
            %{
              last_synced_open_time: checkpoint,
              range_start:
                (previous && previous.range_start) ||
                  DateTime.from_unix!(start_ms * 1000, :microsecond),
              status: if(more, do: "running", else: "complete"),
              last_success_at: now,
              last_error: nil
            },
            timeframe
          )

          Logger.info("candles_synced", symbol: symbol.symbol, count: length(rows), mode: mode)
          {:ok, if(more, do: :more, else: :complete)}
        end

      {:error, reason} ->
        candle_failure(symbol.id, mode, reason, timeframe)
    end
  end

  defp persist_batch(symbol, _, mode, _, _, _, _, timeframe, _),
    do: candle_failure(symbol.id, mode, :invalid_response, timeframe)

  defp candle_failure(id, mode, reason, timeframe) do
    mark_state(id, mode, %{status: "error", last_error: safe_reason(reason)}, timeframe)
    failure(reason)
  end

  def state(id, type, timeframe \\ "1h"),
    do: Repo.get_by(SyncState, market_symbol_id: id, timeframe: timeframe, sync_type: type)

  def mark_state(id, type, attrs, timeframe \\ "1h") do
    now = Collector.now()

    base = %{
      market_symbol_id: id,
      timeframe: timeframe,
      sync_type: to_string(type),
      status: "pending",
      inserted_at: now,
      updated_at: now
    }

    row = Map.merge(base, attrs)
    fields = [:updated_at | Map.keys(attrs)]

    Repo.insert_all(SyncState, [row],
      conflict_target: [:market_symbol_id, :timeframe, :sync_type],
      on_conflict: {:replace, fields}
    )

    :ok
  end

  defp failure(reason) do
    Collector.update(%{last_error: safe_reason(reason)})
    {:error, reason}
  end

  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason({:cooldown, seconds}), do: "cooldown_#{seconds}s"
  defp safe_reason({:upstream_http, status, _}), do: "upstream_http_#{status}"
end
