defmodule FoodStreet.Repo.Migrations.CreateMenuItemSizes do
  @moduledoc """
  Cho phép mỗi món có nhiều size, mỗi size 1 giá riêng (vd bánh mì Nhỏ/Lớn).
  Món không có size vẫn dùng `menu_items.price` như cũ (backward-compatible).

  `order_items` được bổ sung snapshot size (`size_name`) và `menu_item_size_id`
  (để FE nạp lại đúng size khi mở sửa đơn pending). FK dùng `nilify_all` nên xóa
  size không làm hỏng đơn đã đặt.
  """
  use Ecto.Migration

  def change do
    create table(:menu_item_sizes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :menu_item_id,
          references(:menu_items, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :price, :decimal, null: false, precision: 12, scale: 2
      add :sort_order, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:menu_item_sizes, [:menu_item_id])

    alter table(:order_items) do
      add :size_name, :string

      add :menu_item_size_id,
          references(:menu_item_sizes, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:order_items, [:menu_item_size_id])
  end
end
