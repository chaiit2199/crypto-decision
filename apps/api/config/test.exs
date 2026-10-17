import Config

config :crypto_decision_lab, CryptoDecisionLab.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :crypto_decision_lab, CryptoDecisionLabWeb.Endpoint, server: false
config :crypto_decision_lab, Oban, testing: :manual, queues: false, plugins: false
config :crypto_decision_lab, :sync_enabled, false
config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
