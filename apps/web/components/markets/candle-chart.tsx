"use client";

import { CandlestickSeries, ColorType, HistogramSeries, LineStyle, createChart } from "lightweight-charts";
import type { IChartApi, IPriceLine, ISeriesApi, UTCTimestamp } from "lightweight-charts";
import { useEffect, useRef } from "react";

import type { Candle } from "@/lib/api/types";
import { formatChartTick, formatChartTime } from "@/lib/format/chart-time";

type CandleChartProps = {
    candles: Candle[];
    symbol: string;
    snapshotPrice: string | undefined;
};

type ChartInstance = {
    chart: IChartApi;
    prices: ISeriesApi<"Candlestick">;
    volume: ISeriesApi<"Histogram">;
    snapshot: IPriceLine | null;
    fitted: boolean;
};

export function CandleChart({ candles, symbol, snapshotPrice }: CandleChartProps) {
    const containerRef = useRef<HTMLDivElement>(null);
    const instance = useRef<ChartInstance | null>(null);

    useEffect(() => {
        if (!containerRef.current) {
            return;
        }

        const styles = getComputedStyle(containerRef.current);
        const positive = styles.getPropertyValue("--positive").trim();
        const negative = styles.getPropertyValue("--negative").trim();
        const chart = createChart(containerRef.current, {
            autoSize: true,
            layout: {
                background: { type: ColorType.Solid, color: styles.getPropertyValue("--surface").trim() },
                textColor: styles.getPropertyValue("--muted").trim(),
                attributionLogo: true,
            },
            grid: {
                vertLines: { color: styles.getPropertyValue("--border").trim() },
                horzLines: { color: styles.getPropertyValue("--border").trim() },
            },
            timeScale: {
                timeVisible: true,
                secondsVisible: false,
                borderVisible: false,
                tickMarkFormatter: formatChartTick,
            },
            rightPriceScale: { borderVisible: false },
            localization: { locale: "vi-VN", timeFormatter: formatChartTime },
        });
        const prices = chart.addSeries(CandlestickSeries, {
            upColor: positive,
            downColor: negative,
            wickUpColor: positive,
            wickDownColor: negative,
            borderVisible: false,
            priceLineVisible: false,
        });
        const volume = chart.addSeries(
            HistogramSeries,
            {
                priceFormat: { type: "volume" },
                priceLineVisible: false,
                lastValueVisible: false,
            },
            1,
        );
        chart.panes()[1].setHeight(90);
        instance.current = { chart, prices, volume, snapshot: null, fitted: false };

        return () => {
            chart.remove();
            instance.current = null;
        };
    }, []);

    useEffect(() => {
        const current = instance.current;
        const element = containerRef.current;

        if (!current || !element) {
            return;
        }

        const styles = getComputedStyle(element);
        const positive = styles.getPropertyValue("--positive").trim();
        const negative = styles.getPropertyValue("--negative").trim();
        const precision = Math.max(
            2,
            ...candles.flatMap((candle) =>
                [candle.open, candle.high, candle.low, candle.close].map(
                    (value) => (value.split(".")[1] ?? "").replace(/0+$/, "").length,
                ),
            ),
        );
        current.prices.applyOptions({ priceFormat: { type: "price", precision, minMove: 10 ** -precision } });
        // Number conversion is confined to the canvas library; original Decimal strings remain intact.
        current.prices.setData(
            candles.map((candle) => ({
                time: Math.floor(Date.parse(candle.open_time) / 1000) as UTCTimestamp,
                open: Number(candle.open),
                high: Number(candle.high),
                low: Number(candle.low),
                close: Number(candle.close),
            })),
        );
        current.volume.setData(
            candles.map((candle) => ({
                time: Math.floor(Date.parse(candle.open_time) / 1000) as UTCTimestamp,
                value: Number(candle.base_volume),
                color: Number(candle.close) >= Number(candle.open) ? positive : negative,
            })),
        );

        if (!current.fitted && candles.length > 0) {
            current.chart.timeScale().fitContent();
            current.fitted = true;
        }
    }, [candles]);

    useEffect(() => {
        const current = instance.current;
        const element = containerRef.current;

        if (!current || !element) {
            return;
        }

        if (snapshotPrice === undefined || !Number.isFinite(Number(snapshotPrice))) {
            if (current.snapshot) {
                current.prices.removePriceLine(current.snapshot);
                current.snapshot = null;
            }
            return;
        }

        if (current.snapshot) {
            current.snapshot.applyOptions({ price: Number(snapshotPrice) });
        } else {
            current.snapshot = current.prices.createPriceLine({
                price: Number(snapshotPrice),
                color: getComputedStyle(element).getPropertyValue("--accent").trim(),
                lineStyle: LineStyle.Dashed,
                lineWidth: 1,
                axisLabelVisible: true,
                title: "Snapshot",
            });
        }
    }, [snapshotPrice]);

    return (
        <div
            ref={containerRef}
            className="market-chart__canvas"
            role="img"
            aria-label={`Biểu đồ nến và khối lượng ${symbol}, giờ Việt Nam (UTC+7)`}
        />
    );
}
