defmodule FoodStreet.Repo.Migrations.AddBanhMiSaiGonCategory do
  @moduledoc """
  Thêm danh mục "Bánh mì Sài Gòn" cùng toàn bộ món trong menu của nhà bán
  (theo bảng menu "Mang hương vị đến ngôi nhà bạn" - Hotline 0971 804 339).

  Forward-only, idempotent:
    - Danh mục dựa vào unique index trên `categories.name` (ON CONFLICT DO NOTHING).
    - Món dựa vào tên (NOT EXISTS), nên chạy lại không tạo trùng.

  Với các món có KHOẢNG GIÁ (vd 30-40k), `price` lưu mức thấp nhất làm giá gốc,
  còn khoảng giá hiển thị được ghi vào `description` để không mất thông tin.
  """
  use Ecto.Migration

  @category_name "Bánh mì Sài Gòn"

  # {tên món, giá gốc (VND), description/khoảng giá | nil}
  @items [
    {"Bánh mì Sài Gòn đặc biệt", 30_000, "30.000đ - 40.000đ"},
    {"Bánh mì Sài Gòn", 20_000, "20.000đ - 25.000đ"},
    {"Hamburger bò", 20_000, nil},
    {"Hamburger bò trứng", 25_000, nil},
    {"Bánh mì chả cá nóng", 25_000, "25.000đ - 30.000đ"},
    {"Bánh mì nem nướng", 20_000, "20.000đ - 30.000đ"},
    {"Bánh mì nem nướng + trứng", 25_000, nil},
    {"Bánh mì pate + chả + trứng", 25_000, nil},
    {"Bánh mì pate trứng", 20_000, nil},
    {"Bánh mì xúc xích", 20_000, nil},
    {"Bánh mì xúc xích + trứng", 25_000, nil},
    {"Bánh mì trứng bò khô", 25_000, nil},
    {"Bánh mì xúc xích bò khô", 25_000, nil},
    {"Bánh mì Sài Gòn bò khô", 30_000, nil}
  ]

  def up do
    # 1. Tạo danh mục (không đè nếu đã tồn tại)
    execute(fn ->
      repo().query!(
        """
        INSERT INTO categories (id, name, description, active, inserted_at, updated_at)
        VALUES (gen_random_uuid(), $1, $2, true, now(), now())
        ON CONFLICT (name) DO NOTHING
        """,
        [@category_name, "Bánh mì Sài Gòn - Mang hương vị đến ngôi nhà bạn"]
      )
    end)

    # 2. Thêm từng món, gắn vào danh mục; bỏ qua nếu đã có món cùng tên
    for {name, price, desc} <- @items do
      execute(fn ->
        repo().query!(
          """
          INSERT INTO menu_items (id, name, description, price, available, category_id, inserted_at, updated_at)
          SELECT gen_random_uuid(), $1::varchar, $2, $3, true, c.id, now(), now()
          FROM categories c
          WHERE c.name = $4
            AND NOT EXISTS (SELECT 1 FROM menu_items m WHERE m.name = $1::varchar)
          """,
          [name, desc, price, @category_name]
        )
      end)
    end
  end

  def down do
    names = for {n, _, _} <- @items, do: n

    # Xóa món trước (order_items có on_delete: :nilify_all nên an toàn)
    execute(fn ->
      repo().query!("DELETE FROM menu_items WHERE name = ANY($1)", [names])
    end)

    # Rồi xóa danh mục (chỉ khi không còn món nào trỏ vào)
    execute(fn ->
      repo().query!(
        """
        DELETE FROM categories c
        WHERE c.name = $1
          AND NOT EXISTS (SELECT 1 FROM menu_items m WHERE m.category_id = c.id)
        """,
        [@category_name]
      )
    end)
  end
end
