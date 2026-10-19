# REST contracts - Phase 1

Prefix hiện tại `/api`; thay đổi breaking sau này dùng `/api/v2`. Tất cả endpoint chỉ đọc. Không có endpoint quản lý sync hoặc đặt lệnh.

## Envelope và kiểu dữ liệu

Success: `{ "data": ..., "meta": { "generated_at": "<ISO8601 UTC>", ... } }`.
Error: `{ "error": { "code": "<stable code>", "message": "<safe description>" } }`.

Decimal luôn là JSON string, count/ID là integer, dữ liệu chưa có là null, timestamp là ISO 8601 với UTC offset Z. Không serialize Ecto metadata hoặc payload lỗi upstream. Các ví dụ cấu trúc ở đây không phải dữ liệu thị trường thật.

## Danh mục và snapshot

`GET /api/markets`: `page` mặc định 1, 1–100000; `page_size` mặc định 32, 1–100. `data` là mảng asset có `id`, `symbol`, `name`, `category`, `enabled`, timestamps, `availability` và `markets`.

`markets` chứa các mapping Binance USDT đã xác minh với `id`, `asset_id`, `exchange`, `symbol`, `base_asset`, `quote_asset`, `trading_status`, `enabled`, timestamps, `latest_price`, `ticker_stats`, `price_freshness`, `stats_freshness`. Asset không có mapping vẫn xuất hiện với `markets: []`, `availability: unavailable`; có mapping dùng `discovered`, xem `trading_status` để biết có đang giao dịch không.

`latest_price`: `market_symbol_id`, `price`, `fetched_at`, `updated_at`. `ticker_stats`: symbol ID, price_change, price_change_percent, high_price, low_price, base_volume, quote_volume, trade_count, `data_at` từ Binance closeTime, fetched_at và updated_at.

Freshness gồm `status: fresh|stale|missing`, `age_seconds`, `timestamp` khi có dữ liệu. Ngưỡng giá 90 giây, thống kê 600 giây. Price endpoint Binance không có trade timestamp: freshness giá là tuổi snapshot được lấy, không phải tuổi giao dịch cuối.

`meta` của danh mục có `page`, `page_size`, `total`. `GET /api/markets/:symbol` trả một mapping cùng snapshot/freshness; symbol phải uppercase ASCII và tối đa 30 ký tự. Symbol không tồn tại trả 404.

## Candle

`GET /api/markets/:symbol/candles`:

- `timeframe`: `1h` mặc định, hoặc `4h`, `1d`.
- `limit`: mặc định 100, tối đa 1000 bars output.
- `from`: inclusive; `to`: exclusive; cả hai là ISO 8601 UTC, thẳng ranh giới timeframe. Từ chối timestamp có offset khác UTC hoặc phần giây lẻ.
- `to` mặc định là ranh giới cuối đã đóng, có độ trễ an toàn 5 giây. `from` mặc định là `to - limit * timeframe`.
- Khoảng truy vấn tối đa 3 × 366 ngày, `from < to`, không yêu cầu candle chưa đóng. Có `from` thì lấy tối đa limit bars đầu tiên theo thứ tự thời gian.

`data` tăng dần theo open_time; có market_symbol_id, timeframe, open_time, close_time, OHLC, base/quote/taker-buy volumes và trade_count. Candle lưu trữ 1H có id và inserted_at; candle tổng hợp không có ID persistence.

`meta` có timeframe, from, to, limit, count, availability, last_close_time, freshness và generated_at. Response rỗng dùng availability=missing. Tổng hợp thiếu bất kỳ thành phần hoặc cửa sổ giữa dãy trả 422 `incomplete_aggregation`, không nội suy dữ liệu. Để kiểm tra gaps lịch sử toàn symbol, dùng status/integrity.

## Health và status

`GET /api/health`: chạy `SELECT 1` với timeout 2 giây; thành công `data: {status: ok, database: up}`, lỗi 503 `database_unavailable`. Đây là DB readiness, không xác nhận Binance đang hoạt động.

`GET /api/system/market-data-status`: enabled, configured_assets, active_symbols, collector, synchronization, jobs. Collector có các thời điểm thành công gần nhất, next_poll_at, blocked_until, weight_window (epoch minute), used_weight, weight_limit và last_error đã lọc. Sync states gồm checkpoint/range/status/errors/missing_count. `missing_count: null` nghĩa là chưa đo. Không có lịch sử candle thì integrity dùng status=no_data và missing_count=null; chưa thể suy ra listing range; không diễn giải giá trị 0 gaps là đã có lịch sử đầy đủ.

## Errors

| HTTP    | Code                   | Ý nghĩa                                                        |
| ------- | ---------------------- | -------------------------------------------------------------- |
| 400     | invalid_pagination     | page/page_size không hợp lệ.                                   |
| 400     | invalid_symbol         | Symbol sai định dạng.                                          |
| 400     | invalid_candle_query   | timeframe/limit không hợp lệ.                                  |
| 400     | invalid_time_range     | Khoảng không hợp lệ, quá rộng, không thẳng UTC hoặc chưa đóng. |
| 404     | not_found              | Symbol chưa được phát hiện.                                    |
| 422     | incomplete_aggregation | Thiếu candle nguồn.                                            |
| 503     | database_unavailable   | Health check DB thất bại.                                      |
| 404/500 | http_404/http_500      | Lỗi framework được trả bằng cùng error envelope.               |

## Research schedule metadata

Market objects returned by `/api/markets` and `/api/markets/:symbol` include `analysis_interval_seconds` (positive integer). `/api/markets/:symbol/analysis` includes `data.interval_seconds`. Development uses 120 seconds; clients must display the API value instead of hardcoding a frequency. Historical `analysis.reason` describes the stored attempt and does not independently diagnose current runtime credentials.

## Nguồn USD/vàng (2026-10-18)

`GET /api/markets/:symbol`, `/candles`, `/analysis` nhận query `exchange=binance|coinbase|gold_api` (mặc định binance cho compatibility). Mã ứng dụng là BTCUSD/XAUUSD; `provider_symbol` giữ mã gốc BTC-USD/XAU. `latest_price.data_at` là thời điểm nguồn, nullable cho legacy Binance (dùng fetched_at). Market trả `price_max_age_seconds` và `analysis_unavailable_reason`; XAU trả `gold_history_unavailable`. Stats quote_volume/trade_count và candle quote/taker volume/trade_count có thể null nếu nguồn không cung cấp. Không thay bằng 0.

Status thêm `sources` (collector state theo nguồn) và `price_poll_interval_seconds`. Lịch mặc định hiện tại 120 giây cho giá, 300 giây cho Jev. Frontend mặc định USD, hiển thị volume theo quote nếu có; nếu thiếu thì theo base_asset với nhãn đơn vị tương ứng.
