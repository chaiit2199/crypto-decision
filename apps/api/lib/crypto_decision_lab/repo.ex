defmodule CryptoDecisionLab.Repo do
  use Ecto.Repo,
    otp_app: :crypto_decision_lab,
    adapter: Ecto.Adapters.Postgres
end
