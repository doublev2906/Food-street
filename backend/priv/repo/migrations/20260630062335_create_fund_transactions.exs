defmodule FoodStreet.Repo.Migrations.CreateFundTransactions do
  use Ecto.Migration

  def change do
    create table(:fund_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :amount, :decimal, null: false, precision: 12, scale: 2
      add :type, :string, null: false
      add :description, :string
      add :balance_after, :decimal, null: false, precision: 12, scale: 2
      add :order_id, references(:orders, type: :binary_id, on_delete: :nilify_all)
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:fund_transactions, [:user_id])
    create index(:fund_transactions, [:type])
    create index(:fund_transactions, [:order_id])
  end
end
