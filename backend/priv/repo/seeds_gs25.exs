# Seed / cập nhật thực đơn GS25 (CAFE25 — Coffee Beverage).
#
#     mix run priv/repo/seeds_gs25.exs
#
# Idempotent: chạy nhiều lần không tạo trùng (khớp theo tên món). Nếu món đã có,
# script cập nhật giá + mô tả + danh mục cho khớp bảng giá mới nhất.
#
# Giá lấy theo bảng menu trong ảnh. Với món nhiều size, `price` là giá size nhỏ
# nhất được in, các size còn lại ghi trong `description`.

import Ecto.Query
alias FoodStreet.{Repo, Catalog}
alias FoodStreet.Catalog.{MenuItem, Category}

defmodule GS25Seeds do
  def upsert_category(name, desc) do
    case Repo.one(from c in Category, where: c.name == ^name) do
      nil ->
        {:ok, c} = Catalog.create_category(%{"name" => name, "description" => desc})
        IO.puts("  + danh mục #{c.name}")
        c

      c ->
        c
    end
  end

  # Tạo mới nếu chưa có; nếu đã có thì cập nhật giá/mô tả/danh mục khi thay đổi.
  def upsert_menu(attrs) do
    case Repo.one(from m in MenuItem, where: m.name == ^attrs["name"]) do
      nil ->
        {:ok, item} = Catalog.create_menu_item(attrs)
        IO.puts("  + #{item.name} — #{item.price}đ")
        item

      item ->
        changes =
          %{}
          |> maybe_put("price", attrs["price"], to_string(item.price))
          |> maybe_put("description", attrs["description"], item.description)
          |> maybe_put("category_id", attrs["category_id"], item.category_id)

        if map_size(changes) > 0 do
          {:ok, item} = Catalog.update_menu_item(item, changes)
          IO.puts("  ~ cập nhật #{item.name} — #{item.price}đ")
          item
        else
          item
        end
    end
  end

  defp maybe_put(map, _key, nil, _current), do: map
  # so sánh giá bằng Decimal để "15000" == 15000.00
  defp maybe_put(map, "price" = key, value, current) do
    if Decimal.equal?(Decimal.new(value), Decimal.new(current || "0")),
      do: map,
      else: Map.put(map, key, value)
  end

  defp maybe_put(map, _key, value, current) when value == current, do: map
  defp maybe_put(map, key, value, _current), do: Map.put(map, key, value)
end

IO.puts("== GS25: danh mục ==")
gs25 = GS25Seeds.upsert_category("GS25", "Cà phê & đồ uống GS25 / CAFE25")

IO.puts("== GS25: món (giá đọc rõ từ menu) ==")

[
  # --- Cà phê pha máy (cốc GS25) ---
  %{"name" => "Cà Phê Đen", "description" => "Vietnamese Black Coffee · M 420ml", "price" => "15000"},
  %{"name" => "Cà Phê Sữa", "description" => "Vietnamese Milk Coffee · M 420ml", "price" => "20000"},

  # --- Đồ uống lạnh (cốc GS25) ---
  %{"name" => "Sữa Đậu Nành", "description" => "Soy Milk · L 650ml", "price" => "14000"},
  %{"name" => "Nestea Chanh", "description" => "Lemon Nestea · L 650ml", "price" => "15000"},
  %{"name" => "Trà Cóc Xí Muội", "description" => "Ambarella Salted Plum Tea · L 650ml", "price" => "22000"},
  %{"name" => "Trà Me Muối Ớt", "description" => "Chili Salt Tamarind Tea · L 650ml", "price" => "27000"},
  %{"name" => "Trà Tắc", "description" => "Kumquat Tea · L 10.000đ / XL 22.000đ", "price" => "10000"},
  %{"name" => "Milo", "description" => "Milo · L 650ml", "price" => "27000"},
  %{"name" => "Trà Sữa Đại Hồng Bào", "description" => "Dai Hong Pao Milk Tea · L 25.000đ / XL 30.000đ", "price" => "25000"},

  # --- Đồ uống nóng (cốc CAFE25) — giá đọc rõ ---
  %{"name" => "Milo Nóng", "description" => "Hot Milo", "price" => "19000"},
  %{"name" => "Trà Sữa Socola", "description" => "Chocolate Milk Tea · M 420ml", "price" => "25000"},

  # --- Topping ---
  %{"name" => "Trân Châu Kim Cương", "description" => "Crystal Boba (topping)", "price" => "6000"},
  %{"name" => "Thạch Quế Hoa", "description" => "Osmanthus Jelly (topping)", "price" => "10000"}
]
|> Enum.each(fn attrs ->
  attrs
  |> Map.put("category_id", gs25.id)
  |> GS25Seeds.upsert_menu()
end)

# ---------------------------------------------------------------------------
# ⚠️ CHƯA ĐỌC RÕ GIÁ TỪ ẢNH — cần xác nhận trước khi bật.
# Đây là nhóm trà nóng CAFE25 ở cột phải, giá trong ảnh không rõ. Điền "price"
# rồi bỏ comment khối dưới để nạp cùng lúc.
# ---------------------------------------------------------------------------
# [
#   %{"name" => "Trà Tắc Mật Ong", "description" => "Kumquat Honey Tea", "price" => "?"},
#   %{"name" => "Trà Gừng", "description" => "Ginger Tea", "price" => "?"},
#   %{"name" => "Trà Hoa Cúc", "description" => "Daisy Tea", "price" => "?"},
#   %{"name" => "Trà Cam Quế", "description" => "Orange Cinnamon Tea", "price" => "?"},
#   %{"name" => "Trà Sữa Hongkong", "description" => "Hongkong Milk Tea", "price" => "?"}
# ]
# |> Enum.each(fn attrs ->
#   attrs |> Map.put("category_id", gs25.id) |> GS25Seeds.upsert_menu()
# end)

IO.puts("\n✅ Xong. Danh mục GS25 đã cập nhật.")
