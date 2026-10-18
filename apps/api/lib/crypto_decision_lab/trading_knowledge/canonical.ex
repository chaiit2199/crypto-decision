defmodule CryptoDecisionLab.TradingKnowledge.Canonical do
  @moduledoc "Stable application JSON encoding: sorted keys, unchanged array order and decimal strings."
  @spec encode(term()) :: binary()
  def encode(value), do: value |> ordered() |> Jason.encode!()
  @spec hash(term()) :: binary()
  def hash(value), do: :crypto.hash(:sha256, encode(value)) |> Base.encode16(case: :lower)

  defp ordered(value) when is_map(value) do
    value
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {k, v} -> {k, ordered(v)} end)
    |> Jason.OrderedObject.new()
  end

  defp ordered(value) when is_list(value), do: Enum.map(value, &ordered/1)
  defp ordered(value), do: value
end
