# Phase 1 — Báo cáo kiểm chứng

Ngày kiểm tra: 2026-10-17. Đây là kết quả đã chạy, không phải checklist dự kiến.

## Môi trường và kiểm tra tự động

- Elixir 1.18.3, Erlang/OTP 27, PostgreSQL 14.17 trên macOS.
- Cluster PostgreSQL tạm riêng `/tmp/crypto-decision-pg-20261017`, localhost:55433; database development và test riêng. Không sử dụng database có sẵn của người dùng. Cluster tạm đã dừng sau kiểm tra; dữ liệu thử nghiệm không nằm trong repository.
- Ba migration của ứng dụng/Oban chạy thành công; seed đăng ký đúng 32 asset và chạy lặp an toàn.
- `mix format --check-formatted`: đạt.
- `mix compile --warnings-as-errors`: đạt.
- `DB_PORT=55433 mix test`: **35 tests, 0 failures**.
- `DB_PORT=55433 mix precommit`: đạt (compile warnings-as-errors, lockfile cleanup, format và tests).
- Compose YAML parse thành công; chưa chạy Docker Compose vì Docker không có trên máy.

Tests bao phủ Decimal/finite values, cấu trúc JSON/OHLCV, candle chưa đóng, timestamp, 429/418/cooldown, retry 5xx/timeout, response stale, symbol availability, partial prices, snapshot cũ, weight budget, uniqueness, checkpoint và tiếp tục qua batch 1.000 candle, gaps/repair, tổng hợp 4H/1D, polling không overlap, HTTP contracts và Oban job uniqueness/continuation. Khóa collector được thử với hai PostgreSQL connection độc lập; chưa chạy deployment nhiều máy thật.

## Smoke test với Binance thật

Public Binance adapter hoạt động qua Req; không cần API key.

| Kiểm tra | Kết quả thực tế |
| --- | --- |
| exchangeInfo | 28 symbol Spot/USDT đang giao dịch thuộc danh mục 32 asset. |
| latest prices | Đồng bộ 28 snapshot. |
| rolling 24h stats | Đồng bộ 28 snapshot qua batch tối đa 20 symbol. |
| backfill BTCUSDT | Batch đầu 1.000 candle trả `:more`, resume hoàn tất với tổng 1.005 candle 1H. |
| incremental overlap | Sau chạy lặp vẫn đúng 1.005 row; không thêm duplicate. |
| supervised poller | Ba lần đều đồng bộ 28 giá; hai khoảng cách thực tế là 30.001 ms và 30.000 ms. |
| DB health | SELECT 1 thành công. |
| Năm endpoint qua Phoenix | HTTP 200 và JSON hợp lệ. |
| HTTP server thực localhost:4017 | health, markets và candles trả 200/JSON qua TCP. |

Tại thời điểm chạy, TON, KAS, HNT và MEW không có mapping Spot/USDT đang giao dịch trong response nhận được. Đây là kết quả tại thời điểm kiểm tra, không hardcode thành trạng thái cố định. Các asset này vẫn tồn tại trong danh mục; không thay bằng asset khác.

## Giới hạn còn lại

- Chưa chạy Compose/PostgreSQL 18; chỉ kiểm tra YAML và migration/test trên PostgreSQL 14.17 hiện có.
- Smoke test backfill dùng 1.005 candle BTC, chưa tải đủ 3 năm cho toàn bộ 28 symbol. Tác vụ backfill đủ phạm vi được triển khai và sẽ chạy khi bật sync; lịch sử còn phụ thuộc dữ liệu Binance cung cấp.
- Lịch Cron theo ngày/giờ đã cấu hình; không chờ nhiều ngày để quan sát toàn bộ lịch. Worker, pagination và continuation đã được kiểm thử.
- 429/418 và lỗi mạng/schema dùng synthetic fixtures; không cố tình tạo ban thật trên Binance.
- Collector toàn cục giữ DB connection trong HTTP batch. Backfill/request chậm có thể làm bỏ qua poll; API có freshness, không bảo đảm độ trễ giá cố định khi upstream lỗi.
- Listing history trước candle đầu tiên đã biết không được tự coi là gap. Integrity không bịa candle hoặc suy đoán listing date.
- Đây là nền tảng market data; chưa có AI, tín hiệu, hiệu suất đầu tư, dashboard hoặc giao dịch thật.

Phần triển khai Phase 1 và kiểm tra trong môi trường hiện có đã thực hiện. Việc nghiệm thu môi trường Docker và tải lịch sử đầy đủ còn cần chạy trên môi trường vận hành đích.


## Bảng giá dev và Oban — 2026-10-17

- Nguyên nhân kiểm chứng ở API đang chạy: `enabled=false`, 32 assets, 0 active symbols, collector null và không có job. Log `/api/markets/ETH` trả 404 vì contract yêu cầu mã cặp `ETHUSDT`.
- Dev hiện bật sync mặc định; Oban queue được khai báo tại `config/dev.exs`, Cron dùng chung tại `config/config.exs`; runtime hỗ trợ tắt tường minh. Production mặc định tắt, test luôn tắt.
- Backfill/repair priority 3, snapshot priority 0. Poller thử lại khóa sau 1 giây khi collector bận; vẫn dùng deadline chia sẻ 30 giây và không có task chồng lấn.
- `mix precommit`: **46 tests, 0 failures**, compile warnings-as-errors thành công. `mix format --check-formatted` thành công. Tests chạy trên PostgreSQL riêng cổng 55433, database `crypto_decision_lab_test`, không dùng database dev.
- Web: `npm run typecheck`, `npm run lint`, `npm run build` đều thành công. Next.js 16.4.2 / React 19.3.1 / TypeScript 6.0.3. TypeScript 7 không tương thích typescript-eslint hiện tại nên đã khóa về 6.0.3.
- HTTP smoke: `/` trả 200, HTML render đủ 32 dòng; `/api/market-monitor` trả 200 và contract hợp lệ, enabled=true, 28 active symbols. Bốn asset không có mapping Spot USDT được hiển thị rõ, không thay thế bằng dữ liệu giả.
- Kiểm tra hai snapshot thực qua web: ETHUSDT từ `2427.18000000` lúc `2026-10-17T15:00:12.689066Z` sang `2425.19000000` lúc `2026-10-17T15:02:19.533819Z`; freshness fresh và backfill vẫn đang chạy. Đây là hai lần lấy mẫu kiểm chứng, không phải nhịp lấy giá cố định 127 giây.
- Phiên local được khởi động: web `http://127.0.0.1:3000`, API mới `http://127.0.0.1:4001`. Giữ nguyên phiên API/IEx có sẵn ở 4000. Để chạy lại trên 4000, restart phiên cũ với sync bật rồi dùng API_BASE_URL mặc định cho web.
- Chưa kiểm tra tương tác và bố cục bằng trình duyệt tự động vì phiên làm việc không có browser preview tool. Đã kiểm tra SSR/HTTP, type/lint/build; không coi các kiểm tra này thay thế browser QA.
- `npm audit --omit=dev`: **0 vulnerabilities**. Audit toàn bộ cây có 9 cảnh báo (2 moderate, 7 high) trong công cụ build/lint, gồm Tailwind 3, glob/braces và selector parser; chưa áp dụng nâng major tự động vì thay đổi pipeline SCSS. Không có cảnh báo runtime trong lần kiểm tra này.

## Chi tiết, hiệu ứng giá và chart — 2026-10-17

- Thêm `PriceFlash`: CSS animation 800ms trong effect, render thuần; so sánh Decimal bằng BigInt, nháy xanh/đỏ theo tăng/giảm, không nháy với giá không đổi hoặc lần đầu, hỗ trợ reduced motion.
- Bấm mã/dòng mở chi tiết và tự cuộn tới panel. Chart Lightweight Charts 5.2.1 vẽ nến đóng + volume, khung 1H/4H/1D; đường snapshot riêng. Request cũ bị hủy khi đổi mã/khung; loading, empty, unavailable và lỗi được hiển thị rõ.
- `npm run test:e2e`: **4 passed** trên Google Chrome headless. Bao phủ precision cực nhỏ/lớn, so sánh giá tương đương, nháy liên tiếp cùng chiều, giữ DOM khi giá không đổi, reduced motion, chọn mã bằng bàn phím, đổi khung, canvas render, viewport mobile 390px không tràn ngang, empty/error và response cũ không ghi đè lựa chọn mới. Fixtures là dữ liệu kiểm thử; không ghi DB.
- `npm run typecheck`, `npm run lint`, `npm run build`: thành công trên bản cuối.
- Smoke HTTP với dữ liệu thật: BTCUSDT/1H và ETHUSDT/4H đều trả 120 nến qua `/api/market-candles`; timeframe 1m trả 400.
- Đã mở Chrome với dữ liệu thật và kiểm tra screenshot desktop 1440px: chart BTC, snapshot line và stats hiển thị; không có pageerror trong phiên kiểm tra. Đây là lần bổ sung browser QA, khắc phục giới hạn chưa có kiểm tra trình duyệt của mục trước.
- Backend không thay đổi trong lần này; không chạy lại ExUnit. API 4001 và web 3000 tiếp tục chạy.

## Giờ Việt Nam và đánh giá dữ liệu — 2026-10-17

- Chart dùng formatter Asia/Ho_Chi_Minh cho trục thời gian, crosshair và thời gian mở nến. Tick ngắn được dựng từ Intl parts để ổn định giữa Node/Chrome; timestamps gốc và ranh giới 4H/1D vẫn UTC.
- `npm run typecheck`, `npm run lint`, `npm run build`: thành công. `npm run test:e2e`: **5 passed**; gồm chuyển ngày/năm, không thay đổi timestamp, browser context America/New_York vẫn hiển thị UTC+7 và các regression về flash/chọn mã/chart.
- Chrome với dữ liệu thật: phần nến hiển thị `21:00 17/10/2026 (UTC+7)` từ open_time 14:00 UTC; nhãn crosshair canvas quan sát được `15:00 17/10/2026`. Không chỉ đổi chữ UTC thành UTC+7.
- Audit SELECT chỉ đọc: 688.001 nến 1H / 28 cặp, 0 giờ thiếu nội bộ giữa nến đầu-cuối, 0 nến chưa đóng, 0 vi phạm OHLC/base_volume đã kiểm tra. Phạm vi và giới hạn, độ phủ từng cặp và đề xuất chỉ báo/Jev nằm trong [decision-readiness.md](decision-readiness.md).
- Đã xác minh contract Jev bằng OpenAPI công khai; chưa gọi model có xác thực, chưa triển khai inference hoặc engine chỉ báo/quyết định trong lần này. Backend không sửa, không chạy lại ExUnit.


## Jev mỗi 5 phút — 2026-10-17

- Migration `20261017155028_create_market_analyses` chạy thành công trên DB dev và DB test riêng (PostgreSQL local port 55433). Không reset/truncate DB dev.
- `mix precommit`, `mix format --check-formatted`, `mix compile --warnings-as-errors`: thành công; **59 ExUnit tests passed**. Test Jev hoàn toàn offline với `MockDecisionProvider`/injected HTTP request, không dùng key thật trong test.
- Bao phủ reference EMA/RSI với nghiệm đóng, dữ liệu thiếu/gap/stale/future, precision Decimal, schema Jev sai/partial, lỗi 401/429/503/network, cooldown dùng chung, idempotency cùng kỳ, khóa qua hai kết nối PostgreSQL độc lập, API đọc không gọi provider và runtime Cron 5 phút độc lập collector. Tests luôn tắt scheduling dù export JEV_ENABLED=true.
- `npm run typecheck`, `npm run lint`, `npm run build`: thành công. **6 Playwright tests passed** với Chrome headless: bao gồm phân tích ready/waiting/error/no_data/expired, đổi mã, timezone Việt Nam trên browser America/New_York, chart và price flash.
- Smoke thật: key được cung cấp bị `GET /v1/models` từ chối với HTTP 401; adapter inference cũng nhận authentication_failed. Đã lưu kết quả lỗi cho 28 cặp hoạt động, signal NO_DATA, không tạo kết quả suy luận giả. Không xác minh được model tài khoản hoặc phân tích thành công khi chưa có key hợp lệ.
- Chrome với API thật ở 4001 và web 3000 hiển thị panel Jev của BTC, thông báo 401, EMA20/50 và RSI14 tính từ dữ liệu thật; không có pageerror. Ảnh QA local: `/tmp/crypto-decision-jev-analysis.png`.
- Key local chỉ trong `.env.jev` bị gitignore, quyền 0600; kiểm tra không xuất hiện trong source đã sửa hoặc log backend Jev. Không ghi key vào tài liệu, test fixture hoặc frontend.
- Backend dev 4001 đã restart để nhận runtime mới, giữ nguyên backend người dùng ở 4000. Lịch analysis mỗi 5 phút đang bật; lỗi xác thực kích hoạt cooldown 15 phút. Chưa xác minh tích lũy chi phí dài hạn, retention hoặc hiệu quả giao dịch/backtest.
