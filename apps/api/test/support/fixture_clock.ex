defmodule CryptoDecisionLab.FixtureClock do
  def now, do: Process.get(:now, CryptoDecisionLab.MarketFixtures.now())
end
