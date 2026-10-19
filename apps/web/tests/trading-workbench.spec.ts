import { expect, test } from "@playwright/test";

// Synthetic UI fixtures only; no real market claims or provider calls.
test("workbench explains missing data and sends the selected market's hypothetical plan", async ({ page }) => {
    const now = new Date().toISOString();
    await page.route("**/api/market-monitor", (route) => route.fulfill({ json: {
        ok: true,
        checked_at: Date.now(),
        data: {
            assets: [{
                id: 1,
                symbol: "BTC",
                name: "Synthetic BTC",
                enabled: true,
                availability: "discovered",
                markets: [{
                    id: 1,
                    symbol: "BTCUSDT",
                    exchange: "binance",
                    base_asset: "BTC",
                    quote_asset: "USDT",
                    enabled: true,
                    trading_status: "TRADING",
                    analysis_enabled: false,
                    analysis_unavailable_reason: null,
                    price_max_age_seconds: 360,
                    analysis_interval_seconds: 900,
                    analysis: null,
                    latest_price: null,
                    ticker_stats: null,
                    price_freshness: { status: "missing", age_seconds: null },
                    stats_freshness: { status: "missing", age_seconds: null },
                }],
            }],
            status: {
                enabled: true,
                price_poll_interval_seconds: 300,
                sources: {},
                configured_assets: 1,
                active_symbols: 1,
                collector: null,
                jobs: {},
            },
        },
    } }));
    await page.route("**/api/market-candles?**", (route) => route.fulfill({ json: {
        ok: false,
        message: "Synthetic: chưa có nến",
    } }));
    await page.route("**/api/trading?**", (route) => {
        const params = new URL(route.request().url()).searchParams;
        const data = {
            symbol: "BTCUSDT",
            exchange: "binance",
            quote_asset: "USDT",
            market: "spot",
            style: params.get("style"),
            as_of: now,
            valid_until: new Date(Date.now() + 90_000).toISOString(),
            configuration_version: "synthetic",
            timeframes: { trend: "4h", setup: "15m", entry: "5m" },
            frames: { "5m": { status: "no_data", reason: "insufficient_candles", features: {} } },
            liquidity: { status: "missing", reason: "LIQUIDITY_MISSING" },
            market_regime: "UNKNOWN",
            setup: null,
            setup_quality: "UNCONFIRMED",
            ai_signal: "NO_DATA",
            ai_analyzed_at: null,
            direction_assessment: null,
            uncertainty: "UNCALIBRATED",
            expected_move: null,
            profit_probability: null,
            strategy_validation: "UNVALIDATED",
            execution_allowed: false,
            trade_eligibility: "NO_DATA",
            technical_candidate: false,
            risk_flags: ["LIQUIDITY_MISSING", "ENTRY_NOT_CONFIRMED", "STRATEGY_UNVALIDATED"],
            plan: null,
            depth_estimate: null,
            knowledge_matches: [],
            simulations: [],
        };
        return route.fulfill({ json: { ok: true, data: params.get("view") === "scanner" ? [data] : data } });
    });
    let posted: Record<string, string> | undefined;
    await page.route("**/api/trading", async (route) => {
        posted = route.request().postDataJSON() as Record<string, string>;
        await route.fulfill({ status: 400, json: { ok: false, message: "Synthetic: dừng lỗ phải thấp hơn giá vào" } });
    });
    await page.goto("/");
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USDT");
    const workbench = page.getByRole("region", { name: "Nghiên cứu cơ hội giao dịch", exact: true });
    await expect(workbench).toContainText("Chưa đồng bộ sổ lệnh");
    await expect(workbench).toContainText("Chưa đủ điều kiện giao dịch");
    await page.getByLabel("Phong cách nghiên cứu").selectOption("scalping");
    await expect(page.getByRole("button", { name: "5M", exact: true })).toBeVisible();
    const planner = page.getByRole("region", { name: "Mô phỏng quản trị lệnh", exact: true });
    await planner.locator('input[name="entry"]').fill("100");
    await planner.locator('input[name="stop_loss"]').fill("101");
    await planner.locator('input[name="take_profit"]').fill("102");
    await planner.getByRole("button", { name: "Tính mô phỏng", exact: true }).click();
    await expect(planner.getByRole("alert")).toHaveText("Synthetic: dừng lỗ phải thấp hơn giá vào");
    expect(posted?.symbol).toBe("BTCUSDT");
    expect(posted?.exchange).toBe("binance");
    expect(posted?.fee_percent).toBe("0.1");
    await planner.locator('input[name="stop_loss"]').fill("99");
    await expect(planner.getByRole("alert")).toHaveCount(0);
});
