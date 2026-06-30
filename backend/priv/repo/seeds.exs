# Seed dữ liệu mẫu cho hệ thống đặt đồ ăn sáng.
#
#     mix run priv/repo/seeds.exs
#
# Idempotent: chạy nhiều lần không tạo trùng (dựa theo email / tên / tiêu đề).

import Ecto.Query
alias FoodStreet.{Repo, Accounts, Catalog, Ordering}
alias FoodStreet.Catalog.{MenuItem, Category}
alias FoodStreet.Ordering.GroupOrder

defmodule Seeds do
  def upsert_user(attrs) do
    case Accounts.get_user_by_email(attrs["email"]) do
      nil ->
        {:ok, user} = Accounts.create_user(attrs)
        IO.puts("  + user #{user.email} (#{user.role})")
        user

      user ->
        user
    end
  end

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

  def upsert_menu(attrs) do
    case Repo.one(from m in MenuItem, where: m.name == ^attrs["name"]) do
      nil ->
        {:ok, item} = Catalog.create_menu_item(attrs)
        IO.puts("  + món #{item.name} - #{item.price}")
        item

      item ->
        # cập nhật category nếu cần
        if attrs["category_id"] && item.category_id != attrs["category_id"] do
          {:ok, item} = Catalog.update_menu_item(item, %{"category_id" => attrs["category_id"]})
          item
        else
          item
        end
    end
  end
end

IO.puts("== Seeding users ==")

admin =
  Seeds.upsert_user(%{
    "name" => "Quản trị viên",
    "username" => "admin",
    "email" => "admin@foodstreet.vn",
    "password" => "admin123",
    "role" => "admin"
  })

# Thành viên channel "Pancake Food Street" (workspace 4 / channel 11813).
users =
  for {name, username, role} <- [
        {"Phan Định - nF", "phan.dinh", "user"},
        {"Quyết Cam", "quyet.cam", "user"},
        {"Quân Pancake", "quan.pancake", "user"},
        {"Huy Bùi", "huy.bui", "user"},
        {"Nguyễn Bá Duy", "nguyen.ba.duy", "user"},
        {"Đức Duy", "duc.duy", "user"},
        {"Vũ Nguyễn Văn", "vu.nguyen.van", "admin"},
        {"An Luu", "an.luu", "user"},
        {"truonght", "truonght", "user"},
        {"Trần Xuân Phong", "tran.xuan.phong", "user"},
        {"Tuấn Lee", "tuan.lee", "admin"},
        {"Đình Hiếu", "dinh.hieu", "admin"},
        {"ThuyThuy", "thuythuy", "user"},
        {"Quốc Đại", "quoc.dai", "user"}
      ] do
    Seeds.upsert_user(%{
      "name" => name,
      "username" => username,
      "email" => "#{username}@foodstreet.vn",
      "password" => if(role == "admin", do: "admin123", else: "user123"),
      "role" => role
    })
  end

IO.puts("== Đã tạo #{length(users)} user — quỹ khởi tạo 0đ (admin nạp sau) ==")

IO.puts("== Seeding danh mục ==")

an_sang = Seeds.upsert_category("Ăn sáng", "Đồ ăn sáng")
mixue = Seeds.upsert_category("Mixue", "Kem & trà sữa Mixue")

IO.puts("== Seeding menu ==")

[
  %{"name" => "Xôi xéo", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Xôi lạc", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Xôi ngô", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Xôi trứng ruốc", "price" => "30000", "category_id" => an_sang.id},
  %{"name" => "Xôi chả ruốc", "price" => "30000", "category_id" => an_sang.id},
  %{"name" => "Xôi trứng kho thịt chả", "price" => "35000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì trứng", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì pate", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì xá xíu", "price" => "20000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì pate ruốc", "price" => "20000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì trứng ruốc", "price" => "25000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì pate xá xíu", "price" => "25000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì full topping", "price" => "30000", "category_id" => an_sang.id},
  %{"name" => "Sandwich", "price" => "20000", "category_id" => an_sang.id},
  %{"name" => "Bánh dày giò", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Bánh dày", "price" => "20000", "category_id" => an_sang.id},
  %{"name" => "Bánh giò", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Bánh khoai", "price" => "12000", "category_id" => an_sang.id},
  %{"name" => "Bánh rán", "price" => "20000", "category_id" => an_sang.id},
  %{"name" => "Bánh trôi", "price" => "12000", "category_id" => an_sang.id},
  %{"name" => "Bánh tẻ", "price" => "8000", "category_id" => an_sang.id},
  %{"name" => "Xôi chè", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Khoai luộc", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Sắn hấp dừa", "price" => "20000", "category_id" => an_sang.id},
  %{"name" => "Ngô luộc", "price" => "10000", "category_id" => an_sang.id},
  %{"name" => "Sữa đậu", "price" => "10000", "category_id" => an_sang.id},
  %{"name" => "Nước đậu đen", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Cơm cuộn", "price" => "15000", "category_id" => an_sang.id},
  %{"name" => "Xôi chả thịt kho", "price" => "30000", "category_id" => an_sang.id},
  %{"name" => "Giò cây", "price" => "12000", "category_id" => an_sang.id},
  # Mixue — Dòng kem
  %{"name" => "Kem ốc quế", "price" => "10000", "category_id" => mixue.id},
  %{"name" => "Lucky sundae O-coco", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Super Sundae trân châu đường đen", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Lucky sundae dâu tây", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Super Sundae kiwi lô hội", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Super Sundae đào hồng", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Super Sundae xoài", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Super Sundae đào vàng", "price" => "25000", "category_id" => mixue.id},
  # Mixue — Trà hoa quả
  %{"name" => "Nước chanh tươi lạnh", "price" => "15000", "category_id" => mixue.id},
  %{"name" => "Trà đào dâu tây", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Trà xoài chanh leo", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Chanh leo bách hương", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Trà xanh chanh", "price" => "15000", "category_id" => mixue.id},
  %{"name" => "Trà xanh kiwi", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Trà đào bigsize", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Trà xanh hoa đào", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Dương chi cam lộ", "price" => "28000", "category_id" => mixue.id},
  # Mixue — Trà sữa
  %{"name" => "Trà sữa trân châu đường đen", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Trà sữa Caramel", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Trà sữa trân châu", "price" => "30000", "category_id" => mixue.id},
  %{"name" => "Sữa thạch Kiwi Kiwi", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Sữa thạch Dâu tây", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Trà sữa 2J", "description" => "Chọn 2 topping", "price" => "30000", "category_id" => mixue.id},
  %{"name" => "Trà sữa thạch dừa", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Trà sữa đường đen", "price" => "30000", "category_id" => mixue.id},
  %{"name" => "Trà sữa O-coco", "price" => "28000", "category_id" => mixue.id},
  # Mixue — Cà phê
  %{"name" => "Latte đường đen", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Mocha", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Latte", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Cafe Latte Kem tươi", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Cafe Mocha Kem tươi", "price" => "22000", "category_id" => mixue.id},
  %{"name" => "Cafe Latte Caramel Kem tươi", "price" => "25000", "category_id" => mixue.id},
  # Mixue — Đặc biệt (banner)
  %{"name" => "Trà chanh lô hội", "price" => "17000", "category_id" => mixue.id},
  %{"name" => "Trà chanh dâu tây", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Trà sữa bá vương", "price" => "30000", "category_id" => mixue.id},
  %{"name" => "Hồng trà Latte", "price" => "25000", "category_id" => mixue.id},
  # Mixue — Topping (bán như món thường, +3.000đ)
  %{"name" => "Topping Trân châu", "price" => "3000", "category_id" => mixue.id},
  %{"name" => "Topping Thạch dừa", "price" => "3000", "category_id" => mixue.id},
  %{"name" => "Topping Vụn O-coco", "price" => "3000", "category_id" => mixue.id},
  %{"name" => "Topping Thạch đường đen", "price" => "3000", "category_id" => mixue.id},
  %{"name" => "Topping Thạch đào", "price" => "3000", "category_id" => mixue.id},
  %{"name" => "Topping Lô hội", "price" => "3000", "category_id" => mixue.id},
  %{"name" => "Topping Vụn ốc quế", "price" => "3000", "category_id" => mixue.id},
]
|> Enum.each(&Seeds.upsert_menu/1)

IO.puts("== Seeding đợt đặt nhóm mẫu ==")

today = Date.utc_today()

unless Repo.one(from g in GroupOrder, where: g.order_date == ^today and g.category_id == ^an_sang.id) do
  {:ok, go} =
    Ordering.create_group_order(
      %{
        "title" => "Ăn sáng hôm nay",
        "order_date" => Date.to_iso8601(today),
        "category_id" => an_sang.id,
        "note" => "Chốt đơn lúc 8h sáng"
      },
      admin
    )

  IO.puts("  + đợt: #{go.title} (#{go.order_date}) - danh mục Ăn sáng")
end

IO.puts("\n✅ Seed xong.")
IO.puts("   Admin:  admin@foodstreet.vn / admin123  (+ các admin khác / admin123)")
IO.puts("   User:   <username>@foodstreet.vn / user123")
