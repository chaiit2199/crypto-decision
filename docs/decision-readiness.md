# Đánh giá dữ liệu và thiết kế quyết định với Jev

> Cập nhật triển khai: đã bổ sung phân tích Jev mỗi 5 phút theo yêu cầu tiếp theo, với EMA20/50, RSI14 và returns trên 1H; xem [jev-integration.md](jev-integration.md). Nội dung bên dưới là đánh giá ban đầu và thiết kế đầy đủ hơn, không đồng nghĩa toàn bộ roadmap đã được triển khai. Smoke xác thực key hiện trả HTTP 401; chưa có kết quả suy luận thật thành công.

Đánh giá tại 2026-10-17, khoảng 22:30 giờ Việt Nam. Đây là phân tích mức sẵn sàng và thiết kế đề xuất, chưa phải engine giao dịch đã triển khai hoặc khuyến nghị mua/bán một tài sản cụ thể. Thay đổi code trong lần này chỉ là múi giờ chart và kiểm thử liên quan.

## Kết quả kiểm tra dữ liệu thật

API đang bật collector, có 32 assets và 28 cặp Binance Spot/USDT hoạt động. TON, KAS, HNT, MEW chưa có mapping khả dụng trong lần kiểm tra; không thay thế bằng futures hoặc asset khác. Cả 28 snapshot giá và thống kê 24h đang fresh khi lấy mẫu. Backfill/incremental có 28 trạng thái complete mỗi loại, không có job lỗi được báo trong mẫu status.

Đã chạy SELECT chỉ đọc, không chạy migration/collector và không ghi DB: tổng cộng **688.001 nến 1H**, trên 28 cặp. Đối chiếu từng cặp bằng lag(open_time): **0 giờ thiếu nội bộ** giữa nến đầu/cuối; **0 nến chưa đóng**; **0 vi phạm các điều kiện đã kiểm tra** (giá low dương, high bao open/close, low bao open/close, high >= low, base_volume không âm). Đây không phải chứng nhận mọi field, mọi ngày niêm yết hoặc mọi giá đều khớp hoàn toàn với sàn. Chưa đối chiếu lại toàn bộ lịch sử với nguồn độc lập. Status chưa có các state integrity đã đo; không diễn giải missing_count=null thành 0.

| Cặp / nhóm | Số nến 1H | Dữ liệu đầu tiên UTC | Dữ liệu cuối UTC |
| --- | ---: | --- | --- |
| AAVEUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| ADAUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| ALGOUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| ALTUSDT | 23,909 | 2024-01-25 10:00 | 2026-10-17 14:00 |
| ARBUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| AVAXUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| BNBUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| BTCUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| DOGEUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| ETHUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| GRTUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| HYPEUSDT | 556 | 2026-09-24 11:00 | 2026-10-17 14:00 |
| INJUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| LINKUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| NEARUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| ONDOUSDT | 13,297 | 2025-04-11 14:00 | 2026-10-17 14:00 |
| OPUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| PEPEUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| QNTUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| RENDERUSDT | 19,519 | 2024-07-26 08:00 | 2026-10-17 14:00 |
| SEIUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| SHIBUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| SOLUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| SUIUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| UNIUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| XLMUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| XRPUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |
| ZECUSDT | 26,280 | 2023-10-18 15:00 | 2026-10-17 14:00 |

Không suy ra ngày niêm yết chỉ từ nến đầu tiên. Nhiều cặp đủ cửa sổ khoảng 3 năm đang cấu hình; ALT, ONDO, RENDER và đặc biệt HYPE có lịch sử ngắn hơn trong DB. HYPE có 556 giờ: tối đa 139 khối 4H hoặc 23 ngày trước khi loại các khối chưa đủ tại biên, nên không đủ EMA200 trên 4H/1D. Cần trả NO_DATA cho chiến lược bắt buộc các chỉ báo đó, không mượn thị trường khác để lấp.

## Dữ liệu hiện có dùng được đến đâu

OHLCV 1H, số giao dịch và taker-buy volume là nền tảng để nghiên cứu chiến lược Spot 4H/1D. Giá 30 giây chủ yếu phục vụ hiển thị/freshness; chỉ lưu snapshot, không có lịch sử tick để backtest scalping. Thống kê rolling 24h cũng chỉ lưu bản mới nhất: không được dùng snapshot hôm nay làm feature cho quá khứ. Nếu cần thống kê lịch sử, tái tính từ các nến đã đóng với cửa sổ được định nghĩa rõ.

Chưa có engine chỉ báo, feature snapshot, tín hiệu BUY/SELL, dữ liệu vị thế, backtest chi phí hoặc hiệu chuẩn xác suất. Chưa có bid/ask/order book để đo spread/depth; quote volume chỉ là proxy thanh khoản, không phải spread hay khả năng khớp lệnh. Dữ liệu funding/OI, tin tức, on-chain chưa có và không được để Jev tự suy diễn như dữ kiện đã quan sát.

Giới hạn 120 nến trên chart là giới hạn hiển thị, không phải số nến engine chỉ báo nên tải. EMA200 cần tối thiểu 200 nến cho khởi tạo và thêm warm-up; lượng warm-up phải được kiểm chứng bằng tolerance/reference, không đồng nhất với lịch sử 120 nến UI. Chỉ tổng hợp 4H/1D từ đủ nến 1H liên tiếp theo UTC; biên chưa đủ phải được đánh dấu và bỏ qua đúng cửa sổ, không nội suy.

## Chỉ báo và cách kết hợp đề xuất

Giả định “rsa” là RSI. Tính toán bằng code deterministic trong `TechnicalAnalysis`, tách khỏi Jev; Decimal, công thức/version, lookback và test reference rõ ràng.

| Nhóm | Bộ chỉ báo ban đầu | Vai trò |
| --- | --- | --- |
| Xu hướng | EMA20/50/200, độ dốc EMA, returns | Nhận diện xu hướng 1D/4H và hướng ưu tiên |
| Động lượng | RSI14 theo Wilder, MACD12/26/9 | Đánh giá nhịp tăng/giảm, phục hồi và suy yếu |
| Sức mạnh xu hướng | ADX14 và +DI/-DI | Phân biệt thị trường có xu hướng với đi ngang; ADX riêng không cho biết hướng |
| Biến động/rủi ro | ATR14, ATR/close | Chuẩn hóa khoảng dừng lỗ và tránh vị thế quá lớn khi biến động tăng |
| Xác nhận thanh khoản | Relative volume từ các nến đã đóng, quote volume, trade count | So sánh lực tham gia với nền trước đó |
| Cấu trúc giá | Phá đỉnh/đáy N nến trước, hỗ trợ/kháng cự có quy tắc | Xác định điều kiện vào lệnh và điểm vô hiệu hóa |

Không cộng RSI, EMA và MACD như ba bằng chứng độc lập: chúng cùng được suy ra từ giá. Tách nhóm tín hiệu, đo mức đóng góp bằng ablation test. RSI <30 không tự động là BUY, >70 không tự động là SELL; xu hướng mạnh có thể giữ RSI ở vùng cực trị. [Tài liệu RSI chính thức](https://www.tradingview.com/support/solutions/43000502338-relative-strength-index-rsi/) mô tả công thức, mặc định 14 nến và yêu cầu đánh giá cùng bối cảnh.

Thiết kế đầu tiên để kiểm thử: 1D xác định bối cảnh, 4H quyết định, 1H dùng thêm cho điểm vào nếu kiểm thử cho thấy có ích. Đánh giá sau nến 4H đóng và dữ liệu đã commit. Nếu thiếu warm-up/gaps/stale: NO_DATA. Nếu tín hiệu mâu thuẫn, không có lợi thế sau chi phí hoặc rủi ro không đạt: WAIT. BUY chỉ là ứng viên tăng vị thế khi có cấu trúc/xác nhận và risk engine cho phép. SELL trong hệ Spot nghĩa là giảm/thoát vị thế đã có; nếu không có vị thế, không tự diễn giải thành mở short. Cần position context hoặc ghi rõ tín hiệu SELL là tín hiệu thoát theo giả định.

Các ngưỡng RSI, ADX, relative volume, ATR multiple và risk/reward là tham số nghiên cứu, chưa có bộ ngưỡng tối ưu cho danh mục này. Không chọn ngưỡng rồi báo hiệu quả khi chưa backtest.

## Jev: contract xác minh và vai trò

Đã đọc [OpenAPI TypeSafe](https://api.typesafe.ai/openapi.json) từ [Swagger](https://api.typesafe.ai/docs), phiên bản API 0.2.0. GET `/v1/models` yêu cầu Bearer token, trả model/alias có quyền truy cập. POST `/v1/systemone` nhận `model`, `state` (string/object/array), `questions`; câu hỏi choice có criteria do ứng dụng khai báo. Response có `answers`, model được dùng, usage; choice có lựa chọn, confidence và probabilities. Chưa gọi inference có xác thực, chưa xác nhận model nào tài khoản được phép dùng. Tên `jev-latest` trong ví dụ tài liệu không chứng minh quyền truy cập hoặc phiên bản cố định.

Đề xuất: gửi feature snapshot có cấu trúc đã tính sẵn (cutoff UTC, 1D/4H/1H, giá trị chỉ báo và độ dốc, chất lượng dữ liệu, trạng thái vị thế, điều kiện rủi ro), rồi hỏi riêng về regime, mức đồng thuận/mâu thuẫn và ứng viên hành động. Không gửi ảnh chart thay dữ liệu số khi đã có OHLCV. Không yêu cầu model tự tính lại RSI/EMA từ văn bản. Prompt phải giới hạn kết luận vào dữ kiện trong snapshot.

`confidence` và `probabilities` là đầu ra phân loại của model theo câu hỏi; **không được gọi là xác suất giá tăng hoặc xác suất giao dịch có lãi** khi chưa kiểm chứng/hiệu chuẩn theo outcome cụ thể. Không ép response thành lời giải thích tự do mà contract không bảo đảm; lý do hiển thị có thể dựng từ rule outcomes và các câu hỏi có cấu trúc.

Pipeline đề xuất:

1. `MarketData` kiểm tra dữ liệu đóng/fresh/đủ liên tiếp.
2. `TechnicalAnalysis` tính indicator và feature snapshot, mỗi snapshot có version và cutoff.
3. Baseline rule tạo candidate; bộ lọc loại NO_DATA/không có tín hiệu trước khi tốn lượt gọi model.
4. `Decisions.DecisionProvider` có `JevProvider` và `MockDecisionProvider`; gọi server-side, key từ môi trường. Có timeout/retry hữu hạn, validate response và trạng thái provider_error; lỗi provider không được biến thành tín hiệu có thể giao dịch.
5. Risk engine deterministic quyết định chấp nhận/từ chối, stop-loss, take-profit, risk/reward sau chi phí và position sizing. Jev không được vượt giới hạn này.
6. Lưu kết quả BUY/SELL/WAIT/NO_DATA, reason codes, feature snapshot, model được trả về, config/prompt version, raw response đã kiểm soát truy cập, xác suất model, risk result và thời hạn hiệu lực. Dữ liệu thiếu và provider_error có nguyên nhân riêng.

Chỉ gọi sau nến 4H, không mỗi lần web polling. Nếu gọi tất cả 28 cặp mỗi 4H thì tối đa 168 lượt/ngày trước lọc/retry; đây là số lượt, chưa phải ước tính tiền vì chưa xác minh biểu phí/token thực tế. Dedupe theo symbol + close time + feature/config/model version. Không có Jev vẫn chạy market-data và baseline rõ nhãn.

## Tiêu chuẩn đánh giá “đúng nhất”

Phải định nghĩa đúng điều gì và trong bao lâu. Ví dụ nghiên cứu: phân loại lợi suất 24 giờ tiếp theo từ thời điểm có thể vào lệnh, sau phí/slippage, thành tăng/giảm/trung tính. Đây là đề xuất horizon, chưa tối ưu. Quyết định giao dịch còn phụ thuộc stop/take-profit, sizing và vị thế nên không đồng nhất với dự báo chiều giá.

- Chia dữ liệu theo thời gian, walk-forward và tập test cuối chưa dùng để chỉnh ngưỡng; purging/embargo khi các nhãn tương lai chồng lấn. Tuyệt đối không chia ngẫu nhiên các nến lân cận.
- Feature chỉ dùng dữ liệu có sẵn tại thời điểm quyết định. Với khung 1D, chỉ dùng ngày đã đóng lúc đó; rolling 24h không lấy snapshot hiện tại. Pivot dùng nến bên phải để xác nhận chỉ được dùng sau khi các nến xác nhận đã đóng.
- Entry sau khi tín hiệu có thể được tạo ra; tính phí, spread/slippage giả định, độ trễ. Với nến mà stop và target cùng bị chạm, dùng dữ liệu chi tiết hơn hoặc giả định thứ tự bảo thủ, không chọn cách có lợi.
- So sánh giữ USDT, buy-and-hold, rule baseline và rule + Jev trên cùng dữ liệu/chi phí. Chỉ giữ Jev nếu cải thiện kết quả out-of-sample ổn định so với chi phí và độ phức tạp.
- Đo expectancy sau chi phí, max drawdown, profit factor, turnover, số giao dịch/độ phủ quyết định, kết quả theo asset và regime; kèm độ bất định. Accuracy cao nhờ hầu hết là WAIT không chứng minh chiến lược tốt.
- Nếu muốn hiển thị xác suất thực nghiệm: đo reliability/Brier score trên outcome/horizon đã chốt và tập ngoài mẫu, hiệu chuẩn bằng tập riêng. Chưa hiệu chuẩn phải ghi đúng là model score.
- Jev hiện tại có thể đã được huấn luyện với thông tin sau các mốc lịch sử đang backtest; snapshot đúng cutoff không loại trừ hoàn toàn knowledge leakage của model. Lưu model/prompt và ưu tiên forward paper evaluation để xác nhận kết quả trước khi tin vào backtest có model.
- Paper trading trước, không nối API đặt lệnh thật trong phạm vi này.

## Thứ tự triển khai được đề xuất

1. Phase 2: indicator engine + reference tests + data readiness per timeframe; hiển thị indicator trên chart.
2. Baseline 1D/4H và bộ backtest tối thiểu để định lượng trước khi thêm model.
3. Phase 3: Jev adapter, feature/decision persistence, risk engine và đánh giá so sánh.
4. Forward paper trading, theo dõi drift/chất lượng dữ liệu; chưa có bằng chứng thì giữ WAIT/NO_DATA.

Kết luận về mức sẵn sàng: dữ liệu hiện tại đủ nền tảng triển khai và kiểm thử chỉ báo cho phần lớn cặp, chưa có bằng chứng một chiến lược hoặc Jev có khả năng dự báo có lợi nhuận. Không có bộ chỉ báo bảo đảm xu hướng đúng nhất trong mọi giai đoạn thị trường.
