defmodule CryptoDecisionLab.SyncConfigTest do
  use ExUnit.Case, async: false

  @config_dir Path.expand("../../../config", __DIR__)
  @variables ~w(MARKET_SYNC_ENABLED DATABASE_URL SECRET_KEY_BASE TEST_DB_NAME DB_NAME JEV_ENABLED TYPESAFE_API_KEY JEV_MODEL JEV_ENV_FILE)

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    previous = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)
    System.put_env("DATABASE_URL", "ecto://fixture:fixture@localhost/fixture_prod")
    System.put_env("SECRET_KEY_BASE", String.duplicate("fixture-only-", 8))
    System.put_env("JEV_ENV_FILE", Path.join(tmp_dir, ".env.jev"))

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
    assert config[Oban][:queues] == [market: 1, sources: 1]
    assert Keyword.has_key?(config[Oban][:plugins], Oban.Plugins.Cron)

    assert {"*/5 * * * *", CryptoDecisionLab.MarketData.SyncWorker, args: %{kind: "stats"}} in config[
             Oban
           ][:plugins][Oban.Plugins.Cron][:crontab]
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
    assert config(:prod)[Oban][:queues] == [market: 1, sources: 1]
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

  test "Jev dispatcher runs each minute with its own queue and configured slots" do
    System.put_env("MARKET_SYNC_ENABLED", "false")
    System.put_env("JEV_ENABLED", "true")
    config = config(:dev)
    assert config[:jev][:enabled]
    assert config[Oban][:queues] == [analysis: 1]
    cron = config[Oban][:plugins][Oban.Plugins.Cron][:crontab]
    assert cron == [{"* * * * *", CryptoDecisionLab.Decisions.AnalysisWorker}]
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

  test "development intervals come from dev.exs while other environments retain their defaults" do
    assert config(:dev)[:price_poll_interval_ms] == 300_000
    assert config(:dev)[:analysis_interval_seconds] == 900

    for env <- [:test, :prod] do
      assert config(env)[:price_poll_interval_ms] == 300_000
      assert config(env)[:analysis_interval_seconds] == 900
    end
  end

  test "development loads local Jev opt-in, credential and model into the same scheduled config" do
    File.write!(System.fetch_env!("JEV_ENV_FILE"), """
    # Synthetic credentials only
    export JEV_ENABLED=true
    TYPESAFE_API_KEY="synthetic-local-key" # local fixture
    JEV_MODEL='fixture-model'
    """)

    config = config(:dev)
    assert config[:jev] == [enabled: true, api_key: "synthetic-local-key", model: "fixture-model"]
    assert config[Oban][:queues][:analysis] == 1

    assert {"* * * * *", CryptoDecisionLab.Decisions.AnalysisWorker} in config[Oban][:plugins][
             Oban.Plugins.Cron
           ][:crontab]

    System.put_env("JEV_ENABLED", "false")
    System.put_env("TYPESAFE_API_KEY", "")
    System.put_env("JEV_MODEL", "exported-model")
    config = config(:dev)
    refute config[:jev][:enabled]
    assert config[:jev][:api_key] == ""
    assert config[:jev][:model] == "exported-model"
    refute Keyword.has_key?(config[Oban][:queues], :analysis)
  end

  test "production and test ignore local Jev settings" do
    File.write!(
      System.fetch_env!("JEV_ENV_FILE"),
      "JEV_ENABLED=true\nTYPESAFE_API_KEY=fixture-key\n"
    )

    for env <- [:prod, :test] do
      config = config(env)
      refute config[:jev][:enabled]
      assert config[:jev][:api_key] == nil
      assert config[Oban][:queues] == false
    end
  end

  test "invalid local assignment reports its line without exposing its value" do
    File.write!(
      System.fetch_env!("JEV_ENV_FILE"),
      "# fixture\nTYPESAFE_API_KEY=$(fixture-secret)\n"
    )

    assert_raise RuntimeError, "Invalid Jev assignment in JEV_ENV_FILE at line 2", fn ->
      config(:dev)
    end
  end
end
