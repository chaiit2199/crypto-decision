defmodule CryptoDecisionLab.MarketData.Parser do
  @moduledoc "Strict normalization of untrusted market payloads; no float conversions."
  @hour 3_600_000

  def decimal(value) when is_binary(value) and byte_size(value) <= 72 do
    parsed =
      if Regex.match?(~r/^-?\d{1,40}(\.\d{1,30})?$/, value),
        do: Decimal.parse(value),
        else: :error

    case parsed do
      {%Decimal{coef: coef} = number, ""} when is_integer(coef) -> {:ok, number}
      _ -> {:error, :invalid_decimal}
    end
  end

  def decimal(_), do: {:error, :invalid_decimal}

  def price(%{"symbol" => symbol, "price" => value}) when is_binary(symbol) do
    with {:ok, number} <- decimal(value), true <- Decimal.positive?(number) do
      {:ok, %{symbol: symbol, price: number}}
    else
      _ -> {:error, :invalid_price}
    end
  end

  def price(_), do: {:error, :invalid_price}

  def stats(%{"symbol" => symbol, "count" => count, "closeTime" => close_time} = row, now)
      when is_binary(symbol) and is_integer(count) and count >= 0 and
             count <= 9_223_372_036_854_775_807 and is_integer(close_time) do
    fields = [
      price_change: "priceChange",
      price_change_percent: "priceChangePercent",
      high_price: "highPrice",
      low_price: "lowPrice",
      base_volume: "volume",
      quote_volume: "quoteVolume"
    ]

    with {:ok, values} <- decimals(row, fields),
         {:ok, time} <- DateTime.from_unix(close_time * 1000, :microsecond),
         true <- DateTime.diff(now, time) in -5..600,
         true <-
           Decimal.positive?(values.low_price) and
             Decimal.compare(values.high_price, values.low_price) != :lt,
         true <- nonnegative?(values.base_volume) and nonnegative?(values.quote_volume) do
      {:ok, Map.merge(values, %{symbol: symbol, trade_count: count, data_at: time})}
    else
      _ -> {:error, :invalid_or_stale_stats}
    end
  end

  def stats(_, _), do: {:error, :invalid_stats}

  def candle(
        [
          open_ms,
          open,
          high,
          low,
          close,
          base,
          close_ms,
          quote,
          trades,
          taker_base,
          taker_quote,
          _
        ],
        now
      )
      when is_integer(open_ms) and is_integer(close_ms) and is_integer(trades) and trades >= 0 and
             trades <= 9_223_372_036_854_775_807 do
    raw = %{
      open: open,
      high: high,
      low: low,
      close: close,
      base_volume: base,
      quote_volume: quote,
      taker_buy_base_volume: taker_base,
      taker_buy_quote_volume: taker_quote
    }

    with true <- open_ms >= 0 and rem(open_ms, @hour) == 0 and close_ms == open_ms + @hour - 1,
         {:ok, values} <- decimals(raw, Enum.map(Map.keys(raw), &{&1, &1})),
         true <- valid_ohlcv?(values),
         {:ok, open_time} <- DateTime.from_unix(open_ms * 1000, :microsecond),
         {:ok, close_time} <- DateTime.from_unix(close_ms * 1000, :microsecond) do
      if close_ms < DateTime.to_unix(now, :millisecond) - 5000 do
        {:ok,
         Map.merge(values, %{
           timeframe: "1h",
           open_time: open_time,
           close_time: close_time,
           trade_count: trades
         })}
      else
        {:skip, :incomplete}
      end
    else
      _ -> {:error, :invalid_candle}
    end
  end

  def candle(_, _), do: {:error, :invalid_candle}

  defp decimals(raw, fields) do
    Enum.reduce_while(fields, {:ok, %{}}, fn {target, source}, {:ok, values} ->
      case decimal(Map.get(raw, source)) do
        {:ok, value} -> {:cont, {:ok, Map.put(values, target, value)}}
        error -> {:halt, error}
      end
    end)
  end

  defp valid_ohlcv?(v) do
    Decimal.positive?(v.open) and Decimal.positive?(v.low) and
      Decimal.compare(v.high, v.open) != :lt and Decimal.compare(v.high, v.close) != :lt and
      Decimal.compare(v.low, v.open) != :gt and Decimal.compare(v.low, v.close) != :gt and
      Enum.all?(
        [v.base_volume, v.quote_volume, v.taker_buy_base_volume, v.taker_buy_quote_volume],
        &nonnegative?/1
      )
  end

  defp nonnegative?(value), do: Decimal.compare(value, 0) != :lt
end
