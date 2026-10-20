import { expect, test } from "@playwright/test";

import { priceDirection } from "../lib/markets/price-change";
import type { MarketAnalysisData, MarketMonitorResult } from "../lib/api/types";

test.use({ timezoneId: "America/New_York" });

// Synthetic browser fixtures only. Never persisted or used as production fallback.
function fixtureMonitor(
    price = "100.00000000",
    analysis: MarketAnalysisData | null = null,
): Extract<MarketMonitorResult, { ok: true }> {
    const timestamp = new Date().toISOString();
    const freshness = { status: "fresh" as const, age_seconds: 0, timestamp };
    return {
        ok: true,
        checked_at: Date.now(),
        data: {
            assets: ["BTC", "ETH"].map((symbol, index) => ({
                id: index + 1,
                symbol,
                name: `Fixture ${symbol}`,
                enabled: true,
                availability: "discovered",
                markets: [
                    {
                        id: index + 1,
                        symbol: `${symbol}USDT`,
                        exchange: "binance",
                        base_asset: symbol,
                        quote_asset: "USDT",
                        enabled: true,
                        trading_status: "TRADING",
                        analysis_enabled: true,
                        analysis_interval_seconds: 900,
                        price_max_age_seconds: 360,
                        analysis_unavailable_reason: null,
                        analysis,
                        latest_price: {
                            price,
                            data_at: timestamp,
                            fetched_at: timestamp,
                        },
                        ticker_stats: {
                            price_change_percent: "1.25",
                            high_price: "110",
                            low_price: "90",
                            quote_volume: "500000",
                            base_volume: "5000",
                            fetched_at: timestamp,
                        },
                        price_freshness: freshness,
                        stats_freshness: freshness,
                    },
                ],
            })),
            status: {
                enabled: true,
                price_poll_interval_seconds: 300,
                sources: {},
                configured_assets: 3,
                active_symbols: 2,
                collector: {
                    prices_at: timestamp,
                    stats_at: timestamp,
                    metadata_at: timestamp,
                    blocked_until: null,
                    last_error: null,
                },
                jobs: {},
            },
        },
    };
}

function fixtureCandles(timeframe = "1h") {
    return {
        ok: true,
        data: {
            data: [0, 1, 2].map((index) => ({
                open_time: new Date(Date.UTC(2026, 9, 15, index)).toISOString(),
                close_time: new Date(
                    Date.UTC(2026, 9, 15, index + 1) - 1,
                ).toISOString(),
                open: "100",
                high: "110",
                low: "95",
                close: String(102 + index),
                base_volume: "42.12345678",
            })),
            meta: {
                timeframe,
                count: 3,
                availability: "available",
                last_close_time: "2026-10-15T02:59:59.999Z",
                freshness: { status: "fresh", age_seconds: 0 },
            },
        },
    };
}

test("watchlist highlights only active Jev BUY/SELL for every row and selected quote", async ({ page }) => {
    const now = Date.now();
    const analysis: MarketAnalysisData = {
        id: 1,
        status: "ready",
        signal: "BUY",
        model: "fixture-jev",
        reason: null,
        analyzed_at: new Date(now).toISOString(),
        valid_until: new Date(now + 300_000).toISOString(),
        data_at: new Date(now).toISOString(),
        freshness: "fresh",
        features: {},
        answers: {
            trend: {
                type: "choice",
                choice: "BULLISH",
                confidence: 0.8,
                probabilities: { BULLISH: 0.8, BEARISH: 0.1, SIDEWAYS: 0.1 },
            },
            momentum: {
                type: "choice",
                choice: "STRENGTHENING",
                confidence: 0.8,
                probabilities: { STRENGTHENING: 0.8, WEAKENING: 0.1, MIXED: 0.1 },
            },
            volatility: {
                type: "choice",
                choice: "NORMAL",
                confidence: 0.8,
                probabilities: { NORMAL: 0.8, ELEVATED: 0.2 },
            },
        },
        risk_result: { execution_allowed: false, mode: "research_only" },
    };
    const monitor = fixtureMonitor("100", analysis);
    const template = monitor.data.assets[0];
    const symbols = [
        "BTC", "ETH", "SOL", "XRP", "BNB", "LTC", "ADA", "DOGE", "LINK", "AVAX",
        "DOT", "UNI", "ARB", "OP", "APT", "RENDER", "FET", "IMX",
    ];
    monitor.data.assets = symbols.map((symbol, index) => ({
        ...template,
        id: index + 1,
        symbol,
        name: `Fixture ${symbol}`,
        markets: [{
            ...template.markets[0],
            id: index + 1,
            symbol: `${symbol}USDT`,
            base_asset: symbol,
            analysis: { ...analysis, signal: "WAIT" },
        }],
    }));
    const markets = monitor.data.assets.map((asset) => asset.markets[0]);
    markets[0].analysis = { ...analysis, signal: "BUY" };
    markets[1].analysis = { ...analysis, signal: "SELL" };
    markets[2].analysis = { ...analysis, signal: "NO_DATA" };
    markets[3].analysis = { ...analysis, status: "error" };
    markets[4].analysis = { ...analysis, status: "no_data" };
    markets[5].analysis = { ...analysis, freshness: "stale" };
    markets[6].analysis = { ...analysis, valid_until: new Date(now - 1).toISOString() };
    markets[7].analysis = null;
    markets[8].analysis = analysis;
    markets[8].analysis_enabled = false;
    markets[9].analysis = analysis;
    markets[9].enabled = false;
    markets[10].analysis = analysis;
    monitor.data.assets[10].enabled = false;
    markets[11].analysis = analysis;
    markets[11].trading_status = "HALT";
    markets[12].analysis = analysis;
    markets[12].analysis_unavailable_reason = "gold_history_unavailable";
    monitor.data.assets[0].markets.push({
        ...markets[0],
        id: 100,
        symbol: "BTCUSD",
        quote_asset: "USD",
        exchange: "coinbase",
        analysis: { ...analysis, signal: "SELL" },
    });
    await page.route("**/api/market-monitor", (route) => route.fulfill({ json: monitor }));
    await page.route("**/api/market-candles?**", (route) => route.fulfill({ json: fixtureCandles() }));
    await page.goto("/");
    await page.getByRole("button", { name: "Làm mới", exact: true }).click();
    await expect(page.locator(".market-row").first()).toContainText("Fixture BTC");
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USDT");
    const rows = page.locator(".market-row");
    await expect(rows).toHaveCount(20);
    await expect(rows.nth(0)).toHaveAttribute("data-jev-signal", "BUY");
    await expect(rows.nth(1)).toHaveAttribute("data-jev-signal", "SELL");
    await expect(page.locator(".market-row__signal")).toHaveCount(2);
    await expect(rows.nth(0).locator(".market-row__signal")).toContainText("Jev · MUA");
    await expect(rows.nth(1).locator(".market-row__signal")).toContainText("Jev · BÁN");
    await expect(rows.nth(0).locator(".market-row__signal")).toHaveCSS("animation-name", "market-jev-pulse");
    const buyColor = await rows.nth(0).locator(".market-row__signal").evaluate((el) => getComputedStyle(el).color);
    const sellColor = await rows.nth(1).locator(".market-row__signal").evaluate((el) => getComputedStyle(el).color);
    expect(buyColor).not.toBe(sellColor);
    await page.getByRole("button", { name: "Xem chi tiết FET", exact: true }).click();
    await expect(page.locator(".market-analysis")).toContainText("Tài sản đã tắt đồng bộ và phân tích");
    await expect(page.locator(".market-analysis__signal")).toHaveAttribute("data-signal", "WAIT");
    await expect(page.locator(".market-analysis__signal")).toContainText("không còn hiệu lực");
    await page.getByRole("button", { name: "Xem chi tiết ARB", exact: true }).click();
    await expect(rows.nth(1)).toHaveAttribute("data-selected", "true");
    await expect(rows.nth(0)).toHaveAttribute("data-jev-signal", "BUY");
    await page.emulateMedia({ reducedMotion: "reduce" });
    await expect(rows.nth(0).locator(".market-row__signal")).toHaveCSS("animation-name", "none");
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USD");
    await expect(rows.nth(0)).toHaveAttribute("data-jev-signal", "SELL");
    await expect(page.locator(".market-row__signal")).toHaveCount(1);
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USDT");
    markets[0].analysis = { ...analysis, signal: "WAIT" };
    markets[1].analysis = { ...analysis, signal: "BUY" };
    await page.getByRole("button", { name: "Làm mới", exact: true }).click();
    await expect(rows.nth(0).locator(".market-row__signal")).toHaveCount(0);
    await expect(rows.nth(1)).toHaveAttribute("data-jev-signal", "BUY");
    await page.clock.setFixedTime(now + 300_000);
    await expect(page.locator(".market-row__signal")).toHaveCount(0);
});

test("decimal direction preserves precision and ignores equivalent representations", () => {
    expect(priceDirection(undefined, "100")).toBeNull();
    expect(priceDirection("100", undefined)).toBeNull();
    expect(priceDirection("100.000", "100")).toBeNull();
    expect(priceDirection("0.000000000000000001", "0.000000000000000002")).toBe(
        "up",
    );
    expect(priceDirection("9007199254740993.02", "9007199254740993.01")).toBe(
        "down",
    );
});

test("USD selection never relabels USDT data when the USD market is unavailable", async ({
    page,
}) => {
    await page.route("**/api/market-monitor", (route) =>
        route.fulfill({ json: fixtureMonitor() }),
    );
    await page.route("**/api/market-candles?**", (route) =>
        route.fulfill({ json: fixtureCandles() }),
    );
    await page.goto("/");
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USDT");
    await expect(page.locator(".market-row")).toHaveCount(3);
    const details = page.locator("#market-details");
    await expect(details.locator(".price-flash")).toHaveText("100");
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USD");
    await expect(
        page.getByRole("columnheader", { name: "Giá / USD", exact: true }),
    ).toBeVisible();
    await expect(details.locator(".price-flash")).toHaveText("-");
    await expect(details).toContainText("Chưa có cặp USD khả dụng");
    await expect(details).toContainText(
        "Không có cặp giao dịch khả dụng để phân tích",
    );
    await expect(page.locator(".market-chart__canvas")).toHaveCount(0);
    await expect(
        page.getByText(/Coinbase đang xác minh cặp USD/),
    ).toBeVisible();
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USDT");
    await expect(details.locator(".price-flash")).toHaveText("100");
    await expect(page.getByRole("img", { name: /BTCUSDT/ })).toBeVisible();
});

test("quote selection switches to the matching market snapshot and candle request", async ({
    page,
}) => {
    const monitor = fixtureMonitor();
    const btc = monitor.data.assets[0];
    btc.markets.push({
        ...btc.markets[0],
        id: 100,
        exchange: "coinbase",
        symbol: "BTCUSD",
        quote_asset: "USD",
        latest_price: {
            price: "103.25",
            data_at: new Date().toISOString(),
            fetched_at: new Date().toISOString(),
        },
    });
    await page.route("**/api/market-monitor", (route) =>
        route.fulfill({ json: monitor }),
    );
    await page.route("**/api/market-candles?**", (route) =>
        route.fulfill({ json: fixtureCandles() }),
    );
    await page.goto("/");
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USDT");
    await expect(page.locator(".market-row")).toHaveCount(3);
    const request = page.waitForRequest((request) =>
        request.url().includes("symbol=BTCUSD&exchange=coinbase"),
    );
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USD");
    await request;
    const details = page.locator("#market-details");
    await expect(details.locator(".price-flash")).toHaveText("103.25");
    await expect(details.locator(".market-details__pair")).toHaveText("BTCUSD");
    await expect(details).toContainText("COINBASE");
    await expect(page.getByRole("img", { name: /BTCUSD,/ })).toBeVisible();
    await page
        .getByRole("button", { name: "Xem chi tiết ETH", exact: true })
        .click();
    await expect(details.locator(".price-flash")).toHaveText("-");
});

test("gold long-term desk is linked from crypto monitor and shows reference price", async ({
    page,
}) => {
    const monitor = fixtureMonitor();
    const market = monitor.data.assets[0].markets[0];
    monitor.data.assets[0].markets.push({
        ...market,
        id: 100,
        exchange: "coinbase",
        symbol: "BTCUSD",
        quote_asset: "USD",
    });
    monitor.data.assets.push({
        id: 33,
        symbol: "XAU",
        name: "Vàng thế giới",
        enabled: true,
        availability: "discovered",
        markets: [
            {
                ...market,
                id: 101,
                exchange: "gold_api",
                symbol: "XAUUSD",
                base_asset: "XAU",
                quote_asset: "USD",
                latest_price: {
                    price: "4100.12",
                    data_at: new Date().toISOString(),
                    fetched_at: new Date().toISOString(),
                },
                ticker_stats: null,
                analysis_unavailable_reason: "gold_history_unavailable",
            },
        ],
    });
    await page.route("**/api/market-monitor", (route) =>
        route.fulfill({ json: monitor }),
    );
    await page.route("**/api/market-candles?**", (route) =>
        route.fulfill({ json: fixtureCandles() }),
    );
    await page.goto("/");
    await expect(
        page.getByRole("link", { name: "Vàng USD · dài hạn" }),
    ).toBeVisible();
    await expect(
        page.getByRole("button", { name: "Xem chi tiết XAU" }),
    ).toHaveCount(0);
    await page.goto("/gold");
    await expect(
        page.getByRole("heading", { name: /XAU\/USD/ }),
    ).toBeVisible();
    await expect(page.locator(".price-flash")).toHaveText("4,100.12");
    await expect(
        page.getByText(/Đang chờ đồng bộ lịch sử nến ngày/),
    ).toBeVisible();
    await expect(page.locator(".market-chart__canvas")).toHaveCount(0);
});

test("Jev analysis follows selected coin and shows expiry, auth failure and missing data", async ({
    page,
}) => {
    let analysis: MarketAnalysisData | null = null;
    await page.route("**/api/market-monitor", (route) =>
        route.fulfill({ json: fixtureMonitor("100", analysis) }),
    );
    await page.route("**/api/market-candles?**", (route) =>
        route.fulfill({ json: fixtureCandles() }),
    );
    await page.goto("/");
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USDT");
    const panel = page.getByRole("region", { name: "Phân tích Jev" });
    await expect(panel).toContainText("Đang chờ lần phân tích Jev đầu tiên");
    await expect(panel).toContainText("Chỉ báo 1 giờ");
    await expect(panel).not.toContainText("Mỗi 15 phút");
    analysis = {
        id: 1,
        status: "ready",
        signal: "BUY",
        model: "fixture-jev",
        reason: null,
        analyzed_at: new Date().toISOString(),
        valid_until: new Date(Date.now() + 300_000).toISOString(),
        data_at: new Date().toISOString(),
        freshness: "fresh",
        features: {
            ema20: "100",
            ema50: "98",
            rsi14: "55",
            last_close_time: "2026-10-17T11:59:59.999Z",
        },
        answers: {
            trend: {
                type: "choice",
                choice: "BULLISH",
                confidence: 0.7,
                probabilities: { BULLISH: 0.8, BEARISH: 0.1, SIDEWAYS: 0.1 },
            },
            momentum: {
                type: "choice",
                choice: "STRENGTHENING",
                confidence: 0.7,
                probabilities: {
                    STRENGTHENING: 0.8,
                    WEAKENING: 0.1,
                    MIXED: 0.1,
                },
            },
            volatility: {
                type: "choice",
                choice: "NORMAL",
                confidence: 0.7,
                probabilities: { NORMAL: 0.8, ELEVATED: 0.2 },
            },
        },
        risk_result: { execution_allowed: false, mode: "research_only" },
    };
    await page.getByRole("button", { name: "Làm mới", exact: true }).click();
    await expect(panel).toContainText("Theo dõi mua");
    await expect(panel).toContainText("Độ tin cậy mô hình: 70%");
    await expect(panel.locator(".market-analysis__signal")).toHaveCSS(
        "color",
        "rgb(116, 199, 163)",
    );
    await expect(panel).toContainText("cần xác định điểm vào, mức dừng lỗ");
    await expect(panel).toContainText("18:59 17/10/2026 (giờ Việt Nam)");
    await page
        .getByRole("button", { name: "Xem chi tiết ETH", exact: true })
        .click();
    await expect(panel).toContainText("Phân tích Jev · ETHUSDT");
    analysis = {
        ...analysis,
        signal: "SELL",
        answers: {
            ...analysis.answers,
            trend: {
                type: "choice",
                choice: "BEARISH",
                confidence: 0.7,
                probabilities: { BULLISH: 0.1, BEARISH: 0.8, SIDEWAYS: 0.1 },
            },
            momentum: {
                type: "choice",
                choice: "WEAKENING",
                confidence: 0.7,
                probabilities: {
                    STRENGTHENING: 0.1,
                    WEAKENING: 0.8,
                    MIXED: 0.1,
                },
            },
        },
    };
    await page.getByRole("button", { name: "Làm mới", exact: true }).click();
    await expect(panel.locator(".market-analysis__signal")).toHaveCSS(
        "color",
        "rgb(237, 142, 148)",
    );
    await expect(panel).toContainText("phương án giảm vị thế");
    analysis = {
        ...analysis,
        valid_until: new Date(Date.now() - 1_000).toISOString(),
    };
    await page.getByRole("button", { name: "Làm mới", exact: true }).click();
    await expect(panel).toContainText("Đã hết hạn");
    await expect(panel.locator(".market-analysis__signal")).toHaveAttribute(
        "data-signal",
        "WAIT",
    );
    analysis = {
        ...analysis,
        status: "error",
        signal: "NO_DATA",
        answers: {},
        reason: "authentication_failed",
    };
    await page.getByRole("button", { name: "Làm mới", exact: true }).click();
    await expect(panel).toContainText("Khóa API Jev bị từ chối");
    await expect(panel.locator(".market-analysis__signal")).toHaveCount(0);
    analysis = {
        ...analysis,
        status: "no_data",
        reason: "insufficient_candles",
    };
    await page.getByRole("button", { name: "Làm mới", exact: true }).click();
    await expect(panel).toContainText("Cần ít nhất 300 nến giờ");
});

test("selecting symbols and timeframes renders charts and unavailable states", async ({
    page,
}) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.route("**/api/market-monitor", (route) =>
        route.fulfill({ json: fixtureMonitor() }),
    );
    await page.route("**/api/market-candles?**", (route) => {
        const timeframe =
            new URL(route.request().url()).searchParams.get("timeframe") ??
            "1h";
        return route.fulfill({ json: fixtureCandles(timeframe) });
    });
    await page.goto("/");
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USDT");
    await expect(page.locator(".market-row")).toHaveCount(3);
    await expect(
        page.locator(".market-chart__canvas canvas").first(),
    ).toBeVisible();
    await expect(page.locator(".market-chart__summary")).toContainText(
        "09:00 15/10/2026 (giờ Việt Nam)",
    );
    await page
        .getByRole("button", { name: "Xem chi tiết ETH", exact: true })
        .click();
    await expect(
        page.getByRole("heading", { name: "ETH Fixture ETH" }),
    ).toBeVisible();
    await expect(page.getByRole("img", { name: /ETHUSDT/ })).toBeVisible();
    const request = page.waitForRequest((request) =>
        request.url().includes("timeframe=4h"),
    );
    await page.getByRole("button", { name: "4H", exact: true }).click();
    await request;
    await expect(
        page.getByRole("button", { name: "4H", exact: true }),
    ).toHaveAttribute("aria-pressed", "true");
    await expect(
        page.locator(".market-chart__canvas canvas").first(),
    ).toBeVisible();
    await page.setViewportSize({ width: 390, height: 844 });
    await page
        .getByRole("button", { name: "Xem chi tiết BTC", exact: true })
        .click();
    await expect(
        page.locator(".market-chart__canvas canvas").first(),
    ).toBeVisible();
    const overflow = await page.evaluate(
        () => document.documentElement.scrollWidth > window.innerWidth,
    );
    expect(overflow).toBe(false);
    expect(errors).toEqual([]);
});

test("prices flash on changes, repeat for the same direction, and respect reduced motion", async ({
    page,
}) => {
    let price = "100";
    await page.route("**/api/market-monitor", (route) =>
        route.fulfill({ json: fixtureMonitor(price) }),
    );
    await page.route("**/api/market-candles?**", (route) =>
        route.fulfill({ json: fixtureCandles() }),
    );
    await page.goto("/");
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USDT");
    await expect(page.locator(".market-row")).toHaveCount(3);
    const row = page.locator(".market-row").filter({
        has: page.getByRole("button", {
            name: "Xem chi tiết BTC",
            exact: true,
        }),
    });
    const value = row.locator(".price-flash");
    await expect(value).toHaveText("100");
    await expect
        .poll(() => value.evaluate((element) => element.getAnimations().length))
        .toBe(0);
    const initial = await value.elementHandle();
    await page.getByRole("button", { name: "Làm mới", exact: true }).click();
    await expect(
        page.getByRole("button", { name: "Làm mới", exact: true }),
    ).toBeEnabled();
    expect(await initial?.evaluate((element) => element.isConnected)).toBe(
        true,
    );
    price = "101.00000001";
    await page.getByRole("button", { name: "Làm mới", exact: true }).click();
    await expect(value).toHaveText(price);
    await expect(value).toHaveAttribute("data-direction", "up");
    await expect(value).toHaveCSS("animation-name", "price-flash-up");
    const previousAnimation = await value.evaluateHandle(
        (element) => element.getAnimations()[0],
    );
    price = "101.00000002";
    await page.getByRole("button", { name: "Làm mới", exact: true }).click();
    await expect(value).toHaveText(price);
    expect(
        await previousAnimation.evaluate((animation) => animation.playState),
    ).toBe("idle");
    await page.emulateMedia({ reducedMotion: "reduce" });
    price = "99";
    await page.getByRole("button", { name: "Làm mới", exact: true }).click();
    await expect(value).toHaveAttribute("data-direction", "down");
    await expect(value).toHaveCSS("animation-name", "none");
});

test("empty/error candle responses are visible and a delayed old selection cannot replace the new chart", async ({
    page,
}) => {
    let releaseOld: () => void = () => {};
    const oldRequest = new Promise<void>((resolve) => {
        releaseOld = resolve;
    });
    await page.route("**/api/market-monitor", (route) =>
        route.fulfill({ json: fixtureMonitor() }),
    );
    await page.route("**/api/market-candles?**", async (route) => {
        const params = new URL(route.request().url()).searchParams;
        if (params.get("symbol") === "BTCUSDT") {
            await oldRequest;
            await route.fulfill({ json: fixtureCandles() });
        } else if (params.get("timeframe") === "4h") {
            await route.fulfill({
                status: 503,
                json: { ok: false, message: "Fixture: thiếu nến để tổng hợp" },
            });
        } else {
            const empty = fixtureCandles();
            empty.data.data = [];
            empty.data.meta.count = 0;
            empty.data.meta.availability = "missing";
            await route.fulfill({ json: empty });
        }
    });
    await page.goto("/");
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USDT");
    await expect(page.locator(".market-row")).toHaveCount(3);
    await page
        .getByRole("button", { name: "Xem chi tiết ETH", exact: true })
        .click();
    await expect(
        page.getByText(
            "Chưa có nến đã đóng trong khoảng này. Lịch sử đang được đồng bộ.",
        ),
    ).toBeVisible();
    releaseOld();
    await page.getByRole("button", { name: "4H", exact: true }).click();
    await expect(
        page.locator(".market-chart").getByRole("alert"),
    ).toContainText("Fixture: thiếu nến");
    await expect(
        page.getByRole("heading", { name: "ETH Fixture ETH" }),
    ).toBeVisible();
    await expect(page.locator(".market-chart__canvas")).toHaveCount(0);
});

test("polling follows backend cadence and manual refresh also reloads candles", async ({
    page,
}) => {
    const monitor = fixtureMonitor();
    monitor.data.status.price_poll_interval_seconds = 30;
    let monitorRequests = 0;
    let candleRequests = 0;
    await page.clock.install();
    await page.route("**/api/market-monitor", (route) => {
        monitorRequests += 1;
        return route.fulfill({ json: monitor });
    });
    await page.route("**/api/market-candles?**", (route) => {
        candleRequests += 1;
        return route.fulfill({ json: fixtureCandles() });
    });
    await page.goto("/");
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USDT");
    await expect(page.locator(".market-chart__canvas")).toBeVisible();
    await page.clock.pauseAt(new Date(Date.now() + 1000));
    const initialRequests = monitorRequests;
    await page.clock.runFor(20_000);
    expect(monitorRequests).toBe(initialRequests);
    await page.clock.runFor(10_000);
    await expect.poll(() => monitorRequests).toBe(initialRequests + 1);
    await expect.poll(() => candleRequests).toBeGreaterThan(1);
    await expect(page.locator(".market-monitor__live")).not.toContainText(
        "mỗi",
    );

    const previousCandles = candleRequests;
    await page.getByRole("button", { name: "Làm mới", exact: true }).click();
    await page.clock.runFor(1);
    await expect.poll(() => candleRequests).toBeGreaterThan(previousCandles);
    await expect.poll(() => monitorRequests).toBe(initialRequests + 2);
});

test("freshness expires without fetching and an API error preserves the last snapshot", async ({
    page,
}) => {
    const monitor = fixtureMonitor();
    monitor.data.assets[0].markets[0].price_max_age_seconds = 2;
    let fail = false;
    let requests = 0;
    await page.clock.install();
    await page.route("**/api/market-monitor", (route) => {
        requests += 1;
        return route.fulfill({
            json: fail
                ? {
                      ok: false,
                      checked_at: Date.now(),
                      message: "Fixture: API unavailable",
                  }
                : monitor,
        });
    });
    await page.route("**/api/market-candles?**", (route) =>
        route.fulfill({ json: fixtureCandles() }),
    );
    await page.goto("/");
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USDT");
    const row = page.locator(".market-row").filter({
        has: page.getByRole("button", {
            name: "Xem chi tiết BTC",
            exact: true,
        }),
    });
    await expect(row.locator(".price-flash")).toHaveText("100");
    const initialRequests = requests;
    await page.clock.pauseAt(new Date(Date.now() + 1000));
    await page.clock.runFor(3000);
    await expect(row.locator(".market-row__status")).toHaveText("Dữ liệu cũ");
    expect(requests).toBe(initialRequests);
    fail = true;
    await page.getByRole("button", { name: "Làm mới", exact: true }).click();
    await page.clock.runFor(1);
    await expect(page.getByRole("alert")).toContainText(
        "Fixture: API unavailable",
    );
    await expect(row.locator(".price-flash")).toHaveText("100");
});
