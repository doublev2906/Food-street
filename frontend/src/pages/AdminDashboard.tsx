import { useEffect, useState } from "react";
import {
  api,
  formatVND,
  today,
  type Category,
  type ExternalPurchase,
  type FundTransaction,
  type GroupOrder,
  type MenuItem,
  type OrderSchedule,
  type PanchatSettings,
  type Stats,
  type User,
} from "../api";
import { Header, Modal, Money, StatusBadge } from "../components";

type Tab =
  | "stats"
  | "users"
  | "categories"
  | "menu"
  | "groups"
  | "fund"
  | "external"
  | "schedule"
  | "settings";

export default function AdminDashboard() {
  const [tab, setTab] = useState<Tab>("stats");
  const tabs: [Tab, string][] = [
    ["stats", "📊 Tổng quan"],
    ["groups", "🧾 Đơn nhóm"],
    ["users", "👥 Người dùng"],
    ["categories", "🏷️ Danh mục"],
    ["menu", "🍽️ Thực đơn"],
    ["fund", "💰 Quỹ"],
    ["external", "🍜 Mua ngoài"],
    ["schedule", "📅 Lịch hẹn"],
    ["settings", "⚙️ Cài đặt"],
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
        {tab === "groups" && <GroupOrdersTab />}
        {tab === "users" && <UsersTab />}
        {tab === "categories" && <CategoriesTab />}
        {tab === "menu" && <MenuTab />}
        {tab === "fund" && <FundTab />}
        {tab === "external" && <ExternalPurchaseTab />}
        {tab === "schedule" && <ScheduleTab />}
        {tab === "settings" && <SettingsTab />}
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
        <input type="date" value={date} onChange={(e) => setDate(e.target.value)} style={{ width: "auto" }} />
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

// ---------- Đơn nhóm ----------
function GroupOrdersTab() {
  const [groups, setGroups] = useState<GroupOrder[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [creating, setCreating] = useState(false);
  const [detailId, setDetailId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = () => {
    setLoading(true);
    api.admin.groupOrders().then((r) => setGroups(r.data)).finally(() => setLoading(false));
    api.admin.categories().then((r) => setCategories(r.data.filter((c) => c.active)));
  };
  useEffect(load, []);

  if (detailId)
    return <GroupDetail id={detailId} onBack={() => { setDetailId(null); load(); }} />;

  return (
    <div className="grid">
      <div className="row between">
        <h2 style={{ margin: 0 }}>Đợt đặt nhóm ({groups.length})</h2>
        <button onClick={() => setCreating(true)} disabled={categories.length === 0}>
          + Tạo đợt mới
        </button>
      </div>
      {categories.length === 0 && (
        <div className="alert error">Hãy tạo ít nhất 1 danh mục trước khi tạo đợt đặt.</div>
      )}

      {loading ? (
        <div className="spinner">Đang tải…</div>
      ) : groups.length === 0 ? (
        <div className="card muted">Chưa có đợt đặt nào.</div>
      ) : (
        <div className="grid grid-2">
          {groups.map((g) => (
            <div key={g.id} className="card">
              <div className="row between wrap">
                <div>
                  <h2 style={{ marginBottom: 4 }}>{g.title}</h2>
                  <span className="badge admin">{g.category?.name}</span>{" "}
                  <StatusBadge status={g.status} />
                </div>
              </div>
              <div className="small muted mt">📅 {g.order_date}</div>
              <div className="row between mt">
                <span className="small">
                  {g.order_count} đơn · <strong>{formatVND(g.total_amount || "0")}</strong>
                </span>
                <button className="secondary small" onClick={() => setDetailId(g.id)}>
                  Xem & chốt
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {creating && (
        <GroupModal
          categories={categories}
          onClose={() => setCreating(false)}
          onSaved={() => {
            setCreating(false);
            load();
          }}
        />
      )}
    </div>
  );
}

function GroupModal({
  categories,
  onClose,
  onSaved,
}: {
  categories: Category[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState({
    title: "",
    order_date: today(),
    category_id: categories[0]?.id || "",
    note: "",
  });
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setBusy(true);
    try {
      await api.admin.createGroupOrder(form);
      onSaved();
    } catch (err: any) {
      setError(err.message || "Lưu thất bại");
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title="Tạo đợt đặt nhóm" onClose={onClose}>
      {error && <div className="alert error">{error}</div>}
      <form onSubmit={submit}>
        <div className="field">
          <label>Tiêu đề</label>
          <input
            value={form.title}
            onChange={(e) => setForm({ ...form, title: e.target.value })}
            placeholder="VD: Ăn sáng thứ 2"
            required
          />
        </div>
        <div className="grid grid-2">
          <div className="field">
            <label>Danh mục</label>
            <select
              value={form.category_id}
              onChange={(e) => setForm({ ...form, category_id: e.target.value })}
              required
            >
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
          <div className="field">
            <label>Ngày</label>
            <input
              type="date"
              value={form.order_date}
              onChange={(e) => setForm({ ...form, order_date: e.target.value })}
              required
            />
          </div>
        </div>
        <div className="field">
          <label>Ghi chú</label>
          <input
            value={form.note}
            onChange={(e) => setForm({ ...form, note: e.target.value })}
            placeholder="VD: Chốt đơn lúc 8h"
          />
        </div>
        <div className="row" style={{ justifyContent: "flex-end" }}>
          <button type="button" className="secondary" onClick={onClose}>
            Hủy
          </button>
          <button type="submit" disabled={busy}>
            {busy ? "Đang lưu…" : "Tạo đợt"}
          </button>
        </div>
      </form>
    </Modal>
  );
}

function GroupDetail({ id, onBack }: { id: string; onBack: () => void }) {
  const [group, setGroup] = useState<GroupOrder | null>(null);
  const [msg, setMsg] = useState("");
  const [exportOpen, setExportOpen] = useState(false);

  const load = () => api.admin.groupOrder(id).then((r) => setGroup(r.data));
  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  if (!group) return <div className="spinner">Đang tải…</div>;

  const orders = group.orders || [];
  const pending = orders.filter((o) => o.status === "pending").length;
  const open = group.status === "open";

  const close = async () => {
    if (!confirm(`Chốt đợt "${group.title}"? Sẽ trừ quỹ ${pending} đơn và đóng đợt.`)) return;
    try {
      const r = await api.admin.closeGroupOrder(id);
      setMsg(`Đã chốt ${r.data.confirmed} đơn. Đợt đã đóng.`);
      load();
    } catch (e: any) {
      setMsg(e.message);
    }
  };

  const del = async () => {
    if (!confirm("Xóa đợt này? Mọi đơn trong đợt cũng bị xóa.")) return;
    await api.admin.deleteGroupOrder(id);
    onBack();
  };

  return (
    <div className="grid">
      <button className="ghost" style={{ alignSelf: "start" }} onClick={onBack}>
        ← Quay lại danh sách đợt
      </button>

      <div className="card">
        <div className="row between wrap">
          <div>
            <h2 style={{ marginBottom: 4 }}>
              {group.title} <StatusBadge status={group.status} />
            </h2>
            <span className="badge admin">{group.category?.name}</span>{" "}
            <span className="small muted">📅 {group.order_date}</span>
            {group.note && <div className="small muted mt">📌 {group.note}</div>}
          </div>
          <div className="row">
            <button
              className="secondary"
              onClick={() => setExportOpen(true)}
              disabled={orders.length === 0}
            >
              📋 Xuất đơn
            </button>
            {open && (
              <button className="success" onClick={close} disabled={pending === 0}>
                Chốt đợt ({pending})
              </button>
            )}
            <button className="danger" onClick={del}>
              Xóa đợt
            </button>
          </div>
        </div>
        {msg && <div className="alert success mt">{msg}</div>}
        <div className="row between mt">
          <span className="muted small">{orders.length} đơn</span>
          <strong>Tổng: {formatVND(group.total_amount || "0")}</strong>
        </div>
      </div>

      {orders.length === 0 ? (
        <div className="card muted">Chưa có ai đặt trong đợt này.</div>
      ) : (
        <div className="grid">
          {orders.map((o) => (
            <div key={o.id} className="card">
              <div className="row between wrap">
                <div>
                  <strong>{o.user?.name || "?"}</strong>{" "}
                  <span className="muted small">{o.user?.email}</span>
                </div>
                <div className="row">
                  <StatusBadge status={o.status} />
                  <strong>{formatVND(o.total_amount)}</strong>
                </div>
              </div>
              <table className="mt">
                <tbody>
                  {o.items.map((it) => (
                    <tr key={it.id}>
                      <td>
                        {it.item_name}
                        {it.note && (
                          <div className="small" style={{ color: "var(--primary)" }}>
                            ↳ {it.note}
                          </div>
                        )}
                      </td>
                      <td className="muted">×{it.quantity}</td>
                      <td style={{ textAlign: "right" }}>{formatVND(it.subtotal)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {o.note && <div className="small muted mt">Ghi chú chung: {o.note}</div>}
            </div>
          ))}
        </div>
      )}

      {exportOpen && <ExportModal group={group} onClose={() => setExportOpen(false)} />}
    </div>
  );
}

// Gộp đơn của 1 đợt thành text gửi người bán: gộp số lượng theo món, ghi chú
// hiển thị ngay dưới đúng món (kèm người đặt + số lượng).
function buildOrderExport(group: GroupOrder): string {
  const orders = (group.orders || []).filter((o) => o.status !== "cancelled");

  const names: string[] = []; // giữ thứ tự món xuất hiện
  const totals: Record<string, number> = {};
  const itemNotes: Record<string, string[]> = {}; // tên món -> các dòng ghi chú
  let totalItems = 0;
  let totalAmount = 0;

  orders.forEach((o) => {
    const who = o.user?.name || "?";
    o.items.forEach((it) => {
      if (!(it.item_name in totals)) {
        names.push(it.item_name);
        totals[it.item_name] = 0;
        itemNotes[it.item_name] = [];
      }
      totals[it.item_name] += it.quantity;
      totalItems += it.quantity;
      if (it.note && it.note.trim()) {
        itemNotes[it.item_name].push(`   • ${who} ×${it.quantity}: ${it.note.trim()}`);
      }
    });
    totalAmount += parseFloat(o.total_amount);
  });

  const lines: string[] = [];
  lines.push(`🍜 ${group.title} — ${group.order_date}`);
  lines.push("");
  names.forEach((name) => {
    lines.push(`${name} x${totals[name]}`);
    itemNotes[name].forEach((l) => lines.push(l));
  });

  const general = orders.filter((o) => o.note && o.note.trim());
  if (general.length) {
    lines.push("");
    lines.push("Ghi chú chung:");
    general.forEach((o) => lines.push(`- ${o.user?.name || "?"}: ${o.note!.trim()}`));
  }

  lines.push("");
  lines.push(`Tổng: ${totalItems} món · ${formatVND(totalAmount)}`);
  return lines.join("\n");
}

function ExportModal({ group, onClose }: { group: GroupOrder; onClose: () => void }) {
  const text = buildOrderExport(group);
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Trình duyệt chặn clipboard (vd không phải HTTPS) → người dùng tự bôi đen copy.
      setCopied(false);
    }
  };

  return (
    <Modal title="Xuất đơn gửi người bán" onClose={onClose}>
      <p className="small muted" style={{ marginTop: 0 }}>
        Copy nội dung dưới đây gửi cho người bán để đặt món.
      </p>
      <textarea
        readOnly
        value={text}
        onFocus={(e) => e.currentTarget.select()}
        rows={Math.min(20, text.split("\n").length + 1)}
        style={{ fontFamily: "ui-monospace, monospace", fontSize: 13, resize: "vertical" }}
      />
      <div className="row mt" style={{ justifyContent: "flex-end" }}>
        <button className="secondary" onClick={onClose}>
          Đóng
        </button>
        <button onClick={copy}>{copied ? "✓ Đã copy" : "Copy nội dung"}</button>
      </div>
    </Modal>
  );
}

// ---------- Danh mục ----------
function CategoriesTab() {
  const [items, setItems] = useState<Category[]>([]);
  const [editing, setEditing] = useState<Category | null>(null);
  const [creating, setCreating] = useState(false);

  const load = () => api.admin.categories().then((r) => setItems(r.data));
  useEffect(() => {
    load();
  }, []);

  const remove = async (c: Category) => {
    if (!confirm(`Xóa danh mục "${c.name}"? Các món trong danh mục sẽ bị gỡ danh mục.`)) return;
    await api.admin.deleteCategory(c.id);
    load();
  };

  return (
    <div className="grid">
      <div className="row between">
        <h2 style={{ margin: 0 }}>Danh mục ({items.length})</h2>
        <button onClick={() => setCreating(true)}>+ Thêm danh mục</button>
      </div>
      <div className="card" style={{ padding: 0, overflow: "hidden" }}>
        <table>
          <thead>
            <tr>
              <th>Tên</th>
              <th>Mô tả</th>
              <th>Trạng thái</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((c) => (
              <tr key={c.id}>
                <td>
                  <strong>{c.name}</strong>
                </td>
                <td className="muted small">{c.description}</td>
                <td>
                  {c.active ? (
                    <span className="badge confirmed">Hoạt động</span>
                  ) : (
                    <span className="badge inactive">Ẩn</span>
                  )}
                </td>
                <td>
                  <div className="row" style={{ justifyContent: "flex-end" }}>
                    <button className="secondary small" onClick={() => setEditing(c)}>
                      Sửa
                    </button>
                    <button className="danger small" onClick={() => remove(c)}>
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
        <CategoryModal
          category={editing}
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

function CategoryModal({
  category,
  onClose,
  onSaved,
}: {
  category: Category | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState({
    name: category?.name || "",
    description: category?.description || "",
    active: category?.active ?? true,
  });
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setBusy(true);
    try {
      if (category) await api.admin.updateCategory(category.id, form);
      else await api.admin.createCategory(form);
      onSaved();
    } catch (err: any) {
      setError(err.message || "Lưu thất bại");
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title={category ? "Sửa danh mục" : "Thêm danh mục"} onClose={onClose}>
      {error && <div className="alert error">{error}</div>}
      <form onSubmit={submit}>
        <div className="field">
          <label>Tên danh mục</label>
          <input
            value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
            placeholder="VD: Ăn sáng, Trà chiều, Mixue…"
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
        <div className="field">
          <label>Trạng thái</label>
          <select
            value={form.active ? "1" : "0"}
            onChange={(e) => setForm({ ...form, active: e.target.value === "1" })}
          >
            <option value="1">Hoạt động</option>
            <option value="0">Ẩn</option>
          </select>
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
  const [categories, setCategories] = useState<Category[]>([]);
  const [editing, setEditing] = useState<MenuItem | null>(null);
  const [creating, setCreating] = useState(false);

  const load = () => {
    api.admin.menu().then((r) => setItems(r.data));
    api.admin.categories().then((r) => setCategories(r.data));
  };
  useEffect(() => {
    load();
  }, []);

  const catName = (id: string | null) =>
    categories.find((c) => c.id === id)?.name || "—";

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
              <th>Danh mục</th>
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
                  <div className="muted small">{m.description}</div>
                </td>
                <td>
                  <span className="badge user">{catName(m.category_id)}</span>
                </td>
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
          categories={categories}
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
  categories,
  onClose,
  onSaved,
}: {
  item: MenuItem | null;
  categories: Category[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState({
    name: item?.name || "",
    description: item?.description || "",
    price: item?.price || "",
    available: item?.available ?? true,
    image_url: item?.image_url || "",
    category_id: item?.category_id || categories[0]?.id || "",
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
          <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
        </div>
        <div className="field">
          <label>Mô tả</label>
          <input
            value={form.description}
            onChange={(e) => setForm({ ...form, description: e.target.value })}
          />
        </div>
        <div className="field">
          <label>Ảnh món (URL)</label>
          <div className="row" style={{ alignItems: "flex-start" }}>
            {form.image_url && (
              <img
                src={form.image_url}
                alt=""
                style={{
                  width: 56,
                  height: 56,
                  borderRadius: 8,
                  objectFit: "cover",
                  border: "1px solid var(--border)",
                  flexShrink: 0,
                }}
                onError={(e) => (e.currentTarget.style.display = "none")}
              />
            )}
            <input
              value={form.image_url}
              onChange={(e) => setForm({ ...form, image_url: e.target.value })}
              placeholder="https://content.pancake.vn/…"
            />
          </div>
        </div>
        <div className="grid grid-2">
          <div className="field">
            <label>Danh mục</label>
            <select
              value={form.category_id}
              onChange={(e) => setForm({ ...form, category_id: e.target.value })}
            >
              <option value="">— Không —</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
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

// ---------- Người dùng ----------
const emptyUser = {
  name: "",
  username: "",
  email: "",
  password: "",
  role: "user" as const,
  active: true,
};

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
                    <div className="muted small">@{u.username}</div>
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
          <label>Tên hiển thị</label>
          <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
        </div>
        <div className="field">
          <label>Tên đăng nhập</label>
          <input
            value={form.username}
            onChange={(e) => setForm({ ...form, username: e.target.value })}
            placeholder="chữ thường, số, _ hoặc ."
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
            <select value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value })}>
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

// ---------- Quỹ ----------
function FundTab() {
  const [users, setUsers] = useState<User[]>([]);
  const [txs, setTxs] = useState<FundTransaction[]>([]);
  const [page, setPage] = useState(1);
  const [txMeta, setTxMeta] = useState({ total_pages: 1, total: 0 });
  const [modal, setModal] = useState<"deposit" | "adjust" | null>(null);

  const loadUsers = () => api.admin.users().then((r) => setUsers(r.data));
  const loadTxs = (p: number) =>
    api.admin.fundTransactions(p).then((r) => {
      setTxs(r.data);
      setTxMeta({ total_pages: r.total_pages, total: r.total });
    });

  useEffect(() => {
    loadUsers();
  }, []);
  useEffect(() => {
    loadTxs(page);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page]);

  // Sau khi nạp/điều chỉnh: cập nhật số dư + về trang 1 để thấy giao dịch mới.
  const afterMutation = () => {
    loadUsers();
    if (page === 1) loadTxs(1);
    else setPage(1);
  };

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
        <div className="row between wrap">
          <h2 style={{ margin: 0 }}>Lịch sử giao dịch quỹ</h2>
          {txMeta.total > 0 && (
            <span className="small muted">
              Trang {page}/{txMeta.total_pages} · {txMeta.total} giao dịch
            </span>
          )}
        </div>
        {txs.length === 0 ? (
          <p className="muted mt">Chưa có giao dịch.</p>
        ) : (
          <table className="mt">
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
                  <td className="small muted">{new Date(t.inserted_at).toLocaleString("vi-VN")}</td>
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

        {txMeta.total_pages > 1 && (
          <div className="row between mt">
            <button
              className="secondary small"
              disabled={page <= 1}
              onClick={() => setPage((p) => p - 1)}
            >
              ← Trước
            </button>
            <span className="small muted">
              Trang {page}/{txMeta.total_pages}
            </span>
            <button
              className="secondary small"
              disabled={page >= txMeta.total_pages}
              onClick={() => setPage((p) => p + 1)}
            >
              Sau →
            </button>
          </div>
        )}
      </div>

      {modal && (
        <FundModal
          mode={modal}
          users={users}
          onClose={() => setModal(null)}
          onSaved={() => {
            setModal(null);
            afterMutation();
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
            Số tiền (đ) {mode === "adjust" && <span className="muted">— có thể âm để trừ</span>}
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

// ---------- Cài đặt ----------
function SettingsTab() {
  const [settings, setSettings] = useState<PanchatSettings | null>(null);
  const [token, setToken] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ type: "ok" | "error"; text: string } | null>(
    null
  );

  const load = () => {
    api.admin
      .getPanchatSettings()
      .then((r) => setSettings(r.data))
      .catch((e) => setMsg({ type: "error", text: e.message || "Lỗi tải" }));
  };
  useEffect(load, []);

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    setMsg(null);
    setBusy(true);
    try {
      const r = await api.admin.savePanchatToken(token);
      setSettings(r.data);
      setToken("");
      setMsg({ type: "ok", text: "Đã lưu Panchat token." });
    } catch (err: any) {
      setMsg({ type: "error", text: err.message || "Lưu thất bại" });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="grid">
      <div className="card">
        <h2>Panchat</h2>
        <p className="small muted">
          Token Panchat <strong>của riêng bạn</strong> để gửi lời mời ăn sáng vào
          channel (workspace 4 / channel 11813). Mỗi admin dùng token riêng — đợt
          do bạn tạo sẽ gửi bằng token này.{" "}
          <strong>Bắt buộc phải có token</strong> thì bạn mới tạo được đợt đặt nhóm.
        </p>

        {settings && (
          <p className="small">
            Trạng thái:{" "}
            {settings.panchat_configured ? (
              <span className="badge admin">
                Đã cấu hình ({settings.panchat_token_preview})
              </span>
            ) : (
              <span className="badge">Chưa cấu hình</span>
            )}
          </p>
        )}

        {msg && (
          <div className={`alert ${msg.type === "ok" ? "" : "error"}`}>
            {msg.text}
          </div>
        )}

        <form onSubmit={save}>
          <div className="field">
            <label>Panchat token</label>
            <input
              type="password"
              value={token}
              onChange={(e) => setToken(e.target.value)}
              placeholder="Dán token Panchat vào đây…"
              autoComplete="off"
            />
          </div>
          <div className="row" style={{ justifyContent: "flex-end" }}>
            <button type="submit" disabled={busy || token.trim() === ""}>
              {busy ? "Đang lưu…" : "Lưu token"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

function ExternalPurchaseTab() {
  const [users, setUsers] = useState<User[]>([]);
  const [purchases, setPurchases] = useState<ExternalPurchase[]>([]);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ type: "ok" | "error"; text: string } | null>(
    null
  );

  const [description, setDescription] = useState("");
  const [total, setTotal] = useState("");
  const [date, setDate] = useState(today());
  const [checked, setChecked] = useState<Record<string, boolean>>({});
  const [amounts, setAmounts] = useState<Record<string, string>>({});

  const load = () => {
    api.admin.users().then((r) => setUsers(r.data.filter((u) => u.active)));
    api.admin.listExternalPurchases().then((r) => setPurchases(r.data));
  };
  useEffect(load, []);

  const selectedIds = users.filter((u) => checked[u.id]).map((u) => u.id);
  const totalNum = Math.round(Number(total) || 0);
  const sumShares = selectedIds.reduce(
    (acc, id) => acc + (Number(amounts[id]) || 0),
    0
  );
  const matched = selectedIds.length > 0 && sumShares === totalNum;

  const splitEven = () => {
    const n = selectedIds.length;
    if (n === 0 || totalNum <= 0) return;
    const base = Math.floor(totalNum / n);
    const remainder = totalNum - base * n;
    const next: Record<string, string> = { ...amounts };
    selectedIds.forEach((id, i) => {
      next[id] = String(base + (i === 0 ? remainder : 0));
    });
    setAmounts(next);
  };

  const toggle = (id: string) =>
    setChecked((c) => ({ ...c, [id]: !c[id] }));

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setMsg(null);
    setBusy(true);
    try {
      await api.admin.createExternalPurchase({
        description,
        total_amount: String(totalNum),
        purchase_date: date,
        shares: selectedIds.map((id) => ({
          user_id: id,
          amount: String(Number(amounts[id]) || 0),
        })),
      });
      setMsg({ type: "ok", text: "Đã lưu khoản mua ngoài." });
      setDescription("");
      setTotal("");
      setChecked({});
      setAmounts({});
      load();
    } catch (err: any) {
      setMsg({ type: "error", text: err.message || "Lưu thất bại" });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="grid">
      <div className="card">
        <h2>🍜 Chia tiền mua ngoài</h2>
        <p className="small muted">
          Ghi nhận món mua ngoài menu và chia tiền cho những người cùng ăn — số dư
          từng người sẽ bị trừ phần tương ứng.
        </p>

        {msg && (
          <div className={`alert ${msg.type === "ok" ? "" : "error"}`}>
            {msg.text}
          </div>
        )}

        <form onSubmit={submit}>
          <div className="field">
            <label>Mô tả</label>
            <input
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="VD: Bún chả cô Tâm"
              required
            />
          </div>
          <div className="grid grid-2">
            <div className="field">
              <label>Tổng tiền (đ)</label>
              <input
                type="number"
                min={0}
                value={total}
                onChange={(e) => setTotal(e.target.value)}
                required
              />
            </div>
            <div className="field">
              <label>Ngày</label>
              <input
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
                required
              />
            </div>
          </div>

          <div className="field">
            <div className="row between">
              <label>Người ăn ({selectedIds.length})</label>
              <button
                type="button"
                className="secondary"
                onClick={splitEven}
                disabled={selectedIds.length === 0 || totalNum <= 0}
              >
                Chia đều
              </button>
            </div>
            <div className="grid">
              {users.map((u) => (
                <div key={u.id} className="row between">
                  <label className="row" style={{ gap: 6 }}>
                    <input
                      type="checkbox"
                      checked={!!checked[u.id]}
                      onChange={() => toggle(u.id)}
                    />
                    {u.name}
                    <span className="badge">{u.role}</span>
                  </label>
                  <input
                    type="number"
                    min={0}
                    style={{ maxWidth: 140 }}
                    value={amounts[u.id] ?? ""}
                    disabled={!checked[u.id]}
                    onChange={(e) =>
                      setAmounts((a) => ({ ...a, [u.id]: e.target.value }))
                    }
                    placeholder="0"
                  />
                </div>
              ))}
            </div>
          </div>

          <p className={`small ${matched ? "muted" : "danger"}`}>
            Tổng đã chia: {formatVND(String(sumShares))} / {formatVND(String(totalNum))}
            {!matched && selectedIds.length > 0 && " — chưa khớp"}
          </p>

          <div className="row" style={{ justifyContent: "flex-end" }}>
            <button type="submit" disabled={busy || !matched || !description}>
              {busy ? "Đang lưu…" : "Lưu & chia tiền"}
            </button>
          </div>
        </form>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Khoản mua gần đây</h3>
        {purchases.length === 0 && (
          <p className="small muted">Chưa có khoản mua ngoài nào.</p>
        )}
        {purchases.map((p) => (
          <div key={p.id} className="row between" style={{ padding: "8px 0" }}>
            <div>
              <strong>{p.description}</strong>
              <div className="small muted">
                {p.purchase_date} ·{" "}
                {p.eaters.map((e) => `${e.name} (${formatVND(e.amount)})`).join(", ")}
              </div>
            </div>
            <Money value={p.total_amount} />
          </div>
        ))}
      </div>
    </div>
  );
}

const WEEKDAYS: [number, string][] = [
  [1, "T2"],
  [2, "T3"],
  [3, "T4"],
  [4, "T5"],
  [5, "T6"],
  [6, "T7"],
  [7, "CN"],
];

// "HH:MM:SS" -> "HH:MM" cho input type=time; "" nếu rỗng.
const toHHMM = (s: string | null) => (s ? s.slice(0, 5) : "");
// "HH:MM" -> "HH:MM:SS" khi gửi lên (Ecto :time cần đủ giây).
const toSeconds = (s: string) => (s.length === 5 ? `${s}:00` : s);

function ScheduleTab() {
  const [schedule, setSchedule] = useState<OrderSchedule | null>(null);
  const [admins, setAdmins] = useState<User[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ type: "ok" | "error"; text: string } | null>(
    null
  );

  const [form, setForm] = useState({
    enabled: false,
    owner_id: "",
    category_id: "",
    title: "Ăn sáng",
    note: "",
    weekdays: [1, 2, 3, 4, 5] as number[],
    create_time: "07:00",
    deadline_time: "08:30",
  });

  const load = () => {
    api.admin
      .getOrderSchedule()
      .then((r) => {
        const s = r.data;
        setSchedule(s);
        setForm({
          enabled: s.enabled,
          owner_id: s.owner_id || "",
          category_id: s.category_id || "",
          title: s.title || "Ăn sáng",
          note: s.note || "",
          weekdays: s.weekdays?.length ? s.weekdays : [1, 2, 3, 4, 5],
          create_time: toHHMM(s.create_time) || "07:00",
          deadline_time: toHHMM(s.deadline_time) || "08:30",
        });
      })
      .catch((e) => setMsg({ type: "error", text: e.message || "Lỗi tải" }));
    api.admin
      .users()
      .then((r) => setAdmins(r.data.filter((u) => u.role === "admin")));
    api.admin
      .categories()
      .then((r) => setCategories(r.data.filter((c) => c.active)));
  };
  useEffect(load, []);

  const toggleDay = (d: number) =>
    setForm((f) => ({
      ...f,
      weekdays: f.weekdays.includes(d)
        ? f.weekdays.filter((x) => x !== d)
        : [...f.weekdays, d].sort((a, b) => a - b),
    }));

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    setMsg(null);
    setBusy(true);
    try {
      const r = await api.admin.saveOrderSchedule({
        enabled: form.enabled,
        owner_id: form.owner_id || null,
        category_id: form.category_id || null,
        title: form.title,
        note: form.note,
        weekdays: form.weekdays,
        create_time: toSeconds(form.create_time),
        deadline_time: toSeconds(form.deadline_time),
      });
      setSchedule(r.data);
      setMsg({ type: "ok", text: "Đã lưu lịch hẹn." });
    } catch (err: any) {
      setMsg({ type: "error", text: err.message || "Lưu thất bại" });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="grid">
      <div className="card">
        <h2>📅 Lịch hẹn mở đợt tự động</h2>
        <p className="small muted">
          Hệ thống tự mở đợt đặt món vào giờ đã hẹn theo các ngày trong tuần, kèm
          giờ chốt đơn, rồi gửi lời mời Panchat bằng token của{" "}
          <strong>admin đứng tên</strong>. Chỉ 1 lịch dùng chung. Admin đứng tên{" "}
          <strong>phải có Panchat token</strong> thì mới bật được.
        </p>

        {schedule && form.enabled && !schedule.panchat_ready && (
          <div className="alert error">
            Admin đứng tên hiện chưa cấu hình Panchat token — lịch sẽ không chạy tới
            khi có token.
          </div>
        )}
        {schedule?.last_run_on && (
          <p className="small muted">Lần chạy gần nhất: {schedule.last_run_on}</p>
        )}
        {msg && (
          <div className={`alert ${msg.type === "ok" ? "" : "error"}`}>
            {msg.text}
          </div>
        )}

        <form onSubmit={save}>
          <div className="grid grid-2">
            <div className="field">
              <label>Trạng thái</label>
              <select
                value={form.enabled ? "1" : "0"}
                onChange={(e) =>
                  setForm({ ...form, enabled: e.target.value === "1" })
                }
              >
                <option value="1">Bật</option>
                <option value="0">Tắt</option>
              </select>
            </div>
            <div className="field">
              <label>Admin đứng tên</label>
              <select
                value={form.owner_id}
                onChange={(e) => setForm({ ...form, owner_id: e.target.value })}
                required={form.enabled}
              >
                <option value="">— Chọn admin —</option>
                {admins.map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.name}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="grid grid-2">
            <div className="field">
              <label>Danh mục</label>
              <select
                value={form.category_id}
                onChange={(e) =>
                  setForm({ ...form, category_id: e.target.value })
                }
                required={form.enabled}
              >
                <option value="">— Chọn danh mục —</option>
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="field">
              <label>Tiêu đề đợt</label>
              <input
                value={form.title}
                onChange={(e) => setForm({ ...form, title: e.target.value })}
                placeholder="VD: Ăn sáng"
                required={form.enabled}
              />
            </div>
          </div>

          <div className="field">
            <label>Ghi chú (tuỳ chọn)</label>
            <input
              value={form.note}
              onChange={(e) => setForm({ ...form, note: e.target.value })}
              placeholder="VD: Chốt đơn lúc 8h30"
            />
          </div>

          <div className="field">
            <label>Các ngày trong tuần</label>
            <div className="row" style={{ flexWrap: "wrap", gap: 12 }}>
              {WEEKDAYS.map(([d, label]) => (
                <label key={d} className="row" style={{ gap: 4 }}>
                  <input
                    type="checkbox"
                    checked={form.weekdays.includes(d)}
                    onChange={() => toggleDay(d)}
                  />
                  {label}
                </label>
              ))}
            </div>
          </div>

          <div className="grid grid-2">
            <div className="field">
              <label>Giờ mở đợt</label>
              <input
                type="time"
                value={form.create_time}
                onChange={(e) =>
                  setForm({ ...form, create_time: e.target.value })
                }
                required={form.enabled}
              />
            </div>
            <div className="field">
              <label>Giờ chốt đơn</label>
              <input
                type="time"
                value={form.deadline_time}
                onChange={(e) =>
                  setForm({ ...form, deadline_time: e.target.value })
                }
                required={form.enabled}
              />
            </div>
          </div>

          <div className="row" style={{ justifyContent: "flex-end" }}>
            <button type="submit" disabled={busy}>
              {busy ? "Đang lưu…" : "Lưu lịch hẹn"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
