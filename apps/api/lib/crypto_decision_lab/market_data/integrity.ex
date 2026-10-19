defmodule CryptoDecisionLab.MarketData.Integrity do
  @moduledoc "Detect gaps within known listing history and aggregate only complete UTC windows."
  import Ecto.Query
  alias CryptoDecisionLab.Repo
  alias CryptoDecisionLab.MarketData.{Candle, Collector, Sync, SyncWorker}
  @hour 3600
  @volumes [:base_volume, :quote_volume, :taker_buy_base_volume, :taker_buy_quote_volume]

  def gaps(symbol_id, until_time \\ Collector.now()) do
    first =
      Repo.one(
        from c in Candle,
          where: c.market_symbol_id == ^symbol_id and c.timeframe == "1h",
          select: min(c.open_time)
      )

    if first do
      last_open = div(DateTime.to_unix(until_time) - 5, @hour) * @hour - @hour

      result =
        Repo.query!(
          """
          SELECT t FROM generate_series($1::timestamptz, to_timestamp($2), interval '1 hour') AS t
          WHERE NOT EXISTS (SELECT 1 FROM market_candles c WHERE c.market_symbol_id = $3 AND c.timeframe = '1h' AND c.open_time = t AT TIME ZONE 'UTC')
          ORDER BY t
          """,
          [first, last_open, symbol_id]
        )

      Enum.map(result.rows, fn [timestamp] -> timestamp end)
    else
      []
    end
  end

  def check do
    Collector.run(fn ->
      counts =
        for symbol <- Sync.active_symbols() do
          missing = gaps(symbol.id)

          has_history =
            Repo.exists?(
              from c in Candle, where: c.market_symbol_id == ^symbol.id and c.timeframe == "1h"
            )

          status =
            cond do
              not has_history -> "no_data"
              missing == [] -> "complete"
              true -> "gaps"
            end

          Sync.mark_state(symbol.id, :integrity, %{
            status: status,
            missing_count: if(has_history, do: length(missing), else: nil),
            last_attempt_at: Collector.now(),
            last_success_at: Collector.now()
          })

          missing
          |> Enum.chunk_by(&div(DateTime.to_unix(&1), 1000 * @hour))
          |> Enum.each(fn chunk ->
            SyncWorker.enqueue(%{
              kind: "repair",
              symbol_id: symbol.id,
              from: DateTime.to_unix(hd(chunk), :millisecond),
              to: DateTime.to_unix(List.last(chunk), :millisecond) + 3_599_999
            })
          end)

          length(missing)
        end

      {:ok, Enum.sum(counts)}
    end)
  end

  @spec aggregate([map()], String.t()) :: {:ok, [map()]} | {:error, atom()}
  def aggregate(candles, timeframe) when timeframe in ["5m", "15m", "1h"], do: {:ok, candles}

  def aggregate(candles, timeframe) when timeframe in ["4h", "1d"] do
    contiguous =
      candles
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.all?(fn [left, right] ->
        DateTime.diff(right.open_time, left.open_time) == @hour
      end)

    if contiguous do
      Decimal.Context.with(%{Decimal.Context.get() | precision: 100}, fn ->
        aggregate_complete(candles, timeframe)
      end)
    else
      {:error, :incomplete_aggregation}
    end
  end

  defp aggregate_complete(candles, timeframe) do
    hours = if timeframe == "4h", do: 4, else: 24
    width = hours * @hour
    groups = Enum.chunk_by(candles, &div(DateTime.to_unix(&1.open_time), width))

    Enum.reduce_while(groups, {:ok, []}, fn group, {:ok, values} ->
      times = Enum.map(group, &DateTime.to_unix(&1.open_time))
      first = hd(times)
      expected = for n <- 0..(hours - 1), do: first + n * @hour

      if rem(first, width) == 0 and times == expected do
        base = Map.take(hd(group), [:market_symbol_id, :open_time, :open])

        aggregated =
          Map.merge(base, %{
            timeframe: timeframe,
            close_time: List.last(group).close_time,
            close: List.last(group).close,
            high: Enum.reduce(group, hd(group).high, &Decimal.max(&1.high, &2)),
            low: Enum.reduce(group, hd(group).low, &Decimal.min(&1.low, &2)),
            trade_count: sum_known(Enum.map(group, & &1.trade_count), &Enum.sum/1)
          })

        aggregated =
          Enum.reduce(@volumes, aggregated, fn field, result ->
            Map.put(
              result,
              field,
              sum_known(Enum.map(group, &Map.fetch!(&1, field)), fn values ->
                Enum.reduce(values, Decimal.new(0), &Decimal.add/2)
              end)
            )
          end)

        {:cont, {:ok, [aggregated | values]}}
      else
        {:halt, {:error, :incomplete_aggregation}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp sum_known(values, sum), do: if(Enum.any?(values, &is_nil/1), do: nil, else: sum.(values))
end
