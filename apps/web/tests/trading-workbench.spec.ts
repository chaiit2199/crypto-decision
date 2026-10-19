import { expect, test } from "@playwright/test";

// Synthetic UI fixtures only; no real market claims or provider calls.
test("workbench explains missing data and switches research style", async ({ page }) => {
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
    await expect(page.getByRole("region", { name: "Mô phỏng quản trị lệnh" })).toHaveCount(0);
    await page.getByLabel("Khung thời gian nghiên cứu").selectOption("scalping");
    await expect(page.getByRole("button", { name: "5M", exact: true })).toBeVisible();
    await expect(page.getByRole("region", { name: "Chỉ báo kỹ thuật dưới biểu đồ" })).toBeVisible();
});

test("Coinbase shows hourly indicators without short frames or capital planner", async ({ page }) => {
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
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.goto("/");
    await page.getByLabel("Đồng tiền của cặp giao dịch").selectOption("USD");
    const workbench = page.getByRole("region", { name: "Nghiên cứu cơ hội giao dịch", exact: true });
    await expect(workbench).toContainText("Phân tích Jev đang tắt");
    await expect(page.getByRole("region", { name: "Mô phỏng quản trị lệnh" })).toHaveCount(0);
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
    await page.getByLabel("Khung thời gian nghiên cứu").selectOption("scalping");
    await page.setViewportSize({ width: 390, height: 844 });
    await workbench.scrollIntoViewIfNeeded();
    const bounds = await workbench.boundingBox();
    expect(bounds).not.toBeNull();
    expect((bounds?.x ?? 0) + (bounds?.width ?? 0)).toBeLessThanOrEqual(390);
});
