export type PriceDirection = "up" | "down" | null;

/** Compare positive decimal API strings without losing sub-cent precision. */
export function priceDirection(previous: string | undefined, current: string | undefined): PriceDirection {
    if (previous === undefined || current === undefined) {
        return null;
    }

    const [previousWhole, previousFraction = ""] = previous.split(".");
    const [currentWhole, currentFraction = ""] = current.split(".");
    const precision = Math.max(previousFraction.length, currentFraction.length);
    const before = BigInt(previousWhole + previousFraction.padEnd(precision, "0"));
    const after = BigInt(currentWhole + currentFraction.padEnd(precision, "0"));

    if (after === before) {
        return null;
    }

    return after > before ? "up" : "down";
}
