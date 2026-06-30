defmodule FoodStreet.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :order_date, :date, null: false
      add :status, :string, null: false, default: "pending"
      add :total_amount, :decimal, null: false, default: 0, precision: 12, scale: 2
      add :note, :string
      add :confirmed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:orders, [:user_id])
    create index(:orders, [:order_date])
    create index(:orders, [:status])
  end
end
