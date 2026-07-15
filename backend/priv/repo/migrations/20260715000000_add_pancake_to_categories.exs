defmodule FoodStreet.Repo.Migrations.AddPancakeToCategories do
  use Ecto.Migration

  # Cấu hình Pancake Page (pages.fm) của nhà bán, gắn theo từng danh mục
  # ("mỗi category = 1 nhà bán"). Dùng để gửi đơn gộp vào inbox nhà bán.
  def change do
    alter table(:categories) do
      add :pancake_page_id, :string
      add :pancake_conversation_id, :string
      add :pancake_page_access_token, :string
    end

    # Map ngược từ webhook (conversation_id) về category khi nhà bán trả lời.
    create index(:categories, [:pancake_conversation_id])
  end
end
