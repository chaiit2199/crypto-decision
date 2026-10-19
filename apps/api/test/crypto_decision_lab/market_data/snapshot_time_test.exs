defmodule CryptoDecisionLab.MarketData.SnapshotTimeTest do
  use ExUnit.Case, async: true
  alias CryptoDecisionLab.MarketData.SnapshotTime

  test "snapshot skew is bounded to 60 seconds without extending stale data lifetime" do
    now = ~U[2026-10-19 01:00:00.000000Z]

    for offset <- [0, 41_000, 60_000, -600_000] do
      assert SnapshotTime.fresh?(DateTime.add(now, offset, :millisecond), now, 600)
    end

    for offset <- [60_001, 61_000, -600_001] do
      refute SnapshotTime.fresh?(DateTime.add(now, offset, :millisecond), now, 600)
    end

    refute SnapshotTime.future?(DateTime.add(now, 60), now)
    assert SnapshotTime.future?(DateTime.add(now, 60_001, :millisecond), now)
  end
end
