import { useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "./auth";
import { api, formatVND } from "./api";

// Các màu chủ đạo user chọn được (cam mặc định)
const ACCENTS = [
  { key: "orange", icon: "🍊", label: "Cam" },
  { key: "green", icon: "☘️", label: "Rau má" },
  { key: "blue", icon: "💧", label: "Sky" },
  { key: "lychee", icon: "🍒", label: "Vải thiều" },
  { key: "namdinh", icon: "✌️", label: "2 ngón" },
] as const;

// Con trỏ chuột user chọn được (mèo popcat mặc định)
const CURSORS = [
  { key: "cat", icon: "🐱", label: "Mèo" },
  { key: "sakura", icon: "🌸", label: "Quạt hoa đào" },
  { key: "default", icon: "🖱️", label: "Mặc định" },
] as const;

export function Header({ subtitle }: { subtitle?: string }) {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [profileOpen, setProfileOpen] = useState(false);
  // Theme đã được set sớm trên <html> bởi script inline trong index.html
  const [theme, setTheme] = useState(() => document.documentElement.dataset.theme || "light");
  const [accent, setAccent] = useState(() => document.documentElement.dataset.accent || "orange");
  const [accentOpen, setAccentOpen] = useState(false);
  const [cursor, setCursor] = useState(() => document.documentElement.dataset.cursor || "cat");
  const [cursorOpen, setCursorOpen] = useState(false);
  // Grace period khi rời chuột: không đóng phụp ngay, lỡ trớn còn kịp quay lại
  const accentTimer = useRef<number | null>(null);
  const cursorTimer = useRef<number | null>(null);

  const openAccent = () => {
    if (accentTimer.current) window.clearTimeout(accentTimer.current);
    setAccentOpen(true);
  };
  const closeAccentSoon = () => {
    if (accentTimer.current) window.clearTimeout(accentTimer.current);
    accentTimer.current = window.setTimeout(() => setAccentOpen(false), 300);
  };
  const openCursor = () => {
    if (cursorTimer.current) window.clearTimeout(cursorTimer.current);
    setCursorOpen(true);
  };
  const closeCursorSoon = () => {
    if (cursorTimer.current) window.clearTimeout(cursorTimer.current);
    cursorTimer.current = window.setTimeout(() => setCursorOpen(false), 300);
  };
  useEffect(
    () => () => {
      if (accentTimer.current) window.clearTimeout(accentTimer.current);
      if (cursorTimer.current) window.clearTimeout(cursorTimer.current);
    },
    []
  );

  const isAdmin = user?.role === "admin";
  const onAdminPage = location.pathname.startsWith("/admin");

  // 3 giao diện xoay vòng: sáng -> tối -> anime -> sáng
  const THEME_CYCLE: Record<string, string> = { light: "dark", dark: "anime", anime: "light" };
  const THEME_ICON: Record<string, string> = { light: "☀️", dark: "🌙", anime: "🌸" };
  const toggleTheme = () => {
    const next = THEME_CYCLE[theme] ?? "light";
    document.documentElement.dataset.theme = next;
    // Cập nhật lại buổi cho nền anime (index.html chỉ set lúc load trang)
    const h = new Date().getHours();
    document.documentElement.dataset.animeTime = h >= 18 || h < 6 ? "night" : h >= 14 ? "sunset" : "day";
    localStorage.setItem("theme", next);
    setTheme(next);
    // Sang anime thì đóng menu màu đang mở (picker màu bị disable ở theme này)
    if (next === "anime") setAccentOpen(false);
  };

  // Theme anime dùng palette sakura riêng, CSS anime đè mọi accent -> chọn màu
  // không có tác dụng, disable picker cho đỡ gây hiểu nhầm.
  const accentDisabled = theme === "anime";

  const pickAccent = (key: string) => {
    if (key === "orange") {
      // Cam là mặc định trong :root -> gỡ attribute thay vì set
      delete document.documentElement.dataset.accent;
      localStorage.removeItem("accent");
    } else {
      document.documentElement.dataset.accent = key;
      localStorage.setItem("accent", key);
    }
    setAccent(key);
    setAccentOpen(false);
  };

  const pickCursor = (key: string) => {
    document.documentElement.dataset.cursor = key;
    localStorage.setItem("cursor", key);
    setCursor(key);
    setCursorOpen(false);
  };

  // Bấm logo -> về tab đầu của khu đang đứng: admin ở nguyên /admin, user về /app.
  // navigate không kèm query nên ?tab bị xoá -> useTabParam tự rơi về tab đầu.
  const goHome = () => {
    navigate(onAdminPage ? "/admin" : "/app");
  };

  return (
    <header className="app-header">
      <div className="brand" onClick={goHome} title="Về trang đặt món">
        <span className="brand-logo">🍜</span>
        <span className="brand-name">
          Food <span className="brand-accent">Street</span>
        </span>
        {subtitle && <span className="brand-sub">{subtitle}</span>}
      </div>
      <div className="header-user">
        {/* Nhóm 1: điều hướng admin | Nhóm 2: tài khoản | Nhóm 3: theme + thoát */}
        {isAdmin && (
          <>
            {onAdminPage ? (
              <button className="secondary small" onClick={() => navigate("/app")}>
                ← Trang đặt món
              </button>
            ) : (
              <button className="secondary small" onClick={() => navigate("/admin")}>
                🛠️ Trang quản trị
              </button>
            )}
            <span className="header-sep" />
          </>
        )}
        {/* Badge role để ngoài nút: hover Tài khoản chỉ phủ avatar + tên */}
        <button className="ghost user-chip" onClick={() => setProfileOpen(true)} title="Tài khoản">
          <span className="avatar">{(user?.name || "?").charAt(0).toUpperCase()}</span>
          <span className="user-chip-name">{user?.name}</span>
        </button>
        <span className={`badge ${user?.role}`}>
          {user?.role === "admin" ? "Quản trị" : "Thành viên"}
        </span>
        <span className="header-sep" />
        {/* Hover (hoặc bấm - cho mobile) để mở dropdown chọn màu chủ đạo */}
        <div
          className="accent-picker"
          onMouseEnter={accentDisabled ? undefined : openAccent}
          onMouseLeave={closeAccentSoon}
        >
          <button
            className="ghost icon-btn"
            onClick={() => setAccentOpen((o) => !o)}
            disabled={accentDisabled}
            title={
              accentDisabled
                ? "Theme anime dùng bảng màu sakura riêng — về giao diện sáng/tối để chọn màu"
                : "Chọn màu giao diện"
            }
          >
            {ACCENTS.find((a) => a.key === accent)?.icon}
          </button>
          {accentOpen && (
            <div className="accent-menu">
              {ACCENTS.map((a) => (
                <button
                  key={a.key}
                  className={`accent-item ${a.key === accent ? "active" : ""}`}
                  onClick={() => pickAccent(a.key)}
                >
                  <span className="accent-item-ic">{a.icon}</span>
                  {a.label}
                  {a.key === accent && <span className="accent-check">✓</span>}
                </button>
              ))}
            </div>
          )}
        </div>
        {/* Hover (hoặc bấm - cho mobile) để mở dropdown chọn con trỏ chuột */}
        <div className="accent-picker" onMouseEnter={openCursor} onMouseLeave={closeCursorSoon}>
          <button
            className="ghost icon-btn"
            onClick={() => setCursorOpen((o) => !o)}
            title="Chọn con trỏ chuột"
          >
            {CURSORS.find((c) => c.key === cursor)?.icon}
          </button>
          {cursorOpen && (
            <div className="accent-menu">
              {CURSORS.map((c) => (
                <button
                  key={c.key}
                  className={`accent-item ${c.key === cursor ? "active" : ""}`}
                  onClick={() => pickCursor(c.key)}
                >
                  <span className="accent-item-ic">{c.icon}</span>
                  {c.label}
                  {c.key === cursor && <span className="accent-check">✓</span>}
                </button>
              ))}
            </div>
          )}
        </div>
        <button
          className="ghost icon-btn"
          onClick={toggleTheme}
          title="Đổi giao diện (sáng / tối / anime)"
        >
          {THEME_ICON[theme] ?? "☀️"}
        </button>
        <button className="ghost logout-btn" onClick={logout} title="Đăng xuất">
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
  // Portal ra body: modal có thể được mở từ trong header (có backdrop-filter),
  // backdrop-filter biến ancestor thành containing block của position:fixed
  // -> overlay bị nhốt trong header và trôi lên trên nếu không portal.
  return createPortal(
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
    </div>,
    document.body
  );
}

// ---- Loading theo theme đồ ăn: bát mì đổi món + hơi nước + câu chờ vui ----
const LOADING_EMOJIS = ["🍜", "🍲", "🥘", "🍳", "🥟", "🍚", "🧋", "🍢"];
const LOADING_TEXTS = [
  "Đang bưng món ra…",
  "Bếp đang đỏ lửa…",
  "Món ngon sắp lên…",
  "Đang xếp bát đũa…",
  "Đang nêm nếm chút xíu…",
];

export function Spinner({ label, full }: { label?: string; full?: boolean }) {
  const [idx, setIdx] = useState(() => Math.floor(Math.random() * LOADING_EMOJIS.length));
  // Chốt câu chờ 1 lần lúc mount để không nhảy chữ loạn xạ
  const [text] = useState(
    () => label || LOADING_TEXTS[Math.floor(Math.random() * LOADING_TEXTS.length)]
  );

  useEffect(() => {
    const timer = setInterval(() => setIdx((v) => v + 1), 500);
    return () => clearInterval(timer);
  }, []);

  return (
    <div className={`loading ${full ? "full" : ""}`} role="status" aria-label={text}>
      <div className="loading-steam">
        <span />
        <span />
        <span />
      </div>
      <div className="loading-bowl">{LOADING_EMOJIS[idx % LOADING_EMOJIS.length]}</div>
      <div className="loading-text">
        {text.replace(/…$/, "")}
        <span className="loading-dots">
          <span>.</span>
          <span>.</span>
          <span>.</span>
        </span>
      </div>
    </div>
  );
}

export function StatusBadge({ status }: { status: string }) {
  const labels: Record<string, string> = {
    pending: "Chờ chốt",
    confirmed: "Đã chốt",
    cancelled: "Đã hủy",
    // Trạng thái đợt đặt nhóm
    open: "Đang mở",
    closed: "Đã đóng",
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
