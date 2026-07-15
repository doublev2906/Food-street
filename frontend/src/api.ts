// API client cho hệ thống đặt đồ ăn sáng.
const BASE = import.meta.env.VITE_API_URL || "http://localhost:4003/api";

// ---- Types ----
export type Role = "user" | "admin";

export interface User {
  id: string;
  name: string;
  username: string;
  email: string;
  role: Role;
  balance: string;
  /** Nợ lãi trên số dư âm (issue #12) — tách khỏi balance; nạp tiền trừ khoản này trước. */
  interest_debt?: string;
  active: boolean;
  /** UUID user Panchat — để mention thật (@Tên) khi báo số dư. */
  panchat_user_id?: string | null;
  inserted_at?: string;
}

export interface Category {
  id: string;
  name: string;
  description: string | null;
  active: boolean;
  // Cấu hình Pancake Page của nhà bán (chỉ trả về ở API admin).
  pancake_page_id?: string | null;
  pancake_conversation_id?: string | null;
  pancake_configured?: boolean;
  // Chỉ dùng khi submit form (write-only) — không bao giờ trả về từ API.
  pancake_page_access_token?: string;
}

export interface MenuItem {
  id: string;
  name: string;
  description: string | null;
  price: string;
  available: boolean;
  image_url: string | null;
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
  note?: string | null;
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
  runner_count?: number;
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
  type: "deposit" | "order" | "adjustment" | "split";
  description: string | null;
  balance_after: string;
  order_id: string | null;
  inserted_at: string;
  user?: { name: string };
}

// Quỹ lãi trên số dư âm (issue #12).
export interface InterestFund {
  /** Tổng lãi đã cộng dồn (accrual). */
  fund_total: string;
  /** Lãi đã thu thực (đã trả qua nạp tiền) = accrual − còn nợ. */
  collected_total: string;
  /** Nợ lãi các user còn phải trả. */
  outstanding_interest: string;
  /** Lãi cộng dồn hôm nay. */
  today_total: string;
  charge_count: number;
  /** Số người đang âm số dư gốc + tổng dư nợ gốc (âm). */
  debtor_count: number;
  outstanding_debt: string;
  /** Ngày (VN) job tính lãi chạy gần nhất, hoặc null. */
  last_run_on: string | null;
  annual_rate_percent: string;
  daily_rate_percent: string;
  min_daily_interest: string;
}

// Tình trạng nợ (gốc + lãi) của chính user — cho user tự xem.
export interface InterestStatus {
  balance: string;
  /** Nợ lãi hiện có. */
  interest_debt: string;
  /** Dư nợ gốc (|số dư âm|, 0 nếu số dư ≥ 0). */
  principal_debt: string;
  /** Tổng đang nợ = nợ gốc + nợ lãi. */
  total_owed: string;
  /** Lãi ước tính bị cộng cho ngày kế tiếp nếu vẫn nợ. */
  estimated_daily_interest: string;
  annual_rate_percent: string;
  daily_rate_percent: string;
  min_daily_interest: string;
}

// 1 lần tính lãi (sổ cái quỹ lãi).
export interface InterestCharge {
  id: string;
  user_id: string;
  amount: string;
  base_amount: string;
  interest_debt_after: string;
  charged_on: string;
  inserted_at: string;
  user?: { id: string; name: string } | null;
}

export interface Stats {
  date: string;
  total_users: number;
  active_users: number;
  fund_total: string;
  fund_deposited: string;
  fund_spent: string;
  fund_adjusted: string;
  negative_count: number;
  negative_debt: string;
  orders_today: number;
  pending_today: number;
  confirmed_today: number;
  revenue_today: string;
  top_items: { item_name: string; quantity: number; revenue: string }[];
}

// Thống kê theo khoảng ngày (ngày / tháng / năm).
export interface PeriodStats {
  from: string;
  to: string;
  orders: number;
  pending: number;
  confirmed: number;
  revenue: string;
  fund_total: string;
  fund_deposited: string;
  fund_spent: string;
  fund_adjusted: string;
  negative_count: number;
  negative_debt: string;
  top_items: { item_name: string; quantity: number; revenue: string }[];
}

// Doanh thu theo từng ngày (chuỗi thời gian để vẽ biểu đồ).
export interface DailyRevenue {
  date: string;
  revenue: string;
  orders: number;
}

// Doanh thu theo từng danh mục trong kỳ.
export interface CategoryRevenue {
  category_id: string;
  category_name: string;
  revenue: string;
  orders: number;
}

export interface Paginated<T> {
  data: T[];
  page: number;
  page_size: number;
  total: number;
  total_pages: number;
}

export interface PanchatSettings {
  panchat_configured: boolean;
  panchat_token_preview: string;
}

export interface OrderSchedule {
  id: string | null;
  enabled: boolean;
  owner_id: string | null;
  category_id: string | null;
  title: string | null;
  note: string | null;
  weekdays: number[]; // ISO: 1=T2 … 7=CN
  create_time: string | null; // "HH:MM:SS"
  deadline_time: string | null;
  runner_count: number;
  last_run_on: string | null;
  panchat_ready: boolean;
}

export interface OrderSchedulePayload {
  enabled: boolean;
  owner_id: string | null;
  category_id: string | null;
  title: string;
  note?: string;
  weekdays: number[];
  create_time: string; // "HH:MM"
  deadline_time: string;
  runner_count?: number;
}

export interface ExternalPurchaseEater {
  user_id: string;
  name: string | null;
  amount: string;
}

export interface ExternalPurchase {
  id: string;
  description: string;
  total_amount: string;
  purchase_date: string;
  created_by_id: string | null;
  inserted_at?: string;
  eaters: ExternalPurchaseEater[];
}

export interface ExternalPurchasePayload {
  description: string;
  total_amount: string;
  purchase_date: string;
  shares: { user_id: string; amount: string }[];
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
  login: (username: string, password: string) =>
    request<{ token: string; user: User }>("/login", {
      method: "POST",
      body: JSON.stringify({ username, password }),
    }),

  me: () => request<{ user: User }>("/me"),

  // Người dùng tự cập nhật hồ sơ
  updateProfile: (name: string) =>
    request<{ user: User }>("/profile", {
      method: "PUT",
      body: JSON.stringify({ name }),
    }),
  changePassword: (current_password: string, new_password: string) =>
    request<{ ok: boolean; message: string }>("/password", {
      method: "PUT",
      body: JSON.stringify({ current_password, new_password }),
    }),

  // ---- User ----
  menu: () => request<{ data: MenuItem[] }>("/menu"),
  myOrders: () => request<{ data: Order[] }>("/orders"),
  cancelOrder: (id: string) =>
    request<{ data: Order }>(`/orders/${id}`, { method: "DELETE" }),
  balance: () =>
    request<{ balance: string; user_id: string; name: string }>("/fund/balance"),
  myTransactions: () => request<{ data: FundTransaction[] }>("/fund/transactions"),
  // Tình trạng nợ (gốc + lãi) của chính user
  myInterest: () => request<{ data: InterestStatus }>("/interest/me"),

  // Đợt đặt nhóm (user)
  openGroupOrders: () => request<{ data: GroupOrder[] }>("/group_orders"),
  groupOrder: (id: string) =>
    request<{ data: GroupOrderDetail }>(`/group_orders/${id}`),
  orderInGroup: (
    id: string,
    payload: {
      note?: string;
      items: { menu_item_id: string; quantity: number; note?: string }[];
    }
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
      runner_count?: number;
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
    updateOrder: (
      id: string,
      payload: {
        note?: string;
        items: { menu_item_id: string; quantity: number; note?: string }[];
      }
    ) =>
      request<{ data: Order }>(`/admin/orders/${id}`, {
        method: "PUT",
        body: JSON.stringify(payload),
      }),
    closeGroupOrder: (id: string) =>
      request<{
        data: {
          confirmed: number;
          group_order: GroupOrder;
          runners: { id: string; name: string }[];
        };
        panchat: { sent: boolean; error?: string };
        runners_panchat: { sent?: boolean; skipped?: boolean; error?: string };
      }>(`/admin/group_orders/${id}/close`, { method: "POST" }),
    sendGroupOrderToSeller: (id: string) =>
      request<{ data: { sent: boolean; error?: string } }>(
        `/admin/group_orders/${id}/send_to_seller`,
        { method: "POST" }
      ),

    stats: (date?: string) =>
      request<{ data: Stats }>(`/admin/stats${date ? `?date=${date}` : ""}`),
    statsPeriod: (from: string, to: string) =>
      request<{ data: PeriodStats }>(`/admin/stats/period?from=${from}&to=${to}`),
    statsRevenue: (from: string, to: string, categoryId?: string) =>
      request<{ data: DailyRevenue[] }>(
        `/admin/stats/revenue?from=${from}&to=${to}${categoryId ? `&category_id=${categoryId}` : ""}`
      ),
    statsByCategory: (from: string, to: string) =>
      request<{ data: CategoryRevenue[] }>(`/admin/stats/by_category?from=${from}&to=${to}`),
    fundTransactions: (
      page = 1,
      filters: { type?: string; user_id?: string; from?: string; to?: string } = {},
      pageSize = 20
    ) => {
      const qs = new URLSearchParams({ page: String(page), page_size: String(pageSize) });
      if (filters.type) qs.set("type", filters.type);
      if (filters.user_id) qs.set("user_id", filters.user_id);
      if (filters.from) qs.set("from", filters.from);
      if (filters.to) qs.set("to", filters.to);
      return request<Paginated<FundTransaction>>(`/admin/fund/transactions?${qs}`);
    },
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

    // Quỹ lãi trên số dư âm (issue #12)
    interestFund: () => request<{ data: InterestFund }>("/admin/interest/fund"),
    interestCharges: (page = 1, user_id?: string, pageSize = 20) => {
      const qs = new URLSearchParams({ page: String(page), page_size: String(pageSize) });
      if (user_id) qs.set("user_id", user_id);
      return request<Paginated<InterestCharge>>(`/admin/interest/charges?${qs}`);
    },
    runInterest: () =>
      request<{ data: { count: number; total: string }; fund: InterestFund }>(
        "/admin/interest/run",
        { method: "POST" }
      ),

    // Cấu hình Panchat token
    getPanchatSettings: () =>
      request<{ data: PanchatSettings }>("/admin/settings/panchat"),
    savePanchatToken: (panchat_token: string) =>
      request<{ data: PanchatSettings }>("/admin/settings/panchat", {
        method: "PUT",
        body: JSON.stringify({ panchat_token }),
      }),

    // Lịch hẹn tự động mở đợt đặt món hằng ngày (dùng chung)
    getOrderSchedule: () =>
      request<{ data: OrderSchedule }>("/admin/order_schedule"),
    saveOrderSchedule: (payload: OrderSchedulePayload) =>
      request<{ data: OrderSchedule }>("/admin/order_schedule", {
        method: "PUT",
        body: JSON.stringify(payload),
      }),

    // Mua đồ ăn ngoài menu — chia tiền cho người ăn
    listExternalPurchases: () =>
      request<{ data: ExternalPurchase[] }>("/admin/external_purchases"),
    createExternalPurchase: (payload: ExternalPurchasePayload) =>
      request<{ data: ExternalPurchase }>("/admin/external_purchases", {
        method: "POST",
        body: JSON.stringify(payload),
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
