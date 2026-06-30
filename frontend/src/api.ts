// API client cho hệ thống đặt đồ ăn sáng.
const BASE = import.meta.env.VITE_API_URL || "http://localhost:4003/api";

// ---- Types ----
export type Role = "user" | "admin";

export interface User {
  id: string;
  name: string;
  email: string;
  role: Role;
  balance: string;
  active: boolean;
  inserted_at?: string;
}

export interface Category {
  id: string;
  name: string;
  description: string | null;
  active: boolean;
}

export interface MenuItem {
  id: string;
  name: string;
  description: string | null;
  price: string;
  available: boolean;
  category_id: string | null;
  category?: Category | null;
}

export interface OrderItem {
  id?: string;
  menu_item_id: string;
  item_name: string;
  quantity: number;
  unit_price: string;
  subtotal: string;
}

export interface Order {
  id: string;
  user_id: string;
  group_order_id: string | null;
  order_date: string;
  status: "pending" | "confirmed" | "cancelled";
  total_amount: string;
  note: string | null;
  confirmed_at: string | null;
  inserted_at: string;
  items: OrderItem[];
  user?: { id: string; name: string; email: string } | null;
  group_order?: GroupOrder | null;
}

export interface GroupOrder {
  id: string;
  title: string;
  order_date: string;
  status: "open" | "closed" | "cancelled";
  note: string | null;
  deadline: string | null;
  closed_at?: string | null;
  category_id?: string | null;
  category?: Category | null;
  orders?: Order[];
  order_count?: number;
  total_amount?: string;
}

export interface GroupOrderDetail {
  group_order: GroupOrder;
  menu_items: MenuItem[];
  my_order: Order | null;
}

export interface FundTransaction {
  id: string;
  user_id: string;
  amount: string;
  type: "deposit" | "order" | "adjustment";
  description: string | null;
  balance_after: string;
  order_id: string | null;
  inserted_at: string;
  user?: { name: string };
}

export interface Stats {
  date: string;
  total_users: number;
  active_users: number;
  fund_total: string;
  orders_today: number;
  pending_today: number;
  confirmed_today: number;
  revenue_today: string;
  top_items: { item_name: string; quantity: number; revenue: string }[];
}

export class ApiError extends Error {
  status: number;
  body: any;
  constructor(status: number, body: any) {
    super(body?.message || body?.error || `HTTP ${status}`);
    this.status = status;
    this.body = body;
  }
}

const TOKEN_KEY = "fs_token";

export const tokenStore = {
  get: () => localStorage.getItem(TOKEN_KEY),
  set: (t: string) => localStorage.setItem(TOKEN_KEY, t),
  clear: () => localStorage.removeItem(TOKEN_KEY),
};

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = tokenStore.get();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(options.headers as Record<string, string>),
  };
  if (token) headers["Authorization"] = `Bearer ${token}`;

  const res = await fetch(`${BASE}${path}`, { ...options, headers });
  if (res.status === 204) return undefined as T;

  const text = await res.text();
  const body = text ? JSON.parse(text) : null;
  if (!res.ok) {
    if (res.status === 401) tokenStore.clear();
    throw new ApiError(res.status, body);
  }
  return body as T;
}

export const api = {
  login: (email: string, password: string) =>
    request<{ token: string; user: User }>("/login", {
      method: "POST",
      body: JSON.stringify({ email, password }),
    }),

  me: () => request<{ user: User }>("/me"),

  // ---- User ----
  menu: () => request<{ data: MenuItem[] }>("/menu"),
  myOrders: () => request<{ data: Order[] }>("/orders"),
  cancelOrder: (id: string) =>
    request<{ data: Order }>(`/orders/${id}`, { method: "DELETE" }),
  balance: () =>
    request<{ balance: string; user_id: string; name: string }>("/fund/balance"),
  myTransactions: () => request<{ data: FundTransaction[] }>("/fund/transactions"),

  // Đợt đặt nhóm (user)
  openGroupOrders: () => request<{ data: GroupOrder[] }>("/group_orders"),
  groupOrder: (id: string) =>
    request<{ data: GroupOrderDetail }>(`/group_orders/${id}`),
  orderInGroup: (
    id: string,
    payload: { note?: string; items: { menu_item_id: string; quantity: number }[] }
  ) =>
    request<{ data: Order }>(`/group_orders/${id}/order`, {
      method: "POST",
      body: JSON.stringify(payload),
    }),

  // ---- Admin ----
  admin: {
    users: () => request<{ data: User[] }>("/admin/users"),
    createUser: (payload: Partial<User> & { password: string }) =>
      request<{ data: User }>("/admin/users", {
        method: "POST",
        body: JSON.stringify(payload),
      }),
    updateUser: (id: string, payload: Partial<User> & { password?: string }) =>
      request<{ data: User }>(`/admin/users/${id}`, {
        method: "PUT",
        body: JSON.stringify(payload),
      }),
    deleteUser: (id: string) =>
      request<void>(`/admin/users/${id}`, { method: "DELETE" }),

    menu: () => request<{ data: MenuItem[] }>("/admin/menu"),
    createMenu: (payload: Partial<MenuItem>) =>
      request<{ data: MenuItem }>("/admin/menu", {
        method: "POST",
        body: JSON.stringify(payload),
      }),
    updateMenu: (id: string, payload: Partial<MenuItem>) =>
      request<{ data: MenuItem }>(`/admin/menu/${id}`, {
        method: "PUT",
        body: JSON.stringify(payload),
      }),
    deleteMenu: (id: string) =>
      request<void>(`/admin/menu/${id}`, { method: "DELETE" }),

    // Danh mục
    categories: () => request<{ data: Category[] }>("/admin/categories"),
    createCategory: (payload: Partial<Category>) =>
      request<{ data: Category }>("/admin/categories", {
        method: "POST",
        body: JSON.stringify(payload),
      }),
    updateCategory: (id: string, payload: Partial<Category>) =>
      request<{ data: Category }>(`/admin/categories/${id}`, {
        method: "PUT",
        body: JSON.stringify(payload),
      }),
    deleteCategory: (id: string) =>
      request<void>(`/admin/categories/${id}`, { method: "DELETE" }),

    // Đợt đặt nhóm
    groupOrders: (status?: string) =>
      request<{ data: GroupOrder[] }>(
        `/admin/group_orders${status ? `?status=${status}` : ""}`
      ),
    groupOrder: (id: string) =>
      request<{ data: GroupOrder }>(`/admin/group_orders/${id}`),
    createGroupOrder: (payload: {
      title: string;
      order_date: string;
      category_id: string;
      note?: string;
      deadline?: string;
    }) =>
      request<{ data: GroupOrder }>("/admin/group_orders", {
        method: "POST",
        body: JSON.stringify(payload),
      }),
    updateGroupOrder: (id: string, payload: Partial<GroupOrder>) =>
      request<{ data: GroupOrder }>(`/admin/group_orders/${id}`, {
        method: "PUT",
        body: JSON.stringify(payload),
      }),
    deleteGroupOrder: (id: string) =>
      request<void>(`/admin/group_orders/${id}`, { method: "DELETE" }),
    closeGroupOrder: (id: string) =>
      request<{ data: { confirmed: number; group_order: GroupOrder } }>(
        `/admin/group_orders/${id}/close`,
        { method: "POST" }
      ),

    stats: (date?: string) =>
      request<{ data: Stats }>(`/admin/stats${date ? `?date=${date}` : ""}`),
    fundTransactions: () =>
      request<{ data: FundTransaction[] }>("/admin/fund/transactions"),
    deposit: (user_id: string, amount: string, description?: string) =>
      request<{ data: any }>("/admin/fund/deposit", {
        method: "POST",
        body: JSON.stringify({ user_id, amount, description }),
      }),
    adjust: (user_id: string, amount: string, description?: string) =>
      request<{ data: any }>("/admin/fund/adjust", {
        method: "POST",
        body: JSON.stringify({ user_id, amount, description }),
      }),
  },
};

// ---- Helpers ----
export function formatVND(value: string | number): string {
  const n = typeof value === "string" ? parseFloat(value) : value;
  return new Intl.NumberFormat("vi-VN", {
    style: "currency",
    currency: "VND",
    maximumFractionDigits: 0,
  }).format(n);
}

export function today(): string {
  return new Date().toISOString().slice(0, 10);
}
