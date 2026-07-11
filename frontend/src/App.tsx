import { Navigate, Route, Routes, useLocation } from "react-router-dom";
import { useAuth } from "./auth";
import { Spinner } from "./components";
import Login from "./pages/Login";
import UserDashboard from "./pages/UserDashboard";
import AdminDashboard from "./pages/AdminDashboard";
import type { ReactNode } from "react";

function Protected({
  children,
  role,
}: {
  children: ReactNode;
  role?: "admin" | "user";
}) {
  const { user, loading } = useAuth();
  const location = useLocation();
  if (loading) return <Spinner full />;
  if (!user) {
    // Giữ lại đường dẫn hiện tại (kèm ?group=…) để sau khi đăng nhập quay lại.
    const next = encodeURIComponent(location.pathname + location.search);
    return <Navigate to={`/login?next=${next}`} replace />;
  }
  if (role && user.role !== role) {
    return <Navigate to={user.role === "admin" ? "/admin" : "/app"} replace />;
  }
  return <>{children}</>;
}

function Home() {
  const { user, loading } = useAuth();
  const location = useLocation();
  if (loading) return <Spinner full />;
  if (!user) return <Navigate to="/login" replace />;
  // Mọi người (kể cả admin) mặc định vào trang đặt món; giữ ?group=… nếu có.
  return <Navigate to={`/app${location.search}`} replace />;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        path="/app"
        element={
          <Protected>
            <UserDashboard />
          </Protected>
        }
      />
      <Route
        path="/admin"
        element={
          <Protected role="admin">
            <AdminDashboard />
          </Protected>
        }
      />
      <Route path="/" element={<Home />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
