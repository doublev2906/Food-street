defmodule FoodStreet.Repo.Migrations.AddRunnerCountToDailyOrderSchedules do
  use Ecto.Migration

  def change do
    alter table(:daily_order_schedules) do
      # Số người bốc ngẫu nhiên đi lấy đồ cho đợt tạo tự động (0 = không bốc).
      add :runner_count, :integer, null: false, default: 0
    end
  end
end
