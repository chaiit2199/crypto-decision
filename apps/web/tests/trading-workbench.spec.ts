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
            valid_until: new Date(Date.now() + 360_000).toISOString(),
            configuration_version: "synthetic",
            timeframes: { trend: params.get("style") === "scalping" ? "1h" : "4h", setup: "15m", entry: "5m" },
            frames: { "5m": { status: "no_data", reason: "insufficient_candles", features: {} } },
            liquidity: { status: "missing", reason: "LIQUIDITY_MISSING" },
            market_regime: "UNKNOWN",
            setup: null,
            setup_quality: "UNCONFIRMED",
            ai_signal: "NO_DATA",
            ai_status: "missing",
            ai_reason: "analysis_not_run",
            ai_analyzed_at: null,
            direction_assessment: null,
            holding_horizon: null,
            horizon_deterministic: "UNSUITABLE",
            uncertainty: "UNCALIBRATED",
            expected_move: null,
            profit_probability: null,
            strategy_validation: "UNVALIDATED",
            execution_allowed: false,
            trade_eligibility: "NO_DATA",
            technical_candidate: false,
            missing_requirements: ["LIQUIDITY_MISSING", "ENTRY_NOT_CONFIRMED"],
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
    await page.getByRole("button", { name: "Tìm trong danh mục theo dõi", exact: true }).click();
    await expect(page.getByRole("listbox", { name: "Danh mục theo dõi" })).toBeVisible();
    await page.getByRole("option", { name: /BTC/ }).click();
    const workbench = page.getByRole("region", { name: "Nghiên cứu cơ hội giao dịch", exact: true });
    await expect(workbench).toContainText("Chưa đồng bộ sổ lệnh");
    await expect(workbench).toContainText("Chưa đủ dữ liệu");
    await expect(workbench.getByRole("region", { name: "Phiếu lệnh nghiên cứu" })).toContainText("Điều kiện còn thiếu");
    await expect(workbench).toContainText("Chưa có lần phân tích nào");
    await expect(workbench).toContainText("Chưa phù hợp giữ lệnh");
    await page.getByLabel("Phong cách").selectOption("scalping");
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

test("Coinbase shows hourly indicators and keeps the simple calculator usable without short frames", async ({ page }) => {
    const now = new Date().toISOString();
    const market = {
        id: 2, symbol: "BTCUSD", exchange: "coinbase", base_asset: "BTC", quote_asset: "USD",
        enabled: true, trading_status: "TRADING", analysis_enabled: false,
        analysis_unavailable_reason: null, price_max_age_seconds: 360, analysis_interval_seconds: 900,
        analysis: null, latest_price: { price: "100", data_at: now, fetched_at: now }, ticker_stats: null,
        price_freshness: { status: "fresh", age_seconds: 0 },
        stats_freshness: { status: "missing", age_seconds: null },
    };
    await page.route("**/api/market-monitor", (route) => route.fulfill({ json: {
        ok: true,
        checked_at: Date.now(),
        data: {
            assets: [{
                id: 1, symbol: "BTC", name: "Synthetic BTC", enabled: true,
                availability: "discovered", markets: [market],
            }],
            status: {
                enabled: true, price_poll_interval_seconds: 300, sources: {},
                configured_assets: 1, active_symbols: 1, collector: null, jobs: {},
            },
        },
    } }));
    await page.route("**/api/market-candles?**", (route) => route.fulfill({ json: {
        ok: false, message: "Synthetic: no chart history",
    } }));
    await page.route("**/api/trading?**", (route) => {
        const params = new URL(route.request().url()).searchParams;
        const data = {
            symbol: "BTCUSD", exchange: "coinbase", quote_asset: "USD", market: "spot",
            style: params.get("style"), as_of: now,
            valid_until: new Date(Date.now() + 360_000).toISOString(), configuration_version: "synthetic",
            timeframes: { trend: params.get("style") === "scalping" ? "1h" : "4h", setup: "15m", entry: "5m" },
            frames: {
                "4h": { status: "no_data", reason: "insufficient_candles", features: {} },
                "5m": { status: "no_data", reason: "insufficient_candles", features: {} },
                "1h": { status: "ready", reason: null, features: {
                    ema9: "99.1", ema21: "98.2", rsi14: "58.5", atr_percent: "1.2",
                    support: "97", resistance: "103", ema20: "98.3", ema50: "95", ema200: "90",
                    macd: "0.5", macd_signal: "0.4", macd_histogram: "0.1", atr14: "1.2", adx14: "22",
                    relative_volume20: "1.1", vwap: null, volume_delta: null, last_close_time: now,
                } },
            },
            liquidity: { status: "unsupported", reason: "LIQUIDITY_SOURCE_UNSUPPORTED" },
            market_regime: "UNKNOWN", setup: null, setup_quality: "UNCONFIRMED",
            ai_signal: "NO_DATA", ai_status: "disabled", ai_reason: "jev_disabled",
            ai_analyzed_at: null, direction_assessment: null,
            holding_horizon: null, horizon_deterministic: "UNSUITABLE",
            uncertainty: "UNCALIBRATED", expected_move: null, profit_probability: null,
            strategy_validation: "UNVALIDATED", execution_allowed: false,
            trade_eligibility: "NO_DATA", technical_candidate: false,
            missing_requirements: ["TIMEFRAME_DATA_MISSING"],
            risk_flags: ["TIMEFRAME_DATA_MISSING"], plan: null, depth_estimate: null,
            knowledge_matches: [], simulations: [],
        };
        return route.fulfill({ json: { ok: true, data: params.get("view") === "scanner" ? [data] : data } });
    });
    let posted: Record<string, string> | undefined;
    await page.route("**/api/trading", (route) => {
        posted = route.request().postDataJSON() as Record<string, string>;
        return route.fulfill({ json: { ok: true, data: {
            ...posted, risk_budget: "5", notional: "333.33333333333333333333", quantity: "3.33333333",
            net_loss: "5", net_profit: "5", estimated_total_cost_pct: "0.5",
            estimated_cost: "1.66666666667", risk_reward_ratio: "1", execution_allowed: false,
            cost_model: "constant-notional-v1",
        } } });
    });
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.goto("/");
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USD");
    const workbench = page.getByRole("region", { name: "Nghiên cứu cơ hội giao dịch", exact: true });
    await expect(workbench).toContainText("Phân tích Jev đang tắt");
    await workbench.getByText("Chỉ báo theo khung giờ và lịch sử mô phỏng", { exact: true }).click();
    const indicators = page.getByRole("region", { name: "Chỉ báo kỹ thuật theo khung", exact: true });
    await expect(indicators.getByLabel("Khung chỉ báo")).toHaveValue("1h");
    await expect(indicators.getByText("58.5", { exact: true })).toBeVisible();
    await expect(indicators).toContainText("Coinbase hiện chỉ đồng bộ nến 1 giờ");
    await indicators.getByLabel("Khung chỉ báo").selectOption("5m");
    await expect(indicators.getByRole("status")).toContainText("Coinbase chưa đồng bộ nến khung này");
    await indicators.getByLabel("Khung chỉ báo").selectOption("1h");
    await indicators.getByText("Xem thêm chỉ báo xu hướng và khối lượng", { exact: true }).click();
    await expect(indicators.getByText("Cột MACD", { exact: true })).toBeVisible();
    await expect(indicators.getByText("Chưa có dữ liệu", { exact: true })).toHaveCount(2);
    await indicators.getByText("Xem thêm chỉ báo xu hướng và khối lượng", { exact: true }).click();

    const planner = page.getByRole("region", { name: "Mô phỏng quản trị lệnh", exact: true });
    await expect(planner.locator('input[name="fee_percent"]')).toBeHidden();
    await expect(planner.locator('input[name="entry"]')).toHaveValue("");
    await planner.getByRole("button", { name: "Dùng giá hiện tại:" }).click();
    await expect(planner.locator('input[name="entry"]')).toHaveValue("100");
    await planner.locator('input[name="stop_loss"]').fill("99");
    await planner.locator('input[name="take_profit"]').fill("102");
    await page.getByLabel("Phong cách").selectOption("scalping");
    await expect(planner.locator('input[name="stop_loss"]')).toHaveValue("99");
    await planner.locator("summary").filter({ hasText: "Phí và trượt giá" }).click();
    await planner.locator('input[name="fee_percent"]').fill("0.2");
    await planner.locator("summary").filter({ hasText: "Phí và trượt giá" }).click();
    await planner.getByRole("button", { name: "Tính mô phỏng", exact: true }).click();
    await expect(planner.getByText("Kết quả mô phỏng", { exact: true })).toBeVisible();
    expect(posted?.symbol).toBe("BTCUSD");
    expect(posted?.exchange).toBe("coinbase");
    expect(posted?.fee_percent).toBe("0.2");
    await expect(planner.getByText("333.33333", { exact: true })).toBeVisible();
    await planner.screenshot({ path: "/tmp/crypto-workbench-desktop.png" });
    await planner.locator('input[name="entry"]').fill("101");
    await expect(planner.getByText("Kết quả mô phỏng", { exact: true })).toHaveCount(0);

    await page.setViewportSize({ width: 390, height: 844 });
    await planner.scrollIntoViewIfNeeded();
    const bounds = await planner.boundingBox();
    expect(bounds).not.toBeNull();
    expect((bounds?.x ?? 0) + (bounds?.width ?? 0)).toBeLessThanOrEqual(390);
    await expect(planner.getByRole("button", { name: "Tính mô phỏng", exact: true })).toBeVisible();
    await planner.screenshot({ path: "/tmp/crypto-workbench-mobile.png" });
});
