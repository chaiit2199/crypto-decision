defmodule CryptoDecisionLab.TechnicalAnalysis do
  @moduledoc "Closed-hourly features. Decimal arithmetic; SMA-seeded EMA and Wilder RSI."
  alias Decimal, as: D

  @doc "Requires 300 consecutive, valid closed 1H candles, oldest first. No future data."
  @spec features([map()], DateTime.t()) :: {:ok, map()} | {:error, atom()}
  def features(candles, now) when length(candles) == 300 do
    last = List.last(candles)

    cond do
      not Enum.all?(candles, &valid_candle?(&1, now)) ->
        {:error, :invalid_candles}

      not consecutive?(candles) ->
        {:error, :candle_gap}

      DateTime.diff(now, last.close_time) > 3660 ->
        {:error, :stale_candles}

      true ->
        closes = Enum.map(candles, & &1.close)

        macd_values =
          Enum.zip(Enum.drop(ema_series(closes, 12), 14), ema_series(closes, 26))
          |> Enum.map(fn {fast, slow} -> D.sub(fast, slow) end)

        macd = List.last(macd_values)
        macd_signal = ema(macd_values, 9)
        {atr, adx} = volatility_trend(candles, 14)
        volume_average = candles |> Enum.slice(-21, 20) |> Enum.map(& &1.base_volume) |> average()

        {:ok,
         %{
           "timeframe" => "1h",
           "candle_count" => 300,
           "last_close_time" => DateTime.to_iso8601(last.close_time),
           "close" => decimal(last.close),
           "ema20" => decimal(ema(closes, 20)),
           "ema50" => decimal(ema(closes, 50)),
           "ema200" => decimal(ema(closes, 200)),
           "macd" => decimal(macd),
           "macd_signal" => decimal(macd_signal),
           "macd_histogram" => decimal(D.sub(macd, macd_signal)),
           "atr14" => decimal(atr),
           "adx14" => decimal(adx),
           "relative_volume20" =>
             if(D.equal?(volume_average, 0),
               do: nil,
               else: decimal(D.div(last.base_volume, volume_average))
             ),
           "rsi14" => decimal(rsi(closes, 14)),
           "return_1h_percent" => decimal(return_percent(last.close, Enum.at(closes, -2))),
           "return_24h_percent" => decimal(return_percent(last.close, Enum.at(closes, -25)))
         }}
    end
  end

  def features(_, _), do: {:error, :insufficient_candles}

  defp valid_candle?(candle, now) do
    candle.timeframe == "1h" and rem(DateTime.to_unix(candle.open_time), 3600) == 0 and
      DateTime.diff(candle.close_time, candle.open_time, :millisecond) == 3_599_999 and
      DateTime.compare(candle.close_time, DateTime.add(now, -5)) == :lt and
      D.positive?(candle.low) and D.compare(candle.high, candle.low) != :lt and
      D.compare(candle.low, candle.open) != :gt and D.compare(candle.low, candle.close) != :gt and
      D.compare(candle.high, candle.open) != :lt and D.compare(candle.high, candle.close) != :lt and
      D.compare(candle.base_volume, 0) != :lt
  end

  defp consecutive?(candles) do
    candles
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [first, second] ->
      DateTime.diff(second.open_time, first.open_time) == 3600
    end)
  end

  defp ema(values, period) do
    values |> ema_series(period) |> List.last()
  end

  defp ema_series(values, period) do
    {seed, rest} = Enum.split(values, period)
    alpha = D.div(2, period + 1)

    [
      average(seed)
      | Enum.scan(rest, average(seed), fn value, previous ->
          D.add(previous, D.mult(alpha, D.sub(value, previous)))
        end)
    ]
  end

  defp volatility_trend(candles, period) do
    movements =
      Enum.chunk_every(candles, 2, 1, :discard)
      |> Enum.map(fn [previous, current] ->
        tr =
          D.max(
            D.sub(current.high, current.low),
            D.max(
              D.abs(D.sub(current.high, previous.close)),
              D.abs(D.sub(current.low, previous.close))
            )
          )

        up = D.sub(current.high, previous.high)
        down = D.sub(previous.low, current.low)
        plus = if D.positive?(up) and D.compare(up, down) == :gt, do: up, else: D.new(0)
        minus = if D.positive?(down) and D.compare(down, up) == :gt, do: down, else: D.new(0)
        {tr, plus, minus}
      end)

    tr = movements |> Enum.map(&elem(&1, 0)) |> wilder(period)
    plus = movements |> Enum.map(&elem(&1, 1)) |> wilder(period)
    minus = movements |> Enum.map(&elem(&1, 2)) |> wilder(period)

    dx =
      Enum.zip(plus, minus)
      |> Enum.map(fn {p, m} ->
        # TR cancels in DX = 100 * abs(DI+ - DI-) / (DI+ + DI-).
        if D.equal?(D.add(p, m), 0),
          do: D.new(0),
          else: D.mult(100, D.div(D.abs(D.sub(p, m)), D.add(p, m)))
      end)

    {List.last(tr), dx |> wilder(period) |> List.last()}
  end

  defp wilder(values, period) do
    {seed, rest} = Enum.split(values, period)

    [
      average(seed)
      | Enum.scan(rest, average(seed), fn value, previous ->
          D.div(D.add(D.mult(previous, period - 1), value), period)
        end)
    ]
  end

  defp rsi(values, period) do
    changes = Enum.chunk_every(values, 2, 1, :discard) |> Enum.map(fn [a, b] -> D.sub(b, a) end)
    {seed, rest} = Enum.split(changes, period)
    gains = average(Enum.map(seed, &D.max(&1, 0)))
    losses = average(Enum.map(seed, &D.max(D.negate(&1), 0)))

    {gain, loss} =
      Enum.reduce(rest, {gains, losses}, fn change, {gain, loss} ->
        {D.div(D.add(D.mult(gain, period - 1), D.max(change, 0)), period),
         D.div(D.add(D.mult(loss, period - 1), D.max(D.negate(change), 0)), period)}
      end)

    cond do
      D.equal?(gain, 0) and D.equal?(loss, 0) -> D.new(50)
      D.equal?(loss, 0) -> D.new(100)
      true -> D.sub(100, D.div(100, D.add(1, D.div(gain, loss))))
    end
  end

  defp average(values), do: D.div(Enum.reduce(values, D.new(0), &D.add/2), length(values))
  defp return_percent(value, previous), do: D.mult(D.div(D.sub(value, previous), previous), 100)
  defp decimal(value), do: value |> D.normalize() |> D.to_string(:normal)
end
