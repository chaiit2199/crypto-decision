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

        {:ok,
         %{
           "timeframe" => "1h",
           "candle_count" => 300,
           "last_close_time" => DateTime.to_iso8601(last.close_time),
           "close" => decimal(last.close),
           "ema20" => decimal(ema(closes, 20)),
           "ema50" => decimal(ema(closes, 50)),
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
    {seed, rest} = Enum.split(values, period)
    alpha = D.div(2, period + 1)

    Enum.reduce(rest, average(seed), fn value, previous ->
      D.add(previous, D.mult(alpha, D.sub(value, previous)))
    end)
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
