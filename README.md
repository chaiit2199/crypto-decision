# Crypto Decision Lab

Personal Binance Spot research application: Phoenix/Ecto/PostgreSQL backend in `apps/api`, market monitor in `apps/web`. It does not execute real-money trades.

The new [Trading Knowledge Engine](docs/trading-knowledge-engine.md) adds versioned JSON hypotheses, deterministic matching, reviewed Jev context, independent risk policy, paired evaluation and audit records. The [ten example strategies](apps/api/priv/knowledge/README.md) are all unvalidated.

## Backend setup

Use the Elixir/OTP and PostgreSQL environment described in [database configuration](docs/database-runtime.md). Keep development and test databases separate. Export database connection variables in your shell; do not commit credentials. `TYPESAFE_API_KEY` is optional for market-data-only operation. Disable schedulers while doing manual research setup:

```sh
cd apps/api
mix deps.get
MARKET_SYNC_ENABLED=false JEV_ENABLED=true mix ecto.create
MARKET_SYNC_ENABLED=false JEV_ENABLED=true mix ecto.migrate
MARKET_SYNC_ENABLED=false JEV_ENABLED=true mix run priv/repo/seeds.exs
MARKET_SYNC_ENABLED=false JEV_ENABLED=true mix run -e 'IO.inspect(CryptoDecisionLab.TradingKnowledge.import_directory())'
MARKET_SYNC_ENABLED=true JEV_ENABLED=true mix phx.server
```

Existing collection and Jev monitor schedules are described in [synchronization](docs/synchronization.md) and [Jev integration](docs/jev-integration.md). The new knowledge workflow runs manually through its context functions and does not change these schedules. Existing monitor labels are not verified strategy-policy decisions.

## Verification

```sh
cd apps/api
mix format --check-formatted
mix compile --warnings-as-errors
TEST_DB_NAME=crypto_decision_lab_test mix test
```

Set `DB_HOST`, `DB_PORT`, `DB_USER`, and `DB_PASSWORD` for your test PostgreSQL server. Test names must end in `_test`; runtime ignores `DATABASE_URL` for tests. Tests use synthetic fixtures and do not require Binance or Jev network calls. The repository's `mix precommit` alias also formats, compiles and runs tests.

If a knowledge decision remains WAIT, inspect `risk_result.reason`: imports have no verified evidence by default; live knowledge calls also require a documented model token limit and exact tokenizer. Numeric Jev limits were not available from the verified OpenAPI, so no guessed limit is configured. See the engine document for review prerequisites, snapshot lineage, evaluation assumptions and other limits. No historical profitability or calibration has been established by this implementation.

## Chạy local với Jev

Từ thư mục gốc, chạy `./scripts/dev-api`. Script nạp `.env`, sau đó `.env.jev` trước khi chạy Phoenix. Trong `.env.jev`, đặt `JEV_ENABLED=true`, `TYPESAFE_API_KEY` và `JEV_MODEL`; giữ file ngoài Git. Các biến Jev đã export từ shell được ưu tiên. `JEV_ENABLED=true ./scripts/dev-api` tắt Jev cho lần chạy đó.

`mix phx.server` không tự đọc các file `.env`. Đổi cấu hình runtime cần dừng/khởi động lại backend. `GET /api/markets/BTCUSDT/analysis` trả `data.enabled` để kiểm tra trạng thái thực tế; sau khi bật, Cron xếp lịch phân tích mỗi 5 phút.

Jev trên dashboard hiện nhận feature giá/chỉ báo từ `Decisions`; chưa tự đọc `apps/api/trading-skills/`. Bộ 200 skills dùng schema riêng, có feature chưa được hỗ trợ và đều `unvalidated`. Trading Knowledge Engine có API thủ công riêng; bật `JEV_ENABLED` không tự tích hợp hay xác thực các strategy này.
