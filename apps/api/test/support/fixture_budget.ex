defmodule CryptoDecisionLab.FixtureBudget do
  def reserve(_, _), do: :ok
  def observe(_, _), do: :ok
  def block(seconds, status), do: Process.put(:blocked, {seconds, status})
end
