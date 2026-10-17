# Crypto Decision Lab

Ứng dụng cá nhân thu thập Binance Spot market data bằng Phoenix, Ecto, PostgreSQL và Oban. Có REST API, đồng bộ giá, thống kê 24h, backfill 1H, kiểm tra gaps và tổng hợp 4H/1D. Bảng giá Next.js có chart và phân tích Jev mỗi 5 phút theo yêu cầu mở rộng. Chưa có backtest, sizing, dashboard quyết định đầy đủ hoặc giao dịch thật.

## Khởi động local

Cần Elixir/OTP, Docker Compose và quyền tải Hex dependencies. Đã biên dịch/kiểm thử bằng Elixir 1.18.3 và OTP 27; phiên bản dependency cụ thể nằm trong `apps/api/mix.lock`. Compose dùng PostgreSQL 18. Database development và test tách riêng.

Từ thư mục gốc:

```sh
cp .env.example .env
# Sửa thông tin local nếu cần; POSTGRES_PASSWORD và DB_PASSWORD phải khớp.
set -a
source .env
set +a
docker compose --env-file .env -f infra/compose.yaml up -d --wait
cd apps/api
mix deps.get
mix ecto.setup
MARKET_SYNC_ENABLED=true mix phx.server
```

API mặc định: `http://127.0.0.1:4000`. Mix không tự đọc `.env`; cần export như trên ở mỗi terminal. Khi bật sync, startup enqueue bootstrap: xác minh symbol, enqueue snapshot giá/thống kê và backfill tối đa 3 năm cho các asset khả dụng. Không cần Binance API key.

Development bật đồng bộ mặc định: `mix phx.server` khởi động poll giá 30 giây, Oban queue và Cron. Để chỉ đọc dữ liệu hiện có:

```sh
MARKET_SYNC_ENABLED=false mix phx.server
```

Production vẫn mặc định tắt; test luôn tắt đồng bộ tự động. Các job đã enqueue vẫn được lưu và sẽ chạy khi bật sync. Nếu trước đây đã export `MARKET_SYNC_ENABLED=false`, đổi lại `true` và khởi động lại API; thay config không tự restart application trong phiên IEx đang chạy.

Nếu dùng PostgreSQL đã có, bỏ bước Docker và đặt `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `TEST_DB_NAME` tương ứng. Database test bắt buộc có hậu tố `_test`, khác development; cấu hình test bỏ qua `DATABASE_URL` để tránh dùng nhầm database production.

## Database dev và prod

Dev khai báo kết nối trong `apps/api/config/dev.exs`, tương tự cấu trúc `core_api`; prod đọc `DATABASE_URL` hoặc bộ `DB_*` trong `apps/api/config/runtime.exs`. Cấu hình runtime không ghi đè Repo của dev. Xem [hướng dẫn database](docs/database-runtime.md) để đặt credentials và chạy theo môi trường.

## Web xem giá

Cần Node.js >=20.9.0. Chạy API trước, sau đó mở terminal thứ hai:

```sh
cd apps/web
npm ci
npm run dev
```

Mở **http://127.0.0.1:3000**. Web đọc API ở `http://127.0.0.1:4000` theo mặc định. Nếu API chạy trên cổng khác:

```sh
API_BASE_URL=http://127.0.0.1:4001 npm run dev
```

Trang hiển thị đủ danh mục, tìm kiếm, giá USDT, thay đổi/khối lượng 24h, thời điểm lấy giá và trạng thái Oban. Giá nháy xanh khi tăng, đỏ khi giảm (0,8 giây); không nháy khi giá không đổi và tôn trọng chế độ giảm chuyển động. Bấm dòng hoặc nút mã để xem chi tiết, tự cuộn tới panel; mặc định mở BTC. Chart nến và volume có khung 1H/4H/1D, kéo/zoom được; chỉ dùng nến đã đóng. Trục thời gian, crosshair và thời gian mở nến hiển thị giờ Việt Nam (UTC+7); dữ liệu và ranh giới tổng hợp nến vẫn giữ UTC. Chart đọc lại mỗi 60 giây, đường Snapshot theo giá mới nhất. Web đọc lại API mỗi 5 giây; collector lấy snapshot Binance mỗi 30 giây, không phải WebSocket từng tick. Dữ liệu thiếu/cũ và lỗi kết nối được hiển thị rõ ràng. Repo Oban khai báo tại `config/config.exs`; queue, Cron và công tắc market/Jev được ghép tại `config/runtime.exs`.

`API_BASE_URL` chỉ dùng phía server; không cần CORS hay Binance API key trên trình duyệt. Có thể lưu biến này vào `apps/web/.env.local`. API chi tiết dùng **ETHUSDT**, không phải `ETH`: `/api/markets/ETHUSDT`.

Kiểm tra web: `npm run typecheck`, `npm run lint`, `npm run build`. Kiểm thử tương tác: `npm run test:e2e` khi web đang chạy ở 3000 và máy đã cài Google Chrome; có thể đổi URL bằng `WEB_TEST_URL`. Browser tests dùng synthetic fixtures có nhãn, không ghi dữ liệu DB. Xem [thiết kế bảng giá](docs/market-monitor.md).

## Phân tích Jev mỗi 5 phút

Đăng ký key tại [TypeSafe Console](https://console.typesafe.ai/login). Đặt `TYPESAFE_API_KEY`, `JEV_ENABLED=true` và `JEV_MODEL` trong môi trường backend. Model phải thuộc danh sách trả về từ `GET https://api.typesafe.ai/v1/models`; `jev-latest` là alias trong tài liệu, chưa xác minh quyền model của tài khoản khi key bị từ chối.

File `.env.jev` local đã được tạo, gitignore và chmod 600; cập nhật key bằng editor, không đưa key vào chat/Git/Next.js. Từ root, sau khi đã thiết lập kết nối DB:

```sh
set -a
source .env.jev
set +a
cd apps/api
mix ecto.migrate
PORT=4001 mix phx.server
```

Nếu backend đang chạy, dừng và khởi động lại tiến trình đó để nhận key mới. Web đang dùng port 4001 cần `API_BASE_URL=http://127.0.0.1:4001`. Để enqueue ngay kỳ hiện tại, ở terminal khác đã export cùng cấu hình: `mix jev.analyze`; nếu không, chờ mốc phút chia hết cho 5. Không chạy thêm server trên cổng đang dùng.

Oban queue `analysis` và Cron trong `config/runtime.exs` hoạt động độc lập với `MARKET_SYNC_ENABLED`. Mỗi cặp đang giao dịch được phân tích một lần/kỳ 5 phút khi đủ 300 nến 1H liên tiếp và giá/thống kê còn mới. EMA20/50, RSI14 Wilder và returns được backend tính bằng Decimal; Jev đánh giá xu hướng, động lượng, biến động. BUY/SELL/WAIT là tín hiệu nghiên cứu; không có lệnh hoặc vị thế thực. GET và nút Làm mới chỉ đọc kết quả đã lưu, không gọi Jev.

Chọn mã trên web để xem phân tích, chỉ báo và thời điểm đánh giá. API thêm `/api/markets/:symbol/analysis`, đồng thời bổ sung `analysis`/`analysis_enabled` vào các response market. Tắt bằng `JEV_ENABLED=false`, restart backend; market data vẫn hoạt động.

**Trạng thái xác minh:** key được cung cấp hiện trả **401** ở cả models và inference; chưa xác minh một suy luận thật thành công. UI hiển thị lỗi xác thực và không đưa tín hiệu giả. Sau khi thay key, cooldown lỗi 401/403/402 có thể còn tối đa 15 phút; sau đó kỳ kế tiếp tự thử. Với 429, tôn trọng `Retry-After` dạng số giây; lỗi upstream/network có cooldown chung. Không tự retry dồn dập trong request.

28 cặp tương ứng tối đa 8.064 request/ngày trước các lần bị bỏ qua; usage nằm trong raw response lưu DB. Lịch sử phân tích chưa tự xóa, cần chính sách retention khi chạy dài hạn. Thiết kế, giới hạn và công thức: [jev-integration.md](docs/jev-integration.md).

## Kiểm tra

Chạy trong `apps/api` với biến môi trường DB đã export:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

`mix test` tạo/migrate database test và dùng SQL Sandbox. HTTP tests dùng synthetic fixtures được ghi rõ trong `test/support/market_fixtures.ex`, không gọi Binance. Tests bảo vệ Decimal, schema, rate limits/retries, partial data, checkpoint, uniqueness, gaps, aggregation, HTTP contracts, poll không overlap và PostgreSQL advisory lock giữa hai connection độc lập.

Kết quả kiểm tra thực tế và phần chưa kiểm chứng: [docs/verification.md](docs/verification.md).

## Đồng bộ thủ công

Trong `apps/api`, sau migration:

```sh
mix market.sync metadata
mix market.sync prices
mix market.sync stats
mix market.sync backfill BTCUSDT
mix market.sync candles
mix market.sync integrity
```

`metadata`, `prices`, `stats` chạy trực tiếp; `backfill` và `candles` enqueue Oban job. `integrity` kiểm tra gaps và enqueue repair. Cần server bật `MARKET_SYNC_ENABLED=true` để xử lý các job đã enqueue. `mix market.sync bootstrap` xác minh metadata rồi enqueue giá/thống kê/backfill toàn danh mục.

Mỗi backfill job chỉ xử lý tối đa 1.000 candle trong một lần chạy; checkpoint được commit cùng batch. Oban tiếp tục job còn dữ liệu và retry khi gặp lỗi. Conflict policy cập nhật candle bằng response hợp lệ; không nhân đôi khóa `(market_symbol_id, timeframe, open_time)`. Snapshot cũ không được ghi đè snapshot mới.

## REST API

| Method | Route | Mục đích |
| --- | --- | --- |
| GET | `/api/health` | Kiểm tra ứng dụng và kết nối DB; DB lỗi trả 503. |
| GET | `/api/markets` | 32 asset, symbol đã xác minh, giá/thống kê và freshness; hỗ trợ pagination. |
| GET | `/api/markets/:symbol` | Snapshot một Binance symbol, ví dụ BTCUSDT. |
| GET | `/api/markets/:symbol/candles` | Candle 1h/4h/1d, range UTC và limit hữu hạn. |
| GET | `/api/system/market-data-status` | Collector, cooldown/weight, sync states, gaps và số job theo trạng thái. |

```sh
curl http://127.0.0.1:4000/api/health
curl 'http://127.0.0.1:4000/api/markets?page=1&page_size=32'
curl 'http://127.0.0.1:4000/api/markets/BTCUSDT/candles?timeframe=4h&limit=100'
```

Decimal được trả bằng chuỗi; thời gian ISO 8601 UTC; giá thiếu là null. Contract đầy đủ: [docs/api.md](docs/api.md).

## Kiến trúc và lưu trữ

`apps/api` là modular monolith; `apps/web` có trang bảng giá đơn giản theo yêu cầu, dashboard đầy đủ vẫn thuộc Phase 4. `MarketData` là context, `Sync` sở hữu nghiệp vụ đồng bộ, `Binance`/`Transport` là integration boundary, `Parser` kiểm tra dữ liệu, `Integrity` phát hiện gaps/tổng hợp. Controller và worker chỉ điều phối.

Sáu bảng nghiệp vụ: `market_assets`, `market_symbols`, `market_latest_prices`, `market_ticker_stats`, `market_candles`, `market_sync_states`. Thêm `market_collector_states` cho deadline/cooldown/weight dùng chung và các bảng Oban. Toàn bộ financial values lưu NUMERIC; canonical candle là 1H; không lưu tick history hoặc timeframe tổng hợp.

Collector sử dụng PostgreSQL transaction advisory lock chung giữa các backend node. Một HTTP batch giữ lock trong transaction; node khác sẽ hoãn công việc. Poller dùng monotonic timer 30 giây, chỉ một task đang chạy và deadline chung trong DB. Khi backfill đang chiếm lock, poller thử lại khóa sau 1 giây và vẫn kiểm tra deadline 30 giây trước khi gọi Binance. Khi upstream chậm hoặc không có giá mới, API báo dữ liệu stale.

Tài liệu: [kiến trúc](docs/architecture.md), [đồng bộ và vận hành](docs/synchronization.md), [quy tắc code](AGENTS.md).

## Troubleshooting

- `connection refused`: kiểm tra host/port, `docker compose --env-file .env -f infra/compose.yaml ps` tại root; mặc định DB host port 5433, không phải 5432.
- `password authentication failed`: kiểm tra DB_PASSWORD khớp POSTGRES_PASSWORD. Thay biến môi trường không đổi mật khẩu trong volume đã có; không xóa volume để xử lý lỗi kết nối.
- `mix deps.get` timeout: kiểm tra mạng/proxy; có thể thử `HEX_HTTP_CONCURRENCY=1 HEX_HTTP_TIMEOUT=120 mix deps.get`.
- Không có giá: chạy metadata trước, xem symbol availability, `MARKET_SYNC_ENABLED` và status endpoint. Asset không có Spot/USDT không được tự thay thế.
- `cooldown`: dừng request đến `blocked_until`; không khởi động collector khác để vượt cooldown. Thiếu Retry-After dùng 60 giây cho 429, 3 ngày cho 418.
- `stale_response`: kiểm tra đồng hồ hệ thống/NTP và HTTP cache/proxy. Adapter yêu cầu HTTP Date hợp lệ, lệch tối đa 60 giây; ticker closeTime tối đa 10 phút cũ.
- `incomplete_aggregation`: chạy integrity/repair, đợi đủ candle 1H; không lấp candle bằng giá giả.
- Job `discarded`: xem trạng thái/lỗi, khắc phục upstream rồi enqueue lại. Job retry tối đa 10 lần; cooldown dùng snooze.

Migration mới chạy bằng `mix ecto.migrate`; seed chạy lại an toàn bằng `mix run priv/repo/seeds.exs`. Dừng Compose bằng `docker compose --env-file .env -f infra/compose.yaml down` tại root, giữ volume dữ liệu.

## Phạm vi tiếp theo

Phase 2: chuẩn hóa công thức/lookback, thêm EMA 20/50/200, RSI, MACD, ATR, ADX, relative volume và returns; đối chiếu reference implementation với tolerance và tests chống future-data leakage. Sau đó mới thêm feature generation, screener và deterministic baselines.

Đánh giá dữ liệu và thiết kế tích hợp chỉ báo/Jev: [decision-readiness.md](docs/decision-readiness.md). Đây là thiết kế đầy đủ hơn phạm vi đã triển khai; phần Jev 5 phút hiện tại được mô tả trong [jev-integration.md](docs/jev-integration.md).
