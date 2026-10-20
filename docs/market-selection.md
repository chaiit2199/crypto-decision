# Chọn cặp USD/USDT và quản lý danh mục

## Cặp giao dịch

Bộ chọn USD/USDT chọn `market_symbols.quote_asset` của thị trường thật, không quy đổi hay đổi nhãn giá. Mỗi bảng giá, chi tiết, biểu đồ và phân tích phải theo cùng market được chọn. Khi không có cặp tương ứng, UI báo chưa có dữ liệu và không lấy kết quả của cặp khác. API đã trả `exchange`, `base_asset`, `quote_asset`; frontend kiểm tra và giữ các field này tại ranh giới HTTP.

USD là mặc định, dùng Coinbase Exchange; USDT dùng Binance Spot. Request nến có cả `exchange` và `symbol` để tránh lấy nhầm nguồn. Collector Binance chỉ xử lý market Binance. SourceSync xử lý Coinbase và Gold API riêng, có khóa nguồn/cooldown trong PostgreSQL.

Vàng thế giới XAU/USD: giá live free từ [Gold API](https://gold-api.com/docs) `/price/XAU/USD`; lịch sử **nến ngày** free từ [XAUS](https://xaus.com/api/) `/api/v1/history` (không API key). Open ngày = close ngày trước; volume null. Đồng bộ history tối đa mỗi 6 giờ **sau khi đã có nến**; nếu DB còn 0 nến `1d` thì retry mỗi lần poll giá. Lỗi XAUS không làm mất snapshot giá. `price_max_age_seconds` vàng = 1800. UI dài hạn tại `/gold`; bảng crypto không liệt kê XAU. `gold_history_unavailable` khi chưa có nến `1d` (ẩn kết quả Jev cũ). Giá tham chiếu không khớp pip/spread XM.

## Thêm mã crypto

Danh mục mặc định nằm trong `apps/api/lib/crypto_decision_lab/market_data/universe.ex`, thuộc tính `@groups`. Thêm tuple `{symbol, name}` vào nhóm phù hợp. File `apps/api/priv/repo/seeds.exs` gọi `Universe.seed/0`; metadata bootstrap cũng gọi seed. Universe không tự chứng minh rằng Binance hỗ trợ mã đó: metadata Binance `exchangeInfo` xác nhận Spot USDT; Coinbase `/products` xác nhận cặp USD. Metadata Coinbase được cache một ngày; chạy `MARKET_SYNC_ENABLED=false JEV_ENABLED=false mix market.sources` để refresh ngay sau khi sửa danh mục.

Sau khi chỉnh danh sách, từ `apps/api`, seed mà không khởi động collector/Jev:

```sh
MARKET_SYNC_ENABLED=false JEV_ENABLED=false mix run priv/repo/seeds.exs
```

`Universe.seed/0` upsert tên/nhóm cho mã còn trong `@groups`, và đặt `enabled=false` cho mọi asset đã bị gỡ khỏi danh mục. Lịch sử nến/phân tích được giữ. Preference `enabled` của mã vẫn còn trong `@groups` được giữ nguyên. Khởi động lại backend để bootstrap metadata/backfill. Không seed một mã `XAU` rồi coi giá đó là vàng thế giới: cần nguồn XAU/USD riêng.

## Bỏ hoặc bật lại mã đã seed

Xóa tuple khỏi `@groups` rồi chạy seed sẽ tắt asset đó; lịch sử nến/phân tích vẫn được giữ. Muốn **xóa hẳn** asset ngoài danh mục hiện tại (18 crypto + XAU) và dữ liệu liên quan để giảm dung lượng DB, chạy migration `20261020114500_prune_xm_unfamiliar_assets` (sau seed nếu cần) rồi `VACUUM (ANALYZE)` trên PostgreSQL. Migration này không hoàn tác được; giữ BTC–IMX theo `Universe` và XAU. XAU đăng ký lại từ Gold API sau lần sync nguồn tiếp theo nếu bị thiếu.

Muốn tắt tạm một mã vẫn còn trong danh mục:

```sh
MARKET_SYNC_ENABLED=false JEV_ENABLED=false iex -S mix
```

```elixir
alias CryptoDecisionLab.Repo
alias CryptoDecisionLab.MarketData.Asset

asset = Repo.get_by!(Asset, symbol: "FET")
asset |> Ecto.Changeset.change(enabled: false) |> Repo.update!()
```

Dùng `enabled: true` để bật lại. Collector và Jev không chọn asset đã tắt; dashboard vẫn giữ hàng với trạng thái “Đã tắt” để truy vết.

Sau khi đổi `@groups`, trên production/local:

```sh
MARKET_SYNC_ENABLED=false JEV_ENABLED=false mix run priv/repo/seeds.exs
MARKET_SYNC_ENABLED=false JEV_ENABLED=false mix market.sources
```

`mix market.sources` force-refresh Coinbase/Gold metadata (Coinbase cache 1 ngày). Chart vàng cần lần sync nguồn gold thành công để kéo XAUS daily.

## Chẩn đoán USD không đồng bộ trên production

`SourceHTTP` phải phân biệt JSON không hợp lệ, thiếu/sai HTTP `Date`, response cũ và response ở tương lai. Không gộp các trường hợp này thành `:invalid_response`, vì sẽ che lỗi đồng hồ VPS hoặc lỗi upstream. HTTP Date chấp nhận tối đa 120 giây cũ hoặc 60 giây ở tương lai. Giới hạn lệch đồng hồ 60 giây dùng chung cho transport, parser snapshot và freshness/đầu vào Jev; timestamp nguồn vẫn giữ nguyên. Sai lệch vượt giới hạn được trả bằng giây trong lỗi và lưu vào trạng thái nguồn.

Kiểm tra trên chính VPS: `date -u` và `curl -sS --max-time 15 -D - -o /dev/null https://api.exchange.coinbase.com/products`. Đối chiếu HTTP status, Date, Content-Type và UTC của hệ điều hành. Thiếu cặp USD không có nghĩa mọi asset không được Coinbase hỗ trợ: metadata có thể chưa lưu được. Sau khi sửa nguyên nhân và deploy, collector tự thử lại theo lịch sau cooldown; không cần xóa database hoặc lịch sử job lỗi.

### Sửa sai lệch timestamp 41 giây - 2026-10-19

Lỗi `{:future_response, 41}` chặn metadata Coinbase trước khi đăng ký cặp USD. Binance trước đây cho phép HTTP Date lệch 60 giây nhưng từ chối `closeTime` của thống kê khi đi trước máy quá 5 giây; Jev lại từ chối mọi snapshot có tuổi âm. Thống nhất dung sai snapshot ở 60 giây giải quyết chuỗi kiểm tra mâu thuẫn này. Đây là dung sai vận hành của ứng dụng, không phải cam kết độ chính xác đồng hồ của sàn. Máy chạy backend vẫn cần đồng bộ NTP.

`MarketData.SnapshotTime` sở hữu giới hạn này. Không đổi giá trị timestamp hoặc tăng tuổi tối đa của dữ liệu cũ. Binance ghi `fetched_at` khi nhận response thay vì trước request. Nến vẫn phải đóng trước thời gian nhỏ hơn giữa đồng hồ local và HTTP Date, trừ 5 giây; dung sai snapshot không cho phép nhận nến chưa đóng. Contract REST, schema DB, lịch poll và lịch Jev giữ nguyên. Các tài liệu kiến trúc/module/ERD và kế hoạch nghiệm thu hiện có nằm trong `architecture.md`, `synchronization.md` và `api.md`.

Test hồi quy dùng fixture tổng hợp: lệch +41/+60 giây vẫn đăng ký USD, lưu giá/thống kê và cho phép gọi mock Jev nếu có đủ nến; +61 giây bị từ chối, dữ liệu cũ vẫn stale, nến chưa đóng vẫn bị loại. Đối chiếu schema upstream: [Coinbase ticker](https://docs.cdp.coinbase.com/api-reference/exchange-api/rest-api/products/get-product-ticker), [Coinbase stats](https://docs.cdp.coinbase.com/api-reference/exchange-api/rest-api/products/get-product-stats), [Binance Spot REST](https://github.com/binance/binance-spot-api-docs/blob/master/rest-api.md).

Sau deploy/restart backend, có thể khôi phục snapshot ngay trong shell đã cấu hình DB đúng:

```sh
cd apps/api
MARKET_SYNC_ENABLED=false JEV_ENABLED=false mix market.sources
MARKET_SYNC_ENABLED=false JEV_ENABLED=false mix market.sync prices
MARKET_SYNC_ENABLED=false JEV_ENABLED=false mix market.sync stats
```

Nếu nguồn đang cooldown, chờ hết thời hạn rồi chạy lại; không xóa lịch sử lỗi để bỏ cooldown. Phân tích `NO_DATA` đã lưu trong slot hiện tại không bị ghi đè; Jev đánh giá lại ở slot 15 phút tiếp theo khi dữ liệu đủ mới và đủ nến. Thông báo `missing_snapshots` không chứng minh key Jev lỗi, vì chưa đến bước gọi provider.

Kiểm tra bản sửa: test ExUnit độc lập cho `SnapshotTime` chạy trong sandbox đạt 1 test, 0 failures; parser cú pháp Elixir đọc được cả 12 file code/test thay đổi; `git diff --check` đạt. Chưa chạy bộ test DB, `mix precommit`, format/compile qua Mix hoặc smoke đồng bộ/Jev thật: workspace chưa có dependencies/build, không có PostgreSQL/backend local đang chạy, sandbox chặn socket của Mix và shared memory của PostgreSQL; yêu cầu chạy ngoài sandbox đã bị từ chối. Test tích hợp mới là mã hồi quy chưa được thực thi, không phải bằng chứng hệ thống production đã phục hồi.
