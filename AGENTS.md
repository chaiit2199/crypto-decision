# Crypto Decision Lab — Quy tắc phát triển

Áp dụng cho toàn bộ monorepo Crypto Decision Lab. Đây là ứng dụng cá nhân hỗ trợ nghiên cứu và ra quyết định giao dịch tiền mã hóa, không phải SaaS đa người thuê. Code mới và code được chỉnh sửa phải tuân theo các quy tắc dưới đây. Không format hoặc refactor hàng loạt file ngoài phạm vi công việc.

## A. Phạm vi và thứ tự triển khai

- Chỉ triển khai **Phase 1 — Market Data Foundation** khi chưa có yêu cầu mở rộng.
- Phase 1 gồm Phoenix API, PostgreSQL, dữ liệu Binance, lịch đồng bộ, backfill, kiểm tra chất lượng dữ liệu và kiểm thử.
- Các giai đoạn sau lần lượt là Technical Analysis, Jev Decision Engine, Next.js Dashboard, Backtesting và Paper Trading. Chưa triển khai các phần này trong Phase 1.
- Không thực hiện lệnh giao dịch thật, không kết nối API đặt lệnh và không hứa hẹn lợi nhuận.
- Không dùng độ tin cậy do mô hình báo cáo làm xác suất giao dịch có lãi khi chưa hiệu chuẩn bằng dữ liệu thực nghiệm.
- Đọc repository trước khi sửa. Giữ code hợp lệ và thay đổi đang có của người dùng; không tự commit, reset hoặc ghi đè file không liên quan.
- Trước khi viết code, lưu trong `docs/`: tổng quan kiến trúc, cấu trúc module backend, ERD, kế hoạch Phase 1, thiết kế đồng bộ, API contracts và tiêu chí nghiệm thu.
- Triển khai từng bước có thể kiểm chứng. Báo rõ mục tiêu và file liên quan; chạy format, compile và test phù hợp; sửa lỗi trước khi chuyển bước.
- Không coi placeholder, mock hoặc tài liệu thiết kế là tính năng đã hoàn thành. Không báo test thành công khi chưa chạy.

## B. Kiến trúc và công nghệ

```text
apps/
  api/       # Phoenix REST API, domain contexts, Ecto, Oban
  web/       # Next.js App Router; triển khai ở Phase 4
infra/       # Docker Compose và cấu hình hạ tầng local
docs/        # Kiến trúc, API contracts, quyết định và hướng dẫn vận hành
README.md
AGENTS.md
```

- Backend là modular monolith: Elixir, Phoenix, Ecto, PostgreSQL, Oban, Req hoặc HTTP client được duy trì, Decimal và ExUnit.
- Frontend dùng Next.js App Router, React, TypeScript strict, Tailwind CSS, shadcn/ui, TradingView Lightweight Charts; dùng TanStack Query khi có nhu cầu và Zod để kiểm tra response bên ngoài tại ranh giới tích hợp.
- Xác minh phiên bản stable tương thích từ công cụ và tài liệu chính thức khi cài đặt; không tự đoán phiên bản dependency. Lưu lockfile do package manager tạo.
- Không thêm microservice, Kafka, Kubernetes, Redis, ClickHouse hoặc TimescaleDB khi chưa có nhu cầu được chứng minh.
- Backend sở hữu đồng bộ dữ liệu. Không gọi Binance hoặc Jev trực tiếp từ client component.
- Tách HTTP adapter khỏi nghiệp vụ; tách Jev khỏi engine tính chỉ báo.

| Context | Trách nhiệm |
| --- | --- |
| `MarketData` | Asset, symbol, giá mới nhất, thống kê 24h, candle, trạng thái đồng bộ và chất lượng dữ liệu. |
| `TechnicalAnalysis` | Chỉ báo, snapshot, feature và screener; giai đoạn sau. |
| `Decisions` | Provider behaviour, Jev adapter, chuẩn hóa và lưu quyết định, chính sách hiệu lực; giai đoạn sau. |
| `Backtesting` | Replay lịch sử, baseline và đánh giá hiệu suất; giai đoạn sau. |
| `PaperTrading` | Lệnh ảo, vị thế, mô phỏng khớp lệnh và danh mục; giai đoạn sau. |

## C. Quy tắc Elixir và backend

- Dùng quy ước Phoenix và `mix format` với 2 spaces cho Elixir; quy tắc 4 spaces bên dưới chỉ áp dụng cho frontend, JSON và SCSS.
- Module dùng PascalCase, hàm và biến dùng snake_case. Context là public boundary cho nghiệp vụ của mình.
- Controller chỉ kiểm tra đầu vào, gọi context và chuyển kết quả thành HTTP response. Oban worker chỉ điều phối lời gọi service; không đặt nghiệp vụ trong controller hoặc worker.
- Hàm có thể thất bại trả về kết quả có cấu trúc như `{:ok, value}` hoặc `{:error, reason}`. Không nuốt lỗi hoặc trả dữ liệu giả khi upstream thất bại.
- Dùng pattern matching và guard khi giúp contract rõ hơn. Thêm `@spec` và tài liệu cho public API hoặc logic có ràng buộc quan trọng.
- Dùng Ecto changeset cho validation và database constraint cho tính toàn vẹn khi có concurrency. Nhóm các ghi liên quan bằng transaction hoặc `Ecto.Multi` khi cần tính nguyên tử.
- Dùng Decimal/NUMERIC cho giá và khối lượng tài chính; không chuyển qua float trước khi lưu. API trả các giá trị này bằng chuỗi thập phân.
- Lưu thời gian theo UTC; API dùng ISO 8601 UTC. Tách thời điểm thị trường, thời điểm lấy dữ liệu và thời điểm cập nhật bản ghi.
- Process định kỳ phải nằm trong supervision tree, có timeout, shutdown rõ ràng và khả năng phục hồi.
- Tiêm HTTP adapter và clock khi cần để test retry, rate limit, candle closure và scheduler mà không phụ thuộc mạng thật hay chờ thời gian thực.

## D. Danh mục tài sản và Binance

Danh mục nghiên cứu hiện tại (21 asset, quote mặc định `USDT`), định nghĩa trong `MarketData.Universe`:

| Nhóm | Asset |
| --- | --- |
| Core / thanh khoản cao | BTC, ARB, OP, SUI, APT, RENDER |
| Tiềm năng cao | TIA, ONDO, PYTH, EIGEN, ASI |
| Vốn hóa vừa | TAO, IMX, BEAM, AKT, HNT |
| Mở rộng | IO, MKR, CFG, HONEY, BONK |

Seed upsert danh mục này và `enabled=false` các asset đã bị gỡ khỏi `@groups`. Không xóa lịch sử nến/phân tích. Cặp Spot USDT thực tế do `exchangeInfo` xác minh; mã không có trên Binance vẫn giữ trong danh mục với trạng thái không khả dụng.

- Base URL theo đặc tả: `https://data-api.binance.vision/api/v3`. Chỉ dùng public Spot market-data endpoints được tài liệu hóa: `/exchangeInfo`, `/ticker/price`, `/ticker/24hr`, `/klines`.
- Trước khi viết adapter, đọc tài liệu Binance chính thức để xác minh tham số, giới hạn batch, request weight, rate limit và JSON schema thực tế cho cả thành công và lỗi.
- Dùng `exchangeInfo` để xác minh symbol và trading status. Không giả định mọi asset đều có cặp Spot USDT; không thay asset không khả dụng bằng asset hoặc thị trường khác.
- Lưu mapping tường minh giữa asset, exchange, symbol, quote asset, trading status và enabled status.
- Batch request khi API hỗ trợ và hiệu quả hơn; theo dõi request weight thực tế, không gửi một request cho từng asset một cách mặc định.
- Xử lý 429/`Retry-After`, 418/IP ban, 5xx, timeout, JSON lỗi, schema thay đổi, symbol thiếu, dữ liệu cũ và kết quả chỉ có một phần.
- Retry có giới hạn với exponential backoff và jitter. Tạm ngừng collector trong thời gian bị ban; không tạo retry storm qua nhiều job.
- Fixture phải được ghi rõ là dữ liệu kiểm thử. Kiểm thử mặc định không phụ thuộc API Binance đang hoạt động.

## E. Lưu trữ và chất lượng dữ liệu

Các bảng Phase 1: `market_assets`, `market_symbols`, `market_latest_prices`, `market_ticker_stats`, `market_candles`, `market_sync_states`.

- `market_assets`: mã, tên, nhóm, enabled và timestamps; mã asset là duy nhất.
- `market_symbols`: asset FK, exchange, symbol, base/quote asset, trading status, enabled và timestamps; unique theo exchange và symbol.
- `market_latest_prices`: một snapshot giá mới nhất trên mỗi symbol, có `fetched_at` và `updated_at`. Không thêm lịch sử giá mỗi 30 giây.
- `market_ticker_stats`: một snapshot rolling 24h trên mỗi symbol, gồm thay đổi giá/phần trăm, high/low, base/quote volume, trade count và timestamps.
- `market_candles`: symbol FK, timeframe, open/close time, OHLC, base/quote volume, trade count, taker buy base/quote volume và inserted timestamp.
- Bắt buộc unique candle trên `(market_symbol_id, timeframe, open_time)`; định nghĩa rõ chính sách conflict/upsert và tránh để dữ liệu cũ ghi đè snapshot mới.
- `market_sync_states`: symbol, timeframe, sync type, checkpoint `last_synced_open_time`, status, thời điểm thử/thành công, lỗi gần nhất và timestamps. Chỉ cập nhật checkpoint khi dữ liệu tương ứng đã được lưu thành công.
- Giá phải dương; `high >= open`, `high >= close`, `low <= open`, `low <= close`, `high >= low`; volume không âm. Kiểm tra cấu trúc và thời gian trước khi ghi.
- Có FK, uniqueness và check constraints thích hợp. Index theo truy vấn thực tế; không partition sớm.
- Dùng 1H làm timeframe lịch sử chuẩn; mục tiêu tối đa 3 năm tùy ngày niêm yết và dữ liệu có thật.
- Backfill phân batch theo giới hạn API, có checkpoint, tiếp tục an toàn sau gián đoạn, ghi idempotent và phát hiện khoảng trống.
- Chỉ lưu candle đã đóng. Đối chiếu close time thực tế với thời gian hiện tại đáng tin cậy và độ trễ an toàn; không chỉ dựa lịch job hoặc timestamp đóng dự kiến.
- Incremental sync lấy phần thiếu hoặc overlap gần nhất để phục hồi sau lỗi; kiểm tra gaps và không vượt qua gaps mà làm mất khả năng backfill.
- Tổng hợp 4H/1D từ đủ candle 1H liên tiếp theo ranh giới UTC. Từ chối tổng hợp khi thiếu bất kỳ candle nguồn nào; chưa lưu timeframe tổng hợp khi chưa cần tối ưu.
- Dữ liệu thiếu hoặc stale phải có trạng thái rõ ràng; không thay giá thiếu bằng `0` hoặc tự tạo candle để lấp khoảng trống.

## F. Lịch đồng bộ

| Dữ liệu | Tần suất ban đầu |
| --- | --- |
| Exchange metadata | Mỗi ngày |
| Latest prices | Mỗi 30 giây |
| Rolling 24h statistics | Mỗi 5 phút |
| Candle 1H | Sau khi candle đóng |
| Historical backfill | Khởi tạo và theo yêu cầu |
| Data integrity | Mỗi ngày |

- Dùng Oban cho job bền vững, backfill và lịch phù hợp. Không giả định Oban Cron hỗ trợ chu kỳ dưới một phút.
- Poll giá bằng supervised process với monotonic scheduling, không cho lần chạy chồng lấn; xác định cách xử lý khi request kéo dài quá chu kỳ.
- Bảo đảm một collector có hiệu lực nếu chạy nhiều backend node, bằng cơ chế phối hợp có thể kiểm chứng; không xem singleton cục bộ là singleton toàn cluster.
- Các service đồng bộ phải gọi thủ công được để debug. Không công khai endpoint quản lý đồng bộ khi chưa có bảo vệ truy cập.

## G. REST API, bảo mật và vận hành

Endpoints Phase 1 dự kiến; chốt schema/versioning trong `docs/` trước khi triển khai:

```text
GET /api/markets
GET /api/markets/:symbol
GET /api/markets/:symbol/candles
GET /api/health
GET /api/system/market-data-status
```

- Kiểm tra symbol, timeframe, khoảng thời gian và pagination; giới hạn kích thước response và chi phí truy vấn.
- Response/error có schema nhất quán; thể hiện UTC timestamps, freshness và mức độ sẵn có của dữ liệu. Health check phản ánh đúng phụ thuộc đã kiểm tra.
- Secret lấy từ môi trường; không hardcode, đưa vào Git, log, URL hoặc response frontend. `.env.example` chỉ chứa giá trị mẫu không nhạy cảm.
- Tách database development và test. Test không được migrate, truncate hoặc xóa dữ liệu development.
- Docker Compose phục vụ PostgreSQL local, có health check và volume; không xóa volume người dùng khi debug.
- Log có cấu trúc: request duration/weight, last successful sync, missing candle count, freshness, job failures và retry count; tránh log payload nhạy cảm.
- README phải có setup, cấu hình, migration, seed, chạy ứng dụng, test và troubleshooting. Ghi rõ điều kiện cần và hạn chế còn lại.

## H. Kiểm thử và nghiệm thu Phase 1

- Test hành vi có ý nghĩa: parsing/validation, precision Decimal, idempotency, uniqueness, resume, gaps, candle chưa đóng, rate-limit/backoff, poll không overlap và API errors.
- Dùng ExUnit, Ecto SQL Sandbox cho DB tests và HTTP fixtures/mocks có nhãn rõ ràng. Test tích hợp thật phải tách riêng và không là điều kiện cho unit test offline.
- Trong `apps/api`, khi dự án đã được khởi tạo và dependencies sẵn sàng, chạy `mix format --check-formatted`, `mix compile --warnings-as-errors` và `mix test`.
- Chạy migration và smoke test trên database phù hợp. Báo rõ kiểm tra nào chưa chạy do thiếu Docker, PostgreSQL, dependency hoặc mạng.
- Không chạy build hoặc thêm test chỉ cho thay đổi tài liệu. Không sửa lỗi ngoài phạm vi để làm đẹp kết quả.

Chỉ đánh dấu Phase 1 hoàn thành khi xác minh đủ:

- PostgreSQL khởi động và migrations chạy được; đăng ký đúng danh mục `Universe` hiện tại và xác minh symbol Binance.
- Giá và thống kê 24h đồng bộ được; poll giá mỗi 30 giây không chồng lấn.
- Backfill và incremental sync hoạt động, resume được, không trùng candle, không lưu candle chưa đóng và phát hiện được gaps.
- Xử lý đúng rate limit, endpoint trả JSON hợp lệ, test phù hợp chạy thành công và README đủ để chạy hệ thống.

## I. Ràng buộc cho các giai đoạn sau

- Chỉ báo gồm EMA 20/50/200, RSI 14, MACD 12/26/9, ATR 14, ADX 14, relative volume và returns. Mỗi chỉ báo có công thức, lookback, test reference với tolerance và xử lý dữ liệu thiếu; không dùng dữ liệu tương lai.
- Jev dùng API được xác minh tại `https://api.typesafe.ai/docs`; các endpoint dự kiến `/v1/models` và `/v1/systemone` phải được kiểm tra trước khi code. Không đoán request/response hay giả định Jev trả trực tiếp schema ứng dụng.
- Dùng `DecisionProvider` behaviour với `JevProvider` và `MockDecisionProvider`. Không có Jev vẫn chạy được ở chế độ market-data-only.
- Chuẩn hóa quyết định thành `BUY`, `SELL`, `WAIT`, `NO_DATA`; lưu model/version, configuration version, feature snapshot, thời điểm quyết định/dữ liệu, raw response, probabilities và risk result để truy vết.
- Đánh giá ban đầu sau candle 4H hoàn tất với pre-filter cấu hình được; không gọi Jev mỗi 30 giây.
- Risk engine dùng quy tắc deterministic cho freshness, volatility, liquidity, stop-loss, take-profit, risk/reward và position sizing; thông số rủi ro phải cấu hình được.
- Backtest replay theo thời gian, giữ feature có sẵn tại thời điểm quyết định, tính phí/slippage, out-of-sample, walk-forward và so sánh baseline. Không báo hiệu suất chưa kiểm thử.
- Paper trading chỉ mô phỏng. Dashboard dự kiến có `/dashboard`, `/markets`, `/markets/[symbol]`, `/decisions`, `/backtesting`, `/paper-trading`, `/settings` với dark mode responsive và trạng thái loading/error/empty/stale.

## J. Quy tắc frontend

Các mục 1–9 bên dưới áp dụng cho code trong `apps/web/` khi triển khai frontend. Các đường dẫn frontend được hiểu tương đối với thư mục này. Tên component, helper và file ví dụ mô tả quy ước; phải kiểm tra chúng có tồn tại trước khi tái sử dụng.

## 1. Nguyên tắc chung

- Ưu tiên code đơn giản, đọc từ trên xuống hiểu được luồng xử lý.
- Mỗi hàm và component có một nhiệm vụ rõ ràng.
- Viết trực tiếp theo nghiệp vụ hiện tại; không tạo abstraction, cấu hình hoặc lớp trung gian cho nhu cầu chưa có.
- Tìm và dùng lại component, helper, type có sẵn trước khi tạo mới.
- Không gom các nghiệp vụ khác nhau vào một component với nhiều cờ boolean và nhánh điều kiện. Ví dụ: chi tiết thị trường và lịch sử quyết định giữ riêng; phần hiển thị giá có thể dùng chung.
- Giữ nguyên contract API, quyền thao tác và hành vi hiện tại khi chỉ chỉnh cấu trúc hoặc format.

## 2. Format: 4 spaces

- Dùng **4 dấu cách** cho mỗi cấp thụt lề trong TypeScript, JavaScript, TSX, JSX, JSON và SCSS. Không dùng tab.
- Dùng dấu nháy kép, dấu chấm phẩy và dấu phẩy cuối trong khai báo nhiều dòng.
- Mỗi dòng một câu lệnh. Không gộp nhiều thao tác để giảm số dòng.
- Giữa các nhóm import, các hàm và các khối xử lý khác nhiệm vụ có một dòng trống; không chèn nhiều dòng trống liên tiếp.
- Ưu tiên dòng dài không quá 120 ký tự. Tách lời gọi hàm, object hoặc JSX dài thành nhiều dòng; không cắt chuỗi URL hay nội dung chỉ để đủ giới hạn.
- Khi danh sách props, tham số hoặc thuộc tính cần xuống dòng, đặt mỗi mục trên một dòng và căn dấu đóng theo cấp mở.
- Không sửa thủ công file sinh tự động hoặc lockfile chỉ để đổi format.

## 3. Cấu trúc dự án

| Vị trí | Trách nhiệm |
| --- | --- |
| `app/` | Route, metadata, layout, đọc params và tải dữ liệu ban đầu cho trang. Giữ page gọn. |
| `components/<nghiệp vụ>/` | Hiển thị, state và tương tác của từng nghiệp vụ. |
| `components/ui/` | Thành phần shadcn/ui và UI dùng chung; kiểm tra component đã có trước khi tạo mới. |
| `lib/api/` | Hàm gọi API và Server Actions theo nghiệp vụ. |
| `lib/api/types.ts` | Kiểu dữ liệu request và response dùng chung. |
| `lib/cache/` | Cache theo nghiệp vụ, ví dụ `markets.ts`; khai báo khóa cache dùng chung trong `cache_key.ts`. |
| `lib/http/` | HTTP client và xử lý giao tiếp với backend. |
| `lib/server-actions.ts` | Cơ chế xử lý kết quả và lỗi Server Actions dùng chung. |
| `lib/format/` | Format tiền, số lượng, ngày và đơn vị. |
| `lib/dashboard/` | Cấu hình menu, header và sự kiện header. |
| `styles/components/` | SCSS theo nhóm component, dùng lại class hiện có. |

- Giữ cách đặt tên file của thư mục đang sửa; không đổi tên hàng loạt để thống nhất hình thức.
- Component và type dùng PascalCase; biến và hàm dùng camelCase; hằng số cố định dùng UPPER_SNAKE_CASE.
- Giữ tên field API theo contract, ví dụ `market_symbol_id`, `quote_asset`; không đổi qua lại chỉ để làm đẹp tên.
- Dùng alias `@/` cho import giữa các thư mục; dùng đường dẫn tương đối cho file cùng nhóm khi phù hợp với code hiện tại.
- Sắp import theo nhóm: thư viện ngoài → component nội bộ → API/helper/type → file cùng thư mục. Dùng `import type` cho type.

## 4. Biến và logic phải dễ đọc

- Tên biến diễn đạt ý nghĩa: `market`, `candle`, `isRefreshing`, `handleRefresh`. Tránh `temp`, `data2`, `result2` khi có thể đặt tên theo nghiệp vụ.
- Không tạo biến chỉ để đổi tên hoặc chuyển tiếp giá trị dùng một lần, ví dụ `const marketId = market.id` rồi dùng ngay mà không làm code rõ hơn.
- Nên đặt tên cho điều kiện dài hoặc phép tính được dùng nhiều lần. Không loại bỏ biến hữu ích chỉ để giảm số dòng.
- Không lưu state cho giá trị có thể tính trực tiếp từ props hoặc state hiện có.
- Dùng early return để xử lý lỗi, dữ liệu trống và điều kiện dừng trước luồng chính.
- Không dùng ternary lồng nhau. Ternary chỉ dành cho hai nhánh ngắn; nhiều nhánh dùng `if`, `switch` hoặc bảng ánh xạ đơn giản.
- Không lồng nhiều `if/else`, callback hoặc chuỗi `filter/map/reduce` dài trong một biểu thức. Tách bước xử lý khi cần để đọc được mục đích.
- Không tạo helper bọc một câu lệnh nếu không bổ sung ý nghĩa hoặc tái sử dụng thực tế.
- Không thêm `useMemo`, `useCallback`, custom hook hoặc generic phức tạp khi chưa có nhu cầu cụ thể.
- Dùng type rõ ràng; tránh `any`, ép kiểu nhiều lần và dấu `!` để bỏ qua trường hợp thiếu dữ liệu.
- Giữ đúng ý nghĩa `0`, `null` và `undefined`. Dùng `??` khi chỉ muốn thay giá trị thiếu; không dùng `||` làm mất giá trị `0` hợp lệ.

## 5. Function component và hàm xử lý

- Viết React function component bằng khai báo có tên: `export function MarketDetails(...)`. Page/layout dùng `export default function` theo quy ước route; không dùng class component.
- Khai báo props bằng `type` hoặc `interface` có tên như `MarketDetailsProps` khi có nhiều field. Destructure props ở tham số; tránh khai báo type dài chen vào chữ ký component.
- Sắp xếp file theo thứ tự: imports → types → hằng số/helper thuần → component. Trong component: hooks → giá trị suy ra → handlers → JSX.
- Gọi hooks ở cấp cao nhất của component hoặc custom hook, trước các nhánh return có điều kiện. Không gọi hooks trong vòng lặp, handler hoặc điều kiện.
- Không định nghĩa component con bên trong thân component cha. Đặt cùng file nếu chỉ phục vụ màn hình đó; chuyển sang file riêng khi cần tái sử dụng hoặc khối hiển thị đủ lớn.
- Helper không phụ thuộc state/props đặt ngoài component. Handler phụ thuộc state đặt trong component, tên bắt đầu bằng `handle`, ví dụ `handleSubmit`, `handleRefresh`.
- Props callback đặt theo sự kiện: `onClose`, `onSaved`, `onRefresh`. Truyền dữ liệu và callback cần thiết; tránh truyền toàn bộ state hoặc object lớn chỉ để dùng một field.
- Render phải thuần: không gọi API, cập nhật state hoặc thực hiện side effect trong JSX. Effect chỉ dùng để đồng bộ với hệ thống bên ngoài, không dùng để tính lại giá trị có thể suy ra trực tiếp.
- Không ép mọi component vào một template có hooks, state hoặc handlers rỗng. Component chỉ hiển thị thì giữ một hàm nhận props và trả JSX.

## 6. JSX/HTML gọn, không lồng chồng chéo

- JSX tập trung vào hiển thị. Đặt logic submit, tạo payload và xử lý nghiệp vụ trong hàm bên ngoài phần `return`.
- Handler inline chỉ dùng cho thao tác ngắn như `onClick={() => setOpen(true)}`. Handler có nhiều bước phải có tên riêng.
- Không viết nhiều thẻ HTML lồng nhau trên cùng một dòng. Thẻ chỉ chứa nội dung chữ ngắn có thể giữ trên một dòng.
- Không thêm nhiều lớp `div` chỉ để bọc. Mỗi wrapper phải có mục đích rõ ràng về bố cục, style hoặc ngữ nghĩa; dùng Fragment nếu chỉ cần nhóm phần tử.
- Khi một khối JSX quá sâu hoặc có nhiều nhánh độc lập, tách thành component có tên theo chức năng. Không tách từng thẻ nhỏ thành component một cách máy móc.
- Trạng thái loading, lỗi và rỗng dùng nhánh rõ ràng hoặc component riêng; không nối thành ternary nhiều tầng.
- Tái sử dụng `Input`, `Select`, `Dialog`, `Table` và các component sẵn có khi phù hợp.
- Dùng HTML hợp lệ: `col` nằm trong `colgroup`, `tr` nằm trong nhóm hàng của bảng, không lồng `button`, `a` hoặc `form` cùng loại vào nhau.
- Dùng `key` ổn định theo ID khi render danh sách có thể thay đổi; không dùng giá trị ngẫu nhiên.
- Mỗi `id` HTML phải duy nhất. Input có label; nút chỉ có icon phải có tên truy cập như `aria-label`.

Ví dụ cách trình bày JSX với 4 spaces:

```tsx
type MarketActionsProps = {
    isRefreshing: boolean;
    onRefresh: () => void;
};

export function MarketActions({ isRefreshing, onRefresh }: MarketActionsProps) {
    return (
        <div className="market-actions">
            <button
                type="button"
                className="market-actions__refresh"
                disabled={isRefreshing}
                onClick={onRefresh}
            >
                Cập nhật dữ liệu
            </button>
        </div>
    );
}
```

## 7. Style theo component: SCSS kết hợp Tailwind

- Đây là quy ước frontend được giữ từ repository ban đầu. Khi khởi tạo Phase 4, xác minh pipeline SCSS/Tailwind tương thích với phiên bản đã chọn; ghi quyết định trong `docs/` trước khi áp dụng hoặc thay đổi pipeline.

- Không viết CSS bằng `style={{ ... }}` hoặc thẻ `<style>` trong JSX. Style do ứng dụng quản lý đặt trong file SCSS theo component hoặc nhóm nghiệp vụ.
- Tạo hoặc mở rộng file phù hợp trong `styles/components/`; đăng ký file mới qua `styles/components/index.scss` theo cách tổ chức hiện có. Không tạo thêm hệ thống styling song song.
- Dùng class có tên theo component và chức năng, ví dụ `.market-details`, `.market-details__summary`, `.market-details--compact`. Giữ quy ước tên hiện có khi mở rộng component cũ.
- Dùng `@apply` để gom utility Tailwind vào class SCSS. Dùng thuộc tính CSS thông thường cho phần đặc thù hoặc giá trị không có utility phù hợp; không ép mọi thuộc tính thành utility.
- Chuỗi `className` dài, lặp lại hoặc chứa nhiều nhánh responsive/state phải chuyển sang class SCSS có tên. Có thể giữ vài utility ngắn, rõ nghĩa trong JSX; không viết cả bố cục và toàn bộ style thành một chuỗi dài.
- Dùng SCSS nesting cho element, modifier và trạng thái như `&__title`, `&--compact`, `&:hover`. Tránh selector lồng sâu theo toàn bộ cây DOM; ưu tiên tối đa 2–3 cấp.
- Tái sử dụng theme token, class form/button/modal có sẵn. Không hardcode lại màu, radius hoặc shadow đã có token; không lạm dụng `!important` để ghi đè.
- Với trạng thái hữu hạn, đổi class hoặc `data-*` rồi định nghĩa style trong SCSS. Nếu thư viện bắt buộc style động, giữ phần tích hợp tối thiểu và không trộn style bố cục tĩnh vào đó.
- SCSS cũng dùng 4 spaces. Nhóm `@apply` theo bố cục, khoảng cách và kiểu chữ khi một dòng quá dài.

Ví dụ tách style khỏi JSX:

```tsx
<section className="market-details">
    <h3 className="market-details__title">Thông tin thị trường</h3>
    <div className="market-details__summary">{children}</div>
</section>
```

```scss
.market-details {
    @apply rounded-lg border border-theme-primary-border p-4;

    &__title {
        @apply mb-4 text-base font-semibold;
    }

    &__summary {
        @apply grid gap-4;

        @media (min-width: 640px) {
            @apply grid-cols-2;
        }
    }
}
```

## 8. Dữ liệu, API và validation

- Giữ page/layout là Server Component mặc định. Chỉ thêm `"use client"` cho phần cần state, effect hoặc tương tác trình duyệt.
- Tải dữ liệu ban đầu ở server theo cấu trúc trang hiện có. Các request độc lập có thể chạy bằng `Promise.all`; request phụ thuộc phải giữ đúng thứ tự.
- Dùng HTTP client, Server Actions và cơ chế báo lỗi sẵn có. Không thêm lớp gọi API hoặc `try/catch` trùng lặp không có xử lý riêng.
- Form chuyển dữ liệu thành payload có type rồi gọi action. Hiển thị lỗi backend trả về theo kết quả `{ ok: false, message }`.
- Dùng Zod để validate response bên ngoài tại ranh giới HTTP theo contract dùng chung; không lặp lại `parse`/`safeParse` cùng dữ liệu trong component hoặc Server Actions và không nhân bản validation nghiệp vụ của backend.
- Không thêm hàm `validatePayload`, guard hoặc kiểm tra từng field chỉ để lặp lại ràng buộc backend đã xử lý. Chỉ thêm kiểm tra phía client khi có yêu cầu UX cụ thể; phân biệt rõ chuyển đổi payload với validation nghiệp vụ.
- Backend chịu trách nhiệm validation nghiệp vụ, quyền và phạm vi truy cập. Giữ luồng xác thực và kiểm soát truy cập sẵn có; không xem việc ẩn nút trên UI là cơ chế bảo vệ API.
- Có thể dùng `required`, `maxLength`, `accept`, loading và disabled để hỗ trợ nhập liệu và ngăn gửi lặp.
- Chuyển kiểu dữ liệu theo contract; giữ `null` khi chưa có giá. Không tự thêm fallback, field hoặc quy tắc nghiệp vụ backend không yêu cầu.
- Sau mutation, cập nhật UI hoặc revalidate các trang bị ảnh hưởng theo luồng hiện có.
- Tách tùy chọn và sự kiện `create` với `actions` của header; không dùng lẫn hai mục đích.
- Không đưa token, mật khẩu hoặc nội dung `.env.local` vào code, log hoặc tài liệu.

## 9. Kiểm tra trước khi hoàn thành

- Đọc lại diff: có biến thừa, ternary lồng nhau, wrapper dư hoặc thay đổi ngoài yêu cầu không?
- Kiểm tra format 4 spaces ở phần sửa và JSX có cấu trúc dễ nhìn.
- Kiểm tra function component có props rõ ràng, không thừa state/helper; style nằm đúng SCSS và không có chuỗi utility dài trong JSX.
- Khi sửa TypeScript/TSX, chạy `npx tsc --noEmit` và lint các file liên quan; dùng `npm run lint` khi cần kiểm tra toàn dự án.
- Kiểm tra hành vi bị ảnh hưởng và các trạng thái lỗi/loading phù hợp. Chỉ thêm test khi giúp bảo vệ hành vi có ý nghĩa.
- Không chạy build hoặc thêm test chỉ cho thay đổi tài liệu/format đơn giản. Nếu kiểm tra gặp lỗi có sẵn, báo rõ và không sửa lan sang phần khác khi chưa cần thiết.
