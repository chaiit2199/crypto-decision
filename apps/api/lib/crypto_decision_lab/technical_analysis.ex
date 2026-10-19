defmodule CryptoDecisionLab.TechnicalAnalysis do
  @moduledoc "Closed-candle features on explicit UTC timeframes. Decimal arithmetic; SMA-seeded EMA and Wilder RSI."
  alias Decimal, as: D

  @doc "Requires 300 consecutive, valid closed 1H candles, oldest first. No future data."
  @spec features([map()], DateTime.t()) :: {:ok, map()} | {:error, atom()}
  def features(candles, now), do: features(candles, now, "1h")

  @doc "The same closed-bar mathematics on a specified UTC timeframe; no cross-market mixing."
  @spec features([map()], DateTime.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def features(candles, now, timeframe)
      when length(candles) == 300 and timeframe in ["5m", "15m", "1h", "4h", "1d"] do
    width = %{"5m" => 300, "15m" => 900, "1h" => 3600, "4h" => 14_400, "1d" => 86_400}[timeframe]
    last = List.last(candles)

    cond do
      not Enum.all?(candles, &valid_candle?(&1, now, timeframe, width)) ->
        {:error, :invalid_candles}

      not consecutive?(candles, width) ->
        {:error, :candle_gap}

      DateTime.diff(now, last.close_time) > width + 60 ->
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
           "timeframe" => timeframe,
           "candle_count" => 300,
           "last_close_time" => DateTime.to_iso8601(last.close_time),
           "close" => decimal(last.close),
           "ema9" => decimal(ema(closes, 9)),
           "ema21" => decimal(ema(closes, 21)),
           "atr_percent" => decimal(D.mult(D.div(atr, last.close), 100)),
           "support" =>
             decimal(
               candles
               |> Enum.slice(-21, 20)
               |> Enum.map(& &1.low)
               |> Enum.reduce(&D.min/2)
             ),
           "resistance" =>
             decimal(
               candles
               |> Enum.slice(-21, 20)
               |> Enum.map(& &1.high)
               |> Enum.reduce(&D.max/2)
             ),
           "vwap" => session_vwap(candles, width, now),
           "volume_delta" =>
             if(last.taker_buy_base_volume,
               do: decimal(D.sub(D.mult(last.taker_buy_base_volume, 2), last.base_volume)),
               else: nil
             ),
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
           if(timeframe == "1h", do: "return_1h_percent", else: "return_1bar_percent") =>
             decimal(return_percent(last.close, Enum.at(closes, -2))),
           if(timeframe == "1h", do: "return_24h_percent", else: "return_24bar_percent") =>
             decimal(return_percent(last.close, Enum.at(closes, -25)))
         }}
    end
  end

  def features(_, _, _), do: {:error, :insufficient_candles}

  defp valid_candle?(candle, now, timeframe, width) do
    candle.timeframe == timeframe and rem(DateTime.to_unix(candle.open_time), width) == 0 and
      DateTime.diff(candle.close_time, candle.open_time, :millisecond) == width * 1000 - 1 and
      DateTime.compare(candle.close_time, DateTime.add(now, -5)) == :lt and
      D.positive?(candle.low) and D.compare(candle.high, candle.low) != :lt and
      D.compare(candle.low, candle.open) != :gt and D.compare(candle.low, candle.close) != :gt and
      D.compare(candle.high, candle.open) != :lt and D.compare(candle.high, candle.close) != :lt and
      D.compare(candle.base_volume, 0) != :lt
  end

  defp consecutive?(candles, width) do
    candles
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [first, second] ->
      DateTime.diff(second.open_time, first.open_time) == width
    end)
  end

  defp session_vwap(candles, width, now) do
    day = DateTime.to_date(now)
    rows = Enum.filter(candles, &(DateTime.to_date(&1.open_time) == day))

    complete =
      rows != [] and Time.compare(DateTime.to_time(hd(rows).open_time), ~T[00:00:00]) == :eq and
        consecutive?(rows, width) and Enum.all?(rows, &(not is_nil(&1.quote_volume)))

    if complete do
      base = Enum.reduce(rows, D.new(0), &D.add(&2, &1.base_volume))
      quote = Enum.reduce(rows, D.new(0), &D.add(&2, &1.quote_volume))
      if D.positive?(base), do: decimal(D.div(quote, base)), else: nil
    else
      nil
    end
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
