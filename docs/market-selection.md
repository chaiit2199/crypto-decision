# Chọn cặp USD/USDT và quản lý danh mục

## Cặp giao dịch

Bộ chọn USD/USDT chọn `market_symbols.quote_asset` của thị trường thật, không quy đổi hay đổi nhãn giá. Mỗi bảng giá, chi tiết, biểu đồ và phân tích phải theo cùng market được chọn. Khi không có cặp tương ứng, UI báo chưa có dữ liệu và không lấy kết quả của cặp khác. API đã trả `exchange`, `base_asset`, `quote_asset`; frontend kiểm tra và giữ các field này tại ranh giới HTTP.

USD là mặc định, dùng Coinbase Exchange; USDT dùng Binance Spot. Request nến có cả `exchange` và `symbol` để tránh lấy nhầm nguồn. Collector Binance chỉ xử lý market Binance. SourceSync xử lý Coinbase và Gold API riêng, có khóa nguồn/cooldown trong PostgreSQL.

Vàng thế giới XAU/USD lấy snapshot tham chiếu từ [Gold API](https://gold-api.com/docs), không cần key cho endpoint giá. Nguồn này chưa có history/OHLC trong ứng dụng vì cần key riêng; không tạo nến/volume/nhận định Jev giả. Metadata Gold API tự đăng ký XAU ngoài danh mục crypto mặc định. Xem `flow.md` cho chi tiết.

## Thêm mã crypto

Danh mục mặc định nằm trong `apps/api/lib/crypto_decision_lab/market_data/universe.ex`, thuộc tính `@groups`. Thêm tuple `{symbol, name}` vào nhóm phù hợp. File `apps/api/priv/repo/seeds.exs` gọi `Universe.seed/0`; metadata bootstrap cũng gọi seed. Universe không tự chứng minh rằng Binance hỗ trợ mã đó: metadata Binance `exchangeInfo` xác nhận Spot USDT; Coinbase `/products` xác nhận cặp USD. Metadata Coinbase được cache một ngày; chạy `MARKET_SYNC_ENABLED=false JEV_ENABLED=false mix market.sources` để refresh ngay sau khi sửa danh mục.

Sau khi chỉnh danh sách, từ `apps/api`, seed mà không khởi động collector/Jev:

```sh
MARKET_SYNC_ENABLED=false JEV_ENABLED=false mix run priv/repo/seeds.exs
```

Khởi động lại backend để bootstrap metadata/backfill. Không seed một mã `XAU` rồi coi giá đó là vàng thế giới: cần nguồn XAU/USD riêng.

## Bỏ hoặc bật lại mã đã seed

Seed dùng `on_conflict: :nothing` để giữ lựa chọn đã lưu. Xóa tuple khỏi `@groups` **không xóa/tắt** asset đã có trong DB. Không xóa dữ liệu giá/nến/lịch sử phân tích để bỏ theo dõi.

Từ `apps/api`, mở console không bật lịch nền:

```sh
MARKET_SYNC_ENABLED=false JEV_ENABLED=false iex -S mix
```

Ví dụ tắt MEW (thay mã theo nhu cầu):

```elixir
alias CryptoDecisionLab.Repo
alias CryptoDecisionLab.MarketData.Asset

asset = Repo.get_by!(Asset, symbol: "MEW")
asset |> Ecto.Changeset.change(enabled: false) |> Repo.update!()
```

Dùng `enabled: true` để bật lại. Collector và Jev không chọn asset đã tắt; dashboard vẫn giữ hàng với trạng thái “Đã tắt” để truy vết. Các test mặc định đang kiểm tra danh mục gốc 32 mã, cần cập nhật kỳ vọng khi thay danh mục mặc định.

## Chẩn đoán USD không đồng bộ trên production

`SourceHTTP` phải phân biệt JSON không hợp lệ, thiếu/sai HTTP `Date`, response cũ và response ở tương lai. Không gộp các trường hợp này thành `:invalid_response`, vì sẽ che lỗi đồng hồ VPS hoặc lỗi upstream. Giữ giới hạn HTTP Date: tối đa 120 giây cũ hoặc 5 giây ở tương lai; không thay timestamp bằng thời gian fetch để làm dữ liệu cũ thành mới. Sai lệch thời gian được trả bằng giây trong lỗi và lưu vào trạng thái nguồn.

Kiểm tra trên chính VPS: `date -u` và `curl -sS --max-time 15 -D - -o /dev/null https://api.exchange.coinbase.com/products`. Đối chiếu HTTP status, Date, Content-Type và UTC của hệ điều hành. Thiếu cặp USD không có nghĩa mọi asset không được Coinbase hỗ trợ: metadata có thể chưa lưu được. Sau khi sửa nguyên nhân và deploy, collector tự thử lại theo lịch sau cooldown; không cần xóa database hoặc lịch sử job lỗi.
