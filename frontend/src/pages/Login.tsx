import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../auth";

export default function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setBusy(true);
    try {
      const user = await login(email.trim(), password);
      navigate(user.role === "admin" ? "/admin" : "/app", { replace: true });
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
            <label>Email</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="email@foodstreet.vn"
              required
              autoFocus
            />
          </div>
          <div className="field">
            <label>Mật khẩu</label>
            <input
              type="password"
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

        <div
          className="small muted"
          style={{ marginTop: 18, padding: 12, background: "var(--bg)", borderRadius: 8 }}
        >
          <strong>Tài khoản demo:</strong>
          <br />
          Admin: admin@foodstreet.vn / admin123
          <br />
          User: an@foodstreet.vn / user123
        </div>
      </div>
    </div>
  );
}
