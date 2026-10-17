defmodule CryptoDecisionLab.DatabaseConfigTest do
  use ExUnit.Case, async: false

  @config_dir Path.expand("../../../config", __DIR__)
  @variables ~w(DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME DB_POOL_SIZE DATABASE_URL
                POOL_SIZE ECTO_IPV6 TEST_DB_NAME SECRET_KEY_BASE)

  setup do
    previous = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    :ok
  end

  defp read_repo(file, env) do
    @config_dir
    |> Path.join(file)
    |> Config.Reader.read!(env: env)
    |> Keyword.get(:crypto_decision_lab, [])
    |> Keyword.get(CryptoDecisionLab.Repo)
  end

  defp production_credentials do
    System.put_env(%{
      "DB_HOST" => "database.example.invalid",
      "DB_USER" => "fixture_user",
      "DB_PASSWORD" => "synthetic-test-password",
      "DB_NAME" => "fixture_prod",
      "SECRET_KEY_BASE" => String.duplicate("fixture-only-", 8)
    })
  end

  test "dev reads connection fields from the environment" do
    System.put_env(%{
      "DB_HOST" => "dev.example.invalid",
      "DB_PORT" => "5432",
      "DB_USER" => "fixture_dev",
      "DB_PASSWORD" => "synthetic-test-password",
      "DB_NAME" => "fixture_dev",
      "DB_POOL_SIZE" => "7"
    })

    config = read_repo("dev.exs", :dev)
    assert config[:hostname] == "dev.example.invalid"
    assert config[:username] == "fixture_dev"
    assert config[:database] == "fixture_dev"
    assert config[:port] == 5432
    assert config[:pool_size] == 7
    assert config[:stacktrace]
    refute config[:show_sensitive_data_on_connection_error]
  end

  test "runtime does not overwrite the development repo configuration" do
    System.put_env("DATABASE_URL", "ecto://fixture:password@prod.example.invalid/fixture_prod")
    assert read_repo("runtime.exs", :dev) == nil
  end

  test "production supports explicit connection fields at runtime" do
    production_credentials()
    System.put_env("DB_POOL_SIZE", "15")
    System.put_env("ECTO_IPV6", "true")
    config = read_repo("runtime.exs", :prod)
    assert config[:hostname] == "database.example.invalid"
    assert config[:username] == "fixture_user"
    assert config[:database] == "fixture_prod"
    assert config[:password] == "synthetic-test-password"
    assert config[:port] == 5432
    assert config[:pool_size] == 15
    assert config[:socket_options] == [:inet6]
    refute config[:show_sensitive_data_on_connection_error]
  end

  test "production URL takes precedence and preserves legacy POOL_SIZE" do
    production_credentials()
    url = "ecto://fixture:password@url.example.invalid/fixture_prod"
    System.put_env("DATABASE_URL", url)
    System.put_env("POOL_SIZE", "12")
    config = read_repo("runtime.exs", :prod)
    assert config[:url] == url
    refute Keyword.has_key?(config, :hostname)
    assert config[:pool_size] == 12

    System.put_env("DB_POOL_SIZE", "6")
    assert read_repo("runtime.exs", :prod)[:pool_size] == 6
  end

  test "production fails when required connection fields are missing" do
    production_credentials()
    System.delete_env("DB_HOST")
    assert_raise System.EnvError, fn -> read_repo("runtime.exs", :prod) end
  end

  test "test database ignores DATABASE_URL and retains the name guard" do
    System.put_env("DATABASE_URL", "ecto://fixture:password@prod.example.invalid/fixture_prod")
    config = read_repo("runtime.exs", :test)
    assert config[:database] == "crypto_decision_lab_test"
    refute Keyword.has_key?(config, :url)

    System.put_env("TEST_DB_NAME", "fixture_prod")

    assert_raise RuntimeError, ~r/TEST_DB_NAME must end in _test/, fn ->
      read_repo("runtime.exs", :test)
    end
  end
end
