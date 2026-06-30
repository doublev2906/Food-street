# Seed dữ liệu mẫu cho hệ thống đặt đồ ăn sáng.
#
#     mix run priv/repo/seeds.exs
#
# Idempotent: chạy nhiều lần không tạo trùng (dựa theo email / tên món).

alias FoodStreet.{Repo, Accounts, Catalog, Fund}

defmodule Seeds do
  def upsert_user(attrs) do
    case Accounts.get_user_by_email(attrs["email"]) do
      nil ->
        {:ok, user} = Accounts.create_user(attrs)
        IO.puts("  + user #{user.email} (#{user.role})")
        user

      user ->
        IO.puts("  = user #{user.email} đã tồn tại")
        user
    end
  end

  def upsert_menu(attrs) do
    import Ecto.Query

    case Repo.one(from m in FoodStreet.Catalog.MenuItem, where: m.name == ^attrs["name"]) do
      nil ->
        {:ok, item} = Catalog.create_menu_item(attrs)
        IO.puts("  + món #{item.name} - #{item.price}")
        item

      item ->
        item
    end
  end
end

IO.puts("== Seeding users ==")

admin =
  Seeds.upsert_user(%{
    "name" => "Quản trị viên",
    "email" => "admin@foodstreet.vn",
    "password" => "admin123",
    "role" => "admin"
  })

users =
  for {name, email} <- [
        {"Nguyễn Văn An", "an@foodstreet.vn"},
        {"Trần Thị Bình", "binh@foodstreet.vn"},
        {"Lê Văn Cường", "cuong@foodstreet.vn"}
      ] do
    Seeds.upsert_user(%{
      "name" => name,
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

IO.puts("== Seeding menu ==")

[
  %{"name" => "Phở bò", "description" => "Phở bò tái nạm", "price" => "40000"},
  %{"name" => "Bún chả", "description" => "Bún chả Hà Nội", "price" => "35000"},
  %{"name" => "Bánh mì trứng", "description" => "Bánh mì ốp la pa tê", "price" => "20000"},
  %{"name" => "Xôi gà", "description" => "Xôi xéo gà xé", "price" => "25000"},
  %{"name" => "Cháo lòng", "description" => "Cháo lòng dồi", "price" => "30000"},
  %{"name" => "Cà phê sữa", "description" => "Cà phê sữa đá", "price" => "15000"},
  %{"name" => "Trà đá", "description" => "Trà đá", "price" => "3000", "available" => true}
]
|> Enum.each(&Seeds.upsert_menu/1)

IO.puts("\n✅ Seed xong.")
IO.puts("   Admin:  admin@foodstreet.vn / admin123")
IO.puts("   User:   an@foodstreet.vn / user123 (và binh@, cuong@)")
