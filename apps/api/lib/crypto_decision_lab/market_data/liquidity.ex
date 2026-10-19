defmodule CryptoDecisionLab.MarketData.Liquidity do
  @moduledoc "Same-snapshot spread, depth and bounded hypothetical fills; never an execution quote."
  alias CryptoDecisionLab.Repo

  alias CryptoDecisionLab.MarketData.{
    Asset,
    Symbol,
    Binance,
    Collector,
    Parser,
    LiquiditySnapshot
  }

  alias Decimal, as: D

  @spec sync(integer()) :: {:ok, term()} | {:error, term()}
  def sync(id) do
    Collector.run(fn ->
      symbol = Repo.get(Symbol, id)
      existing = Repo.get(LiquiditySnapshot, id)
      now = Collector.now()

      cond do
        is_nil(symbol) or symbol.exchange != "binance" or not symbol.enabled or
          symbol.trading_status != "TRADING" or not Repo.get!(Asset, symbol.asset_id).enabled ->
          {:error, :symbol_unavailable}

        existing && DateTime.diff(now, existing.fetched_at) in 0..59 ->
          {:ok, :not_due}

        true ->
          with {:ok, response} <- Binance.depth(symbol.symbol),
               {:ok, _} <- parse(response.body) do
            if is_nil(existing) or
                 DateTime.compare(response.fetched_at, existing.fetched_at) == :gt do
              Repo.insert_all(
                LiquiditySnapshot,
                [
                  %{
                    market_symbol_id: id,
                    book: response.body,
                    data_at: response.server_time,
                    fetched_at: response.fetched_at
                  }
                ],
                conflict_target: [:market_symbol_id],
                on_conflict: {:replace, [:book, :data_at, :fetched_at]}
              )
            end

            {:ok, :stored}
          end
      end
    end)
  end

  @spec parse(term()) :: {:ok, map()} | {:error, atom()}
  def parse(%{"lastUpdateId" => id, "bids" => bids, "asks" => asks})
      when is_integer(id) and id >= 0 do
    with {:ok, bids} <- levels(bids, :gt),
         {:ok, asks} <- levels(asks, :lt),
         true <- D.compare(hd(bids).price, hd(asks).price) == :lt do
      bid = hd(bids).price
      ask = hd(asks).price
      bid_depth = total(bids)
      ask_depth = total(asks)

      {:ok,
       %{
         bids: bids,
         asks: asks,
         bid: bid,
         ask: ask,
         spread_percent: D.mult(D.div(D.sub(ask, bid), D.div(D.add(ask, bid), 2)), 100),
         bid_depth: bid_depth,
         ask_depth: ask_depth,
         imbalance: D.div(D.sub(bid_depth, ask_depth), D.add(bid_depth, ask_depth))
       }}
    else
      _ -> {:error, :invalid_order_book}
    end
  end

  def parse(_), do: {:error, :invalid_order_book}

  defp levels(rows, direction) when is_list(rows) and length(rows) in 1..100 do
    parsed =
      Enum.reduce_while(rows, {:ok, []}, fn
        [price, quantity], {:ok, acc} ->
          with {:ok, p} <- Parser.decimal(price),
               {:ok, q} <- Parser.decimal(quantity),
               true <- D.positive?(p) and D.positive?(q) do
            {:cont, {:ok, [%{price: p, quantity: q} | acc]}}
          else
            _ -> {:halt, {:error, :invalid_order_book}}
          end

        _, _ ->
          {:halt, {:error, :invalid_order_book}}
      end)

    with {:ok, values} <- parsed do
      values = Enum.reverse(values)

      if Enum.all?(Enum.chunk_every(values, 2, 1, :discard), fn [a, b] ->
           D.compare(a.price, b.price) == direction
         end),
         do: {:ok, values},
         else: {:error, :invalid_order_book}
    end
  end

  defp levels(_, _), do: {:error, :invalid_order_book}
  defp total(levels), do: Enum.reduce(levels, D.new(0), &D.add(&2, D.mult(&1.price, &1.quantity)))

  @doc "Walk an entire requested base quantity; insufficient depth never produces a partial success."
  @spec fill([map()], Decimal.t()) :: {:ok, Decimal.t()} | {:error, atom()}
  def fill(levels, quantity) do
    if D.positive?(quantity) do
      {remaining, cost} =
        Enum.reduce(levels, {quantity, D.new(0)}, fn row, {left, total} ->
          take = D.min(left, row.quantity)
          {D.sub(left, take), D.add(total, D.mult(take, row.price))}
        end)

      if D.equal?(remaining, 0),
        do: {:ok, D.div(cost, quantity)},
        else: {:error, :insufficient_depth}
    else
      {:error, :invalid_quantity}
    end
  end
end
