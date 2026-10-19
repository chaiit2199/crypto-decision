# Bảng giá development

## Cập nhật giao diện và đồng bộ - 2026-10-19

- Chu kỳ hiện tại trong backend: giá 300 giây, thống kê 24h mỗi 5 phút, nến 1H vào phút 01 mỗi giờ; Jev theo slot 15 phút. Không thay lịch collector trong đợt chỉnh UI này.
- Frontend lấy chu kỳ từ `status.price_poll_interval_seconds`, truyền cùng chu kỳ xuống biểu đồ; mỗi request hoàn tất mới hẹn lần tiếp theo. Giữ chu kỳ hợp lệ gần nhất khi API lỗi, mặc định 300 giây khi chưa có status. Nút làm mới tải lại cả danh mục và lịch sử đang xem. Đồng hồ freshness cập nhật riêng mỗi giây, không gọi mạng.
- Giao diện nền xanh đen, điểm nhấn mint, bố cục biểu đồ và phân tích song song trên desktop, xếp dọc trên mobile. Tổng quan thể hiện số tài sản, số mã tăng/giảm có thống kê còn mới; không dùng dữ liệu thiếu/cũ để suy ra biến động.
- Bỏ wording tần suất poll, hướng dẫn thao tác lặp và chi tiết job trên màn hình chính. Thu gọn thông số chỉ báo trong disclosure; giữ timestamp, cảnh báo lỗi/stale, nguồn dữ liệu và attribution.
- Nghiệm thu: TypeScript, ESLint, kiểm thử browser cho polling theo backend, refresh cả biểu đồ, freshness khi không fetch, lỗi vẫn giữ snapshot, chuyển cặp/khung và không tràn trang mobile. Kiểm tra ảnh desktop/mobile nếu môi trường browser khả dụng.

Phạm vi theo yêu cầu: một trang theo dõi giá trong `apps/web`, chưa triển khai dashboard quyết định, chỉ báo hoặc giao dịch. Phoenix vẫn sở hữu việc lấy dữ liệu Binance và ghi PostgreSQL.

## Luồng dữ liệu

- Development bật sync mặc định; `MARKET_SYNC_ENABLED=false` tắt poller, queue và Cron. Production vẫn phải bật tường minh; test luôn tắt.
- Repo Oban dùng chung ở `config/config.exs`; runtime ghép queue và Cron riêng cho market/Jev theo công tắc môi trường. Giá dùng supervised poller 5 phút, không dùng Cron dưới một phút. Nếu backfill chiếm khóa, poller thử lại khóa sau 1 giây; deadline chia sẻ vẫn chặn request Binance dư.
- Bootstrap ưu tiên snapshot giá và thống kê trước backfill. Job backfill có độ ưu tiên thấp hơn các job cập nhật hiện tại.
- Next.js App Router tải dữ liệu ban đầu phía server. Route `/api/market-monitor` chỉ đọc hai endpoint Phoenix cố định (`/api/markets`, `/api/system/market-data-status`); không chuyển tiếp URL tùy ý hoặc lộ cấu hình DB.
- Client đọc lại route này theo `price_poll_interval_seconds` (hiện là 5 phút), không request chồng lấn; backend lấy giá mỗi 5 phút. Có nút tải lại và tìm kiếm asset/cặp. Đây là cập nhật snapshot, không phải WebSocket từng giao dịch.
- Schema Zod ở ranh giới HTTP; Decimal giữ dưới dạng chuỗi. UI thể hiện thời điểm lấy giá, trạng thái thiếu/cũ và số mã tăng/giảm có thống kê còn mới; không tạo giá giả.

## Cấu trúc và giao diện

`app/` chứa route, layout và page; `components/markets/` chứa bảng giá; `lib/api/` chứa contract và fetch; `styles/components/` chứa SCSS theo component. TypeScript strict, 4 spaces, named components. Bảng tối màu, màu xanh/đỏ cho biến động 24h, trạng thái stale riêng và bảng cuộn trên màn hình nhỏ.

Chọn Tailwind 3.4 cùng Sass/PostCSS để giữ quy ước SCSS + `@apply` của repository; không nâng lên Tailwind 4 vì [Tailwind 4 không thiết kế để chạy cùng Sass](https://tailwindcss.com/docs/compatibility#sass-less-and-stylus). [Next.js hỗ trợ Sass](https://nextjs.org/docs/app/guides/sass). Phiên bản thực tế được package manager khóa trong `apps/web/package-lock.json`: Next.js 16.4.2, React 19.3.1, TypeScript 6.0.3, Tailwind 3.4.19, Sass 1.105.2. TypeScript 7 chưa được typescript-eslint hỗ trợ; dùng 6.0.3 đã kiểm tra type/lint/build.

## Nghiệm thu

- Khởi động web local, đọc dữ liệu DB thật qua Phoenix; thời điểm snapshot tiếp tục tăng khi collector hoạt động.
- Hiển thị đủ danh mục, cho biết asset không có Spot USDT; tìm kiếm ETH dẫn tới cặp ETHUSDT.
- API lỗi vẫn giữ snapshot trước đó với cảnh báo mất kết nối; không gắn nhãn fresh khi quá `price_max_age_seconds` backend trả về (hiện là 360 giây).
- Kiểm tra cấu hình dev/prod/test và ưu tiên job; chạy `mix precommit`, TypeScript, ESLint và build web.
- Không ghi dữ liệu dev trong test. Giữ server người dùng đang chạy; nếu cổng API bận, khởi động instance mới trên cổng khác và đặt `API_BASE_URL` cho web.

## Nhấp nháy, chi tiết và chart

- Luồng hiện tại: Binance → poller Phoenix khoảng 5 phút → PostgreSQL → API Phoenix → Next.js server route → trình duyệt polling 5 phút sau khi request trước hoàn tất. Không dùng WebSocket; giá có thể trễ do mạng, backfill, cooldown. Thống kê 24h cập nhật mỗi 5 phút.
- Giá nháy xanh khi tăng, đỏ khi giảm, một lần trong khoảng 0,8 giây; so sánh chuỗi Decimal chính xác bằng BigInt, không làm tròn qua float. Không nháy khi render lần đầu, cùng giá hoặc thiếu dữ liệu; tôn trọng prefers-reduced-motion.
- Bấm tên/cặp hoặc dòng tài sản mở panel chi tiết ngay trên bảng; có nút mã truy cập bằng bàn phím, trạng thái lựa chọn rõ ràng. Panel dùng snapshot đang có, tự cập nhật theo bảng. Hiển thị giá, biến động, high/low, volume và freshness. Asset chưa có thị trường vẫn xem được thông tin thiếu dữ liệu.
- Chart dùng TradingView Lightweight Charts theo kiến trúc dự án. Nến OHLC và volume lấy từ PostgreSQL qua `/api/markets/:symbol/candles`, 120 nến đã đóng, các khung 1H/4H/1D. Khung 4H/1D tổng hợp phía backend; thiếu dữ liệu phải báo rõ, không tạo nến thay thế.
- Next.js thêm route chỉ đọc `/api/market-candles?symbol=BTCUSDT&timeframe=1h`; giới hạn timeframe và số nến cố định, không chấp nhận URL tùy ý. Dùng Zod ở ranh giới backend response; có trạng thái tải/lỗi/rỗng, hủy request cũ khi chuyển mã/khung. Đọc lại chart theo cùng chu kỳ backend trả về cho bảng giá; giữ viewport khi cùng mã/khung và dữ liệu cập nhật.
- Chỉ đổi Decimal sang Number tại adapter vẽ canvas vì thư viện chart yêu cầu số; dữ liệu API, lưu trữ, so sánh tăng/giảm và các giá trị hiển thị vẫn giữ chuỗi gốc. Đường snapshot tách riêng, không ghi snapshot vào nến đã đóng. Trục thời gian chart hiện hiển thị giờ Việt Nam; timestamp gốc vẫn là UTC (xem cập nhật múi giờ bên dưới).
- Giữ attribution TradingView và NOTICE của thư viện. Kiểm tra precision/flash, đổi mã/khung nhanh, thiếu dữ liệu, lỗi API, chart resize và giảm chuyển động; chạy TypeScript, lint, build và browser checks khi công cụ khả dụng.

## Múi giờ hiển thị

Chart hiển thị giờ Việt Nam (`Asia/Ho_Chi_Minh`, UTC+7) cho tick trên trục, nhãn crosshair và thời gian nến trong phần mô tả. Formatter xử lý cả chuyển ngày/tháng/năm, không phụ thuộc múi giờ máy người xem. Timestamp truyền vào chart và lưu trong DB vẫn là UTC; không cộng 7 giờ vào dữ liệu. Nến 4H/1D vẫn tổng hợp theo ranh giới UTC: nến ngày 00:00 UTC xuất hiện ở 07:00 giờ Việt Nam, không phải một nến ngày mới tổng hợp từ 00:00 giờ Việt Nam.

## Kiểm tra đợt UI 2026-10-19

- Đã chạy thành công: `npx tsc --noEmit`, `npm run lint`, biên dịch SCSS qua Sass + Tailwind + Autoprefixer (0 warning), hai test Decimal/múi giờ bằng Playwright runner.
- Đã bổ sung browser tests cho chu kỳ backend, làm mới nến và freshness độc lập với fetch; chưa chạy browser suite/ảnh desktop-mobile vì quyền chạy Next.js local bị từ chối.
- `npm run build` bị sandbox chặn lúc Turbopack mở cổng nội bộ để xử lý stylesheet; yêu cầu chạy build ngoài sandbox cũng bị từ chối. Chưa xác nhận production build. Không thay đổi backend hay triển khai lên hosting.

## Tín hiệu Jev trong danh mục — 2026-10-19

Mỗi `MarketRow` đọc analysis của đúng cặp đang chọn (USD/USDT) từ response danh mục đã có. Chỉ asset enabled, market đang giao dịch, analysis enabled/ready/fresh và chưa tới `valid_until` mới được hiển thị tín hiệu BUY/SELL. BUY có nhãn Jev · MUA và hiệu ứng xanh; SELL có nhãn Jev · BÁN và hiệu ứng đỏ. WAIT, NO_DATA, lỗi, chưa có dữ liệu hoặc hết hạn không có nhãn/hiệu ứng tín hiệu. Đồng hồ hiện có cập nhật mỗi giây để gỡ tín hiệu hết hạn, kể cả khi request tiếp theo chưa thành công. Không thêm request inference hoặc sửa quy tắc tạo tín hiệu. Reduced motion giữ màu/nhãn nhưng tắt animation. Kiểm tra bằng fixture trình duyệt cho tất cả trạng thái và thay đổi tín hiệu sau refresh.

Đã chạy `npx tsc --noEmit`, ESLint các file thay đổi và browser test `watchlist highlights` (20 mã synthetic, không ghi DB). Dùng `WEB_TEST_URL=http://localhost:3000` cho server dev hiện tại; hostname 127.0.0.1 bị Next dev chặn HMR, nên các lần thử trên hostname đó không nhận fixture qua tương tác. Không sửa config server hoặc các thay đổi đang có ở panel phân tích/chart.
