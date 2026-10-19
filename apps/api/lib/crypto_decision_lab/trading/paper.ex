defmodule CryptoDecisionLab.Trading.Paper do
  @moduledoc "Manual Spot paper scenarios at fresh same-market depth. Append-only; no exchange execution."
  import Ecto.Query
  alias CryptoDecisionLab.Repo
  alias CryptoDecisionLab.Trading.{Plan, Simulation}

  alias CryptoDecisionLab.MarketData.{
    Symbol,
    Asset,
    LiquiditySnapshot,
    Liquidity,
    Collector,
    SnapshotTime
  }

  alias Decimal, as: D

  @doc "Open an explicitly hypothetical position from user stop/target/capital assumptions."
  @spec open(integer(), map()) :: {:ok, Simulation.t()} | {:error, term()}
  def open(symbol_id, input) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(764220, $1)", [symbol_id])

      with {:ok, book, at} <- book(symbol_id),
           {:ok, plan} <- Plan.calculate(Map.put(input, "entry", decimal(book.ask))),
           {:ok, average} <- Liquidity.fill(book.asks, D.new(plan["quantity"])) do
        impact = D.mult(D.sub(D.div(average, book.ask), 1), 100)

        if D.compare(impact, input["slippage_percent"]) == :gt,
          do: Repo.rollback(:slippage_exceeds_assumption)

        report =
          Map.merge(plan, %{
            "mode" => "paper",
            "event" => "OPEN",
            "observed_at" => DateTime.to_iso8601(at),
            "depth_average" => decimal(average),
            "validation" => "UNVALIDATED"
          })

        Repo.insert!(%Simulation{market_symbol_id: symbol_id, kind: "paper", report: report})
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Close once at a fresh bid snapshot. Costs remain explicit conservative assumptions."
  @spec close(integer()) :: {:ok, Simulation.t()} | {:error, term()}
  def close(id) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(764221, $1)", [id])
      row = Repo.get(Simulation, id)

      cond do
        is_nil(row) or row.kind != "paper" or row.report["event"] != "OPEN" ->
          Repo.rollback(:not_found)

        Repo.exists?(
          from s in Simulation,
            where: s.kind == "paper" and fragment("?->>'open_id' = ?", s.report, ^to_string(id))
        ) ->
          Repo.rollback(:already_closed)

        true ->
          with {:ok, book, at} <- book(row.market_symbol_id),
               true <-
                 DateTime.compare(at, DateTime.from_iso8601(row.report["observed_at"]) |> elem(1)) ==
                   :gt,
               {:ok, average} <- Liquidity.fill(book.bids, D.new(row.report["quantity"])) do
            p = row.report
            impact = D.mult(D.sub(1, D.div(average, book.bid)), 100)
            # Use the worse of configured exit slippage and observed depth impact.
            extra = D.max(D.sub(impact, p["slippage_percent"]), 0)

            pnl =
              D.sub(
                D.sub(D.mult(D.sub(book.bid, p["entry"]), p["quantity"]), p["estimated_cost"]),
                D.div(D.mult(p["notional"], extra), 100)
              )

            report = %{
              "mode" => "paper",
              "event" => "CLOSE",
              "open_id" => id,
              "observed_at" => DateTime.to_iso8601(at),
              "exit" => decimal(book.bid),
              "depth_average" => decimal(average),
              "net_pnl" => decimal(pnl),
              "execution_allowed" => false,
              "validation" => "UNVALIDATED"
            }

            Repo.insert!(%Simulation{
              market_symbol_id: row.market_symbol_id,
              kind: "paper",
              report: report
            })
          else
            false -> Repo.rollback(:new_snapshot_required)
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  defp book(id) do
    now = Collector.now()

    with %Symbol{exchange: "binance", enabled: true, trading_status: "TRADING"} = symbol <-
           Repo.get(Symbol, id),
         %Asset{enabled: true} <- Repo.get(Asset, symbol.asset_id),
         %LiquiditySnapshot{} = row <- Repo.get(LiquiditySnapshot, id),
         true <-
           SnapshotTime.fresh?(row.fetched_at, now, 90) and
             SnapshotTime.fresh?(row.data_at, now, 90),
         {:ok, book} <- Liquidity.parse(row.book) do
      {:ok, book, row.fetched_at}
    else
      _ -> {:error, :fresh_liquidity_required}
    end
  end

  defp decimal(value), do: value |> D.normalize() |> D.to_string(:normal)
end
