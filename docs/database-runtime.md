# Database — cấu hình tương tự core_api

## Cấu trúc đã chọn

- **Dev:** `apps/api/config/dev.exs` khai báo đầy đủ username, password, hostname, database, port, pool_size và stacktrace, cùng cách tổ chức với `core_api/config/dev.exs`.
- **Prod:** `apps/api/config/runtime.exs` đọc kết nối khi khởi động, áp dụng cả Mix và production release. Ưu tiên `DATABASE_URL`; nếu không đặt URL thì dùng `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_NAME`, `DB_PORT`.
- **Test:** giữ database riêng có hậu tố `_test` và không đọc `DATABASE_URL`.

Không sao chép credentials của core_api. Dev đọc các biến môi trường hiện có để không đưa thông tin đăng nhập vào Git. Runtime không ghi đè cấu hình Repo của dev.

## Development

Từ root, copy `.env.example` sang `.env` nếu chưa có, rồi điền các giá trị kết nối dev trong `.env`:

```dotenv
DB_HOST=127.0.0.1
DB_PORT=5433
DB_USER=crypto_decision
DB_PASSWORD='replace-with-your-dev-password'
DB_NAME=crypto_decision_lab_dev
DB_POOL_SIZE=10
```

Đây là giá trị minh họa. Nếu DB dev chạy trên server khác, dùng hostname/port/user/database của server đó. File `.env` đã được Git ignore.

```sh
set -a
source .env
set +a
cd apps/api
MIX_ENV=dev mix phx.server
```

Mix không tự load `.env`. Các giá trị dev được đọc khi Mix load config; sau khi thay đổi biến môi trường cần khởi động lại ứng dụng. Default port 5433 khớp Compose local; PostgreSQL remote thường dùng port được nhà cung cấp chỉ định.

## Production runtime

Cấu hình các biến sau trên môi trường chạy, bằng secret manager của deployment hoặc environment riêng:

```dotenv
DB_HOST=db.example.internal
DB_PORT=5432
DB_USER=crypto_decision
DB_PASSWORD='replace-with-your-production-password'
DB_NAME=crypto_decision_lab_prod
DB_POOL_SIZE=10
SECRET_KEY_BASE='replace-with-output-of-mix-phx.gen.secret'
```

Hoặc đặt `DATABASE_URL` thay bộ DB_HOST/PORT/USER/PASSWORD/NAME. URL có ưu tiên cao hơn; password có ký tự đặc biệt phải percent-encode. `DB_POOL_SIZE` ưu tiên hơn `POOL_SIZE` cũ; nếu cả hai không được đặt thì pool_size=10. `ECTO_IPV6=true` bật socket IPv6 khi hạ tầng yêu cầu. Thiếu credentials prod sẽ dừng khởi động thay vì fallback về DB local.

```sh
# Trong apps/api, sau khi export biến môi trường production:
MIX_ENV=prod mix phx.server
```

Với release đã build cho prod, các biến được đọc khi chạy binary:

```sh
PHX_SERVER=true _build/prod/rel/crypto_decision_lab/bin/crypto_decision_lab start
```

`mix phx.gen.secret` tạo SECRET_KEY_BASE; lưu giá trị đó trong cấu hình deployment. Không khởi động prod trong cùng shell đang export `.env` local nếu chưa thay toàn bộ credentials tương ứng.

## Kiểm tra kết nối

Ứng dụng đang chạy có `GET /api/health`, thực hiện `SELECT 1`; `database: up` nghĩa là đã kết nối. Kết nối tới DB đã có không cần chạy `mix ecto.setup`. Migration/seed là thao tác thay đổi schema/dữ liệu, thực hiện riêng khi triển khai.

Chưa có host/credentials dev và prod thực tế trong yêu cầu nên chưa xác nhận kết nối tới hai DB của người dùng. Tests chỉ kiểm tra lựa chọn cấu hình và chạy với PostgreSQL local riêng.

Kiểm tra sau thay đổi: `mix precommit` đạt, **41 tests, 0 failures**, gồm 6 test về cấu hình dev/prod/test, ưu tiên DATABASE_URL và bảo vệ tên database test. PostgreSQL tạm được dừng sau khi kiểm tra.
