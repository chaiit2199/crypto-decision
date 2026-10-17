defmodule CryptoDecisionLab.LogFormatter do
  @moduledoc false
  def format(level, message, {{year, month, day}, {hour, minute, second, millisecond}}, metadata) do
    {:ok, timestamp} =
      NaiveDateTime.new(year, month, day, hour, minute, second, {millisecond * 1000, 3})

    Jason.encode!(%{
      level: level,
      message: IO.iodata_to_binary(message),
      timestamp: NaiveDateTime.to_iso8601(timestamp) <> "Z",
      metadata: Map.new(metadata, fn {key, value} -> {key, serializable(value)} end)
    }) <> "\n"
  end

  defp serializable(value)
       when is_number(value) or is_binary(value) or is_boolean(value) or is_nil(value),
       do: value

  defp serializable(value), do: inspect(value)
end
