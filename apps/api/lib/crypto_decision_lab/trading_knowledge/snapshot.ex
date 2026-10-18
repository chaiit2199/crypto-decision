defmodule CryptoDecisionLab.TradingKnowledge.Snapshot do
  @moduledoc "Point-in-time input checks. Availability time is distinct from market observation time."
  alias Decimal, as: D
  @features ~w(close ema20 ema50 rsi14 return_1h_percent return_24h_percent)
  @decimal ~r/^-?(0|[1-9][0-9]{0,17})(\.[0-9]{1,38})?$/

  @spec decimal(term()) :: {:ok, Decimal.t()} | {:error, atom()}
  def decimal(value) when is_binary(value) do
    if Regex.match?(@decimal, value), do: {:ok, D.new(value)}, else: {:error, :invalid_decimal}
  end

  def decimal(_), do: {:error, :invalid_decimal}

  @spec time(term()) :: {:ok, DateTime.t()} | {:error, atom()}
  def time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, 0} -> {:ok, time}
      _ -> {:error, :invalid_timestamp}
    end
  end

  def time(_), do: {:error, :invalid_timestamp}

  @spec validate(map(), DateTime.t(), pos_integer()) :: :ok | {:error, atom()}
  def validate(snapshot, now, max_age) when is_map(snapshot) do
    with {:ok, as_of} <- time(snapshot["as_of"]),
         {:ok, available} <- time(snapshot["available_at"]),
         true <- ordered?(as_of, available) and ordered?(available, now),
         true <- DateTime.diff(now, as_of, :microsecond) <= max_age * 1_000_000,
         true <- snapshot["timeframe"] == "1h" and snapshot["feature_version"] == "hourly-v1",
         true <-
           is_binary(snapshot["symbol"]) and
             Regex.match?(~r/^[A-Z0-9]{2,20}USDT$/, snapshot["symbol"]),
         true <-
           is_binary(snapshot["dataset_hash"]) and
             Regex.match?(~r/^[a-f0-9]{64}$/, snapshot["dataset_hash"]),
         true <- is_map(snapshot["features"]),
         true <- Enum.sort(Map.keys(snapshot["features"])) == Enum.sort(@features),
         true <-
           Enum.sort(Map.keys(snapshot)) ==
             Enum.sort(
               ~w(symbol timeframe regime as_of available_at feature_version dataset_hash features)
             ),
         true <- Enum.all?(@features, &match?({:ok, _}, feature(snapshot, &1, now, max_age))),
         {:ok, regime} <- regime(snapshot, now, max_age),
         true <- snapshot["regime"] == regime do
      :ok
    else
      _ -> {:error, :invalid_or_stale_snapshot}
    end
  end

  def validate(_, _, _), do: {:error, :invalid_or_stale_snapshot}

  @spec feature(map(), binary(), DateTime.t(), pos_integer()) ::
          {:ok, Decimal.t()} | {:error, atom()}
  def feature(snapshot, name, now, max_age) when is_map(snapshot) do
    with features when is_map(features) <- snapshot["features"],
         %{"value" => raw, "observed_at" => observed, "available_at" => available} <-
           Map.get(features, name),
         {:ok, value} <- decimal(raw),
         {:ok, observed} <- time(observed),
         {:ok, available} <- time(available),
         {:ok, as_of} <- time(snapshot["as_of"]),
         {:ok, envelope} <- time(snapshot["available_at"]),
         true <-
           ordered?(observed, available) and ordered?(observed, as_of) and
             ordered?(available, envelope) and ordered?(envelope, now),
         true <- DateTime.diff(now, observed, :microsecond) <= max_age * 1_000_000,
         true <- domain?(name, value) do
      {:ok, value}
    else
      _ -> {:error, :unknown_feature}
    end
  end

  def feature(_, _, _, _), do: {:error, :unknown_feature}

  defp domain?(name, value) when name in ~w(close ema20 ema50), do: D.compare(value, 0) == :gt
  defp domain?("rsi14", value), do: D.compare(value, 0) != :lt and D.compare(value, 100) != :gt
  defp domain?(name, _), do: name in ~w(return_1h_percent return_24h_percent)

  @doc "Version-one regime uses EMA20/50 separation: within 0.5% is range, otherwise EMA ordering."
  @spec regime(map(), DateTime.t(), pos_integer()) :: {:ok, binary()} | {:error, atom()}
  def regime(snapshot, now, max_age) do
    with {:ok, _close} <- feature(snapshot, "close", now, max_age),
         {:ok, fast} <- feature(snapshot, "ema20", now, max_age),
         {:ok, slow} <- feature(snapshot, "ema50", now, max_age) do
      difference = D.mult(D.sub(D.div(fast, slow), 1), 100)

      cond do
        D.compare(D.abs(difference), "0.5") != :gt -> {:ok, "range"}
        D.compare(fast, slow) == :gt -> {:ok, "uptrend"}
        true -> {:ok, "downtrend"}
      end
    end
  end

  @doc "Build from 300 closed candles with archived per-candle availability; never infer historical availability from current ingestion."
  @spec from_candles([map()], binary(), DateTime.t()) :: {:ok, map()} | {:error, term()}
  def from_candles(records, symbol, now) when length(records) == 300 do
    alias CryptoDecisionLab.TechnicalAnalysis
    alias CryptoDecisionLab.TradingKnowledge.Canonical

    available =
      Enum.all?(records, fn record ->
        is_struct(record[:available_at], DateTime) and
          is_map(record[:candle]) and
          ordered?(record.candle.close_time, record.available_at) and
          ordered?(record.available_at, now)
      end)

    with true <- available,
         {:ok, features} <- TechnicalAnalysis.features(Enum.map(records, & &1.candle), now) do
      observed_at = features["last_close_time"]

      available_at =
        records |> Enum.map(& &1.available_at) |> Enum.max(DateTime) |> DateTime.to_iso8601()

      lineage =
        Enum.map(records, fn record ->
          %{
            "available_at" => DateTime.to_iso8601(record.available_at),
            "candle" =>
              Map.take(record.candle, [
                :open_time,
                :close_time,
                :open,
                :high,
                :low,
                :close,
                :base_volume
              ])
              |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
          }
        end)

      snapshot = %{
        "symbol" => symbol,
        "timeframe" => "1h",
        "feature_version" => "hourly-v1",
        "as_of" => observed_at,
        "available_at" => available_at,
        "dataset_hash" => Canonical.hash(lineage),
        "features" =>
          Map.new(
            @features,
            &{&1,
             %{
               "value" => features[&1],
               "observed_at" => observed_at,
               "available_at" => available_at
             }}
          )
      }

      {:ok, regime} = regime(snapshot, now, 3660)
      snapshot = Map.put(snapshot, "regime", regime)
      with :ok <- validate(snapshot, now, 3660), do: {:ok, snapshot}
    else
      false -> {:error, :unavailable_candle}
      error -> error
    end
  end

  def from_candles(_, _, _), do: {:error, :insufficient_candles}

  defp ordered?(a, b), do: DateTime.compare(a, b) != :gt
end
