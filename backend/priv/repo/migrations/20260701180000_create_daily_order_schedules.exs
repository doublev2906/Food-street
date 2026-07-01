defmodule FoodStreet.Repo.Migrations.CreateDailyOrderSchedules do
  @moduledoc """
  Lịch hẹn tự động mở đợt đặt món hằng ngày (1 lịch dùng chung toàn hệ thống).

  Tới giờ đã cấu hình, hệ thống tự tạo 1 đợt đặt nhóm đứng tên `owner` và gửi lời
  mời Panchat bằng token của owner. `last_run_on` chống tạo trùng trong ngày.
  """
  use Ecto.Migration

  def change do
    create table(:daily_order_schedules, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :enabled, :boolean, default: false, null: false
      add :owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :category_id, references(:categories, type: :binary_id, on_delete: :nilify_all)

      add :title, :string
      add :note, :string
      # ISO day_of_week: 1 = Thứ 2 … 7 = Chủ nhật
      add :weekdays, {:array, :integer}, default: [], null: false
      add :create_time, :time
      add :deadline_time, :time
      add :last_run_on, :date

      timestamps(type: :utc_datetime)
    end

    create index(:daily_order_schedules, [:owner_id])
    create index(:daily_order_schedules, [:category_id])
  end
end
