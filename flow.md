# Luồng dữ liệu → PostgreSQL → chỉ báo → Jev → dashboard

USD là lựa chọn mặc định. Crypto/USD lấy từ Coinbase Exchange, crypto/USDT từ Binance Spot. Vàng thế giới XAU/USD lấy giá tham chiếu từ Gold API; không dùng PAXG thay vàng. Mỗi thị trường giữ nguồn, mã nguồn và đồng tiền riêng.

```text
Danh mục market_assets
  → metadata xác minh cặp giao dịch
  → market_symbols (exchange, symbol, provider_symbol, base/quote)
  → lịch lấy snapshot mỗi 120 giây
      Binance: giá + thống kê 24h
      Coinbase: ticker + thống kê 24h; nến 1H khi có giờ mới
      Gold API: giá XAU/USD + thời điểm cập nhật của nguồn
  → kiểm tra cấu trúc, Decimal, timestamp, OHLC và nến đã đóng
  → PostgreSQL: market_latest_prices / market_ticker_stats / market_candles
  → mỗi 300 giây: dispatcher Jev chọn market crypto đủ điều kiện
  → 300 nến 1H liên tiếp, giá/thống kê còn mới
  → EMA20/50/200, RSI14, MACD12/26/9, ATR14, ADX14, relative volume20, returns
  → feature snapshot + nguồn + thời điểm → Jev System One
  → kiểm tra response → policy deterministic BUY / SELL / WAIT / NO_DATA
  → market_analyses: model/version, features, answers, raw response, thời hạn
  → API chỉ đọc DB → dashboard cập nhật mỗi 5 giây
```

## Lịch và tính toàn vẹn

- `dev.exs`: `price_poll_interval_ms: 120_000`, `analysis_interval_seconds: 300`. Thống kê Binance chạy mỗi 2 phút; lịch nến đóng và metadata riêng.
- Worker USD/vàng dùng queue riêng, khóa PostgreSQL theo nguồn và deadline theo market để không gọi trùng giữa node. Timeout hữu hạn, không retry ngay; 429/cooldown được lưu theo nguồn. Mỗi request Coinbase cách ít nhất 150ms trong khóa nguồn.
- Chỉ ghi giá mới hơn timestamp nguồn hiện có. Không xem thời điểm fetch là thời điểm giao dịch; trả cả `data_at` và `fetched_at`. Giá được coi mới tối đa chu kỳ poll + 60 giây. Jev dùng cùng ngưỡng.
- Coinbase trả volume theo tài sản gốc, không trả quote volume/taker volume/trade count trong các endpoint đã chọn: lưu `null`, không suy diễn bằng giá hiện tại hay ghi 0. Nến thiếu không được lấp giả. Lần bootstrap chỉ lấy cửa sổ 300 giờ phục vụ chỉ báo; chưa phải backfill 3 năm Coinbase.
- XAU/USD hiện chỉ có snapshot tham chiếu, không có nến/volume xác thực: không gọi Jev cho vàng và hiển thị lý do. Không giả lập nến từ snapshot 2 phút. Timestamp cũ cuối tuần phải hiện stale.
- Chọn market bằng exchange + symbol; Binance collector không xử lý market Coinbase/vàng. GET không gọi provider hoặc Jev.

## Diễn giải tín hiệu

Jev phân loại **xu hướng quan sát**, **động lượng**, **biến động** từ feature snapshot. Phần giải thích tiếng Việt là diễn giải có quy tắc từ nhãn/giá trị này, không phải nội dung tự do do Jev tạo. BUY xanh khi tăng + động lượng tích cực + biến động bình thường; SELL đỏ khi giảm + động lượng suy yếu + biến động bình thường; các tổ hợp khác WAIT. Kết quả hết hạn hiển thị WAIT và nhãn cũ. Confidence của mô hình không phải tỷ lệ có lãi; không đưa target giá, win rate hay xác suất thành công chưa kiểm chứng.

Trading Knowledge Engine hiện là luồng nghiên cứu riêng, chưa tự ghép thư viện JSON vào monitor Jev. Chiến lược ví dụ vẫn `unvalidated`. Không có đặt lệnh thật.

## Nguồn đã đối chiếu

- [Coinbase products](https://docs.cdp.coinbase.com/api-reference/exchange-api/rest-api/products/get-all-known-trading-pairs), [ticker](https://docs.cdp.coinbase.com/api-reference/exchange-api/rest-api/products/get-product-ticker), [stats](https://docs.cdp.coinbase.com/api-reference/exchange-api/rest-api/products/get-product-stats), [candles](https://docs.cdp.coinbase.com/api-reference/exchange-api/rest-api/products/get-product-candles). Candles tối đa 300/request, có thể thiếu khoảng không có giao dịch.
- [Coinbase rate limits](https://docs.cdp.coinbase.com/exchange/rest-api/rate-limits): public 10 requests/giây/IP, xử lý 429.
- [Gold API](https://gold-api.com/docs), [đặc tả endpoint](https://gold-api.com/llms.txt): `/price/XAU/USD` không cần key; history/OHLC cần key. Giá vàng là dữ liệu tham chiếu của nhà cung cấp.
- Công thức: EMA SMA-seeded; RSI/ATR/ADX Wilder; MACD = EMA12−EMA26, signal EMA9; RVOL = volume nến cuối / trung bình 20 nến trước, `null` khi mẫu số 0. Không dùng nến tương lai.
