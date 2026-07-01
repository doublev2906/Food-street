import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import {
  api,
  formatVND,
  type FundTransaction,
  type GroupOrder,
  type GroupOrderDetail,
  type MenuItem,
  type Order,
} from "../api";
import { useAuth } from "../auth";
import { Header, Money, StatusBadge } from "../components";
import { categoryIcon, FoodThumb, GROUP_ORDER, menuGroup, type MenuGroup } from "../menu";

type Tab = "order" | "orders" | "fund";

const PAGE_SIZE = 18; // 6×3 như mockup

export default function UserDashboard() {
  const [tab, setTab] = useState<Tab>("order");
  return (
    <>
      <Header subtitle="Khu vực người dùng" />
      <div className="container">
        <div className="tabs center">
          <button className={`tab ${tab === "order" ? "active" : ""}`} onClick={() => setTab("order")}>
            🥢 Đặt theo đợt
          </button>
          <button className={`tab ${tab === "orders" ? "active" : ""}`} onClick={() => setTab("orders")}>
            📋 Đơn của tôi
          </button>
          <button className={`tab ${tab === "fund" ? "active" : ""}`} onClick={() => setTab("fund")}>
            💰 Quỹ của tôi
          </button>
        </div>

        {tab === "order" && <GroupOrdersTab onPlaced={() => setTab("orders")} />}
        {tab === "orders" && <MyOrdersTab />}
        {tab === "fund" && <FundTab />}
      </div>
    </>
  );
}

// ---------- Danh sách đợt + đặt món ----------
function GroupOrdersTab({ onPlaced }: { onPlaced: () => void }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const [groups, setGroups] = useState<GroupOrder[]>([]);
  // Deep-link: ?group=<id> mở thẳng form đặt của đợt đó.
  const [selected, setSelected] = useState<string | null>(searchParams.get("group"));
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api.openGroupOrders().then((r) => setGroups(r.data)).finally(() => setLoading(false));
  }, []);

  const back = () => {
    setSelected(null);
    if (searchParams.has("group")) {
      searchParams.delete("group");
      setSearchParams(searchParams, { replace: true });
    }
  };

  if (selected) return <OrderForm groupId={selected} onBack={back} onPlaced={onPlaced} />;

  if (loading) return <div className="spinner">Đang tải…</div>;
  if (groups.length === 0)
    return (
      <div className="card muted" style={{ textAlign: "center" }}>
        Hiện chưa có đợt đặt nào đang mở. Chờ admin tạo đợt nhé.
      </div>
    );

  return (
    <div className="batch-list">
      {groups.map((g) => (
        <div key={g.id} className="card batch-card">
          <div className="batch-head">
            <div className="icon-circle">{categoryIcon(g.category?.name)}</div>
            <div>
              <h2 className="batch-title">{g.title}</h2>
              <div className="row" style={{ gap: 8 }}>
                {g.category && <span className="badge admin">{g.category.name}</span>}
                <span className="small muted">📅 {g.order_date}</span>
              </div>
            </div>
          </div>
          <div className="divider" />
          {g.note && <p className="small muted batch-note">📌 {g.note}</p>}
          <button className="cta" onClick={() => setSelected(g.id)}>
            🧺 Đặt món cho đợt này
          </button>
        </div>
      ))}
    </div>
  );
}

// ---------- Form đặt món trong 1 đợt ----------
function OrderForm({
  groupId,
  onBack,
  onPlaced,
}: {
  groupId: string;
  onBack: () => void;
  onPlaced: () => void;
}) {
  const [detail, setDetail] = useState<GroupOrderDetail | null>(null);
  const [cart, setCart] = useState<Record<string, number>>({});
  const [itemNotes, setItemNotes] = useState<Record<string, string>>({});
  const [note, setNote] = useState("");
  const [msg, setMsg] = useState<{ type: "error" | "success"; text: string } | null>(null);
  const [busy, setBusy] = useState(false);
  // Bộ lọc / tìm / phân trang (client-side — không tăng call API)
  const [group, setGroup] = useState<MenuGroup | "all">("all");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);

  useEffect(() => {
    api.groupOrder(groupId).then((r) => {
      setDetail(r.data);
      if (r.data.my_order) {
        const c: Record<string, number> = {};
        const n: Record<string, string> = {};
        r.data.my_order.items.forEach((it) => {
          c[it.menu_item_id] = it.quantity;
          if (it.note) n[it.menu_item_id] = it.note;
        });
        setCart(c);
        setItemNotes(n);
        setNote(r.data.my_order.note || "");
      }
    });
  }, [groupId]);

  const setQty = (id: string, delta: number) =>
    setCart((c) => {
      const nextQ = (c[id] || 0) + delta;
      const next = { ...c };
      if (nextQ <= 0) delete next[id];
      else next[id] = nextQ;
      return next;
    });

  const items = detail?.menu_items ?? [];

  // Các nhóm có món (§6.2 hướng A: nhóm suy ra client-side trong 1 danh mục)
  const groupsPresent = useMemo(() => {
    const set = new Set(items.map(menuGroup));
    return GROUP_ORDER.filter((g) => set.has(g));
  }, [items]);

  // Lọc theo nhóm + từ khoá
  const filtered = useMemo(() => {
    const kw = q.trim().toLowerCase();
    return items.filter(
      (m) =>
        (group === "all" || menuGroup(m) === group) &&
        (kw === "" || m.name.toLowerCase().includes(kw))
    );
  }, [items, group, q]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const curPage = Math.min(page, totalPages);
  const pageItems = filtered.slice((curPage - 1) * PAGE_SIZE, curPage * PAGE_SIZE);

  const total = useMemo(
    () => items.reduce((sum, m) => sum + (cart[m.id] || 0) * parseFloat(m.price), 0),
    [cart, items]
  );
  const cartCount = Object.values(cart).reduce((a, b) => a + b, 0);

  if (!detail) return <div className="spinner">Đang tải…</div>;

  const closed = detail.group_order.status !== "open";

  const resetFilter = (g: MenuGroup | "all") => {
    setGroup(g);
    setPage(1);
  };

  const submit = async () => {
    setMsg(null);
    const payloadItems = Object.entries(cart).map(([menu_item_id, quantity]) => ({
      menu_item_id,
      quantity,
      note: itemNotes[menu_item_id]?.trim() || undefined,
    }));
    if (payloadItems.length === 0) {
      setMsg({ type: "error", text: "Hãy chọn ít nhất 1 món" });
      return;
    }
    setBusy(true);
    try {
      await api.orderInGroup(groupId, { note, items: payloadItems });
      setMsg({ type: "success", text: "Đặt món thành công!" });
      setTimeout(onPlaced, 600);
    } catch (e: any) {
      setMsg({ type: "error", text: e.message || "Đặt món thất bại" });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div>
      <button className="ghost mb" onClick={onBack}>
        ← Quay lại danh sách đặt
      </button>
      <div className="row between wrap mb">
        <h2 style={{ margin: 0 }}>
          {detail.group_order.title}{" "}
          {detail.group_order.category && (
            <span className="badge admin">{detail.group_order.category.name}</span>
          )}
        </h2>
        <span className="small muted">📅 {detail.group_order.order_date}</span>
      </div>

      {closed && <div className="alert error">Đợt này đã đóng, không thể đặt thêm.</div>}

      <div className="order-layout">
        {/* -------- Chọn món -------- */}
        <div className="card">
          <div className="row between wrap mb">
            <h2 style={{ margin: 0 }}>Chọn món</h2>
            <input
              className="search-box"
              value={q}
              onChange={(e) => {
                setQ(e.target.value);
                setPage(1);
              }}
              placeholder="🔍 Tìm món…"
            />
          </div>

          <div className="filter-tabs">
            <button
              className={`chip ${group === "all" ? "active" : ""}`}
              onClick={() => resetFilter("all")}
            >
              Tất cả
            </button>
            {groupsPresent.map((g) => (
              <button
                key={g}
                className={`chip ${group === g ? "active" : ""}`}
                onClick={() => resetFilter(g)}
              >
                {g}
              </button>
            ))}
          </div>

          {filtered.length === 0 ? (
            <p className="muted mt">Không tìm thấy món phù hợp.</p>
          ) : (
            <div className="menu-grid">
              {pageItems.map((m) => {
                const qty = cart[m.id] || 0;
                return (
                  <div key={m.id} className={`food-card ${qty > 0 ? "selected" : ""}`}>
                    <FoodThumb item={m} size={104} radius={10} />
                    <div className="food-name" title={m.name}>
                      {m.name}
                    </div>
                    <div className="food-price">{formatVND(m.price)}</div>
                    <div className="qty">
                      <button onClick={() => setQty(m.id, -1)} disabled={qty === 0 || closed}>
                        −
                      </button>
                      <span>{qty}</span>
                      <button onClick={() => setQty(m.id, 1)} disabled={closed}>
                        +
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}

          {totalPages > 1 && (
            <div className="pager">
              <button
                className="pager-btn"
                onClick={() => setPage((p) => Math.max(1, p - 1))}
                disabled={curPage === 1}
              >
                ‹
              </button>
              {Array.from({ length: totalPages }, (_, i) => i + 1).map((p) => (
                <button
                  key={p}
                  className={`pager-btn ${p === curPage ? "active" : ""}`}
                  onClick={() => setPage(p)}
                >
                  {p}
                </button>
              ))}
              <button
                className="pager-btn"
                onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                disabled={curPage === totalPages}
              >
                ›
              </button>
            </div>
          )}
        </div>

        {/* -------- Giỏ đặt -------- */}
        <div className="card cart-panel">
          <h2>Giỏ đặt</h2>
          {msg && <div className={`alert ${msg.type}`}>{msg.text}</div>}
          <p className="small muted">
            {detail.my_order
              ? `Bạn đã đặt ${cartCount} món — sửa lại sẽ thay thế đơn cũ.`
              : `Bạn đã chọn ${cartCount} món.`}
          </p>

          {cartCount === 0 ? (
            <div className="cart-empty">
              <div className="cart-empty-ic">🧺</div>
              <strong>Chưa có món nào</strong>
              <span className="small muted">Hãy chọn món bên trái để thêm vào giỏ.</span>
            </div>
          ) : (
            <div className="grid" style={{ gap: 10 }}>
              {items
                .filter((m) => cart[m.id])
                .map((m) => (
                  <div key={m.id} className="cart-line">
                    <div className="row between">
                      <span>
                        <strong>{m.name}</strong>{" "}
                        <span className="muted small">×{cart[m.id]}</span>
                      </span>
                      <span>{formatVND(parseFloat(m.price) * cart[m.id])}</span>
                    </div>
                    <input
                      className="mt"
                      style={{ fontSize: 13, padding: "6px 10px" }}
                      value={itemNotes[m.id] || ""}
                      onChange={(e) => setItemNotes((n) => ({ ...n, [m.id]: e.target.value }))}
                      placeholder="Ghi chú món này (vd: ít cay, không hành…)"
                      disabled={closed}
                    />
                  </div>
                ))}
            </div>
          )}

          <div className="field mt">
            <label>Ghi chú chung (tùy chọn)</label>
            <textarea
              rows={2}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Ghi chú cho cả đơn, vd: giao trước 8h…"
              disabled={closed}
            />
          </div>

          <div className="row between mt">
            <strong>Tổng cộng</strong>
            <strong style={{ fontSize: 18, color: "var(--primary)" }}>{formatVND(total)}</strong>
          </div>
          <button className="cta mt" onClick={submit} disabled={busy || closed}>
            {busy ? "Đang gửi…" : detail.my_order ? "Cập nhật đơn" : "Đặt món"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ---------- Đơn của tôi ----------
function MyOrdersTab() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);
  // Map menu_item_id -> ảnh (order_item không lưu ảnh) — fetch menu 1 lần cho tab này.
  const [imgMap, setImgMap] = useState<Record<string, MenuItem>>({});

  const load = () => {
    setLoading(true);
    api.myOrders().then((r) => setOrders(r.data)).finally(() => setLoading(false));
  };
  useEffect(load, []);

  useEffect(() => {
    api.menu().then((r) => {
      const map: Record<string, MenuItem> = {};
      r.data.forEach((m) => (map[m.id] = m));
      setImgMap(map);
    });
  }, []);

  const cancel = async (id: string) => {
    if (!confirm("Hủy đơn này?")) return;
    await api.cancelOrder(id);
    load();
  };

  if (loading) return <div className="spinner">Đang tải…</div>;
  if (orders.length === 0) return <div className="card muted">Bạn chưa có đơn nào.</div>;

  return (
    <div className="grid">
      {orders.map((o) => (
        <div key={o.id} className="card order-card">
          <div className="order-head">
            <div className="icon-circle sm">{categoryIcon(o.group_order?.category?.name)}</div>
            <div style={{ flex: 1 }}>
              <div className="row wrap" style={{ gap: 8 }}>
                <strong>{o.group_order?.title || o.order_date}</strong>
                <StatusBadge status={o.status} />
                {o.group_order?.category && (
                  <span className="badge admin">{o.group_order.category.name}</span>
                )}
              </div>
              <div className="small muted">📅 {o.order_date}</div>
            </div>
            <div className="row">
              <strong>{formatVND(o.total_amount)}</strong>
              {o.status === "pending" && (
                <button className="secondary danger-outline small" onClick={() => cancel(o.id)}>
                  Hủy
                </button>
              )}
            </div>
          </div>

          <div className="divider" />

          <div className="grid" style={{ gap: 12 }}>
            {o.items.map((it) => {
              const mi = imgMap[it.menu_item_id];
              return (
                <div key={it.id} className="order-line">
                  {mi ? (
                    <FoodThumb item={mi} size={44} radius={8} />
                  ) : (
                    <div className="food-thumb placeholder" style={{ width: 44, height: 44, fontSize: 20 }}>
                      🍽️
                    </div>
                  )}
                  <div style={{ flex: 1 }}>
                    <div>{it.item_name}</div>
                    {it.note && (
                      <div className="small" style={{ color: "var(--primary)" }}>
                        ↳ {it.note}
                      </div>
                    )}
                  </div>
                  <span className="muted" style={{ minWidth: 40, textAlign: "center" }}>
                    ×{it.quantity}
                  </span>
                  <strong style={{ minWidth: 90, textAlign: "right" }}>{formatVND(it.subtotal)}</strong>
                </div>
              );
            })}
          </div>
          {o.note && <div className="small muted mt">Ghi chú chung: {o.note}</div>}
        </div>
      ))}
    </div>
  );
}

// ---------- Quỹ của tôi ----------
function FundTab() {
  const { user, refresh } = useAuth();
  const [txs, setTxs] = useState<FundTransaction[]>([]);
  const [balance, setBalance] = useState<string>(user?.balance || "0");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([api.balance(), api.myTransactions()])
      .then(([b, t]) => {
        setBalance(b.balance);
        setTxs(t.data);
      })
      .finally(() => setLoading(false));
    refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const typeLabel: Record<string, string> = {
    deposit: "Nạp quỹ",
    order: "Trừ đơn",
    adjustment: "Điều chỉnh",
  };
  // badge class theo loại giao dịch
  const typeBadge: Record<string, string> = {
    deposit: "confirmed",
    order: "cancelled",
    adjustment: "admin",
  };

  return (
    <div className="grid">
      <div className="card balance-card">
        <div className="icon-circle">👛</div>
        <div>
          <p className="label" style={{ margin: 0 }}>
            Số dư quỹ hiện tại
          </p>
          <div className="balance-value">{formatVND(balance)}</div>
        </div>
      </div>

      <div className="card">
        <h2>Lịch sử giao dịch</h2>
        {loading ? (
          <div className="spinner">Đang tải…</div>
        ) : txs.length === 0 ? (
          <p className="muted">Chưa có giao dịch nào.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Thời gian</th>
                <th>Loại</th>
                <th>Diễn giải</th>
                <th style={{ textAlign: "right" }}>Số tiền</th>
                <th style={{ textAlign: "right" }}>Số dư sau</th>
              </tr>
            </thead>
            <tbody>
              {txs.map((t) => {
                const up = parseFloat(t.amount) >= 0;
                return (
                  <tr key={t.id}>
                    <td className="small muted">
                      <span className="row" style={{ gap: 8 }}>
                        <span className={`tx-arrow ${up ? "up" : "down"}`}>{up ? "↑" : "↓"}</span>
                        {new Date(t.inserted_at).toLocaleString("vi-VN")}
                      </span>
                    </td>
                    <td>
                      <span className={`badge ${typeBadge[t.type] || "user"}`}>
                        {typeLabel[t.type] || t.type}
                      </span>
                    </td>
                    <td className="small">{t.description}</td>
                    <td style={{ textAlign: "right" }}>
                      <Money value={t.amount} sign />
                    </td>
                    <td style={{ textAlign: "right" }}>{formatVND(t.balance_after)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
