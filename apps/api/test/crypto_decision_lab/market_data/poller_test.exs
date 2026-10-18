defmodule CryptoDecisionLab.MarketData.PollerTest do
  use ExUnit.Case
  alias CryptoDecisionLab.MarketData.Poller

  test "a busy collector retries before the next interval without overlapping work" do
    parent = self()

    run = fn ->
      send(parent, {:started, self()})

      receive do
        {:finish, result} -> result
      end
    end

    pid =
      start_supervised!(
        {Poller,
         name: :busy_poller,
         enabled: true,
         interval: 60_000,
         retry_interval: 10,
         bootstrap: false,
         run: run}
      )

    assert_receive {:started, first}
    send(first, {:finish, {:error, :collector_busy}})
    assert_receive {:started, second}, 200
    send(pid, :retry_tick)
    send(pid, :tick)
    _ = :sys.get_state(pid)
    refute_receive {:started, _}, 30
    send(second, {:finish, {:ok, :not_due}})
    refute_receive {:started, _}, 30
  end

  test "a slow poll never overlaps and polling resumes after completion" do
    parent = self()

    run = fn ->
      send(parent, {:started, self()})

      receive do
        :finish -> {:ok, :done}
      end
    end

    pid =
      start_supervised!(
        {Poller, name: :test_poller, enabled: true, interval: 20, bootstrap: false, run: run}
      )

    assert_receive {:started, first}
    refute_receive {:started, _}, 80
    send(first, :finish)
    assert_receive {:started, second}, 200
    assert first != second
    GenServer.stop(pid)
    ref = Process.monitor(second)
    assert_receive {:DOWN, ^ref, :process, ^second, _}
  end

  test "the supervised timer uses the configured price interval" do
    previous = Application.fetch_env!(:crypto_decision_lab, :price_poll_interval_ms)
    Application.put_env(:crypto_decision_lab, :price_poll_interval_ms, 60_000)

    on_exit(fn ->
      Application.put_env(:crypto_decision_lab, :price_poll_interval_ms, previous)
    end)

    pid = start_supervised!({Poller, name: :configured_poller, enabled: false})
    assert :sys.get_state(pid).interval == 60_000
  end
end
