defmodule CryptoDecisionLab.MarketData.SnapshotTime do
  @moduledoc "Bounded clock skew for live snapshots; never used to decide candle closure."

  @max_future_seconds 60

  @spec max_future_seconds() :: pos_integer()
  def max_future_seconds, do: @max_future_seconds

  @doc "Accept a source timestamp within the clock-skew allowance and the given maximum age."
  @spec fresh?(DateTime.t(), DateTime.t(), non_neg_integer()) :: boolean()
  def fresh?(timestamp, now, max_age_seconds) do
    age_ms = DateTime.diff(now, timestamp, :millisecond)
    age_ms >= -@max_future_seconds * 1000 and age_ms <= max_age_seconds * 1000
  end

  @spec future?(DateTime.t(), DateTime.t()) :: boolean()
  def future?(timestamp, now) do
    DateTime.diff(timestamp, now, :millisecond) > @max_future_seconds * 1000
  end
end
