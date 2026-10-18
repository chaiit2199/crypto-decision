# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :crypto_decision_lab,
  ecto_repos: [CryptoDecisionLab.Repo],
  generators: [timestamp_type: :utc_datetime_usec],
  sync_enabled: false,
  price_poll_interval_ms: 300_000,
  analysis_interval_seconds: 900,
  binance_transport: CryptoDecisionLab.MarketData.Binance.Transport,
  clock: CryptoDecisionLab.Clock

# Configure the endpoint
config :crypto_decision_lab, CryptoDecisionLabWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: CryptoDecisionLabWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CryptoDecisionLab.PubSub,
  live_view: [signing_salt: "rt1uoftu"]

config :logger, utc_log: true

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: {CryptoDecisionLab.LogFormatter, :format},
  metadata: :all

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Runtime assembles independently enabled market and analysis queues/schedules.
config :crypto_decision_lab, Oban,
  repo: CryptoDecisionLab.Repo,
  queues: false,
  plugins: false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
