defmodule CryptoDecisionLabWeb.RequestMetrics do
  @moduledoc false
  import Plug.Conn
  require Logger
  def init(opts), do: opts

  def call(conn, _) do
    started = System.monotonic_time(:microsecond)

    register_before_send(conn, fn conn ->
      Logger.info("api_request",
        method: conn.method,
        path: conn.request_path,
        status: conn.status,
        duration_us: System.monotonic_time(:microsecond) - started
      )

      conn
    end)
  end
end
