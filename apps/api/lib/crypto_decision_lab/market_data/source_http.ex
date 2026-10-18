defmodule CryptoDecisionLab.MarketData.SourceHTTP do
  @moduledoc "Public read-only USD/gold transport. Caller serializes requests and persists cooldowns."
  alias CryptoDecisionLab.MarketData.Collector

  @spec get(String.t(), String.t(), keyword()) :: {:ok, term(), DateTime.t()} | {:error, term()}
  def get(source, path, params \\ []) do
    base = %{
      "coinbase" => "https://api.exchange.coinbase.com",
      "gold_api" => "https://api.gold-api.com"
    }

    sleep = Application.get_env(:crypto_decision_lab, :source_sleep, &Process.sleep/1)
    sleep.(150)
    request = Application.get_env(:crypto_decision_lab, :source_request, &Req.get/1)

    result =
      request.(
        url: Map.fetch!(base, source) <> path,
        params: params,
        headers: [{"user-agent", "CryptoDecisionLab/0.1"}],
        decode_body: false,
        receive_timeout: 8_000,
        connect_options: [timeout: 3_000],
        retry: false,
        redirect: false
      )

    case result do
      {:ok, %{status: 200, body: body, headers: headers}} when is_binary(body) ->
        with {:ok, data_at} <- response_time(headers),
             {:ok, decoded} <- Jason.decode(body, floats: :decimals) do
          {:ok, decoded, data_at}
        else
          {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
          {:error, _} = error -> error
        end

      {:ok, %{status: 429, headers: headers}} ->
        seconds =
          case get_in(headers, ["retry-after"]) do
            [value | _] ->
              case Integer.parse(value) do
                {n, ""} when n > 0 -> n
                _ -> 120
              end

            _ ->
              120
          end

        {:error, {:rate_limited, seconds}}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      _ ->
        {:error, :transport_error}
    end
  end

  defp response_time(%{"date" => [date | _]}) when is_binary(date) do
    with [_, day, month, year, hour, minute, second] <-
           Regex.run(~r/^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$/, date),
         index when is_integer(index) <-
           Enum.find_index(~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec), &(&1 == month)),
         {:ok, naive} <-
           NaiveDateTime.new(
             String.to_integer(year),
             index + 1,
             String.to_integer(day),
             String.to_integer(hour),
             String.to_integer(minute),
             String.to_integer(second)
           ),
         time =
           DateTime.from_naive!(naive, "Etc/UTC")
           |> DateTime.to_unix(:microsecond)
           |> DateTime.from_unix!(:microsecond) do
      age_seconds = DateTime.diff(Collector.now(), time)

      cond do
        age_seconds > 120 -> {:error, {:stale_response, age_seconds}}
        age_seconds < -5 -> {:error, {:future_response, -age_seconds}}
        true -> {:ok, time}
      end
    else
      _ -> {:error, :invalid_response_date}
    end
  end

  defp response_time(headers) when not is_map_key(headers, "date"),
    do: {:error, :missing_response_date}

  defp response_time(_headers), do: {:error, :invalid_response_date}
end
