defmodule FoodStreet.Repo.Migrations.CreateOrderItems do
  use Ecto.Migration

  def change do
    create table(:order_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :menu_item_id, references(:menu_items, type: :binary_id, on_delete: :nilify_all)
      add :item_name, :string, null: false
      add :quantity, :integer, null: false, default: 1
      add :unit_price, :decimal, null: false, precision: 12, scale: 2
      add :subtotal, :decimal, null: false, precision: 12, scale: 2

      timestamps(type: :utc_datetime)
    end

    create index(:order_items, [:order_id])
    create index(:order_items, [:menu_item_id])
  end
end
