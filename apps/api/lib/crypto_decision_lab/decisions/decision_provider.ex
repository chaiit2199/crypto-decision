defmodule CryptoDecisionLab.Decisions.DecisionProvider do
  @moduledoc "Provider boundary. Errors are sanitized codes and a shared cooldown in seconds."
  @callback analyze(map()) :: {:ok, map()} | {:error, String.t(), non_neg_integer()}
end
