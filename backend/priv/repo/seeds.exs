# Seed dữ liệu mẫu cho hệ thống đặt đồ ăn sáng.
#
#     mix run priv/repo/seeds.exs
#
# Idempotent: chạy nhiều lần không tạo trùng (dựa theo email / tên / tiêu đề).

import Ecto.Query
alias FoodStreet.{Repo, Accounts, Catalog, Fund, Ordering}
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

users =
  for {name, username, email} <- [
        {"Nguyễn Văn An", "an", "an@foodstreet.vn"},
        {"Trần Thị Bình", "binh", "binh@foodstreet.vn"},
        {"Lê Văn Cường", "cuong", "cuong@foodstreet.vn"}
      ] do
    Seeds.upsert_user(%{
      "name" => name,
      "username" => username,
      "email" => email,
      "password" => "user123",
      "role" => "user"
    })
  end

IO.puts("== Nạp quỹ ban đầu cho users ==")

for user <- users do
  if Decimal.equal?(user.balance, Decimal.new(0)) do
    {:ok, _} = Fund.deposit(user, "200000", admin, "Nạp quỹ khởi tạo")
    IO.puts("  + nạp 200.000đ cho #{user.name}")
  end
end

IO.puts("== Seeding danh mục ==")

an_sang = Seeds.upsert_category("Ăn sáng", "Đồ ăn sáng")
tra_chieu = Seeds.upsert_category("Trà chiều", "Đồ uống, trà chiều")
mixue = Seeds.upsert_category("Mixue", "Kem & trà sữa Mixue")
an_vat = Seeds.upsert_category("Ăn vặt", "Đồ ăn vặt")

IO.puts("== Seeding menu ==")

[
  %{"name" => "Phở bò", "description" => "Phở bò tái nạm", "price" => "40000", "category_id" => an_sang.id},
  %{"name" => "Bún chả", "description" => "Bún chả Hà Nội", "price" => "35000", "category_id" => an_sang.id},
  %{"name" => "Bánh mì trứng", "description" => "Bánh mì ốp la pa tê", "price" => "20000", "category_id" => an_sang.id},
  %{"name" => "Xôi gà", "description" => "Xôi xéo gà xé", "price" => "25000", "category_id" => an_sang.id},
  %{"name" => "Cháo lòng", "description" => "Cháo lòng dồi", "price" => "30000", "category_id" => an_sang.id},
  %{"name" => "Cà phê sữa", "description" => "Cà phê sữa đá", "price" => "15000", "category_id" => tra_chieu.id},
  %{"name" => "Trà đá", "description" => "Trà đá", "price" => "3000", "category_id" => tra_chieu.id},
  %{"name" => "Trà tắc", "description" => "Trà tắc mật ong", "price" => "18000", "category_id" => tra_chieu.id},
  %{"name" => "Kem ốc quế Mixue", "description" => "Kem tươi ốc quế", "price" => "10000", "category_id" => mixue.id},
  %{"name" => "Trà sữa trân châu Mixue", "description" => "Trà sữa trân châu đường đen", "price" => "25000", "category_id" => mixue.id},
  %{"name" => "Hồng trà Mixue", "description" => "Hồng trà mật ong", "price" => "15000", "category_id" => mixue.id},
  %{"name" => "Hướng dương", "description" => "Hạt hướng dương", "price" => "12000", "category_id" => an_vat.id},
  %{"name" => "Bánh tráng trộn", "description" => "Bánh tráng trộn", "price" => "20000", "category_id" => an_vat.id}
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
IO.puts("   Admin:  admin@foodstreet.vn / admin123")
IO.puts("   User:   an@foodstreet.vn / user123 (và binh@, cuong@)")
