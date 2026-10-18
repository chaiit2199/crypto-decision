import Config

# Start collection in dev; MARKET_SYNC_ENABLED=false opts out at runtime.
# Runtime assembles market/Jev queues and Cron independently. Prices use Poller every 30s.
config :crypto_decision_lab, :sync_enabled, true
config :crypto_decision_lab, Oban, repo: CryptoDecisionLab.Repo

# Development connection, following the same layout as core_api/config/dev.exs.
config :crypto_decision_lab, CryptoDecisionLab.Repo,
  username: System.get_env("DB_USER", "postgres"),
  password: System.get_env("DB_PASSWORD", "093834"),
  hostname: System.get_env("DB_HOST", "localhost"),
  database: System.get_env("DB_NAME", "crypto"),
  port: String.to_integer(System.get_env("DB_PORT", "5432")),
  pool_size: String.to_integer(System.get_env("DB_POOL_SIZE", "10")),
  stacktrace: true,
  show_sensitive_data_on_connection_error: false

config :crypto_decision_lab, CryptoDecisionLabWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: false,
  watchers: []

# Jev and its Oban queue are configured together in runtime.exs.
# Start with ../../scripts/dev-api to load the local .env.jev opt-in.

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
