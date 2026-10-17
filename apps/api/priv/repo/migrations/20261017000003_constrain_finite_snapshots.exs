defmodule CryptoDecisionLab.Repo.Migrations.ConstrainFiniteSnapshots do
  use Ecto.Migration

  def change do
    for {table, fields} <- [
          market_latest_prices: [:price],
          market_ticker_stats: [
            :price_change,
            :price_change_percent,
            :high_price,
            :low_price,
            :base_volume,
            :quote_volume
          ]
        ],
        field <- fields do
      create constraint(table, String.to_atom("finite_#{field}"),
               check:
                 "#{field} NOT IN ('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)"
             )
    end
  end
end
