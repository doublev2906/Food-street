import type { ReactNode } from "react";
import { useAuth } from "./auth";
import { formatVND } from "./api";

export function Header({ subtitle }: { subtitle?: string }) {
  const { user, logout } = useAuth();
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
        <span>
          {user?.name}{" "}
          <span className={`badge ${user?.role}`}>{user?.role}</span>
        </span>
        <button className="ghost" onClick={logout}>
          Đăng xuất
        </button>
      </div>
    </header>
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
