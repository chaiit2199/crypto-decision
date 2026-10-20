defmodule CryptoDecisionLab.MarketData.SourceParser do
  @moduledoc "Normalize documented Coinbase and Gold API payloads without inventing missing volumes."
  alias Decimal, as: D
  alias CryptoDecisionLab.MarketData.{Parser, SnapshotTime}

  def decimal(%D{coef: coef} = value) when is_integer(coef), do: {:ok, value}
  def decimal(value) when is_integer(value), do: {:ok, D.new(value)}
  def decimal(value), do: Parser.decimal(value)

  def price(%{"price" => value} = row, source, now) do
    timestamp = if source == "gold_api", do: row["updatedAt"], else: row["time"]

    with true <- source != "gold_api" or (row["symbol"] == "XAU" and row["currency"] == "USD"),
         {:ok, price} <- decimal(value),
         true <- D.positive?(price),
         {:ok, data_at, 0} <- parse_time(timestamp),
         false <- SnapshotTime.future?(data_at, now) do
      {:ok,
       %{
         price: price,
         data_at: DateTime.from_unix!(DateTime.to_unix(data_at, :microsecond), :microsecond),
         fetched_at: now,
         updated_at: now
       }}
    else
      _ -> {:error, :invalid_price}
    end
  end

  def price(_, _, _), do: {:error, :invalid_price}

  def stats(row, data_at, now) when is_map(row) do
    with {:ok, values} <-
           decimals(row,
             open: "open",
             close: "last",
             high_price: "high",
             low_price: "low",
             base_volume: "volume"
           ),
         true <-
           D.positive?(values.open) and D.positive?(values.close) and
             D.positive?(values.low_price),
         true <-
           D.compare(values.high_price, values.low_price) != :lt and
             D.compare(values.base_volume, 0) != :lt do
      change = D.sub(values.close, values.open)

      {:ok,
       values
       |> Map.drop([:open, :close])
       |> Map.merge(%{
         price_change: change,
         price_change_percent: D.mult(D.div(change, values.open), 100),
         quote_volume: nil,
         trade_count: nil,
         data_at: data_at,
         fetched_at: now,
         updated_at: now
       })}
    else
      _ -> {:error, :invalid_stats}
    end
  end

  def stats(_, _, _), do: {:error, :invalid_stats}

  def candles(rows, now) when is_list(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case candle(row, now) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:skip, :open} -> {:cont, {:ok, acc}}
        error -> {:halt, error}
      end
    end)
  end

  def candles(_, _), do: {:error, :invalid_candles}

  @doc """
  Build closed daily research candles from XAUS `/api/v1/history` points.

  Points provide high/low/close; open is the previous day's close (first day uses
  close). Volume stays nil. Only days fully closed before `now` are kept.
  """
  def gold_daily_candles(%{"points" => points}, now) when is_list(points) do
    points
    |> Enum.reduce_while({:ok, [], nil}, fn row, {:ok, acc, prev_close} ->
      case daily_point(row, prev_close, now) do
        {:ok, candle, close} -> {:cont, {:ok, [candle | acc], close}}
        {:skip, close} -> {:cont, {:ok, acc, close || prev_close}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, candles, _} -> {:ok, Enum.reverse(candles)}
      error -> error
    end
  end

  def gold_daily_candles(_, _), do: {:error, :invalid_gold_history}

  defp daily_point(row, prev_close, now) when is_map(row) do
    with {:ok, day} <- daily_open_time(row["d"]),
         {:ok, high} <- decimal(row["h"]),
         {:ok, low} <- decimal(row["l"]),
         {:ok, close} <- decimal(row["c"]),
         open = prev_close || close,
         true <-
           D.positive?(low) and D.positive?(high) and D.positive?(open) and D.positive?(close),
         high = high |> D.max(open) |> D.max(close),
         low = low |> D.min(open) |> D.min(close),
         close_time = DateTime.add(day, 86_399_999, :millisecond),
         true <- DateTime.compare(close_time, DateTime.add(now, -5)) == :lt do
      {:ok,
       %{
         timeframe: "1d",
         open_time: day,
         close_time: close_time,
         open: open,
         high: high,
         low: low,
         close: close,
         base_volume: Decimal.new(0),
         quote_volume: nil,
         trade_count: nil,
         taker_buy_base_volume: nil,
         taker_buy_quote_volume: nil
       }, close}
    else
      false ->
        close =
          case decimal(row["c"]) do
            {:ok, value} -> value
            _ -> prev_close
          end

        {:skip, close}

      _ ->
        {:error, :invalid_gold_history}
    end
  end

  defp daily_point(_, _, _), do: {:error, :invalid_gold_history}

  defp daily_open_time(value) when is_binary(value) do
    with {:ok, date} <- Date.from_iso8601(value),
         {:ok, naive} <- NaiveDateTime.new(date, ~T[00:00:00]) do
      {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
    else
      _ -> {:error, :invalid_time}
    end
  end

  defp daily_open_time(_), do: {:error, :invalid_time}

  defp candle([seconds, low, high, open, close, volume], now)
       when is_integer(seconds) and seconds >= 0 do
    with true <- rem(seconds, 3600) == 0,
         {:ok, values} <-
           decimals(%{low: low, high: high, open: open, close: close, base_volume: volume},
             low: :low,
             high: :high,
             open: :open,
             close: :close,
             base_volume: :base_volume
           ),
         true <- D.positive?(values.low) and D.compare(values.base_volume, 0) != :lt,
         true <-
           Enum.all?(
             [values.open, values.close],
             &(D.compare(&1, values.low) != :lt and D.compare(&1, values.high) != :gt)
           ),
         {:ok, open_time} <- DateTime.from_unix(seconds * 1_000_000, :microsecond) do
      close_time = DateTime.add(open_time, 3_599_999, :millisecond)

      if DateTime.compare(close_time, DateTime.add(now, -5)) == :lt do
        {:ok,
         Map.merge(values, %{
           timeframe: "1h",
           open_time: open_time,
           close_time: close_time,
           quote_volume: nil,
           trade_count: nil,
           taker_buy_base_volume: nil,
           taker_buy_quote_volume: nil
         })}
      else
        {:skip, :open}
      end
    else
      _ -> {:error, :invalid_candle}
    end
  end

  defp candle(_, _), do: {:error, :invalid_candle}

  defp decimals(row, fields) do
    Enum.reduce_while(fields, {:ok, %{}}, fn {target, source}, {:ok, acc} ->
      case decimal(row[source]) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, target, value)}}
        error -> {:halt, error}
      end
    end)
  end

  defp parse_time(time) when is_binary(time), do: DateTime.from_iso8601(time)
  defp parse_time(_), do: {:error, :invalid_time}
end
