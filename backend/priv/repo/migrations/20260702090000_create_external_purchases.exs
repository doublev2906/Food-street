defmodule FoodStreet.Repo.Migrations.CreateExternalPurchases do
  @moduledoc """
  Khoản mua đồ ăn ngoài menu do admin ứng, chia tiền cho những người cùng ăn.

  Mỗi người ăn = 1 dòng `fund_transactions` type "split" (trừ số dư), liên kết về
  `external_purchases` qua `external_purchase_id` (giống cột `order_id` sẵn có).
  """
  use Ecto.Migration

  def change do
    create table(:external_purchases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :description, :string, null: false
      add :total_amount, :decimal, null: false, precision: 12, scale: 2
      add :purchase_date, :date, null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:external_purchases, [:purchase_date])

    alter table(:fund_transactions) do
      add :external_purchase_id,
          references(:external_purchases, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:fund_transactions, [:external_purchase_id])
  end
end
