# Deploy Food Street lên VPS Ubuntu

Có 2 cách: **Docker (khuyến nghị)** hoặc mix release trực tiếp trên host.

---

# 🐳 Cách 1 — Docker (khuyến nghị)

Toàn bộ chạy trong container, **không cần cài Elixir/Node/Postgres trên host**.
Caddy tự cấp & gia hạn HTTPS (Let's Encrypt).

```
Internet :80/:443 ──► web (Caddy)  ──► file tĩnh React (dist/)
                          └────► /api ──► backend (Phoenix release) :4003
                                              └────► db (PostgreSQL, volume)
```

### Setup server — MỘT LẦN
```bash
git clone <repo> /opt/food_street
cd /opt/food_street
bash scripts/server_bootstrap_docker.sh   # cài Docker + mở firewall + tạo .env
# Sửa .env: PHX_HOST, SECRET_KEY_BASE, DB_PASS  (secret: openssl rand -base64 64)
```

**TLS — chọn 1 trong .env:**
- **Có domain:** `PHX_HOST=ten-mien.com`, để `CADDY_EXTRA_TLS` trống → HTTPS Let's Encrypt thật. Trỏ DNS A record về IP + mở cổng 80/443.
- **Chỉ có IP:** `PHX_HOST=123.45.67.89`, `CADDY_EXTRA_TLS="tls internal"` → HTTPS **tự ký** (trình duyệt cảnh báo "không tin cậy", bấm bỏ qua). Không cần DNS.

### Deploy lần đầu (trên server)
```bash
bash scripts/deploy_remote_docker.sh
# Seed dữ liệu (1 lần):
docker compose -f docker-compose.prod.yml exec backend /app/bin/seed
```

### Deploy các lần sau — từ máy dev
```bash
cp deploy.config.example deploy.config   # DEPLOY_MODE="docker" (mặc định)
./deploy.sh
```

### Vận hành (Docker)
```bash
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs -f backend
docker compose -f docker-compose.prod.yml logs -f web      # log Caddy / cấp SSL
docker compose -f docker-compose.prod.yml down             # dừng
```

> File Docker: `docker-compose.prod.yml`, `backend/Dockerfile`, `frontend/Dockerfile`,
> `frontend/Caddyfile`, `.env.prod.example`. Migration tự chạy khi container backend khởi động.

### Chia sẻ trang HTML (`/share`)

Folder `share/` ở root repo (có thể chia thư mục con) được mount vào `backend`; Caddy
proxy `/share/*` sang backend (`ShareController`) serve ở `https://<host>/share/<đường dẫn>`,
thư mục không có `index.html` thì hiện trang danh sách. Nội dung folder bị gitignore vì
repo public — **đừng commit**.

**Phải đăng nhập mới xem được** (user thường cũng xem được). Đăng nhập / mở app
(`/api/login`, `/api/me`) gắn thêm cookie `fs_share` (HttpOnly, `Path=/share`, 30 ngày);
chưa đăng nhập thì redirect `/login?next=/share/...` rồi quay lại đúng trang. Đăng xuất
xoá cookie.

**Tự lưu dữ liệu nhập trên trang.** Mỗi trang `.html` được chèn `priv/share/inject.js`:
giá trị người xem nhập (input, select, textarea, checkbox, radio, `contenteditable`) và
`localStorage` của trang được lưu lên server (bảng `shared_page_states`, **dùng chung cho
mọi người**, ô nào lưu sau thì thắng), mở lại / người khác F5 là thấy. Ghi đè file vẫn giữ
dữ liệu (ô nào còn cùng id/name thì khớp lại); xoá file / thư mục thì xoá luôn dữ liệu.

- **Qua UI:** Admin → tab "🔗 Chia sẻ HTML" → vào/tạo thư mục → chọn/kéo thả file
  `.html` → Upload. Tên file/thư mục được chuẩn hoá (bỏ dấu, chữ thường). Trùng tên:
  mặc định báo lỗi, tick **"Ghi đè file trùng tên"** mới thay bản cũ.
- **Qua rsync (máy dev):** bỏ file vào `share/` rồi `make share` (giữ cây thư mục), hoặc
  `make share FILE="a.html b.html" DIR=bao-cao` (thư mục đích tự tạo). Trùng tên mặc định
  **bỏ qua** file đã có trên server, thêm `OVERWRITE=1` để đè. Không xoá file trên server.
  Đặt `SHARE_BASE_URL="https://dev.pancake.vn:3200"` trong `deploy.config` để in đúng link.

Trang được serve với `Content-Security-Policy: sandbox …` → JS trong trang vẫn chạy nhưng
**không đọc được token đăng nhập** (localStorage) của app cùng domain; `localStorage`,
`sessionStorage`, `document.cookie` của trang là bản giả do `inject.js` cung cấp.
(`indexedDB` không có — trang nào dùng sẽ lỗi.)

> Upload qua UI > 1 MB mà bị lỗi 413: tăng `client_max_body_size` (vd `25m`) ở nginx
> ngoài (nơi terminate TLS) cho domain này.

---

# 🖥️ Cách 2 — mix release trên host

Frontend (React) + backend (Phoenix) chạy chung 1 server. Nginx serve file tĩnh
`frontend/dist` và proxy `/api` sang Phoenix release (cổng 4003).

```
Internet :443 ──► Nginx ──► file tĩnh React (dist/)
                     └────► /api  ──► Phoenix release :4003 ──► PostgreSQL
```

> **Quan trọng:** Elixir release không chạy cross-platform. Mọi build diễn ra
> **trên server** (qua `scripts/deploy_remote.sh`), không build dưới máy macOS.
> Đặt `DEPLOY_MODE="release"` trong `deploy.config` nếu dùng cách này.

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
