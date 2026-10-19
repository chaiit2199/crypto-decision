# Crypto Decision API

Phoenix REST backend cho Phase 1. Xem [README gốc](../../README.md) để cấu hình PostgreSQL, export môi trường, chạy migration, đồng bộ và kiểm thử.

```sh
mix deps.get
mix ecto.setup
MARKET_SYNC_ENABLED=true mix phx.server
```

Kiểm tra: `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`.
