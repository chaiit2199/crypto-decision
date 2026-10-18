# Deploy API lên VPS

Kiến trúc: Jenkins checkout monorepo → build Phoenix release → push image theo build/commit → SSH VPS → PostgreSQL healthy → migration bằng image mới → khởi động API → health check. Không deploy frontend. Giữ quy trình Docker Hub/SSH của crypto-decision và lineup_api, bỏ dependency core_auth.

Jenkins dùng script path `apps/api/Jenkinsfile`; Docker build context là `apps/api`. Builder và runner cùng Ubuntu Jammy. Compose project `crypto-decision` có volume riêng, không dùng volume/network core_auth. PostgreSQL không publish port; API publish localhost:5005 cho reverse proxy HTTPS trên VPS.

## Chuẩn bị

VPS cần Docker Compose v2 hỗ trợ `up --wait`, Bash, quyền Docker và đăng nhập Docker Hub nếu image private. Jenkins cần Docker, Git, SSH Agent plugin, credential `docker-hub-credentials`, `core-api-production-ssh`; thêm host key VPS đã xác minh vào known_hosts của Jenkins. Sửa registry/host/path trong Jenkinsfile nếu hạ tầng khác.

Tạo `/home/deploy_user/crypto-decision`, sao chép `apps/api/env.sh.example` thành `env.sh` tại đó, điền password và SECRET_KEY_BASE (sinh bằng `openssl rand -base64 48`), chmod 600. Dùng các biến PHX_HOST, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB như file mẫu; AUTH_DB_* không được API sử dụng. Không commit secrets. PHX_HOST là domain API; reverse proxy chuyển tiếp Host và X-Forwarded-Proto=https tới 127.0.0.1:5005. Nếu frontend chạy container khác, cấu hình mạng/proxy phù hợp; localhost của container không phải VPS.

Chạy Jenkins DEPLOY=none để build/push; DEPLOY=production để migrate/deploy. Pipeline chuyển compose và script lên VPS, không ghi đè `env.sh`. Image tag đang chạy được lưu trong `.image.env` sau khi health thành công.

## Tạo database và các bảng lần đầu

Trong `env.sh` trên VPS, đặt `HTTP_PORT=5005`, `POSTGRES_USER=crypto_decision`,
`POSTGRES_DB=crypto_decision_lab_prod` và điền các secret bắt buộc.
Chạy trong thư mục deploy có `docker-compose.yml` và `env.sh`:

```bash
cd /home/deploy_user/crypto-decision
# Thay BUILD-COMMIT bằng tag image Jenkins đã push thành công.
set -a
source ./env.sh
set +a
export IMAGE_TAG=docker.io/chaiit2199/crypto-decision:BUILD-COMMIT

docker compose --env-file /dev/null up -d --wait --wait-timeout 120 db
docker compose --env-file /dev/null pull api
docker compose --env-file /dev/null run --rm --no-deps -T api \
  eval 'CryptoDecisionLab.Release.migrate()'

# Xem các bảng đã tạo:
docker compose --env-file /dev/null exec db sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt"'

# Khởi động API và lưu tag để dùng cho các lệnh vận hành bên dưới:
bash deploy-api.sh "$IMAGE_TAG"
curl --fail http://127.0.0.1:5005/api/health
```

Với volume mới, container PostgreSQL tự tạo user/database theo POSTGRES_USER và
POSTGRES_DB. Migrations tạo toàn bộ bảng, index và constraints theo code, bao gồm
Oban và Trading Knowledge; chạy lại chỉ áp dụng migration chưa chạy.
Nếu volume đã có dữ liệu, đổi POSTGRES_DB trong `env.sh` không tự tạo database mới.
Sau khi xác nhận đúng database cần thêm, dùng lệnh sau trước migration (chỉ chạy
khi database đó chưa tồn tại; user phải là role đã có trong cluster):

```bash
docker compose --env-file /dev/null exec db sh -c \
  'createdb -U "$POSTGRES_USER" -O "$POSTGRES_USER" "$POSTGRES_DB"'
```

Không xóa volume để tạo lại database. Cổng 5005 chỉ bind localhost của VPS;
truy cập từ Internet qua reverse proxy HTTPS.

## Thủ công và vận hành

Từ repo: `docker build -f apps/api/Dockerfile -t crypto-decision:local apps/api`.

Tại VPS, đặt docker-compose.yml và deploy-api.sh trong thư mục deploy:

```bash
bash deploy-api.sh docker.io/chaiit2199/crypto-decision:BUILD-COMMIT
# Những lệnh vận hành sau deploy:
set -a
source ./env.sh
source ./.image.env
set +a
docker compose --env-file /dev/null --env-file .image.env ps
docker compose --env-file /dev/null --env-file .image.env logs --tail 100 api
```

Backup PostgreSQL trước migration. Migration lỗi dừng deploy trước khi thay API cũ. Health lỗi báo thất bại, không tự rollback schema. Muốn rollback ứng dụng: chạy deploy-api.sh với tag cũ sau khi xác nhận schema còn tương thích. Không chạy down -v. Lần đầu migration tạo schema; metadata collector sẽ seed danh mục khi MARKET_SYNC_ENABLED=true. Jev opt-in bằng JEV_ENABLED=true và TYPESAFE_API_KEY. Chu kỳ hiện tại: giá 120 giây, Jev 300 giây; chưa đủ dữ liệu thì chưa có phân tích.

Tham khảo: https://hexdocs.pm/phoenix/releases.html và https://docs.docker.com/compose/how-tos/startup-order/.

## Kết quả kiểm tra ngày 2026-10-18

- Format và compile warnings-as-errors: đạt (MIX_ENV=test).
- `MIX_ENV=prod mix release`: thành công trên macOS; release eval `CryptoDecisionLab.Release.migrate()` thành công trên PostgreSQL test riêng.
- `mix precommit`: 108 tests, 4 failures sẵn có do Universe chứa 31 tài sản trong khi test kỳ vọng 32; không sửa danh mục trong thay đổi deploy.
- Bash syntax cho deploy script và các shell block Jenkins: đạt. Compose YAML parse: đạt.
- Chưa chạy Docker build, Compose config/runtime hoặc Jenkins validation thực tế vì máy kiểm tra chưa có Docker/Jenkins. Chưa SSH hay deploy lên VPS. Build release macOS không thay thế kiểm tra image Linux.

## Deploy dừng với exit code 1 sau khi push image

Kiểm tra đường dẫn DEPLOY_PATH trong Jenkinsfile và quyền đọc `env.sh` trên VPS.
`~/crypto-decision` (`/home/deploy_user/crypto-decision`) là thư mục deploy. Pipeline chép docker-compose.yml và deploy-api.sh vào đây; env.sh được giữ nguyên.
Jenkinsfile hiện in lỗi cụ thể nếu thiếu thư mục, thiếu `env.sh`, thiếu quyền ghi hoặc công cụ cần thiết.
Database trong `infra-postgres-1` cũng khác service `db` của Compose production; việc tạo database thủ công trong infra không chứng minh migration production đã chạy.

Production nạp `env.sh` bằng Bash `source` và export các biến cho Compose. Chỉ dùng file shell do quản trị viên quản lý, chmod 600. Không truyền env.sh qua --env-file; Compose dùng --env-file /dev/null để không tự đọc .env cũ. Tag Jenkins được áp dụng sau khi nạp env.sh, nên IMAGE_TAG cũ trong file không ghi đè image vừa build. File rel/env.sh.eex của Elixir release không phải file cấu hình deploy này.
