# Deploy Food Street lên VPS Ubuntu

Frontend (React) + backend (Phoenix) chạy chung 1 server. Nginx serve file tĩnh
`frontend/dist` và proxy `/api` sang Phoenix release (cổng 4003).

```
Internet :443 ──► Nginx ──► file tĩnh React (dist/)
                     └────► /api  ──► Phoenix release :4003 ──► PostgreSQL
```

> **Quan trọng:** Elixir release không chạy cross-platform. Mọi build diễn ra
> **trên server** (qua `scripts/deploy_remote.sh`), không build dưới máy macOS.

---

## Yêu cầu trước

- 1 VPS Ubuntu, có user thường + quyền `sudo` (đừng dùng root).
- 1 git remote chung mà **cả máy dev lẫn server** kéo được (vd GitHub private repo).
- (Để có HTTPS) 1 tên miền trỏ bản ghi A về IP server.

---

## A. Setup server — chỉ làm MỘT LẦN

```bash
# Trên server:
git clone <repo> /opt/food_street
cd /opt/food_street
bash scripts/server_bootstrap.sh
```

Script tự: cài Elixir/Erlang (asdf) + Node 20 + PostgreSQL + Nginx, tạo DB,
tạo `/etc/food_street/env`, cài systemd service + cấu hình Nginx.

Sau đó làm theo hướng dẫn in ra cuối script:

1. Sửa `/etc/food_street/env` — điền `SECRET_KEY_BASE` (`cd backend && mix phx.gen.secret`),
   `DATABASE_URL`, `PHX_HOST`.
2. Sửa `server_name` trong `/etc/nginx/sites-available/food_street`.
3. Deploy lần đầu: `bash scripts/deploy_remote.sh`
4. Seed tài khoản mẫu: `backend/_build/prod/rel/food_street/bin/seed`
   (**nhớ đổi mật khẩu admin** sau đó).
5. Bật HTTPS: `sudo certbot --nginx -d <ten-mien>`
6. Firewall: `sudo ufw allow OpenSSH && sudo ufw allow 'Nginx Full' && sudo ufw enable`

---

## B. Deploy các lần sau — từ máy dev

```bash
# Lần đầu: tạo file cấu hình kết nối server
cp deploy.config.example deploy.config   # rồi điền SSH_HOST, APP_DIR, GIT_REMOTE...

# Mỗi lần deploy:
./deploy.sh
```

`./deploy.sh` sẽ: push nhánh lên git → SSH vào server → `git pull` →
build backend release + frontend → migrate → restart service → health-check.

---

## Cấu trúc các file deploy

| File | Vai trò |
|------|---------|
| `deploy.sh` | Chạy **dưới máy dev**: push git + kích hoạt deploy qua SSH |
| `deploy.config.example` | Mẫu cấu hình server (copy → `deploy.config`, đã gitignore) |
| `scripts/deploy_remote.sh` | Chạy **trên server**: build + migrate + restart + health-check |
| `scripts/server_bootstrap.sh` | Chạy **trên server 1 lần**: cài toàn bộ môi trường |
| `deploy/env.example` | Mẫu file env prod → `/etc/food_street/env` |
| `deploy/food_street.service` | systemd unit cho Phoenix release |
| `deploy/nginx.conf` | Cấu hình Nginx (tĩnh + proxy `/api`) |
| `backend/lib/food_street/release.ex` | Lệnh release: `migrate`, `rollback`, `seed` |
| `frontend/.env.production` | `VITE_API_URL=/api` (gọi API cùng origin) |

---

## Vận hành / debug

```bash
sudo systemctl status food_street       # trạng thái
sudo journalctl -u food_street -f       # log backend realtime
sudo tail -f /var/log/nginx/error.log   # log nginx
```

- Rollback migration: `backend/_build/prod/rel/food_street/bin/food_street eval 'FoodStreet.Release.rollback(FoodStreet.Repo, <version>)'`
- Mở IEx vào node đang chạy: `backend/_build/prod/rel/food_street/bin/food_street remote`
