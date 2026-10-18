defmodule CryptoDecisionLab.SyncConfigTest do
  use ExUnit.Case, async: false

  @config_dir Path.expand("../../../config", __DIR__)
  @variables ~w(MARKET_SYNC_ENABLED DATABASE_URL SECRET_KEY_BASE TEST_DB_NAME DB_NAME JEV_ENABLED TYPESAFE_API_KEY JEV_MODEL)

  setup do
    previous = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)
    System.put_env("DATABASE_URL", "ecto://fixture:fixture@localhost/fixture_prod")
    System.put_env("SECRET_KEY_BASE", String.duplicate("fixture-only-", 8))

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    :ok
  end

  defp config(env) do
    base = Config.Reader.read!(Path.join(@config_dir, "config.exs"), env: env)
    runtime = Config.Reader.read!(Path.join(@config_dir, "runtime.exs"), env: env)
    Config.Reader.merge(base, runtime)[:crypto_decision_lab]
  end

  test "development starts the collector, queue and Cron by default" do
    config = config(:dev)
    assert config[:sync_enabled]
    assert config[Oban][:queues] == [market: 1]
    assert Keyword.has_key?(config[Oban][:plugins], Oban.Plugins.Cron)
  end

  test "development can explicitly disable all automatic collection" do
    System.put_env("MARKET_SYNC_ENABLED", "false")
    config = config(:dev)
    refute config[:sync_enabled]
    assert config[Oban][:queues] == false
    assert config[Oban][:plugins] == false
  end

  test "production requires explicit opt-in" do
    refute config(:prod)[:sync_enabled]
    assert config(:prod)[Oban][:queues] == false
    System.put_env("MARKET_SYNC_ENABLED", "true")
    assert config(:prod)[:sync_enabled]
    assert config(:prod)[Oban][:queues] == [market: 1]
  end

  test "tests never start collection even with development environment exported" do
    System.put_env("MARKET_SYNC_ENABLED", "true")
    System.put_env("JEV_ENABLED", "true")
    config = config(:test)
    refute config[:sync_enabled]
    assert config[Oban][:queues] == false
    assert config[Oban][:plugins] == false
    assert config[Oban][:testing] == :manual
    refute config[:jev][:enabled]
  end

  test "Jev runs independently on a five-minute Cron with its own queue" do
    System.put_env("MARKET_SYNC_ENABLED", "false")
    System.put_env("JEV_ENABLED", "true")
    config = config(:dev)
    assert config[:jev][:enabled]
    assert config[Oban][:queues] == [analysis: 1]
    cron = config[Oban][:plugins][Oban.Plugins.Cron][:crontab]
    assert cron == [{"*/5 * * * *", CryptoDecisionLab.Decisions.AnalysisWorker}]
  end

  test "Jev uses the exported credential and remains disabled without an explicit opt-in" do
    refute config(:dev)[:jev][:enabled]
    assert config(:dev)[:jev][:api_key] == nil
    System.put_env("TYPESAFE_API_KEY", "synthetic-config-key")
    System.put_env("JEV_ENABLED", "true")
    assert config(:dev)[:jev][:enabled]
    assert config(:dev)[:jev][:api_key] == "synthetic-config-key"
    System.put_env("JEV_ENABLED", "false")
    refute config(:dev)[:jev][:enabled]
  end
end
