defmodule CryptoDecisionLab.TradingKnowledge.Outcomes do
  @moduledoc false
  alias CryptoDecisionLab.Repo
  alias CryptoDecisionLab.TradingKnowledge.{AIDecision, Outcome, Snapshot}
  alias Decimal, as: D

  def record(decision_id, attrs) do
    with %AIDecision{} = decision <- Repo.get(AIDecision, decision_id),
         {:ok, entry_at} <- Snapshot.time(attrs["entry_at"]),
         {:ok, exit_at} <- Snapshot.time(attrs["exit_at"]),
         {:ok, observed_at} <- Snapshot.time(attrs["observed_at"]),
         true <-
           DateTime.compare(decision.decision_at, entry_at) == :lt and
             DateTime.compare(entry_at, exit_at) == :lt,
         true <-
           DateTime.compare(exit_at, observed_at) != :gt and
             DateTime.compare(observed_at, DateTime.utc_now()) != :gt,
         {:ok, entry} <- Snapshot.decimal(attrs["entry_price"]),
         {:ok, exit} <- Snapshot.decimal(attrs["exit_price"]),
         {:ok, fee} <- Snapshot.decimal(get_in(attrs, ["costs", "fee_bps_per_side"])),
         {:ok, slip} <- Snapshot.decimal(get_in(attrs, ["costs", "slippage_bps_per_side"])),
         true <-
           D.compare(entry, 0) == :gt and D.compare(exit, 0) == :gt and D.compare(fee, 0) != :lt and
             D.compare(slip, 0) != :lt,
         cost = D.div(D.add(fee, slip), 10_000),
         true <- D.compare(cost, 1) == :lt,
         true <-
           is_map(attrs["lineage"]) and is_binary(attrs["lineage"]["dataset_hash"]) and
             Regex.match?(~r/^[a-f0-9]{64}$/, attrs["lineage"]["dataset_hash"]),
         horizon = DateTime.diff(exit_at, entry_at),
         true <-
           horizon > 0 and DateTime.diff(exit_at, entry_at, :microsecond) == horizon * 1_000_000 do
      net = D.sub(D.div(D.mult(exit, D.sub(1, cost)), D.mult(entry, D.add(1, cost))), 1)

      record = %Outcome{
        decision_id: decision_id,
        horizon_seconds: horizon,
        decision_at: decision.decision_at,
        entry_at: entry_at,
        exit_at: exit_at,
        observed_at: observed_at,
        entry_price: entry,
        exit_price: exit,
        net_return: net,
        costs: attrs["costs"],
        lineage:
          Map.put(
            attrs["lineage"],
            "meaning",
            "Forward long-return label; not proof of an executed trade."
          )
      }

      record
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint([:decision_id, :horizon_seconds])
      |> Repo.insert()
    else
      _ -> {:error, :invalid_outcome}
    end
  end
end
