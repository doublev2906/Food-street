import { useEffect, useState } from "react";
import {
  api,
  formatVND,
  today,
  type FundTransaction,
  type MenuItem,
  type Order,
  type Stats,
  type User,
} from "../api";
import { Header, Modal, Money, StatusBadge } from "../components";

type Tab = "stats" | "users" | "menu" | "orders" | "fund";

export default function AdminDashboard() {
  const [tab, setTab] = useState<Tab>("stats");
  const tabs: [Tab, string][] = [
    ["stats", "📊 Tổng quan"],
    ["users", "👥 Người dùng"],
    ["menu", "🍽️ Thực đơn"],
    ["orders", "📋 Đơn hàng"],
    ["fund", "💰 Quỹ"],
  ];
  return (
    <>
      <Header subtitle="Khu vực quản trị" />
      <div className="container">
        <div className="tabs">
          {tabs.map(([key, label]) => (
            <button
              key={key}
              className={`tab ${tab === key ? "active" : ""}`}
              onClick={() => setTab(key)}
            >
              {label}
            </button>
          ))}
        </div>
        {tab === "stats" && <StatsTab />}
        {tab === "users" && <UsersTab />}
        {tab === "menu" && <MenuTab />}
        {tab === "orders" && <OrdersTab />}
        {tab === "fund" && <FundTab />}
      </div>
    </>
  );
}

// ---------- Tổng quan ----------
function StatsTab() {
  const [date, setDate] = useState(today());
  const [stats, setStats] = useState<Stats | null>(null);

  useEffect(() => {
    api.admin.stats(date).then((r) => setStats(r.data)).catch(() => setStats(null));
  }, [date]);

  if (!stats) return <div className="spinner">Đang tải…</div>;

  return (
    <div className="grid">
      <div className="row between wrap">
        <h2 style={{ margin: 0 }}>Thống kê ngày</h2>
        <input
          type="date"
          value={date}
          onChange={(e) => setDate(e.target.value)}
          style={{ width: "auto" }}
        />
      </div>

      <div className="grid grid-4">
        <Stat label="Tổng người dùng" value={stats.total_users} />
        <Stat label="Đang hoạt động" value={stats.active_users} />
        <Stat label="Tổng quỹ" value={formatVND(stats.fund_total)} accent />
        <Stat label="Doanh thu (đã chốt)" value={formatVND(stats.revenue_today)} accent />
      </div>
      <div className="grid grid-3">
        <Stat label="Đơn trong ngày" value={stats.orders_today} />
        <Stat label="Chờ chốt" value={stats.pending_today} warn={stats.pending_today > 0} />
        <Stat label="Đã chốt" value={stats.confirmed_today} />
      </div>

      <div className="card">
        <h2>Món đặt nhiều nhất</h2>
        {stats.top_items.length === 0 ? (
          <p className="muted">Chưa có dữ liệu cho ngày này.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Món</th>
                <th style={{ textAlign: "right" }}>Số lượng</th>
                <th style={{ textAlign: "right" }}>Doanh thu</th>
              </tr>
            </thead>
            <tbody>
              {stats.top_items.map((it) => (
                <tr key={it.item_name}>
                  <td>{it.item_name}</td>
                  <td style={{ textAlign: "right" }}>{it.quantity}</td>
                  <td style={{ textAlign: "right" }}>{formatVND(it.revenue)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

function Stat({
  label,
  value,
  accent,
  warn,
}: {
  label: string;
  value: string | number;
  accent?: boolean;
  warn?: boolean;
}) {
  return (
    <div className="stat">
      <p className="label">{label}</p>
      <div
        className="value"
        style={{ color: accent ? "var(--primary)" : warn ? "var(--warn)" : undefined }}
      >
        {value}
      </div>
    </div>
  );
}

// ---------- Người dùng ----------
const emptyUser = { name: "", email: "", password: "", role: "user" as const, active: true };

function UsersTab() {
  const [users, setUsers] = useState<User[]>([]);
  const [editing, setEditing] = useState<User | null>(null);
  const [creating, setCreating] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = () => {
    setLoading(true);
    api.admin.users().then((r) => setUsers(r.data)).finally(() => setLoading(false));
  };
  useEffect(load, []);

  const remove = async (u: User) => {
    if (!confirm(`Xóa người dùng "${u.name}"?`)) return;
    try {
      await api.admin.deleteUser(u.id);
      load();
    } catch (e: any) {
      alert(e.message);
    }
  };

  return (
    <div className="grid">
      <div className="row between">
        <h2 style={{ margin: 0 }}>Người dùng ({users.length})</h2>
        <button onClick={() => setCreating(true)}>+ Thêm người dùng</button>
      </div>

      <div className="card" style={{ padding: 0, overflow: "hidden" }}>
        {loading ? (
          <div className="spinner">Đang tải…</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Tên</th>
                <th>Email</th>
                <th>Vai trò</th>
                <th>Trạng thái</th>
                <th style={{ textAlign: "right" }}>Số dư</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {users.map((u) => (
                <tr key={u.id}>
                  <td>
                    <strong>{u.name}</strong>
                  </td>
                  <td className="muted">{u.email}</td>
                  <td>
                    <span className={`badge ${u.role}`}>{u.role}</span>
                  </td>
                  <td>
                    {u.active ? (
                      <span className="badge confirmed">Hoạt động</span>
                    ) : (
                      <span className="badge inactive">Khóa</span>
                    )}
                  </td>
                  <td style={{ textAlign: "right" }}>{formatVND(u.balance)}</td>
                  <td>
                    <div className="row" style={{ justifyContent: "flex-end" }}>
                      <button className="secondary small" onClick={() => setEditing(u)}>
                        Sửa
                      </button>
                      <button className="danger small" onClick={() => remove(u)}>
                        Xóa
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {creating && (
        <UserModal
          title="Thêm người dùng"
          initial={emptyUser}
          requirePassword
          onClose={() => setCreating(false)}
          onSubmit={async (data) => {
            await api.admin.createUser(data as any);
            setCreating(false);
            load();
          }}
        />
      )}
      {editing && (
        <UserModal
          title="Sửa người dùng"
          initial={{ ...editing, password: "" }}
          onClose={() => setEditing(null)}
          onSubmit={async (data) => {
            const payload: any = { ...data };
            if (!payload.password) delete payload.password;
            await api.admin.updateUser(editing.id, payload);
            setEditing(null);
            load();
          }}
        />
      )}
    </div>
  );
}

function UserModal({
  title,
  initial,
  requirePassword,
  onClose,
  onSubmit,
}: {
  title: string;
  initial: any;
  requirePassword?: boolean;
  onClose: () => void;
  onSubmit: (data: any) => Promise<void>;
}) {
  const [form, setForm] = useState(initial);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setBusy(true);
    try {
      await onSubmit(form);
    } catch (err: any) {
      setError(err.message || "Lưu thất bại");
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title={title} onClose={onClose}>
      {error && <div className="alert error">{error}</div>}
      <form onSubmit={submit}>
        <div className="field">
          <label>Tên</label>
          <input
            value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
            required
          />
        </div>
        <div className="field">
          <label>Email</label>
          <input
            type="email"
            value={form.email}
            onChange={(e) => setForm({ ...form, email: e.target.value })}
            required
          />
        </div>
        <div className="field">
          <label>Mật khẩu {requirePassword ? "" : "(để trống nếu không đổi)"}</label>
          <input
            type="password"
            value={form.password || ""}
            onChange={(e) => setForm({ ...form, password: e.target.value })}
            required={requirePassword}
            minLength={6}
          />
        </div>
        <div className="grid grid-2">
          <div className="field">
            <label>Vai trò</label>
            <select
              value={form.role}
              onChange={(e) => setForm({ ...form, role: e.target.value })}
            >
              <option value="user">user</option>
              <option value="admin">admin</option>
            </select>
          </div>
          <div className="field">
            <label>Trạng thái</label>
            <select
              value={form.active ? "1" : "0"}
              onChange={(e) => setForm({ ...form, active: e.target.value === "1" })}
            >
              <option value="1">Hoạt động</option>
              <option value="0">Khóa</option>
            </select>
          </div>
        </div>
        <div className="row" style={{ justifyContent: "flex-end" }}>
          <button type="button" className="secondary" onClick={onClose}>
            Hủy
          </button>
          <button type="submit" disabled={busy}>
            {busy ? "Đang lưu…" : "Lưu"}
          </button>
        </div>
      </form>
    </Modal>
  );
}

// ---------- Thực đơn ----------
function MenuTab() {
  const [items, setItems] = useState<MenuItem[]>([]);
  const [editing, setEditing] = useState<MenuItem | null>(null);
  const [creating, setCreating] = useState(false);

  const load = () => api.admin.menu().then((r) => setItems(r.data));
  useEffect(() => {
    load();
  }, []);

  const remove = async (m: MenuItem) => {
    if (!confirm(`Xóa món "${m.name}"?`)) return;
    await api.admin.deleteMenu(m.id);
    load();
  };

  return (
    <div className="grid">
      <div className="row between">
        <h2 style={{ margin: 0 }}>Thực đơn ({items.length})</h2>
        <button onClick={() => setCreating(true)}>+ Thêm món</button>
      </div>
      <div className="card" style={{ padding: 0, overflow: "hidden" }}>
        <table>
          <thead>
            <tr>
              <th>Tên món</th>
              <th>Mô tả</th>
              <th style={{ textAlign: "right" }}>Giá</th>
              <th>Trạng thái</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((m) => (
              <tr key={m.id}>
                <td>
                  <strong>{m.name}</strong>
                </td>
                <td className="muted small">{m.description}</td>
                <td style={{ textAlign: "right" }}>{formatVND(m.price)}</td>
                <td>
                  {m.available ? (
                    <span className="badge confirmed">Còn bán</span>
                  ) : (
                    <span className="badge inactive">Ẩn</span>
                  )}
                </td>
                <td>
                  <div className="row" style={{ justifyContent: "flex-end" }}>
                    <button className="secondary small" onClick={() => setEditing(m)}>
                      Sửa
                    </button>
                    <button className="danger small" onClick={() => remove(m)}>
                      Xóa
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {(creating || editing) && (
        <MenuModal
          item={editing}
          onClose={() => {
            setCreating(false);
            setEditing(null);
          }}
          onSaved={() => {
            setCreating(false);
            setEditing(null);
            load();
          }}
        />
      )}
    </div>
  );
}

function MenuModal({
  item,
  onClose,
  onSaved,
}: {
  item: MenuItem | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState({
    name: item?.name || "",
    description: item?.description || "",
    price: item?.price || "",
    available: item?.available ?? true,
  });
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setBusy(true);
    try {
      const payload = { ...form, price: String(form.price) };
      if (item) await api.admin.updateMenu(item.id, payload);
      else await api.admin.createMenu(payload);
      onSaved();
    } catch (err: any) {
      setError(err.message || "Lưu thất bại");
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title={item ? "Sửa món" : "Thêm món"} onClose={onClose}>
      {error && <div className="alert error">{error}</div>}
      <form onSubmit={submit}>
        <div className="field">
          <label>Tên món</label>
          <input
            value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
            required
          />
        </div>
        <div className="field">
          <label>Mô tả</label>
          <input
            value={form.description}
            onChange={(e) => setForm({ ...form, description: e.target.value })}
          />
        </div>
        <div className="grid grid-2">
          <div className="field">
            <label>Giá (đ)</label>
            <input
              type="number"
              min={0}
              value={form.price}
              onChange={(e) => setForm({ ...form, price: e.target.value })}
              required
            />
          </div>
          <div className="field">
            <label>Trạng thái</label>
            <select
              value={form.available ? "1" : "0"}
              onChange={(e) => setForm({ ...form, available: e.target.value === "1" })}
            >
              <option value="1">Còn bán</option>
              <option value="0">Ẩn</option>
            </select>
          </div>
        </div>
        <div className="row" style={{ justifyContent: "flex-end" }}>
          <button type="button" className="secondary" onClick={onClose}>
            Hủy
          </button>
          <button type="submit" disabled={busy}>
            {busy ? "Đang lưu…" : "Lưu"}
          </button>
        </div>
      </form>
    </Modal>
  );
}

// ---------- Đơn hàng ----------
function OrdersTab() {
  const [date, setDate] = useState(today());
  const [status, setStatus] = useState("");
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);
  const [msg, setMsg] = useState("");

  const load = () => {
    setLoading(true);
    api.admin
      .orders(date, status || undefined)
      .then((r) => setOrders(r.data))
      .finally(() => setLoading(false));
  };
  useEffect(load, [date, status]);

  const confirmOne = async (o: Order) => {
    try {
      await api.admin.confirmOrder(o.id);
      load();
    } catch (e: any) {
      alert(e.message);
    }
  };

  const confirmAll = async () => {
    const pending = orders.filter((o) => o.status === "pending").length;
    if (pending === 0) return;
    if (!confirm(`Chốt tất cả ${pending} đơn chờ của ngày ${date}?`)) return;
    const r = await api.admin.confirmDate(date);
    setMsg(`Đã chốt ${r.data.confirmed}/${r.data.total} đơn.`);
    load();
  };

  const pendingCount = orders.filter((o) => o.status === "pending").length;

  return (
    <div className="grid">
      <div className="row between wrap">
        <h2 style={{ margin: 0 }}>Đơn hàng</h2>
        <div className="row wrap">
          <input
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            style={{ width: "auto" }}
          />
          <select
            value={status}
            onChange={(e) => setStatus(e.target.value)}
            style={{ width: "auto" }}
          >
            <option value="">Tất cả</option>
            <option value="pending">Chờ chốt</option>
            <option value="confirmed">Đã chốt</option>
            <option value="cancelled">Đã hủy</option>
          </select>
          <button className="success" onClick={confirmAll} disabled={pendingCount === 0}>
            Chốt tất cả ({pendingCount})
          </button>
        </div>
      </div>

      {msg && <div className="alert success">{msg}</div>}

      {loading ? (
        <div className="spinner">Đang tải…</div>
      ) : orders.length === 0 ? (
        <div className="card muted">Không có đơn nào cho bộ lọc này.</div>
      ) : (
        <div className="grid">
          {orders.map((o) => (
            <div key={o.id} className="card">
              <div className="row between wrap">
                <div>
                  <strong>{o.user?.name || "?"}</strong>{" "}
                  <span className="muted small">{o.user?.email}</span>
                  <div className="small muted">{o.order_date}</div>
                </div>
                <div className="row">
                  <StatusBadge status={o.status} />
                  <strong>{formatVND(o.total_amount)}</strong>
                  {o.status === "pending" && (
                    <button className="success small" onClick={() => confirmOne(o)}>
                      Chốt đơn
                    </button>
                  )}
                </div>
              </div>
              <table className="mt">
                <tbody>
                  {o.items.map((it) => (
                    <tr key={it.id}>
                      <td>{it.item_name}</td>
                      <td className="muted">×{it.quantity}</td>
                      <td style={{ textAlign: "right" }}>{formatVND(it.subtotal)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {o.note && <div className="small muted mt">Ghi chú: {o.note}</div>}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ---------- Quỹ ----------
function FundTab() {
  const [users, setUsers] = useState<User[]>([]);
  const [txs, setTxs] = useState<FundTransaction[]>([]);
  const [modal, setModal] = useState<"deposit" | "adjust" | null>(null);

  const load = () => {
    api.admin.users().then((r) => setUsers(r.data));
    api.admin.fundTransactions().then((r) => setTxs(r.data));
  };
  useEffect(load, []);

  const typeLabel: Record<string, string> = {
    deposit: "Nạp quỹ",
    order: "Trừ đơn",
    adjustment: "Điều chỉnh",
  };

  const total = users.reduce((s, u) => s + parseFloat(u.balance), 0);

  return (
    <div className="grid">
      <div className="row between wrap">
        <div className="stat" style={{ minWidth: 240 }}>
          <p className="label">Tổng quỹ toàn hệ thống</p>
          <div className="value" style={{ color: "var(--primary)" }}>
            {formatVND(total)}
          </div>
        </div>
        <div className="row">
          <button onClick={() => setModal("deposit")}>+ Nạp quỹ</button>
          <button className="secondary" onClick={() => setModal("adjust")}>
            Điều chỉnh
          </button>
        </div>
      </div>

      <div className="card">
        <h2>Số dư theo người dùng</h2>
        <table>
          <thead>
            <tr>
              <th>Người dùng</th>
              <th>Email</th>
              <th style={{ textAlign: "right" }}>Số dư</th>
            </tr>
          </thead>
          <tbody>
            {users.map((u) => (
              <tr key={u.id}>
                <td>{u.name}</td>
                <td className="muted">{u.email}</td>
                <td style={{ textAlign: "right" }}>
                  <strong>{formatVND(u.balance)}</strong>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h2>Lịch sử giao dịch quỹ</h2>
        {txs.length === 0 ? (
          <p className="muted">Chưa có giao dịch.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Thời gian</th>
                <th>Người dùng</th>
                <th>Loại</th>
                <th>Diễn giải</th>
                <th style={{ textAlign: "right" }}>Số tiền</th>
                <th style={{ textAlign: "right" }}>Số dư sau</th>
              </tr>
            </thead>
            <tbody>
              {txs.map((t) => (
                <tr key={t.id}>
                  <td className="small muted">
                    {new Date(t.inserted_at).toLocaleString("vi-VN")}
                  </td>
                  <td>{t.user?.name}</td>
                  <td>{typeLabel[t.type] || t.type}</td>
                  <td className="small">{t.description}</td>
                  <td style={{ textAlign: "right" }}>
                    <Money value={t.amount} sign />
                  </td>
                  <td style={{ textAlign: "right" }}>{formatVND(t.balance_after)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {modal && (
        <FundModal
          mode={modal}
          users={users}
          onClose={() => setModal(null)}
          onSaved={() => {
            setModal(null);
            load();
          }}
        />
      )}
    </div>
  );
}

function FundModal({
  mode,
  users,
  onClose,
  onSaved,
}: {
  mode: "deposit" | "adjust";
  users: User[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [userId, setUserId] = useState(users[0]?.id || "");
  const [amount, setAmount] = useState("");
  const [description, setDescription] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setBusy(true);
    try {
      if (mode === "deposit") await api.admin.deposit(userId, amount, description);
      else await api.admin.adjust(userId, amount, description);
      onSaved();
    } catch (err: any) {
      setError(err.message || "Thất bại");
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title={mode === "deposit" ? "Nạp quỹ" : "Điều chỉnh quỹ"} onClose={onClose}>
      {error && <div className="alert error">{error}</div>}
      <form onSubmit={submit}>
        <div className="field">
          <label>Người dùng</label>
          <select value={userId} onChange={(e) => setUserId(e.target.value)} required>
            {users.map((u) => (
              <option key={u.id} value={u.id}>
                {u.name} — {formatVND(u.balance)}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>
            Số tiền (đ){" "}
            {mode === "adjust" && (
              <span className="muted">— có thể âm để trừ</span>
            )}
          </label>
          <input
            type="number"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder={mode === "adjust" ? "VD: -50000" : "VD: 200000"}
            required
          />
        </div>
        <div className="field">
          <label>Diễn giải</label>
          <input
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="VD: Nạp quỹ tháng 7"
          />
        </div>
        <div className="row" style={{ justifyContent: "flex-end" }}>
          <button type="button" className="secondary" onClick={onClose}>
            Hủy
          </button>
          <button type="submit" disabled={busy}>
            {busy ? "Đang xử lý…" : "Xác nhận"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
