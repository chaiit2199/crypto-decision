defmodule CryptoDecisionLab.MockDecisionProvider do
  @moduledoc "Synthetic provider, available only in test builds; never used as a live fallback."
  @behaviour CryptoDecisionLab.Decisions.DecisionProvider

  @impl true
  def analyze(features) do
    send(self(), {:jev_called, features})
    Process.get(:jev_result, {:ok, response()})
  end

  def response do
    %{
      "model" => "fixture-jev",
      "usage" => %{"input_tokens" => 300, "output_tokens" => 50},
      "answers" => %{
        "trend" => answer("BULLISH", %{"BULLISH" => 0.8, "BEARISH" => 0.1, "SIDEWAYS" => 0.1}),
        "momentum" =>
          answer("STRENGTHENING", %{"STRENGTHENING" => 0.8, "WEAKENING" => 0.1, "MIXED" => 0.1}),
        "volatility" => answer("NORMAL", %{"NORMAL" => 0.8, "ELEVATED" => 0.2})
      }
    }
  end

  defp answer(choice, probabilities),
    do: %{
      "type" => "choice",
      "choice" => choice,
      "confidence" => 0.7,
      "probabilities" => probabilities
    }
end
