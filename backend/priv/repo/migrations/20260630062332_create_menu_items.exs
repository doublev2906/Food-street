defmodule FoodStreet.Repo.Migrations.CreateMenuItems do
  use Ecto.Migration

  def change do
    create table(:menu_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :price, :decimal, null: false, precision: 12, scale: 2
      add :available, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end
  end
end
