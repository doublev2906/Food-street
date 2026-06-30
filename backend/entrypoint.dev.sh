#!/bin/bash
# Entrypoint dev: chờ Postgres sẵn sàng -> cài deps -> tạo DB + migrate + seed -> chạy lệnh.
set -e

echo "⏳ Chờ Postgres tại ${DB_HOST:-db}:${DB_PORT:-5432}..."
until pg_isready -h "${DB_HOST:-db}" -p "${DB_PORT:-5432}" -U "${DB_USER:-postgres}" >/dev/null 2>&1; do
  sleep 1
done
echo "✅ Postgres đã sẵn sàng."

# Source được mount qua volume nên cần đảm bảo deps có mặt (lần đầu / khi mix.lock đổi).
mix deps.get

# Tạo DB nếu chưa có, chạy migrate, seed dữ liệu mẫu.
mix ecto.create
mix ecto.migrate
mix run priv/repo/seeds.exs

echo "🚀 Khởi động: $@"
exec "$@"
