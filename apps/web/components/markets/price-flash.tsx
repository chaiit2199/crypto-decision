"use client";

import { useEffect, useRef } from "react";

import { formatDecimal } from "@/lib/format/market";
import { priceDirection } from "@/lib/markets/price-change";

type PriceFlashProps = {
    value: string | undefined;
};

export function PriceFlash({ value }: PriceFlashProps) {
    const previous = useRef(value);
    const elementRef = useRef<HTMLSpanElement>(null);

    useEffect(() => {
        const direction = priceDirection(previous.current, value);
        previous.current = value;
        const element = elementRef.current;

        if (!element) {
            return;
        }

        element.dataset.direction = "unchanged";

        if (direction) {
            // Flush the cleared CSS animation so consecutive increases/decreases
            // replay it without remounting the price or changing state during render.
            element.getBoundingClientRect();
            element.dataset.direction = direction;
        }
    }, [value]);

    return (
        <span ref={elementRef} className="price-flash" data-direction="unchanged">
            {formatDecimal(value)}
        </span>
    );
}
