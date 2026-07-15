defmodule FoodStreet.Repo.Migrations.CreatePancakeWebhookEvents do
  use Ecto.Migration

  # Chống xử lý trùng webhook Pancake: mỗi tin (message_id) chỉ relay 1 lần.
  # Insert trước khi relay; đụng unique index -> đã xử lý -> bỏ qua.
  def change do
    create table(:pancake_webhook_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :message_id, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:pancake_webhook_events, [:message_id])
  end
end
