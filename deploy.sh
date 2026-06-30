#!/usr/bin/env bash
# =============================================================================
# Chạy DƯỚI MÁY DEV. Push code lên git rồi SSH vào server tự deploy.
#
#   ./deploy.sh
#
# Lần đầu: copy deploy.config.example -> deploy.config và điền thông tin server.
#
# Lưu ý: Elixir release KHÔNG chạy cross-platform (macOS != Linux) nên việc
# build diễn ra TRÊN SERVER (qua scripts/deploy_remote.sh), không build dưới máy.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/deploy.config"

if [ ! -f "$CONFIG" ]; then
  echo "Thiếu deploy.config. Tạo bằng:"
  echo "    cp deploy.config.example deploy.config   # rồi điền thông tin server"
  exit 1
fi

# shellcheck disable=SC1090
. "$CONFIG"

: "${SSH_HOST:?SSH_HOST chưa đặt trong deploy.config}"
SSH_USER="${SSH_USER:-pancake}"
SSH_PORT="${SSH_PORT:-22}"
APP_DIR="${APP_DIR:-/opt/food_street}"
GIT_REMOTE="${GIT_REMOTE:-origin}"
BRANCH="${BRANCH:-master}"
# docker  -> scripts/deploy_remote_docker.sh (khuyến nghị)
# release -> scripts/deploy_remote.sh (mix release trên host)
DEPLOY_MODE="${DEPLOY_MODE:-docker}"
SERVICE="${SERVICE:-food_street}"
REMOTE_ENV_FILE="${REMOTE_ENV_FILE:-/etc/food_street/env}"

REMOTE="${SSH_USER}@${SSH_HOST}"

if [ "$DEPLOY_MODE" = "docker" ]; then
  REMOTE_CMD="bash scripts/deploy_remote_docker.sh"
else
  REMOTE_CMD="FOOD_STREET_SERVICE='$SERVICE' FOOD_STREET_ENV='$REMOTE_ENV_FILE' bash scripts/deploy_remote.sh"
fi

echo "==> Push '$BRANCH' lên '$GIT_REMOTE' (để server kéo được)"
git push "$GIT_REMOTE" "$BRANCH"

echo "==> SSH $REMOTE  →  deploy $APP_DIR (nhánh $BRANCH, mode=$DEPLOY_MODE)"
# -A: forward SSH agent để server dùng key của máy dev khi 'git pull' repo private.
# Heredoc không trích dẫn: các biến dưới đây được nội suy ở MÁY DEV trước khi gửi.
ssh -A -p "$SSH_PORT" "$REMOTE" bash -s <<EOF
set -euo pipefail
cd "$APP_DIR"
echo "    git fetch + checkout + pull"
git fetch --all --prune
git checkout "$BRANCH"
git pull --ff-only "$GIT_REMOTE" "$BRANCH"
$REMOTE_CMD
EOF

echo "==> Hoàn tất. Mở https://${PHX_HOST:-$SSH_HOST} để kiểm tra."
