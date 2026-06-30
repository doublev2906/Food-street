import { useEffect, useMemo, useState } from "react";
import {
  api,
  formatVND,
  today,
  type FundTransaction,
  type MenuItem,
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
            🥢 Đặt món
          </button>
          <button className={`tab ${tab === "orders" ? "active" : ""}`} onClick={() => setTab("orders")}>
            📋 Đơn của tôi
          </button>
          <button className={`tab ${tab === "fund" ? "active" : ""}`} onClick={() => setTab("fund")}>
            💰 Quỹ của tôi
          </button>
        </div>

        {tab === "order" && <OrderTab onPlaced={() => setTab("orders")} />}
        {tab === "orders" && <MyOrdersTab />}
        {tab === "fund" && <FundTab />}
      </div>
    </>
  );
}

// ---------- Đặt món ----------
function OrderTab({ onPlaced }: { onPlaced: () => void }) {
  const [menu, setMenu] = useState<MenuItem[]>([]);
  const [cart, setCart] = useState<Record<string, number>>({});
  const [date, setDate] = useState(today());
  const [note, setNote] = useState("");
  const [msg, setMsg] = useState<{ type: "error" | "success"; text: string } | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api.menu().then((r) => setMenu(r.data)).catch(() => {});
  }, []);

  const setQty = (id: string, delta: number) =>
    setCart((c) => {
      const q = (c[id] || 0) + delta;
      const next = { ...c };
      if (q <= 0) delete next[id];
      else next[id] = q;
      return next;
    });

  const total = useMemo(
    () =>
      menu.reduce((sum, m) => sum + (cart[m.id] || 0) * parseFloat(m.price), 0),
    [cart, menu]
  );

  const itemCount = Object.values(cart).reduce((a, b) => a + b, 0);

  const submit = async () => {
    setMsg(null);
    const items = Object.entries(cart).map(([menu_item_id, quantity]) => ({
      menu_item_id,
      quantity,
    }));
    if (items.length === 0) {
      setMsg({ type: "error", text: "Hãy chọn ít nhất 1 món" });
      return;
    }
    setBusy(true);
    try {
      await api.placeOrder({ order_date: date, note, items });
      setMsg({ type: "success", text: "Đặt món thành công!" });
      setCart({});
      setNote("");
      setTimeout(onPlaced, 600);
    } catch (e: any) {
      setMsg({ type: "error", text: e.message || "Đặt món thất bại" });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="grid grid-2">
      <div className="card">
        <h2>Thực đơn</h2>
        {menu.length === 0 && <p className="muted">Chưa có món nào.</p>}
        {menu.map((m) => {
          const q = cart[m.id] || 0;
          return (
            <div key={m.id} className={`menu-item ${q > 0 ? "selected" : ""}`}>
              <div>
                <strong>{m.name}</strong>
                <div className="small muted">{m.description}</div>
                <div className="small">{formatVND(m.price)}</div>
              </div>
              <div className="qty">
                <button onClick={() => setQty(m.id, -1)} disabled={q === 0}>
                  −
                </button>
                <span>{q}</span>
                <button onClick={() => setQty(m.id, 1)}>+</button>
              </div>
            </div>
          );
        })}
      </div>

      <div className="card" style={{ alignSelf: "start", position: "sticky", top: 84 }}>
        <h2>Giỏ đặt</h2>
        {msg && <div className={`alert ${msg.type}`}>{msg.text}</div>}

        <div className="field">
          <label>Ngày đặt</label>
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </div>

        {itemCount === 0 ? (
          <p className="muted">Chưa chọn món nào.</p>
        ) : (
          <table>
            <tbody>
              {menu
                .filter((m) => cart[m.id])
                .map((m) => (
                  <tr key={m.id}>
                    <td>{m.name}</td>
                    <td className="muted">×{cart[m.id]}</td>
                    <td style={{ textAlign: "right" }}>
                      {formatVND(parseFloat(m.price) * cart[m.id])}
                    </td>
                  </tr>
                ))}
            </tbody>
          </table>
        )}

        <div className="field mt">
          <label>Ghi chú</label>
          <textarea
            rows={2}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="VD: ít cay, không hành…"
          />
        </div>

        <div className="row between mt">
          <strong>Tổng cộng</strong>
          <strong style={{ fontSize: 18, color: "var(--primary)" }}>
            {formatVND(total)}
          </strong>
        </div>
        <button className="mt" style={{ width: "100%" }} onClick={submit} disabled={busy}>
          {busy ? "Đang gửi…" : "Đặt món"}
        </button>
        <p className="small muted mt">
          Nếu bạn đã đặt trong ngày này, đơn cũ (chưa chốt) sẽ được thay thế.
        </p>
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
  if (orders.length === 0)
    return <div className="card muted">Bạn chưa có đơn nào.</div>;

  return (
    <div className="grid">
      {orders.map((o) => (
        <div key={o.id} className="card">
          <div className="row between wrap">
            <div>
              <strong>{o.order_date}</strong> <StatusBadge status={o.status} />
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
