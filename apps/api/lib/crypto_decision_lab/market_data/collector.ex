defmodule CryptoDecisionLab.MarketData.Collector do
  @moduledoc "Serializes collection across nodes using a PostgreSQL transaction advisory lock."
  import Ecto.Query
  alias CryptoDecisionLab.Repo
  alias CryptoDecisionLab.MarketData.CollectorState
  @key "binance_spot"
  @lock 7_413_201

  def now, do: Application.fetch_env!(:crypto_decision_lab, :clock).now()

  @spec run((-> term())) :: term()
  def run(fun) do
    case Repo.transaction(
           fn ->
             case Repo.query!("SELECT pg_try_advisory_xact_lock($1)", [@lock]).rows do
               [[true]] ->
                 Repo.insert_all(CollectorState, [%{key: @key, updated_at: now()}],
                   on_conflict: :nothing
                 )

                 fun.()

               [[false]] ->
                 {:error, :collector_busy}
             end
           end,
           timeout: 120_000
         ) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  def state, do: Repo.get(CollectorState, @key)

  def update(attrs) do
    Repo.update_all(from(s in CollectorState, where: s.key == @key),
      set: Map.to_list(Map.put(attrs, :updated_at, now()))
    )

    :ok
  end

  def reserve(weight, timestamp) do
    state = state()
    window = div(DateTime.to_unix(timestamp), 60)
    used = if state.weight_window == window, do: state.used_weight, else: 0

    cond do
      state.blocked_until && DateTime.compare(state.blocked_until, timestamp) == :gt ->
        {:error, {:cooldown, DateTime.diff(state.blocked_until, timestamp) + 1}}

      used + weight > state.weight_limit ->
        {:error, {:cooldown, 61 - rem(DateTime.to_unix(timestamp), 60)}}

      true ->
        update(%{weight_window: window, used_weight: used + weight})
    end
  end

  def observe(headers, timestamp) do
    case Map.get(headers, "x-mbx-used-weight-1m", []) do
      [value | _] ->
        case Integer.parse(value) do
          {weight, ""} ->
            state = state()
            window = div(DateTime.to_unix(timestamp), 60)

            used =
              if state.weight_window == window, do: max(state.used_weight, weight), else: weight

            update(%{weight_window: window, used_weight: used})

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end

  def block(seconds, status) do
    update(%{blocked_until: DateTime.add(now(), seconds), last_error: "http_#{status}"})
  end
end
