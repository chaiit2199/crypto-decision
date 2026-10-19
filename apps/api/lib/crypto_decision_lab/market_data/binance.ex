defmodule CryptoDecisionLab.MarketData.Binance do
  @moduledoc "Public Spot requests with explicit weights, bounded retries and shared cooldown."
  require Logger
  alias CryptoDecisionLab.MarketData.{Collector, SnapshotTime}

  def exchange_info(opts \\ []),
    do: request("/exchangeInfo", [permissions: "SPOT", showPermissionSets: false], 20, opts)

  def prices(symbols, opts \\ []),
    do: request("/ticker/price", [symbols: Jason.encode!(symbols)], 4, opts)

  def stats(symbols, opts \\ []) when length(symbols) in 1..20,
    do: request("/ticker/24hr", [symbols: Jason.encode!(symbols), type: "FULL"], 2, opts)

  def klines(symbol, start_ms, end_ms, opts \\ []) do
    request(
      "/klines",
      [
        symbol: symbol,
        interval: Keyword.get(opts, :timeframe, "1h"),
        startTime: start_ms,
        endTime: end_ms,
        limit: 1000
      ],
      2,
      opts
    )
  end

  @doc "Bounded Spot depth snapshot (weight 5). Uses the shared collector budget."
  def depth(symbol, opts \\ []), do: request("/depth", [symbol: symbol, limit: 100], 5, opts)

  defp request(path, params, weight, opts, attempt \\ 0) do
    budget = Keyword.get(opts, :budget, Collector)

    transport =
      Keyword.get(
        opts,
        :transport,
        Application.fetch_env!(:crypto_decision_lab, :binance_transport)
      )

    clock = Keyword.get(opts, :now, &Collector.now/0)
    now = clock.()

    with :ok <- budget.reserve(weight, now) do
      started = System.monotonic_time(:millisecond)
      result = transport.get(path, params)

      Logger.info("binance_request",
        path: path,
        weight: weight,
        attempt: attempt,
        duration_ms: System.monotonic_time(:millisecond) - started
      )

      case result do
        {:ok, %{status: status, headers: headers} = response} ->
          fetched_at = clock.()
          budget.observe(headers, fetched_at)

          cond do
            status in [418, 429] ->
              seconds = retry_after(headers, status)
              budget.block(seconds, status)
              {:error, {:cooldown, seconds}}

            status >= 500 ->
              retry(path, params, weight, opts, attempt, :upstream_unavailable)

            status != 200 ->
              {:error, {:upstream_http, status, error_code(response.body)}}

            true ->
              decode(response, fetched_at)
          end

        {:error, _reason} ->
          retry(path, params, weight, opts, attempt, :network_error)
      end
    end
  end

  defp retry(path, params, weight, opts, attempt, _reason) when attempt < 2 do
    sleep = Keyword.get(opts, :sleep, &Process.sleep/1)
    sleep.(min(500 * Integer.pow(2, attempt) + :rand.uniform(250), 5000))
    request(path, params, weight, opts, attempt + 1)
  end

  defp retry(_path, _params, _weight, _opts, _attempt, reason), do: {:error, reason}

  defp decode(response, fetched_at) do
    with {:ok, server_time} <- server_time(response.headers),
         true <- SnapshotTime.fresh?(server_time, fetched_at, SnapshotTime.max_future_seconds()),
         {:ok, body} <- Jason.decode(response.body) do
      {:ok, %{body: body, fetched_at: fetched_at, server_time: server_time}}
    else
      false -> {:error, :stale_response}
      _ -> {:error, :invalid_response}
    end
  end

  defp server_time(headers) do
    with [date | _] <- Map.get(headers, "date", []),
         [_, day, month, year, hour, minute, second] <-
           Regex.run(~r/^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$/, date),
         month_index when is_integer(month_index) <-
           Enum.find_index(~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec), &(&1 == month)),
         {:ok, value} <-
           NaiveDateTime.new(
             String.to_integer(year),
             month_index + 1,
             String.to_integer(day),
             String.to_integer(hour),
             String.to_integer(minute),
             String.to_integer(second)
           ) do
      DateTime.from_naive(value, "Etc/UTC")
    else
      _ -> {:error, :invalid_date}
    end
  end

  defp retry_after(headers, status) do
    fallback = if status == 418, do: 259_200, else: 60

    with [value | _] <- Map.get(headers, "retry-after", []),
         {seconds, ""} when seconds > 0 <- Integer.parse(value) do
      seconds
    else
      _ -> fallback
    end
  end

  defp error_code(body) do
    case Jason.decode(body) do
      {:ok, %{"code" => code}} when is_integer(code) -> code
      _ -> nil
    end
  end
end
