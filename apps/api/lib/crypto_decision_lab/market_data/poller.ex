defmodule CryptoDecisionLab.MarketData.Poller do
  @moduledoc "Configurable monotonic scheduler; one monitored task at a time, plus a shared DB deadline."
  use GenServer
  require Logger
  alias CryptoDecisionLab.MarketData.{Sync, SyncWorker}

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    enabled =
      Keyword.get(opts, :enabled, Application.get_env(:crypto_decision_lab, :sync_enabled, false))

    state = %{
      enabled: enabled,
      interval:
        Keyword.get(
          opts,
          :interval,
          Application.fetch_env!(:crypto_decision_lab, :price_poll_interval_ms)
        ),
      retry_interval: Keyword.get(opts, :retry_interval, 1_000),
      retry_timer: nil,
      task: nil,
      run: Keyword.get(opts, :run, &Sync.poll/0),
      next: System.monotonic_time(:millisecond)
    }

    if enabled do
      send(self(), :tick)
      if Keyword.get(opts, :bootstrap, true), do: send(self(), :bootstrap)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:bootstrap, state) do
    SyncWorker.enqueue(%{kind: "bootstrap"})
    {:noreply, state}
  end

  def handle_info(message, %{enabled: true, task: nil} = state)
      when message in [:tick, :retry_tick] do
    if state.retry_timer, do: Process.cancel_timer(state.retry_timer)
    task = Task.Supervisor.async_nolink(CryptoDecisionLab.TaskSupervisor, state.run)
    state = %{state | task: task, retry_timer: nil}
    {:noreply, if(message == :tick, do: schedule(state), else: state)}
  end

  def handle_info(:tick, %{enabled: true} = state), do: {:noreply, schedule(state)}

  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    state = %{state | task: nil}

    if result == {:error, :collector_busy} do
      # Retry lock acquisition soon during backfill. Sync.poll/0 still enforces
      # the shared configured deadline before making any Binance request.
      timer = Process.send_after(self(), :retry_tick, state.retry_interval)
      {:noreply, %{state | retry_timer: timer}}
    else
      if match?({:error, _}, result),
        do: Logger.warning("price_poll_failed", reason: inspect(result))

      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: %Task{ref: ref}} = state) do
    Logger.error("price_poll_crashed", reason: inspect(reason))
    {:noreply, %{state | task: nil}}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp schedule(state) do
    now = System.monotonic_time(:millisecond)
    # Skip missed deadlines instead of creating a backlog after a slow request.
    next = state.next + (div(max(now - state.next, 0), state.interval) + 1) * state.interval
    Process.send_after(self(), :tick, max(next - now, 0))
    %{state | next: next}
  end

  @impl true
  def terminate(_reason, %{task: %Task{} = task}), do: Task.shutdown(task, :brutal_kill)
  def terminate(_, _), do: :ok
end
