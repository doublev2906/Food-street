defmodule FoodStreet.Repo.Migrations.CreateGroupOrders do
  use Ecto.Migration

  def change do
    create table(:group_orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :order_date, :date, null: false
      add :status, :string, null: false, default: "open"
      add :note, :string
      add :deadline, :utc_datetime
      add :closed_at, :utc_datetime

      add :category_id, references(:categories, type: :binary_id, on_delete: :nilify_all)
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:group_orders, [:status])
    create index(:group_orders, [:order_date])
    create index(:group_orders, [:category_id])
  end
end
