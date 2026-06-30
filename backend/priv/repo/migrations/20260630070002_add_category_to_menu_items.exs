defmodule FoodStreet.Repo.Migrations.AddCategoryToMenuItems do
  use Ecto.Migration

  def change do
    alter table(:menu_items) do
      add :category_id, references(:categories, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:menu_items, [:category_id])
  end
end
