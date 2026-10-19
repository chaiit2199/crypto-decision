"use client";

import { useEffect, useId, useRef, useState } from "react";

import type { Asset } from "@/lib/api/types";
import {
    formatDecimal,
    formatPercentage,
    priceStatus,
} from "@/lib/format/market";
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
                <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="16"
                    height="16"
                    viewBox="0 0 6.35 6.35"
                    aria-hidden="true"
                    focusable="false"
                >
                    <path
                        d="M2.894.511a2.384 2.384 0 0 0-2.38 2.38 2.386 2.386 0 0 0 2.38 2.384c.56 0 1.076-.197 1.484-.523l.991.991a.265.265 0 0 0 .375-.374l-.991-.992a2.37 2.37 0 0 0 .523-1.485C5.276 1.58 4.206.51 2.894.51m0 .53c1.026 0 1.852.825 1.852 1.85S3.92 4.746 2.894 4.746s-1.851-.827-1.851-1.853.825-1.852 1.851-1.852"
                        fill="currentColor"
                    />
                </svg>
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
                            const change =
                                market?.ticker_stats?.price_change_percent;

                            return (
                                <li key={asset.id}>
                                    <button
                                        type="button"
                                        role="option"
                                        aria-selected={active}
                                        className="watchlist-picker__option"
                                        data-active={active || undefined}
                                        onClick={() =>
                                            handleSelect(asset.symbol)
                                        }
                                    >
                                        <span className="watchlist-picker__symbol">
                                            <strong>{asset.symbol}</strong>
                                            <small>
                                                {market?.symbol ??
                                                    `Chưa có cặp ${quoteAsset}`}
                                            </small>
                                        </span>
                                        <span className="watchlist-picker__meta">
                                            <strong data-freshness={freshness}>
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
