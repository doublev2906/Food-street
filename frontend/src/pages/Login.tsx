import { useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { useAuth } from "../auth";

// Mốc lần cuối tự quay lại /share — chặn vòng lặp /share -> /login -> /share nếu
// trình duyệt không lưu được cookie fs_share.
const SHARE_REDIRECT_KEY = "share_redirect_at";

export default function Login() {
  const { login, user } = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const nextParam = searchParams.get("next");
  const next = nextParam ? decodeURIComponent(nextParam) : null;
  // /share/* do Caddy serve (không phải route React) -> phải tải lại cả trang.
  const shareNext = next?.startsWith("/share/") ? next : null;

  // Đã đăng nhập sẵn (AuthProvider gọi /me -> đã gắn cookie) mà bị đẩy về đây từ
  // /share -> quay lại luôn, khỏi bắt nhập lại mật khẩu.
  useEffect(() => {
    if (!user || !shareNext) return;
    const last = Number(sessionStorage.getItem(SHARE_REDIRECT_KEY) || 0);
    if (Date.now() - last < 5000) {
      setError("Không mở được trang chia sẻ: trình duyệt đang chặn cookie của trang này.");
      return;
    }
    sessionStorage.setItem(SHARE_REDIRECT_KEY, String(Date.now()));
    window.location.replace(shareNext);
  }, [user, shareNext]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setBusy(true);
    try {
      await login(username.trim(), password);
      // Về /share/*: useEffect phía trên tự chuyển trang ngay khi có user.
      if (shareNext) return;
      // Quay lại đường dẫn deep-link (nếu có, vd /app?group=…), mặc định /app.
      navigate(next ?? "/app", { replace: true });
    } catch (err: any) {
      setError(err.message || "Đăng nhập thất bại");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="login-wrap">
      <div className="card login-card">
        <div className="brand">🍜 Food Street</div>
        <p className="muted small" style={{ textAlign: "center", marginTop: 0 }}>
          Hệ thống đặt đồ ăn sáng
        </p>

        {error && <div className="alert error">{error}</div>}

        <form onSubmit={submit}>
          <div className="field">
            <label htmlFor="username">Tên đăng nhập</label>
            <input
              id="username"
              name="username"
              type="text"
              autoComplete="username"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="VD: an (hoặc email)"
              required
              autoFocus
            />
          </div>
          <div className="field">
            <label htmlFor="password">Mật khẩu</label>
            <input
              id="password"
              name="password"
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••"
              required
            />
          </div>
          <button type="submit" disabled={busy} style={{ width: "100%" }}>
            {busy ? "Đang đăng nhập…" : "Đăng nhập"}
          </button>
        </form>
      </div>
    </div>
  );
}
