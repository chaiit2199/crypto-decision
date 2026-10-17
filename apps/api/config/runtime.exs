import Config

is_test = config_env() == :test

if config_env() == :prod do
  # Production credentials are read at boot, including when running a release.
  database_config =
    case System.get_env("DATABASE_URL") do
      url when is_binary(url) and url != "" ->
        [url: url]

      _ ->
        [
          username: System.fetch_env!("DB_USER"),
          password: System.fetch_env!("DB_PASSWORD"),
          hostname: System.fetch_env!("DB_HOST"),
          database: System.fetch_env!("DB_NAME"),
          port: String.to_integer(System.get_env("DB_PORT", "5432"))
        ]
    end

  config :crypto_decision_lab, CryptoDecisionLab.Repo, database_config

  config :crypto_decision_lab, CryptoDecisionLab.Repo,
    pool_size:
      String.to_integer(System.get_env("DB_POOL_SIZE") || System.get_env("POOL_SIZE", "10")),
    show_sensitive_data_on_connection_error: false,
    socket_options: if(System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: [])
end

# Development is configured in dev.exs; runtime must not overwrite it.
if is_test do
  database = System.get_env("TEST_DB_NAME", "crypto_decision_lab_test")

  if not String.ends_with?(database, "_test") or database == System.get_env("DB_NAME") do
    raise "TEST_DB_NAME must end in _test and differ from DB_NAME"
  end

  config :crypto_decision_lab, CryptoDecisionLab.Repo,
    hostname: System.get_env("DB_HOST", "127.0.0.1"),
    port: String.to_integer(System.get_env("DB_PORT", "5433")),
    username: System.get_env("DB_USER", "crypto_decision"),
    password: System.get_env("DB_PASSWORD", ""),
    database: database,
    show_sensitive_data_on_connection_error: false
end

secret =
  if config_env() == :prod,
    do: System.fetch_env!("SECRET_KEY_BASE"),
    else: System.get_env("SECRET_KEY_BASE") || Base.encode64(:crypto.strong_rand_bytes(48))

config :crypto_decision_lab, CryptoDecisionLabWeb.Endpoint,
  secret_key_base: secret,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4000"))]

if System.get_env("PHX_SERVER") in ["true", "1"] do
  config :crypto_decision_lab, CryptoDecisionLabWeb.Endpoint, server: true
end

sync_default = if config_env() == :dev, do: "true", else: "false"
sync_enabled = not is_test and System.get_env("MARKET_SYNC_ENABLED", sync_default) == "true"

config :crypto_decision_lab,
  sync_enabled: sync_enabled,
  binance_base_url: System.get_env("BINANCE_BASE_URL", "https://data-api.binance.vision/api/v3")

# Analysis is independently enabled; tests never call the paid provider automatically.
jev_enabled = not is_test and System.get_env("JEV_ENABLED", "false") == "true"

config :crypto_decision_lab, :jev,
  enabled: jev_enabled,
  api_key:
    "apikey_26348e6614ce2444c44a810858bc7a2ebe4_455c0c46b6e2a3fc00023bc52a227a51bababd76fce302ef4e54fa62734f30fe",
  model: System.get_env("JEV_MODEL", "jev-latest")

market_cron =
  if sync_enabled do
    [
      {"0 0 * * *", CryptoDecisionLab.MarketData.SyncWorker, args: %{kind: "metadata"}},
      {"*/5 * * * *", CryptoDecisionLab.MarketData.SyncWorker, args: %{kind: "stats"}},
      {"1 * * * *", CryptoDecisionLab.MarketData.SyncWorker, args: %{kind: "candles"}},
      {"15 0 * * *", CryptoDecisionLab.MarketData.SyncWorker, args: %{kind: "integrity"}}
    ]
  else
    []
  end

analysis_cron =
  if jev_enabled, do: [{"*/5 * * * *", CryptoDecisionLab.Decisions.AnalysisWorker}], else: []

queues =
  if(sync_enabled, do: [market: 1], else: []) ++ if jev_enabled, do: [analysis: 1], else: []

plugins =
  if queues == [] do
    false
  else
    [
      {Oban.Plugins.Pruner, max_age: 604_800},
      {Oban.Plugins.Cron, crontab: market_cron ++ analysis_cron}
    ]
  end

config :crypto_decision_lab, Oban,
  queues: if(queues == [], do: false, else: queues),
  plugins: plugins
