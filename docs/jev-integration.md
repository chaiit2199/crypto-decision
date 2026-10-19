# Jev: phân tích từng cặp theo lịch môi trường

Lịch hiện tại (2026-10-18): giá/API mỗi 5 phút, Jev mỗi 15 phút ở cả development và production. Xem [synchronization](synchronization.md#chu-kỳ-hiện-tại--2026-10-18); các mốc bên dưới ghi lại lịch trước đây.

Yêu cầu người dùng ngày 2026-10-17 mở rộng phạm vi sang phân tích Jev và thay lịch đề xuất 4H bằng Cron `*/5 * * * *` UTC. Lịch này độc lập với thu thập giá 30 giây. Không đặt lệnh thật.

## Kiến trúc và phạm vi

`TechnicalAnalysis` tính EMA20/50, RSI14 Wilder và return 1H/24H bằng Decimal từ 300 nến 1H liên tiếp đã đóng (SMA seed cho EMA, đủ warm-up cho EMA50). Giá hiện tại và rolling 24H là snapshot ở thời điểm phân tích, không dùng chúng để backtest quá khứ. Chưa triển khai MACD/ADX/ATR/EMA200, đa khung hoặc backtest; không mô tả chúng như input đã có.

`Decisions` kiểm tra freshness, xây feature snapshot, gọi `DecisionProvider` / `JevProvider` bằng Req và lưu kết quả. `MockDecisionProvider` chỉ dùng trong kiểm thử. Oban `AnalysisWorker` điều phối một job/cặp/slot theo `analysis_interval_seconds`; queue riêng không chặn đồng bộ thị trường. HTTP không tự retry: lần lỗi được lưu và kỳ sau thử lại, có cooldown chung khi upstream lỗi. GET từ dashboard chỉ đọc DB, không gọi Jev.

Jev nhận các câu hỏi choice riêng cho xu hướng, động lượng và mức biến động. Ứng dụng tổng hợp BUY/SELL/WAIT bằng quy tắc phiên bản cố định; BUY/SELL là tín hiệu nghiên cứu, SELL không phải mở short. Không có vị thế, stop-loss, sizing hoặc chiến lược được kiểm chứng: risk result luôn ghi `research_only`, `execution_allowed=false`. Thiếu dữ liệu trả NO_DATA trước khi gọi nhà cung cấp. Confidence không phải xác suất giao dịch có lãi.

## Lưu trữ / ERD

`market_symbols 1 -> N market_analyses`: symbol FK, slot UTC, status, signal, feature snapshot, model yêu cầu/thực tế, config version, answers/probabilities/raw response, risk result, error code, data_at, analyzed_at, valid_until. Unique `(market_symbol_id, slot)` chống lưu/call lại cùng kỳ đã hoàn tất; index symbol/slot phục vụ đọc bản mới nhất.

`jev_provider_states`: singleton ID=1, blocked_until và mã lỗi đã lọc. Advisory transaction lock chung bao phủ kiểm tra cooldown, kiểm tra bản ghi và request để các node không đồng thời vượt qua cooldown. Timeout request và transaction hữu hạn. Crash sau upstream trước commit vẫn có thể gây gọi lại; không tuyên bố exactly-once đối với API ngoài.

## Contract và bảo mật

Xác minh https://api.typesafe.ai/openapi.json và https://docs.typesafe.ai/introduction/quickstart : Bearer key, GET `/v1/models`, POST `/v1/systemone` với model/state/questions. Validate tên choice, confidence/probabilities hữu hạn trong [0,1], tổng probabilities và model/usage trước khi lưu success. Không log header, key hoặc body lỗi upstream. Không forward key qua redirect.

Runtime: `JEV_ENABLED`, `TYPESAFE_API_KEY`, `JEV_MODEL`; test luôn tắt scheduling. Key chỉ nằm trong biến môi trường backend; `.env.jev` local được gitignore và chmod 600. Dev/prod dùng cùng runtime config. Không key vẫn chạy market-data-only.

`GET /api/markets` và `GET /api/markets/:symbol` bổ sung `analysis_enabled` và `analysis` nullable. Analysis gồm status (`ready`, `no_data`, `error`), signal, model, answers, features, reason, timestamps, freshness và risk_result; không trả raw response. `GET /api/markets/:symbol/analysis` trả `{data: {enabled, analysis}, meta: {}}`. Chart/UI đọc kết quả lưu, hiển thị đang chờ/tắt/lỗi/thiếu dữ liệu/hết hạn; giờ Việt Nam chỉ dùng để hiển thị.

## Nghiệm thu

- Migration additive trên dev và DB test riêng; tests offline cho chỉ báo, warm-up/gap/stale, schema Jev, lỗi HTTP/cooldown, idempotency và API đọc không gọi provider.
- Test runtime: lịch Jev riêng 5 phút, không bật ở test, hoạt động khi collector tắt.
- Typecheck/lint và kiểm thử giao diện khi chuyển mã, stale, lỗi và thiếu dữ liệu.
- Smoke gọi models thật bằng key local, chạy một batch phân tích, xác minh bản ghi/API/web; báo riêng lỗi hoặc quyền tài khoản nếu upstream từ chối.
- Tối đa 28 x 288 = 8.064 request/ngày cho 28 cặp, không phải báo giá; theo dõi usage. Mỗi kỳ thêm một bản ghi/cặp; cần chính sách retention trước khi vận hành dài hạn.

## Công thức và giới hạn chỉ báo v1

- EMA(N): SMA của N close đầu làm seed, sau đó `EMA = previous + 2/(N+1) * (close-previous)`. Tải 300 nến cho EMA20/50; seed policy và chiều dài cửa sổ cố định thuộc configuration version.
- RSI14: chênh lệch giữa các close, lấy SMA 14 gains/losses đầu; cập nhật Wilder `(previous*13 + current)/14`; `RSI=100-100/(1+avg_gain/avg_loss)`. Quy ước chuỗi phẳng là 50, chỉ tăng là 100, chỉ giảm là 0. Không suy ra đảo chiều chỉ từ ngưỡng 30/70.
- Return N giờ: `(close/close_N_hours_ago - 1)*100`, dùng N=1 và 24. Tất cả giữ Decimal và serialize string; UI làm tròn để đọc, hover giữ giá trị gốc.
- Kiểm thử reference có nghiệm đóng cho chuỗi tăng đều và chuỗi luân phiên 100/101; tolerance `1e-9`. Chưa tuyên bố mọi kết quả trùng TradingView vì seed/history có thể khác. Công thức tham khảo: [EMA](https://www.tradingview.com/support/solutions/43000592270-exponential-moving-average/), [RSI](https://www.tradingview.com/support/solutions/43000502338-relative-strength-index-rsi/).
- Price tối đa 90 giây, stats tối đa 600 giây, close cuối tối đa 3660 giây; không nhận future timestamps hoặc gaps. Chỉ lấy close trước clock trừ 5 giây. Cập nhật đánh giá 5 phút không tạo nến 5 phút: EMA/RSI chỉ thay đổi sau khi có nến 1H mới, giá/stats snapshot có thể đổi giữa các kỳ.
- Chính sách tín hiệu v1: BULLISH + STRENGTHENING + NORMAL -> BUY; BEARISH + WEAKENING + NORMAL -> SELL; các trường hợp còn lại -> WAIT. Đây là tổng hợp nhãn nghiên cứu chưa backtest, không sử dụng confidence làm tỷ lệ thắng. Chưa có quyết định giao dịch có sizing/stop-loss.

## Chẩn đoán thông báo “Phân tích Jev đang tắt”

UI hiển thị thông báo khi API trả `analysis_enabled=false`; đây là trạng thái cấu hình, không phải lỗi phản hồi TypeSafe. `runtime.exs` quyết định `enabled`, queue và Cron từ cùng một cấu hình. Development tự đọc ba biến `JEV_ENABLED`, `TYPESAFE_API_KEY`, `JEV_MODEL` trong `.env.jev` ở root khi chạy `mix phx.server`; biến môi trường đã export luôn được ưu tiên, kể cả `false` hoặc chuỗi rỗng. Có thể chọn file local khác bằng `JEV_ENV_FILE`. File chỉ hỗ trợ assignment một dòng, dấu nháy và comment; không thực thi shell hay nội suy biến. Production/test không đọc file này. Không key vẫn chạy được ở chế độ market-data-only. Script `./scripts/dev-api` vẫn hỗ trợ nạp cả `.env`. Khởi động lại tiến trình sau khi thay đổi cấu hình.

Luồng tự động vẫn là `AnalysisWorker -> Decisions -> TechnicalAnalysis -> JevProvider`, chưa gọi `TradingKnowledge` và chưa import bộ 200 file `trading-skills`. Các rule chưa kiểm chứng không được tự coi là verified context.

## Điều chỉnh lịch development và phục hồi key (2026-10-18)

Theo yêu cầu mới, `dev.exs` đặt `price_poll_interval_ms: 60_000` và `analysis_interval_seconds: 120`. Đây là chu kỳ collector giá Binance và chu kỳ phân tích Jev; các endpoint GET vẫn chỉ đọc DB. Các môi trường khác giữ mặc định 30 giây/300 giây. Poller và deadline chống trùng giữa node phải dùng cùng chu kỳ giá. Cron đánh thức dispatcher mỗi phút; dispatcher chỉ xếp job trong phút đầu của slot cấu hình. Slot, kiểm tra job hết hạn và `valid_until` cùng lấy một giá trị cấu hình.

API market bổ sung `analysis_interval_seconds` để UI hiển thị lịch thật, không hardcode 5 phút. `missing_api_key` trong một bản ghi phân tích mô tả lần chạy đó, không phải kiểm tra config hiện tại. Khi key được bổ sung, lần phân tích tiếp theo được bỏ qua cooldown thiếu key cũ; cooldown 401, quota và 429 vẫn có hiệu lực. Không xóa lịch sử lỗi hay gọi Jev từ GET.

## Phục hồi dữ liệu cũ — 2026-10-19

API đang phục vụ frontend tại `api-crypto.9nine.tech` có chu kỳ giá 300 giây, phân tích 900 giây. Tại lần kiểm tra khoảng 21:37 giờ Việt Nam, RENDER có no_data/stale_price từ 21:30 dù giá đã cập nhật lúc 21:31; NEAR/INJ/SEI có asset.enabled=false nên không nằm trong lịch đồng bộ/phân tích.

Sửa Poller: khi timer monotonic thức sớm hơn deadline DB, Sync.poll trả thời gian chờ còn lại; Poller hẹn lại tại deadline thay vì bỏ qua nguyên chu kỳ 300 giây. Vẫn giữ khóa DB và deadline chia sẻ, không thêm request Binance trước hạn.

Sửa Decisions: bản ghi no_data do snapshot thiếu/cũ hoặc nến chưa đủ/gap/stale được đánh giá lại trong cùng slot. Worker snooze 30 giây để chờ đồng bộ; khi có input hợp lệ, update chính bản ghi đó và gọi provider. ready/error vẫn idempotent, không gọi lại Jev trong slot; slot hết hạn dừng retry. Không nâng ngưỡng freshness hoặc giả dữ liệu. Các mã disabled vẫn giữ nguyên lựa chọn người dùng, UI nêu rõ đã tắt thay vì hứa chờ phân tích mới.

Nghiệm thu: test deadline lệch dưới một chu kỳ, không overlap; no_data -> ready cùng ID sau snapshot mới, chỉ một provider call; worker snooze và dừng sau expiry; UI disabled không hiển thị tín hiệu active. Đây là thay đổi code local, cần deploy API để sửa server đang chạy.

Kết quả kiểm tra local: format và compile warnings-as-errors đạt; 20 test Decisions/Poller và test deadline riêng đạt; TypeScript, ESLint các file sửa và browser test watchlist/asset disabled đạt. `mix test` và `mix precommit`: 140 test, 2 lỗi ở kỳ vọng đã có sẵn (`SyncTest` chờ 21 mã trong danh mục hiện có 20; `SourceSyncTest` chờ ngưỡng 180 giây trong khi cấu hình trả 360). Không sửa các kỳ vọng ngoài phạm vi. Database test tạm riêng trên cổng 55433, không chạy test trên DB dev/server.
