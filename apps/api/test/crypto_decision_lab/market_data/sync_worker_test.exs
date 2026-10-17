defmodule CryptoDecisionLab.MarketData.SyncWorkerTest do
  use CryptoDecisionLab.DataCase
  alias CryptoDecisionLab.MarketData.{SyncWorker, Candle}
  alias CryptoDecisionLab.MarketFixtures, as: F

  setup do
    F.configure()
  end

  test "bootstrap persists unique jobs without executing them synchronously" do
    F.queue([F.response(F.exchange()), F.response(F.exchange())])
    job = %Oban.Job{args: %{"kind" => "bootstrap"}}
    assert :ok = SyncWorker.perform(job)
    assert :ok = SyncWorker.perform(job)
    assert Repo.aggregate(Oban.Job, :count) == 3
    assert Repo.aggregate(Candle, :count) == 0

    jobs = Repo.all(from j in Oban.Job, order_by: [j.priority, j.id])
    assert Enum.map(jobs, & &1.args["kind"]) == ["prices", "stats", "backfill"]
    assert Enum.map(jobs, & &1.priority) == [0, 0, 3]
  end

  test "durable backfill snoozes after a full page and rate limiting does not retry immediately" do
    symbol = F.symbol()
    first = F.start() - 1000 * F.hour()
    F.queue([F.response(for n <- 0..999, do: F.kline(first + n * F.hour()))])
    job = %Oban.Job{args: %{"kind" => "backfill", "symbol_id" => symbol.id}}
    assert {:snooze, 1} = SyncWorker.perform(job)
    assert Repo.aggregate(Candle, :count) == 1000
    F.queue([F.response(%{}, 429, %{"retry-after" => ["45"]})])
    assert {:snooze, 45} = SyncWorker.perform(job)
    assert {:snooze, _} = SyncWorker.perform(job)
    assert length(Process.get(:http_calls)) == 2
  end
end
