#!/usr/bin/env bash
# =============================================================================
# Chạy TRÊN SERVER. Được deploy.sh (dưới máy) gọi qua SSH sau khi `git pull`.
# Build backend release + frontend, migrate DB, restart service, health-check.
#
# Có thể chạy trực tiếp trên server để deploy thủ công:
#   cd /opt/food_street && git pull && bash scripts/deploy_remote.sh
#
# Biến môi trường (tuỳ chọn):
#   FOOD_STREET_ENV      đường dẫn file env (mặc định /etc/food_street/env)
#   FOOD_STREET_SERVICE  tên systemd service (mặc định food_street)
# =============================================================================
set -euo pipefail

# asdf cài elixir/erlang/node — nạp PATH cho shell SSH không tương tác
[ -f "$HOME/.asdf/asdf.sh" ] && . "$HOME/.asdf/asdf.sh"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${FOOD_STREET_ENV:-/etc/food_street/env}"
SERVICE="${FOOD_STREET_SERVICE:-food_street}"

echo "==> Nạp biến môi trường: $ENV_FILE"
[ -f "$ENV_FILE" ] || { echo "LỖI: không thấy $ENV_FILE (xem deploy/env.example)"; exit 1; }
set -a; . "$ENV_FILE"; set +a

# ----------------------------------------------------------------------------
echo "==> [Backend] Lấy deps + build release (MIX_ENV=prod)"
cd "$REPO_DIR/backend"
export MIX_ENV=prod
mix local.hex --if-missing --force >/dev/null
mix local.rebar --if-missing --force >/dev/null
mix deps.get --only prod
mix compile
mix release --overwrite

echo "==> [Backend] Chạy migration"
_build/prod/rel/food_street/bin/migrate

# ----------------------------------------------------------------------------
echo "==> [Frontend] npm ci + build (dist/)"
cd "$REPO_DIR/frontend"
npm ci
npm run build

# ----------------------------------------------------------------------------
echo "==> Restart service: $SERVICE"
sudo systemctl restart "$SERVICE"

echo "==> Health check"
sleep 2
HEALTH_URL="http://127.0.0.1:${PORT:-4003}/api/health"
if curl -fsS "$HEALTH_URL" >/dev/null; then
  echo "✓ Deploy thành công — $HEALTH_URL OK"
else
  echo "✗ Health check THẤT BẠI ($HEALTH_URL). Xem log: sudo journalctl -u $SERVICE -n 50"
  exit 1
fi
