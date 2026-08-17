defmodule FoodStreet.Repo.Migrations.SeedBanhMiSizes do
  @moduledoc """
  Chuyển 4 món "Bánh mì Sài Gòn" đang để khoảng giá trong `description` (vd 30-40k)
  sang size thật (Nhỏ/Lớn). Sau khi có size, xóa text khoảng giá ở `description`.

  Forward-only, idempotent theo (menu_item_id, name) size. `down` xóa các size này
  (order_items dùng nilify_all nên không hỏng đơn cũ) và không khôi phục description.
  """
  use Ecto.Migration

  # {tên món, [{tên size, giá}, ...]}
  @data [
    {"Bánh mì Sài Gòn đặc biệt", [{"Nhỏ", 30_000}, {"Lớn", 40_000}]},
    {"Bánh mì Sài Gòn", [{"Nhỏ", 20_000}, {"Lớn", 25_000}]},
    {"Bánh mì chả cá nóng", [{"Nhỏ", 25_000}, {"Lớn", 30_000}]},
    {"Bánh mì nem nướng", [{"Nhỏ", 20_000}, {"Lớn", 30_000}]}
  ]

  def up do
    for {item_name, sizes} <- @data do
      sizes
      |> Enum.with_index()
      |> Enum.each(fn {{size_name, price}, idx} ->
        execute(fn ->
          repo().query!(
            """
            INSERT INTO menu_item_sizes (id, menu_item_id, name, price, sort_order, inserted_at, updated_at)
            SELECT gen_random_uuid(), m.id, $1::varchar, $2, $3, now(), now()
            FROM menu_items m
            WHERE m.name = $4::varchar
              AND NOT EXISTS (
                SELECT 1 FROM menu_item_sizes s
                WHERE s.menu_item_id = m.id AND s.name = $1::varchar
              )
            """,
            [size_name, price, idx, item_name]
          )
        end)
      end)

      # Bỏ text khoảng giá — thông tin size giờ nằm ở menu_item_sizes.
      execute(fn ->
        repo().query!("UPDATE menu_items SET description = NULL WHERE name = $1", [item_name])
      end)
    end
  end

  def down do
    names = for {n, _} <- @data, do: n

    execute(fn ->
      repo().query!(
        """
        DELETE FROM menu_item_sizes s
        USING menu_items m
        WHERE s.menu_item_id = m.id AND m.name = ANY($1)
        """,
        [names]
      )
    end)
  end
end
