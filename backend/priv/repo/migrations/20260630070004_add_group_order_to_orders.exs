defmodule FoodStreet.Repo.Migrations.AddGroupOrderToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :group_order_id, references(:group_orders, type: :binary_id, on_delete: :delete_all)
    end

    create index(:orders, [:group_order_id])
    # Mỗi user chỉ có 1 đơn trong 1 đợt đặt nhóm.
    create unique_index(:orders, [:group_order_id, :user_id],
             name: :orders_group_order_user_index
           )
  end
end
