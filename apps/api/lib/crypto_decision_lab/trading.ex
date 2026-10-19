defmodule CryptoDecisionLab.Trading do
  @moduledoc "Stored-data Spot research workbench. Reads never call a provider or authorize execution."
  import Ecto.Query
  alias CryptoDecisionLab.{Repo, MarketData, TechnicalAnalysis}

  alias CryptoDecisionLab.MarketData.{
    Asset,
    Symbol,
    Candle,
    Collector,
    Integrity,
    Liquidity,
    LiquiditySnapshot,
    SnapshotTime
  }

  alias CryptoDecisionLab.Trading.{Plan, Assessment}
  alias CryptoDecisionLab.TradingKnowledge.{StrategyVersion, Matcher, Snapshot}

  @styles %{
    "scalping" => %{"trend" => "1h", "setup" => "15m", "entry" => "5m"},
    "intraday" => %{"trend" => "4h", "setup" => "15m", "entry" => "5m"},
    "swing" => %{"trend" => "1d", "setup" => "4h", "entry" => "1h"}
  }
  @widths %{"5m" => 300, "15m" => 900, "1h" => 3600, "4h" => 14_400, "1d" => 86_400}

  @spec workbench(binary(), map()) :: {:ok, map(), map()} | {:error, atom()}
  def workbench(symbol, params) do
    with {:ok, market, _} <- MarketData.get_market(symbol, params),
         {:ok, frames} <- style(params) do
      {:ok, report(market, Map.get(params, "style", "intraday"), frames, Collector.now()), %{}}
    end
  end

  @spec plan(binary(), map()) :: {:ok, map(), map()} | {:error, atom()}
  def plan(symbol, params) do
    with {:ok, market, _} <- MarketData.get_market(symbol, params),
         true <- market.exchange in ["binance", "coinbase"],
         {:ok, plan} <- Plan.calculate(params) do
      {:ok,
       Map.merge(plan, %{
         "symbol" => market.symbol,
         "exchange" => market.exchange,
         "quote_asset" => market.quote_asset,
         "market" => "spot",
         "mode" => "hypothetical"
       }), %{}}
    else
      false -> {:error, :unsupported_market}
      error -> error
    end
  end

  @spec opportunities(map()) :: {:ok, [map()], map()} | {:error, atom()}
  def opportunities(params) do
    with {:ok, frames} <- style(params),
         exchange when exchange in ["binance", "coinbase"] <-
           Map.get(params, "exchange", "binance") do
      now = Collector.now()

      symbols =
        Repo.all(
          from s in Symbol,
            join: a in Asset,
            on: a.id == s.asset_id,
            where:
              s.exchange == ^exchange and s.enabled and a.enabled and
                s.trading_status == "TRADING",
            order_by: s.id,
            limit: 100
        )

      rows =
        Enum.map(symbols, fn symbol ->
          {:ok, market, _} = MarketData.get_market(symbol.symbol, %{"exchange" => exchange})
          report(market, Map.get(params, "style", "intraday"), frames, now)
        end)

      # Decimal sorting preserves ratios without float conversions.
      rows =
        Enum.sort(rows, fn a, b ->
          cond do
            a["technical_candidate"] != b["technical_candidate"] ->
              a["technical_candidate"]

            true ->
              Decimal.compare(
                a["plan"]["risk_reward_ratio"] || "-1",
                b["plan"]["risk_reward_ratio"] || "-1"
              ) != :lt
          end
        end)

      {:ok, rows, %{count: length(rows), execution_allowed: false}}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_exchange}
    end
  end

  defp valid_until(market, liquidity, now) do
    price = market.latest_price
    price_at = if price, do: price.data_at || price.fetched_at, else: now

    book_at =
      case DateTime.from_iso8601(liquidity["fetched_at"] || "") do
        {:ok, at, 0} -> at
        _ -> now
      end

    [price_at, book_at, now]
    |> Enum.min_by(&DateTime.to_unix(&1, :microsecond))
    |> DateTime.add(90)
    |> DateTime.to_iso8601()
  end

  @doc "Recent stored simulation summaries, never treated as validation of the current setup."
  @spec simulations(integer()) :: [map()]
  def simulations(symbol_id) do
    Repo.all(
      from s in CryptoDecisionLab.Trading.Simulation,
        where: s.market_symbol_id == ^symbol_id,
        order_by: [desc: s.id],
        limit: 20
    )
    |> Enum.map(fn row ->
      %{
        "id" => row.id,
        "kind" => row.kind,
        "created_at" => DateTime.to_iso8601(row.inserted_at),
        "event" => row.report["event"],
        "trade_count" => row.report["trade_count"],
        "net_return_percent" => row.report["net_return_percent"],
        "net_pnl" => row.report["net_pnl"],
        "validation" => "UNVALIDATED"
      }
    end)
  end

  @doc "Manual bounded replay from stored candles. No public mutation route or inference calls."
  @spec replay(binary(), map(), map()) :: {:ok, struct()} | {:error, term()}
  def replay(symbol, params, config) do
    with {:ok, market, _} <- MarketData.get_market(symbol, params),
         timeframe when timeframe in ["5m", "15m", "1h"] <- Map.get(params, "timeframe", "5m"),
         {:ok, start_at, 0} <- DateTime.from_iso8601(config["test_from"] || ""),
         {:ok, end_at, 0} <- DateTime.from_iso8601(config["test_to"] || "") do
      from = DateTime.add(start_at, -302 * @widths[timeframe])

      rows =
        Repo.all(
          from c in Candle,
            where:
              c.market_symbol_id == ^market.id and c.timeframe == ^timeframe and
                c.open_time >= ^from and c.close_time < ^end_at,
            order_by: c.open_time,
            limit: 10_001
        )

      config =
        Map.merge(config, %{
          "symbol" => market.symbol,
          "exchange" => market.exchange,
          "timeframe" => timeframe,
          "quote_asset" => market.quote_asset
        })

      CryptoDecisionLab.Trading.Replay.save(market.id, rows, config)
    else
      _ -> {:error, :invalid_replay}
    end
  end

  defp style(params) do
    case @styles[Map.get(params, "style", "intraday")] do
      nil -> {:error, :invalid_style}
      frames -> {:ok, frames}
    end
  end

  defp report(market, style, frames, now) do
    market = Map.update!(market, :enabled, &(&1 and Repo.get!(Asset, market.asset_id).enabled))

    series =
      Map.new(Enum.uniq(Map.values(frames)), fn frame -> {frame, frame(market.id, frame, now)} end)

    liquidity = liquidity(market, now)
    assessment = Assessment.evaluate(market, frames, series, liquidity, now)

    Map.merge(assessment, %{
      "symbol" => market.symbol,
      "exchange" => market.exchange,
      "quote_asset" => market.quote_asset,
      "market" => if(market.exchange == "gold_api", do: "reference", else: "spot"),
      "style" => style,
      "timeframes" => frames,
      "as_of" => DateTime.to_iso8601(now),
      "configuration_version" => "spot-workbench-v1",
      "valid_until" => valid_until(market, liquidity, now),
      "frames" => series,
      "liquidity" => Map.drop(liquidity, ["parsed"]),
      "knowledge_matches" => knowledge_matches(market, now),
      "simulations" => simulations(market.id),
      "expected_move" => nil,
      "profit_probability" => nil,
      "strategy_validation" => "UNVALIDATED",
      "execution_allowed" => false
    })
  end

  @doc "Exactly 300 complete closed windows; rejects missing sources and stale history."
  @spec frame(integer(), binary(), DateTime.t()) :: map()
  def frame(id, timeframe, now) do
    width = Map.fetch!(@widths, timeframe)
    cutoff = div(DateTime.to_unix(now) - 5, width) * width
    from = DateTime.from_unix!(cutoff - 300 * width)
    to = DateTime.from_unix!(cutoff)
    source = if timeframe in ["5m", "15m"], do: timeframe, else: "1h"

    rows =
      Repo.all(
        from c in Candle,
          where:
            c.market_symbol_id == ^id and c.timeframe == ^source and c.open_time >= ^from and
              c.open_time < ^to,
          order_by: c.open_time,
          limit: ^(300 * max(div(width, 3600), 1))
      )
      |> Enum.map(&Map.from_struct/1)

    with {:ok, candles} <- Integrity.aggregate(rows, timeframe),
         {:ok, features} <- TechnicalAnalysis.features(candles, now, timeframe) do
      last = List.last(candles)
      previous = Enum.at(candles, -2)
      {:ok, previous_features} = previous_levels(candles)

      %{
        "status" => "ready",
        "reason" => nil,
        "features" => features,
        "last_low" => Decimal.to_string(last.low, :normal),
        "previous_close" => Decimal.to_string(previous.close, :normal),
        "previous_resistance" => previous_features
      }
    else
      {:error, reason} ->
        %{"status" => "no_data", "reason" => to_string(reason), "features" => %{}}
    end
  end

  defp previous_levels(candles) do
    value = candles |> Enum.slice(-22, 20) |> Enum.map(& &1.high) |> Enum.reduce(&Decimal.max/2)
    {:ok, Decimal.to_string(value, :normal)}
  end

  defp liquidity(%{exchange: exchange}, _) when exchange != "binance",
    do: %{"status" => "unsupported", "reason" => "LIQUIDITY_SOURCE_UNSUPPORTED"}

  defp liquidity(market, now) do
    case Repo.get(LiquiditySnapshot, market.id) do
      nil ->
        %{"status" => "missing", "reason" => "LIQUIDITY_MISSING"}

      row ->
        with true <-
               SnapshotTime.fresh?(row.fetched_at, now, 90) and
                 SnapshotTime.fresh?(row.data_at, now, 90),
             {:ok, book} <- Liquidity.parse(row.book) do
          %{
            "status" => "fresh",
            "reason" => nil,
            "fetched_at" => DateTime.to_iso8601(row.fetched_at),
            "data_at" => DateTime.to_iso8601(row.data_at),
            "parsed" => book,
            "bid" => Decimal.to_string(book.bid, :normal),
            "ask" => Decimal.to_string(book.ask, :normal),
            "spread_percent" => Decimal.to_string(book.spread_percent, :normal),
            "bid_depth" => Decimal.to_string(book.bid_depth, :normal),
            "ask_depth" => Decimal.to_string(book.ask_depth, :normal),
            "imbalance" => Decimal.to_string(book.imbalance, :normal)
          }
        else
          _ ->
            %{
              "status" => "stale",
              "reason" => "LIQUIDITY_STALE",
              "fetched_at" => DateTime.to_iso8601(row.fetched_at)
            }
        end
    end
  end

  defp knowledge_matches(%{exchange: exchange}, _) when exchange != "binance", do: []

  defp knowledge_matches(market, now) do
    rows =
      Repo.all(
        from c in Candle,
          where: c.market_symbol_id == ^market.id and c.timeframe == "1h",
          order_by: [desc: c.open_time],
          limit: 300
      )
      |> Enum.reverse()

    # This is a current observation, never an assertion of historical availability.
    records = Enum.map(rows, &%{candle: &1, available_at: now})

    with {:ok, snapshot} <- Snapshot.from_candles(records, market.symbol, now) do
      Repo.all(
        from v in StrategyVersion,
          distinct: v.strategy_id,
          order_by: [v.strategy_id, desc: v.version],
          limit: 50
      )
      |> Enum.flat_map(fn version ->
        case Matcher.match(version.document, snapshot, now) do
          {:ok, result} ->
            [
              Map.take(
                result,
                ~w(strategy_id version matched data_valid validation_status eligible)
              )
            ]

          _ ->
            []
        end
      end)
    else
      _ -> []
    end
  end
end
