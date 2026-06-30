import { useState, type ReactNode } from "react";
import { useAuth } from "./auth";
import { api, formatVND } from "./api";

export function Header({ subtitle }: { subtitle?: string }) {
  const { user, logout } = useAuth();
  const [profileOpen, setProfileOpen] = useState(false);
  return (
    <header className="app-header">
      <div className="brand">
        🍜 Food Street{" "}
        {subtitle && (
          <span className="muted small" style={{ fontWeight: 500 }}>
            · {subtitle}
          </span>
        )}
      </div>
      <div className="header-user">
        <button className="ghost" onClick={() => setProfileOpen(true)} title="Tài khoản">
          {user?.name}{" "}
          <span className={`badge ${user?.role}`}>{user?.role}</span>
        </button>
        <button className="ghost" onClick={logout}>
          Đăng xuất
        </button>
      </div>
      {profileOpen && <ProfileModal onClose={() => setProfileOpen(false)} />}
    </header>
  );
}

function ProfileModal({ onClose }: { onClose: () => void }) {
  const { user, refresh } = useAuth();
  const [name, setName] = useState(user?.name || "");
  const [cur, setCur] = useState("");
  const [pw1, setPw1] = useState("");
  const [pw2, setPw2] = useState("");
  const [msg, setMsg] = useState<{ type: "error" | "success"; text: string } | null>(null);
  const [busy, setBusy] = useState(false);

  const saveName = async (e: React.FormEvent) => {
    e.preventDefault();
    setMsg(null);
    setBusy(true);
    try {
      await api.updateProfile(name.trim());
      await refresh();
      setMsg({ type: "success", text: "Đã đổi tên" });
    } catch (err: any) {
      setMsg({ type: "error", text: err.message || "Đổi tên thất bại" });
    } finally {
      setBusy(false);
    }
  };

  const savePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setMsg(null);
    if (pw1 !== pw2) {
      setMsg({ type: "error", text: "Mật khẩu mới nhập lại không khớp" });
      return;
    }
    setBusy(true);
    try {
      await api.changePassword(cur, pw1);
      setCur("");
      setPw1("");
      setPw2("");
      setMsg({ type: "success", text: "Đổi mật khẩu thành công" });
    } catch (err: any) {
      setMsg({ type: "error", text: err.message || "Đổi mật khẩu thất bại" });
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title="Tài khoản" onClose={onClose}>
      {msg && <div className={`alert ${msg.type}`}>{msg.text}</div>}

      <div className="field">
        <label>Tên đăng nhập</label>
        <input value={user?.username || ""} disabled />
      </div>

      <form onSubmit={saveName}>
        <div className="field">
          <label>Tên hiển thị</label>
          <input value={name} onChange={(e) => setName(e.target.value)} required />
        </div>
        <button type="submit" disabled={busy} className="small">
          Lưu tên
        </button>
      </form>

      <hr style={{ border: "none", borderTop: "1px solid var(--border)", margin: "18px 0" }} />

      <form onSubmit={savePassword}>
        <h3 style={{ margin: "0 0 10px" }}>Đổi mật khẩu</h3>
        <div className="field">
          <label>Mật khẩu hiện tại</label>
          <input type="password" value={cur} onChange={(e) => setCur(e.target.value)} required />
        </div>
        <div className="field">
          <label>Mật khẩu mới</label>
          <input
            type="password"
            value={pw1}
            onChange={(e) => setPw1(e.target.value)}
            required
            minLength={6}
          />
        </div>
        <div className="field">
          <label>Nhập lại mật khẩu mới</label>
          <input
            type="password"
            value={pw2}
            onChange={(e) => setPw2(e.target.value)}
            required
            minLength={6}
          />
        </div>
        <button type="submit" disabled={busy} className="small">
          Đổi mật khẩu
        </button>
      </form>
    </Modal>
  );
}

export function Modal({
  title,
  children,
  onClose,
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
}) {
  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="row between mb">
          <h2 style={{ margin: 0 }}>{title}</h2>
          <button className="ghost" onClick={onClose}>
            ✕
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

export function StatusBadge({ status }: { status: string }) {
  const labels: Record<string, string> = {
    pending: "Chờ chốt",
    confirmed: "Đã chốt",
    cancelled: "Đã hủy",
  };
  return <span className={`badge ${status}`}>{labels[status] || status}</span>;
}

export function Money({ value, sign }: { value: string; sign?: boolean }) {
  const n = parseFloat(value);
  const color = n < 0 ? "var(--danger)" : n > 0 && sign ? "var(--success)" : undefined;
  return (
    <span style={{ color, fontWeight: 600 }}>
      {sign && n > 0 ? "+" : ""}
      {formatVND(value)}
    </span>
  );
}
