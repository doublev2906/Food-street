defmodule FoodStreet.Repo.Migrations.AddRunnerCountToGroupOrders do
  use Ecto.Migration

  def change do
    alter table(:group_orders) do
      # Số người sẽ được bốc ngẫu nhiên đi lấy đồ khi chốt đợt (0 = không bốc).
      add :runner_count, :integer, null: false, default: 0
    end
  end
end
