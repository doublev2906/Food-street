// Tiện ích hiển thị thực đơn cho khu vực người dùng.
// - categoryIcon: icon theo TÊN danh mục (client-side, §6.3 — không cần field icon ở BE)
// - menuGroup: nhóm hiển thị trong 1 danh mục (§6.2 hướng A — suy ra từ tên món,
//   KHÔNG đổi data model; mỗi đợt vẫn chỉ gắn 1 danh mục)
// - FoodThumb: ảnh món có fallback placeholder khi thiếu ảnh (không vỡ layout)
import { useState } from "react";
import type { MenuItem } from "./api";

export function categoryIcon(name?: string | null): string {
  const n = (name || "").toLowerCase();
  if (n.includes("sáng")) return "☀️";
  if (n.includes("trưa")) return "🍚";
  if (n.includes("tối") || n.includes("chiều")) return "🌙";
  if (
    n.includes("mixue") ||
    n.includes("kem") ||
    n.includes("trà") ||
    n.includes("cà phê") ||
    n.includes("cafe") ||
    n.includes("uống")
  )
    return "🧋";
  return "🍽️";
}

export type MenuGroup =
  | "Bánh mì"
  | "Bánh ngọt"
  | "Đồ ăn"
  | "Đồ uống"
  | "Kem"
  | "Topping"
  | "Khác";

// Thứ tự tab hiển thị (chỉ tab có món mới hiện).
export const GROUP_ORDER: MenuGroup[] = [
  "Bánh mì",
  "Bánh ngọt",
  "Đồ ăn",
  "Đồ uống",
  "Kem",
  "Topping",
  "Khác",
];

export function menuGroup(item: MenuItem): MenuGroup {
  const n = item.name.toLowerCase();
  if (n.startsWith("topping")) return "Topping";
  if (n.includes("bánh mì") || n.includes("sandwich")) return "Bánh mì";
  // Đồ uống: check trước "kem" để "Cafe Latte Kem tươi" không bị nhận nhầm là Kem
  if (
    n.includes("trà") ||
    n.includes("cà phê") ||
    n.includes("cafe") ||
    n.includes("latte") ||
    n.includes("mocha") ||
    n.includes("nước") ||
    n.includes("sữa đậu") ||
    n.includes("sữa thạch") ||
    n.includes("cam lộ") ||
    n.includes("chanh")
  )
    return "Đồ uống";
  if (n.includes("kem") || n.includes("sundae") || n.includes("ốc quế")) return "Kem";
  if (n.includes("xôi")) return "Đồ ăn";
  if (n.includes("bánh") || n.includes("chè")) return "Bánh ngọt";
  if (
    n.includes("khoai") ||
    n.includes("ngô") ||
    n.includes("sắn") ||
    n.includes("giò") ||
    n.includes("cơm")
  )
    return "Đồ ăn";
  return "Khác";
}

const GROUP_EMOJI: Record<MenuGroup, string> = {
  "Bánh mì": "🥖",
  "Bánh ngọt": "🍰",
  "Đồ ăn": "🍙",
  "Đồ uống": "🥤",
  Kem: "🍨",
  Topping: "🧋",
  Khác: "🍽️",
};

export function FoodThumb({
  item,
  size = 72,
  radius = 10,
}: {
  item: MenuItem;
  size?: number;
  radius?: number;
}) {
  const [broken, setBroken] = useState(false);
  const style = { width: size, height: size, borderRadius: radius } as const;

  if (item.image_url && !broken) {
    return (
      <img
        className="food-thumb"
        src={item.image_url}
        alt={item.name}
        style={style}
        loading="lazy"
        onError={() => setBroken(true)}
      />
    );
  }
  return (
    <div className="food-thumb placeholder" style={{ ...style, fontSize: size * 0.44 }}>
      {GROUP_EMOJI[menuGroup(item)]}
    </div>
  );
}
