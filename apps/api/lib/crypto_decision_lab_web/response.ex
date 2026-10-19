defmodule CryptoDecisionLabWeb.Response do
  @moduledoc false
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def send(conn, {:ok, data, meta}) do
    json(conn, normalize(%{data: data, meta: Map.put(meta, :generated_at, DateTime.utc_now())}))
  end

  def send(conn, {:error, reason}) do
    status =
      case reason do
        :not_found -> 404
        :database_unavailable -> 503
        :incomplete_aggregation -> 422
        _ -> 400
      end

    conn
    |> put_status(status)
    |> json(%{error: %{code: to_string(reason), message: message(reason)}})
  end

  defp message(:invalid_plan),
    do: "Use decimal strings, positive equity, risk up to 5%, and stop < entry < target"

  defp message(:not_found), do: "Market symbol not found"
  defp message(:database_unavailable), do: "Database unavailable"
  defp message(:incomplete_aggregation), do: "Underlying hourly candles are missing"
  defp message(_), do: "Invalid request parameters"

  def normalize(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  def normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)

  def normalize(value) when is_map(value),
    do: Map.new(value, fn {key, val} -> {key, normalize(val)} end)

  def normalize(value), do: value
end
