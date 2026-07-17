defmodule FoodStreet.Repo.Migrations.AddSellerPaidToGroupOrders do
  use Ecto.Migration

  def change do
    alter table(:group_orders) do
      # Thời điểm admin tick tay "đã thanh toán cho người bán" — null = chưa trả (issue #10)
      add :seller_paid_at, :utc_datetime
    end
  end
end
