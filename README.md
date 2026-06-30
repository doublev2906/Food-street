# 🍜 Food Street — Hệ thống đặt đồ ăn sáng

Hệ thống đặt đồ ăn sáng nội bộ với quản lý quỹ chung.

- **Backend**: Elixir / Phoenix 1.8 (API-only) + PostgreSQL
- **Frontend**: React + TypeScript (Vite)
- **Auth**: JWT (Guardian)

## Hai vai trò (actor)

| Vai trò | Chức năng |
|--------|-----------|
| **User** | Đăng nhập · Đặt đồ ăn · Xem số dư quỹ + lịch sử giao dịch · Hủy đơn chưa chốt |
| **Admin** | Tất cả của user + CRUD người dùng · CRUD thực đơn · Xem thống kê · Chốt đơn (từng đơn hoặc cả ngày) · Quản lý quỹ (nạp / điều chỉnh) |

> User **chỉ được tạo bởi admin** (không có đăng ký công khai).

## Mô hình nghiệp vụ quỹ

- Mỗi user có một **số dư** (`balance`) trong quỹ chung.
- Admin **nạp quỹ** (`deposit`) hoặc **điều chỉnh** (`adjust`, có thể âm) cho user.
- User **đặt đơn** trong ngày → đơn ở trạng thái `pending` (chưa trừ tiền).
- Admin **chốt đơn** (`confirm`) → trừ tiền từ số dư user, ghi `fund_transaction`,
  đổi trạng thái đơn sang `confirmed`. Toàn bộ chạy trong **transaction** (atomic).
- Mỗi thay đổi số dư đều ghi lại một dòng trong `fund_transactions` để truy vết.

## Cơ sở dữ liệu

| Bảng | Mô tả |
|------|-------|
| `users` | name, email, password_hash, role, **balance**, active |
| `menu_items` | name, description, price, available |
| `orders` | user_id, order_date, status, total_amount, note, confirmed_at |
| `order_items` | order_id, menu_item_id, item_name + unit_price (snapshot), quantity, subtotal |
| `fund_transactions` | user_id, amount, type (deposit/order/adjustment), balance_after, order_id, created_by_id |

---

## Chạy dự án

### Yêu cầu
- Elixir 1.18+, Erlang/OTP 27
- Node 20+
- PostgreSQL đang chạy

### 1. Backend (cổng 4003)

```bash
cd backend
mix deps.get
mix ecto.setup        # tạo DB + migrate + seed dữ liệu mẫu
mix phx.server
```

> Cấu hình DB ở `config/dev.exs` (mặc định user `pancake`, không mật khẩu, localhost).
> Sửa `username`/`password` cho phù hợp môi trường của bạn.

#### Hoặc chạy backend bằng Docker (dev)

Không cần cài Elixir/Postgres trên máy — chỉ cần Docker:

```bash
cd backend
docker compose up        # build + chạy Postgres + Phoenix (tự migrate & seed)
# chạy nền: docker compose up -d
docker compose down      # dừng
docker compose down -v   # dừng + xóa toàn bộ dữ liệu DB
```

- Backend: http://localhost:4003 — có **code reload** (source được mount qua volume).
- Postgres trong container map ra cổng **5433** ở host (tránh đụng Postgres local 5432).
- `_build`/`deps` để trong volume riêng nên không xung đột với bản biên dịch trên máy host.

### 2. Frontend (cổng 5173)

```bash
cd frontend
npm install
npm run dev
```

Mở http://localhost:5173

### Tài khoản demo (tạo bởi seed)

| Vai trò | Email | Mật khẩu |
|--------|-------|----------|
| Admin | `admin@foodstreet.vn` | `admin123` |
| User | `an@foodstreet.vn` | `user123` |
| User | `binh@foodstreet.vn` | `user123` |
| User | `cuong@foodstreet.vn` | `user123` |

---

## API tóm tắt

Base URL: `http://localhost:4003/api`

### Công khai
- `POST /login` → `{ token, user }`
- `GET /health`

### Cần đăng nhập (header `Authorization: Bearer <token>`)
- `GET /me`
- `GET /menu`
- `GET /orders` · `POST /orders` · `DELETE /orders/:id`
- `GET /fund/balance` · `GET /fund/transactions`

### Admin (`/api/admin`, yêu cầu role admin)
- `GET|POST|PUT|DELETE /users` (CRUD)
- `GET|POST|PUT|DELETE /menu` (CRUD thực đơn)
- `GET /orders?date=&status=`
- `POST /orders/:id/confirm` · `POST /orders/confirm_date` (chốt cả ngày)
- `GET /stats?date=` · `GET /stats/revenue?from=&to=`
- `GET /fund/transactions` · `POST /fund/deposit` · `POST /fund/adjust`

---

## Cấu trúc

```
food_street/
├── backend/                    # Phoenix API
│   ├── lib/food_street/         # Contexts: Accounts, Catalog, Ordering, Fund, Stats
│   │   ├── accounts/ catalog/ ordering/ fund/   # Schemas
│   │   └── guardian.ex          # JWT
│   ├── lib/food_street_web/
│   │   ├── controllers/         # + controllers/admin/
│   │   ├── auth/                # Pipeline + ErrorHandler
│   │   ├── plugs/               # RequireAdmin
│   │   └── router.ex
│   └── priv/repo/               # migrations + seeds.exs
└── frontend/                   # React + TS
    └── src/
        ├── api.ts               # API client + types + helpers
        ├── auth.tsx             # AuthContext
        ├── components.tsx       # Header, Modal, badges
        └── pages/               # Login, UserDashboard, AdminDashboard
```

## Ghi chú bảo mật (cho production)
- Đổi `secret_key` của Guardian trong `config/config.exs` (dùng biến môi trường).
- Thêm rate-limit cho `/login`.
- Mật khẩu băm bằng bcrypt; số tiền dùng `decimal` để tránh sai số.
