defmodule FoodStreet.Repo.Migrations.AddRunnerUserIdsToGroupOrders do
  use Ecto.Migration

  def change do
    alter table(:group_orders) do
      # Danh sách user được bốc đi lấy đồ, lưu snapshot lúc chốt để tái dùng khi
      # nhà bán báo "xuống lấy hàng" (ping đúng nhóm này). Không FK — user xoá tự
      # rớt khỏi list khi load. Thứ tự = thứ tự bốc.
      add :runner_user_ids, {:array, :binary_id}, null: false, default: []
    end
  end
end
