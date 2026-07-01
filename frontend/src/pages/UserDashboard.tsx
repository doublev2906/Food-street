import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import {
  api,
  formatVND,
  type FundTransaction,
  type GroupOrder,
  type GroupOrderDetail,
  type Order,
} from "../api";
import { useAuth } from "../auth";
import { Header, Money, StatusBadge } from "../components";

type Tab = "order" | "orders" | "fund";

export default function UserDashboard() {
  const [tab, setTab] = useState<Tab>("order");
  return (
    <>
      <Header subtitle="Khu vực người dùng" />
      <div className="container">
        <div className="tabs">
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

  if (selected)
    return <OrderForm groupId={selected} onBack={back} onPlaced={onPlaced} />;

  if (loading) return <div className="spinner">Đang tải…</div>;
  if (groups.length === 0)
    return <div className="card muted">Hiện chưa có đợt đặt nào đang mở. Chờ admin tạo đợt nhé.</div>;

  return (
    <div className="grid grid-2">
      {groups.map((g) => (
        <div key={g.id} className="card">
          <div className="row between wrap">
            <div>
              <h2 style={{ marginBottom: 4 }}>{g.title}</h2>
              <span className="badge admin">{g.category?.name}</span>{" "}
              <span className="small muted">📅 {g.order_date}</span>
            </div>
          </div>
          {g.note && <p className="small muted mt">📌 {g.note}</p>}
          <button className="mt" style={{ width: "100%" }} onClick={() => setSelected(g.id)}>
            Đặt món cho đợt này
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

  useEffect(() => {
    api.groupOrder(groupId).then((r) => {
      setDetail(r.data);
      // nạp lại đơn cũ nếu đã đặt
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
      const q = (c[id] || 0) + delta;
      const next = { ...c };
      if (q <= 0) delete next[id];
      else next[id] = q;
      return next;
    });

  const total = useMemo(() => {
    if (!detail) return 0;
    return detail.menu_items.reduce(
      (sum, m) => sum + (cart[m.id] || 0) * parseFloat(m.price),
      0
    );
  }, [cart, detail]);

  if (!detail) return <div className="spinner">Đang tải…</div>;

  const closed = detail.group_order.status !== "open";

  const submit = async () => {
    setMsg(null);
    const items = Object.entries(cart).map(([menu_item_id, quantity]) => ({
      menu_item_id,
      quantity,
      note: itemNotes[menu_item_id]?.trim() || undefined,
    }));
    if (items.length === 0) {
      setMsg({ type: "error", text: "Hãy chọn ít nhất 1 món" });
      return;
    }
    setBusy(true);
    try {
      await api.orderInGroup(groupId, { note, items });
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
        ← Quay lại danh sách đợt
      </button>
      <div className="row between wrap mb">
        <h2 style={{ margin: 0 }}>
          {detail.group_order.title}{" "}
          <span className="badge admin">{detail.group_order.category?.name}</span>
        </h2>
        <span className="small muted">📅 {detail.group_order.order_date}</span>
      </div>

      {closed && <div className="alert error">Đợt này đã đóng, không thể đặt thêm.</div>}

      <div className="grid grid-2">
        <div className="card">
          <h2>Thực đơn — {detail.group_order.category?.name}</h2>
          {detail.menu_items.length === 0 && <p className="muted">Đợt này chưa có món.</p>}
          {detail.menu_items.map((m) => {
            const q = cart[m.id] || 0;
            return (
              <div key={m.id} className={`menu-item ${q > 0 ? "selected" : ""}`}>
                <div>
                  <strong>{m.name}</strong>
                  <div className="small muted">{m.description}</div>
                  <div className="small">{formatVND(m.price)}</div>
                </div>
                <div className="qty">
                  <button onClick={() => setQty(m.id, -1)} disabled={q === 0 || closed}>
                    −
                  </button>
                  <span>{q}</span>
                  <button onClick={() => setQty(m.id, 1)} disabled={closed}>
                    +
                  </button>
                </div>
              </div>
            );
          })}
        </div>

        <div className="card" style={{ alignSelf: "start", position: "sticky", top: 84 }}>
          <h2>Giỏ đặt</h2>
          {msg && <div className={`alert ${msg.type}`}>{msg.text}</div>}
          {detail.my_order && (
            <p className="small muted">Bạn đã đặt đợt này — sửa lại sẽ thay thế đơn cũ.</p>
          )}

          {Object.keys(cart).length === 0 ? (
            <p className="muted">Chưa chọn món nào.</p>
          ) : (
            <div className="grid" style={{ gap: 10 }}>
              {detail.menu_items
                .filter((m) => cart[m.id])
                .map((m) => (
                  <div
                    key={m.id}
                    style={{ borderBottom: "1px solid var(--border)", paddingBottom: 10 }}
                  >
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
                      onChange={(e) =>
                        setItemNotes((n) => ({ ...n, [m.id]: e.target.value }))
                      }
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
          <button className="mt" style={{ width: "100%" }} onClick={submit} disabled={busy || closed}>
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

  const load = () => {
    setLoading(true);
    api.myOrders().then((r) => setOrders(r.data)).finally(() => setLoading(false));
  };
  useEffect(load, []);

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
        <div key={o.id} className="card">
          <div className="row between wrap">
            <div>
              <strong>{o.group_order?.title || o.order_date}</strong>{" "}
              <StatusBadge status={o.status} />
              {o.group_order?.category && (
                <span className="badge admin" style={{ marginLeft: 6 }}>
                  {o.group_order.category.name}
                </span>
              )}
              <div className="small muted">📅 {o.order_date}</div>
            </div>
            <div className="row">
              <strong>{formatVND(o.total_amount)}</strong>
              {o.status === "pending" && (
                <button className="danger small" onClick={() => cancel(o.id)}>
                  Hủy
                </button>
              )}
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

  return (
    <div className="grid">
      <div className="stat" style={{ maxWidth: 320 }}>
        <p className="label">Số dư quỹ hiện tại</p>
        <div className="value" style={{ color: "var(--primary)" }}>
          {formatVND(balance)}
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
              {txs.map((t) => (
                <tr key={t.id}>
                  <td className="small muted">
                    {new Date(t.inserted_at).toLocaleString("vi-VN")}
                  </td>
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
    </div>
  );
}
