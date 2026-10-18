# Đồng bộ, giới hạn và quyết định triển khai

## Provider contract đã kiểm tra

Nguồn chính thức: [Binance Spot REST](https://github.com/binance/binance-spot-api-docs/blob/master/rest-api.md), [public data host](https://github.com/binance/binance-spot-api-docs/blob/master/faqs/market_data_only.md). Đã đối chiếu tài liệu và JSON live ngày 2026-10-17.

| Endpoint | Tham số sử dụng | Weight |
| --- | --- | --- |
| exchangeInfo | permissions=SPOT, showPermissionSets=false | 20 |
| ticker/price | symbols là JSON array | 4 |
| ticker/24hr | symbols theo batch 1–20, type=FULL | 2 mỗi batch |
| klines | symbol, interval=1h, startTime, endTime, limit=1000 | 2 |

Không dùng danh sách symbol suy đoán để gọi exchangeInfo; tải metadata SPOT rồi lọc base asset và quote USDT. Giá gửi một batch, thống kê chia tối đa 20 symbol để tránh mức weight 40 cho 21–100 symbol. Không có authenticated endpoint.

## Collector coordination

Mọi service ghi/đồng bộ lấy cùng PostgreSQL advisory transaction lock `7413201`. Một transaction chứa một batch HTTP, validation, ghi dữ liệu và checkpoint. Request bên ngoài transaction service không phải API được hỗ trợ. Một connection khác không lấy được lock sẽ trả collector_busy; Oban snooze 5 giây, poller thử lại khóa sau 1 giây. PostgreSQL tự nhả lock khi connection/process chết và rollback batch chưa commit.

`market_collector_states` là bảng hạ tầng bổ sung, không phải giá lịch sử. Nó lưu cooldown, weight budget và deadline poll để cùng chính sách hoạt động trên nhiều backend node. Không cần Redis hoặc cluster membership cho khóa này; mọi node phải trỏ cùng database. Các ứng dụng khác dùng cùng IP có thể tiêu thụ quota ngoài phạm vi collector, vì vậy vẫn theo dõi X-MBX-USED-WEIGHT-1M.

Giới hạn phút là min(limit metadata, 1200); quota còn lại được kiểm tra trước request. Header weight cập nhật số đã dùng. 429/418 commit blocked_until ngay cả khi service trả lỗi; không rollback chỉ vì HTTP thất bại. Retry-After được hiểu là số giây; thiếu/không hợp lệ thì dùng cooldown bảo thủ 60 giây/3 ngày. Network/5xx thử tối đa 3 request với exponential backoff và jitter; các HTTP 4xx khác không retry ngay. Timeout kết nối 5 giây, response 10 giây, transaction tối đa 120 giây.

Giữ DB connection trong HTTP batch là lựa chọn đơn giản cho 32 asset. Hạn chế: request chậm hoặc backfill có thể làm poll bị bỏ qua. Không xếp backlog poll; dashboard phải dùng freshness. Nếu throughput thực tế cần lớn hơn, đo trước khi thay bằng distributed lease hoặc tách quota coordinator.

## Polling và jobs

Poller có monotonic deadline, một monitored task tại một thời điểm. Task hoàn thành/chết mới cho tick sau chạy; shutdown hủy task. Shared next_poll_at ngăn node thứ hai poll ngay sau node thứ nhất. Thời gian UTC do clock hệ thống đồng bộ NTP cung cấp; HTTP Date được đối chiếu trong ±60 giây.

Oban queue `market` concurrency 1 trên mỗi node; advisory lock bảo vệ toàn bộ collector. Cron mặc định UTC: metadata 00:00 mỗi ngày, stats mỗi 5 phút, candle phút 01 mỗi giờ, integrity 00:15 mỗi ngày. Startup bootstrap được enqueue idempotent. Background jobs có max_attempts=10; uniqueness áp dụng cho args giống nhau ở trạng thái đang chờ/chạy/retry, không cho job cũ đã hoàn tất chặn yêu cầu mới.

## Historical data

Backfill bắt đầu ở ranh giới giờ đầu tiên trong 3 × 365 ngày gần nhất. Binance trả candle đầu tiên còn khả dụng nếu tài sản niêm yết sau mốc đó; không tạo dữ liệu trước niêm yết. Mỗi batch tối đa 1.000 candle. Resume dùng checkpoint +1H; incremental dùng candle mới nhất làm overlap. Chỉ tăng checkpoint sau batch đã validate và ghi thành công. Request bị lỗi giữ checkpoint cũ.

Parser kiểm tra length/type, finite Decimal, OHLC, volumes, trade count, open_time UTC-aligned và close_time=open_time+1H−1ms. Đồng thời close_time phải nhỏ hơn min(local clock, HTTP server Date) −5 giây. Vì HTTP Date có độ phân giải giây, có thể chờ thêm một phần giây quanh biên. Không chỉ tin planned close timestamp.

Conflict candle cập nhật dữ liệu hợp lệ bằng unique key; inserted_at không đổi. Snapshot price giữ một row/symbol và từ chối response fetched_at cũ hơn. Ticker còn bảo vệ data_at không lùi. Decimal đầu vào dùng dạng fixed-point tối đa 40 chữ số nguyên/30 chữ số thập phân; aggregation dùng precision 100 để cộng mà không mất số lẻ trong phạm vi này.

Integrity kiểm tra lưới UTC từ candle đầu tiên đã biết đến giờ hoàn tất mới nhất. Trước candle đầu tiên chưa đủ chứng cứ phân biệt chưa niêm yết và thiếu lịch sử. Gap count được lưu; repair jobs chia theo cửa sổ tối đa 1.000 giờ, không để checkpoint mới bỏ quên gaps cũ. Gap count phản ánh lần kiểm tra cuối và được cập nhật ở lần integrity tiếp theo. Không có dữ liệu thì không tự khẳng định lịch sử đầy đủ.

4H/1D chỉ tổng hợp đủ 4/24 candle liên tiếp; từ chối gap, kể cả thiếu cả một cửa sổ giữa dãy. Không persistence timeframe tổng hợp.

## Dependencies và local database

Phiên bản được resolver xác minh và khóa tại `apps/api/mix.lock`: Phoenix 1.8.15, Ecto 3.14.2/Ecto SQL 3.14.0, Oban 2.24.2, Req 0.7.5, Decimal 3.2.0. Toolchain máy kiểm tra: Elixir 1.18.3/OTP 27; giữ phiên bản tương thích này thay vì nâng toolchain hệ thống của người dùng.

Compose chọn PostgreSQL 18 và mount `/var/lib/postgresql` theo [Docker Official Image](https://hub.docker.com/_/postgres). Máy hiện tại thiếu Docker; migrations/tests chạy trên PostgreSQL 14.17 có sẵn bằng cluster tạm độc lập. Chưa xác nhận chạy Compose/PostgreSQL 18 trên máy này.

## Development và bảng giá

Dev bật sync mặc định; tắt bằng `MARKET_SYNC_ENABLED=false`. Production cần bật tường minh, test luôn tắt. Repo Oban khai báo trong `config/config.exs`; runtime ghép queue/Cron cho market và Jev riêng biệt. Tắt sync chỉ tắt collector và queue market; queue analysis vẫn chạy nếu `JEV_ENABLED=true`. Thay đổi biến môi trường hoặc config cần restart API.

Bootstrap enqueue prices/stats trước backfill; backfill và repair có priority 3, công việc hiện tại priority 0 (Oban ưu tiên số nhỏ). Poll giá vẫn dùng process 5 phút và advisory lock; nếu lock bận, thử lại khóa sau 1 giây, không tạo request Binance trước deadline 5 phút. Web chỉ đọc API mỗi 5 phút; xem [market-monitor.md](market-monitor.md).

## Chu kỳ hiện tại — 2026-10-18

Theo yêu cầu mới: collector giá và thống kê 24h chạy mỗi 5 phút; dashboard đọc API thị trường và lịch sử nến mỗi 5 phút sau khi request trước hoàn tất. Lần mở trang, đổi cặp/khung nến hoặc tải lại thủ công vẫn gọi ngay. Jev dùng slot UTC 15 phút (00/15/30/45), dispatcher kiểm tra mỗi phút nhưng chỉ xếp job ở phút đầu slot. GET chỉ đọc dữ liệu đã lưu.

`config.exs` và `dev.exs` dùng `price_poll_interval_ms: 300_000`, `analysis_interval_seconds: 900`; freshness giá vẫn là chu kỳ poll + 60 giây. Cần khởi động lại backend hoặc build/deploy lại release để áp dụng. Lịch metadata, nến đóng và integrity giữ riêng.
