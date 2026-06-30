#!/usr/bin/env bash
# =============================================================================
# Chạy MỘT LẦN trên server Ubuntu (user thường có quyền sudo, KHÔNG phải root).
# Cài runtime + DB + systemd + nginx. Idempotent: chạy lại an toàn.
#
#   git clone <repo> /opt/food_street
#   cd /opt/food_street && bash scripts/server_bootstrap.sh
#
# Sau khi xong: sửa /etc/food_street/env rồi chạy `bash scripts/deploy_remote.sh`.
# =============================================================================
set -euo pipefail

ERLANG_VERSION="27.3"
ELIXIR_VERSION="1.18.3-otp-27"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="/etc/food_street/env"
SERVICE_USER="$(whoami)"

[ "$EUID" -eq 0 ] && { echo "Đừng chạy bằng root — dùng user thường có sudo (asdf cài vào \$HOME)."; exit 1; }

echo "==> [1/7] Cài gói hệ thống"
sudo apt update
sudo apt install -y build-essential git curl nginx postgresql postgresql-contrib \
  automake autoconf libssl-dev libncurses5-dev unzip

echo "==> [2/7] Cài Node 20"
if ! command -v node >/dev/null || [ "$(node -v | cut -d. -f1 | tr -d v)" -lt 20 ]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt install -y nodejs
fi
node -v

echo "==> [3/7] Cài asdf + Erlang/Elixir (có thể mất vài phút lần đầu)"
if [ ! -d "$HOME/.asdf" ]; then
  git clone https://github.com/asdf-vm/asdf.git "$HOME/.asdf" --branch v0.14.1
  grep -q 'asdf.sh' "$HOME/.bashrc" || echo '. "$HOME/.asdf/asdf.sh"' >> "$HOME/.bashrc"
fi
. "$HOME/.asdf/asdf.sh"
asdf plugin add erlang || true
asdf plugin add elixir || true
asdf install erlang "$ERLANG_VERSION" || true
asdf install elixir "$ELIXIR_VERSION" || true
asdf global erlang "$ERLANG_VERSION"
asdf global elixir "$ELIXIR_VERSION"
mix local.hex --force && mix local.rebar --force

echo "==> [4/7] PostgreSQL: tạo user + database (nếu chưa có)"
DB_USER="food_street"
DB_NAME="food_street_prod"
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
  read -rsp "Nhập mật khẩu DB cho user '$DB_USER': " DB_PASS; echo
  sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
  sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
  echo "    Đã tạo DB. DATABASE_URL=ecto://$DB_USER:<mat_khau>@localhost/$DB_NAME"
else
  echo "    User '$DB_USER' đã tồn tại — bỏ qua."
fi

echo "==> [5/7] Tạo file env $ENV_FILE (nếu chưa có)"
if [ ! -f "$ENV_FILE" ]; then
  sudo mkdir -p /etc/food_street
  sudo cp "$APP_DIR/deploy/env.example" "$ENV_FILE"
  sudo chown "$SERVICE_USER" "$ENV_FILE"
  sudo chmod 600 "$ENV_FILE"
  echo "    ĐÃ TẠO $ENV_FILE — BẮT BUỘC sửa SECRET_KEY_BASE, DATABASE_URL, PHX_HOST."
  echo "    Sinh secret:  cd $APP_DIR/backend && mix phx.gen.secret"
else
  echo "    $ENV_FILE đã tồn tại — bỏ qua."
fi

echo "==> [6/7] Cài systemd service + sudoers cho restart không cần mật khẩu"
sudo cp "$APP_DIR/deploy/food_street.service" /etc/systemd/system/food_street.service
sudo sed -i "s/^User=.*/User=$SERVICE_USER/" /etc/systemd/system/food_street.service
sudo sed -i "s#WorkingDirectory=.*#WorkingDirectory=$APP_DIR/backend#" /etc/systemd/system/food_street.service
sudo sed -i "s#ExecStart=.*#ExecStart=$APP_DIR/backend/_build/prod/rel/food_street/bin/food_street start#" /etc/systemd/system/food_street.service
sudo sed -i "s#ExecStop=.*#ExecStop=$APP_DIR/backend/_build/prod/rel/food_street/bin/food_street stop#" /etc/systemd/system/food_street.service
sudo systemctl daemon-reload
sudo systemctl enable food_street
# Cho phép deploy_remote.sh restart service không hỏi mật khẩu sudo
SUDOERS="/etc/sudoers.d/food_street"
echo "$SERVICE_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart food_street, /bin/systemctl status food_street" | sudo tee "$SUDOERS" >/dev/null
sudo chmod 440 "$SUDOERS"

echo "==> [7/7] Cài cấu hình Nginx"
sudo cp "$APP_DIR/deploy/nginx.conf" /etc/nginx/sites-available/food_street
sudo sed -i "s#root .*#root $APP_DIR/frontend/dist;#" /etc/nginx/sites-available/food_street
sudo ln -sf /etc/nginx/sites-available/food_street /etc/nginx/sites-enabled/food_street
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

cat <<DONE

==============================================================
 Bootstrap xong. Bước tiếp theo:
   1. Sửa $ENV_FILE  (SECRET_KEY_BASE, DATABASE_URL, PHX_HOST)
   2. Sửa server_name trong /etc/nginx/sites-available/food_street
   3. Deploy lần đầu:   bash scripts/deploy_remote.sh
   4. Seed dữ liệu mẫu: backend/_build/prod/rel/food_street/bin/seed
   5. Bật HTTPS:        sudo apt install -y certbot python3-certbot-nginx
                        sudo certbot --nginx -d <ten-mien>
   6. Firewall:         sudo ufw allow OpenSSH && sudo ufw allow 'Nginx Full' && sudo ufw enable
==============================================================
DONE
