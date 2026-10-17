defmodule CryptoDecisionLab.Clock do
  @moduledoc "UTC wall clock, replaceable in synchronization tests."
  def now, do: DateTime.utc_now()
end
