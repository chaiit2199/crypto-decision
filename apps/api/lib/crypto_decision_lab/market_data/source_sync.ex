defmodule CryptoDecisionLab.MarketData.SourceSync do
  @moduledoc "Coinbase USD and gold snapshots, isolated from the Binance collector."
  import Ecto.Query
  alias CryptoDecisionLab.Repo

  alias CryptoDecisionLab.MarketData.{
    Asset,
    Symbol,
    LatestPrice,
    TickerStats,
    Candle,
    Collector,
    CollectorState,
    SourceHTTP,
    SourceParser,
    SourceWorker,
    Sync,
    Universe
  }

  @sources ~w(coinbase gold_api)

  @spec enqueue() :: {:ok, non_neg_integer()}
  def enqueue do
    Enum.each(@sources, fn source ->
      %{source: source} |> SourceWorker.new() |> Oban.insert!()
    end)

    {:ok, length(@sources)}
  end

  @spec metadata(String.t()) :: {:ok, term()} | {:error, term()}
  def metadata(source, opts \\ []) when source in @sources do
    result =
      locked(source, fn ->
        state = Repo.get!(CollectorState, source)

        if (not Keyword.get(opts, :force, false) and state.metadata_at) &&
             DateTime.diff(Collector.now(), state.metadata_at) < 86_400 do
          {:ok, :cached}
        else
          discover(source)
        end
      end)

    if match?({:ok, _}, result) do
      for symbol <- active_symbols(source) do
        %{source: source, symbol_id: symbol.id} |> SourceWorker.new() |> Oban.insert!()
      end
    end

    result
  end

  @spec active_symbols(String.t()) :: [Symbol.t()]
  def active_symbols(source) do
    Repo.all(
      from s in Symbol,
        join: a in Asset,
        on: a.id == s.asset_id,
        where:
          s.exchange == ^source and s.enabled and a.enabled and s.trading_status == "TRADING",
        order_by: s.id
    )
  end

  defp discover("coinbase") do
    Universe.seed()

    with {:ok, products, _} <- SourceHTTP.get("coinbase", "/products"),
         true <- is_list(products) and products != [] and Enum.all?(products, &valid_product?/1) do
      assets =
        Map.new(
          Repo.all(from(a in Asset, where: a.category != "precious_metals")),
          &{&1.symbol, &1.id}
        )

      now = Collector.now()

      Repo.update_all(from(s in Symbol, where: s.exchange == "coinbase"),
        set: [trading_status: "UNAVAILABLE", updated_at: now]
      )

      for product <- products,
          product["quote_currency"] == "USD",
          Map.has_key?(assets, product["base_currency"]) do
        base = product["base_currency"]

        status =
          if product["status"] == "online" and product["trading_disabled"] != true and
               product["cancel_only"] != true,
             do: "TRADING",
             else: "UNAVAILABLE"

        put_symbol(assets[base], "coinbase", base, "USD", product["id"], status)
      end

      update_state("coinbase", metadata_at: now)
      {:ok, :discovered}
    else
      false -> {:error, :invalid_metadata}
      error -> error
    end
  end

  defp discover("gold_api") do
    with {:ok, symbols, _} <- SourceHTTP.get("gold_api", "/symbols"),
         true <- is_list(symbols) and Enum.any?(symbols, &(is_map(&1) and &1["symbol"] == "XAU")) do
      now = Collector.now()

      Repo.insert_all(
        Asset,
        [
          %{
            symbol: "XAU",
            name: "Vàng thế giới",
            category: "precious_metals",
            enabled: true,
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: {:replace, [:name, :category, :enabled, :updated_at]},
        conflict_target: [:symbol]
      )

      asset = Repo.get_by!(Asset, symbol: "XAU")
      put_symbol(asset.id, "gold_api", "XAU", "USD", "XAU", "TRADING")
      update_state("gold_api", metadata_at: now)
      {:ok, :discovered}
    else
      false -> {:error, :invalid_metadata}
      error -> error
    end
  end

  defp valid_product?(p) when is_map(p) do
    Enum.all?(~w(id base_currency quote_currency status), &is_binary(p[&1])) and
      Regex.match?(~r/^[A-Z0-9-]{1,40}$/, p["id"])
  end

  defp valid_product?(_), do: false

  defp put_symbol(asset_id, source, base, quote, provider_symbol, status) do
    now = Collector.now()

    Repo.insert_all(
      Symbol,
      [
        %{
          asset_id: asset_id,
          exchange: source,
          symbol: base <> quote,
          base_asset: base,
          quote_asset: quote,
          provider_symbol: provider_symbol,
          trading_status: status,
          enabled: true,
          inserted_at: now,
          updated_at: now
        }
      ],
      conflict_target: [:exchange, :symbol],
      on_conflict: {:replace, [:provider_symbol, :trading_status, :updated_at]}
    )
  end

  @spec sync(String.t(), integer()) :: {:ok, term()} | {:error, term()}
  def sync(source, id) when source in @sources do
    locked(source, fn ->
      case Enum.find(active_symbols(source), &(&1.id == id)) do
        nil ->
          {:ok, :unavailable}

        symbol ->
          state = Sync.state(id, "snapshot")

          interval =
            div(Application.fetch_env!(:crypto_decision_lab, :price_poll_interval_ms), 1000)

          if state && state.last_attempt_at &&
               DateTime.diff(Collector.now(), state.last_attempt_at) < interval do
            {:ok, :not_due}
          else
            Sync.mark_state(id, :snapshot, %{last_attempt_at: Collector.now(), status: "running"})
            result = fetch_symbol(symbol)

            case result do
              {:ok, _} ->
                Sync.mark_state(id, :snapshot, %{
                  last_success_at: Collector.now(),
                  status: "complete",
                  last_error: nil
                })

                update_state(source, prices_at: Collector.now())

              {:error, reason} ->
                Sync.mark_state(id, :snapshot, %{status: "error", last_error: inspect(reason)})
            end

            result
          end
      end
    end)
  end

  defp fetch_symbol(%Symbol{exchange: "gold_api"} = symbol) do
    with {:ok, body, _} <- SourceHTTP.get("gold_api", "/price/XAU/USD"),
         {:ok, price} <- SourceParser.price(body, "gold_api", Collector.now()) do
      save_price(symbol.id, price)

      case fetch_gold_candles(symbol) do
        {:ok, count} when is_integer(count) ->
          refresh_gold_stats(symbol.id, price.price, Collector.now())
          {:ok, count}

        {:ok, other} ->
          refresh_gold_stats(symbol.id, price.price, Collector.now())
          {:ok, other}

        error ->
          error
      end
    end
  end

  defp fetch_symbol(symbol) do
    path = "/products/" <> symbol.provider_symbol

    with {:ok, body, _} <- SourceHTTP.get("coinbase", path <> "/ticker"),
         {:ok, price} <- SourceParser.price(body, "coinbase", Collector.now()) do
      save_price(symbol.id, price)

      with {:ok, body, data_at} <- SourceHTTP.get("coinbase", path <> "/stats"),
           {:ok, stats} <- SourceParser.stats(body, data_at, Collector.now()) do
        Repo.insert_all(TickerStats, [Map.put(stats, :market_symbol_id, symbol.id)],
          conflict_target: [:market_symbol_id],
          on_conflict:
            from(t in TickerStats,
              where: fragment("EXCLUDED.data_at >= ?", t.data_at),
              update: [
                set: [
                  price_change: fragment("EXCLUDED.price_change"),
                  price_change_percent: fragment("EXCLUDED.price_change_percent"),
                  high_price: fragment("EXCLUDED.high_price"),
                  low_price: fragment("EXCLUDED.low_price"),
                  base_volume: fragment("EXCLUDED.base_volume"),
                  data_at: fragment("EXCLUDED.data_at"),
                  fetched_at: fragment("EXCLUDED.fetched_at"),
                  updated_at: fragment("EXCLUDED.updated_at")
                ]
              ]
            )
        )

        fetch_candles(symbol)
      end
    end
  end

  defp save_price(id, price) do
    Repo.insert_all(LatestPrice, [Map.put(price, :market_symbol_id, id)],
      conflict_target: [:market_symbol_id],
      on_conflict:
        from(p in LatestPrice,
          where: fragment("EXCLUDED.data_at >= COALESCE(?, ?)", p.data_at, p.fetched_at),
          update: [
            set: [
              price: fragment("EXCLUDED.price"),
              data_at: fragment("EXCLUDED.data_at"),
              fetched_at: fragment("EXCLUDED.fetched_at"),
              updated_at: fragment("EXCLUDED.updated_at")
            ]
          ]
        )
    )
  end

  defp fetch_candles(symbol) do
    now = Collector.now()

    last =
      Repo.one(
        from c in Candle, where: c.market_symbol_id == ^symbol.id, select: max(c.open_time)
      )

    boundary = div(DateTime.to_unix(now) - 5, 3600) * 3600
    state = Sync.state(symbol.id, "source_candles")

    cond do
      state && state.status in ["complete", "gaps"] && state.last_attempt_at &&
          div(DateTime.to_unix(state.last_attempt_at) - 5, 3600) == div(boundary, 3600) ->
        {:ok, :candles_checked}

      last && DateTime.to_unix(last) >= boundary - 3600 ->
        {:ok, :current}

      true ->
        Sync.mark_state(symbol.id, :source_candles, %{last_attempt_at: now, status: "running"})
        # One bounded window. Missing market hours are not synthesized.
        first = boundary - 300 * 3600

        params = [
          granularity: 3600,
          start: DateTime.to_iso8601(DateTime.from_unix!(first)),
          end: DateTime.to_iso8601(DateTime.from_unix!(boundary - 1))
        ]

        with {:ok, body, server_time} <-
               SourceHTTP.get(
                 "coinbase",
                 "/products/" <> symbol.provider_symbol <> "/candles",
                 params
               ),
             cutoff = Enum.min_by([now, server_time], &DateTime.to_unix(&1, :microsecond)),
             {:ok, candles} <- SourceParser.candles(body, cutoff) do
          persist_source_candles(symbol.id, candles, first, boundary, now, 300)
        else
          {:error, reason} = error ->
            Sync.mark_state(symbol.id, :source_candles, %{
              status: "error",
              last_error: inspect(reason)
            })

            error
        end
    end
  end

  # Free daily history via XAUS; refresh at most every 6 hours (upstream caches ~6h).
  defp fetch_gold_candles(symbol) do
    now = Collector.now()
    state = Sync.state(symbol.id, "source_candles")

    last =
      Repo.one(
        from c in Candle,
          where: c.market_symbol_id == ^symbol.id and c.timeframe == "1d",
          select: max(c.open_time)
      )

    today = DateTime.from_unix!(div(DateTime.to_unix(now), 86_400) * 86_400)

    cond do
      state && state.status in ["complete", "gaps"] && state.last_attempt_at &&
          DateTime.diff(now, state.last_attempt_at) < 6 * 3600 ->
        {:ok, :candles_checked}

      last && DateTime.compare(last, DateTime.add(today, -86_400)) != :lt ->
        {:ok, :current}

      true ->
        Sync.mark_state(symbol.id, :source_candles, %{last_attempt_at: now, status: "running"})

        with {:ok, body, _} <- SourceHTTP.get("xaus", "/api/v1/history"),
             {:ok, candles} <- SourceParser.gold_daily_candles(body, now) do
          first =
            case candles do
              [c | _] -> DateTime.to_unix(c.open_time)
              [] -> 0
            end

          boundary = DateTime.to_unix(today)
          persist_source_candles(symbol.id, candles, first, boundary, now, 300)
        else
          {:error, reason} = error ->
            Sync.mark_state(symbol.id, :source_candles, %{
              status: "error",
              last_error: inspect(reason)
            })

            error
        end
    end
  end

  # Spot gold has no exchange 24h ticker; derive research stats from recent daily candles.
  defp refresh_gold_stats(symbol_id, last_price, now) do
    from_time = DateTime.add(now, -7 * 86_400)

    candles =
      Repo.all(
        from c in Candle,
          where:
            c.market_symbol_id == ^symbol_id and c.timeframe == "1d" and
              c.open_time >= ^from_time,
          order_by: [asc: c.open_time]
      )

    case candles do
      [] ->
        :ok

      [first | _] = rows ->
        high = Enum.reduce(rows, first.high, &Decimal.max(&1.high, &2))
        low = Enum.reduce(rows, first.low, &Decimal.min(&1.low, &2))
        open = first.open
        change = Decimal.sub(last_price, open)

        stats = %{
          market_symbol_id: symbol_id,
          price_change: change,
          price_change_percent: Decimal.mult(Decimal.div(change, open), 100),
          high_price: high,
          low_price: low,
          base_volume: Decimal.new(0),
          quote_volume: nil,
          trade_count: nil,
          data_at: now,
          fetched_at: now,
          updated_at: now
        }

        Repo.insert_all(TickerStats, [stats],
          conflict_target: [:market_symbol_id],
          on_conflict:
            from(t in TickerStats,
              where: fragment("EXCLUDED.data_at >= ?", t.data_at),
              update: [
                set: [
                  price_change: fragment("EXCLUDED.price_change"),
                  price_change_percent: fragment("EXCLUDED.price_change_percent"),
                  high_price: fragment("EXCLUDED.high_price"),
                  low_price: fragment("EXCLUDED.low_price"),
                  base_volume: fragment("EXCLUDED.base_volume"),
                  data_at: fragment("EXCLUDED.data_at"),
                  fetched_at: fragment("EXCLUDED.fetched_at"),
                  updated_at: fragment("EXCLUDED.updated_at")
                ]
              ]
            )
        )

        :ok
    end
  end

  defp persist_source_candles(symbol_id, candles, first, boundary, now, expected) do
    rows =
      candles
      |> Enum.filter(
        &(DateTime.to_unix(&1.open_time) >= first and DateTime.to_unix(&1.open_time) < boundary)
      )
      |> Enum.uniq_by(& &1.open_time)
      |> Enum.map(&Map.merge(&1, %{market_symbol_id: symbol_id, inserted_at: now}))

    Repo.insert_all(Candle, rows,
      on_conflict: :nothing,
      conflict_target: [:market_symbol_id, :timeframe, :open_time]
    )

    Sync.mark_state(symbol_id, :source_candles, %{
      last_success_at: now,
      status: if(length(rows) >= expected, do: "complete", else: "gaps"),
      missing_count: max(expected - length(rows), 0),
      last_error: nil
    })

    {:ok, length(rows)}
  end

  defp locked(source, fun) do
    key = if source == "coinbase", do: 1, else: 2

    case Repo.transaction(
           fn ->
             case Repo.query!("SELECT pg_try_advisory_xact_lock(7413202, $1)", [key]).rows do
               [[true]] ->
                 Repo.insert_all(CollectorState, [%{key: source, updated_at: Collector.now()}],
                   on_conflict: :nothing
                 )

                 state = Repo.get!(CollectorState, source)

                 if state.blocked_until &&
                      DateTime.compare(state.blocked_until, Collector.now()) == :gt do
                   {:error, :source_cooldown}
                 else
                   result = fun.()

                   case result do
                     {:error, {:rate_limited, seconds}} ->
                       update_state(source,
                         blocked_until: DateTime.add(Collector.now(), seconds),
                         last_error: "rate_limited"
                       )

                     {:error, reason} ->
                       update_state(source,
                         last_error: inspect(reason),
                         blocked_until: DateTime.add(Collector.now(), 120)
                       )

                     _ ->
                       update_state(source, last_error: nil)
                   end

                   result
                 end

               _ ->
                 {:error, :source_busy}
             end
           end,
           timeout: 60_000
         ) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_state(source, attrs) do
    Repo.update_all(from(s in CollectorState, where: s.key == ^source),
      set: Keyword.put(attrs, :updated_at, Collector.now())
    )
  end
end
