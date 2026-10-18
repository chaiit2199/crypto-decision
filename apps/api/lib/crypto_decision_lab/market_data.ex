defmodule CryptoDecisionLab.MarketData do
  @moduledoc "Public market-data context for API reads and internal synchronization commands."
  import Ecto.Query
  alias CryptoDecisionLab.Repo
  alias CryptoDecisionLab.Decisions

  alias CryptoDecisionLab.MarketData.{
    Asset,
    Symbol,
    LatestPrice,
    TickerStats,
    Candle,
    SyncState,
    Collector,
    Sync,
    SyncWorker,
    Integrity
  }

  @spec execute_sync(map()) :: {:ok, term()} | {:error, term()}
  def execute_sync(%{"kind" => "bootstrap"}) do
    with {:ok, _} <- Sync.metadata() do
      SyncWorker.enqueue(%{kind: "prices"})
      SyncWorker.enqueue(%{kind: "stats"})
      enqueue_symbols("backfill")
      {:ok, :queued}
    end
  end

  def execute_sync(%{"kind" => "metadata"}) do
    with {:ok, count} <- Sync.metadata() do
      enqueue_symbols("backfill")
      {:ok, count}
    end
  end

  def execute_sync(%{"kind" => "prices"}), do: Sync.prices()
  def execute_sync(%{"kind" => "stats"}), do: Sync.stats()
  def execute_sync(%{"kind" => "integrity"}), do: Integrity.check()
  def execute_sync(%{"kind" => "candles"}), do: enqueue_symbols("incremental")
  def execute_sync(%{"kind" => "backfill", "symbol_id" => id}), do: Sync.candles(id, :backfill)

  def execute_sync(%{"kind" => "incremental", "symbol_id" => id}),
    do: Sync.candles(id, :incremental)

  def execute_sync(%{"kind" => "repair", "symbol_id" => id, "from" => first, "to" => last}),
    do: Sync.candles(id, :repair, from: first, to: last)

  def execute_sync(_), do: {:error, :invalid_sync_command}

  defp enqueue_symbols(kind) do
    Enum.each(Sync.active_symbols(), &SyncWorker.enqueue(%{kind: kind, symbol_id: &1.id}))
    {:ok, :queued}
  end

  @spec list_markets(map()) :: {:ok, [map()], map()} | {:error, atom()}
  def list_markets(params) do
    with {:ok, page} <- integer(params, "page", 1, 1, 100_000),
         {:ok, size} <- integer(params, "page_size", 32, 1, 100) do
      assets =
        Repo.all(from a in Asset, order_by: a.id, limit: ^size, offset: ^((page - 1) * size))

      ids = Enum.map(assets, & &1.id)
      symbols = Repo.all(from s in Symbol, where: s.asset_id in ^ids, order_by: s.symbol)
      snapshots = snapshots(symbols)

      data =
        Enum.map(assets, fn asset ->
          markets =
            symbols |> Enum.filter(&(&1.asset_id == asset.id)) |> Enum.map(&market(&1, snapshots))

          Map.merge(fields(asset), %{
            markets: markets,
            availability: if(markets == [], do: "unavailable", else: "discovered")
          })
        end)

      {:ok, data, %{page: page, page_size: size, total: Repo.aggregate(Asset, :count)}}
    end
  end

  @spec get_market(String.t()) :: {:ok, map(), map()} | {:error, atom()}
  def get_market(symbol) do
    with {:ok, record} <- find_symbol(symbol) do
      {:ok, market(record, snapshots([record])), %{}}
    end
  end

  @spec candles(String.t(), map()) :: {:ok, [map()], map()} | {:error, atom()}
  def candles(symbol, params) do
    with {:ok, record} <- find_symbol(symbol),
         {:ok, range} <- candle_range(params) do
      rows =
        Repo.all(
          from c in Candle,
            where:
              c.market_symbol_id == ^record.id and c.timeframe == "1h" and
                c.open_time >= ^range.from and c.open_time < ^range.to,
            order_by: c.open_time,
            limit: ^(range.limit * range.hours)
        )

      rows = Enum.map(rows, &fields/1)

      with {:ok, values} <- Integrity.aggregate(rows, range.timeframe) do
        {:ok, values,
         %{
           timeframe: range.timeframe,
           from: range.from,
           to: range.to,
           limit: range.limit,
           count: length(values),
           availability: if(values == [], do: "missing", else: "available"),
           last_close_time: if(values == [], do: nil, else: List.last(values).close_time),
           freshness:
             freshness(
               if(values == [], do: nil, else: List.last(values).close_time),
               range.hours * 3600 + 60
             )
         }}
      end
    end
  end

  defp candle_range(params) do
    timeframe = Map.get(params, "timeframe", "1h")

    with hours when is_integer(hours) <- %{"1h" => 1, "4h" => 4, "1d" => 24}[timeframe],
         {:ok, limit} <- integer(params, "limit", 100, 1, 1000) do
      width = hours * 3600

      default_to =
        (div(DateTime.to_unix(Collector.now()) - 5, width) * width) |> DateTime.from_unix!()

      with {:ok, to} <- timestamp(params["to"], default_to),
           {:ok, from} <- timestamp(params["from"], DateTime.add(to, -limit * width)),
           true <- DateTime.compare(from, to) == :lt and DateTime.compare(to, default_to) != :gt,
           true <- DateTime.diff(to, from) <= 3 * 366 * 86_400,
           true <-
             Enum.all?(
               [from, to],
               &(rem(DateTime.to_unix(&1, :microsecond), width * 1_000_000) == 0)
             ) do
        {:ok, %{from: from, to: to, hours: hours, limit: limit, timeframe: timeframe}}
      else
        _ -> {:error, :invalid_time_range}
      end
    else
      _ -> {:error, :invalid_candle_query}
    end
  end

  defp timestamp(nil, default), do: {:ok, default}

  defp timestamp(value, _) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, 0} -> {:ok, timestamp}
      _ -> {:error, :invalid_timestamp}
    end
  end

  defp timestamp(_, _), do: {:error, :invalid_timestamp}

  defp integer(params, key, default, minimum, maximum) do
    case Map.get(params, key, Integer.to_string(default)) do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {number, ""} when number >= minimum and number <= maximum -> {:ok, number}
          _ -> {:error, :invalid_pagination}
        end

      _ ->
        {:error, :invalid_pagination}
    end
  end

  defp find_symbol(value) when is_binary(value) and byte_size(value) <= 30 do
    if Regex.match?(~r/^[A-Z0-9]+$/, value) do
      case Repo.get_by(Symbol, exchange: "binance", symbol: value) do
        nil -> {:error, :not_found}
        record -> {:ok, record}
      end
    else
      {:error, :invalid_symbol}
    end
  end

  defp find_symbol(_), do: {:error, :invalid_symbol}

  defp snapshots(symbols) do
    ids = Enum.map(symbols, & &1.id)
    prices = Repo.all(from p in LatestPrice, where: p.market_symbol_id in ^ids)
    stats = Repo.all(from t in TickerStats, where: t.market_symbol_id in ^ids)

    {Map.new(prices, &{&1.market_symbol_id, &1}), Map.new(stats, &{&1.market_symbol_id, &1}),
     Decisions.latest(ids)}
  end

  defp market(symbol, {prices, stats, analyses}) do
    price = prices[symbol.id]
    ticker = stats[symbol.id]

    Map.merge(fields(symbol), %{
      analysis_enabled: Decisions.enabled?(),
      analysis_interval_seconds: Decisions.interval_seconds(),
      analysis: analyses[symbol.id],
      latest_price: fields(price),
      ticker_stats: fields(ticker),
      price_freshness: freshness(price && price.fetched_at, 90),
      stats_freshness: freshness(ticker && ticker.data_at, 600)
    })
  end

  @spec analysis(String.t()) :: {:ok, map(), map()} | {:error, atom()}
  def analysis(symbol) do
    with {:ok, record} <- find_symbol(symbol) do
      {:ok,
       %{
         enabled: Decisions.enabled?(),
         interval_seconds: Decisions.interval_seconds(),
         analysis: Decisions.latest([record.id])[record.id]
       }, %{}}
    end
  end

  @doc "Bounded, fresh snapshots and closed candles for server-side research only."
  @spec analysis_inputs(integer(), DateTime.t()) :: {:ok, map()} | {:error, atom()}
  def analysis_inputs(id, now) do
    symbol =
      Repo.one(
        from s in Symbol,
          join: a in Asset,
          on: a.id == s.asset_id,
          where: s.id == ^id and s.enabled and a.enabled and s.trading_status == "TRADING",
          select: s
      )

    price = Repo.get(LatestPrice, id)
    stats = Repo.get(TickerStats, id)

    cond do
      is_nil(symbol) ->
        {:error, :symbol_unavailable}

      is_nil(price) or is_nil(stats) ->
        {:error, :missing_snapshots}

      DateTime.diff(now, price.fetched_at) not in 0..90 ->
        {:error, :stale_price}

      DateTime.diff(now, stats.data_at) not in 0..600 or
          DateTime.diff(now, stats.fetched_at) not in 0..600 ->
        {:error, :stale_stats}

      true ->
        cutoff = DateTime.add(now, -5)

        candles =
          Repo.all(
            from c in Candle,
              where: c.market_symbol_id == ^id and c.timeframe == "1h" and c.close_time < ^cutoff,
              order_by: [desc: c.open_time],
              limit: 300
          )
          |> Enum.reverse()

        {:ok,
         %{
           candles: candles,
           price_at: price.fetched_at,
           snapshot: %{
             "symbol" => symbol.symbol,
             "exchange" => "binance",
             "market" => "spot",
             "as_of" => DateTime.to_iso8601(now),
             "price" => Decimal.to_string(price.price, :normal),
             "price_at" => DateTime.to_iso8601(price.fetched_at),
             "stats_at" => DateTime.to_iso8601(stats.data_at),
             "change_24h_percent" => Decimal.to_string(stats.price_change_percent, :normal),
             "high_24h" => Decimal.to_string(stats.high_price, :normal),
             "low_24h" => Decimal.to_string(stats.low_price, :normal),
             "quote_volume_24h" => Decimal.to_string(stats.quote_volume, :normal)
           }
         }}
    end
  end

  def freshness(nil, _), do: %{status: "missing", age_seconds: nil}

  def freshness(timestamp, threshold) do
    age = DateTime.diff(Collector.now(), timestamp)

    %{
      status: if(age in 0..threshold, do: "fresh", else: "stale"),
      age_seconds: max(age, 0),
      timestamp: timestamp
    }
  end

  def status do
    states =
      Repo.all(from s in SyncState, order_by: [s.market_symbol_id, s.sync_type])
      |> Enum.map(&fields/1)

    jobs =
      Repo.all(
        from j in Oban.Job,
          where: j.worker == "CryptoDecisionLab.MarketData.SyncWorker",
          group_by: j.state,
          select: {j.state, count(j.id)}
      )
      |> Map.new()

    {:ok,
     %{
       collector: fields(Collector.state()),
       synchronization: states,
       jobs: jobs,
       enabled: Application.get_env(:crypto_decision_lab, :sync_enabled, false),
       configured_assets: Repo.aggregate(Asset, :count),
       active_symbols: length(Sync.active_symbols())
     }, %{}}
  end

  def health do
    case Repo.query("SELECT 1", [], timeout: 2000) do
      {:ok, _} -> {:ok, %{status: "ok", database: "up"}, %{}}
      {:error, _} -> {:error, :database_unavailable}
    end
  rescue
    _ in [DBConnection.ConnectionError] -> {:error, :database_unavailable}
  catch
    :exit, _ -> {:error, :database_unavailable}
  end

  defp fields(nil), do: nil
  defp fields(%module{} = record), do: Map.take(record, module.__schema__(:fields))
end
