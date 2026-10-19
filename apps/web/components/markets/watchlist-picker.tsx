"use client";

import { useEffect, useId, useRef, useState } from "react";

import type { Asset } from "@/lib/api/types";
import { formatDecimal, formatPercentage, priceStatus } from "@/lib/format/market";
import { selectedMarket } from "@/lib/markets/selected-market";
import type { QuoteAsset } from "@/lib/markets/selected-market";

type WatchlistPickerProps = {
    assets: Asset[];
    quoteAsset: QuoteAsset;
    selectedSymbol: string;
    now: number;
    onSelect: (symbol: string) => void;
};

export function WatchlistPicker({
    assets,
    quoteAsset,
    selectedSymbol,
    now,
    onSelect,
}: WatchlistPickerProps) {
    const [open, setOpen] = useState(false);
    const [query, setQuery] = useState("");
    const rootRef = useRef<HTMLDivElement>(null);
    const inputRef = useRef<HTMLInputElement>(null);
    const listId = useId();
    const search = query.trim().toLowerCase();
    const rows = assets.filter((asset) =>
        `${asset.symbol} ${asset.name} ${asset.markets.map((market) => market.symbol).join(" ")}`
            .toLowerCase()
            .includes(search),
    );

    useEffect(() => {
        if (!open) {
            return;
        }

        function handlePointer(event: MouseEvent) {
            if (!rootRef.current?.contains(event.target as Node)) {
                setOpen(false);
            }
        }

        function handleKey(event: KeyboardEvent) {
            if (event.key === "Escape") {
                setOpen(false);
            }
        }

        document.addEventListener("mousedown", handlePointer);
        document.addEventListener("keydown", handleKey);
        inputRef.current?.focus();

        return () => {
            document.removeEventListener("mousedown", handlePointer);
            document.removeEventListener("keydown", handleKey);
        };
    }, [open]);

    function handleSelect(symbol: string) {
        onSelect(symbol);
        setQuery("");
        setOpen(false);
    }

    return (
        <div className="watchlist-picker" ref={rootRef}>
            <button
                type="button"
                className="watchlist-picker__trigger"
                aria-expanded={open}
                aria-controls={listId}
                aria-haspopup="listbox"
                aria-label="Tìm trong danh mục theo dõi"
                onClick={() => setOpen((value) => !value)}
            >
                <span aria-hidden="true">⌕</span>
                <span>Danh mục</span>
            </button>

            {open && (
                <div
                    className="watchlist-picker__panel"
                    id={listId}
                    role="listbox"
                    aria-label="Danh mục theo dõi"
                >
                    <label className="watchlist-picker__search">
                        <span className="sr-only">Tìm tài sản</span>
                        <input
                            ref={inputRef}
                            type="search"
                            value={query}
                            placeholder="Tìm BTC, ETH…"
                            onChange={(event) => setQuery(event.target.value)}
                        />
                    </label>

                    <ul className="watchlist-picker__list">
                        {rows.length === 0 && (
                            <li className="watchlist-picker__empty">
                                Không tìm thấy tài sản phù hợp.
                            </li>
                        )}
                        {rows.map((asset) => {
                            const market = selectedMarket(asset, quoteAsset);
                            const active = asset.symbol === selectedSymbol;
                            const freshness = priceStatus(market, now);
                            const change = market?.ticker_stats?.price_change_percent;

                            return (
                                <li key={asset.id}>
                                    <button
                                        type="button"
                                        role="option"
                                        aria-selected={active}
                                        className="watchlist-picker__option"
                                        data-active={active || undefined}
                                        onClick={() => handleSelect(asset.symbol)}
                                    >
                                        <span className="watchlist-picker__symbol">
                                            <strong>{asset.symbol}</strong>
                                            <small>
                                                {market?.symbol ??
                                                    `Chưa có cặp ${quoteAsset}`}
                                            </small>
                                        </span>
                                        <span className="watchlist-picker__meta">
                                            <strong
                                                data-freshness={freshness}
                                            >
                                                {formatDecimal(
                                                    market?.latest_price?.price,
                                                )}
                                            </strong>
                                            <small
                                                data-direction={
                                                    change?.startsWith("-")
                                                        ? "down"
                                                        : "up"
                                                }
                                            >
                                                {change
                                                    ? `${formatPercentage(change)}%`
                                                    : "—"}
                                            </small>
                                        </span>
                                    </button>
                                </li>
                            );
                        })}
                    </ul>
                </div>
            )}
        </div>
    );
}
